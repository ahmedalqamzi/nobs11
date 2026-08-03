#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    $null = New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS
}

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-barebones-machine' |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $BackupPath) { throw 'No machine barebones backup was found.' }

$manifestPath = Join-Path $BackupPath 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $projectRoot "logs\barebones-machine-rollback-$stamp.log"

function Write-Audit {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ssK'), $Level, $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Restore-RegistrySnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    $displayName = if ($Snapshot.Name) { $Snapshot.Name } else { '(Default)' }
    $target = "$($Snapshot.Path)::$displayName"
    if ($Snapshot.Existed) {
        if (-not $PSCmdlet.ShouldProcess($target, 'Restore original registry value')) { return }
        if (-not (Test-Path -LiteralPath $Snapshot.Path)) { $null = New-Item -Path $Snapshot.Path -Force }
        if ($Snapshot.Name -eq '') {
            $kind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$Snapshot.Kind)
            (Get-Item -LiteralPath $Snapshot.Path).SetValue('', $Snapshot.Value, $kind)
        }
        else {
            $null = New-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Value $Snapshot.Value -PropertyType $Snapshot.Kind -Force
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($target, 'Remove value created by barebones')) { return }
    $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
    if ($key -and ($key.GetValueNames() -contains [string]$Snapshot.Name)) {
        if ($Snapshot.Name -eq '') {
            $key.DeleteValue('', $false)
        }
        else {
            Remove-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Force
        }
    }
    if (-not $Snapshot.KeyExisted) {
        $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
        if ($key -and $key.GetValueNames().Count -eq 0 -and $key.SubKeyCount -eq 0) {
            Remove-Item -LiteralPath $Snapshot.Path -Force
        }
    }
}

Write-Audit INFO "Rolling back machine barebones state from $manifestPath"

$registrySnapshots = @($manifest.RegistryValues)
[array]::Reverse($registrySnapshots)
foreach ($snapshot in $registrySnapshots) {
    try {
        Restore-RegistrySnapshot -Snapshot $snapshot
    }
    catch {
        Write-Audit ERROR "Registry rollback failed for $($snapshot.Path)::$($snapshot.Name): $($_.Exception.Message)"
    }
}

foreach ($service in @($manifest.Services | Where-Object Changed)) {
    if (-not $PSCmdlet.ShouldProcess($service.Name, "Restore startup=$($service.StartType), state=$($service.Status)")) { continue }
    try {
        Set-Service -Name $service.Name -StartupType $service.StartType -ErrorAction Stop
        if ($service.Status -eq 'Running') {
            Start-Service -Name $service.Name -ErrorAction Stop
        }
        Write-Audit OK "Restored service: $($service.Name)"
    }
    catch {
        Write-Audit ERROR "Service rollback failed for $($service.Name): $($_.Exception.Message)"
    }
}

foreach ($task in @($manifest.ScheduledTasks | Where-Object { $_.Changed -and $_.WasEnabled })) {
    $target = "$($task.TaskPath)$($task.TaskName)"
    if (-not $PSCmdlet.ShouldProcess($target, 'Re-enable scheduled task')) { continue }
    try {
        $null = Enable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop
        Write-Audit OK "Re-enabled task: $target"
    }
    catch {
        Write-Audit ERROR "Task rollback failed for $($target): $($_.Exception.Message)"
    }
}

foreach ($feature in @($manifest.Features | Where-Object Changed)) {
    if (-not $PSCmdlet.ShouldProcess($feature.Name, 'Re-enable optional Windows feature')) { continue }
    try {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature.Name -All -NoRestart -ErrorAction Stop
        Write-Audit OK "Re-enabled feature $($feature.Name); restartNeeded=$($result.RestartNeeded)"
    }
    catch {
        Write-Audit ERROR "Feature rollback failed for $($feature.Name): $($_.Exception.Message)"
    }
}

foreach ($capability in @($manifest.Capabilities | Where-Object Removed)) {
    if (-not $PSCmdlet.ShouldProcess($capability.Name, 'Reinstall Windows capability')) { continue }
    try {
        $result = Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
        Write-Audit OK "Restored capability $($capability.Name); restartNeeded=$($result.RestartNeeded)"
    }
    catch {
        Write-Audit ERROR "Capability rollback failed for $($capability.Name): $($_.Exception.Message)"
    }
}

$deprovisioned = @($manifest.ProvisionedPackages | Where-Object Removed)
if ($deprovisioned.Count -gt 0) {
    Write-Audit WARN 'Provisioned Appx payloads are not automatically restored machine-wide; use Rollback-Barebones.ps1 to restore this user or reinstall from Microsoft Store.'
}

$removedPackages = @($manifest.Packages | Where-Object Removed)
if ($removedPackages.Count -gt 0) {
    Write-Audit WARN 'Removed vendor/MSI packages require vendor installers or the captured System Restore point for reinstallation.'
    $removedPackages | Select-Object DisplayName, Version, Id, UninstallString | Format-Table -AutoSize
}
if ($manifest.RestorePoint) {
    Write-Audit INFO "System Restore point: sequence $($manifest.RestorePoint.SequenceNumber), $($manifest.RestorePoint.Description)"
}

Write-Audit INFO 'Machine barebones rollback finished. Restart Windows to complete feature and service restoration.'
Write-Host "Rollback log: $logPath" -ForegroundColor Cyan
