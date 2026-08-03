# Upstream provenance review

Review date: 2026-08-03

The cleanup and performance policies use Windows package identifiers, registry values, task names, and service names that also appear in established tuning projects. The public tree keeps its own data-driven PowerShell implementation and does not intentionally redistribute an upstream source file or binary.

## Reviewed snapshots

| Project | Exact revision reviewed | Commit date | Upstream license |
|---|---|---|---|
| AtlasOS | [`1ed9630616b29f0c7974e8bd76a94fc06f60388c`](https://github.com/Atlas-OS/Atlas/tree/1ed9630616b29f0c7974e8bd76a94fc06f60388c) | 2026-05-04 | GPL-3.0 |
| Win11Debloat | [`6957ce4220960ea1473ff6b9f6d6a8a8359f4cb5`](https://github.com/Raphire/Win11Debloat/tree/6957ce4220960ea1473ff6b9f6d6a8a8359f4cb5) | 2026-08-01 | MIT |
| Winhance | [`f23d554eb2d6400b1827bcc46b91294ffa53fbc9`](https://github.com/memstechtips/Winhance/tree/f23d554eb2d6400b1827bcc46b91294ffa53fbc9) | 2026-06-12 | PolyForm Shield 1.0.0, with separately identified third-party components |

## Review notes

- AtlasOS was checked for the performance-policy behaviors named in this repository, including MMCSS responsiveness, foreground scheduling, paging, mouse acceleration, LLMNR, WPBT, shutdown timing, and SleepStudy-related tasks and logs.
- Win11Debloat was checked for common optional-app identifiers and Explorer, Search, suggestions, taskbar, and Snap registry values.
- Winhance was checked as an independent behavior reference for overlapping Windows customization and performance values. No Winhance implementation file is intentionally copied into this repository.
- A spot check found no matching project-specific implementation identifiers from the three upstream codebases. Common Windows registry names and package identifiers necessarily overlap.
- The retired Zebar/Notch implementation and its vendored JavaScript, webfont, and image assets were removed from the public tree.

This is a provenance record, not a legal conclusion. Before release, the repository owner must still choose a root license that is compatible with any material ultimately determined to be derivative and preserve all notices that license requires.
