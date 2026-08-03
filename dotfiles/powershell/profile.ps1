# Managed PowerShell 7 profile. Keep this file fast and safe for every terminal.
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'
$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

$winGetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
if ((Test-Path -LiteralPath $winGetLinks) -and ($env:Path -notlike "*$winGetLinks*")) {
    $env:Path = "$winGetLinks;$env:Path"
}

if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and (Get-Module -ListAvailable -Name PSReadLine)) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView -ErrorAction Stop
    }
    catch {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
    }
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Chord Ctrl+r -Function ReverseSearchHistory
}

function global:ll { if (Get-Command eza -ErrorAction SilentlyContinue) { eza -lah --icons=auto --group-directories-first --git @args } elseif (Test-Path -LiteralPath (Join-Path $ucrtBin 'eza.exe')) { & (Join-Path $ucrtBin 'eza.exe') -lah --icons=auto --group-directories-first --git @args } else { Get-ChildItem -Force @args } }
function global:la { if (Get-Command eza -ErrorAction SilentlyContinue) { eza -a --icons=auto --group-directories-first @args } elseif (Test-Path -LiteralPath (Join-Path $ucrtBin 'eza.exe')) { & (Join-Path $ucrtBin 'eza.exe') -a --icons=auto --group-directories-first @args } else { Get-ChildItem -Force @args } }
function global:which { Get-Command @args | Select-Object -ExpandProperty Source }
function global:touch { param([Parameter(Mandatory)][string]$Path) if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).LastWriteTime = Get-Date } else { New-Item -ItemType File -Path $Path | Out-Null } }
function global:mkcd { param([Parameter(Mandatory)][string]$Path) New-Item -ItemType Directory -Path $Path -Force | Out-Null; Set-Location -LiteralPath $Path }
function global:open { param([string]$Path = '.') Start-Process explorer.exe -ArgumentList $Path }

$ucrtBin = 'C:\msys64\ucrt64\bin'
function global:fetch { & (Join-Path $ucrtBin 'fastfetch.exe') @args }
function global:y { & (Join-Path $ucrtBin 'yazi.exe') @args }

if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Set-Alias -Name vim -Value nvim -Scope Global
    Set-Alias -Name vi -Value nvim -Scope Global
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& zoxide init powershell | Out-String)
}
elseif (Test-Path -LiteralPath (Join-Path $ucrtBin 'zoxide.exe')) {
    Invoke-Expression (& (Join-Path $ucrtBin 'zoxide.exe') init powershell | Out-String)
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell | Out-String)
}
