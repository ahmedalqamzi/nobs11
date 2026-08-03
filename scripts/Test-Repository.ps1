#requires -Version 7.2
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$results = [System.Collections.Generic.List[object]]::new()
$ignoredRuntimePattern = '\\(\.git|backups|baseline|logs)\\|\\manifests\\local\\|\\website\\dist\\'

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Detail
    )
    $results.Add([pscustomobject]@{
        Status = if ($Passed) { 'pass' } else { 'fail' }
        Check = $Check
        Detail = $Detail
    })
}

$parseFailures = [System.Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.ps1' | Where-Object FullName -notmatch $ignoredRuntimePattern) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($error in $errors) {
        $relative = [IO.Path]::GetRelativePath($projectRoot, $file.FullName)
        $parseFailures.Add("$relative`:$($error.Extent.StartLineNumber) $($error.Message)")
    }
}
Add-Result 'PowerShell syntax' ($parseFailures.Count -eq 0) $(if ($parseFailures.Count) { $parseFailures -join '; ' } else { 'All scripts parse successfully' })

$jsonFailures = [System.Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.json' | Where-Object { $_.FullName -notmatch $ignoredRuntimePattern }) {
    try {
        Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
    }
    catch {
        $relative = [IO.Path]::GetRelativePath($projectRoot, $file.FullName)
        $jsonFailures.Add("$relative $($_.Exception.Message)")
    }
}
Add-Result 'JSON syntax' ($jsonFailures.Count -eq 0) $(if ($jsonFailures.Count) { $jsonFailures -join '; ' } else { 'All public JSON files parse successfully' })

$policyPath = Join-Path $projectRoot 'config\startup-policy.json'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$usesExplicitBlocklists = [int]$policy.schemaVersion -ge 2 -and
    $policy.PSObject.Properties.Name -contains 'blockedCurrentUserRunValues' -and
    $policy.PSObject.Properties.Name -contains 'blockedStartupItems' -and
    $policy.PSObject.Properties.Name -notcontains 'allowedCurrentUserRunValues' -and
    $policy.PSObject.Properties.Name -notcontains 'allowedStartupItems'
$safeStartupModel = $usesExplicitBlocklists
Add-Result 'Safe startup policy model' $safeStartupModel $(if ($safeStartupModel) { 'Explicit blocklists preserve unlisted startup entries' } else { 'Policy must use explicit blocklists' })

$legacyPaths = @(
    'dotfiles\zebar',
    'dotfiles\glazewm\Start-ZebarDetached.ps1',
    'dotfiles\glazewm\Watch-ZebarDock.ps1',
    'scripts\Install-ZebarDockService.ps1',
    'scripts\Install-Notch.ps1',
    'scripts\Remove-Notch.ps1',
    'dotfiles\glazewm',
    'dotfiles\autohotkey'
)
$remainingLegacy = @($legacyPaths | Where-Object {
    $path = Join-Path $projectRoot $_
    (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Test-Path -LiteralPath $path -PathType Container) -and [bool](Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1))
})
Add-Result 'Retired custom dock removed' ($remainingLegacy.Count -eq 0) $(if ($remainingLegacy.Count) { $remainingLegacy -join ', ' } else { 'No retired dock implementation is shipped' })

$textExtensions = @('.ps1', '.md', '.json', '.yaml', '.yml', '.toml', '.ini', '.conf', '.js', '.css', '.html', '.txt')
$identityHits = [System.Collections.Generic.List[string]]::new()
$runtimeIdentityValues = @([Environment]::UserName, [Environment]::MachineName) |
    Where-Object { $_ -and $_.Length -ge 4 -and $_ -notin @('user', 'admin', 'administrator', 'runneradmin') } |
    Select-Object -Unique
$emailPattern = '(?i)(?<![\w.+-])[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
foreach ($file in Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch $ignoredRuntimePattern -and
    ($textExtensions -contains $_.Extension.ToLowerInvariant() -or $_.Name -in @('Makefile', '.gitignore', '.gitattributes', '.editorconfig'))
}) {
    $content = [IO.File]::ReadAllText($file.FullName)
    $containsRuntimeIdentity = [bool]($runtimeIdentityValues | Where-Object { $content -match [regex]::Escape($_) } | Select-Object -First 1)
    if ($content -match '(?i)C:\\Users\\(?!%USERNAME%|<username>)' -or $content -match $emailPattern -or $containsRuntimeIdentity) {
        $identityHits.Add([IO.Path]::GetRelativePath($projectRoot, $file.FullName))
    }
}
Add-Result 'No personal identity in public files' ($identityHits.Count -eq 0) $(if ($identityHits.Count) { ($identityHits | Sort-Object -Unique) -join ', ' } else { 'No email, hard-coded user profile, or local runtime identity found' })

$secretPatterns = @(
    '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    '(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}',
    'sk-(?:proj-)?[A-Za-z0-9_-]{20,}',
    '(?:AKIA|ASIA)[A-Z0-9]{16}',
    'AIza[0-9A-Za-z_-]{30,}',
    'xox[baprs]-[A-Za-z0-9-]{10,}',
    '(?i)(?:password|passwd|client_secret|access_token|api[_-]?key)\s*[:=]\s*["'']?[^\s"'']{8,}'
)
$secretHits = [System.Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch $ignoredRuntimePattern -and
    ($textExtensions -contains $_.Extension.ToLowerInvariant() -or $_.Name -in @('Makefile', '.gitignore', '.gitattributes', '.editorconfig'))
}) {
    $content = [IO.File]::ReadAllText($file.FullName)
    if ($secretPatterns | Where-Object { $content -match $_ } | Select-Object -First 1) {
        $secretHits.Add([IO.Path]::GetRelativePath($projectRoot, $file.FullName))
    }
}
Add-Result 'No embedded credentials in public files' ($secretHits.Count -eq 0) $(if ($secretHits.Count) { ($secretHits | Sort-Object -Unique) -join ', ' } else { 'No private keys or common access-token formats found' })

