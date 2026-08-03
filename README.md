# Windows Linux-like Workstation

A transparent, reversible-by-design Windows 11 workstation profile with a Unix-like command line, native window snapping, and the native Explorer taskbar. Windows remains the only operating-system kernel: this project does not install WSL, a Linux VM, or a replacement shell.

The public project website is in [`website/`](website/). Its performance section uses the aggregate, non-identifying observations and limitations recorded in [docs/MEASUREMENTS.md](docs/MEASUREMENTS.md); no universal battery or performance gain is claimed.

The default desktop uses:

- Windows Terminal with one visible MSYS2 UCRT64 Bash profile
- PowerShell 7 for native Windows administration
- Windows Snap for half-screen layouts, Snap Assist, and multi-monitor movement
- Explorer's native taskbar for Start, Search, tray, clock, multi-monitor behavior, and fullscreen games
- Git, Neovim, Yazi, tmux, Starship, and modern command-line tools

## Safety and support boundary

This is a personal workstation configuration and a public preview, not a universal Windows debloater. It has been tested on the hardware and Windows build in [docs/TESTED-CONFIGURATION.md](docs/TESTED-CONFIGURATION.md).

The shell and taskbar configuration is separated from the aggressive cleanup profiles. Do not run `barebones`, `barebones-machine`, `atlas`, or persistent startup enforcement until you have reviewed the corresponding JSON policy. Machine-wide cleanup is hardware-specific, requires elevation, and has only best-effort rollback for Windows servicing operations.

Generated backups, logs, baselines, and package snapshots are intentionally ignored by Git. Never publish a ZIP of the working directory; publish tracked files with Git or `git archive`.

## Quick start

Open a normal, non-administrator PowerShell window in the cloned repository and preview the guided installer:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -WhatIf
```

Then run the standard profile. It installs the curated dependencies, fully updates MSYS2, creates rollback data, and applies the native desktop configuration. The guided prompt also lets you keep, disable at startup, or uninstall cataloged optional apps; pressing Enter keeps everything:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

The default choice does not uninstall Windows applications or disable Windows services. The same controls can be scripted or run separately:

```powershell
# Read-only status
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Manage-OptionalApps.ps1 -Action Audit

# Stop an app and remove its startup entries, but keep it installed
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Manage-OptionalApps.ps1 -Action DisableStartup -Name overwolf

# Explicit uninstall example; Mobalytics depends on Overwolf, so select both only if neither is wanted
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Manage-OptionalApps.ps1 -Action Uninstall -Name overwolf,mobalytics

# Non-interactive installer selections use the same audited catalog
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -DisableStartupApp overwolf -UninstallApp powertoys -Force
```

## Ongoing app control

The standard setup installs **Workstation App Control** in the Start menu only. It is an on-demand native Windows panel, not another background process:

- **Installed apps** searches desktop and Store apps, runs their registered uninstallers without leaving App Control, and can stop cataloged background activity plus known automatic launch sources. This does not block an app that you or another application explicitly launches later.
- **Startup** reversibly disables and restores current-user Run entries and Startup-folder shortcuts.
- **Processes** shows current-session memory use and can end a selected non-core process after confirmation.

Install or refresh the panel without rerunning the workstation setup:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Install-AppControl.ps1 -Launch
```

The separate Startup Guard remains responsible for persistent explicit blocklists at logon and every six hours. Unlisted applications are not silently disabled.

After reopening UCRT64 Bash in this repository, the make targets remain available:

```bash
make check
make preflight
make apply-config
```

`apply-config` installs the tracked configuration, retires old custom bars and shortcut hooks, and configures native Snap plus the native taskbar. It creates ignored rollback data under `backups/` and restarts Explorer so shell settings take effect. `make native-taskbar` is the standalone repair/migration command if only that portion needs to be reapplied.

On a fully configured test system, run `make verify` to validate the complete workstation profile. That verifier also covers optional browser, startup-guard, cleanup, and performance-policy state, so a new installation can report pending or failed checks for profiles that were deliberately not enabled.

## Desktop behavior

- `Win` and `Ctrl+Esc` open native Start; `Win+S` opens Windows Search.
- `Win+Left` and `Win+Right` place windows on exact monitor halves; `Win+Z` opens Snap layouts.
- Native maximized and fullscreen applications use the normal Windows work area and fullscreen behavior.
- Windows Terminal reuses one window and exposes one user-facing UCRT64 profile.
- The taskbar remains editable through normal Windows controls; no custom dock or shell hook is installed.
- GlazeWM, Zebar, AutoHotkey hooks, and Command Palette are not required by the standard profile.

See [HOTKEYS.md](HOTKEYS.md) for the complete keyboard map.

## Commands

Read-only or low-risk entry points:

| Command | Purpose |
|---|---|
| `make check` | Validate public repository files and release hygiene |
| `make preflight` | Check required software without changing Windows |
| `make audit` | Audit the explicit startup/background policy |
| `make verify` | Produce a redacted workstation verification report |
| `make apply-config` | Install tracked shell, editor, terminal, native Snap, and native-taskbar configuration with backups |
| `make native-taskbar` | Reapply only the custom-bar retirement and native taskbar profile |
| `make native-windowing` | Reapply native Snap and Snap-layout settings |
| `make apps` | Audit optional apps, background processes, startup entries, and services |
| `make app-control` | Install or refresh and open the ongoing App Control panel |
| `make browser` | Apply the optional Brave/Firefox low-memory preferences |

Explicit opt-in commands:

| Command | Risk |
|---|---|
| `make guard` | Installs persistent policy enforcement at logon and every six hours |
| `make barebones` | Changes more than 100 current-user settings and can remove optional Appx packages |
| `make barebones-machine` | Elevated, hardware-specific service, feature, capability, package, and servicing changes |
| `make atlas` | Optional performance-related registry, task, event-log, and service-host changes |

The high-impact entry points display a confirmation unless invoked with `-Force` directly. Use the underlying script with `-WhatIf` to inspect proposed operations first.

## Rollback

Rollback scripts restore captured values where Windows exposes a reversible operation:

- `make rollback-config`
- `make rollback-native-taskbar`
- `make rollback-barebones`
- `make rollback-barebones-machine`
- `make rollback-atlas`
- `make remove-guard`

App reinstall, capability restoration, component-store cleanup, and third-party uninstallers may not reproduce the exact previous state. Keep the generated backups until the machine has passed restart, hardware, and gaming validation.

## Project layout

```text
config/       Reviewed policy data; aggressive profiles are opt-in
dotfiles/     Shell, editor, terminal, Firefox, and command-line configuration
manifests/    Curated public dependency manifests
scripts/      Preflight, apply, audit, verification, and rollback entry points
backups/      Local rollback data; ignored except for .gitkeep
baseline/     Local measurements; ignored except for .gitkeep
logs/         Local reports; ignored except for .gitkeep
```

Run `make check` before every release. Remaining publication work is tracked in [docs/RELEASE-CHECKLIST.md](docs/RELEASE-CHECKLIST.md). The original project source is MIT licensed; licensing and upstream provenance are described in [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
