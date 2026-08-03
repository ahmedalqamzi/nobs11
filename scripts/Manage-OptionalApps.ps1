#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('Audit', 'DisableStartup', 'EnableStartup', 'Uninstall')]
    [string]$Action = 'Audit',
    [string[]]$Name,
    [switch]$Json,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$projectRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $projectRoot 'config\optional-apps.json'
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "Optional-app catalog not found: $catalogPath"
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
if ([int]$catalog.schemaVersion -ne 1) { throw "Unsupported optional-app catalog schema: $($catalog.schemaVersion)" }

$knownNames = @($catalog.apps.name)
if ($Name) {
    # Native-process argument forwarding can collapse an array into one
    # whitespace-separated argument, so accept either commas or whitespace.
    $Name = @($Name | ForEach-Object { $_ -split '[,\s]+' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $unknownNames = @($Name | Where-Object { $_ -notin $knownNames })
    if ($unknownNames.Count -gt 0) {
        throw "Unknown app name(s): $($unknownNames -join ', '). Available names: $($knownNames -join ', ')"
    }
    $selected = @($catalog.apps | Where-Object name -in $Name)
}
elseif ($Action -eq 'Audit') {
    $selected = @($catalog.apps)
}
else {
    Write-Host 'Optional applications:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $catalog.apps.Count; $index++) {
        Write-Host ('  {0}. {1,-24} {2}' -f ($index + 1), $catalog.apps[$index].name, $catalog.apps[$index].description)
    }
    $answer = Read-Host 'Enter one or more numbers separated by commas'
    $indexes = @($answer -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
    $invalidIndexes = @($indexes | Where-Object { $_ -lt 0 -or $_ -ge $catalog.apps.Count })
    if ($indexes.Count -eq 0 -or $invalidIndexes.Count -gt 0) { throw 'No valid application selection was provided.' }
    $selected = @($indexes | Select-Object -Unique | ForEach-Object { $catalog.apps[$_] })
}

$startupFolder = [Environment]::GetFolderPath('Startup')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $projectRoot "backups\$stamp-optional-apps"
$manifest = [ordered]@{
    SchemaVersion = 1
    CreatedAt = (Get-Date).ToString('o')
    Action = $Action
    Selected = @($selected.name)
    StartupShortcuts = [System.Collections.Generic.List[object]]::new()
    RunValues = [System.Collections.Generic.List[object]]::new()
    ScheduledTasks = [System.Collections.Generic.List[object]]::new()
    Services = [System.Collections.Generic.List[object]]::new()
    Results = [System.Collections.Generic.List[object]]::new()
}
$failures = 0

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][ValidateSet('ok', 'unchanged', 'failed', 'what-if')][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    $manifest.Results.Add([pscustomobject]@{ App = $App; Operation = $Operation; Status = $Status; Detail = $Detail })
    if ($Status -eq 'failed') { $script:failures++ }
}

function Get-MatchingProcesses {
    param([Parameter(Mandatory)]$App)

    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    foreach ($rule in @($App.processes)) {
        $processName = ([string]$rule.name) -replace '(?i)\.exe$', ''
        foreach ($process in $all | Where-Object { $_.Name -ieq "$processName.exe" -or $_.Name -ieq $processName }) {
            $needle = [string]$rule.commandLineContains
            if (-not $needle -or [string]$process.CommandLine -like "*$needle*") { $process }
        }
    }
}

function Test-AppInstalled {
    param([Parameter(Mandatory)]$App)

    if ($App.uninstall.kind -eq 'appx') {
        return [bool](Get-AppxPackage -Name ([string]$App.uninstall.value) -ErrorAction SilentlyContinue | Select-Object -First 1)
    }

    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        foreach ($entry in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $properties = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            $displayName = if ($properties -and $properties.PSObject.Properties.Name -contains 'DisplayName') { [string]$properties.DisplayName } else { '' }
            if ($displayName -and $displayName -in @($App.installedDisplayNames)) { return $true }
        }
    }
    return $false
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-WinGetUninstall {
    param(
        [Parameter(Mandatory)][string]$WingetPath,
        [Parameter(Mandatory)][string]$Selector,
        [Parameter(Mandatory)][string]$Value
    )

    $arguments = @('uninstall', $Selector, $Value, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity')
    & $WingetPath @arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) { return }

    if (-not (Test-IsAdministrator)) {
        Write-Host "The $Value uninstaller needs administrator approval; requesting UAC once." -ForegroundColor Yellow
        $elevatedArguments = @(
            'uninstall',
            $Selector,
            ('"{0}"' -f ($Value -replace '"', '\"')),
            '--exact',
            '--silent',
            '--accept-source-agreements',
            '--disable-interactivity'
        )
        $process = Start-Process -FilePath $WingetPath -ArgumentList $elevatedArguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        $exitCode = $process.ExitCode
        if ($exitCode -eq 0) { return }
    }

    throw "WinGet exited with code $exitCode"
}

function Get-RunValueMatches {
    param([Parameter(Mandatory)]$App)

    $runPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($path in $runPaths) {
        $key = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($valueName in $key.GetValueNames()) {
            foreach ($pattern in @($App.runValuePatterns)) {
                if ($valueName -like "*$pattern*") {
                    [pscustomobject]@{ Path = $path; Name = $valueName; Value = $key.GetValue($valueName); Kind = $key.GetValueKind($valueName).ToString() }
                    break
                }
            }
        }
    }
}

function Get-TaskMatches {
    param([Parameter(Mandatory)]$App)

    foreach ($rule in @($App.scheduledTasks)) {
        Get-ScheduledTask -TaskPath ([string]$rule.taskPath) -ErrorAction SilentlyContinue |
            Where-Object TaskName -Like ([string]$rule.taskName)
    }
}

function Test-DisableNeedsElevation {
    param([Parameter(Mandatory)][object[]]$Apps)

    foreach ($app in $Apps) {
        if (@(Get-RunValueMatches -App $app | Where-Object Path -Like 'HKLM:*').Count -gt 0) { return $true }
        if (@(Get-TaskMatches -App $app | Where-Object State -ne 'Disabled').Count -gt 0) { return $true }
        foreach ($serviceName in @($app.services)) {
            $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
            if ($service -and ($service.State -eq 'Running' -or $service.StartMode -eq 'Auto')) { return $true }
        }
    }
    return $false
}

function Get-AppState {
    param([Parameter(Mandatory)]$App)

    $shortcuts = @($App.startupShortcutNames | ForEach-Object { Join-Path $startupFolder $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    $runValues = @(Get-RunValueMatches -App $App)
    $tasks = @(Get-TaskMatches -App $App)
    $services = @($App.services | ForEach-Object { Get-CimInstance Win32_Service -Filter "Name='$($_)'" -ErrorAction SilentlyContinue })
    $processes = @(Get-MatchingProcesses -App $App | Sort-Object ProcessId -Unique)
    $enabledTasks = @($tasks | Where-Object State -ne 'Disabled')
    $activeServices = @($services | Where-Object { $_.State -eq 'Running' -or $_.StartMode -eq 'Auto' })
    $startupEntries = $shortcuts.Count + $runValues.Count + $enabledTasks.Count
    [pscustomobject]@{
        Name = $App.name
        DisplayName = $App.displayName
        Installed = Test-AppInstalled -App $App
        Running = $processes.Count
        StartupEntries = $startupEntries
        BackgroundActive = ($processes.Count -gt 0 -or $startupEntries -gt 0 -or $activeServices.Count -gt 0)
        Services = ($services | ForEach-Object { "$($_.Name):$($_.State)/$($_.StartMode)" }) -join ', '
        Warning = $App.warning
    }
}

if ($Action -eq 'Audit') {
    $states = @($selected | ForEach-Object { Get-AppState -App $_ })
    if ($Json) {
        $states | ConvertTo-Json -Depth 5
    }
    else {
        $states | Format-Table Name, Installed, Running, StartupEntries, Services -Wrap -AutoSize
        Write-Host "Audited $($states.Count) optional application(s); no changes were made." -ForegroundColor Cyan
    }
    return
}

if ($Action -eq 'Uninstall' -and -not $Force -and -not $WhatIfPreference) {
    Write-Host 'Selected uninstall targets:' -ForegroundColor Yellow
    $selected | ForEach-Object { Write-Host "  $($_.displayName): $($_.warning)" }
    if (-not $PSCmdlet.ShouldContinue('Uninstall only the applications listed above?', 'Confirm optional application removal')) {
        Write-Host 'Uninstall canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

if ($Action -eq 'DisableStartup' -and $Force -and -not $WhatIfPreference -and -not (Test-IsAdministrator) -and (Test-DisableNeedsElevation -Apps $selected)) {
    $pwshPath = (Get-Process -Id $PID).Path
    $elevatedArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"{0}"' -f ($PSCommandPath -replace '"', '\"')),
        '-Action',
        $Action,
        '-Name',
        (@($selected.name) -join ','),
        '-Force'
    )
    Write-Host 'Administrator approval is required to change a machine-wide startup source.' -ForegroundColor Yellow
    $elevated = Start-Process -FilePath $pwshPath -ArgumentList $elevatedArguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($elevated.ExitCode -ne 0) { throw "The administrator-approved action exited with code $($elevated.ExitCode)." }
    Write-Host 'Administrator-approved background action completed.' -ForegroundColor Green
    return
}

if (-not $WhatIfPreference) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }

$optionalHistory = @()
if ($Action -eq 'EnableStartup') {
    $historyRoot = Join-Path $projectRoot 'backups'
    $optionalHistory = @(
        Get-ChildItem -LiteralPath $historyRoot -Filter manifest.json -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Directory.Name -like '*-optional-apps' } |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                try { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
                catch { Write-Warning "Ignored unreadable optional-app backup: $($_.FullName)" }
            }
    )
}

function Get-LatestRestoreRecords {
    param(
        [Parameter(Mandatory)][string]$Collection,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string[]]$KeyProperties
    )

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($history in $optionalHistory) {
        foreach ($record in @($history.$Collection | Where-Object { $_.App -eq $AppName })) {
            $key = ($KeyProperties | ForEach-Object { [string]$record.$_ }) -join '|'
            if ($seen.Add($key)) { $record }
        }
    }
}

foreach ($app in $selected) {
    $appName = [string]$app.name

    if ($Action -eq 'EnableStartup') {
        if (-not (Test-AppInstalled -App $app)) {
            Add-Result $appName 'enable-startup' 'unchanged' 'Application is not installed.'
            continue
        }

        $restored = 0
        foreach ($record in @(Get-LatestRestoreRecords -Collection 'StartupShortcuts' -AppName $appName -KeyProperties @('Original'))) {
            if (Test-Path -LiteralPath $record.Original) { continue }
            if (-not (Test-Path -LiteralPath $record.Backup -PathType Leaf)) { continue }
            if ($PSCmdlet.ShouldProcess($record.Original, "Restore $($app.displayName) startup shortcut")) {
                try {
                    New-Item -ItemType Directory -Path (Split-Path -Parent $record.Original) -Force | Out-Null
                    Copy-Item -LiteralPath $record.Backup -Destination $record.Original -Force
                    Add-Result $appName 'enable-startup-shortcut' 'ok' ([string]$record.Original)
                    $restored++
                }
                catch { Add-Result $appName 'enable-startup-shortcut' 'failed' $_.Exception.Message }
            }
            else { Add-Result $appName 'enable-startup-shortcut' 'what-if' ([string]$record.Original) }
        }

        foreach ($record in @(Get-LatestRestoreRecords -Collection 'RunValues' -AppName $appName -KeyProperties @('Path', 'Name'))) {
            $key = Get-Item -LiteralPath $record.Path -ErrorAction SilentlyContinue
            if ($key -and $key.GetValueNames() -contains [string]$record.Name) { continue }
            if ($PSCmdlet.ShouldProcess("$($record.Path)\$($record.Name)", "Restore $($app.displayName) startup value")) {
                try {
                    if (-not (Test-Path -LiteralPath $record.Path)) { New-Item -Path $record.Path -Force | Out-Null }
                    $value = switch ([string]$record.Kind) {
                        'Binary' { [byte[]]@($record.Value | ForEach-Object { [byte]$_ }) }
                        'DWord' { [int]$record.Value }
                        'QWord' { [long]$record.Value }
                        'MultiString' { [string[]]@($record.Value) }
                        default { [string]$record.Value }
                    }
                    New-ItemProperty -LiteralPath $record.Path -Name $record.Name -Value $value -PropertyType $record.Kind -Force | Out-Null
                    Add-Result $appName 'enable-run-value' 'ok' ([string]$record.Name)
                    $restored++
                }
                catch { Add-Result $appName 'enable-run-value' 'failed' $_.Exception.Message }
            }
            else { Add-Result $appName 'enable-run-value' 'what-if' ([string]$record.Name) }
        }

        foreach ($record in @(Get-LatestRestoreRecords -Collection 'ScheduledTasks' -AppName $appName -KeyProperties @('TaskPath', 'TaskName'))) {
            if ([string]$record.State -eq 'Disabled') { continue }
            $task = Get-ScheduledTask -TaskPath $record.TaskPath -TaskName $record.TaskName -ErrorAction SilentlyContinue
            if (-not $task -or $task.State -ne 'Disabled') { continue }
            if ($PSCmdlet.ShouldProcess("$($record.TaskPath)$($record.TaskName)", "Re-enable $($app.displayName) startup task")) {
                try {
                    Enable-ScheduledTask -InputObject $task | Out-Null
                    Add-Result $appName 'enable-scheduled-task' 'ok' "$($record.TaskPath)$($record.TaskName)"
                    $restored++
                }
                catch { Add-Result $appName 'enable-scheduled-task' 'failed' $_.Exception.Message }
            }
            else { Add-Result $appName 'enable-scheduled-task' 'what-if' "$($record.TaskPath)$($record.TaskName)" }
        }

        foreach ($record in @(Get-LatestRestoreRecords -Collection 'Services' -AppName $appName -KeyProperties @('Name'))) {
            $service = Get-Service -Name $record.Name -ErrorAction SilentlyContinue
            if (-not $service) { continue }
            $startupType = switch ([string]$record.StartMode) {
                'Auto' { 'Automatic' }
                'Automatic' { 'Automatic' }
                'Disabled' { 'Disabled' }
                default { 'Manual' }
            }
            if ($PSCmdlet.ShouldProcess($record.Name, "Restore $($app.displayName) service startup type to $startupType")) {
                try {
                    Set-Service -Name $record.Name -StartupType $startupType -ErrorAction Stop
                    if ([string]$record.State -eq 'Running') { Start-Service -Name $record.Name -ErrorAction Stop }
                    Add-Result $appName 'enable-service' 'ok' "$($record.Name):$startupType"
                    $restored++
                }
                catch { Add-Result $appName 'enable-service' 'failed' $_.Exception.Message }
            }
            else { Add-Result $appName 'enable-service' 'what-if' "$($record.Name):$startupType" }
        }

        if ($restored -eq 0 -and (@($manifest.Results | Where-Object App -eq $appName)).Count -eq 0) {
            Add-Result $appName 'enable-startup' 'unchanged' 'No disabled startup state was found to restore.'
        }
        continue
    }

    foreach ($process in @(Get-MatchingProcesses -App $app | Sort-Object ProcessId -Unique)) {
        if ($PSCmdlet.ShouldProcess("$($process.Name) PID $($process.ProcessId)", "Stop $($app.displayName) background process")) {
            try {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
                Add-Result $appName 'stop-process' 'ok' "$($process.Name) PID $($process.ProcessId)"
            }
            catch { Add-Result $appName 'stop-process' 'failed' $_.Exception.Message }
        }
        else { Add-Result $appName 'stop-process' 'what-if' "$($process.Name) PID $($process.ProcessId)" }
    }

    foreach ($shortcutName in @($app.startupShortcutNames)) {
        $shortcutPath = Join-Path $startupFolder $shortcutName
        if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { continue }
        $backupPath = Join-Path $backupRoot "startup\$appName\$shortcutName"
        $manifest.StartupShortcuts.Add([pscustomobject]@{ App = $appName; Original = $shortcutPath; Backup = $backupPath })
        if ($PSCmdlet.ShouldProcess($shortcutPath, "Remove $($app.displayName) from user startup")) {
            try {
                New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
                Copy-Item -LiteralPath $shortcutPath -Destination $backupPath -Force
                Remove-Item -LiteralPath $shortcutPath -Force
                Add-Result $appName 'disable-startup-shortcut' 'ok' $shortcutName
            }
            catch { Add-Result $appName 'disable-startup-shortcut' 'failed' $_.Exception.Message }
        }
        else { Add-Result $appName 'disable-startup-shortcut' 'what-if' $shortcutName }
    }

    foreach ($runValue in @(Get-RunValueMatches -App $app)) {
        $manifest.RunValues.Add([pscustomobject]@{ App = $appName; Path = $runValue.Path; Name = $runValue.Name; Value = $runValue.Value; Kind = $runValue.Kind })
        if ($PSCmdlet.ShouldProcess("$($runValue.Path)\$($runValue.Name)", "Remove $($app.displayName) startup value")) {
            try {
                Remove-ItemProperty -LiteralPath $runValue.Path -Name $runValue.Name -Force
                Add-Result $appName 'disable-run-value' 'ok' $runValue.Name
            }
            catch { Add-Result $appName 'disable-run-value' 'failed' $_.Exception.Message }
        }
        else { Add-Result $appName 'disable-run-value' 'what-if' $runValue.Name }
    }

    foreach ($task in @(Get-TaskMatches -App $app)) {
        $manifest.ScheduledTasks.Add([pscustomobject]@{ App = $appName; TaskPath = $task.TaskPath; TaskName = $task.TaskName; State = $task.State.ToString() })
        if ($task.State -ne 'Disabled' -and $PSCmdlet.ShouldProcess("$($task.TaskPath)$($task.TaskName)", "Disable $($app.displayName) startup task")) {
            try {
                Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName | Out-Null
                Stop-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction SilentlyContinue
                Add-Result $appName 'disable-scheduled-task' 'ok' "$($task.TaskPath)$($task.TaskName)"
            }
            catch { Add-Result $appName 'disable-scheduled-task' 'failed' $_.Exception.Message }
        }
    }

    foreach ($serviceName in @($app.services)) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if (-not $service) { continue }
        $manifest.Services.Add([pscustomobject]@{ App = $appName; Name = $service.Name; State = $service.State; StartMode = $service.StartMode })
        $needsStop = $service.State -eq 'Running'
        $needsManual = $service.StartMode -eq 'Auto'
        if (-not $needsStop -and -not $needsManual) {
            Add-Result $appName 'set-service-manual' 'unchanged' "$($service.Name) is already stopped without automatic startup."
            continue
        }
        if ($PSCmdlet.ShouldProcess($service.Name, "Stop $($app.displayName) service and set it to manual start")) {
            try {
                if ($needsStop) { Stop-Service -Name $service.Name -Force -ErrorAction Stop }
                if ($needsManual) { Set-Service -Name $service.Name -StartupType Manual -ErrorAction Stop }
                Add-Result $appName 'set-service-manual' 'ok' $service.Name
            }
            catch { Add-Result $appName 'set-service-manual' 'failed' $_.Exception.Message }
        }
        else { Add-Result $appName 'set-service-manual' 'what-if' $service.Name }
    }

    if ($Action -ne 'Uninstall' -or -not (Test-AppInstalled -App $app)) { continue }

    $uninstallKind = [string]$app.uninstall.kind
    $uninstallValue = [string]$app.uninstall.value
    if (-not $PSCmdlet.ShouldProcess($app.displayName, "Uninstall using $uninstallKind")) {
        Add-Result $appName 'uninstall' 'what-if' $uninstallValue
        continue
    }

    try {
        if ($uninstallKind -eq 'appx') {
            $packages = @(Get-AppxPackage -Name $uninstallValue -ErrorAction SilentlyContinue)
            foreach ($package in $packages) { Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop }
        }
        else {
            $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
            if (-not (Test-Path -LiteralPath $winget -PathType Leaf)) { throw 'WinGet was not found.' }
            $selector = if ($uninstallKind -eq 'wingetId') { '--id' } elseif ($uninstallKind -eq 'wingetName') { '--name' } else { throw "Unsupported uninstall kind: $uninstallKind" }
            Invoke-WinGetUninstall -WingetPath $winget -Selector $selector -Value $uninstallValue
        }
        Add-Result $appName 'uninstall' 'ok' $uninstallValue
    }
    catch { Add-Result $appName 'uninstall' 'failed' $_.Exception.Message }
}

if (-not $WhatIfPreference) {
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $backupRoot 'manifest.json') -Encoding utf8NoBOM
}

$manifest.Results | Format-Table Status, App, Operation, Detail -Wrap -AutoSize
if ($WhatIfPreference) {
    Write-Host 'Optional-app preview complete; no changes were made.' -ForegroundColor Yellow
}
else {
    Write-Host "Optional-app action complete. Backup manifest: $backupRoot" -ForegroundColor Green
}
if ($failures -gt 0) { exit 1 }
