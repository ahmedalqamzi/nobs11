#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-atlas-performance' |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $BackupPath) { throw 'No Atlas performance backup was found.' }

$manifestPath = Join-Path $BackupPath 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$auditPath = Join-Path $projectRoot "logs\atlas-performance-rollback-$stamp.log"

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
            $value = $Snapshot.Value
            if ($Snapshot.Kind -eq 'Binary') { $value = [byte[]]($Snapshot.Value) }
            $null = New-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Value $value -PropertyType $Snapshot.Kind -Force
        }
        Write-Audit OK "Restored registry value: $target"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($target, 'Remove value created by the Atlas performance policy')) { return }
    $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
    if ($key -and ($key.GetValueNames() -contains [string]$Snapshot.Name)) {
        if ($Snapshot.Name -eq '') {
            $key.DeleteValue('', $false)
        }
        else {
            Remove-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Force
        }
        Write-Audit OK "Removed registry value created by the Atlas performance policy: $target"
    }
    if (-not $Snapshot.KeyExisted) {
        $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
        if ($key -and $key.GetValueNames().Count -eq 0 -and $key.SubKeyCount -eq 0) {
            Remove-Item -LiteralPath $Snapshot.Path -Force
        }
    }
}

Write-Audit INFO "Rolling back Atlas performance state from $manifestPath"

$snapshots = @($manifest.RegistryValues)
[array]::Reverse($snapshots)
foreach ($snapshot in $snapshots) {
    try {
        Restore-RegistrySnapshot -Snapshot $snapshot
    }
    catch {
        Write-Audit ERROR "Registry rollback failed for $($snapshot.Path)::$($snapshot.Name): $($_.Exception.Message)"
    }
}

foreach ($record in @($manifest.SvcHostSplit | Where-Object Changed)) {
    $target = "$($record.Path)::SvcHostSplitDisable"
    if ($record.Existed) {
        if (-not $PSCmdlet.ShouldProcess($target, "Restore SvcHostSplitDisable=$($record.PreviousValue)")) { continue }
        try {
            $null = New-ItemProperty -LiteralPath $record.Path -Name SvcHostSplitDisable -Value ([int]$record.PreviousValue) -PropertyType DWord -Force -ErrorAction Stop
            Write-Audit OK "Restored svchost split state: $target"
        }
        catch {
            Write-Audit ERROR "Svchost rollback failed for $($target): $($_.Exception.Message)"
        }
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($target, 'Remove SvcHostSplitDisable created by the Atlas performance policy')) { continue }
    try {
        $key = Get-Item -LiteralPath $record.Path -ErrorAction SilentlyContinue
        if ($key -and ($key.GetValueNames() -contains 'SvcHostSplitDisable')) {
            Remove-ItemProperty -LiteralPath $record.Path -Name SvcHostSplitDisable -Force -ErrorAction Stop
            Write-Audit OK "Removed svchost split value created by the Atlas performance policy: $target"
        }
    }
    catch {
        Write-Audit ERROR "Svchost rollback failed for $($target): $($_.Exception.Message)"
    }
}

foreach ($record in @($manifest.EventLogs | Where-Object { $_.Changed -and $_.WasEnabled })) {
    if (-not $PSCmdlet.ShouldProcess($record.LogName, 'Re-enable event log')) { continue }
    $null = & wevtutil.exe set-log $record.LogName /e:true 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Audit OK "Re-enabled event log: $($record.LogName)"
    }
    else {
        Write-Audit ERROR "Event log rollback failed for $($record.LogName): wevtutil exit code $LASTEXITCODE."
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

foreach ($record in @($manifest.Fsutil | Where-Object Changed)) {
    $restoreArguments = $record.Arguments -replace '\d+\s*$', [string]$record.PreviousValue
    $target = "fsutil $restoreArguments"
    if (-not $PSCmdlet.ShouldProcess($target, 'Restore previous fsutil behavior')) { continue }
    & fsutil.exe ($restoreArguments -split ' ') 2>&1 | ForEach-Object { Write-Audit INFO "fsutil: $_" }
    if ($LASTEXITCODE -eq 0) {
        Write-Audit OK "Restored fsutil behavior: $target"
    }
    else {
        Write-Audit ERROR "fsutil rollback failed for $($target): fsutil exit code $LASTEXITCODE."
    }
}

Write-Audit INFO 'Atlas performance rollback finished. Restart Windows for kernel, MMCSS, and svchost grouping changes to fully revert.'
Write-Host "Rollback log: $auditPath" -ForegroundColor Cyan
