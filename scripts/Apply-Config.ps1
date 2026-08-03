#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$dotfilesRoot = Join-Path $projectRoot 'dotfiles'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-config"
$manifest = [System.Collections.Generic.List[object]]::new()
if (-not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
}

function Backup-Target {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    $exists = Test-Path -LiteralPath $Path
    $backupPath = Join-Path $backupRoot $Name
    if ($exists -and -not $WhatIfPreference) {
        $parent = Split-Path -Parent $backupPath
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    }
    $manifest.Add([pscustomobject]@{ Target = $Path; Backup = $backupPath; Existed = $exists })
}

function Copy-ManagedFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$BackupName
    )

    Backup-Target -Path $Destination -Name $BackupName
    if ($PSCmdlet.ShouldProcess($Destination, "Install managed config from $Source")) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Set-ManagedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$BackupName
    )

    Backup-Target -Path $Path -Name $BackupName
    $start = "# >>> windows-linux-workstation:$Name >>>"
    $end = "# <<< windows-linux-workstation:$Name <<<"
    $current = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { '' }
    $pattern = '(?ms)^' + [regex]::Escape($start) + '.*?^' + [regex]::Escape($end) + '\r?\n?'
    $current = [regex]::Replace($current, $pattern, '').TrimEnd()
    $block = @($start) + $Lines + @($end)
    $updated = if ($current) { $current + [Environment]::NewLine + [Environment]::NewLine + ($block -join [Environment]::NewLine) + [Environment]::NewLine } else { ($block -join [Environment]::NewLine) + [Environment]::NewLine }

    if ($PSCmdlet.ShouldProcess($Path, "Install managed $Name loader")) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
        Set-Content -LiteralPath $Path -Value $updated -Encoding utf8NoBOM
    }
}

$configRoot = Join-Path $HOME '.config'
Copy-ManagedFile (Join-Path $dotfilesRoot 'shell\bashrc') (Join-Path $configRoot 'shell\bashrc') 'managed-shell-bashrc'
Copy-ManagedFile (Join-Path $dotfilesRoot 'shell\inputrc') (Join-Path $configRoot 'shell\inputrc') 'managed-shell-inputrc'
Copy-ManagedFile (Join-Path $dotfilesRoot 'powershell\profile.ps1') (Join-Path $configRoot 'powershell\profile.ps1') 'managed-powershell-profile'
Copy-ManagedFile (Join-Path $dotfilesRoot 'starship\starship.toml') (Join-Path $configRoot 'starship.toml') 'starship.toml'
Copy-ManagedFile (Join-Path $dotfilesRoot 'git\config') (Join-Path $configRoot 'git\config') 'git-config'
Copy-ManagedFile (Join-Path $dotfilesRoot 'nvim\init.lua') (Join-Path $env:LOCALAPPDATA 'nvim\init.lua') 'nvim-init.lua'
Copy-ManagedFile (Join-Path $dotfilesRoot 'tmux\tmux.conf') (Join-Path $configRoot 'tmux\tmux.conf') 'tmux.conf'

Set-ManagedBlock -Path (Join-Path $HOME '.bashrc') -Name 'bash' -BackupName 'bashrc' -Lines @(
    '[[ -f "$HOME/.config/shell/bashrc" ]] && source "$HOME/.config/shell/bashrc"'
)

$msysRoot = 'C:\msys64'
$msysBashHome = Join-Path $msysRoot "home\$env:USERNAME"
$cygpath = Join-Path $msysRoot 'usr\bin\cygpath.exe'
if ((Test-Path -LiteralPath $msysBashHome) -and (Test-Path -LiteralPath $cygpath)) {
    $managedBashPath = (& $cygpath -u (Join-Path $configRoot 'shell\bashrc')).Trim()
    Set-ManagedBlock -Path (Join-Path $msysBashHome '.bashrc') -Name 'bash' -BackupName 'msys2-bashrc' -Lines @(
        "[[ -f `"$managedBashPath`" ]] && source `"$managedBashPath`""
    )
}

$pwshProfile = $PROFILE.CurrentUserCurrentHost
Set-ManagedBlock -Path $pwshProfile -Name 'powershell' -BackupName 'Microsoft.PowerShell_profile.ps1' -Lines @(
    ". (Join-Path `$HOME '.config\powershell\profile.ps1')"
)

$gitGlobal = Join-Path $HOME '.gitconfig'
Backup-Target -Path $gitGlobal -Name '.gitconfig'
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitInclude = (Join-Path $configRoot 'git\config').Replace('\', '/')
    # Use the explicit legacy global file. When ~/.gitconfig does not yet exist,
    # git config --global may select the XDG config we are trying to include and
    # append a self-reference to it.
    $existingIncludes = @(& git config --file $gitGlobal --get-all include.path 2>$null)
    if ($existingIncludes -notcontains $gitInclude -and $PSCmdlet.ShouldProcess($gitGlobal, "Add Git include $gitInclude")) {
        & git config --file $gitGlobal --add include.path $gitInclude
    }
}

$terminalSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path -LiteralPath $terminalSettings) {
    Backup-Target -Path $terminalSettings -Name 'terminal-settings.json'
    $settings = Get-Content -LiteralPath $terminalSettings -Raw | ConvertFrom-Json -AsHashtable

    if (-not $settings.ContainsKey('profiles')) { $settings.profiles = @{} }
    if (-not $settings.profiles.ContainsKey('defaults')) { $settings.profiles.defaults = @{} }
    if (-not $settings.profiles.ContainsKey('list')) { $settings.profiles.list = @() }
    if (-not $settings.ContainsKey('schemes')) { $settings.schemes = @() }

    $ucrtGuid = '{d8d0ce2f-7a4d-4d21-9bb2-28c86a738e39}'
    $pwshGuid = '{6037f5d2-1f63-4d64-9e64-4f0f3862f761}'
    $settings.profiles.list = @($settings.profiles.list | Where-Object { $_.guid -notin @($ucrtGuid, $pwshGuid) -and $_.name -notin @('UCRT64 Bash', 'PowerShell 7') })
    $settings.profiles.list += [ordered]@{
        guid = $ucrtGuid
        name = 'UCRT64 Bash'
        commandline = 'C:/msys64/msys2_shell.cmd -defterm -here -no-start -ucrt64'
        startingDirectory = '%USERPROFILE%'
        icon = 'C:/msys64/ucrt64.ico'
        hidden = $false
    }
    $settings.profiles.list += [ordered]@{
        guid = $pwshGuid
        name = 'PowerShell 7'
        commandline = 'pwsh.exe'
        startingDirectory = '%USERPROFILE%'
        hidden = $true
    }

    # Keep one user-facing terminal profile. Native PowerShell and cmd remain
    # installed for scripts and administration, but do not clutter the menu.
    foreach ($profile in @($settings.profiles.list)) {
        $profile.hidden = ([string]$profile.guid -ne $ucrtGuid)
    }

    $scheme = [ordered]@{
        name = 'Catppuccin Mocha'
        foreground = '#CDD6F4'
        background = '#1E1E2E'
        cursorColor = '#F5E0DC'
        selectionBackground = '#585B70'
        black = '#45475A'
        red = '#F38BA8'
        green = '#A6E3A1'
        yellow = '#F9E2AF'
        blue = '#89B4FA'
        purple = '#F5C2E7'
        cyan = '#94E2D5'
        white = '#BAC2DE'
        brightBlack = '#585B70'
        brightRed = '#F38BA8'
        brightGreen = '#A6E3A1'
        brightYellow = '#F9E2AF'
        brightBlue = '#89B4FA'
        brightPurple = '#F5C2E7'
        brightCyan = '#94E2D5'
        brightWhite = '#A6ADC8'
    }
    $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne 'Catppuccin Mocha' }) + @($scheme)
    $settings.defaultProfile = $ucrtGuid
    $settings.windowingBehavior = 'useExisting'
    $settings.firstWindowPreference = 'defaultProfile'
    $settings.theme = 'dark'
    $settings.launchMode = 'maximized'
    $settings.tabWidthMode = 'compact'
    $settings.showTabsInTitlebar = $false
    $settings.alwaysShowTabs = $true
    $settings.confirmCloseAllTabs = $false
    $settings.copyOnSelect = $true
    $settings.profiles.defaults.colorScheme = 'Catppuccin Mocha'
    $settings.profiles.defaults.opacity = 94
    $settings.profiles.defaults.useAcrylic = $true
    $settings.profiles.defaults.padding = '10'
    $settings.profiles.defaults.cursorShape = 'filledBox'
    $settings.profiles.defaults.font = [ordered]@{ face = 'JetBrainsMono Nerd Font'; size = 11 }

    if ($PSCmdlet.ShouldProcess($terminalSettings, 'Merge UCRT64, PowerShell 7, and Catppuccin settings')) {
        $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $terminalSettings -Encoding utf8NoBOM
    }
}

$optionalAppManager = Join-Path $PSScriptRoot 'Manage-OptionalApps.ps1'
if ($PSCmdlet.ShouldProcess('Legacy tiling and hotkey startup entries', 'Disable the retired GlazeWM, Zebar, AutoHotkey helper, and Command Palette launchers')) {
    & $optionalAppManager -Action DisableStartup -Name glazewm, zebar, workstation-hotkeys, command-palette -Force
}

$dockServiceRemover = Join-Path $PSScriptRoot 'Remove-ZebarDockService.ps1'
if ($PSCmdlet.ShouldProcess('WindowsLinuxWorkstation Zebar Dock Service', 'Remove the retired custom taskbar supervisor')) {
    & $dockServiceRemover
}

$nativeWindowingConfigurator = Join-Path $PSScriptRoot 'Configure-NativeWindowing.ps1'
if ($PSCmdlet.ShouldProcess('Windows Snap', 'Apply native window snapping and layout settings')) {
    & $nativeWindowingConfigurator
}

$nativeTaskbarConfigurator = Join-Path $PSScriptRoot 'Configure-NativeTaskbar.ps1'
if ($PSCmdlet.ShouldProcess('Explorer taskbar', 'Apply the managed native taskbar configuration')) {
    & $nativeTaskbarConfigurator
}

$appControlInstaller = Join-Path $PSScriptRoot 'Install-AppControl.ps1'
if ($PSCmdlet.ShouldProcess('NoBS11 Control', 'Install ongoing app and startup control shortcuts')) {
    & $appControlInstaller
}

if ($WhatIfPreference) {
    Write-Host 'Configuration preview complete; no files or settings were changed.' -ForegroundColor Yellow
}
else {
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupRoot 'manifest.json') -Encoding utf8NoBOM
    Write-Host "Configuration applied. Backup manifest: $backupRoot" -ForegroundColor Green
}
