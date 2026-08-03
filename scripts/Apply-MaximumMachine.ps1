#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$machineScript = Join-Path $PSScriptRoot 'Apply-Barebones-Machine.ps1'
$pwshRunner = Join-Path $PSScriptRoot 'Invoke-Pwsh.ps1'
$performanceScript = Join-Path $PSScriptRoot 'Apply-AtlasPerformance.ps1'

foreach ($requiredFile in @($machineScript, $pwshRunner, $performanceScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Maximum-profile source is incomplete: $requiredFile"
    }
}

$machineArguments = @()
if ($Force) { $machineArguments += '-Force' }
& $machineScript @machineArguments

$performanceArguments = @(
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $pwshRunner,
    '-ScriptPath', $performanceScript
)
if ($Force) { $performanceArguments += '-Force' }
& powershell.exe @performanceArguments
if ($LASTEXITCODE -ne 0) {
    throw "Elevated performance profile exited with code $LASTEXITCODE."
}

Write-Host "Maximum machine profile complete. Rollback data remains under $projectRoot\backups." -ForegroundColor Green
