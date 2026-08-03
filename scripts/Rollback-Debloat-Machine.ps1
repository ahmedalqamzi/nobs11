# LEGACY, restore-only: only for rolling back backups created by the removed
# Apply-Debloat*.ps1 scripts; new rollbacks use Rollback-Barebones*.ps1.
#requires -Version 7.2
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-debloat-machine' |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $BackupPath) { throw 'No machine-debloat backup was found.' }

$manifestPath = Join-Path $BackupPath 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

function Restore-RegistrySnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    $target = "$($Snapshot.Path)::$($Snapshot.Name)"
    if ($Snapshot.Existed) {
        if ($PSCmdlet.ShouldProcess($target, 'Restore original registry value')) {
            if (-not (Test-Path -LiteralPath $Snapshot.Path)) { New-Item -Path $Snapshot.Path -Force | Out-Null }
            New-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Value $Snapshot.Value -PropertyType $Snapshot.Kind -Force | Out-Null
        }
    }
    elseif ($PSCmdlet.ShouldProcess($target, 'Remove registry value created by machine cleanup')) {
        $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
        if ($key -and ($key.GetValueNames() -contains $Snapshot.Name)) {
            Remove-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Force
        }
        if (-not $Snapshot.KeyExisted) {
            $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
            if ($key -and $key.GetValueNames().Count -eq 0 -and $key.SubKeyCount -eq 0) {
                Remove-Item -LiteralPath $Snapshot.Path -Force
            }
        }
    }
}

$snapshots = @($manifest.RegistryValues)
[array]::Reverse($snapshots)
foreach ($snapshot in $snapshots) {
    Restore-RegistrySnapshot -Snapshot $snapshot
}

$removedPackages = @($manifest.Packages | Where-Object Removed)
if ($removedPackages.Count -gt 0) {
    Write-Warning 'Registry settings were restored, but removed machine-wide packages require the captured System Restore point or their vendor installers.'
    $removedPackages | Select-Object DisplayName,Version,Id | Format-Table -AutoSize
    if ($manifest.RestorePoint) {
        Write-Host "System Restore point: sequence $($manifest.RestorePoint.SequenceNumber) - $($manifest.RestorePoint.Description)" -ForegroundColor Yellow
        Write-Host 'Open rstrui.exe if full machine-package restoration is required.' -ForegroundColor Yellow
    }
}

Write-Host "Machine registry rollback complete from: $BackupPath" -ForegroundColor Green
