#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$KeepManagedFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$taskName = 'WindowsLinuxWorkstation Zebar Dock Service'
$watchdogScript = Join-Path $env:USERPROFILE '.glzr\glazewm\Watch-ZebarDock.ps1'
$detachedLauncher = Join-Path $env:USERPROFILE '.glzr\glazewm\Start-ZebarDetached.ps1'
$userGlzrRoot = Join-Path $env:USERPROFILE '.glzr'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$archiveRoot = Join-Path $projectRoot "backups\$stamp-retired-zebar"

function Resolve-ChildPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to move a path outside the expected root '$fullRoot': $fullPath"
    }
    $fullPath
}

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($taskName, 'Stop and unregister the Zebar dock supervisor')) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}

$watchdogProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -in @('powershell.exe', 'pwsh.exe', 'wscript.exe') -and
        ($_.CommandLine -like "*$watchdogScript*" -or $_.CommandLine -like "*$detachedLauncher*")
    }
foreach ($process in $watchdogProcesses) {
    if ($PSCmdlet.ShouldProcess("PID $($process.ProcessId)", 'Stop the Zebar dock watchdog process')) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

foreach ($process in Get-Process -Name zebar -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess("PID $($process.Id)", 'Stop the retired Zebar taskbar')) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}

$archived = [System.Collections.Generic.List[object]]::new()
if (-not $KeepManagedFiles) {
    $legacyTargets = @(
        @{ Source = $watchdogScript; Relative = 'glazewm\Watch-ZebarDock.ps1' },
        @{ Source = $detachedLauncher; Relative = 'glazewm\Start-ZebarDetached.ps1' },
        @{ Source = (Join-Path $userGlzrRoot 'zebar\linux-bar'); Relative = 'zebar\linux-bar' },
        @{ Source = (Join-Path $userGlzrRoot 'zebar\settings.json'); Relative = 'zebar\settings.json' }
    )

    foreach ($target in $legacyTargets) {
        if (-not (Test-Path -LiteralPath $target.Source)) { continue }

        $source = Resolve-ChildPath -Path $target.Source -Root $userGlzrRoot
        $destination = Resolve-ChildPath -Path (Join-Path $archiveRoot $target.Relative) -Root $archiveRoot
        if ($PSCmdlet.ShouldProcess($source, "Archive retired managed file to $destination")) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Move-Item -LiteralPath $source -Destination $destination
            $archived.Add([ordered]@{ OriginalPath = $source; ArchivePath = $destination })
        }
    }
}

if ($archived.Count -gt 0) {
    $manifest = [ordered]@{
        ArchivedAt = (Get-Date).ToString('o')
        Items = $archived
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $archiveRoot 'manifest.json') -Encoding utf8NoBOM
}

if ($WhatIfPreference) {
    Write-Host 'Retired Zebar taskbar removal preview complete; no changes were made.' -ForegroundColor Yellow
}
elseif ($archived.Count -gt 0) {
    Write-Host "Retired Zebar taskbar removed; managed files were archived to $archiveRoot. Explorer remains the only active taskbar." -ForegroundColor Yellow
}
else {
    Write-Host 'Retired Zebar taskbar service removed and Zebar stopped; no managed dock files remained. Explorer remains the only active taskbar.' -ForegroundColor Yellow
}
