param([string]$OutputDirectory, [string]$NsisCompiler)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
$executable = Join-Path $OutputDirectory 'Folder Organizer.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Run scripts/Build.ps1 first.' }
if (-not $NsisCompiler) {
    $NsisCompiler = Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'
}
if (-not (Test-Path -LiteralPath $NsisCompiler)) { throw 'Install NSIS 3, or pass -NsisCompiler.' }
$portable = Join-Path $OutputDirectory "Folder-Organizer_${version}_x64-portable.exe"
$installer = Join-Path $OutputDirectory "Folder-Organizer_${version}_x64-setup.exe"
Copy-Item -LiteralPath $executable -Destination $portable -Force
& $NsisCompiler /V2 "/DAPP_VERSION=$version" "/DAPP_EXE=$executable" `
    "/DSETUP_OUTPUT=$installer" "$repo\installer\FolderOrganizer.nsi"
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$lines = @($portable, $installer) | ForEach-Object {
    '{0} *{1}' -f (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant(),
        [IO.Path]::GetFileName($_)
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'),
    ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
Write-Output $portable,$installer,(Join-Path $OutputDirectory 'SHA256SUMS.txt')
