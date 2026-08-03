# LEGACY, restore-only: only for rolling back backups created by the removed
# Apply-Debloat*.ps1 scripts; new rollbacks use Rollback-Barebones*.ps1.
#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-debloat' |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $BackupPath) { throw 'No debloat backup was found.' }

$manifestPath = Join-Path $BackupPath 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Backup manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$auditPath = Join-Path $projectRoot "logs\debloat-rollback-$stamp.log"

function Write-Audit {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ssK'), $Level, $Message
    Add-Content -LiteralPath $auditPath -Value $line -Encoding utf8
    Write-Host $line
}

function Restore-RegistrySnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    $target = "$($Snapshot.Path)::$($Snapshot.Name)"
    if ($Snapshot.Existed) {
        if ($PSCmdlet.ShouldProcess($target, 'Restore original registry value')) {
            if (-not (Test-Path -LiteralPath $Snapshot.Path)) {
                New-Item -Path $Snapshot.Path -Force | Out-Null
            }
            New-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Value $Snapshot.Value -PropertyType $Snapshot.Kind -Force | Out-Null
            Write-Audit OK "Restored registry value: $target"
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($target, 'Remove value created by debloat batch')) {
        $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
        if ($key -and ($key.GetValueNames() -contains $Snapshot.Name)) {
            Remove-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Force
            Write-Audit OK "Removed registry value created by debloat batch: $target"
        }

        if (-not $Snapshot.KeyExisted) {
            $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
            if ($key -and $key.GetValueNames().Count -eq 0 -and $key.SubKeyCount -eq 0) {
                Remove-Item -LiteralPath $Snapshot.Path -Force
                Write-Audit OK "Removed empty registry key created by debloat batch: $($Snapshot.Path)"
            }
        }
    }
}

Write-Audit INFO "Rolling back debloat state from $manifestPath"

$registrySnapshots = @($manifest.RegistryValues)
[array]::Reverse($registrySnapshots)
foreach ($snapshot in $registrySnapshots) {
    try {
        Restore-RegistrySnapshot -Snapshot $snapshot
    }
    catch {
        Write-Audit ERROR "Failed to restore $($snapshot.Path)::$($snapshot.Name): $($_.Exception.Message)"
    }
}

$startupSnapshots = @($manifest.StartupEntries)
[array]::Reverse($startupSnapshots)
foreach ($snapshot in $startupSnapshots) {
    try {
        Restore-RegistrySnapshot -Snapshot $snapshot
    }
    catch {
        Write-Audit ERROR "Failed to restore startup entry $($snapshot.Path)::$($snapshot.Name): $($_.Exception.Message)"
    }
}

foreach ($app in @($manifest.AppPackages | Where-Object Removed)) {
    if (Get-AppxPackage -Name $app.PackageName -ErrorAction SilentlyContinue) {
        Write-Audit INFO "App already installed: $($app.DisplayName)"
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($app.DisplayName, 'Restore removed current-user app')) { continue }

    $restored = $false
    $appxManifest = Join-Path $app.InstallLocation 'AppxManifest.xml'
    if (Test-Path -LiteralPath $appxManifest) {
        try {
            Add-AppxPackage -DisableDevelopmentMode -Register $appxManifest -ErrorAction Stop
            $restored = [bool](Get-AppxPackage -Name $app.PackageName -ErrorAction SilentlyContinue)
        }
        catch {
            Write-Audit WARN "Local re-registration failed for $($app.DisplayName): $($_.Exception.Message)"
        }
    }

    if (-not $restored -and $app.StoreId) {
        try {
            & winget install --id $app.StoreId --exact --source msstore --accept-source-agreements --accept-package-agreements --disable-interactivity
            $restored = $LASTEXITCODE -eq 0 -and [bool](Get-AppxPackage -Name $app.PackageName -ErrorAction SilentlyContinue)
        }
        catch {
            Write-Audit WARN "Store reinstall failed for $($app.DisplayName): $($_.Exception.Message)"
        }
    }

    if ($restored) {
        Write-Audit OK "Restored app: $($app.DisplayName)"
    }
    else {
        Write-Audit ERROR "Could not automatically restore $($app.DisplayName); reinstall Store ID $($app.StoreId) manually."
    }
}

Write-Audit INFO 'Debloat rollback finished. Sign out or restart Explorer for all shell preferences to refresh.'
Write-Host "Rollback audit log: $auditPath" -ForegroundColor Cyan
