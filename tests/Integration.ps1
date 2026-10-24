param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [string]$TestRoot = (Join-Path $env:TEMP 'FolderOrganizer.Tests')
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $TestRoot ([guid]::NewGuid().ToString('N'))
$desktop = Join-Path $root 'Test Desktop'
$history = Join-Path $root 'History'
New-Item -ItemType Directory -Path $desktop,$history -Force | Out-Null
$script:checks = 0
function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Write-Sample([string]$Name, [string]$Content = 'sample') {
    [IO.File]::WriteAllText((Join-Path $desktop $Name), $Content)
}
function Run-Tool([string[]]$Extra = @(), [int]$ExpectedExit = 0) {
    $report = Join-Path $root (([guid]::NewGuid().ToString('N')) + '.json')
    $arguments = @('--headless','--desktop',('"' + $desktop + '"'),'--history',
        ('"' + $history + '"'),'--report',('"' + $report + '"')) + $Extra
    $process = Start-Process -FilePath $Executable -ArgumentList $arguments -PassThru -Wait
    Assert-That ($process.ExitCode -eq $ExpectedExit) ('Unexpected exit: ' + $process.ExitCode)
    return Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
}

$samples = [ordered]@{
    'photo.JPG' = 'Images'; 'notes.docx' = 'Documents'; 'manual.pdf' = 'PDFs';
    'budget.xlsx' = 'Spreadsheets'; 'talk.pptx' = 'Presentations'; 'clip.mp4' = 'Videos';
    'song.mp3' = 'Audio'; 'archive.zip' = 'Archives'; 'setup.msi' = 'Installers';
    'script.py' = 'Code'; 'drawing.psd' = 'Design Files'; 'font.ttf' = 'Fonts';
    'unknown.custom' = 'Other Files'; 'LICENSE' = 'Other Files';
    'report & notes (final).txt' = 'Documents'; 'বাংলা.txt' = 'Documents'
}
foreach ($name in $samples.Keys) { Write-Sample $name ('contents of ' + $name) }
New-Item -ItemType Directory -Path (Join-Path $desktop 'Documents'),(Join-Path $desktop 'Keep This Folder') | Out-Null
[IO.File]::WriteAllText((Join-Path $desktop 'Documents\notes.docx'), 'existing document')
[IO.File]::WriteAllText((Join-Path $desktop 'Keep This Folder\nested.txt'), 'nested')
foreach ($name in @('App.lnk','Site.url','download.crdownload','partial.part','~$draft.docx','hidden.txt','desktop.ini')) {
    Write-Sample $name
}
[IO.File]::SetAttributes((Join-Path $desktop 'hidden.txt'), [IO.FileAttributes]::Hidden)
[IO.File]::SetAttributes((Join-Path $desktop 'desktop.ini'), [IO.FileAttributes]::System)
$preview = Run-Tool -Extra @('--preview')
Assert-That ($preview.Moved -eq $samples.Count) 'Preview count is wrong.'
Assert-That (@(Get-ChildItem -LiteralPath $history).Count -eq 0) 'Preview wrote an undo journal.'
Assert-That (Test-Path -LiteralPath (Join-Path $desktop 'photo.JPG')) 'Preview moved a file.'
Assert-That (-not (Test-Path -LiteralPath (Join-Path $desktop 'Images'))) 'Preview created a folder.'

$sort = Run-Tool
Assert-That ($sort.Moved -eq $samples.Count) 'Sort count is wrong.'
foreach ($name in $samples.Keys) {
    $targetName = if ($name -eq 'notes.docx') { 'notes (2).docx' } else { $name }
    $target = Join-Path (Join-Path $desktop $samples[$name]) $targetName
    Assert-That (Test-Path -LiteralPath $target) ('Missing sorted file: ' + $name)
    Assert-That ([IO.File]::ReadAllText($target) -eq ('contents of ' + $name)) ('Changed contents: ' + $name)
}
Assert-That ([IO.File]::ReadAllText((Join-Path $desktop 'Documents\notes.docx')) -eq 'existing document') 'Overwrite occurred.'
Assert-That (Test-Path -LiteralPath (Join-Path $desktop 'Keep This Folder\nested.txt')) 'A nested file was moved.'
foreach ($name in @('App.lnk','Site.url','download.crdownload','partial.part','~$draft.docx','hidden.txt','desktop.ini')) {
    Assert-That (Test-Path -LiteralPath (Join-Path $desktop $name)) ('Excluded file moved: ' + $name)
}
$noop = Run-Tool
Assert-That ($noop.Moved -eq 0) 'Repeated sort was not a no-op.'
Assert-That (@(Get-ChildItem -LiteralPath $history -Filter '*.json').Count -eq 1) 'No-op replaced undo history.'
$undo = Run-Tool -Extra @('--undo')
Assert-That ($undo.Moved -eq $samples.Count) 'Undo count is wrong.'
foreach ($name in $samples.Keys) {
    Assert-That (Test-Path -LiteralPath (Join-Path $desktop $name)) ('Undo missed: ' + $name)
}

