@echo off
setlocal
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -Command "try { $parent = Join-Path $env:LOCALAPPDATA 'ExcelPasswordSafeTests'; [void][IO.Directory]::CreateDirectory($parent); $folder = Join-Path $parent ('run-' + [guid]::NewGuid().ToString('N').Substring(0,8)); Write-Host ('Evidence: ' + $folder); & (Join-Path (Get-Location) 'Test-ExcelSynthetic.ps1') -EvidenceDirectory $folder; exit $LASTEXITCODE } catch { Write-Error $_; exit 1 }"
set "rc=%errorlevel%"
echo Test exit code: %rc%
pause
exit /b %rc%
