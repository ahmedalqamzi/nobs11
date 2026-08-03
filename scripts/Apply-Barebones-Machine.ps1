#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipComponentCleanup,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    $null = New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $projectRoot 'config\barebones-machine-policy.json'
$userPolicyPath = Join-Path $projectRoot 'config\barebones-policy.json'
if (-not (Test-Path -LiteralPath $policyPath)) { throw "Policy not found: $policyPath" }
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$userPolicy = Get-Content -LiteralPath $userPolicyPath -Raw | ConvertFrom-Json

if (-not $WhatIfPreference -and -not $Force) {
    $warning = 'This elevated, hardware-specific profile disables services and tasks, removes optional Windows capabilities and provisioned apps, uninstalls selected packages, and may run DISM component cleanup. Rollback is best-effort.'
    if (-not $PSCmdlet.ShouldContinue($warning, 'Apply the machine-wide cleanup?')) {
        Write-Host 'Machine-wide cleanup canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-barebones-machine"
$logPath = Join-Path $projectRoot "logs\barebones-machine-$stamp.log"
$taskBackupRoot = Join-Path $backupRoot 'scheduled-tasks'
$null = New-Item -ItemType Directory -Path $backupRoot -Force
$null = New-Item -ItemType Directory -Path $taskBackupRoot -Force

$manifest = [ordered]@{
    SchemaVersion = 1
    CreatedAt = (Get-Date).ToString('o')
    User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Scope = 'Aggressive machine-wide barebones profile'
    PolicyPath = $policyPath
    RestorePoint = $null
    RegistryValues = [System.Collections.Generic.List[object]]::new()
    Services = [System.Collections.Generic.List[object]]::new()
    ScheduledTasks = [System.Collections.Generic.List[object]]::new()
    Features = [System.Collections.Generic.List[object]]::new()
    Capabilities = [System.Collections.Generic.List[object]]::new()
    ProvisionedPackages = [System.Collections.Generic.List[object]]::new()
    Packages = [System.Collections.Generic.List[object]]::new()
    Results = [System.Collections.Generic.List[object]]::new()
}

function Write-Audit {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ssK'), $Level, $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
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

function Get-OptionalProperty {
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
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
        [Parameter(Mandatory)][ValidateSet('DWord', 'String')][string]$Type
    )
    $snapshot = Get-RegistrySnapshot -Path $Path -Name $Name
    $manifest.RegistryValues.Add($snapshot)
    $displayName = if ($Name) { $Name } else { '(Default)' }
    $target = "$Path::$displayName"
    if ($snapshot.Existed -and [string]$snapshot.Value -ceq [string]$Value) {
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
            (Get-Item -LiteralPath $Path).SetValue('', [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
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

function Disable-ManagedService {
    param([Parameter(Mandatory)][string]$Name)

    # Per-user service instances (<Template>_<hex>) cannot be configured directly
    # ("The parameter is incorrect"); configure their template service instead.
    if ($Name -match '^(.+)_([0-9a-fA-F]{5,8})$' -and (Get-Service -Name $Matches[1] -ErrorAction SilentlyContinue)) {
        Write-Audit INFO "Per-user instance $Name redirected to template service $($Matches[1])."
        $Name = $Matches[1]
    }

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        Add-Result service $Name unchanged 'Service is not installed.'
        return
    }
    $record = [ordered]@{
        Name = $service.Name
        DisplayName = $service.DisplayName
        StartType = $service.StartType.ToString()
        Status = $service.Status.ToString()
        Changed = $false
    }
    $manifest.Services.Add($record)
    if ($service.StartType -eq 'Disabled' -and $service.Status -eq 'Stopped') {
        Add-Result service $Name unchanged 'Already disabled and stopped.'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Name, 'Disable optional service and stop it')) {
        Add-Result service $Name what-if 'No change made.'
        return
    }
    try {
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        $record.Changed = $true
        Add-Result service $Name changed "Previous startup=$($record.StartType), state=$($record.Status)."
        Write-Audit OK "Disabled service: $Name"
    }
    catch {
        Add-Result service $Name failed $_.Exception.Message
        Write-Audit ERROR "Failed to disable service $($Name): $($_.Exception.Message)"
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

function Disable-ManagedFeature {
    param([Parameter(Mandatory)][string]$Name)

    # Querying an absent feature by name can terminate Windows PowerShell on
    # some Windows 11 builds (DISM 0x800f080c) before the catch block runs.
    # The main routine therefore builds one safe inventory and this function
    # only filters that in-memory result.
    $feature = $script:featureInventory |
        Where-Object FeatureName -eq $Name |
        Select-Object -First 1
    if (-not $feature) {
        Add-Result feature $Name unchanged 'Feature is not present on this edition.'
        return
    }
    $record = [ordered]@{ Name = $Name; State = $feature.State.ToString(); Changed = $false }
    $manifest.Features.Add($record)
    if ($feature.State -notin @('Enabled', 'EnablePending')) {
        Add-Result feature $Name unchanged "Current state is $($feature.State)."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Name, 'Disable optional Windows feature')) {
        Add-Result feature $Name what-if 'No change made.'
        return
    }
    try {
        $result = Disable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
        $record.Changed = $true
        Add-Result feature $Name changed "Disabled; restartNeeded=$($result.RestartNeeded)."
        Write-Audit OK "Disabled optional feature: $Name"
    }
    catch {
        Add-Result feature $Name failed $_.Exception.Message
        Write-Audit ERROR "Failed to disable feature $($Name): $($_.Exception.Message)"
    }
}

function Remove-ManagedCapability {
    param([Parameter(Mandatory)][string]$Prefix)

    $matches = @($script:capabilityInventory | Where-Object Name -like "$Prefix*")
    if ($matches.Count -eq 0) {
        Add-Result capability $Prefix unchanged 'Capability is not present.'
        return
    }
    foreach ($capability in $matches) {
        $record = [ordered]@{ Name = $capability.Name; State = $capability.State.ToString(); Removed = $false }
        $manifest.Capabilities.Add($record)
        if ($capability.State -ne 'Installed') {
            Add-Result capability $capability.Name unchanged "Current state is $($capability.State)."
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($capability.Name, 'Remove optional Windows capability')) {
            Add-Result capability $capability.Name what-if 'No change made.'
            continue
        }
        try {
            $result = Remove-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
            $record.Removed = $true
            Add-Result capability $capability.Name changed "Removed; restartNeeded=$($result.RestartNeeded)."
            Write-Audit OK "Removed optional capability: $($capability.Name)"
        }
        catch {
            Add-Result capability $capability.Name failed $_.Exception.Message
            Write-Audit ERROR "Failed to remove capability $($capability.Name): $($_.Exception.Message)"
        }
    }
}

trap {
    $fatalMessage = $_.Exception.Message
    try { Write-Audit ERROR "Fatal batch error: $fatalMessage" } catch {}
    try {
        Add-Result fatal 'Apply-Barebones-Machine.ps1' failed $fatalMessage
        $_ | Format-List * -Force | Out-String |
            Set-Content -LiteralPath (Join-Path $backupRoot 'fatal-error.txt') -Encoding UTF8
        $manifest | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $backupRoot 'partial-manifest.json') -Encoding UTF8
    }
    catch {}
    exit 1
}

Write-Audit INFO 'Starting elevated aggressive barebones batch.'

try {
    & manage-bde.exe -status C: | Set-Content -LiteralPath (Join-Path $backupRoot 'bitlocker-status.txt') -Encoding UTF8
}
catch {
    Write-Audit WARN "BitLocker inventory failed: $($_.Exception.Message)"
}

try {
    $description = "Windows Linux Workstation before barebones $stamp"
    Enable-ComputerRestore -Drive "$env:SystemDrive\"
    Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS
    $restorePoint = Get-ComputerRestorePoint | Where-Object Description -eq $description | Sort-Object SequenceNumber -Descending | Select-Object -First 1
    if ($restorePoint) {
        $manifest.RestorePoint = $restorePoint
        Add-Result recovery $description changed "Restore point sequence $($restorePoint.SequenceNumber) created."
    }
    else {
        Add-Result recovery $description failed 'Restore point command completed but no matching point was exposed.'
    }
}
catch {
    Add-Result recovery 'System Restore checkpoint' failed $_.Exception.Message
    Write-Audit WARN "Restore point unavailable; itemized rollback capture will be used: $($_.Exception.Message)"
}

foreach ($setting in @($policy.registry)) {
    Set-ManagedRegistryValue -Path $setting.path -Name $setting.name -Value $setting.value -Type $setting.type
}
foreach ($servicePattern in @($policy.services)) {
    $matches = @(Get-Service -Name $servicePattern -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 0) {
        Add-Result service $servicePattern unchanged 'Service pattern did not match an installed service.'
        continue
    }
    foreach ($service in $matches) {
        Disable-ManagedService -Name $service.Name
    }
}
foreach ($task in @($policy.tasks)) {
    Disable-ManagedTask -TaskPath $task.path -TaskName $task.name
}

# DISM-backed sections (optional features, capabilities, provisioned apps,
# component cleanup) block indefinitely while the servicing stack reports a
# pending restart, so skip them until after reboot. PendingFileRenameOperations
# is deliberately excluded: app updaters (Brave/goopdate, Gaming Services)
# re-create it continuously on this machine without blocking DISM.
$servicingPending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($servicingPending) {
    Write-Audit WARN 'A servicing restart is pending; skipping feature, capability, and component-store sections (DISM blocks on a pending state). Re-run after restart.'
    foreach ($featureName in @($policy.features)) { Add-Result feature $featureName unchanged 'Skipped: servicing restart pending.' }
    foreach ($prefix in @($policy.capabilities)) { Add-Result capability $prefix unchanged 'Skipped: servicing restart pending.' }
    Add-Result cleanup 'Windows component store' unchanged 'Skipped: servicing restart pending.'
}
else {
    Write-Audit INFO 'Disabling optional Windows features.'
    $script:featureInventory = @()
    try {
        $script:featureInventory = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop)
        foreach ($featureName in @($policy.features)) {
            Disable-ManagedFeature -Name $featureName
        }
    }
    catch {
        $message = $_.Exception.Message
        foreach ($featureName in @($policy.features)) {
            Add-Result feature $featureName failed "Feature inventory failed: $message"
        }
        Write-Audit ERROR "Optional-feature inventory failed: $message"
    }

    Write-Audit INFO 'Removing optional Windows capabilities (DISM inventory can take several minutes).'
    $script:capabilityInventory = @()
    try {
        $script:capabilityInventory = @(Get-WindowsCapability -Online -ErrorAction Stop)
        foreach ($prefix in @($policy.capabilities)) {
            Remove-ManagedCapability -Prefix $prefix
        }
    }
    catch {
        $message = $_.Exception.Message
        foreach ($prefix in @($policy.capabilities)) {
            Add-Result capability $prefix failed "Capability inventory failed: $message"
        }
        Write-Audit ERROR "Optional-capability inventory failed: $message"
    }
}

if ($servicingPending) {
    Write-Audit WARN 'Skipping provisioned-app removal (Get-AppxProvisionedPackage is CBS-backed and blocks on a pending servicing restart). Re-run after restart.'
    Add-Result provisioned-app '(all)' unchanged 'Skipped: servicing restart pending.'
}
else {
    Write-Audit INFO 'Removing provisioned optional apps.'

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($app in @($userPolicy.apps)) {
        foreach ($package in @($provisioned | Where-Object DisplayName -eq $app.packageName)) {
        $record = [ordered]@{
            DisplayName = $package.DisplayName
            PackageName = $package.PackageName
            Version = $package.Version
            Removed = $false
        }
        $manifest.ProvisionedPackages.Add($record)
        if (-not $PSCmdlet.ShouldProcess($package.PackageName, 'Remove provisioned optional app')) {
            Add-Result provisioned-app $package.DisplayName what-if 'No change made.'
            continue
        }
        try {
            $null = Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop
            $record.Removed = $true
            Add-Result provisioned-app $package.DisplayName changed 'Removed from Windows provisioning.'
        }
        catch {
            Add-Result provisioned-app $package.DisplayName failed $_.Exception.Message
            Write-Audit ERROR "Failed to deprovision $($package.DisplayName): $($_.Exception.Message)"
        }
        }
    }
}

$wingetPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
if (-not (Test-Path -LiteralPath $wingetPath)) {
    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCommand) { $wingetPath = $wingetCommand.Source }
}

Write-Audit INFO 'Uninstalling optional machine packages via WinGet.'
foreach ($target in @($policy.uninstallPackages)) {
    $installed = Get-ItemProperty -LiteralPath $target.registryPath -ErrorAction SilentlyContinue
    $record = [ordered]@{
        DisplayName = $target.displayName
        Id = $target.id
        RegistryPath = $target.registryPath
        Version = Get-OptionalProperty -Object $installed -Name 'DisplayVersion'
        UninstallString = Get-OptionalProperty -Object $installed -Name 'UninstallString'
        QuietUninstallString = Get-OptionalProperty -Object $installed -Name 'QuietUninstallString'
        Removed = $false
        ExitCode = $null
    }
    $manifest.Packages.Add($record)
    if (-not $installed) {
        Add-Result package $target.displayName unchanged 'Package is not installed.'
        continue
    }
    if (-not (Test-Path -LiteralPath $wingetPath)) {
        Add-Result package $target.displayName failed 'WinGet executable was not found.'
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($target.displayName, 'Uninstall optional machine package')) {
        Add-Result package $target.displayName what-if 'No change made.'
        continue
    }
    try {
        $packageLog = Join-Path $backupRoot (($target.displayName -replace '[^a-zA-Z0-9.-]', '-') + '.log')
        & $wingetPath uninstall --id $target.id --exact --silent --disable-interactivity --accept-source-agreements 2>&1 |
            Set-Content -LiteralPath $packageLog -Encoding UTF8
        $record.ExitCode = $LASTEXITCODE
        $record.Removed = -not (Test-Path -LiteralPath $target.registryPath)
        if ($record.Removed) {
            Add-Result package $target.displayName changed "Uninstalled; exitCode=$($record.ExitCode)."
            Write-Audit OK "Uninstalled machine package: $($target.displayName)"
        }
        else {
            Add-Result package $target.displayName failed "Package remains registered; exitCode=$($record.ExitCode)."
        }
    }
    catch {
        Add-Result package $target.displayName failed $_.Exception.Message
        Write-Audit ERROR "Failed to uninstall $($target.displayName): $($_.Exception.Message)"
    }
}

if (-not $SkipComponentCleanup -and -not $servicingPending -and $PSCmdlet.ShouldProcess('Windows component store', 'Run StartComponentCleanup without ResetBase')) {
    try {
        $componentLog = Join-Path $backupRoot 'dism-start-component-cleanup.log'
        & dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart 2>&1 |
            Set-Content -LiteralPath $componentLog -Encoding UTF8
        if ($LASTEXITCODE -eq 0) {
            Add-Result cleanup 'Windows component store' changed 'StartComponentCleanup completed without ResetBase.'
        }
        else {
            Add-Result cleanup 'Windows component store' failed "DISM exit code $LASTEXITCODE."
        }
    }
    catch {
        Add-Result cleanup 'Windows component store' failed $_.Exception.Message
    }
}

$manifestPath = Join-Path $backupRoot 'manifest.json'
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$manifest.Results | Export-Csv -LiteralPath (Join-Path $backupRoot 'results.csv') -NoTypeInformation -Encoding UTF8

$changed = @($manifest.Results | Where-Object Status -eq 'changed').Count
$failed = @($manifest.Results | Where-Object Status -eq 'failed').Count
$completion = [ordered]@{
    FinishedAt = (Get-Date).ToString('o')
    BackupPath = $backupRoot
    ManifestPath = $manifestPath
    LogPath = $logPath
    Changed = $changed
    Failed = $failed
    RestartRecommended = $true
}
$completion | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'logs\barebones-machine-latest.json') -Encoding UTF8

Write-Audit INFO "Elevated barebones batch complete. Changed=$changed Failed=$failed"
Write-Host "Rollback manifest: $manifestPath" -ForegroundColor Cyan
if ($failed -gt 0) { exit 2 }
