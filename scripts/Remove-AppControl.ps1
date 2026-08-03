#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$runtimeRoot = Join-Path $env:LOCALAPPDATA 'WindowsLinuxWorkstation'
$runtimeFiles = @(
    Join-Path $runtimeRoot 'scripts\Workstation-App-Control.ps1'
    Join-Path $runtimeRoot 'scripts\Manage-OptionalApps.ps1'
    Join-Path $runtimeRoot 'scripts\Manage-InstalledApps.ps1'
    Join-Path $runtimeRoot 'scripts\Manage-UserStartup.ps1'
    Join-Path $runtimeRoot 'config\optional-apps.json'
)
$startMenuFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Windows Linux Workstation'
$shortcutPaths = @(
    Join-Path ([Environment]::GetFolderPath('Desktop')) 'Workstation App Control.lnk'
    Join-Path $startMenuFolder 'Workstation App Control.lnk'
)

if (-not $Force -and -not $WhatIfPreference) {
    if (-not $PSCmdlet.ShouldContinue('Remove the App Control launchers and runtime code? Saved startup state and backups will be retained.', 'Remove Workstation App Control')) {
        Write-Host 'Removal canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

foreach ($path in @($shortcutPaths + $runtimeFiles)) {
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove Workstation App Control managed file')) {
        Remove-Item -LiteralPath $path -Force
    }
}
if ((Test-Path -LiteralPath $startMenuFolder -PathType Container) -and -not (Get-ChildItem -LiteralPath $startMenuFolder -Force) -and $PSCmdlet.ShouldProcess($startMenuFolder, 'Remove empty Start-menu folder')) {
    Remove-Item -LiteralPath $startMenuFolder -Force
}

Write-Host 'Workstation App Control removed. Saved state and backups remain under %LOCALAPPDATA%\WindowsLinuxWorkstation.' -ForegroundColor Green