$unpinnedActions = [System.Collections.Generic.List[string]]::new()
foreach ($workflow in Get-ChildItem -LiteralPath (Join-Path $projectRoot '.github\workflows') -File -ErrorAction SilentlyContinue | Where-Object Extension -in @('.yml', '.yaml')) {
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadLines($workflow.FullName)) {
        $lineNumber++
        if ($line -match '^\s*-?\s*uses:\s*(?<action>[^\s@]+)@(?<ref>[^\s#]+)' -and $Matches.action -notlike './*' -and $Matches.ref -notmatch '^[0-9a-fA-F]{40}$') {
            $unpinnedActions.Add("$($workflow.Name):$lineNumber $($Matches.action)")
        }
    }
}
Add-Result 'GitHub Actions dependencies are pinned' ($unpinnedActions.Count -eq 0) $(if ($unpinnedActions.Count) { $unpinnedActions -join ', ' } else { 'External actions use immutable commit SHAs' })

$requiredFiles = @(
    'README.md',
    'LICENSE',
    'Install.ps1',
    'bootstrap.ps1',
    'CHANGELOG.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    'THIRD-PARTY-NOTICES.md',
    '.github\dependabot.yml',
    '.github\ISSUE_TEMPLATE\bug_report.yml',
    '.github\ISSUE_TEMPLATE\feature_request.yml',
    '.github\ISSUE_TEMPLATE\config.yml',
    '.github\pull_request_template.md',
    '.github\workflows\validate.yml',
    '.github\workflows\pages.yml',
    'docs\RELEASE-CHECKLIST.md',
    'docs\TESTED-CONFIGURATION.md',
    'docs\UPSTREAM-PROVENANCE.md',
    'docs\MEASUREMENTS.md',
    'website\index.html',
    'website\styles.css',
    'website\app.js',
    'website\og.png',
    'config\optional-apps.json',
    'scripts\Configure-NativeWindowing.ps1',
    'scripts\Install-AppControl.ps1',
    'scripts\Invoke-Pwsh.ps1',
    'scripts\Manage-InstalledApps.ps1',
    'scripts\Manage-OptionalApps.ps1',
    'scripts\Manage-UserStartup.ps1',
    'scripts\Remove-AppControl.ps1',
    'scripts\Test-Prerequisites.ps1',
    'scripts\Test-Repository.ps1',
    'scripts\Workstation-App-Control.ps1'
)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $projectRoot $_) -PathType Leaf) })
Add-Result 'Required public documentation and tooling' ($missingFiles.Count -eq 0) $(if ($missingFiles.Count) { $missingFiles -join ', ' } else { 'Required release files are present' })

$appControlSource = [IO.File]::ReadAllText((Join-Path $projectRoot 'scripts\Workstation-App-Control.ps1'))
$appControlInstaller = [IO.File]::ReadAllText((Join-Path $projectRoot 'scripts\Install-AppControl.ps1'))
$shortcutAssignment = [regex]::Match($appControlInstaller, '(?s)\$shortcutPaths\s*=\s*@\((?<body>.*?)\)')
$shortcutBody = $shortcutAssignment.Groups['body'].Value
$appControlStaysInApp = $appControlSource -match [regex]::Escape("Manage-InstalledApps.ps1") -and
    $appControlSource -notmatch '(?i)ms-settings:|SystemSettings(?:\.exe)?'
$appControlIsStartOnly = $shortcutAssignment.Success -and
    $shortcutBody -match 'startMenuFolder' -and
    $shortcutBody -notmatch '(?i)Desktop'
$safeAppControlShell = $appControlStaysInApp -and $appControlIsStartOnly
Add-Result 'App Control stays in-app and Start-only' $safeAppControlShell $(if ($safeAppControlShell) { 'Installed-app management stays in one window with only a Start-menu launcher' } else { 'App Control must not route to Settings or create a Desktop launcher' })

$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'manifests\winget-packages.json') -Raw | ConvertFrom-Json
$packageIds = @($manifest.Sources.Packages.PackageIdentifier)
$requiredPackages = @('Microsoft.PowerShell', 'Microsoft.WindowsTerminal', 'MSYS2.MSYS2')
$missingPackages = @($requiredPackages | Where-Object { $_ -notin $packageIds })
Add-Result 'Required WinGet packages declared' ($missingPackages.Count -eq 0) $(if ($missingPackages.Count) { $missingPackages -join ', ' } else { 'Core Windows dependencies are declared' })

$git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($git) {
    $trackedRuntime = @(& $git.Source -C $projectRoot ls-files -- 'backups/*' 'baseline/*' 'logs/*' | Where-Object { $_ -notmatch '/\.gitkeep$' })
    Add-Result 'Runtime data excluded from Git' ($trackedRuntime.Count -eq 0) $(if ($trackedRuntime.Count) { $trackedRuntime -join ', ' } else { 'Only placeholder files are tracked' })
}
else {
    Add-Result 'Runtime data excluded from Git' $false 'git.exe is required for this check'
}

$results | Format-Table Status, Check, Detail -Wrap -AutoSize
$failures = @($results | Where-Object Status -eq 'fail')
Write-Host "Repository checks: $($results.Count - $failures.Count) passed, $($failures.Count) failed."
if ($failures.Count -gt 0) { exit 1 }
