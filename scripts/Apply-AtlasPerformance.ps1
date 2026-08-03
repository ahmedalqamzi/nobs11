#requires -Version 7.2
# Reviewed, locally tracked adaptation of AtlasOS revision
# 1ed9630616b29f0c7974e8bd76a94fc06f60388c playbook
# tweaks. AtlasOS items that reduce security or violate the project constraints
# (Defender/VBS/mitigations, disabling Windows Update, Edge removal, NetBT/UCPD,
# UAC secure desktop, NIC driver registry tweaks, BCD boot-menu changes,
# 8.3-name disabling, AutoEndTasks) are deliberately excluded.
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $projectRoot 'config\atlas-performance-policy.json'
if (-not (Test-Path -LiteralPath $policyPath)) { throw "Policy not found: $policyPath" }
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json

if (-not $WhatIfPreference -and -not $Force) {
    $warning = 'This applies optional performance-related registry, scheduled-task, event-log, and service-host settings. Review config\atlas-performance-policy.json before continuing.'
    if (-not $PSCmdlet.ShouldContinue($warning, 'Apply the optional performance profile?')) {
        Write-Host 'Performance profile canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-atlas-performance"
$auditPath = Join-Path $projectRoot "logs\atlas-performance-$stamp.log"
$taskBackupRoot = Join-Path $backupRoot 'scheduled-tasks'
$null = New-Item -ItemType Directory -Path $backupRoot -Force
$null = New-Item -ItemType Directory -Path $taskBackupRoot -Force
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $auditPath) -Force

$isElevated = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$manifest = [ordered]@{
    SchemaVersion = 1
    CreatedAt = (Get-Date).ToString('o')
    User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Scope = 'AtlasOS-derived performance policy'
    PolicyPath = $policyPath
    Sources = @($policy.sources)
    Elevated = $isElevated
    RegistryValues = [System.Collections.Generic.List[object]]::new()
    SvcHostSplit = [System.Collections.Generic.List[object]]::new()
    EventLogs = [System.Collections.Generic.List[object]]::new()
    ScheduledTasks = [System.Collections.Generic.List[object]]::new()
    Fsutil = [System.Collections.Generic.List[object]]::new()
    Results = [System.Collections.Generic.List[object]]::new()
}

function Write-Audit {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ssK'), $Level, $Message
    Add-Content -LiteralPath $auditPath -Value $line -Encoding utf8
    Write-Host $line
}

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][ValidateSet('changed', 'unchanged', 'failed', 'what-if')][string]$Status,
        [string]$Detail
    )
    $manifest.Results.Add([pscustomobject]@{
        Category = $Category
        Target = $Target
        Status = $Status
        Detail = $Detail
    })
}

function Get-RegistrySnapshot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    $keyExisted = $null -ne $key
    $valueExisted = $keyExisted -and ($key.GetValueNames() -contains $Name)
    [pscustomobject]@{
        Path = $Path
        Name = $Name
        KeyExisted = $keyExisted
        Existed = $valueExisted
        Kind = if ($valueExisted) { $key.GetValueKind($Name).ToString() } else { $null }
        Value = if ($valueExisted) {
            $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        else { $null }
    }
}

function Set-ManagedRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][ValidateSet('DWord', 'String', 'Binary')][string]$Type
    )
    $snapshot = Get-RegistrySnapshot -Path $Path -Name $Name
    $manifest.RegistryValues.Add($snapshot)
    $displayName = if ($Name) { $Name } else { '(Default)' }
    $target = "$Path::$displayName"
    $bytes = $null
    $alreadySet = $false
    if ($Type -eq 'Binary') {
        # Policy stores binary values as a comma-separated hex byte string ("90,12,03,80,10,00,00,00").
        $bytes = [byte[]]($Value -split ',' | ForEach-Object { [Convert]::ToByte($_.Trim(), 16) })
        $alreadySet = $snapshot.Existed -and (([string]([byte[]]$snapshot.Value -join ',')) -ceq ([string]($bytes -join ',')))
    }
    else {
        $alreadySet = $snapshot.Existed -and [string]$snapshot.Value -ceq [string]$Value
    }
    if ($alreadySet) {
        Add-Result registry $target unchanged "Already set to $Value."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($target, "Set $Type value to $Value")) {
        Add-Result registry $target what-if 'No change made.'
        return
    }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force }
        if ($Name -eq '') {
            $key = Get-Item -LiteralPath $Path
            $key.SetValue('', [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
        }
        elseif ($Type -eq 'Binary') {
            $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $bytes -PropertyType Binary -Force
        }
        else {
            $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force
        }
        Add-Result registry $target changed "Set to $Value; previous state captured."
    }
    catch {
        Add-Result registry $target failed $_.Exception.Message
        Write-Audit ERROR "Failed to set $($target): $($_.Exception.Message)"
    }
}

