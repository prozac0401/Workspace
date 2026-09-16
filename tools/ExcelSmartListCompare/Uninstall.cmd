@echo off
setlocal DisableDelayedExpansion
rem An installed launcher must transfer control to a private copy before its
rem engine deletes the installed files. A batch file cannot resume after deletion.
if not exist "%~dp0install.json" goto slcPrepared
set "SLC_UNINSTALL_SOURCE=%~dp0"
set "SLC_UNINSTALL_STAGE=%TEMP%\SLC-uninstall-%RANDOM%-%RANDOM%"
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try { $ErrorActionPreference='Stop'; $stage=$env:SLC_UNINSTALL_STAGE; if (Test-Path -LiteralPath $stage) { throw 'Removal staging directory already exists.' }; [void](New-Item -ItemType Directory -Path $stage); foreach ($name in @('Uninstall.cmd','Setup.ps1')) { Copy-Item -LiteralPath (Join-Path $env:SLC_UNINSTALL_SOURCE $name) -Destination (Join-Path $stage $name) }; exit 0 } catch { Write-Error $_ -ErrorAction Continue; exit 1 }"
if errorlevel 1 exit /b 1
rem Deliberately transfer to the other batch without CALL; never return here.
"%SLC_UNINSTALL_STAGE%\Uninstall.cmd" %*
exit /b 1
:slcPrepared
rem ADR-0005: prepare only our script, then run under a process-only policy.
set "SLC_SETUP_SCRIPT=%~dp0Setup.ps1"
set "slcPolicy="
powershell.exe -NoLogo -NoProfile -NonInteractive -Command "try { $ErrorActionPreference = 'Stop'; if (-not (Test-Path -LiteralPath $env:SLC_SETUP_SCRIPT -PathType Leaf)) { throw 'Setup.ps1 is missing. Extract the complete release ZIP first.' }; if ((Get-ExecutionPolicy -Scope MachinePolicy) -ne 'Undefined' -or (Get-ExecutionPolicy -Scope UserPolicy) -ne 'Undefined' -or (Get-ExecutionPolicy) -eq 'AllSigned') { Write-Host 'Using the configured PowerShell policy; file trust was not changed.'; exit 2 }; Unblock-File -LiteralPath $env:SLC_SETUP_SCRIPT; exit 0 } catch { Write-Error $_ -ErrorAction Continue; exit 1 }"
set "slcExit=%ERRORLEVEL%"
if "%slcExit%"=="0" set "slcPolicy=-ExecutionPolicy RemoteSigned"
if "%slcExit%"=="2" set "slcExit=0"
if not "%slcExit%"=="0" goto slcDone
rem The caller's working directory may also be the directory being removed.
pushd "%SystemRoot%"
if errorlevel 1 exit /b 1
powershell.exe -NoLogo -NoProfile -STA %slcPolicy% -File "%~dp0Setup.ps1" -Action Uninstall %*
set "slcExit=%ERRORLEVEL%"
popd 2>nul
:slcDone
echo.
if not "%SLC_SETUP_NO_PAUSE%"=="1" pause
exit /b %slcExit%
