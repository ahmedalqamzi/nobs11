#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository,
    [string]$Ref,
    [string]$SourcePath,
    [switch]$SkipPackages,
    [switch]$IncludeBrowserTuning,
    [switch]$IncludeStartupGuard,
    [string[]]$DisableStartupApp,
    [string[]]$UninstallApp,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sourceRoot = $null
$archivePath = $null

if ($SourcePath) {
    $sourceRoot = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
}
elseif (-not $Repository) {
    throw 'Specify -Repository owner/name for a GitHub download, or use -SourcePath for a local source tree.'
}
elseif ($WhatIfPreference) {
    $targetRef = if ($Ref) { $Ref } else { 'the latest release (main as fallback)' }
    [void]$PSCmdlet.ShouldProcess("GitHub repository $Repository at $targetRef", 'Download a persistent installer source under %LOCALAPPDATA%\WindowsLinuxWorkstation\sources')
    Write-Host 'Bootstrap preview complete. No files were downloaded and no settings were changed.' -ForegroundColor Yellow
    return
}
else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'WindowsLinuxWorkstation-Installer'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $downloadUri = $null
    $sourceLabel = $Ref
    if ($Ref) {
        $downloadUri = "https://api.github.com/repos/$Repository/zipball/$([uri]::EscapeDataString($Ref))"
    }
    else {
        try {
            $latest = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/latest"
            $downloadUri = [string]$latest.zipball_url
            $sourceLabel = [string]$latest.tag_name
        }
        catch {
            Write-Warning 'No published release was available; using the current main branch preview.'
            $downloadUri = "https://github.com/$Repository/archive/refs/heads/main.zip"
            $sourceLabel = 'main-preview'
        }
    }

    if (-not $downloadUri) { throw 'GitHub did not return a source archive URL.' }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeLabel = ($sourceLabel -replace '[^A-Za-z0-9._-]', '-').Trim('-')
    if (-not $safeLabel) { $safeLabel = 'source' }
    $sourcesRoot = Join-Path $env:LOCALAPPDATA 'WindowsLinuxWorkstation\sources'
    $extractRoot = Join-Path $sourcesRoot "$safeLabel-$stamp"
    $archivePath = Join-Path $env:TEMP "windows-linux-workstation-$stamp.zip"

    if ($PSCmdlet.ShouldProcess($downloadUri, "Download and retain source under $extractRoot")) {
        New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
        try {
            Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $downloadUri -OutFile $archivePath
            Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
        }
        finally {
            if ($archivePath -and (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
                Remove-Item -LiteralPath $archivePath -Force
            }
        }
    }

    $sourceRoot = Get-ChildItem -LiteralPath $extractRoot -Directory -ErrorAction Stop |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Install.ps1') -PathType Leaf } |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $sourceRoot -or -not (Test-Path -LiteralPath (Join-Path $sourceRoot 'Install.ps1') -PathType Leaf)) {
    throw 'The downloaded source is incomplete; Install.ps1 was not found.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'scripts\Apply-Config.ps1') -PathType Leaf)) {
    throw 'The downloaded source is incomplete; the configuration scripts were not found.'
}

$arguments = @(
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $sourceRoot 'Install.ps1')
)
if ($SkipPackages) { $arguments += '-SkipPackages' }
if ($IncludeBrowserTuning) { $arguments += '-IncludeBrowserTuning' }
if ($IncludeStartupGuard) { $arguments += '-IncludeStartupGuard' }
if ($DisableStartupApp) { $arguments += @('-DisableStartupApp', ($DisableStartupApp -join ',')) }
if ($UninstallApp) { $arguments += @('-UninstallApp', ($UninstallApp -join ',')) }
if ($Force) { $arguments += '-Force' }
if ($WhatIfPreference) { $arguments += '-WhatIf' }

& powershell.exe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "The workstation installer exited with code $LASTEXITCODE. Retained source: $sourceRoot"
}
