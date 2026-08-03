#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$BackupPath,
    [switch]$RestoreQuarantinedStartupEntries,
    [switch]$RestorePreviousTask
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$taskName = 'WindowsLinuxWorkstation Startup Guard'
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'WindowsLinuxWorkstation'

if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-startup-guard' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($taskName, 'Unregister startup guard')) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}

$restoredPreviousTask = $false
if ($BackupPath) {
    $manifestPath = Join-Path $BackupPath 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $taskBackup = if ($manifest.PSObject.Properties.Name -contains 'ReplacedTaskBackup') {
            $manifest.ReplacedTaskBackup
        }
        elseif ($manifest.PSObject.Properties.Name -contains 'PreviousTask') {
            $manifest.PreviousTask
        }
        else {
            $null
        }
        if ($RestorePreviousTask -and $taskBackup -and (Test-Path -LiteralPath $taskBackup)) {
            if ($PSCmdlet.ShouldProcess($taskName, 'Restore task definition that existed before guard installation')) {
                Register-ScheduledTask -TaskName $taskName -Xml (Get-Content -LiteralPath $taskBackup -Raw) -Force | Out-Null
                $restoredPreviousTask = $true
            }
        }
    }
}

if (-not $restoredPreviousTask -and (Test-Path -LiteralPath $runtimeRoot)) {
    if ($PSCmdlet.ShouldProcess($runtimeRoot, 'Remove the installed per-user startup-guard runtime')) {
        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
    }
}

if ($RestoreQuarantinedStartupEntries) {
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $snapshots = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups\startup-guard') -Filter actions.json -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName
    foreach ($snapshotFile in $snapshots) {
        $snapshot = Get-Content -LiteralPath $snapshotFile.FullName -Raw | ConvertFrom-Json
        foreach ($action in @($snapshot.Actions)) {
            if ($action.Type -eq 'RegistryRun' -and $action.Status -eq 'removed') {
                $key = Get-Item -LiteralPath $runPath -ErrorAction SilentlyContinue
                $exists = $key -and ($key.GetValueNames() -contains $action.Name)
                if (-not $exists -and $PSCmdlet.ShouldProcess("$runPath::$($action.Name)", 'Restore quarantined startup value')) {
                    if (-not (Test-Path -LiteralPath $runPath)) { New-Item -Path $runPath -Force | Out-Null }
                    New-ItemProperty -LiteralPath $runPath -Name $action.Name -Value $action.Value -PropertyType $action.Kind -Force | Out-Null
                }
            }
            elseif ($action.Type -eq 'StartupItem' -and $action.Status -eq 'moved' -and $action.QuarantinePath) {
                if ((Test-Path -LiteralPath $action.QuarantinePath) -and -not (Test-Path -LiteralPath $action.OriginalPath)) {
                    if ($PSCmdlet.ShouldProcess($action.OriginalPath, 'Restore quarantined Startup-folder item')) {
                        Move-Item -LiteralPath $action.QuarantinePath -Destination $action.OriginalPath
                    }
                }
            }
        }
    }
}

if ($WhatIfPreference) {
    Write-Host 'Startup guard removal preview complete; no changes were made.' -ForegroundColor Yellow
}
else {
    Write-Host 'Startup guard removed. Use Rollback-Barebones.ps1 if removed inbox apps also need to be restored.' -ForegroundColor Green
}
