param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [string]$TestRoot = (Join-Path $env:TEMP 'FolderOrganizer.InstallerTests')
)
$ErrorActionPreference = 'Stop'
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Folder Organizer'
if ((Test-Path -LiteralPath $registry) -or (Test-Path -LiteralPath $menu)) {
    throw 'Folder Organizer is already installed; smoke test will not change an existing installation.'
}
$root = Join-Path $TestRoot ([guid]::NewGuid().ToString('N'))
$installation = Join-Path $root 'installed'
$folder = Join-Path $root 'files'
$history = Join-Path $root 'history'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$source = Join-Path $folder 'installer-test.txt'
[IO.File]::WriteAllText($source, 'installer smoke test')
try {
    $process = Start-Process -FilePath $Installer -ArgumentList "/S /D=$installation" -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'Silent installer failed.' }
    $executable = Join-Path $installation 'Folder Organizer.exe'
    if (-not (Test-Path -LiteralPath $executable)) { throw 'Installed executable is missing.' }
    if (-not (Test-Path -LiteralPath $source)) { throw 'Installation moved a file.' }
    if (-not (Test-Path -LiteralPath $registry)) { throw 'Uninstall registration is missing.' }
    $shell = New-Object -ComObject WScript.Shell
    $expected = [ordered]@{
        'Organize Desktop.lnk' = ''; 'Organize Downloads.lnk' = '--downloads'
        'Undo Desktop Sort.lnk' = '--undo'; 'Undo Downloads Sort.lnk' = '--downloads --undo'
    }
    foreach ($name in $expected.Keys) {
        $path = Join-Path $menu $name
        if (-not (Test-Path -LiteralPath $path)) { throw ('Missing Start shortcut: ' + $name) }
        $shortcut = $shell.CreateShortcut($path)
        if ($shortcut.TargetPath -ne $executable -or $shortcut.Arguments -ne $expected[$name]) {
            throw ('Wrong shortcut target: ' + $name)
        }
    }
    $arguments = @('--folder',('"' + $folder + '"'),'--history',('"' + $history + '"'),'--headless')
    $process = Start-Process -FilePath $executable -ArgumentList $arguments -PassThru -Wait
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $folder 'Documents\installer-test.txt'))) {
        throw 'Installed app did not sort the test file.'
    }
    $process = Start-Process -FilePath $executable -ArgumentList ($arguments + '--undo') -PassThru -Wait
    if ($process.ExitCode -ne 0 -or [IO.File]::ReadAllText($source) -ne 'installer smoke test') {
        throw 'Installed app did not restore the original file.'
    }
} finally {
    $uninstaller = Join-Path $installation 'Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        $process = Start-Process -FilePath $uninstaller -ArgumentList "/S _?=$installation" -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw 'Silent uninstaller failed.' }
    }
}
if ((Test-Path -LiteralPath $registry) -or (Test-Path -LiteralPath $menu) -or
    (Test-Path -LiteralPath (Join-Path $installation 'Folder Organizer.exe'))) {
    throw 'Uninstall left registered program files or shortcuts.'
}
if ([IO.File]::ReadAllText($source) -ne 'installer smoke test' -or
    @(Get-ChildItem -LiteralPath $history -Filter '*.json').Count -ne 1) {
    throw 'Uninstall changed test documents or history.'
}
Write-Output 'PASS: install, four shortcuts, real-file sort/undo, uninstall, preserved files/history.'

