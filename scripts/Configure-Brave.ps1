#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$AuditOnly,
    [switch]$NoBackup,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$userDataRoot = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
$localStatePath = Join-Path $userDataRoot 'Local State'
$preferencesPath = Join-Path $userDataRoot 'Default\Preferences'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-brave-profile"
$results = [System.Collections.Generic.List[object]]::new()
$script:configureBraveCmdlet = $PSCmdlet

function Set-NestedValue {
    param(
        [Parameter(Mandatory)][hashtable]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    $segments = $Path -split '\.'
    $cursor = $Root
    for ($index = 0; $index -lt $segments.Count - 1; $index++) {
        $segment = $segments[$index]
        if (-not $cursor.ContainsKey($segment) -or $cursor[$segment] -isnot [hashtable]) {
            $cursor[$segment] = @{}
        }
        $cursor = $cursor[$segment]
    }

    $leaf = $segments[-1]
    $previous = if ($cursor.ContainsKey($leaf)) { $cursor[$leaf] } else { $null }
    $changed = -not $cursor.ContainsKey($leaf) -or ($previous | ConvertTo-Json -Compress -Depth 20) -cne ($Value | ConvertTo-Json -Compress -Depth 20)
    if ($changed -and -not $AuditOnly) {
        $cursor[$leaf] = $Value
    }
    $changed
}

function Set-JsonPreferences {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$BackupName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $results.Add([pscustomobject]@{ File = $Path; Status = 'missing'; Changes = 0 })
        return
    }

    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $changes = 0
    $changedPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $Values.GetEnumerator()) {
        if (Set-NestedValue -Root $settings -Path $entry.Key -Value $entry.Value) {
            $changes++
            $changedPaths.Add($entry.Key)
        }
    }

    if ($changes -eq 0) {
        $results.Add([pscustomobject]@{ File = $Path; Status = 'unchanged'; Changes = 0; Paths = @() })
        return
    }
    if ($AuditOnly) {
        $results.Add([pscustomobject]@{ File = $Path; Status = 'drift'; Changes = $changes; Paths = @($changedPaths) })
        return
    }

    if (-not $script:configureBraveCmdlet.ShouldProcess($Path, "Apply $changes managed browser preference change(s)")) {
        $results.Add([pscustomobject]@{ File = $Path; Status = 'what-if'; Changes = $changes; Paths = @($changedPaths) })
        return
    }

    if (-not $NoBackup) {
        $null = New-Item -ItemType Directory -Path $backupRoot -Force
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupRoot $BackupName) -Force
    }

    $tempPath = "$Path.windows-linux-workstation.tmp"
    try {
        $settings | ConvertTo-Json -Depth 100 -Compress | Set-Content -LiteralPath $tempPath -Encoding utf8NoBOM
        $null = Get-Content -LiteralPath $tempPath -Raw | ConvertFrom-Json -AsHashtable
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
    $results.Add([pscustomobject]@{ File = $Path; Status = 'changed'; Changes = $changes; Paths = @($changedPaths) })
}

