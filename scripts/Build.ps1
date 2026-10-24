param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The .NET Framework 4 C# compiler is required on 64-bit Windows.'
}
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
$metadata = Get-Content -LiteralPath (Join-Path $repo 'src\AssemblyInfo.cs') -Raw
if ($metadata -notmatch ('AssemblyFileVersion\("' + [regex]::Escape($version) + '\.0"\)')) {
    throw 'VERSION and AssemblyInfo.cs must match.'
}
$output = Join-Path $OutputDirectory 'Folder Organizer.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ `
    "/win32icon:$repo\assets\icon.ico" "/out:$output" `
    /reference:System.Windows.Forms.dll /reference:System.Drawing.dll `
    /reference:System.Web.Extensions.dll "$repo\src\FolderOrganizer.cs" `
    "$repo\src\AssemblyInfo.cs"
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
Write-Output $output