function Set-SvcHostSplitDisableState {
    param([Parameter(Mandatory)][string]$ExcludePattern)

    $servicesRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    foreach ($key in @(Get-ChildItem -LiteralPath $servicesRoot -ErrorAction SilentlyContinue)) {
        $serviceName = $key.PSChildName
        if ($serviceName -match $ExcludePattern) { continue }
        if ($key.GetValueNames() -notcontains 'Start') { continue }
        $path = "$servicesRoot\$serviceName"
        $target = "$path::SvcHostSplitDisable"
        $snapshot = Get-RegistrySnapshot -Path $path -Name 'SvcHostSplitDisable'
        $record = [ordered]@{
            Path = $path
            Service = $serviceName
            Existed = $snapshot.Existed
            PreviousValue = $snapshot.Value
            Changed = $false
        }
        $manifest.SvcHostSplit.Add($record)
        if ($snapshot.Existed -and [int]$snapshot.Value -eq 1) {
            Add-Result svchost $target unchanged 'Already set to 1.'
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($target, 'Group service into a shared svchost process')) {
            Add-Result svchost $target what-if 'No change made.'
            continue
        }
        try {
            $null = New-ItemProperty -LiteralPath $path -Name SvcHostSplitDisable -Value 1 -PropertyType DWord -Force -ErrorAction Stop
            $record.Changed = $true
            Add-Result svchost $target changed 'Set to 1; previous state captured.'
        }
        catch {
            Add-Result svchost $target failed $_.Exception.Message
            Write-Audit ERROR "Failed to set $($target): $($_.Exception.Message)"
        }
    }
}

function Disable-ManagedEventLog {
    param([Parameter(Mandatory)][string]$LogName)

    $queryOutput = & wevtutil.exe get-log $LogName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Result eventlog $LogName unchanged 'Log is not present.'
        return
    }
    $wasEnabled = [bool](@($queryOutput) | Select-String -Pattern '(?i)^enabled:\s*true')
    $record = [ordered]@{
        LogName = $LogName
        WasEnabled = $wasEnabled
        Changed = $false
    }
    $manifest.EventLogs.Add($record)
    if (-not $wasEnabled) {
        Add-Result eventlog $LogName unchanged 'Log was already disabled.'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($LogName, 'Disable event log')) {
        Add-Result eventlog $LogName what-if 'No change made.'
        return
    }
    $null = & wevtutil.exe set-log $LogName /e:false 2>&1
    if ($LASTEXITCODE -eq 0) {
        $record.Changed = $true
        Add-Result eventlog $LogName changed 'Disabled; prior enabled state captured.'
    }
    else {
        Add-Result eventlog $LogName failed "wevtutil exit code $LASTEXITCODE."
        Write-Audit ERROR "Failed to disable event log $($LogName): wevtutil exit code $LASTEXITCODE."
    }
}

