# Project website

This directory contains the static public landing page. It deliberately has no package manager or runtime dependency: GitHub Pages can publish the files directly, and `build.ps1` creates the small Worker-compatible bundle used for the private Sites preview.

The performance figures on the page are copied from the aggregate, non-identifying measurements recorded in [`../docs/MEASUREMENTS.md`](../docs/MEASUREMENTS.md). Do not add private reports, raw captures, screenshots, account names, hostnames, or local paths here.

Run the local build with:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\website\build.ps1
```

For a hosted preview outside GitHub Pages, pass the public repository URL with `-RepositoryUrl`. The GitHub Pages workflow injects its repository URL automatically, so the public source does not hard-code an account name.
