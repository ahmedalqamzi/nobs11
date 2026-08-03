#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$AuditOnly,
    [switch]$IncludeAppRemoval,
    [switch]$IncludeIdentity
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'config\startup-policy.json'
$logPath = Join-Path $projectRoot 'logs\startup-guard.log'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$quarantineRoot = Join-Path $projectRoot "backups\startup-guard\$stamp"

if (-not (Test-Path -LiteralPath $configPath)) { throw "Startup policy not found: $configPath" }
$policy = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$actions = [System.Collections.Generic.List[object]]::new()
$failures = 0
$mutex = [Threading.Mutex]::new($false, 'Local\WindowsLinuxWorkstationStartupGuard')
$lockTaken = $false

function Write-Audit {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force | Out-Null
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ssK'), $Level, $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
    Write-Host $line
}

try {
    $lockTaken = $mutex.WaitOne(0)
    if (-not $lockTaken) {
        Write-Audit WARN 'Another startup-guard instance is already running; exiting.'
        exit 0
    }

    Write-Audit INFO "Startup guard beginning. AuditOnly=$AuditOnly IncludeAppRemoval=$IncludeAppRemoval"

    $braveConfigurator = Join-Path $PSScriptRoot 'Configure-Brave.ps1'
    if (Test-Path -LiteralPath $braveConfigurator) {
        try {
            $powerShellExecutable = (Get-Process -Id $PID).Path
            $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $braveConfigurator, '-NoBackup')
            $readOnlyMode = $AuditOnly -or $WhatIfPreference
            if ($readOnlyMode) { $arguments += '-AuditOnly' }
            $output = (& $powerShellExecutable @arguments 2>&1 | Out-String).Trim()
            $configuratorExitCode = $LASTEXITCODE
            $summary = if ($output) { $output | ConvertFrom-Json } else { $null }

            if ($configuratorExitCode -eq 2 -and $readOnlyMode) {
                $actions.Add([pscustomobject]@{ Type = 'BraveProfile'; Status = 'drift'; Detail = $summary })
                Write-Audit WARN 'Brave low-memory profile drift detected.'
            }
            elseif ($configuratorExitCode -notin @(0, $null)) {
                $failures++
                $actions.Add([pscustomobject]@{ Type = 'BraveProfile'; Status = 'failed'; Detail = $output })
                Write-Audit ERROR "Brave profile configurator exited with code $configuratorExitCode."
            }
            elseif ($summary -and [int]$summary.Changed -gt 0) {
                $actions.Add([pscustomobject]@{ Type = 'BraveProfile'; Status = 'configured'; Detail = $summary })
                Write-Audit OK 'Reapplied the Brave low-memory profile.'
            }
        }
        catch {
            $failures++
            $actions.Add([pscustomobject]@{ Type = 'BraveProfile'; Status = 'failed'; Error = $_.Exception.Message })
            Write-Audit ERROR "Failed to enforce the Brave profile: $($_.Exception.Message)"
        }
    }

    foreach ($packageName in @($policy.blockedAppPackages)) {
        foreach ($package in @(Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue)) {
            $record = [ordered]@{
                Type = 'BlockedAppPackage'
                Name = $package.Name
                PackageFullName = $package.PackageFullName
                PackageFamilyName = $package.PackageFamilyName
                Version = $package.Version.ToString()
                InstallLocation = $package.InstallLocation
                Status = 'detected'
            }
            $actions.Add($record)

            if ($AuditOnly -or -not $IncludeAppRemoval) {
                Write-Audit WARN "Blocked app detected: $($package.Name)"
                continue
            }

            if ($PSCmdlet.ShouldProcess($package.PackageFullName, 'Remove denylisted app for current user')) {
                try {
                    Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                    $record.Status = if (Get-AppxPackage -Name $package.Name -ErrorAction SilentlyContinue) { 'failed' } else { 'removed' }
                    if ($record.Status -eq 'removed') {
                        Write-Audit OK "Removed reappearing blocked app: $($package.Name)"
                    }
                    else {
                        $failures++
                        Write-Audit ERROR "Blocked app remained registered: $($package.Name)"
                    }
                }
                catch {
                    $record.Status = 'failed'
                    $record.Error = $_.Exception.Message
                    $failures++
                    Write-Audit ERROR "Failed to remove blocked app $($package.Name): $($_.Exception.Message)"
                }
            }
        }
    }

    foreach ($setting in @($policy.enforcedRegistryValues)) {
        $path = [string]$setting.path
        $name = [string]$setting.name
        $type = [string]$setting.type
        $expectedValue = switch ($type) {
            'Binary' { [byte[]]@($setting.value | ForEach-Object { [byte]$_ }) }
            'DWord' { [int]$setting.value }
            'QWord' { [long]$setting.value }
            default { [string]$setting.value }
        }

        $key = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        $exists = $key -and (@($key.GetValueNames()) -contains $name)
        $currentValue = if ($exists) {
            $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        else {
            $null
        }
        $matches = if (-not $exists) {
            $false
        }
        elseif ($type -eq 'Binary') {
            [Convert]::ToBase64String([byte[]]$currentValue) -eq [Convert]::ToBase64String([byte[]]$expectedValue)
        }
        else {
            [string]$currentValue -eq [string]$expectedValue
        }

        if ($matches) { continue }

        $record = [ordered]@{
            Type = 'EnforcedRegistryValue'
            Path = $path
            Name = $name
            ValueType = $type
            PreviousExists = [bool]$exists
            PreviousKind = if ($exists) { $key.GetValueKind($name).ToString() } else { $null }
            PreviousValue = if ($type -eq 'Binary' -and $exists) { @([byte[]]$currentValue) } else { $currentValue }
            DesiredValue = if ($type -eq 'Binary') { @([byte[]]$expectedValue) } else { $expectedValue }
            Status = 'detected'
        }
        $actions.Add($record)

        if ($AuditOnly) {
            Write-Audit WARN "Low-memory registry value drifted: $path::$name"
            continue
        }

        if ($PSCmdlet.ShouldProcess("$path::$name", "Set low-memory registry value to $expectedValue")) {
            try {
                if (-not (Test-Path -LiteralPath $path)) {
                    New-Item -Path $path -Force | Out-Null
                }
                New-ItemProperty -LiteralPath $path -Name $name -Value $expectedValue -PropertyType $type -Force | Out-Null
                $record.Status = 'set'
                Write-Audit OK "Enforced low-memory registry value: $path::$name"
            }
            catch {
                $record.Status = 'failed'
                $record.Error = $_.Exception.Message
                $failures++
                Write-Audit ERROR "Failed to enforce $path::$name`: $($_.Exception.Message)"
            }
        }
    }

    $scheduledTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    foreach ($rule in @($policy.blockedScheduledTasks)) {
        $taskPathPattern = [string]$rule.taskPath
        $taskNamePattern = [string]$rule.taskName
        foreach ($task in @($scheduledTasks | Where-Object { $_.TaskPath -like $taskPathPattern -and $_.TaskName -like $taskNamePattern })) {
            if ($task.State -eq 'Disabled') { continue }

            $record = [ordered]@{
                Type = 'ScheduledTask'
                Path = $task.TaskPath
                Name = $task.TaskName
                PreviousState = $task.State.ToString()
                Status = 'detected'
            }
            $actions.Add($record)

            if ($AuditOnly) {
                Write-Audit WARN "Low-memory scheduled task enabled: $($task.TaskPath)$($task.TaskName)"
                continue
            }

            if ($PSCmdlet.ShouldProcess("$($task.TaskPath)$($task.TaskName)", 'Disable low-memory denylisted scheduled task')) {
                try {
                    Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
                    $record.Status = 'disabled'
                    Write-Audit OK "Disabled low-memory scheduled task: $($task.TaskPath)$($task.TaskName)"
                }
                catch {
                    $record.Status = 'failed'
                    $record.Error = $_.Exception.Message
                    $failures++
                    Write-Audit ERROR "Failed to disable scheduled task $($task.TaskPath)$($task.TaskName): $($_.Exception.Message)"
                }
            }
        }
    }

    $handledProcessIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($pattern in @($policy.blockedProcessPatterns)) {
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like [string]$pattern })) {
            if (-not $handledProcessIds.Add($process.Id)) { continue }

            $record = [ordered]@{
                Type = 'BackgroundProcess'
                Name = $process.ProcessName
                Id = $process.Id
                WorkingSetMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
                Status = 'detected'
            }
            $actions.Add($record)

            if ($AuditOnly) {
                Write-Audit WARN "Low-memory blocked background process is running: $($process.ProcessName) ($($process.Id))"
                continue
            }

            if ($PSCmdlet.ShouldProcess("$($process.ProcessName) ($($process.Id))", 'Stop low-memory blocked background process')) {
                try {
                    if ($process.ProcessName -eq 'OneDrive' -and $process.Path) {
                        Start-Process -FilePath $process.Path -ArgumentList '/shutdown' -WindowStyle Hidden -Wait
                        Start-Sleep -Milliseconds 750
                    }
                    if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
                        Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    }
                    $record.Status = 'stopped'
                    Write-Audit OK "Stopped low-memory background process: $($process.ProcessName) ($($process.Id))"
                }
                catch {
                    if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
                        $record.Status = 'failed'
                        $record.Error = $_.Exception.Message
                        $failures++
                        Write-Audit ERROR "Failed to stop $($process.ProcessName) ($($process.Id)): $($_.Exception.Message)"
                    }
                    else {
                        $record.Status = 'stopped'
                        Write-Audit OK "Stopped low-memory background process: $($process.ProcessName) ($($process.Id))"
                    }
                }
            }
        }
    }

    $runRules = @($policy.blockedCurrentUserRunValues)
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runKey = Get-Item -LiteralPath $runPath -ErrorAction SilentlyContinue
    if ($runKey) {
        foreach ($name in @($runKey.GetValueNames())) {
            $blocked = @($runRules | Where-Object { $name -like [string]$_ }).Count -gt 0
            if (-not $blocked) { continue }

            $record = [ordered]@{
                Type = 'RegistryRun'
                Path = $runPath
                Name = $name
                Kind = $runKey.GetValueKind($name).ToString()
                Value = $runKey.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                Status = 'detected'
            }
            $actions.Add($record)

            if ($AuditOnly) {
                Write-Audit WARN "Blocked current-user startup value detected: $name"
                continue
            }

            if ($PSCmdlet.ShouldProcess("$runPath::$name", 'Quarantine current-user startup value')) {
                try {
                    Remove-ItemProperty -LiteralPath $runPath -Name $name -ErrorAction Stop
                    $record.Status = 'removed'
                    Write-Audit OK "Quarantined current-user startup value: $name"
                }
                catch {
                    $record.Status = 'failed'
                    $record.Error = $_.Exception.Message
                    $failures++
                    Write-Audit ERROR "Failed to quarantine startup value $name`: $($_.Exception.Message)"
                }
            }
        }
    }

    $startupRules = @($policy.blockedStartupItems)
    $startupFolder = [Environment]::GetFolderPath('Startup')
    foreach ($item in @(Get-ChildItem -LiteralPath $startupFolder -Force -ErrorAction SilentlyContinue)) {
        $blocked = @($startupRules | Where-Object { $item.Name -like [string]$_ }).Count -gt 0
        if (-not $blocked) { continue }

        $record = [ordered]@{
            Type = 'StartupItem'
            Name = $item.Name
            OriginalPath = $item.FullName
            QuarantinePath = $null
            Status = 'detected'
        }
        $actions.Add($record)

        if ($AuditOnly) {
            Write-Audit WARN "Unapproved Startup-folder item detected: $($item.Name)"
            continue
        }

        if ($PSCmdlet.ShouldProcess($item.FullName, 'Move Startup-folder item to quarantine')) {
            try {
                New-Item -ItemType Directory -Path $quarantineRoot -Force | Out-Null
                $destination = Join-Path $quarantineRoot $item.Name
                if (Test-Path -LiteralPath $destination) {
                    $destination = Join-Path $quarantineRoot ("{0}-{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($item.Name), [guid]::NewGuid().ToString('N'), [IO.Path]::GetExtension($item.Name))
                }
                Move-Item -LiteralPath $item.FullName -Destination $destination
                $record.QuarantinePath = $destination
                $record.Status = 'moved'
                Write-Audit OK "Moved Startup-folder item to quarantine: $($item.Name)"
            }
            catch {
                $record.Status = 'failed'
                $record.Error = $_.Exception.Message
                $failures++
                Write-Audit ERROR "Failed to quarantine Startup item $($item.Name): $($_.Exception.Message)"
            }
        }
    }

    if ($actions.Count -gt 0) {
        New-Item -ItemType Directory -Path $quarantineRoot -Force | Out-Null
        $snapshot = [ordered]@{
            CapturedAt = (Get-Date).ToString('o')
            AuditOnly = [bool]$AuditOnly
            Policy = $configPath
            Actions = $actions
        }
        if ($IncludeIdentity) {
            $snapshot['User'] = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $quarantineRoot 'actions.json') -Encoding utf8NoBOM
    }

    Write-Audit INFO "Startup guard complete. Findings=$($actions.Count) Failures=$failures"
    if ($failures -gt 0) { exit 2 }
}
finally {
    if ($lockTaken) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
