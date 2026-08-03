#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('Audit', 'Uninstall')]
    [string]$Action = 'Audit',
    [string[]]$Id,
    [switch]$Json,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$projectRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $projectRoot 'config\optional-apps.json'
$catalog = if (Test-Path -LiteralPath $catalogPath -PathType Leaf) { Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{ apps = @() } }

function New-AppId {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Key
    )
    $bytes = [Text.Encoding]::UTF8.GetBytes("$Kind`0$Key")
    return ([Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
}

function Get-OptionalProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function ConvertTo-CleanText {
    param($Value)
    return ([string]$Value).Trim([char]0).Trim()
}

function Get-ManagedName {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$PackageName
    )
    foreach ($app in @($catalog.apps)) {
        if ($DisplayName -in @($app.installedDisplayNames)) { return [string]$app.name }
        if ($PackageName -and $app.uninstall.kind -eq 'appx' -and $PackageName -eq [string]$app.uninstall.value) { return [string]$app.name }
    }
    return $null
}

function Get-InstalledApps {
    $apps = [Collections.Generic.List[object]]::new()
    $registryRoots = @(
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Current user' },
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'All users' },
        @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'All users (32-bit)' }
    )
    foreach ($root in $registryRoots) {
        foreach ($key in @(Get-ChildItem -LiteralPath $root.Path -ErrorAction SilentlyContinue)) {
            $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (-not $properties) { continue }
            $name = ConvertTo-CleanText (Get-OptionalProperty $properties 'DisplayName' '')
            if (-not $name) { continue }
            if ([int](Get-OptionalProperty $properties 'SystemComponent' 0) -eq 1) { continue }
            if ([int](Get-OptionalProperty $properties 'NoRemove' 0) -eq 1) { continue }
            if ([string](Get-OptionalProperty $properties 'ParentKeyName' '')) { continue }
            if ([string](Get-OptionalProperty $properties 'ReleaseType' '') -match 'Update|Hotfix|Security') { continue }
            $quietUninstall = [string](Get-OptionalProperty $properties 'QuietUninstallString' '')
            $uninstallCommand = if ($quietUninstall) { $quietUninstall } else { [string](Get-OptionalProperty $properties 'UninstallString' '') }
            $apps.Add([pscustomobject]@{
                Id = New-AppId -Kind 'Registry' -Key $key.PSPath
                Name = $name
                Publisher = ConvertTo-CleanText (Get-OptionalProperty $properties 'Publisher' '')
                Version = ConvertTo-CleanText (Get-OptionalProperty $properties 'DisplayVersion' '')
                Scope = [string]$root.Scope
                Source = 'Desktop app'
                Kind = 'Registry'
                Key = $key.PSPath
                ProductCode = [string]$key.PSChildName
                UninstallCommand = $uninstallCommand
                CanUninstall = [bool]$uninstallCommand
                ManagedName = Get-ManagedName -DisplayName $name
            })
        }
    }

    $startAppNames = @{}
    foreach ($startApp in @(Get-StartApps -ErrorAction SilentlyContinue)) {
        if ([string]$startApp.AppID -notmatch '!') { continue }
        $familyName = ([string]$startApp.AppID -split '!', 2)[0]
        if (-not $startAppNames.ContainsKey($familyName)) { $startAppNames[$familyName] = [string]$startApp.Name }
    }

    foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable })) {
        $displayName = [string]$package.Name
        $publisher = [string]$package.PublisherId
        $managedName = Get-ManagedName -DisplayName $displayName -PackageName $package.Name
        $startDisplayName = if ($startAppNames.ContainsKey([string]$package.PackageFamilyName)) { [string]$startAppNames[[string]$package.PackageFamilyName] } else { '' }
        if (-not $startDisplayName -and -not $managedName) { continue }
        if ($startDisplayName) { $displayName = $startDisplayName }
        try {
            $manifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
            $manifestName = [string]$manifest.Package.Properties.DisplayName
            $manifestPublisher = [string]$manifest.Package.Properties.PublisherDisplayName
            if (-not $startDisplayName -and $manifestName -and $manifestName -notlike 'ms-resource:*') { $displayName = $manifestName }
            if ($manifestPublisher -and $manifestPublisher -notlike 'ms-resource:*') { $publisher = $manifestPublisher }
        }
        catch {}
        $apps.Add([pscustomobject]@{
            Id = New-AppId -Kind 'Appx' -Key $package.PackageFullName
            Name = $displayName
            Publisher = $publisher
            Version = $package.Version.ToString()
            Scope = 'Current user'
            Source = 'Store app'
            Kind = 'Appx'
            Key = $package.PackageFullName
            ProductCode = $null
            UninstallCommand = $null
            CanUninstall = -not [bool]$package.NonRemovable
            ManagedName = $managedName
        })
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    return @(
        $apps |
            Sort-Object Name, Source, Scope |
            Where-Object { $seen.Add("$($_.Kind)|$($_.Name)|$($_.Version)|$($_.Scope)") }
    )
}

