@echo off
setlocal
powershell.exe -NoLogo -NoProfile -STA -File "%~dp0Setup.ps1" -Action Install %*
set "slcExit=%ERRORLEVEL%"
echo.
if not "%SLC_SETUP_NO_PAUSE%"=="1" pause
exit /b %slcExit%
