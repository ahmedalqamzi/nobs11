#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('Audit', 'Disable', 'Enable')]
    [string]$Action = 'Audit',
    [string[]]$Id,
    [switch]$Json,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$runtimeRoot = Join-Path $env:LOCALAPPDATA 'WindowsLinuxWorkstation'
$stateRoot = Join-Path $runtimeRoot 'state'
$statePath = Join-Path $stateRoot 'disabled-user-startup.json'
$disabledFilesRoot = Join-Path $stateRoot 'disabled-startup-files'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupFolder = [Environment]::GetFolderPath('Startup')

function New-StartupId {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Name
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes("$Type`0$Name")
    return ([Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
}

function Convert-RegistryValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Kind
    )

    switch ($Kind) {
        'Binary' { return [byte[]]@($Value | ForEach-Object { [byte]$_ }) }
        'DWord' { return [int]$Value }
        'QWord' { return [long]$Value }
        'MultiString' { return [string[]]@($Value) }
        default { return [string]$Value }
    }
}

$stateEntries = [Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $savedState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ([int]$savedState.schemaVersion -ne 1) { throw "Unsupported user-startup state schema: $($savedState.schemaVersion)" }
    foreach ($entry in @($savedState.entries)) { $stateEntries.Add($entry) }
}

function Save-State {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $payload = [ordered]@{
        schemaVersion = 1
        updatedAt = (Get-Date).ToString('o')
        entries = @($stateEntries)
    }
    $temporaryPath = "$statePath.tmp"
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding utf8NoBOM
    Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
}

function Get-EnabledItems {
    $items = [Collections.Generic.List[object]]::new()
    $runKey = Get-Item -LiteralPath $runPath -ErrorAction SilentlyContinue
    if ($runKey) {
        foreach ($name in $runKey.GetValueNames()) {
            $items.Add([pscustomobject]@{
                Id = New-StartupId -Type 'RegistryRun' -Name $name
                Name = $name
                Source = 'Current-user Run registry'
                Command = [string]$runKey.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                Status = 'Enabled'
                Type = 'RegistryRun'
                Path = $runPath
                Kind = $runKey.GetValueKind($name).ToString()
                Value = $runKey.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            })
        }
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $startupFolder -File -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini')) {
        $items.Add([pscustomobject]@{
            Id = New-StartupId -Type 'StartupFile' -Name $item.Name
            Name = $item.Name
            Source = 'Current-user Startup folder'
            Command = $item.FullName
            Status = 'Enabled'
            Type = 'StartupFile'
            Path = $item.FullName
            Kind = $null
            Value = $null
        })
    }
    return @($items)
}

function Get-AllItems {
    $enabled = @(Get-EnabledItems)
    $enabledIds = @($enabled | ForEach-Object { $_.Id })
    $disabled = @(
        $stateEntries |
            Where-Object { $_.Id -notin $enabledIds } |
            ForEach-Object {
                [pscustomobject]@{
                    Id = $_.Id
                    Name = $_.Name
                    Source = $_.Source
                    Command = if ($_.Type -eq 'RegistryRun') { [string]$_.Value } else { [string]$_.OriginalPath }
                    Status = 'Disabled'
                    Type = $_.Type
                    Path = if ($_.Type -eq 'RegistryRun') { [string]$_.Path } else { [string]$_.OriginalPath }
                    Kind = $_.Kind
                    Value = $_.Value
                }
            }
    )
    return @($enabled + $disabled | Sort-Object Status, Name)
}

$allItems = @(Get-AllItems)
if ($Action -eq 'Audit') {
    if ($Json) {
        ConvertTo-Json -InputObject @($allItems) -Depth 6
    }
    else {
        $allItems | Format-Table Name, Status, Source, Command -Wrap -AutoSize
        Write-Host "Audited $($allItems.Count) current-user startup item(s); no changes were made." -ForegroundColor Cyan
    }
    return
}