function Split-UninstallCommand {
    param([Parameter(Mandatory)][string]$CommandLine)

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    $executable = $null
    $arguments = ''
    if ($expanded.StartsWith('"')) {
        $closingQuote = $expanded.IndexOf('"', 1)
        if ($closingQuote -lt 2) { throw "Invalid quoted uninstall command: $expanded" }
        $executable = $expanded.Substring(1, $closingQuote - 1)
        $arguments = $expanded.Substring($closingQuote + 1).Trim()
    }
    elseif ($expanded -match '^(?<exe>.+?\.(?:exe|com|cmd|bat))(?:\s+(?<args>.*))?$') {
        $executable = $Matches.exe
        $arguments = [string]$Matches.args
    }
    elseif ($expanded -match '^(?<command>[^\s]+)(?:\s+(?<args>.*))?$') {
        $commandName = [string]$Matches.command
        $arguments = [string]$Matches.args
        $resolved = Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) {
            $executable = [string]$resolved.Source
        }
        else {
            $candidateNames = if ([IO.Path]::HasExtension($commandName)) { @($commandName) } else { @("$commandName.exe", "$commandName.com", "$commandName.cmd", "$commandName.bat") }
            $candidateDirectories = @(
                (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'),
                (Join-Path $env:SystemRoot 'System32'),
                $env:SystemRoot
            )
            $executable = $candidateDirectories |
                ForEach-Object { $directory = $_; $candidateNames | ForEach-Object { Join-Path $directory $_ } } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Select-Object -First 1
        }
        if (-not $executable) { throw "Uninstaller command was not found: $commandName" }
    }
    else {
        throw "Unsupported uninstall command: $expanded"
    }

    if ([IO.Path]::GetFileName($executable) -ieq 'msiexec.exe') {
        $arguments = $arguments -replace '(?i)(^|\s)/I(?=\s*\{)', '$1/X'
    }
    return [pscustomobject]@{ FilePath = $executable; Arguments = $arguments }
}

$requestedWhatIf = [bool]$WhatIfPreference
$WhatIfPreference = $false
try { $installedApps = @(Get-InstalledApps) }
finally { $WhatIfPreference = $requestedWhatIf }
if ($Action -eq 'Audit') {
    $publicState = @($installedApps | Select-Object Id, Name, Publisher, Version, Scope, Source, Kind, CanUninstall, ManagedName)
    if ($Json) { ConvertTo-Json -InputObject $publicState -Depth 5 }
    else {
        $publicState | Format-Table Name, Publisher, Version, Scope, Source -AutoSize
        Write-Host "Audited $($publicState.Count) installed app(s); no changes were made." -ForegroundColor Cyan
    }
    return
}

if (-not $Id) { throw 'Select an installed app ID to uninstall.' }
$Id = @($Id | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | Select-Object -Unique)
$installedIds = @($installedApps | ForEach-Object { $_.Id })
$unknown = @($Id | Where-Object { $_ -notin $installedIds })
if ($unknown.Count -gt 0) { throw "Unknown installed app ID(s): $($unknown -join ', ')" }
$selected = @($installedApps | Where-Object Id -in $Id)
$notRemovable = @($selected | Where-Object { -not $_.CanUninstall })
if ($notRemovable.Count -gt 0) { throw "Windows marks these apps as non-removable: $($notRemovable.Name -join ', ')" }

if (-not $Force -and -not $WhatIfPreference) {
    if (-not $PSCmdlet.ShouldContinue("Uninstall only: $($selected.Name -join ', ')?", 'Confirm installed app removal')) {
        Write-Host 'Uninstall canceled; no changes were made.' -ForegroundColor Yellow
        return
    }
}

$results = [Collections.Generic.List[object]]::new()
foreach ($app in $selected) {
    if (-not $PSCmdlet.ShouldProcess($app.Name, "Run registered $($app.Source) uninstaller")) {
        $results.Add([pscustomobject]@{ Status = 'what-if'; Name = $app.Name; Detail = $app.Source })
        continue
    }
    try {
        if ($app.Kind -eq 'Appx') {
            Remove-AppxPackage -Package $app.Key -ErrorAction Stop
        }
        else {
            $command = if ($app.ProductCode -match '^\{[0-9A-Fa-f-]{36}\}$') {
                [pscustomobject]@{ FilePath = 'msiexec.exe'; Arguments = "/X$($app.ProductCode) /passive /norestart" }
            }
            else {
                Split-UninstallCommand -CommandLine $app.UninstallCommand
            }
            $startArguments = @{
                FilePath = $command.FilePath
                ArgumentList = $command.Arguments
                Wait = $true
                PassThru = $true
            }
            if ($app.Scope -like 'All users*') { $startArguments.Verb = 'RunAs' }
            $process = Start-Process @startArguments
            if ($null -ne $process.ExitCode -and $process.ExitCode -notin @(0, 3010)) { throw "Uninstaller exited with code $($process.ExitCode)." }
        }
        $results.Add([pscustomobject]@{ Status = 'ok'; Name = $app.Name; Detail = 'Uninstaller completed or was launched successfully.' })
    }
    catch {
        $results.Add([pscustomobject]@{ Status = 'failed'; Name = $app.Name; Detail = $_.Exception.Message })
    }
}

if ($Json) { ConvertTo-Json -InputObject @($results) -Depth 5 }
else { $results | Format-Table Status, Name, Detail -Wrap -AutoSize }
if ((@($results | Where-Object Status -eq 'failed')).Count -gt 0) { exit 1 }
