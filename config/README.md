# Policy profiles

The shell configuration and native taskbar do not require the cleanup policies in this directory.

| File | Scope | Default safety boundary |
|---|---|---|
| `optional-apps.json` | Catalog for guided keep, disable-at-startup, and uninstall choices | No action without an explicit selection; machine-wide uninstallers request UAC |
| `startup-policy.json` | Explicit current-user startup, task, process, registry, and optional Appx blocklists | Unlisted startup entries are preserved; Appx removal requires `-IncludeAppRemoval` |
| `barebones-policy.json` | Aggressive current-user privacy, shell, and optional-app changes | Interactive confirmation; review every entry |
| `barebones-machine-policy.json` | Elevated, ASUS-oriented services, tasks, features, capabilities, and packages | Hardware-specific interactive confirmation; do not reuse blindly |
| `atlas-performance-policy.json` | Optional performance-related settings | Interactive confirmation; security-reducing Atlas items are intentionally excluded |

`-WhatIf` previews `SupportsShouldProcess` operations. `-Force` bypasses the one-time warning on high-impact apply/install scripts and is intended for reviewed automation only.

The current-user policy keeps `ToastEnabled=1`; individual low-value notification categories can still be disabled without turning off the WinRT notification platform. The machine policy restores entries in `requiredServices` before cleanup, handles per-user service templates through their registry definition, and protects required services from the disable list. This keeps NVIDIA App and other hardware-control apps operational while retaining the Maximum profile.

Rollback manifests are best-effort state captures, not system images. Windows servicing cleanup and third-party uninstallers can be only partially reversible.