$eligibleStatus = if ($Action -eq 'Disable') { 'Enabled' } else { 'Disabled' }
$eligible = @($allItems | Where-Object Status -eq $eligibleStatus)
if ($Id) {
    $Id = @($Id | ForEach-Object { $_ -split '[,\s]+' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    $eligibleIds = @($eligible | ForEach-Object { $_.Id })
    $unknown = @($Id | Where-Object { $_ -notin $eligibleIds })
    if ($unknown.Count -gt 0) { throw "Unknown or ineligible startup item ID(s): $($unknown -join ', ')" }
    $selected = @($eligible | Where-Object Id -in $Id)
}
else {
    if ($eligible.Count -eq 0) {
        Write-Host "No $($eligibleStatus.ToLowerInvariant()) current-user startup items are available." -ForegroundColor Cyan
        return
    }
    for ($index = 0; $index -lt $eligible.Count; $index++) {
        Write-Host ('  {0}. {1,-28} {2}' -f ($index + 1), $eligible[$index].Name, $eligible[$index].Source)
    }
    $answer = Read-Host 'Enter one or more numbers separated by commas'
    $indexes = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
    if ($indexes.Count -eq 0 -or (@($indexes | Where-Object { $_ -lt 0 -or $_ -ge $eligible.Count })).Count -gt 0) {
        throw 'No valid startup-item selection was provided.'
    }
    $selected = @($indexes | Select-Object -Unique | ForEach-Object { $eligible[$_] })
}

if (-not $Force -and -not $WhatIfPreference) {
    $verb = if ($Action -eq 'Disable') { 'Disable' } else { 'Restore' }
    if (-not $PSCmdlet.ShouldContinue("$verb only the $($selected.Count) selected current-user startup item(s)?", "$verb startup items")) {
        Write-Host 'Startup-item action canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

$results = [Collections.Generic.List[object]]::new()
foreach ($item in $selected) {
    if ($Action -eq 'Disable') {
        if (-not $PSCmdlet.ShouldProcess($item.Name, "Disable current-user startup item from $($item.Source)")) {
            $results.Add([pscustomobject]@{ Status = 'what-if'; Name = $item.Name; Action = 'disable'; Detail = $item.Source })
            continue
        }
        try {
            $existingState = $stateEntries | Where-Object Id -eq $item.Id | Select-Object -First 1
            if ($item.Type -eq 'RegistryRun') {
                if (-not $existingState) {
                    $stateEntries.Add([pscustomobject]@{
                        Id = $item.Id
                        Type = $item.Type
                        Name = $item.Name
                        Source = $item.Source
                        Path = $item.Path
                        Kind = $item.Kind
                        Value = $item.Value
                        OriginalPath = $null
                        BackupPath = $null
                        DisabledAt = (Get-Date).ToString('o')
                    })
                }
                Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -ErrorAction Stop
            }
            else {
                New-Item -ItemType Directory -Path $disabledFilesRoot -Force | Out-Null
                $backupPath = Join-Path $disabledFilesRoot ("{0}-{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($item.Name), (Get-Date -Format 'yyyyMMddHHmmssfff'), [IO.Path]::GetExtension($item.Name))
                Move-Item -LiteralPath $item.Path -Destination $backupPath
                if ($existingState) {
                    $existingState.BackupPath = $backupPath
                    $existingState.DisabledAt = (Get-Date).ToString('o')
                }
                else {
                    $stateEntries.Add([pscustomobject]@{
                        Id = $item.Id
                        Type = $item.Type
                        Name = $item.Name
                        Source = $item.Source
                        Path = $null
                        Kind = $null
                        Value = $null
                        OriginalPath = $item.Path
                        BackupPath = $backupPath
                        DisabledAt = (Get-Date).ToString('o')
                    })
                }
            }
            Save-State
            $results.Add([pscustomobject]@{ Status = 'ok'; Name = $item.Name; Action = 'disable'; Detail = $item.Source })
        }
        catch {
            $results.Add([pscustomobject]@{ Status = 'failed'; Name = $item.Name; Action = 'disable'; Detail = $_.Exception.Message })
        }
        continue
    }

    $record = $stateEntries | Where-Object Id -eq $item.Id | Select-Object -First 1
    if (-not $record) {
        $results.Add([pscustomobject]@{ Status = 'unchanged'; Name = $item.Name; Action = 'enable'; Detail = 'No saved disabled state exists.' })
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($item.Name, "Restore current-user startup item to $($item.Source)")) {
        $results.Add([pscustomobject]@{ Status = 'what-if'; Name = $item.Name; Action = 'enable'; Detail = $item.Source })
        continue
    }
    try {
        if ($record.Type -eq 'RegistryRun') {
            if (-not (Test-Path -LiteralPath $record.Path)) { New-Item -Path $record.Path -Force | Out-Null }
            $key = Get-Item -LiteralPath $record.Path
            if ($key.GetValueNames() -notcontains [string]$record.Name) {
                $value = Convert-RegistryValue -Value $record.Value -Kind $record.Kind
                New-ItemProperty -LiteralPath $record.Path -Name $record.Name -Value $value -PropertyType $record.Kind -Force | Out-Null
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $record.OriginalPath)) {
                if (-not (Test-Path -LiteralPath $record.BackupPath -PathType Leaf)) { throw "Saved startup file is missing: $($record.BackupPath)" }
                New-Item -ItemType Directory -Path (Split-Path -Parent $record.OriginalPath) -Force | Out-Null
                Move-Item -LiteralPath $record.BackupPath -Destination $record.OriginalPath
            }
        }
        $remaining = @($stateEntries | Where-Object Id -ne $item.Id)
        $stateEntries.Clear()
        foreach ($entry in $remaining) { $stateEntries.Add($entry) }
        Save-State
        $results.Add([pscustomobject]@{ Status = 'ok'; Name = $item.Name; Action = 'enable'; Detail = $item.Source })
    }
    catch {
        $results.Add([pscustomobject]@{ Status = 'failed'; Name = $item.Name; Action = 'enable'; Detail = $_.Exception.Message })
    }
}

if ($Json) {
    ConvertTo-Json -InputObject @($results) -Depth 5
}
else {
    $results | Format-Table Status, Name, Action, Detail -Wrap -AutoSize
}
if ((@($results | Where-Object Status -eq 'failed')).Count -gt 0) { exit 1 }
