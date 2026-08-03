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
$startMenuFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'NoBS11'
$legacyStartMenuFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Windows Linux Workstation'
$shortcutPaths = @(
    Join-Path ([Environment]::GetFolderPath('Desktop')) 'Workstation App Control.lnk'
    Join-Path ([Environment]::GetFolderPath('Desktop')) 'NoBS11 Control.lnk'
    Join-Path $startMenuFolder 'Workstation App Control.lnk'
    Join-Path $startMenuFolder 'NoBS11 Control.lnk'
    Join-Path $legacyStartMenuFolder 'Workstation App Control.lnk'
)

if (-not $Force -and -not $WhatIfPreference) {
    if (-not $PSCmdlet.ShouldContinue('Remove the NoBS11 Control launchers and runtime code? Saved startup state and backups will be retained.', 'Remove NoBS11 Control')) {
        Write-Host 'Removal canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

foreach ($path in @($shortcutPaths + $runtimeFiles)) {
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove NoBS11 Control managed file')) {
        Remove-Item -LiteralPath $path -Force
    }
}
foreach ($folder in @($startMenuFolder, $legacyStartMenuFolder)) {
    if ((Test-Path -LiteralPath $folder -PathType Container) -and -not (Get-ChildItem -LiteralPath $folder -Force) -and $PSCmdlet.ShouldProcess($folder, 'Remove empty Start-menu folder')) {
        Remove-Item -LiteralPath $folder -Force
    }
}

Write-Host 'NoBS11 Control removed. Saved state and backups remain under the compatibility runtime path in %LOCALAPPDATA%.' -ForegroundColor Green
