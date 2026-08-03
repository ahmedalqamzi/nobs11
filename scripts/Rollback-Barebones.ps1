#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-barebones' |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $BackupPath) { throw 'No barebones backup was found.' }

$manifestPath = Join-Path $BackupPath 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$auditPath = Join-Path $projectRoot "logs\barebones-rollback-$stamp.log"

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
            $null = New-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Value $Snapshot.Value -PropertyType $Snapshot.Kind -Force
        }
        Write-Audit OK "Restored registry value: $target"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($target, 'Remove value created by the barebones profile')) { return }
    $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
    if ($key -and ($key.GetValueNames() -contains [string]$Snapshot.Name)) {
        if ($Snapshot.Name -eq '') {
            $key.DeleteValue('', $false)
        }
        else {
            Remove-ItemProperty -LiteralPath $Snapshot.Path -Name $Snapshot.Name -Force
        }
        Write-Audit OK "Removed registry value created by barebones: $target"
    }
    if (-not $Snapshot.KeyExisted) {
        $key = Get-Item -LiteralPath $Snapshot.Path -ErrorAction SilentlyContinue
        if ($key -and $key.GetValueNames().Count -eq 0 -and $key.SubKeyCount -eq 0) {
            Remove-Item -LiteralPath $Snapshot.Path -Force
        }
    }
}

Write-Audit INFO "Rolling back current-user barebones state from $manifestPath"

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

$wingetPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
if (-not (Test-Path -LiteralPath $wingetPath)) {
    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCommand) { $wingetPath = $wingetCommand.Source }
}

foreach ($app in @($manifest.AppPackages | Where-Object Removed)) {
    if (Get-AppxPackage -Name $app.PackageName -ErrorAction SilentlyContinue) {
        Write-Audit INFO "App is already installed: $($app.DisplayName)"
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($app.DisplayName, 'Restore removed app package')) { continue }

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
    if (-not $restored -and $app.StoreId -and (Test-Path -LiteralPath $wingetPath)) {
        try {
            & $wingetPath install --id $app.StoreId --exact --source msstore --accept-source-agreements --accept-package-agreements --disable-interactivity
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
        Write-Audit ERROR "Could not automatically restore $($app.DisplayName)."
    }
}

Write-Audit INFO 'Barebones rollback finished. Sign out or restart Explorer for all shell settings to refresh.'
Write-Host "Rollback log: $auditPath" -ForegroundColor Cyan
