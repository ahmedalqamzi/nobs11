#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Launch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'WindowsLinuxWorkstation'
$runtimeScripts = Join-Path $runtimeRoot 'scripts'
$runtimeConfig = Join-Path $runtimeRoot 'config'
$sourceFiles = [ordered]@{
    (Join-Path $PSScriptRoot 'Workstation-App-Control.ps1') = (Join-Path $runtimeScripts 'Workstation-App-Control.ps1')
    (Join-Path $PSScriptRoot 'Manage-OptionalApps.ps1') = (Join-Path $runtimeScripts 'Manage-OptionalApps.ps1')
    (Join-Path $PSScriptRoot 'Manage-InstalledApps.ps1') = (Join-Path $runtimeScripts 'Manage-InstalledApps.ps1')
    (Join-Path $PSScriptRoot 'Manage-UserStartup.ps1') = (Join-Path $runtimeScripts 'Manage-UserStartup.ps1')
    (Join-Path $projectRoot 'config\optional-apps.json') = (Join-Path $runtimeConfig 'optional-apps.json')
}
$missing = @($sourceFiles.Keys | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) { throw "App Control source is incomplete: $($missing -join ', ')" }

$pwshPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
if (-not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) {
    $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
}

$programsPath = [Environment]::GetFolderPath('Programs')
$startMenuFolder = Join-Path $programsPath 'NoBS11'
$shortcutPaths = @(Join-Path $startMenuFolder 'NoBS11 Control.lnk')
$legacyStartMenuFolder = Join-Path $programsPath 'Windows Linux Workstation'
$legacyShortcuts = @(
    Join-Path ([Environment]::GetFolderPath('Desktop')) 'Workstation App Control.lnk'
    Join-Path ([Environment]::GetFolderPath('Desktop')) 'NoBS11 Control.lnk'
    Join-Path $legacyStartMenuFolder 'Workstation App Control.lnk'
)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-app-control"
$manifest = [ordered]@{
    InstalledAt = (Get-Date).ToString('o')
    RuntimeRoot = $runtimeRoot
    Files = [Collections.Generic.List[object]]::new()
    Shortcuts = [Collections.Generic.List[object]]::new()
    RemovedLegacyShortcuts = [Collections.Generic.List[object]]::new()
}

foreach ($entry in $sourceFiles.GetEnumerator()) {
    $source = [string]$entry.Key
    $destination = [string]$entry.Value
    $backup = $null
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $backup = Join-Path $backupRoot ("files\{0}" -f [IO.Path]::GetFileName($destination))
        if (-not $WhatIfPreference) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backup -Force
        }
    }
    $manifest.Files.Add([pscustomobject]@{ Source = $source; Destination = $destination; PreviousBackup = $backup })
    if ($PSCmdlet.ShouldProcess($destination, 'Install NoBS11 Control runtime file')) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}

if ($PSCmdlet.ShouldProcess($runtimeRoot, 'Prepare persistent App Control state and backup directories')) {
    New-Item -ItemType Directory -Path (Join-Path $runtimeRoot 'state'), (Join-Path $runtimeRoot 'backups'), (Join-Path $runtimeRoot 'logs') -Force | Out-Null
}

$shortcutArguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $runtimeScripts 'Workstation-App-Control.ps1')
$shell = if (-not $WhatIfPreference) { New-Object -ComObject WScript.Shell } else { $null }

foreach ($legacyShortcut in $legacyShortcuts) {
    if (Test-Path -LiteralPath $legacyShortcut -PathType Leaf) {
        $legacyBackupName = 'legacy-{0}-{1}' -f ([Math]::Abs($legacyShortcut.GetHashCode())), [IO.Path]::GetFileName($legacyShortcut)
        $legacyBackup = Join-Path $backupRoot "shortcuts\$legacyBackupName"
        $manifest.RemovedLegacyShortcuts.Add([pscustomobject]@{ Path = $legacyShortcut; Backup = $legacyBackup })
        if ($PSCmdlet.ShouldProcess($legacyShortcut, 'Remove retired launcher; NoBS11 Control is Start-menu only')) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $legacyBackup) -Force | Out-Null
            Copy-Item -LiteralPath $legacyShortcut -Destination $legacyBackup -Force
            Remove-Item -LiteralPath $legacyShortcut -Force
        }
    }
}
if ((Test-Path -LiteralPath $legacyStartMenuFolder -PathType Container) -and -not (Get-ChildItem -LiteralPath $legacyStartMenuFolder -Force) -and $PSCmdlet.ShouldProcess($legacyStartMenuFolder, 'Remove the empty legacy Start-menu folder')) {
    Remove-Item -LiteralPath $legacyStartMenuFolder -Force
}

foreach ($shortcutPath in $shortcutPaths) {
    $backup = $null
    if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
        $backup = Join-Path $backupRoot ("shortcuts\{0}" -f [IO.Path]::GetFileName($shortcutPath))
        if (-not $WhatIfPreference) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Copy-Item -LiteralPath $shortcutPath -Destination $backup -Force
        }
    }
    $manifest.Shortcuts.Add([pscustomobject]@{ Path = $shortcutPath; PreviousBackup = $backup })
    if ($PSCmdlet.ShouldProcess($shortcutPath, 'Create NoBS11 Control shortcut')) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $shortcutPath) -Force | Out-Null
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $pwshPath
        $shortcut.Arguments = $shortcutArguments
        $shortcut.WorkingDirectory = $runtimeRoot
        $shortcut.Description = 'Ongoing app, startup, and background control for NoBS11'
        $shortcut.IconLocation = "$(Join-Path $env:WINDIR 'System32\shell32.dll'),167"
        $shortcut.WindowStyle = 1
        $shortcut.Save()
    }
}

if (-not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backupRoot 'manifest.json') -Encoding utf8NoBOM
}

if ($Launch -and -not $WhatIfPreference) {
    Start-Process -FilePath $pwshPath -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f (Join-Path $runtimeScripts 'Workstation-App-Control.ps1')))
}

if ($WhatIfPreference) {
    Write-Host 'NoBS11 Control installation preview complete; no files or shortcuts were changed.' -ForegroundColor Yellow
}
else {
    Write-Host "NoBS11 Control installed. Start shortcut: $($shortcutPaths[0])" -ForegroundColor Green
}
