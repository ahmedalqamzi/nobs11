#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [switch]$Force,
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$latestResultPath = Join-Path $projectRoot 'logs\nvidia-app-repair-latest.json'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    if ($WhatIfPreference) {
        Write-Host 'Would request administrator approval, back up notification settings, restore the Windows notification services, and reload NVIDIA App.' -ForegroundColor Yellow
        return
    }
    if (-not $Force -and -not $PSCmdlet.ShouldContinue(
        'Back up and restore the Windows notification platform required by NVIDIA App?',
        'Repair NVIDIA App?'
    )) {
        Write-Host 'NVIDIA App repair canceled; no changes were made.' -ForegroundColor Yellow
        return
    }

    $pwshPath = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f ($PSCommandPath -replace '"', '\"')),
        '-Elevated',
        '-Force'
    )
    Write-Host 'Administrator approval is required once to restore the notification service templates.' -ForegroundColor Yellow
    $process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "The administrator-approved NVIDIA App repair exited with code $($process.ExitCode)."
    }
    if (Test-Path -LiteralPath $latestResultPath) {
        $result = Get-Content -LiteralPath $latestResultPath -Raw | ConvertFrom-Json
        Write-Host "NVIDIA App repair: $($result.Status)" -ForegroundColor $(if ($result.RestartRequired) { 'Yellow' } else { 'Green' })
        Write-Host "Backup: $($result.BackupPath)"
        if ($result.RestartRequired) {
            Write-Host 'Restart Windows once so it can recreate the per-user notification service.' -ForegroundColor Yellow
        }
    }
    return
}

if (-not $Elevated -and -not $Force -and -not $WhatIfPreference -and -not $PSCmdlet.ShouldContinue(
    'Back up and restore the Windows notification platform required by NVIDIA App?',
    'Repair NVIDIA App?'
)) {
    Write-Host 'NVIDIA App repair canceled; no changes were made.' -ForegroundColor Yellow
    return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-nvidia-app-repair"
$null = New-Item -ItemType Directory -Path $backupRoot -Force
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $latestResultPath) -Force
$changes = [System.Collections.Generic.List[string]]::new()
$restartReasons = [System.Collections.Generic.List[string]]::new()
$restartRequired = $false

function Export-RegistryBackup {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$FileName
    )

    $outputPath = Join-Path $backupRoot $FileName
    & reg.exe export $Key $outputPath /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not back up registry key: $Key" }
}

function Set-RequiredWindowsService {
    param([Parameter(Mandatory)][string]$Name)

    $service = Get-Service -Name $Name -ErrorAction Stop
    if ($service.StartType -ne 'Automatic') {
        Set-Service -Name $Name -StartupType Automatic -ErrorAction Stop
        $changes.Add("$Name startup=Automatic")
    }
    if ($service.Status -ne 'Running') {
        Start-Service -Name $Name -ErrorAction Stop
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
        $changes.Add("$Name state=Running")
    }
}

