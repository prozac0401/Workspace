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
rem An installed launcher must transfer control to a private copy before its
rem engine deletes the installed files. A batch file cannot resume after deletion.
if not exist "%~dp0install.json" goto slcPrepared
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_STAGE_START
set "SLC_UNINSTALL_SOURCE=%~dp0"
set "SLC_UNINSTALL_STAGE=%TEMP%\SLC-uninstall-%RANDOM%-%RANDOM%"
"%slcPowerShell%" -NoLogo -NoProfile -NonInteractive -Command "try { $ErrorActionPreference='Stop'; $stage=$env:SLC_UNINSTALL_STAGE; if (Test-Path -LiteralPath $stage) { throw ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('7KCc6rGwIOyekeyXheyXkCDsgqzsmqntlaAg7J6E7IucIO2PtOuNlOqwgCDsnbTrr7gg7J6I7Iq164uI64ukLiDsoJzqsbDrpbwg64uk7IucIOyLpO2Wie2VtCDso7zshLjsmpQu'))) }; [void](New-Item -ItemType Directory -Path $stage); foreach ($name in @('Uninstall.cmd','Setup.ps1')) { Copy-Item -LiteralPath (Join-Path $env:SLC_UNINSTALL_SOURCE $name) -Destination (Join-Path $stage $name) }; exit 0 } catch { Write-Error $_ -ErrorAction Continue; exit 1 }"
set "slcExit=%ERRORLEVEL%"
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_STAGE_EXIT=%slcExit%
if not "%slcExit%"=="0" exit /b %slcExit%
rem Deliberately transfer to the other batch without CALL; never return here.
"%SLC_UNINSTALL_STAGE%\Uninstall.cmd" %*
exit /b 1
:slcPrepared
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
rem The caller's working directory may also be the directory being removed.
pushd "%SystemRoot%"
if errorlevel 1 exit /b 1
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_ENGINE_START
"%slcPowerShell%" -NoLogo -NoProfile -STA %slcPolicy% -File "%~dp0Setup.ps1" -Action Uninstall %*
set "slcExit=%ERRORLEVEL%"
if "%SLC_SETUP_DIAGNOSTICS%"=="1" echo SLC_LAUNCHER_ENGINE_EXIT=%slcExit%
popd 2>nul
:slcDone
echo.
if not "%SLC_SETUP_NO_PAUSE%"=="1" pause
exit /b %slcExit%
