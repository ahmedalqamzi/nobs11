# NoBS11

**Windows performance. No BS.**

NoBS11 is a transparent, reversible-by-design Windows 11 performance toolkit. It cuts avoidable idle overhead, startup clutter, background activity, and unwanted optional components while preserving Defender, Windows Update, Microsoft Store, WinGet, drivers, Gaming Services, Explorer, the native taskbar, Snap, and normal fullscreen behavior.

- **Website:** [NoBS11](https://ahmedalqamzi.github.io/nobs11/)
- **Guided installer:** [Download NoBS11 v0.2.0](https://github.com/ahmedalqamzi/nobs11/releases/download/v0.2.0/NoBS11-Setup.cmd)
- **Measurements:** [Reference result and limitations](docs/MEASUREMENTS.md)

## Reference result

On the owner's 64 GB Windows 11 reference laptop:

- idle memory use was observed at approximately **27–28 GB before** and **7 GB after** the final configuration and clean restart;
- retained performance-counter snapshots showed **384 to 186 running processes**, or 51.6% fewer.

These were observational results from one machine, not controlled universal benchmarks. Hardware, drivers, Windows builds, active workloads, and profile choices change the outcome. No battery-life, frame-rate, or latency percentage is claimed because a controlled repeated A/B test has not been completed.

## Install from the website

Download and open NoBS11-Setup.cmd from the project website or the v0.2.0 release. The launcher:

1. downloads the pinned v0.2.0 PowerShell installer;
2. verifies its SHA-256 before running it;
3. lets you choose Standard, Lean, or Maximum;
4. downloads the matching pinned source and retains it with rollback data.

Run the launcher normally, not with **Run as administrator**. NoBS11 requests UAC only when the Maximum profile reaches its machine-wide stage.

This is an open-source preview, not a signed commercial installer, so Windows may show a download or script warning. The launcher and every applied policy are readable in this repository.

## Profiles

| Profile | What it does | Boundary |
|---|---|---|
| **Standard** | Restores the native taskbar, Start, Snap, terminal profile, and installs NoBS11 Control | Does not apply cleanup policy or remove Windows apps and services |
| **Lean** | Adds reviewed current-user cleanup and performance settings | Does not remove optional Windows apps or disable machine services |
| **Maximum** | Applies the full reference profile, including reviewed optional-app/component removal and elevated machine tuning | Hardware-sensitive; explicit typed confirmation, UAC, restart, and hardware/game validation required |

All profiles preserve Windows security controls, Windows Update, Store/WinGet, WebView2 and shared runtimes, drivers, Gaming Services, and hardware-control components. Maximum has only best-effort rollback for Windows servicing operations.

## Preview or install from source

Open a normal, non-administrator PowerShell window in the repository:

~~~powershell
# No-change preview
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Profile Lean -WhatIf

# Recommended user-level profile
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Profile Lean

# Conservative desktop-only profile
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Profile Standard
~~~

Maximum is intentionally explicit:

~~~powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Profile Maximum
~~~

The guided prompt also lets you keep, disable at startup, or uninstall cataloged third-party apps. Pressing Enter keeps everything:

~~~powershell
# Read-only status
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Manage-OptionalApps.ps1 -Action Audit

# Stop an app and remove its known automatic launch sources, but keep it installed
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Manage-OptionalApps.ps1 -Action DisableStartup -Name overwolf

# Explicit uninstall example
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Manage-OptionalApps.ps1 -Action Uninstall -Name overwolf,mobalytics
~~~

Mobalytics depends on Overwolf, so select both only when neither application is wanted.

## NoBS11 Control

Every profile installs **NoBS11 Control** in the Start menu only. It is an on-demand native Windows panel, not another background service:

- **Installed apps** searches desktop and Store apps, stops cataloged background activity, removes known automatic launch sources, and runs registered uninstallers in the same app.
- **Startup** reversibly disables and restores current-user Run entries and Startup-folder shortcuts.
- **Processes** shows current-session memory use and can end a selected non-core process after confirmation.

Disabling background activity does not prevent an app that you or another program deliberately launches later. Persistent enforcement remains a separate explicit blocklist.

Refresh the panel without rerunning the workstation installer:

~~~powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Pwsh.ps1 -ScriptPath scripts\Install-AppControl.ps1 -Launch
~~~

## Native desktop behavior

- Win and Ctrl+Esc open native Start; Win+S opens Windows Search.
- Win+Left and Win+Right place windows on monitor halves; Win+Z opens Snap layouts.
- Explorer owns the taskbar, work area, Start, Search, tray, clock, multi-monitor behavior, and fullscreen handoff.
- GlazeWM, Zebar, AutoHotkey key hooks, Command Palette, and a replacement dock are not required.
- Windows Terminal exposes one clear UCRT64 profile while PowerShell 7 remains available for native administration.

Optional Unix-style tools include Git, Neovim, Yazi, tmux, Starship, and familiar command-line utilities. They are a convenience layer; NoBS11 is not Linux, WSL, a VM, or a replacement operating system.

## Safety and rollback

High-impact behavior lives in reviewed JSON policy files under config/. The scripts create ignored backup and audit data under backups/ and logs/.

Available rollback commands include:

- make rollback-config
- make rollback-native-taskbar
- make rollback-barebones
- make rollback-barebones-machine
- make rollback-atlas
- make remove-guard

App reinstall, capability restoration, component-store cleanup, and third-party uninstallers may not recreate the exact previous state. Keep rollback data until the machine passes restart, hardware, and gaming validation.

## Useful commands

| Command | Purpose |
|---|---|
| make check | Validate public files, credentials hygiene, syntax, and release requirements |
| make preflight | Check required software without changing Windows |
| make audit | Audit the explicit startup/background policy |
| make verify | Produce a redacted workstation verification report |
| make apply-config | Apply the shell, terminal, native Snap, and native-taskbar configuration |
| make native-taskbar | Repair only the native taskbar migration |
| make native-windowing | Reapply native Snap settings |
| make apps | Audit optional apps, processes, startup entries, and services |
| make app-control | Install or refresh NoBS11 Control |
| make browser | Apply optional Brave/Firefox low-memory preferences |

Explicit high-impact commands remain available for review:

| Command | Risk |
|---|---|
| make guard | Installs recurring explicit-blocklist enforcement |
| make barebones | Applies more than 100 current-user changes and can remove optional Appx packages |
| make barebones-machine | Elevated hardware-specific service, feature, capability, package, and servicing changes |
| make atlas | Optional performance-related registry, task, event-log, and service-host changes |

## Project layout

~~~text
config/       Reviewed policy data; aggressive profiles are explicit
dotfiles/     Shell, editor, terminal, Firefox, and command-line configuration
installer/    Hash-verified website launcher and pinned online installer
manifests/    Curated public dependency manifests
scripts/      Preflight, apply, control, audit, verification, and rollback entry points
website/      Static project site and hosting build
backups/      Local rollback data; ignored except for .gitkeep
baseline/     Local measurements; ignored except for .gitkeep
logs/         Local reports; ignored except for .gitkeep
~~~

Run make check before every release. Publication requirements are tracked in [docs/RELEASE-CHECKLIST.md](docs/RELEASE-CHECKLIST.md). NoBS11 is MIT licensed; upstream provenance is documented in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
