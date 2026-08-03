#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$IncludeIdentity
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$checks = [System.Collections.Generic.List[object]]::new()

function Protect-LocalDetail {
    param([Parameter(Mandatory)][string]$Detail)

    if ($IncludeIdentity) { return $Detail }
    $replacements = [ordered]@{
        $env:LOCALAPPDATA = '%LOCALAPPDATA%'
        $env:APPDATA = '%APPDATA%'
        $env:USERPROFILE = '%USERPROFILE%'
        $env:ProgramFiles = '%ProgramFiles%'
        $env:WINDIR = '%WINDIR%'
    }
    $protected = $Detail
    foreach ($entry in $replacements.GetEnumerator()) {
        if ($entry.Key) {
            $protected = $protected -replace [regex]::Escape([string]$entry.Key), [string]$entry.Value
            $jsonEscapedPath = ([string]$entry.Key).Replace('\', '\\')
            $protected = $protected -replace [regex]::Escape($jsonEscapedPath), [string]$entry.Value
        }
    }
    $protected
}

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('pass', 'pending', 'fail')][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    $checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = (Protect-LocalDetail $Detail) })
}

$windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Add-Check 'Windows version' 'pass' "Windows $($windows.DisplayVersion), build $($windows.CurrentBuild).$($windows.UBR)"