try {
    Export-RegistryBackup -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -FileName 'PushNotifications.reg'
    Export-RegistryBackup -Key 'HKLM\SYSTEM\CurrentControlSet\Services\WpnService' -FileName 'WpnService.reg'
    Export-RegistryBackup -Key 'HKLM\SYSTEM\CurrentControlSet\Services\WpnUserService' -FileName 'WpnUserService.reg'
    Export-RegistryBackup -Key 'HKLM\SYSTEM\CurrentControlSet\Services\NvContainerLocalSystem' -FileName 'NvContainerLocalSystem.reg'

    $toastPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
    if ($PSCmdlet.ShouldProcess($toastPath, 'Enable the notification platform')) {
        if (-not (Test-Path -LiteralPath $toastPath)) {
            $null = New-Item -Path $toastPath -Force
        }
        $null = New-ItemProperty -LiteralPath $toastPath -Name ToastEnabled -Value 1 -PropertyType DWord -Force
        $changes.Add('ToastEnabled=1')
    }

    $templatePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\WpnUserService'
    if ($PSCmdlet.ShouldProcess($templatePath, 'Restore the per-user notification service template')) {
        $null = New-ItemProperty -LiteralPath $templatePath -Name Start -Value 2 -PropertyType DWord -Force
        $null = New-ItemProperty -LiteralPath $templatePath -Name UserServiceFlags -Value 3 -PropertyType DWord -Force
        $changes.Add('WpnUserService template=Automatic')
    }

    if ($PSCmdlet.ShouldProcess('WpnService', 'Set Automatic and start')) {
        Set-RequiredWindowsService -Name 'WpnService'
    }
    if ($PSCmdlet.ShouldProcess('NvContainerLocalSystem', 'Set Automatic and start')) {
        Set-RequiredWindowsService -Name 'NvContainerLocalSystem'
    }

    $userServices = @(Get-Service -Name 'WpnUserService_*' -ErrorAction SilentlyContinue)
    if ($userServices.Count -eq 0) {
        $restartRequired = $true
        $restartReasons.Add('Windows has not created a per-user notification service for this session.')
    }
    foreach ($service in $userServices) {
        if ($service.Status -eq 'Running') { continue }
        try {
            if ($PSCmdlet.ShouldProcess($service.Name, 'Start the per-user notification service')) {
                Start-Service -Name $service.Name -ErrorAction Stop
                $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
                $changes.Add("$($service.Name) state=Running")
            }
        }
        catch {
            $restartRequired = $true
            $restartReasons.Add("$($service.Name) was created from the previously disabled template and must be recreated at sign-in.")
        }
    }

    if (-not $restartRequired -and $PSCmdlet.ShouldProcess('NvContainerLocalSystem', 'Reload NVIDIA App services')) {
        Restart-Service -Name 'NvContainerLocalSystem' -Force -ErrorAction Stop
        (Get-Service -Name 'NvContainerLocalSystem').WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
        $changes.Add('NvContainerLocalSystem reloaded')

        Get-Process -Name 'NVIDIA App' -ErrorAction SilentlyContinue | Stop-Process -Force
        $nvidiaApp = 'C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe'
        if (Test-Path -LiteralPath $nvidiaApp -PathType Leaf) {
            Start-Process -FilePath $nvidiaApp | Out-Null
            $changes.Add('NVIDIA App relaunched')
        }
    }

    $result = [ordered]@{
        FinishedAt = (Get-Date).ToString('o')
        Status = if ($restartRequired) { 'repaired-restart-required' } else { 'repaired' }
        RestartRequired = $restartRequired
        RestartReasons = @($restartReasons)
        Changes = @($changes)
        BackupPath = $backupRoot
        ToastEnabled = Get-ItemPropertyValue -LiteralPath $toastPath -Name ToastEnabled
        WpnService = (Get-Service -Name 'WpnService').Status.ToString()
        WpnUserService = @((Get-Service -Name 'WpnUserService_*' -ErrorAction SilentlyContinue) | ForEach-Object { "$($_.Name):$($_.Status)" })
        NvContainerLocalSystem = (Get-Service -Name 'NvContainerLocalSystem').Status.ToString()
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backupRoot 'result.json') -Encoding UTF8
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $latestResultPath -Encoding UTF8

    Write-Host "NVIDIA App repair: $($result.Status)" -ForegroundColor $(if ($restartRequired) { 'Yellow' } else { 'Green' })
    Write-Host "Backup: $backupRoot"
    if ($restartRequired) {
        Write-Host 'Restart Windows once so it can recreate the per-user notification service.' -ForegroundColor Yellow
    }
}
catch {
    $failure = [ordered]@{
        FinishedAt = (Get-Date).ToString('o')
        Status = 'failed'
        RestartRequired = $restartRequired
        Error = $_.Exception.Message
        BackupPath = $backupRoot
    }
    $failure | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $latestResultPath -Encoding UTF8
    throw
}
