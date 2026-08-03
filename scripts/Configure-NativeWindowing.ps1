#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-native-windowing"
$backupPath = Join-Path $backupRoot 'registry.json'
$settings = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SnapAssist'; Value = 1; Type = 'DWord'; Description = 'Show suggested windows after snapping' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'EnableSnapBar'; Value = 1; Type = 'DWord'; Description = 'Show Snap layouts at the top edge' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'EnableSnapAssistFlyout'; Value = 1; Type = 'DWord'; Description = 'Show Snap layouts from the maximize button' },
    @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'WindowArrangementActive'; Value = '1'; Type = 'String'; Description = 'Enable native edge snapping' }
)

$snapshot = [System.Collections.Generic.List[object]]::new()
foreach ($setting in $settings) {
    $key = Get-Item -LiteralPath $setting.Path -ErrorAction SilentlyContinue
    $exists = $key -and $key.GetValueNames() -contains $setting.Name
    $snapshot.Add([pscustomobject]@{
        Path = $setting.Path
        Name = $setting.Name
        Existed = [bool]$exists
        Value = if ($exists) { $key.GetValue($setting.Name) } else { $null }
        Kind = if ($exists) { $key.GetValueKind($setting.Name).ToString() } else { $null }
    })
}

if (-not $WhatIfPreference -and $PSCmdlet.ShouldProcess($backupPath, 'Save native windowing registry state')) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backupPath -Encoding utf8NoBOM
}

foreach ($setting in $settings) {
    if ($PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)", $setting.Description)) {
        if (-not (Test-Path -LiteralPath $setting.Path)) { New-Item -Path $setting.Path -Force | Out-Null }
        New-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value $setting.Value -PropertyType $setting.Type -Force | Out-Null
    }
}

if ($WhatIfPreference) {
    Write-Host 'Native windowing preview complete; no settings were changed.' -ForegroundColor Yellow
}
else {
    Write-Host "Native Windows Snap configured. Backup: $backupPath" -ForegroundColor Green
}