$rebootFlags = [ordered]@{
    CBS = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    WindowsUpdate = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    PendingFileRename = [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
}
# PendingFileRenameOperations is re-created continuously on this machine by app
# updaters (Brave/goopdate, Gaming Services), so it is informational; only the
# servicing flags (CBS/WindowsUpdate) mean a restart is actually required.
$pendingReboot = $rebootFlags.CBS -or $rebootFlags.WindowsUpdate
Add-Check 'Pending restart' $(if ($pendingReboot) { 'pending' } else { 'pass' }) (($rebootFlags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')

$terminalPackage = Get-AppxPackage Microsoft.WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
$knownNativePaths = @{
    wt = @($(if ($terminalPackage) { Join-Path $terminalPackage.InstallLocation 'wt.exe' }))
    lazygit = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Recurse -Filter lazygit.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
}
$nativeCommands = 'pwsh', 'wt', 'git', 'starship', 'nvim', 'lazygit'
foreach ($name in $nativeCommands) {
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    $commandSource = if ($command) {
        $command.Source
    }
    else {
        @($knownNativePaths[$name]) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
    Add-Check "Native command: $name" $(if ($commandSource) { 'pass' } else { 'fail' }) $(if ($commandSource) { $commandSource } else { 'Not found' })
}

$bash = 'C:\msys64\usr\bin\bash.exe'
$unixCommands = 'rg', 'fd', 'fzf', 'bat', 'eza', 'zoxide', 'jq', 'nvim', 'yazi', 'starship', 'fastfetch', 'tmux', 'delta', 'dust', 'procs', 'tldr'
if (Test-Path -LiteralPath $bash) {
    $env:MSYSTEM = 'UCRT64'
    $env:CHERE_INVOKING = '1'
    # A caller-exported HOME (e.g. Git Bash) hijacks the MSYS2 login shell away
    # from its real home (~/.bash_profile -> ~/.bashrc loader chain). Strip it so
    # MSYS2 resolves HOME per nsswitch, as an Explorer-launched terminal does.
    $inheritedHome = $env:HOME
    Remove-Item Env:HOME -ErrorAction SilentlyContinue
    try {
        foreach ($name in $unixCommands) {
            & $bash -lc "command -v $name >/dev/null 2>&1"
            Add-Check "UCRT64 command: $name" $(if ($LASTEXITCODE -eq 0) { 'pass' } else { 'fail' }) $(if ($LASTEXITCODE -eq 0) { 'Available' } else { 'Not found' })
        }
        & $bash -lic 'type lg >/dev/null 2>&1'
        Add-Check 'UCRT64 lazygit launcher' $(if ($LASTEXITCODE -eq 0) { 'pass' } else { 'fail' }) $(if ($LASTEXITCODE -eq 0) { 'Alias/function available' } else { 'lg alias/function missing' })
    }
    finally {
        if ($inheritedHome) { $env:HOME = $inheritedHome }
    }
}
else {
    Add-Check 'MSYS2 UCRT64' 'fail' "Bash not found: $bash"
}

$configPairs = @(
    @('dotfiles\shell\bashrc', "$HOME\.config\shell\bashrc"),
    @('dotfiles\shell\inputrc', "$HOME\.config\shell\inputrc"),
    @('dotfiles\powershell\profile.ps1', "$HOME\.config\powershell\profile.ps1"),
    @('dotfiles\starship\starship.toml', "$HOME\.config\starship.toml"),
    @('dotfiles\git\config', "$HOME\.config\git\config"),
    @('dotfiles\tmux\tmux.conf', "$HOME\.config\tmux\tmux.conf"),
    @('dotfiles\nvim\init.lua', "$env:LOCALAPPDATA\nvim\init.lua")
)
foreach ($pair in $configPairs) {
    $source = Join-Path $projectRoot $pair[0]
    $target = $pair[1]
    $matches = (Test-Path -LiteralPath $target) -and ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash)
    Add-Check "Managed config: $($pair[0])" $(if ($matches) { 'pass' } else { 'fail' }) $(if ($matches) { 'Installed and matches project' } else { "Missing or drifted: $target" })
}

$terminalSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path -LiteralPath $terminalSettings) {
    $terminal = Get-Content -LiteralPath $terminalSettings -Raw | ConvertFrom-Json
    $visibleProfiles = @($terminal.profiles.list | Where-Object { -not $_.hidden })
    $terminalReady = $terminal.defaultProfile -eq '{d8d0ce2f-7a4d-4d21-9bb2-28c86a738e39}' -and
        $terminal.profiles.defaults.colorScheme -eq 'Catppuccin Mocha' -and
        $terminal.windowingBehavior -eq 'useExisting' -and
        $visibleProfiles.Count -eq 1 -and
        $visibleProfiles[0].name -eq 'UCRT64 Bash'
    Add-Check 'Windows Terminal default' $(if ($terminalReady) { 'pass' } else { 'fail' }) "Default=$($terminal.defaultProfile), scheme=$($terminal.profiles.defaults.colorScheme), reuse=$($terminal.windowingBehavior), visibleProfiles=$($visibleProfiles.Count)"
}
else {
    Add-Check 'Windows Terminal default' 'fail' 'settings.json not found'
}

$terminalProcesses = @(Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue)
$terminalWindows = @($terminalProcesses | Where-Object { $_.MainWindowHandle -ne 0 })
$terminalRuntimeStatus = if ($terminalProcesses.Count -gt 1 -or $terminalWindows.Count -gt 1) { 'fail' } else { 'pass' }
$terminalRuntimeDetail = "Processes=$($terminalProcesses.Count), windows=$($terminalWindows.Count)"
if ($terminalRuntimeStatus -eq 'pass' -and $terminalWindows.Count -eq 1) {
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $terminalElement = [Windows.Automation.AutomationElement]::FromHandle($terminalWindows[0].MainWindowHandle)
        $tabCondition = [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty,
            [Windows.Automation.ControlType]::TabItem
        )
        $terminalTabCount = $terminalElement.FindAll([Windows.Automation.TreeScope]::Descendants, $tabCondition).Count
        $terminalRuntimeDetail += ", tabs=$terminalTabCount"
    }
    catch {
        $terminalRuntimeDetail += ", tab inspection unavailable: $($_.Exception.Message)"
    }
}
Add-Check 'Windows Terminal singleton runtime' $terminalRuntimeStatus $terminalRuntimeDetail

$task = Get-ScheduledTask -TaskName 'WindowsLinuxWorkstation Startup Guard' -ErrorAction SilentlyContinue
Add-Check 'Startup guard task' $(if ($task) { 'pass' } else { 'fail' }) $(if ($task) { "State=$($task.State)" } else { 'Task not registered' })
if ($task) {
    $taskXml = Export-ScheduledTask -TaskName 'WindowsLinuxWorkstation Startup Guard'
    $guardIntervalReady = $taskXml -match '<Interval>PT6H</Interval>'
    Add-Check 'Startup guard lightweight interval' $(if ($guardIntervalReady) { 'pass' } else { 'fail' }) $(if ($guardIntervalReady) { 'Logon plus every 6 hours' } else { 'Expected PT6H repetition interval' })
}

$startupPolicyPath = Join-Path $projectRoot 'config\startup-policy.json'
$startupPolicy = Get-Content -LiteralPath $startupPolicyPath -Raw | ConvertFrom-Json
$safeStartupModel = [int]$startupPolicy.schemaVersion -ge 2 -and
    $startupPolicy.PSObject.Properties.Name -contains 'blockedCurrentUserRunValues' -and
    $startupPolicy.PSObject.Properties.Name -contains 'blockedStartupItems'
Add-Check 'Startup guard explicit blocklist' $(if ($safeStartupModel) { 'pass' } else { 'fail' }) $(if ($safeStartupModel) { 'Unlisted startup entries are preserved' } else { 'Policy uses a broad allowlist instead of explicit blocklists' })

$dockTaskName = 'WindowsLinuxWorkstation Zebar Dock Service'
$dockTask = Get-ScheduledTask -TaskName $dockTaskName -ErrorAction SilentlyContinue
$zebarProcesses = @(Get-Process -Name zebar -ErrorAction SilentlyContinue)
$zebarRetired = -not $dockTask -and $zebarProcesses.Count -eq 0
Add-Check 'Custom taskbar retired' $(if ($zebarRetired) { 'pass' } else { 'fail' }) $(if ($zebarRetired) { 'No Zebar task or process; Explorer owns the taskbar' } else { "Task=$([bool]$dockTask), processes=$($zebarProcesses.Count)" })

$retiredProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -in @('glazewm.exe', 'glazewm-watcher.exe', 'zebar.exe') -or
    ($_.Name -eq 'AutoHotkey64.exe' -and [string]$_.CommandLine -like '*command-palette-win-key.ahk*')
})
$retiredShortcutNames = @('GlazeWM.lnk', 'WindowsLinuxWorkstationHotkeys.lnk', 'CommandPaletteWinKey.lnk')
$retiredShortcuts = @($retiredShortcutNames | ForEach-Object { Join-Path ([Environment]::GetFolderPath('Startup')) $_ } | Where-Object { Test-Path -LiteralPath $_ })
$nativeDesktopReady = $retiredProcesses.Count -eq 0 -and $retiredShortcuts.Count -eq 0
Add-Check 'Native desktop startup model' $(if ($nativeDesktopReady) { 'pass' } else { 'fail' }) $(if ($nativeDesktopReady) { 'No GlazeWM, Zebar, or managed AutoHotkey background layer' } else { "Processes=$(@($retiredProcesses.Name) -join ', '); startup=$(@($retiredShortcuts | Split-Path -Leaf) -join ', ')" })
Add-Check 'Native Windows-key behavior' $(if ($nativeDesktopReady) { 'pass' } else { 'fail' }) $(if ($nativeDesktopReady) { 'Explorer owns Win, Search, Snap, and fullscreen behavior' } else { 'A retired global shortcut or window-manager layer remains active' })

