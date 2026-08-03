# Changelog

## 0.2.0 - 2026-08-03

### Changed

- Renamed the project to NoBS11 and refocused the public site on transparent Windows performance instead of the optional Unix-style shell.
- Added a website-downloadable, SHA-256-verified launcher pinned to the v0.2.0 source.
- Added Standard, Lean, and Maximum installer profiles with explicit safety boundaries and a second confirmation for the hardware-sensitive reference profile.
- Updated the public measurement note with the owner's 27–28 GB to approximately 7 GB clean-idle observation and the retained 384-to-186 process snapshots.
- Renamed the Start-menu panel to NoBS11 Control while retaining legacy runtime identifiers for safe upgrades.
- Replaced the custom dock experiment with the native Explorer taskbar.
- Replaced GlazeWM and the managed AutoHotkey shortcut layer with native Windows Snap and Explorer-owned shortcuts.
- Added a guided standard installer plus explicit audit, disable-at-startup, and uninstall choices for optional apps, including scoped UAC retry for machine-wide uninstallers.
- Added an on-demand, Start-menu-only NoBS11 Control panel with searchable installed apps, in-app uninstall, reversible startup control, and process management.
- Made optional-app background actions idempotent, added scoped administrator retry for machine-wide startup sources, and exposed a clear disabled state in App Control.
- Added safe PowerShell 7 resolution, dependency preflight, repository validation, and Windows CI.
- Changed startup enforcement from a global allowlist to explicit blocklists.
- Made recurring Appx removal and high-impact cleanup explicitly opt-in.
- Replaced machine-wide package exports with curated public manifests and ignored local snapshots.
- Redacted verification identity and local paths by default.
- Made verification surface partial elevated-cleanup runs instead of passing on marker presence alone.
- Removed three unsupported or obsolete Explorer registry hacks from the aggressive cleanup profiles.
- Pinned and documented the exact AtlasOS, Win11Debloat, and Winhance revisions used for the provenance review.
- Added GitHub issue and pull-request templates plus monthly Actions dependency updates.

### Removed

- Retired Zebar/Notch implementation and supervisor scripts.
- Retired GlazeWM, the workstation AutoHotkey hook, and Command Palette from the standard dependency set.
- Vendored Zebar client, Nerd Font web assets, preview image, and unverified wallpaper.
- Machine-specific execution diary, full package inventory, and exported OS metadata from the public tree.
