#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $BackupPath) {
    $originalBackupPath = Join-Path $projectRoot 'backups\native-taskbar-original\registry.json'
    $BackupPath = if (Test-Path -LiteralPath $originalBackupPath) {
        $originalBackupPath
    }
    else {
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'backups') -Directory -Filter '*-native-taskbar' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName 'registry.json' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
    }
}

if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath)) {
    throw 'No native taskbar registry backup was found.'
}

$snapshot = @(Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json)
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $snapshot) {
    try {
        if (-not (Test-Path -LiteralPath $entry.Path)) {
            if ($entry.Existed -and $PSCmdlet.ShouldProcess($entry.Path, 'Recreate registry key')) {
                New-Item -Path $entry.Path -Force | Out-Null
            }
        }

        if (-not $entry.Existed) {
            $key = Get-Item -LiteralPath $entry.Path -ErrorAction SilentlyContinue
            if ($key -and $key.GetValueNames() -contains $entry.Name) {
                if ($PSCmdlet.ShouldProcess("$($entry.Path)\$($entry.Name)", 'Remove value that did not exist before taskbar configuration')) {
                    Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -Force
                }
            }
            continue
        }

        $value = if ($entry.Kind -eq 'Binary') {
            [Convert]::FromBase64String([string]$entry.ValueBase64)
        }
        else {
            $entry.Value
        }

        if ($PSCmdlet.ShouldProcess("$($entry.Path)\$($entry.Name)", 'Restore saved taskbar value')) {
            New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -Value $value -PropertyType $entry.Kind -Force | Out-Null
        }
    }
    catch {
        $warnings.Add("$($entry.Path)\$($entry.Name): $($_.Exception.Message)")
    }
}

if ($PSCmdlet.ShouldProcess('explorer.exe', 'Restart Explorer after restoring native taskbar settings')) {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 750
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe')
    }
}

if ($warnings.Count -gt 0) {
    Write-Warning "Taskbar rollback completed with $($warnings.Count) protected value(s): $($warnings -join '; ')"
}
if ($WhatIfPreference) {
    Write-Host "Native taskbar rollback preview complete for: $BackupPath" -ForegroundColor Yellow
}
else {
    Write-Host "Native taskbar settings restored from: $BackupPath" -ForegroundColor Green
}
