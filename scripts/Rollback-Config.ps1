#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-config' |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $BackupPath) { throw 'No configuration backup was found.' }

$manifestPath = Join-Path $BackupPath 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Backup manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

foreach ($entry in $manifest) {
    if ($entry.Existed) {
        if ($PSCmdlet.ShouldProcess($entry.Target, "Restore from $($entry.Backup)")) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $entry.Target) -Force | Out-Null
            Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force
        }
    }
    elseif (Test-Path -LiteralPath $entry.Target) {
        if ($PSCmdlet.ShouldProcess($entry.Target, 'Remove file created by Apply-Config')) {
            Remove-Item -LiteralPath $entry.Target -Force
        }
    }
}

Write-Host "Configuration rollback complete from: $BackupPath" -ForegroundColor Green
