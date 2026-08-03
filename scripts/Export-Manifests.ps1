#requires -Version 7.2
[CmdletBinding()]
param(
    [switch]$RefreshCuratedPacmanList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestRoot = Join-Path $projectRoot 'manifests'
$localSnapshotRoot = Join-Path $manifestRoot 'local'
New-Item -ItemType Directory -Path $localSnapshotRoot -Force | Out-Null

$wingetOutput = Join-Path $localSnapshotRoot 'winget-installed.json'
& winget.exe export --output $wingetOutput --include-versions --accept-source-agreements --disable-interactivity
$wingetExitCode = $LASTEXITCODE

$bash = 'C:\msys64\usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { throw "MSYS2 Bash not found: $bash" }
$env:MSYSTEM = 'UCRT64'
$env:CHERE_INVOKING = '1'

$explicitPackages = @(& $bash -lc 'pacman -Qqe | LC_ALL=C sort')
if ($LASTEXITCODE -ne 0) { throw "pacman explicit-package export failed with exit code $LASTEXITCODE" }
$explicitSnapshot = Join-Path $localSnapshotRoot 'pacman-explicit.txt'
$explicitPackages | Set-Content -LiteralPath $explicitSnapshot -Encoding utf8NoBOM
if ($RefreshCuratedPacmanList) {
    $explicitPackages | Set-Content -LiteralPath (Join-Path $manifestRoot 'pacman-explicit.txt') -Encoding utf8NoBOM
}

$allPackages = @(& $bash -lc 'pacman -Q | LC_ALL=C sort')
if ($LASTEXITCODE -ne 0) { throw "pacman full-package export failed with exit code $LASTEXITCODE" }
$allPackages | Set-Content -LiteralPath (Join-Path $localSnapshotRoot 'pacman-all.txt') -Encoding utf8NoBOM

$foreignPackages = @(& $bash -lc 'pacman -Qqm | LC_ALL=C sort')
if ($LASTEXITCODE -notin @(0, 1)) { throw "pacman foreign-package export failed with exit code $LASTEXITCODE" }
$foreignPackages | Set-Content -LiteralPath (Join-Path $localSnapshotRoot 'pacman-foreign.txt') -Encoding utf8NoBOM

$windowsVersion = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$metadata = [ordered]@{
    ExportedAt = (Get-Date).ToString('o')
    Windows = [ordered]@{
        DisplayVersion = $windowsVersion.DisplayVersion
        Build = "$($windowsVersion.CurrentBuild).$($windowsVersion.UBR)"
    }
    WinGetVersion = (& winget.exe --version | Select-Object -First 1)
    WinGetExitCode = $wingetExitCode
    PacmanExplicitCount = $explicitPackages.Count
    PacmanPackageCount = $allPackages.Count
    PacmanForeignCount = $foreignPackages.Count
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $localSnapshotRoot 'export-metadata.json') -Encoding utf8NoBOM

Write-Host "Machine-specific package snapshots exported to ignored directory: $localSnapshotRoot" -ForegroundColor Green
if ($wingetExitCode -ne 0) { exit $wingetExitCode }