if (Get-Process brave -ErrorAction SilentlyContinue) {
    $results.Add([pscustomobject]@{ File = $userDataRoot; Status = 'skipped-running'; Changes = 0 })
}
elseif (-not (Test-Path -LiteralPath $userDataRoot)) {
    $results.Add([pscustomobject]@{ File = $userDataRoot; Status = 'not-installed'; Changes = 0 })
}
else {
    $localStateValues = [ordered]@{
        'background_mode.enabled' = $false
        'brave.p3a.enabled' = $false
        'brave.stats.reporting_enabled' = $false
        'profile.info_cache.Default.background_apps' = $false
        'hardware_acceleration_mode_previous' = $true
    }
    $profileValues = [ordered]@{
        'background_mode.enabled' = $false
        'performance_tuning.high_efficiency_mode.state' = 1
        'performance_tuning.high_efficiency_mode.time_before_discard_in_minutes' = 5
        'brave.p3a.enabled' = $false
        'brave.stats.reporting_enabled' = $false
        'brave.rewards.enabled' = $false
        'brave.rewards.disabled_by_policy' = $true
        'brave.brave_ads.enabled' = $false
        'brave.brave_vpn.disabled_by_policy' = $true
        'brave.brave_vpn.show_button' = $false
        'brave.wallet.disabled_by_policy' = $true
        'brave.wallet.show_wallet_icon_on_toolbar' = $false
        'brave.wallet.should_show_wallet_suggestion_badge' = $false
        'brave.ai_chat.enabled_by_policy' = $false
        'brave.ai_chat.autocomplete_provider_enabled' = $false
        'brave.ai_chat.context_menu_enabled' = $false
        'brave.ai_chat.show_toolbar_button' = $false
        'brave.news.disabled_by_policy' = $true
        'brave.new_tab_page.show_brave_news' = $false
        'brave.today.opted_in' = $false
        'brave.today.should_show_toolbar_button' = $false
        'brave.talk.disabled_by_policy' = $true
        'brave.new_tab_page.show_together' = $false
        'brave.new_tab_page.show_rewards' = $false
        'brave.new_tab_page.show_brave_vpn' = $false
        'brave.new_tab_page.show_sponsored_sites' = $false
        'brave.web_discovery_enabled' = $false
        'brave.enable_media_router_on_restart' = $false
        'brave.enable_window_closing_confirm' = $false
    }

    Set-JsonPreferences -Path $localStatePath -Values $localStateValues -BackupName 'Local State'
    Set-JsonPreferences -Path $preferencesPath -Values $profileValues -BackupName 'Preferences'
}

$firefoxUserJsSource = Join-Path $projectRoot 'dotfiles\firefox\user.js'
$firefoxProfilesRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
$firefoxProfile = Get-ChildItem -LiteralPath $firefoxProfilesRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object Name -like '*.default-release' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ((Test-Path -LiteralPath $firefoxUserJsSource) -and $firefoxProfile) {
    $firefoxUserJsTarget = Join-Path $firefoxProfile.FullName 'user.js'
    if (Get-Process firefox -ErrorAction SilentlyContinue) {
        $results.Add([pscustomobject]@{ File = $firefoxUserJsTarget; Status = 'skipped-running'; Changes = 0; Paths = @() })
    }
    else {
        $matches = (Test-Path -LiteralPath $firefoxUserJsTarget) -and
            ((Get-FileHash -LiteralPath $firefoxUserJsSource -Algorithm SHA256).Hash -eq
                (Get-FileHash -LiteralPath $firefoxUserJsTarget -Algorithm SHA256).Hash)
        if ($matches) {
            $results.Add([pscustomobject]@{ File = $firefoxUserJsTarget; Status = 'unchanged'; Changes = 0; Paths = @() })
        }
        elseif ($AuditOnly) {
            $results.Add([pscustomobject]@{ File = $firefoxUserJsTarget; Status = 'drift'; Changes = 1; Paths = @('Firefox user.js') })
        }
        elseif (-not $PSCmdlet.ShouldProcess($firefoxUserJsTarget, 'Install the managed Firefox user.js')) {
            $results.Add([pscustomobject]@{ File = $firefoxUserJsTarget; Status = 'what-if'; Changes = 1; Paths = @('Firefox user.js') })
        }
        else {
            if (-not $NoBackup -and (Test-Path -LiteralPath $firefoxUserJsTarget)) {
                $null = New-Item -ItemType Directory -Path $backupRoot -Force
                Copy-Item -LiteralPath $firefoxUserJsTarget -Destination (Join-Path $backupRoot 'Firefox-user.js') -Force
            }
            Copy-Item -LiteralPath $firefoxUserJsSource -Destination $firefoxUserJsTarget -Force
            $results.Add([pscustomobject]@{ File = $firefoxUserJsTarget; Status = 'changed'; Changes = 1; Paths = @('Firefox user.js') })
        }
    }
}

$summary = [pscustomobject]@{
    AuditOnly = [bool]$AuditOnly
    Backup = if ((-not $NoBackup) -and (Test-Path -LiteralPath $backupRoot)) { $backupRoot } else { $null }
    Changed = @($results | Where-Object Status -eq 'changed').Count
    Drift = @($results | Where-Object Status -eq 'drift').Count
    WhatIf = @($results | Where-Object Status -eq 'what-if').Count
    Skipped = @($results | Where-Object Status -like 'skipped*').Count
    Results = @($results)
}

if (-not $Quiet) {
    $summary | ConvertTo-Json -Depth 6
}

if ($summary.Drift -gt 0) { exit 2 }