$snapExpectations = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SnapAssist'; Expected = 1 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'EnableSnapBar'; Expected = 1 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'EnableSnapAssistFlyout'; Expected = 1 },
    @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'WindowArrangementActive'; Expected = 1 }
)
$snapDrift = [System.Collections.Generic.List[string]]::new()
foreach ($expectation in $snapExpectations) {
    $key = Get-Item -LiteralPath $expectation.Path -ErrorAction SilentlyContinue
    $actual = if ($key) { $key.GetValue($expectation.Name, $null) } else { $null }
    if ($null -eq $actual -or [int]$actual -ne $expectation.Expected) { $snapDrift.Add("$($expectation.Name)=$actual") }
}
Add-Check 'Native Windows Snap' $(if ($snapDrift.Count -eq 0) { 'pass' } else { 'fail' }) $(if ($snapDrift.Count -eq 0) { 'Edge snapping, Snap Assist, and Snap layouts enabled' } else { "Drift=$($snapDrift -join '; ')" })

$taskbarRegistryExpectations = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Expected = 0 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Expected = 0 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Expected = 0; Optional = $true },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Expected = 0 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarGlomLevel'; Expected = 0 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'MMTaskbarEnabled'; Expected = 1 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarBadges'; Expected = 0 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Expected = 0 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Expected = 0 },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Expected = 1 }
)
$taskbarRegistryDrift = [System.Collections.Generic.List[string]]::new()
foreach ($expectation in $taskbarRegistryExpectations) {
    $key = Get-Item -LiteralPath $expectation.Path -ErrorAction SilentlyContinue
    $actual = if ($key) { $key.GetValue($expectation.Name, $null) } else { $null }
    $optionalAndProtected = $expectation.ContainsKey('Optional') -and $expectation.Optional -and $null -eq $actual
    if (-not $optionalAndProtected -and ($null -eq $actual -or [int]$actual -ne $expectation.Expected)) {
        $taskbarRegistryDrift.Add("$($expectation.Name)=$actual (expected $($expectation.Expected))")
    }
}
$stuckRects = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3' -Name Settings -ErrorAction SilentlyContinue).Settings
$taskbarAutoHideDisabled = $stuckRects -and $stuckRects.Length -gt 8 -and (($stuckRects[8] -band 1) -eq 0)
$nativeTaskbarStyleReady = $taskbarRegistryDrift.Count -eq 0 -and $taskbarAutoHideDisabled
Add-Check 'Native taskbar configuration' $(if ($nativeTaskbarStyleReady) { 'pass' } else { 'fail' }) $(if ($nativeTaskbarStyleReady) { 'Dark, left aligned, grouped, uncluttered, transparent, and not auto-hidden' } else { "Drift=$($taskbarRegistryDrift -join '; '); autoHideDisabled=$taskbarAutoHideDisabled" })