function Disable-ManagedTask {
    param(
        [Parameter(Mandatory)][string]$TaskPath,
        [Parameter(Mandatory)][string]$TaskName
    )
    $target = "$TaskPath$TaskName"
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Add-Result task $target unchanged 'Task is not present.'
        return
    }
    $safeName = ($target.Trim('\') -replace '[^a-zA-Z0-9_.-]', '_') + '.xml'
    $xmlPath = Join-Path $taskBackupRoot $safeName
    try {
        Export-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName | Set-Content -LiteralPath $xmlPath -Encoding UTF8
    }
    catch {
        $xmlPath = $null
    }
    $wasEnabled = [bool]$task.Settings.Enabled
    $record = [ordered]@{
        TaskPath = $TaskPath
        TaskName = $TaskName
        WasEnabled = $wasEnabled
        State = $task.State.ToString()
        XmlPath = $xmlPath
        Changed = $false
    }
    $manifest.ScheduledTasks.Add($record)
    if (-not $wasEnabled) {
        Add-Result task $target unchanged 'Task was already disabled.'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($target, 'Disable scheduled task')) {
        Add-Result task $target what-if 'No change made.'
        return
    }
    try {
        $null = Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
        $record.Changed = $true
        Add-Result task $target changed 'Disabled; prior XML/state captured.'
    }
    catch {
        Add-Result task $target failed $_.Exception.Message
        Write-Audit ERROR "Failed to disable task $($target): $($_.Exception.Message)"
    }
}

function Set-FsutilBehavior {
    param([Parameter(Mandatory)][string]$Arguments)

    $target = "fsutil $Arguments"
    $queryArguments = ($Arguments -replace '^behavior\s+set\s+', 'behavior query ') -replace '\s+\S+\s*$', ''
    $queryOutput = & fsutil.exe ($queryArguments -split ' ') 2>&1
    $queryText = ($queryOutput | Out-String).Trim()
    $previousValue = $null
    if ($LASTEXITCODE -eq 0 -and $queryText -match '=\s*(\d+)') { $previousValue = [int]$Matches[1] }
    $desiredValue = $null
    if ($Arguments -match '(\d+)\s*$') { $desiredValue = [int]$Matches[1] }
    $record = [ordered]@{
        Arguments = $Arguments
        QueryArguments = $queryArguments
        PreviousValue = $previousValue
        QueryOutput = $queryText
        Changed = $false
    }
    $manifest.Fsutil.Add($record)
    if ($null -eq $previousValue -or $null -eq $desiredValue) {
        Add-Result fsutil $target failed "Could not parse current or desired state: $queryText"
        Write-Audit ERROR "Failed to query state for $($target)."
        return
    }
    if ($previousValue -eq $desiredValue) {
        Add-Result fsutil $target unchanged "Already set to $desiredValue."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($target, 'Run fsutil')) {
        Add-Result fsutil $target what-if 'No change made.'
        return
    }
    & fsutil.exe ($Arguments -split ' ') 2>&1 | ForEach-Object { Write-Audit INFO "fsutil: $_" }
    if ($LASTEXITCODE -eq 0) {
        $record.Changed = $true
        Add-Result fsutil $target changed "Applied; previous value was $previousValue."
    }
    else {
        Add-Result fsutil $target failed "fsutil exit code $LASTEXITCODE."
        Write-Audit ERROR "Failed to run $($target): fsutil exit code $LASTEXITCODE."
    }
}

Write-Audit INFO 'Applying AtlasOS-derived performance policy.'

foreach ($setting in @($policy.registryUser)) {
    Set-ManagedRegistryValue -Path $setting.path -Name $setting.name -Value $setting.value -Type $setting.type
}

if ($isElevated) {
    Write-Audit INFO 'Elevated shell detected; applying the machine-wide section.'
    foreach ($setting in @($policy.registryMachine)) {
        Set-ManagedRegistryValue -Path $setting.path -Name $setting.name -Value $setting.value -Type $setting.type
    }
    foreach ($action in @($policy.machineActions)) {
        switch ($action.kind) {
            'svcHostSplitDisable' { Set-SvcHostSplitDisableState -ExcludePattern $action.excludePattern }
            'disableEventLogs' {
                foreach ($log in @($action.logs)) { Disable-ManagedEventLog -LogName $log }
            }
            'disableScheduledTasks' {
                foreach ($task in @($action.tasks)) { Disable-ManagedTask -TaskPath $task.path -TaskName $task.name }
            }
            'fsutil' { Set-FsutilBehavior -Arguments $action.args }
            default {
                Add-Result machine-action $action.kind failed 'Unknown machine action kind.'
                Write-Audit ERROR "Unknown machine action kind: $($action.kind)"
            }
        }
    }
}
else {
    Write-Audit WARN 'Not elevated; skipping the machine-wide section (HKLM policy values and machine actions).'
    Write-Audit WARN "Re-run from an elevated shell to apply it: powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath"
    Write-Host 'Machine section skipped: this shell is not elevated.' -ForegroundColor Yellow
    Write-Host "Re-run elevated: powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath" -ForegroundColor Yellow
    foreach ($setting in @($policy.registryMachine)) {
        Add-Result registry "$($setting.path)::$($setting.name)" unchanged 'skipped: requires elevation'
    }
    foreach ($action in @($policy.machineActions)) {
        Add-Result machine-action $action.kind unchanged 'skipped: requires elevation'
    }
}

$manifestPath = Join-Path $backupRoot 'manifest.json'
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
$manifest.Results | Export-Csv -LiteralPath (Join-Path $backupRoot 'results.csv') -NoTypeInformation -Encoding utf8

try {
    Add-Type -Namespace AtlasPerformance -Name ShellNotify -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
'@
    [AtlasPerformance.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    & rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, $true
}
catch {
    Write-Audit WARN "Shell refresh signal failed: $($_.Exception.Message)"
}

$changed = @($manifest.Results | Where-Object Status -eq 'changed').Count
$failed = @($manifest.Results | Where-Object Status -eq 'failed').Count
$completion = [ordered]@{
    FinishedAt = (Get-Date).ToString('o')
    BackupPath = $backupRoot
    ManifestPath = $manifestPath
    LogPath = $auditPath
    Changed = $changed
    Failed = $failed
    MachineSectionApplied = $isElevated
    RestartRecommended = $true
}
$completion | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'logs\atlas-performance-latest.json') -Encoding utf8NoBOM

Write-Audit INFO "Atlas performance policy finished. Changed=$changed Failed=$failed"
Write-Host "Rollback manifest: $manifestPath" -ForegroundColor Cyan
Write-Host "Audit log: $auditPath" -ForegroundColor Cyan
if ($failed -gt 0) { exit 2 }
