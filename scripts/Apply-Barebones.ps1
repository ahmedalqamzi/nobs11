#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipAppRemoval,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $projectRoot 'config\barebones-policy.json'
if (-not (Test-Path -LiteralPath $policyPath)) { throw "Policy not found: $policyPath" }
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json

if (-not $WhatIfPreference -and -not $Force) {
    $warning = 'This applies more than 100 current-user policy changes and can remove optional Appx packages. Review config\barebones-policy.json and retain the generated rollback files.'
    if (-not $PSCmdlet.ShouldContinue($warning, 'Apply the aggressive current-user cleanup?')) {
        Write-Host 'Current-user cleanup canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-barebones"
$auditPath = Join-Path $projectRoot "logs\barebones-$stamp.log"
$null = New-Item -ItemType Directory -Path $backupRoot -Force
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $auditPath) -Force

$manifest = [ordered]@{
    SchemaVersion = 1
    CreatedAt = (Get-Date).ToString('o')
    User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Scope = 'Aggressive current-user barebones profile'
    PolicyPath = $policyPath
    Sources = @($policy.sources)
    RegistryValues = [System.Collections.Generic.List[object]]::new()
    AppPackages = [System.Collections.Generic.List[object]]::new()
    Results = [System.Collections.Generic.List[object]]::new()
    Preserved = @($policy.preserved)
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
        [Parameter(Mandatory)][ValidateSet('changed', 'unchanged', 'failed', 'what-if', 'preserved')][string]$Status,
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
            $key = Get-Item -LiteralPath $Path
            $key.SetValue('', [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
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

function Remove-ManagedRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )
    $snapshot = Get-RegistrySnapshot -Path $Path -Name $Name
    $manifest.RegistryValues.Add($snapshot)
    $target = "$Path::$Name"
    if (-not $snapshot.Existed) {
        Add-Result registry $target unchanged 'Value was already absent.'
        return
    }
    if (-not $PSCmdlet.ShouldProcess($target, 'Remove registry value')) {
        Add-Result registry $target what-if 'No change made.'
        return
    }
    try {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -Force
        Add-Result registry $target changed 'Removed; previous state captured.'
    }
    catch {
        Add-Result registry $target failed $_.Exception.Message
        Write-Audit ERROR "Failed to remove $($target): $($_.Exception.Message)"
    }
}

function Remove-ManagedAppPackage {
    param(
        [Parameter(Mandatory)][string]$PackageName,
        [Parameter(Mandatory)][string]$DisplayName,
        [AllowNull()][string]$StoreId
    )
    $packages = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
    if ($packages.Count -eq 0) {
        Add-Result app $DisplayName unchanged 'Package was not installed for this user.'
        return
    }
    foreach ($package in $packages) {
        $record = [ordered]@{
            DisplayName = $DisplayName
            PackageName = $package.Name
            PackageFullName = $package.PackageFullName
            PackageFamilyName = $package.PackageFamilyName
            Version = $package.Version.ToString()
            InstallLocation = $package.InstallLocation
            StoreId = $StoreId
            NonRemovable = [bool]$package.NonRemovable
            Removed = $false
        }
        $manifest.AppPackages.Add($record)
        if ($record.NonRemovable) {
            Add-Result app $DisplayName preserved 'Windows marks this package as non-removable.'
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($package.PackageFullName, "Remove optional app: $DisplayName")) {
            Add-Result app $DisplayName what-if 'No change made.'
            continue
        }
        try {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
            $record.Removed = -not [bool](Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
            if ($record.Removed) {
                Add-Result app $DisplayName changed 'Removed for the current user.'
                Write-Audit OK "Removed optional app: $DisplayName"
            }
            else {
                Add-Result app $DisplayName failed 'Package remained registered after removal.'
            }
        }
        catch {
            Add-Result app $DisplayName failed $_.Exception.Message
            Write-Audit ERROR "Failed to remove $($DisplayName): $($_.Exception.Message)"
        }
    }
}

Write-Audit INFO 'Applying aggressive current-user barebones profile.'

foreach ($setting in @($policy.registry)) {
    Set-ManagedRegistryValue -Path $setting.path -Name $setting.name -Value $setting.value -Type $setting.type
}
foreach ($setting in @($policy.removeValues)) {
    Remove-ManagedRegistryValue -Path $setting.path -Name $setting.name
}
if (-not $SkipAppRemoval) {
    foreach ($app in @($policy.apps)) {
        Remove-ManagedAppPackage -PackageName $app.packageName -DisplayName $app.displayName -StoreId $app.storeId
    }
}

foreach ($item in $manifest.Preserved) {
    Add-Result preserved $item preserved 'Retained to avoid security, data-loss, driver, update, login or gaming breakage.'
}

$manifestPath = Join-Path $backupRoot 'manifest.json'
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
$manifest.Results | Export-Csv -LiteralPath (Join-Path $backupRoot 'results.csv') -NoTypeInformation -Encoding utf8

try {
    Add-Type -Namespace Barebones -Name ShellNotify -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
'@
    [Barebones.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    & rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, $true
}
catch {
    Write-Audit WARN "Shell refresh signal failed: $($_.Exception.Message)"
}

$changed = @($manifest.Results | Where-Object Status -eq 'changed').Count
$failed = @($manifest.Results | Where-Object Status -eq 'failed').Count
Write-Audit INFO "Barebones profile finished. Changed=$changed Failed=$failed"
Write-Host "Rollback manifest: $manifestPath" -ForegroundColor Cyan
Write-Host "Audit log: $auditPath" -ForegroundColor Cyan
if ($failed -gt 0) { exit 2 }
