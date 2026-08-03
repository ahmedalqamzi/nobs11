#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$IncludeAppRemoval,
    [switch]$SkipInitialRun,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$guardScript = Join-Path $PSScriptRoot 'Enforce-StartupPolicy.ps1'
$braveScript = Join-Path $PSScriptRoot 'Configure-Brave.ps1'
$configPath = Join-Path $projectRoot 'config\startup-policy.json'
$firefoxConfig = Join-Path $projectRoot 'dotfiles\firefox\user.js'
$taskName = 'WindowsLinuxWorkstation Startup Guard'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-startup-guard"
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'WindowsLinuxWorkstation'
$runtimeScripts = Join-Path $runtimeRoot 'scripts'
$runtimeConfig = Join-Path $runtimeRoot 'config'
$runtimeFirefox = Join-Path $runtimeRoot 'dotfiles\firefox'
$installedGuardScript = Join-Path $runtimeScripts 'Enforce-StartupPolicy.ps1'
$installedBraveScript = Join-Path $runtimeScripts 'Configure-Brave.ps1'
$installedPolicy = Join-Path $runtimeConfig 'startup-policy.json'
$installedFirefoxConfig = Join-Path $runtimeFirefox 'user.js'

if (-not (Test-Path -LiteralPath $guardScript)) { throw "Guard script not found: $guardScript" }
if (-not (Test-Path -LiteralPath $braveScript)) { throw "Brave policy script not found: $braveScript" }
if (-not (Test-Path -LiteralPath $configPath)) { throw "Guard config not found: $configPath" }

if (-not $WhatIfPreference -and -not $Force) {
    $warning = 'This installs a scheduled task that enforces the explicit startup, process, scheduled-task, registry, and browser policy at logon and every six hours.'
    if ($IncludeAppRemoval) { $warning += ' App-package removal is enabled for this task.' }
    if (-not $PSCmdlet.ShouldContinue($warning, 'Install persistent startup enforcement?')) {
        Write-Host 'Startup guard installation canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$replacedTaskPath = $null
if ($existing -and -not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $replacedTaskPath = Join-Path $backupRoot 'replaced-managed-task.xml'
    Export-ScheduledTask -TaskName $taskName | Set-Content -LiteralPath $replacedTaskPath -Encoding utf8NoBOM
}

if ($PSCmdlet.ShouldProcess($runtimeRoot, 'Install the startup guard into a stable per-user runtime directory')) {
    New-Item -ItemType Directory -Path $runtimeScripts, $runtimeConfig, $runtimeFirefox -Force | Out-Null
    Copy-Item -LiteralPath $guardScript -Destination $installedGuardScript -Force
    Copy-Item -LiteralPath $braveScript -Destination $installedBraveScript -Force
    Copy-Item -LiteralPath $configPath -Destination $installedPolicy -Force
    if (Test-Path -LiteralPath $firefoxConfig) {
        Copy-Item -LiteralPath $firefoxConfig -Destination $installedFirefoxConfig -Force
    }
}

$pwshPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
if (-not (Test-Path -LiteralPath $pwshPath)) {
    $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$argumentParts = @('-NoLogo', '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $installedGuardScript))
if ($IncludeAppRemoval) { $argumentParts += '-IncludeAppRemoval' }
$arguments = $argumentParts -join ' '
$action = New-ScheduledTaskAction -Execute $pwshPath -Argument $arguments -WorkingDirectory $runtimeRoot
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
$repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited

if ($PSCmdlet.ShouldProcess($taskName, 'Register current-user startup guard at logon and every 6 hours')) {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logonTrigger, $repeatTrigger) -Settings $settings -Principal $principal -Description 'Enforces the low-memory startup, task, background-process, registry, and inbox-app policy at logon and every six hours.' -Force | Out-Null
}

$manifest = [ordered]@{
    InstalledAt = (Get-Date).ToString('o')
    TaskName = $taskName
    PowerShell = $pwshPath
    RuntimeRoot = $runtimeRoot
    GuardScript = $installedGuardScript
    Policy = $installedPolicy
    ReplacedTaskBackup = $replacedTaskPath
    RunEveryHours = 6
    IncludeAppRemoval = [bool]$IncludeAppRemoval
}
if (-not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backupRoot 'manifest.json') -Encoding utf8NoBOM
}

if (-not $WhatIfPreference -and -not $SkipInitialRun) {
    $initialArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $installedGuardScript)
    if ($IncludeAppRemoval) { $initialArguments += '-IncludeAppRemoval' }
    & $pwshPath @initialArguments
    if ($LASTEXITCODE -notin @(0, $null)) { throw "Initial startup-guard run exited with code $LASTEXITCODE" }
}

if ($WhatIfPreference) {
    Write-Host 'Startup guard installation preview complete; no changes were made.' -ForegroundColor Yellow
}
else {
    Write-Host "Startup guard installed. Backup: $backupRoot" -ForegroundColor Green
}
