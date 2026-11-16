@echo off
setlocal
cd /d "%~dp0"
if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
  echo Windows PowerShell 5.1 is required.
  pause
  exit /b 3
)
echo ExcelPasswordSafe - local desktop Excel required
echo 1. Encrypt - preview only
echo 2. Decrypt - preview only
echo 3. Encrypt - review and approve execution
echo 4. Decrypt - review and approve execution
echo 5. Retry failed files from a results.csv
choice /c 12345 /n /m "Select [1-5]: "
set "sel=%errorlevel%"
if %sel% LSS 1 exit /b 3
if %sel% GTR 5 exit /b 3
set "EPS_MODE=Encrypt"
set "EPS_EXECUTE=0"
if "%sel%"==2 set "EPS_MODE=Decrypt"
if "%sel%"==3 set "EPS_EXECUTE=1"
if "%sel%"==4 set "EPS_MODE=Decrypt"
if "%sel%"==4 set "EPS_EXECUTE=1"
if "%sel%"==5 (
  echo Retry is reviewed and approved again; passwords are entered again.
  set "EPS_EXECUTE=1"
)
set "EPS_RETRY="
if "%sel%"==5 set /p "EPS_RETRY=Full path to results.csv: "
if "%sel%"==5 (
  if not defined EPS_RETRY (
    echo A retry requires the full path to results.csv.
    pause
    exit /b 3
  )
  choice /c ED /n /m "Original mode: [E]ncrypt / [D]ecrypt: "
  if errorlevel 3 exit /b 3
  if not errorlevel 1 exit /b 3
  if errorlevel 2 set "EPS_MODE=Decrypt"
)
set "EPS_ROOT="
set /p "EPS_ROOT=Target folder: "
set "EPS_BACKUP="
set /p "EPS_BACKUP=Backup folder outside target [Enter=automatic]: "
rem Paths travel as environment data, never as shell-interpolated PowerShell source.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -Command "try { & (Join-Path (Get-Location) 'ExcelPassword.ps1') -Mode $env:EPS_MODE -Root $env:EPS_ROOT -BackupRoot $env:EPS_BACKUP -RetryLog $env:EPS_RETRY -Execute:($env:EPS_EXECUTE -eq '1') } catch { Write-Error $_; exit 3 }"
set "rc=%errorlevel%"
echo Exit code: %rc%
pause
exit /b %rc%
