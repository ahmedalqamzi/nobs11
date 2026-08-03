#requires -Version 7.2
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$checks = [System.Collections.Generic.List[object]]::new()
function Protect-LocalPath {
    param([Parameter(Mandatory)][string]$Value)

    $redactions = [ordered]@{
        $env:LOCALAPPDATA = '%LOCALAPPDATA%'
        $env:APPDATA = '%APPDATA%'
        $env:USERPROFILE = '%USERPROFILE%'
    }
    foreach ($entry in $redactions.GetEnumerator()) {
        if ($entry.Key) { $Value = $Value -replace [regex]::Escape([string]$entry.Key), [string]$entry.Value }
    }
    return $Value
}

function Add-Prerequisite {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Present,
        [Parameter(Mandatory)][bool]$Required,
        [Parameter(Mandatory)][string]$Detail
    )
    $checks.Add([pscustomobject]@{
        Name = $Name
        Status = if ($Present) { 'pass' } elseif ($Required) { 'fail' } else { 'optional' }
        Detail = $Detail
    })
}

$windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$windows11 = [int]$windows.CurrentBuild -ge 22000
Add-Prerequisite 'Windows 11' $windows11 $true "Version=$($windows.DisplayVersion), build=$($windows.CurrentBuild).$($windows.UBR)"
Add-Prerequisite 'PowerShell 7.2+' ($PSVersionTable.PSVersion -ge [version]'7.2') $true $PSVersionTable.PSVersion.ToString()

$git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
Add-Prerequisite 'Git' ([bool]$git) $true $(if ($git) { Protect-LocalPath $git.Source } else { 'Install Git.Git with WinGet' })

$winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
Add-Prerequisite 'WinGet' (Test-Path -LiteralPath $winget -PathType Leaf) $true (Protect-LocalPath $winget)

$bash = 'C:\msys64\usr\bin\bash.exe'
Add-Prerequisite 'MSYS2 UCRT64' (Test-Path -LiteralPath $bash -PathType Leaf) $true $bash

$terminalPackage = Get-AppxPackage Microsoft.WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
Add-Prerequisite 'Windows Terminal' ([bool]$terminalPackage) $true $(if ($terminalPackage) { $terminalPackage.Version.ToString() } else { 'Install Microsoft.WindowsTerminal with WinGet' })

$brave = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe'
Add-Prerequisite 'Brave browser profile' (Test-Path -LiteralPath $brave -PathType Leaf) $false $(if (Test-Path -LiteralPath $brave -PathType Leaf) { Protect-LocalPath $brave } else { 'Optional; required only for make browser' })

$checks | Format-Table Status, Name, Detail -Wrap -AutoSize
$failures = @($checks | Where-Object Status -eq 'fail')
Write-Host "Prerequisites: $($checks.Count - $failures.Count) ready, $($failures.Count) required item(s) missing."
if ($failures.Count -gt 0) { exit 1 }