Write-Sample 'locked.txt'
$handle = [IO.File]::Open((Join-Path $desktop 'locked.txt'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $locked = Run-Tool -ExpectedExit 2
    Assert-That (Test-Path -LiteralPath (Join-Path $desktop 'locked.txt')) 'Locked file was moved.'
    Assert-That ($locked.Messages.Count -eq 1) 'Locked file error was not reported.'
} finally { $handle.Dispose() }
$undo = Run-Tool -Extra @('--undo')
Assert-That ($undo.Moved -eq $samples.Count) 'Undo after partial sort failed.'

$sort = Run-Tool
[IO.File]::WriteAllText((Join-Path $desktop 'Documents\report & notes (final).txt'), 'edited after sort')
Write-Sample 'notes.docx' 'new desktop document'
$undo = Run-Tool -Extra @('--undo') -ExpectedExit 2
Assert-That ($undo.Moved -eq ($samples.Count - 1)) 'Undo did not restore unaffected files.'
Assert-That ($undo.Messages.Count -eq 2) 'Undo did not report both conflicts.'
Assert-That ([IO.File]::ReadAllText((Join-Path $desktop 'notes.docx')) -eq 'new desktop document') 'Undo overwrote a new file.'
Assert-That ([IO.File]::ReadAllText((Join-Path $desktop 'Documents\report & notes (final).txt')) -eq 'edited after sort') 'Undo overwrote edits.'
Assert-That (Test-Path -LiteralPath (Join-Path $desktop 'Documents\notes (2).docx')) 'Undo lost a conflicted file.'

$linkRoot = Join-Path $root 'Junction Test Desktop'
$outside = Join-Path $root 'Outside Target'
New-Item -ItemType Directory -Path $linkRoot,$outside | Out-Null
$junction = Join-Path $linkRoot 'Images'
New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
$previousDesktop = $desktop
try {
    $desktop = $linkRoot
    Write-Sample 'keep.png'
    $linked = Run-Tool -ExpectedExit 2
    Assert-That ($linked.Moved -eq 0) 'Tool used a redirected category folder.'
    Assert-That (Test-Path -LiteralPath (Join-Path $desktop 'keep.png')) 'Linked folder test lost its source.'
    Assert-That (@(Get-ChildItem -LiteralPath $outside).Count -eq 0) 'Tool wrote outside the desktop.'
} finally {
    [IO.Directory]::Delete($junction, $false)
    $desktop = $previousDesktop
}

$selfDesktop = Join-Path $root 'Self Test Desktop'
New-Item -ItemType Directory -Path $selfDesktop | Out-Null
$copiedExecutable = Join-Path $selfDesktop 'DesktopOrganizer.exe'
Copy-Item -LiteralPath $Executable -Destination $copiedExecutable
$previousExe = $Executable
$previousDesktop = $desktop
try {
    $Executable = $copiedExecutable
    $desktop = $selfDesktop
    $self = Run-Tool
    Assert-That ($self.Moved -eq 0) 'The tool tried to sort itself.'
    Assert-That (Test-Path -LiteralPath $copiedExecutable) 'Tool moved itself.'
} finally {
    $Executable = $previousExe
    $desktop = $previousDesktop
}

$previousDesktop = $desktop
try {
    $firstFolder = Join-Path $root 'Folder A'
    $secondFolder = Join-Path $root 'Folder B'
    New-Item -ItemType Directory -Path $firstFolder,$secondFolder | Out-Null
    foreach ($folder in @($firstFolder,$secondFolder)) {
        $desktop = $folder
        Write-Sample 'separate.txt'
        $sorted = Run-Tool -Extra @('--folder',('"' + $folder + '"'))
        Assert-That ($sorted.Folder -eq $folder -and $sorted.Moved -eq 1) 'Folder option did not use the selected target.'
    }
    $desktop = $firstFolder
    $undone = Run-Tool -Extra @('--folder',('"' + $firstFolder + '"'),'--undo')
    Assert-That ($undone.Moved -eq 1) 'Undo could not find the first folder history.'
    Assert-That (Test-Path -LiteralPath (Join-Path $secondFolder 'Documents\separate.txt')) 'Undo affected another folder.'
    $desktop = $secondFolder
    $undone = Run-Tool -Extra @('--undo')
    Assert-That ($undone.Moved -eq 1) 'Undo could not find the second folder history.'
} finally { $desktop = $previousDesktop }

$summary = [ordered]@{ ChecksPassed = $script:checks; Root = $root; Executable = $Executable }
$summary | ConvertTo-Json | Tee-Object -FilePath (Join-Path $root 'verification-summary.json')
