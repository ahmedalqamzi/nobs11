[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [Parameter(ValueFromRemainingArguments)][string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedScript = if ([IO.Path]::IsPathRooted($ScriptPath)) {
    $ScriptPath
}
else {
    Join-Path $projectRoot $ScriptPath
}
if (-not (Test-Path -LiteralPath $resolvedScript -PathType Leaf)) {
    throw "PowerShell script not found: $resolvedScript"
}

$candidates = [System.Collections.Generic.List[string]]::new()
foreach ($registryPath in @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe'
)) {
    $key = Get-Item -LiteralPath $registryPath -ErrorAction SilentlyContinue
    if ($key) {
        $value = [string]$key.GetValue('')
        if ($value) { $candidates.Add($value) }
    }
}

$candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'))
if ($env:ProgramFiles) {
    $candidates.Add((Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'))
}
$command = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($command) { $candidates.Add($command.Source) }

$pwshPath = $candidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -Unique -First 1
if (-not $pwshPath) {
    throw 'PowerShell 7 was not found. Install it with: winget install --id Microsoft.PowerShell --exact'
}

& $pwshPath -NoLogo -NoProfile -File $resolvedScript @RemainingArguments
if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
