#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [switch]$SkipPackages,
    [switch]$IncludeBrowserTuning,
    [switch]$IncludeStartupGuard,
    [string[]]$DisableStartupApp,
    [string[]]$UninstallApp,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$projectRoot = Split-Path -Parent $PSCommandPath
$runner = Join-Path $projectRoot 'scripts\Invoke-Pwsh.ps1'
$wingetManifest = Join-Path $projectRoot 'manifests\winget-packages.json'
$pacmanManifest = Join-Path $projectRoot 'manifests\pacman-explicit.txt'
$optionalCatalogPath = Join-Path $projectRoot 'config\optional-apps.json'

function Write-Stage {
    param(
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][string]$Message
    )

    Write-Host "`n[$Number/5] $Message" -ForegroundColor Cyan
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$Description
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE. Review the preceding output and retained rollback data."
    }
}

function Invoke-ProjectScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $runner,
        '-ScriptPath', $ScriptPath
    ) + $ArgumentList
    Invoke-CheckedCommand -FilePath 'powershell.exe' -ArgumentList $arguments -Description $ScriptPath
}

function Get-WinGetPath {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }

    $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }

    throw 'WinGet was not found. Install or update App Installer from Microsoft Store, then run this installer again.'
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Read-OptionalAppSelection {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Apps
    )

    $answer = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($answer)) { return @() }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($token in @($answer -split '[,\s]+' | Where-Object { $_ })) {
        if ($token -match '^\d+$') {
            $index = [int]$token - 1
            if ($index -lt 0 -or $index -ge $Apps.Count) { throw "Optional-app number is out of range: $token" }
            $names.Add([string]$Apps[$index].name)
            continue
        }

        $match = @($Apps | Where-Object { $_.name -eq $token })
        if ($match.Count -ne 1) { throw "Unknown optional app: $token" }
        $names.Add([string]$match[0].name)
    }
    return @($names | Select-Object -Unique)
}

$optionalAppManager = Join-Path $projectRoot 'scripts\Manage-OptionalApps.ps1'
foreach ($requiredFile in @($runner, $wingetManifest, $pacmanManifest, $optionalAppManager, $optionalCatalogPath, (Join-Path $projectRoot 'scripts\Apply-Config.ps1'), (Join-Path $projectRoot 'scripts\Install-AppControl.ps1'), (Join-Path $projectRoot 'scripts\Manage-InstalledApps.ps1'), (Join-Path $projectRoot 'scripts\Workstation-App-Control.ps1'))) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Installer source is incomplete: $requiredFile"
    }
}

