@echo off
setlocal DisableDelayedExpansion
rem ADR-0005: prepare only our script, then run under a process-only policy.
set "SLC_SETUP_SCRIPT=%~dp0Setup.ps1"
set "slcPolicy="
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try { $ErrorActionPreference = 'Stop'; if (-not (Test-Path -LiteralPath $env:SLC_SETUP_SCRIPT -PathType Leaf)) { throw ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('7ISk7LmY7JeQIO2VhOyalO2VnCBTZXR1cC5wczEg7YyM7J287J20IOyXhuyKteuLiOuLpC4g67Cb7J2AIFpJUCDtjIzsnbzsnZgg7JWV7LaV7J2EIOuqqOuRkCDtkbwg65KkIOuLpOyLnCDsi6TtlontlbQg7KO87IS47JqULg=='))) }; if ((Get-ExecutionPolicy -Scope MachinePolicy) -ne 'Undefined' -or (Get-ExecutionPolicy -Scope UserPolicy) -ne 'Undefined' -or (Get-ExecutionPolicy) -eq 'AllSigned') { Write-Host ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6riw7KG0IFBvd2VyU2hlbGwg67O07JWIIOygleyxheyXkCDrlLDrnbwg7Iuk7ZaJ7ZWp64uI64ukLiDtjIzsnbzsnZgg7LCo64uoIOyDge2DnOuKlCDrsJTqvrjsp4Ag7JWK7JWY7Iq164uI64ukLg=='))); exit 2 }; Unblock-File -LiteralPath $env:SLC_SETUP_SCRIPT; exit 0 } catch { Write-Error $_ -ErrorAction Continue; exit 1 }"
set "slcExit=%ERRORLEVEL%"
if "%slcExit%"=="0" set "slcPolicy=-ExecutionPolicy RemoteSigned"
if "%slcExit%"=="2" set "slcExit=0"
if not "%slcExit%"=="0" goto slcDone
powershell.exe -NoLogo -NoProfile -STA %slcPolicy% -File "%~dp0Setup.ps1" -Action Install %*
set "slcExit=%ERRORLEVEL%"
:slcDone
echo.
if not "%SLC_SETUP_NO_PAUSE%"=="1" pause
exit /b %slcExit%
