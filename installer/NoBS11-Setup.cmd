@echo off
setlocal
title NoBS11 Setup

set "NOBS11_URL=https://github.com/ahmedalqamzi/nobs11/releases/download/v0.2.0/NoBS11-OnlineInstaller.ps1"
set "NOBS11_FILE=%TEMP%\NoBS11-OnlineInstaller-v0.2.0.ps1"
set "NOBS11_SHA256=CCDF1D3B5590BCAC82DA39B0D7DF465A1F2E35BAD89D392435C32578E4E4195A"

echo.
echo   NoBS11
echo   Windows performance. No BS.
echo.
echo Downloading the pinned v0.2.0 installer...

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Headers @{'User-Agent'='NoBS11-Setup'} -Uri '%NOBS11_URL%' -OutFile '%NOBS11_FILE%'; $actual=(Get-FileHash -LiteralPath '%NOBS11_FILE%' -Algorithm SHA256).Hash.ToUpperInvariant(); if ($actual -ne '%NOBS11_SHA256%') { throw ('Installer integrity check failed. Expected %NOBS11_SHA256% but received ' + $actual) }"
if errorlevel 1 goto :failed

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%NOBS11_FILE%"
set "NOBS11_EXIT=%ERRORLEVEL%"
del /q "%NOBS11_FILE%" >nul 2>&1
if not "%NOBS11_EXIT%"=="0" goto :failed_with_code

echo.
echo NoBS11 setup finished.
pause
exit /b 0

:failed_with_code
echo.
echo NoBS11 setup stopped with exit code %NOBS11_EXIT%.
echo Review the message above; no integrity failure was ignored.
pause
exit /b %NOBS11_EXIT%

:failed
set "NOBS11_EXIT=%ERRORLEVEL%"
del /q "%NOBS11_FILE%" >nul 2>&1
echo.
echo NoBS11 could not download or verify the installer.
echo Check your connection and download a fresh copy from the official release page.
pause
exit /b %NOBS11_EXIT%
