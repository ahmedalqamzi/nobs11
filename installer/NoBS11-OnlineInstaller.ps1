#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Standard', 'Lean', 'Maximum')]
    [string]$Profile,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repository = 'ahmedalqamzi/nobs11'
$releaseTag = 'v0.2.0'
$bootstrapUri = "https://raw.githubusercontent.com/$repository/$releaseTag/bootstrap.ps1"
$bootstrapSha256 = 'D45B4F48FC86B73933EDE97110FA4D8774F9B645F8FDC66A972681BEFA86559D'
$bootstrapPath = Join-Path $env:TEMP "NoBS11-bootstrap-$releaseTag.ps1"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Start NoBS11 normally, not with Run as administrator. The Maximum profile requests UAC only for its machine-wide stage.'
}

if (-not $Profile) {
    if ($WhatIfPreference -or $Force) {
        $Profile = 'Standard'
    }
    else {
        Write-Host ''
        Write-Host 'NoBS11' -ForegroundColor White
        Write-Host 'Windows performance. No BS.' -ForegroundColor Green
        Write-Host ''
        Write-Host 'Choose a profile:' -ForegroundColor Cyan
        Write-Host '  1. Standard  Native taskbar, Snap, clean terminal, and NoBS11 Control. No cleanup.'
        Write-Host '  2. Lean      Adds current-user cleanup and performance settings. No Windows app removal. (recommended)'
        Write-Host '  3. Maximum   Full reference profile. Hardware-sensitive; can remove optional components and services.'
        Write-Host ''
        $selection = (Read-Host 'Profile [2]').Trim()
        $Profile = switch ($selection) {
            { $_ -in @('', '2', 'lean') } { 'Lean'; break }
            { $_ -in @('1', 'standard') } { 'Standard'; break }
            { $_ -in @('3', 'maximum') } { 'Maximum'; break }
            default { throw "Unknown profile choice: $selection" }
        }
    }
}

if ($Profile -eq 'Maximum' -and -not $Force -and -not $WhatIfPreference) {
    Write-Host ''
    Write-Host 'Maximum can remove optional Windows apps, capabilities, and provisioned packages; disable reviewed services and tasks; and run component cleanup.' -ForegroundColor Yellow
    Write-Host 'It preserves Defender, Windows Update, Microsoft Store, WinGet, Gaming Services, drivers, and hardware-control components.'
    $maximumConfirmation = (Read-Host 'Type MAXIMUM to continue').Trim()
    if ($maximumConfirmation -cne 'MAXIMUM') {
        Write-Host 'Maximum profile canceled; nothing was downloaded or changed.' -ForegroundColor Yellow
        return
    }
}

Write-Host ''
Write-Host "Preparing NoBS11 $Profile from the pinned $releaseTag source..." -ForegroundColor Cyan
if (-not $PSCmdlet.ShouldProcess($bootstrapUri, "Download and verify NoBS11 bootstrap ($bootstrapSha256)")) {
    Write-Host 'Online-installer preview complete. No files were downloaded and no settings were changed.' -ForegroundColor Yellow
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ 'User-Agent' = 'NoBS11-OnlineInstaller' }
try {
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $bootstrapUri -OutFile $bootstrapPath
    $actualHash = (Get-FileHash -LiteralPath $bootstrapPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $bootstrapSha256) {
        throw "Bootstrap integrity check failed. Expected $bootstrapSha256 but received $actualHash."
    }

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $bootstrapPath,
        '-Repository', $repository,
        '-Ref', $releaseTag,
        '-Profile', $Profile
    )
    if ($Force) { $arguments += '-Force' }
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "NoBS11 setup exited with code $LASTEXITCODE."
    }
}
finally {
    if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) {
        Remove-Item -LiteralPath $bootstrapPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host 'NoBS11 setup finished. Restart Windows before judging idle memory or process counts.' -ForegroundColor Green