$optionalCatalog = Get-Content -LiteralPath $optionalCatalogPath -Raw | ConvertFrom-Json
$optionalApps = @($optionalCatalog.apps)
$knownOptionalAppNames = @($optionalApps | ForEach-Object { [string]$_.name })
$DisableStartupApp = @($DisableStartupApp | ForEach-Object { $_ -split '[,\s]+' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
$UninstallApp = @($UninstallApp | ForEach-Object { $_ -split '[,\s]+' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
$unknownOptionalAppNames = @($DisableStartupApp + $UninstallApp | Where-Object { $_ -notin $knownOptionalAppNames } | Select-Object -Unique)
if ($unknownOptionalAppNames.Count -gt 0) {
    throw "Unknown optional app name(s): $($unknownOptionalAppNames -join ', '). Available names: $($knownOptionalAppNames -join ', ')"
}

if (-not $Force -and -not $WhatIfPreference -and $DisableStartupApp.Count -eq 0 -and $UninstallApp.Count -eq 0) {
    Write-Host ''
    Write-Host 'Optional existing-app control (press Enter twice to keep everything)' -ForegroundColor Cyan
    for ($index = 0; $index -lt $optionalApps.Count; $index++) {
        Write-Host ('  {0}. {1,-22} {2}' -f ($index + 1), $optionalApps[$index].name, $optionalApps[$index].description)
    }
    Write-Host ''
    $DisableStartupApp = @(Read-OptionalAppSelection -Prompt 'Disable startup/background activity (numbers or names, comma-separated)' -Apps $optionalApps)
    $UninstallApp = @(Read-OptionalAppSelection -Prompt 'Uninstall applications (numbers or names, comma-separated)' -Apps $optionalApps)
}

$overlap = @($DisableStartupApp | Where-Object { $_ -in $UninstallApp })
if ($overlap.Count -gt 0) {
    Write-Warning "Uninstall takes precedence over disable-startup for: $($overlap -join ', ')"
    $DisableStartupApp = @($DisableStartupApp | Where-Object { $_ -notin $overlap })
}
if ('overwolf' -in $UninstallApp -and 'mobalytics' -notin $UninstallApp) {
    Write-Warning 'Mobalytics depends on Overwolf and may stop working or be removed. Include mobalytics too if neither application is wanted.'
}

$windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
if ([int]$windows.CurrentBuild -lt 22000) {
    throw "Windows 11 is required. Detected build: $($windows.CurrentBuild)."
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'A 64-bit Windows installation is required.'
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdministrator) {
    throw 'Run this installer from a normal, non-administrator PowerShell window so the desktop configuration is applied to your user account. Package installers can request elevation when needed.'
}

$steps = [System.Collections.Generic.List[string]]::new()
if ($SkipPackages) {
    $steps.Add('Keep existing applications and verify that required packages are already installed')
}
else {
    $steps.Add('Install missing curated Windows applications with WinGet (existing apps are not upgraded)')
    $steps.Add('Fully update MSYS2, then install the curated Unix command-line packages')
}
$steps.Add('Back up and apply the shell, terminal, native Snap, native taskbar, and ongoing App Control panel')
if ($IncludeBrowserTuning) { $steps.Add('Back up and apply the optional Brave/Firefox low-memory preferences') }
if ($IncludeStartupGuard) { $steps.Add('Install the explicit-blocklist startup guard; application removal remains disabled') }
if ($DisableStartupApp.Count -gt 0) { $steps.Add("Stop and disable startup for: $($DisableStartupApp -join ', ')") }
if ($UninstallApp.Count -gt 0) { $steps.Add("Explicitly uninstall: $($UninstallApp -join ', ')") }

Write-Host ''
Write-Host 'Windows Linux Workstation installer' -ForegroundColor White
Write-Host "Windows $($windows.DisplayVersion), build $($windows.CurrentBuild).$($windows.UBR)" -ForegroundColor DarkGray
Write-Host ''
for ($index = 0; $index -lt $steps.Count; $index++) {
    Write-Host ('  {0}. {1}' -f ($index + 1), $steps[$index])
}
Write-Host ''
if ($UninstallApp.Count -eq 0) {
    Write-Host 'Default safety boundary: no Windows apps, services, features, or security controls are removed.' -ForegroundColor Green
}
else {
    Write-Host 'Only the applications explicitly named for uninstall will be removed.' -ForegroundColor Yellow
}
Write-Host 'WinGet source and package agreements are accepted for the curated package import.' -ForegroundColor DarkGray

if ($WhatIfPreference) {
    foreach ($step in $steps) {
        [void]$PSCmdlet.ShouldProcess('current user', $step)
    }
    Write-Host "`nPreview complete. No packages or settings were changed." -ForegroundColor Yellow
    return
}

if (-not $Force) {
    $continue = $PSCmdlet.ShouldContinue(
        'The standard profile changes current-user configuration and restarts Explorer after creating rollback data. Continue?',
        'Install Windows Linux Workstation?'
    )
    if (-not $continue) {
        Write-Host 'Installation canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

Write-Stage 1 'Checking the source and Windows environment'
Write-Host "Source: $projectRoot"

if (-not $SkipPackages) {
    Write-Stage 2 'Installing curated Windows applications'
    $winget = Get-WinGetPath
    Invoke-CheckedCommand -FilePath $winget -ArgumentList @(
        'import',
        '--import-file', $wingetManifest,
        '--ignore-versions',
        '--no-upgrade',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    ) -Description 'WinGet package import'
    Update-ProcessPath

    Write-Stage 3 'Updating MSYS2 and installing Unix tools'
    $bash = 'C:\msys64\usr\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
        throw 'MSYS2 was not found at C:\msys64 after the WinGet import.'
    }

    $packages = @(Get-Content -LiteralPath $pacmanManifest | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    $invalidPackages = @($packages | Where-Object { $_ -notmatch '^[A-Za-z0-9@._+:-]+$' })
    if ($invalidPackages.Count -gt 0) {
        throw "The MSYS2 package manifest contains unsafe package names: $($invalidPackages -join ', ')"
    }

    $previousMsystem = $env:MSYSTEM
    $previousChere = $env:CHERE_INVOKING
    try {
        $env:MSYSTEM = 'UCRT64'
        $env:CHERE_INVOKING = 'yes'
        Invoke-CheckedCommand -FilePath $bash -ArgumentList @('-lc', ' ') -Description 'MSYS2 initialization'

        for ($attempt = 1; $attempt -le 2; $attempt++) {
            & $bash -lc 'pacman --noconfirm -Syuu'
            if ($LASTEXITCODE -ne 0 -and $attempt -eq 2) {
                throw "MSYS2 full-system update failed with exit code $LASTEXITCODE."
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Warning 'The first MSYS2 update pass requested a shell restart; continuing with the required second pass.'
            }
        }

        $packageCommand = 'pacman --noconfirm --needed -S ' + ($packages -join ' ')
        Invoke-CheckedCommand -FilePath $bash -ArgumentList @('-lc', $packageCommand) -Description 'MSYS2 package installation'
    }
    finally {
        $env:MSYSTEM = $previousMsystem
        $env:CHERE_INVOKING = $previousChere
    }
}
else {
    Write-Stage 2 'Skipping package installation as requested'
    Write-Stage 3 'Using the existing MSYS2 environment'
}

Write-Stage 4 'Validating prerequisites and applying the desktop profile'
Invoke-ProjectScript -ScriptPath 'scripts\Test-Prerequisites.ps1'
Invoke-ProjectScript -ScriptPath 'scripts\Apply-Config.ps1'

if ($IncludeBrowserTuning) {
    Invoke-ProjectScript -ScriptPath 'scripts\Configure-Brave.ps1'
}
if ($IncludeStartupGuard) {
    Invoke-ProjectScript -ScriptPath 'scripts\Install-StartupGuard.ps1' -ArgumentList @('-Force')
}
if ($DisableStartupApp.Count -gt 0) {
    Invoke-ProjectScript -ScriptPath 'scripts\Manage-OptionalApps.ps1' -ArgumentList @('-Action', 'DisableStartup', '-Name', ($DisableStartupApp -join ','), '-Force')
}
if ($UninstallApp.Count -gt 0) {
    Invoke-ProjectScript -ScriptPath 'scripts\Manage-OptionalApps.ps1' -ArgumentList @('-Action', 'Uninstall', '-Name', ($UninstallApp -join ','), '-Force')
}

Write-Stage 5 'Installation complete'
Write-Host 'The Linux-style shell and native Windows desktop are ready; Windows remains the only operating-system kernel.' -ForegroundColor Green
Write-Host "Source and rollback data: $projectRoot"
Write-Host 'Use Workstation App Control from the Start menu for ongoing app, startup, and process management.'
Write-Host 'Sign out and back in once to confirm startup behavior, then run make verify from UCRT64 Bash.'
