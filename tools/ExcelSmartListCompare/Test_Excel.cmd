@echo off
setlocal DisableDelayedExpansion
rem ADR-0005: prepare only our script, then run under a process-only policy.
set "SLC_SETUP_SCRIPT=%~dp0Setup.ps1"
set "slcPolicy="
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try { $ErrorActionPreference = 'Stop'; if (-not (Test-Path -LiteralPath $env:SLC_SETUP_SCRIPT -PathType Leaf)) { throw 'Setup.ps1 is missing. Extract the complete release ZIP first.' }; if ((Get-ExecutionPolicy -Scope MachinePolicy) -ne 'Undefined' -or (Get-ExecutionPolicy -Scope UserPolicy) -ne 'Undefined' -or (Get-ExecutionPolicy) -eq 'AllSigned') { Write-Host 'Using the configured PowerShell policy; file trust was not changed.'; exit 2 }; Unblock-File -LiteralPath $env:SLC_SETUP_SCRIPT; exit 0 } catch { Write-Error $_ -ErrorAction Continue; exit 1 }"
set "slcExit=%ERRORLEVEL%"
if "%slcExit%"=="0" set "slcPolicy=-ExecutionPolicy RemoteSigned"
if "%slcExit%"=="2" set "slcExit=0"
if not "%slcExit%"=="0" goto slcDone
powershell.exe -NoLogo -NoProfile -STA %slcPolicy% -File "%~dp0Setup.ps1" -Action Test %*
set "slcExit=%ERRORLEVEL%"
:slcDone
echo.
if not "%SLC_SETUP_NO_PAUSE%"=="1" pause
exit /b %slcExit%
