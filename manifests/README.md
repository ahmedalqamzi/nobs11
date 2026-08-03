# Dependency manifests

Public manifests are curated requirements, not exports of every package installed on the development machine.

- `winget-packages.json` contains the stable native applications needed by this workstation. Versions are intentionally omitted so WinGet resolves a currently available stable release.
- `pacman-explicit.txt` contains the intentionally selected MSYS2 packages. Transitive dependencies are resolved by the configured MSYS2 repositories.

`scripts/Export-Manifests.ps1` writes full machine snapshots, versions, foreign packages, and OS metadata under `manifests/local/`, which is ignored by Git. Pass `-RefreshCuratedPacmanList` only when intentionally updating the reviewed public MSYS2 list.

The Windows and UCRT64 environments remain separate. Do not add all of `C:\msys64\usr\bin` to the global Windows `PATH`.
