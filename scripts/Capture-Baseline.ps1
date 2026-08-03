[CmdletBinding()]
param(
    [string]$Label = 'pre-linux-shell'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safeLabel = $Label -replace '[^a-zA-Z0-9._-]', '-'
$outputRoot = Join-Path $projectRoot "baseline\$stamp-$safeLabel"
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 8
    )

    $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-Capture {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    try {
        & $Action
        [pscustomobject]@{ Name = $Name; Status = 'ok'; Error = $null }
    }
    catch {
        [pscustomobject]@{ Name = $Name; Status = 'unavailable'; Error = $_.Exception.Message }
    }
}

$captureResults = [System.Collections.Generic.List[object]]::new()

$captureResults.Add((Invoke-Capture 'system' {
    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $system = [ordered]@{
        CapturedAt = (Get-Date).ToString('o')
        User = "$env:USERDOMAIN\$env:USERNAME"
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $computer.Manufacturer
        Model = $computer.Model
        TotalMemoryBytes = [int64]$computer.TotalPhysicalMemory
        WindowsCaption = $os.Caption
        WindowsVersion = $os.Version
        WindowsBuild = $os.BuildNumber
        LastBoot = $os.LastBootUpTime
        BiosVersion = ($bios.SMBIOSBIOSVersion -join ', ')
        BiosReleaseDate = $bios.ReleaseDate
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    }
    Write-JsonFile $system (Join-Path $outputRoot 'system.json')
}))

$captureResults.Add((Invoke-Capture 'pending-reboot' {
    $pending = [ordered]@{
        ComponentBasedServicing = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        PendingFileRename = [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
    }
    Write-JsonFile $pending (Join-Path $outputRoot 'pending-reboot.json')
}))

$captureResults.Add((Invoke-Capture 'winget-export' {
    & winget export --output (Join-Path $outputRoot 'winget-export.json') --include-versions --accept-source-agreements --disable-interactivity | Out-File (Join-Path $outputRoot 'winget-export.log') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'winget-list' {
    & winget list --accept-source-agreements --disable-interactivity | Out-File (Join-Path $outputRoot 'winget-list.txt') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'appx' {
    Get-AppxPackage | Select-Object Name, PackageFullName, PackageFamilyName, Version, InstallLocation, SignatureKind, Status |
        ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outputRoot 'appx-packages.json') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'startup' {
    $startup = [ordered]@{
        Cim = @(Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User)
        CurrentUserRun = @(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Select-Object * -ExcludeProperty PS*)
        LocalMachineRun = @(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Select-Object * -ExcludeProperty PS*)
    }
    Write-JsonFile $startup (Join-Path $outputRoot 'startup.json') 6
}))

$captureResults.Add((Invoke-Capture 'services' {
    Get-CimInstance Win32_Service | Sort-Object Name | Select-Object Name, DisplayName, State, StartMode, PathName, StartName |
        ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outputRoot 'services.json') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'scheduled-tasks' {
    Get-ScheduledTask | Sort-Object TaskPath, TaskName | Select-Object TaskPath, TaskName, State, Author, Description |
        ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outputRoot 'scheduled-tasks.json') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'processes' {
    $processes = Get-Process | Sort-Object WorkingSet64 -Descending
    $summary = [ordered]@{
        Count = @($processes).Count
        TotalWorkingSetBytes = [int64](($processes | Measure-Object WorkingSet64 -Sum).Sum)
        TopByWorkingSet = @($processes | Select-Object -First 30 Name, Id, CPU, WorkingSet64, Path)
    }
    Write-JsonFile $summary (Join-Path $outputRoot 'processes.json') 5
}))

$captureResults.Add((Invoke-Capture 'performance-sample' {
    $counters = Get-Counter -Counter '\Processor(_Total)\% Processor Time', '\Memory\Available MBytes', '\System\Processes' -SampleInterval 1 -MaxSamples 5
    $counters.CounterSamples | Select-Object Timestamp, Path, CookedValue |
        Export-Csv -LiteralPath (Join-Path $outputRoot 'performance-samples.csv') -NoTypeInformation -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'drives' {
    Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID, VolumeName, FileSystem, DriveType, Size, FreeSpace |
        ConvertTo-Json -Depth 3 | Set-Content (Join-Path $outputRoot 'drives.json') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'power' {
    & powercfg.exe /batteryreport /output (Join-Path $outputRoot 'battery-report.html') | Out-File (Join-Path $outputRoot 'battery-report.log') -Encoding utf8
    & powercfg.exe /systempowerreport /output (Join-Path $outputRoot 'system-power-report.html') | Out-File (Join-Path $outputRoot 'system-power-report.log') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'defender-status' {
    Get-MpComputerStatus | Select-Object AMServiceEnabled, AntivirusEnabled, AntispywareEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled, OnAccessProtectionEnabled, RealTimeProtectionEnabled, AntivirusSignatureVersion, AntivirusSignatureLastUpdated |
        ConvertTo-Json -Depth 3 | Set-Content (Join-Path $outputRoot 'defender-status.json') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'restore-points' {
    Get-ComputerRestorePoint -ErrorAction Stop | Select-Object SequenceNumber, Description, CreationTime, RestorePointType, EventType |
        ConvertTo-Json -Depth 3 | Set-Content (Join-Path $outputRoot 'restore-points.json') -Encoding utf8
}))

$captureResults.Add((Invoke-Capture 'bitlocker-status' {
    # Status only. Recovery passwords are intentionally never captured.
    & manage-bde.exe -status C: | Out-File (Join-Path $outputRoot 'bitlocker-status.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "manage-bde exited with code $LASTEXITCODE" }
}))

$captureResults.Add((Invoke-Capture 'terminal-settings' {
    $terminalSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $terminalSettings)) { throw 'Windows Terminal settings were not found.' }
    Copy-Item -LiteralPath $terminalSettings -Destination (Join-Path $outputRoot 'terminal-settings.json')
}))

$captureResults.Add((Invoke-Capture 'taskbar-registry' {
    & reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' (Join-Path $outputRoot 'explorer-advanced.reg') /y | Out-Null
    & reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' (Join-Path $outputRoot 'theme-personalize.reg') /y | Out-Null
}))

Write-JsonFile $captureResults (Join-Path $outputRoot 'capture-results.json') 4
$captureResults | Format-Table -AutoSize
Write-Host "Baseline captured at: $outputRoot" -ForegroundColor Green
