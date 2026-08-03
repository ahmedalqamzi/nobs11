#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$NoExplorerRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-native-taskbar"
$backupPath = Join-Path $backupRoot 'registry.json'
$originalBackupPath = Join-Path $projectRoot 'backups\native-taskbar-original\registry.json'
$applyWarnings = [System.Collections.Generic.List[string]]::new()

$settings = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Value = 0; Type = 'DWord'; Description = 'Align taskbar buttons to the left' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Value = 0; Type = 'DWord'; Description = 'Hide Task View button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Value = 0; Type = 'DWord'; Description = 'Hide Widgets button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Value = 0; Type = 'DWord'; Description = 'Hide Chat button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'PeopleBand'; Value = 0; Type = 'DWord'; Description = 'Hide People button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Value = 0; Type = 'DWord'; Description = 'Hide Copilot button' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarGlomLevel'; Value = 0; Type = 'DWord'; Description = 'Always group taskbar buttons' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'MMTaskbarGlomLevel'; Value = 0; Type = 'DWord'; Description = 'Always group buttons on secondary taskbars' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'MMTaskbarEnabled'; Value = 1; Type = 'DWord'; Description = 'Show the native taskbar on every monitor' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarBadges'; Value = 0; Type = 'DWord'; Description = 'Hide notification badges' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarSd'; Value = 1; Type = 'DWord'; Description = 'Keep the Show desktop corner' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSecondsInSystemClock'; Value = 0; Type = 'DWord'; Description = 'Use a quiet minute-resolution clock' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Value = 0; Type = 'DWord'; Description = 'Hide the search box; Win+S remains available' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Value = 0; Type = 'DWord'; Description = 'Use the dark system shell' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Value = 0; Type = 'DWord'; Description = 'Use dark application chrome' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Value = 1; Type = 'DWord'; Description = 'Enable the native taskbar transparency effect' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'ColorPrevalence'; Value = 0; Type = 'DWord'; Description = 'Keep the taskbar neutral instead of forcing an accent color' }
)

$snapshot = [System.Collections.Generic.List[object]]::new()
foreach ($setting in $settings) {
    $key = Get-Item -LiteralPath $setting.Path -ErrorAction SilentlyContinue
    $exists = $key -and ($key.GetValueNames() -contains $setting.Name)
    $snapshot.Add([ordered]@{
        Path = $setting.Path
        Name = $setting.Name
        Existed = [bool]$exists
        Value = if ($exists) { $key.GetValue($setting.Name) } else { $null }
        Kind = if ($exists) { $key.GetValueKind($setting.Name).ToString() } else { $null }
    })
}

$stuckRectPaths = [System.Collections.Generic.List[string]]::new()
$primaryStuckRects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
if (Test-Path -LiteralPath $primaryStuckRects) {
    $stuckRectPaths.Add($primaryStuckRects)
}
$multiMonitorStuckRects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MMStuckRects3'
if (Test-Path -LiteralPath $multiMonitorStuckRects) {
    foreach ($key in Get-ChildItem -LiteralPath $multiMonitorStuckRects -ErrorAction SilentlyContinue) {
        $stuckRectPaths.Add($key.PSPath)
    }
}

foreach ($path in $stuckRectPaths) {
    $value = (Get-ItemProperty -LiteralPath $path -Name Settings -ErrorAction SilentlyContinue).Settings
    if ($value) {
        $snapshot.Add([ordered]@{
            Path = $path
            Name = 'Settings'
            Existed = $true
            ValueBase64 = [Convert]::ToBase64String([byte[]]$value)
            Kind = 'Binary'
        })
    }
}

if ($PSCmdlet.ShouldProcess($backupRoot, 'Save the current native taskbar registry state')) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $backupPath -Encoding utf8NoBOM
}
if (-not (Test-Path -LiteralPath $originalBackupPath)) {
    if ($PSCmdlet.ShouldProcess($originalBackupPath, 'Preserve the original pre-managed taskbar state')) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $originalBackupPath) -Force | Out-Null
        $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $originalBackupPath -Encoding utf8NoBOM
    }
}

foreach ($setting in $settings) {
    if ($PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)", $setting.Description)) {
        try {
            if (-not (Test-Path -LiteralPath $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
            }
            New-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value $setting.Value -PropertyType $setting.Type -Force | Out-Null
        }
        catch {
            $applyWarnings.Add("$($setting.Name): $($_.Exception.Message)")
            Write-Warning "Windows protected $($setting.Name); continuing with the remaining native taskbar settings."
        }
    }
}

# StuckRects3 stores auto-hide in the low bit of byte 8. Preserve the taskbar
# edge, monitor geometry, and all other flags while clearing only auto-hide.
foreach ($path in $stuckRectPaths) {
    [byte[]]$settingsBytes = (Get-ItemProperty -LiteralPath $path -Name Settings -ErrorAction SilentlyContinue).Settings
    if ($settingsBytes -and $settingsBytes.Length -gt 8) {
        $updatedBytes = [byte[]]$settingsBytes.Clone()
        $updatedBytes[8] = [byte]($updatedBytes[8] -band 0xFE)
        if ($PSCmdlet.ShouldProcess("$path\Settings", 'Disable native taskbar auto-hide')) {
            try {
                Set-ItemProperty -LiteralPath $path -Name Settings -Value $updatedBytes
            }
            catch {
                $applyWarnings.Add("$path\Settings: $($_.Exception.Message)")
                Write-Warning "Windows protected the saved taskbar geometry; Explorer visibility will still be restored directly."
            }
        }
    }
}

if (-not ('NativeTaskbarConfiguration' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeTaskbarConfiguration {
    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder className, int capacity);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);

    public static int ShowTaskbars() {
        int shown = 0;
        EnumWindows((window, parameter) => {
            StringBuilder className = new StringBuilder(64);
            GetClassName(window, className, className.Capacity);
            string value = className.ToString();
            if (value == "Shell_TrayWnd" || value == "Shell_SecondaryTrayWnd") {
                ShowWindow(window, 5);
                shown++;
            }
            return true;
        }, IntPtr.Zero);
        return shown;
    }
}
'@
}

if (-not $WhatIfPreference) {
    [void][NativeTaskbarConfiguration]::ShowTaskbars()
}

if (-not $NoExplorerRestart -and $PSCmdlet.ShouldProcess('explorer.exe', 'Restart Explorer so native taskbar settings take effect')) {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 750
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe')
    }

    $deadline = (Get-Date).AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 250
        $shown = [NativeTaskbarConfiguration]::ShowTaskbars()
    } while ($shown -eq 0 -and (Get-Date) -lt $deadline)
}

if ($applyWarnings.Count -gt 0) {
    Write-Warning "Native taskbar configured with $($applyWarnings.Count) protected cosmetic value(s): $($applyWarnings -join '; ')"
}
Write-Host "Native Windows taskbar configured. Backup: $backupPath" -ForegroundColor Green