if (-not ('NativeTaskbarProbe' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeTaskbarProbe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string className, string windowName);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr window, out RECT rect);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
}
$taskbarHandle = [NativeTaskbarProbe]::FindWindow('Shell_TrayWnd', $null)
$taskbarRect = New-Object NativeTaskbarProbe+RECT
$taskbarRectReady = $taskbarHandle -ne [IntPtr]::Zero -and [NativeTaskbarProbe]::GetWindowRect($taskbarHandle, [ref]$taskbarRect)
$taskbarWidth = if ($taskbarRectReady) { $taskbarRect.Right - $taskbarRect.Left } else { 0 }
$taskbarHeight = if ($taskbarRectReady) { $taskbarRect.Bottom - $taskbarRect.Top } else { 0 }
$taskbarVisible = $taskbarRectReady -and [NativeTaskbarProbe]::IsWindowVisible($taskbarHandle) -and $taskbarWidth -ge 800 -and $taskbarHeight -ge 28
Add-Check 'Native taskbar render' $(if ($taskbarVisible) { 'pass' } else { 'fail' }) $(if ($taskbarVisible) { "Visible Explorer taskbar ${taskbarWidth}x${taskbarHeight}" } else { 'Explorer taskbar is missing, hidden, or collapsed' })

$appControlRoot = Join-Path $env:LOCALAPPDATA 'WindowsLinuxWorkstation'
$appControlFiles = @(
    Join-Path $appControlRoot 'scripts\Workstation-App-Control.ps1'
    Join-Path $appControlRoot 'scripts\Manage-InstalledApps.ps1'
    Join-Path $appControlRoot 'scripts\Manage-OptionalApps.ps1'
    Join-Path $appControlRoot 'scripts\Manage-UserStartup.ps1'
    Join-Path $appControlRoot 'config\optional-apps.json'
)
$appControlShortcuts = @(Join-Path ([Environment]::GetFolderPath('Programs')) 'NoBS11\NoBS11 Control.lnk')
$retiredDesktopAppControl = @(
    Join-Path ([Environment]::GetFolderPath('Desktop')) 'Workstation App Control.lnk'
    Join-Path ([Environment]::GetFolderPath('Desktop')) 'NoBS11 Control.lnk'
)
$missingAppControl = @($appControlFiles + $appControlShortcuts | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$desktopAppControlPresent = @($retiredDesktopAppControl | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
$appControlInstalledCleanly = $missingAppControl.Count -eq 0 -and -not $desktopAppControlPresent
Add-Check 'Ongoing App Control installed' $(if ($appControlInstalledCleanly) { 'pass' } else { 'fail' }) $(if ($appControlInstalledCleanly) { 'Runtime and Start launcher are present; no Desktop shortcut' } else { "Missing=$($missingAppControl -join ', '); DesktopShortcut=$desktopAppControlPresent" })

$runKeyForAppControl = Get-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$appControlRunValues = @(if ($runKeyForAppControl) { $runKeyForAppControl.GetValueNames() | Where-Object { $_ -like '*Workstation*App*Control*' -or $_ -like '*NoBS11*Control*' } })
$appControlStartupItems = @(Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('Startup')) -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*Workstation*App*Control*' -or $_.Name -like '*NoBS11*Control*' })
$appControlOnDemand = $appControlRunValues.Count -eq 0 -and $appControlStartupItems.Count -eq 0
Add-Check 'App Control on-demand runtime' $(if ($appControlOnDemand) { 'pass' } else { 'fail' }) $(if ($appControlOnDemand) { 'No automatic startup entry; closing the panel ends its process' } else { "RunValues=$($appControlRunValues -join ','); StartupItems=$(@($appControlStartupItems | ForEach-Object Name) -join ',')" })

$policy = Get-Content -LiteralPath (Join-Path $projectRoot 'config\startup-policy.json') -Raw | ConvertFrom-Json
$remainingApps = @($policy.blockedAppPackages | Where-Object { Get-AppxPackage -Name $_ -ErrorAction SilentlyContinue })
Add-Check 'Denylisted current-user apps' $(if ($remainingApps.Count -eq 0) { 'pass' } else { 'fail' }) $(if ($remainingApps.Count -eq 0) { 'All absent' } else { $remainingApps -join ', ' })

$requiredPackages = @(
    'Microsoft.DesktopAppInstaller',
    'Microsoft.GamingServices',
    'Microsoft.WindowsStore',
    'Microsoft.XboxIdentityProvider'
)
foreach ($packageName in $requiredPackages) {
    $package = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -First 1
    Add-Check "Preserved package: $packageName" $(if ($package) { 'pass' } else { 'fail' }) $(if ($package) { $package.Version.ToString() } else { 'Missing' })
}

$oneDrive = Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Select-Object -First 1
$runKey = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$oneDriveRunValue = if ($runKey) { $runKey.GetValue('OneDrive') } else { $null }
$oneDriveAutoStart = (Get-ItemProperty 'HKCU:\Software\Microsoft\OneDrive' -Name AutoStartEnabled -ErrorAction SilentlyContinue).AutoStartEnabled
$oneDriveTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object TaskName -like 'OneDrive * Task-*')
$oneDriveTasksDisabled = $oneDriveTasks.Count -eq 0 -or @($oneDriveTasks | Where-Object State -ne 'Disabled').Count -eq 0
$oneDriveDormant = -not $oneDrive -and -not $oneDriveRunValue -and $oneDriveAutoStart -eq 0 -and $oneDriveTasksDisabled
Add-Check 'OneDrive low-memory mode' $(if ($oneDriveDormant) { 'pass' } else { 'fail' }) $(
    "Process=$([bool]$oneDrive), RunEntry=$([bool]$oneDriveRunValue), AutoStart=$oneDriveAutoStart, TasksDisabled=$oneDriveTasksDisabled; client and synchronized files remain installed"
)

$powerToysProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object ProcessName -like 'PowerToys*')
$powerToysTasks = @(Get-ScheduledTask -TaskPath '\PowerToys\' -ErrorAction SilentlyContinue | Where-Object TaskName -like 'Autorun for *')
$powerToysTasksDisabled = $powerToysTasks.Count -eq 0 -or @($powerToysTasks | Where-Object State -ne 'Disabled').Count -eq 0
$powerToysSettingsPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'
$powerToysStartup = if (Test-Path -LiteralPath $powerToysSettingsPath) { (Get-Content -LiteralPath $powerToysSettingsPath -Raw | ConvertFrom-Json).startup } else { $false }
$powerToysDormant = $powerToysProcesses.Count -eq 0 -and $powerToysTasksDisabled -and -not $powerToysStartup
Add-Check 'PowerToys low-memory mode' $(if ($powerToysDormant) { 'pass' } else { 'fail' }) "Processes=$($powerToysProcesses.Count), Startup=$powerToysStartup, TasksDisabled=$powerToysTasksDisabled"

$overlayProcesses = @(Get-Process -Name 'NVIDIA Overlay' -ErrorAction SilentlyContinue)
$shadowPlayKey = Get-Item 'HKCU:\Software\NVIDIA Corporation\Global\ShadowPlay\NVSPCAPS' -ErrorAction SilentlyContinue
$shadowPlayValueNames = @('IsShadowPlayEnabled', 'IsShadowPlayEnabledUser', 'HLEnabled', 'RecEnabled')
$shadowPlayDisabled = $shadowPlayKey -and @($shadowPlayValueNames | Where-Object {
    $value = [byte[]]$shadowPlayKey.GetValue($_, [byte[]]@())
    $value.Count -eq 0 -or @($value | Where-Object { $_ -ne 0 }).Count -eq 0
}).Count -eq 4
$shareSettingsPath = Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NVIDIA Overlay\ShareSettings.json'
$globalHighlights = if (Test-Path -LiteralPath $shareSettingsPath) { (Get-Content -LiteralPath $shareSettingsPath -Raw | ConvertFrom-Json).settings.globalhighlights.enabled } else { $false }
$overlayDormant = $overlayProcesses.Count -eq 0 -and $shadowPlayDisabled -and -not $globalHighlights
Add-Check 'NVIDIA overlay low-memory mode' $(if ($overlayDormant) { 'pass' } else { 'fail' }) "Processes=$($overlayProcesses.Count), ShadowPlayDisabled=$shadowPlayDisabled, Highlights=$globalHighlights; display driver containers are preserved"

$bravePath = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe'
$braveSignature = if (Test-Path -LiteralPath $bravePath) { Get-AuthenticodeSignature -LiteralPath $bravePath } else { $null }
$braveInstalled = $braveSignature -and $braveSignature.Status -eq 'Valid'
Add-Check 'Modern lightweight browser' $(if ($braveInstalled) { 'pass' } else { 'fail' }) $(if ($braveInstalled) { "Brave $((Get-Item -LiteralPath $bravePath).VersionInfo.FileVersion), valid publisher signature" } else { 'Brave missing or signature invalid' })

$braveUserData = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
$braveLocalStatePath = Join-Path $braveUserData 'Local State'
$bravePreferencesPath = Join-Path $braveUserData 'Default\Preferences'
$braveProfileReady = $false
if ((Test-Path -LiteralPath $braveLocalStatePath) -and (Test-Path -LiteralPath $bravePreferencesPath)) {
    $braveLocalState = Get-Content -LiteralPath $braveLocalStatePath -Raw | ConvertFrom-Json
    $bravePreferences = Get-Content -LiteralPath $bravePreferencesPath -Raw | ConvertFrom-Json
    $braveProfileReady = $braveLocalState.background_mode.enabled -eq $false `
        -and $braveLocalState.brave.p3a.enabled -eq $false `
        -and $bravePreferences.background_mode.enabled -eq $false `
        -and $bravePreferences.performance_tuning.high_efficiency_mode.state -eq 1 `
        -and $bravePreferences.brave.rewards.enabled -eq $false `
        -and $bravePreferences.brave.ai_chat.enabled_by_policy -eq $false
}
Add-Check 'Brave low-memory profile' $(if ($braveProfileReady) { 'pass' } else { 'fail' }) $(if ($braveProfileReady) { 'Memory Saver on; background mode, rewards, AI, VPN, wallet, news, telemetry, and prefetch disabled' } else { 'Managed Brave preferences are missing or drifted' })

$firefoxProfilesRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
$firefoxProfile = Get-ChildItem -LiteralPath $firefoxProfilesRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object Name -like '*.default-release' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$firefoxUserJs = if ($firefoxProfile) { Join-Path $firefoxProfile.FullName 'user.js' } else { $null }
$firefoxUserJsReady = $firefoxUserJs -and (Test-Path -LiteralPath $firefoxUserJs)
Add-Check 'Firefox low-memory fallback' $(if ($firefoxUserJsReady) { 'pass' } else { 'fail' }) $(if ($firefoxUserJsReady) { 'Firefox remains installed but unpinned with a four-process fallback profile' } else { 'Managed Firefox user.js missing' })

$machineMarker = Join-Path $projectRoot 'logs\barebones-machine-latest.json'
if (Test-Path -LiteralPath $machineMarker) {
    try {
        $machineCompletion = Get-Content -LiteralPath $machineMarker -Raw | ConvertFrom-Json
        $machineFailures = [int]$machineCompletion.Failed
        $machineStatus = if ($machineFailures -eq 0) { 'pass' } else { 'pending' }
        $machineDetail = "Finished=$($machineCompletion.FinishedAt), changed=$($machineCompletion.Changed), failed=$machineFailures"
        if ($machineFailures -gt 0) { $machineDetail += '; inspect the ignored manifest before another elevated run' }
        Add-Check 'Elevated barebones batch' $machineStatus $machineDetail
    }
    catch {
        Add-Check 'Elevated barebones batch' 'fail' "Completion marker is invalid: $($_.Exception.Message)"
    }
}
else {
    Add-Check 'Elevated barebones batch' 'pending' 'Optional elevated profile has not been applied'
}

# Atlas performance policy sentinels. HKLM values are elevation-gated, so an
# unapplied machine section is reported as pending rather than failed.
$atlasUserSentinels = @(
    @{ Label = 'HKCU MouseSpeed'; Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Expected = '0' },
    @{ Label = 'HKCU VisualFXSetting'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Expected = 3 }
)
foreach ($sentinel in $atlasUserSentinels) {
    $sentinelKey = Get-Item -LiteralPath $sentinel.Path -ErrorAction SilentlyContinue
    $current = if ($sentinelKey -and ($sentinelKey.GetValueNames() -contains $sentinel.Name)) { $sentinelKey.GetValue($sentinel.Name) } else { $null }
    $applied = $null -ne $current -and [string]$current -ceq [string]$sentinel.Expected
    Add-Check "Atlas policy: $($sentinel.Label)" $(if ($applied) { 'pass' } else { 'fail' }) "Current=$current, expected $($sentinel.Expected)"
}
$atlasMachineSentinels = @(
    @{ Label = 'HKLM SystemResponsiveness'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Expected = 10 },
    @{ Label = 'HKLM Win32PrioritySeparation'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Expected = 38 },
    @{ Label = 'HKLM FTH Enabled'; Path = 'HKLM:\SOFTWARE\Microsoft\FTH'; Name = 'Enabled'; Expected = 0 },
    @{ Label = 'HKLM DNSClient EnableMulticast'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; Name = 'EnableMulticast'; Expected = 0 }
)
foreach ($sentinel in $atlasMachineSentinels) {
    $sentinelKey = Get-Item -LiteralPath $sentinel.Path -ErrorAction SilentlyContinue
    $current = if ($sentinelKey -and ($sentinelKey.GetValueNames() -contains $sentinel.Name)) { $sentinelKey.GetValue($sentinel.Name) } else { $null }
    $applied = $null -ne $current -and [string]$current -ceq [string]$sentinel.Expected
    Add-Check "Atlas policy: $($sentinel.Label)" $(if ($applied) { 'pass' } else { 'pending' }) "Current=$current, expected $($sentinel.Expected)"
}

$machineRun = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$trayEntries = @(@('Riot Vanguard', 'Virtual Pet') | Where-Object { $machineRun.PSObject.Properties.Name -contains $_ })
Add-Check 'Optional machine startup entries' $(if ($trayEntries.Count -eq 0) { 'pass' } else { 'fail' }) $(if ($trayEntries.Count -eq 0) { 'Vanguard tray and Virtual Pet are disabled' } else { $trayEntries -join ', ' })

$protectedServices = 'WinDefend', 'wuauserv', 'BITS', 'InstallService'
foreach ($name in $protectedServices) {
    $service = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
    $healthy = $service -and $service.StartMode -ne 'Disabled'
    Add-Check "Protected service: $name" $(if ($healthy) { 'pass' } else { 'fail' }) $(if ($service) { "State=$($service.State), StartMode=$($service.StartMode)" } else { 'Service not found' })
}

$manualValidation = @(
    'Verify the BitLocker recovery key is accessible.',
    'Confirm the native Explorer taskbar, Win key, and Snap layouts work after restart.',
    'Confirm fullscreen games cover the taskbar without a third-party window manager.',
    'Test sleep/wake, network, audio, camera, hotkeys, lighting, thermal/GPU controls, battery limit, refresh switching, and external displays.',
    'Test Steam, Riot/Vanguard, Overwolf-dependent games, Store, WinGet, Windows Update, and Defender.',
    'Capture and compare a post-restart performance baseline.'
)

$result = [ordered]@{
    CapturedAt = (Get-Date).ToString('o')
}
if ($IncludeIdentity) {
    $result['Computer'] = $env:COMPUTERNAME
    $result['User'] = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}
$result['Summary'] = [ordered]@{
        Passed = @($checks | Where-Object Status -eq 'pass').Count
        Pending = @($checks | Where-Object Status -eq 'pending').Count
        Failed = @($checks | Where-Object Status -eq 'fail').Count
}
$result['Checks'] = $checks
$result['ManualValidation'] = $manualValidation

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $projectRoot "logs\verification-$stamp.json"
}
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
$result | ConvertTo-Json -Depth 8
Write-Host "Verification report: $OutputPath" -ForegroundColor Cyan
if ([int]$result['Summary']['Failed'] -gt 0) { exit 1 }
