@echo off
setlocal DisableDelayedExpansion
rem Use built-in Windows modules, not a parent PS7/custom module search path.
rem SETLOCAL restores the caller's environment; no user or machine setting changes.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
rem Resolve the Windows host explicitly; never search the package folder or PATH.
set "slcPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "slcPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%slcPowerShell%" (
  echo Windows PowerShell is unavailable.
  exit /b 1
)
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_HOST=%slcPowerShell%
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_PREPARE_START
rem ADR-0005: prepare only our script, then run under a process-only policy.
set "SLC_SETUP_SCRIPT=%~dp0Setup.ps1"
set "slcPolicy="
"%slcPowerShell%" -NoLogo -NoProfile -NonInteractive -Command "try { if ($env:SLC_SETUP_DIAGNOSTICS -eq '1') { Write-Host 'SLC_LAUNCHER_PREPARE_ENTERED' }; $ErrorActionPreference = 'Stop'; if (-not (Test-Path -LiteralPath $env:SLC_SETUP_SCRIPT -PathType Leaf)) { throw ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('7ISk7LmY7JeQIO2VhOyalO2VnCBTZXR1cC5wczEg7YyM7J287J20IOyXhuyKteuLiOuLpC4g67Cb7J2AIFpJUCDtjIzsnbzsnZgg7JWV7LaV7J2EIOuqqOuRkCDtkbwg65KkIOuLpOyLnCDsi6TtlontlbQg7KO87IS47JqULg=='))) }; if ((Get-ExecutionPolicy -Scope MachinePolicy) -ne 'Undefined' -or (Get-ExecutionPolicy -Scope UserPolicy) -ne 'Undefined' -or (Get-ExecutionPolicy) -eq 'AllSigned') { Write-Host ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6riw7KG0IFBvd2VyU2hlbGwg67O07JWIIOygleyxheyXkCDrlLDrnbwg7Iuk7ZaJ7ZWp64uI64ukLiDtjIzsnbzsnZgg7LCo64uoIOyDge2DnOuKlCDrsJTqvrjsp4Ag7JWK7JWY7Iq164uI64ukLg=='))); exit 2 }; Unblock-File -LiteralPath $env:SLC_SETUP_SCRIPT; exit 0 } catch { Write-Error $_ -ErrorAction Continue; exit 1 }"
set "slcExit=%ERRORLEVEL%"
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_PREPARE_EXIT=%slcExit%
if "%slcExit%"=="0" set "slcPolicy=-ExecutionPolicy RemoteSigned"
if "%slcExit%"=="2" set "slcExit=0"
if not "%slcExit%"=="0" goto slcDone
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_ENGINE_START
"%slcPowerShell%" -NoLogo -NoProfile -STA %slcPolicy% -File "%~dp0Setup.ps1" -Action Install %*
set "slcExit=%ERRORLEVEL%"
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_ENGINE_EXIT=%slcExit%
:slcDone
echo.
if not "%SLC_SETUP_NO_PAUSE%"=="1" pause
exit /b %slcExit%
