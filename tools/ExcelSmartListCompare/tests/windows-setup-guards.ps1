[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = [IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $output -Force)
$results = New-Object System.Collections.Generic.List[object]
$env:SLC_SETUP_NO_PAUSE = '1'
function Run-Case([string]$Id,[string]$Command,[int]$Expected) {
    $start = Get-Date
    $log = Join-Path $output ($Id + '.log')
    & cmd.exe /d /c ($Command + ' 2>&1') | Out-File -LiteralPath $log -Encoding UTF8
    $actual = $LASTEXITCODE
    $status = if($actual -eq $Expected){'PASS'}else{'FAIL'}
    $results.Add([pscustomobject]@{id=$Id;layer='Windows process / Setup';command=$Command;expectedExit=$Expected;actualExit=$actual;status=$status;started=$start.ToString('o');durationMs=((Get-Date)-$start).TotalMilliseconds;evidence=($Id+'.log')})
    Write-Output "$Id $status expected=$Expected actual=$actual"
}
Push-Location $root
$excel=$null
$mutex=$null
$held=$false
try {
    $existing=@(Get-Process EXCEL -ErrorAction SilentlyContinue)
    if($existing.Count -gt 0){throw 'Close existing Excel yourself before running these guards.'}
    if(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare/install.json')){throw 'These absence tests require no existing product installation.'}
    $excel=New-Object -ComObject Excel.Application
    $excel.AutomationSecurity=2
    $owned=@(Get-Process EXCEL -ErrorAction SilentlyContinue)
    if($owned.Count -ne 1){throw 'Cannot uniquely identify test-owned Excel.'}
    $ownedId=$owned[0].Id
    Run-Case 'GUARD-OPEN-INSTALL' 'Install.cmd -ConfirmProduct SLC-68A45C44-2026' 3
    Run-Case 'GUARD-OPEN-UNINSTALL' 'Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026' 3
    Run-Case 'GUARD-OPEN-BUILD' 'Build_Release.cmd' 3
    Run-Case 'GUARD-OPEN-TEST' 'Test_Excel.cmd' 3
    $results.Add([pscustomobject]@{id='GUARD-OWNED-PID-PRESERVED';status=if(Get-Process -Id $ownedId -ErrorAction SilentlyContinue){'PASS'}else{'FAIL'};pid=$ownedId;evidence='guards.json'})
    $excel.Quit()
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($excel)
    $excel=$null
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    $process=Get-Process -Id $ownedId -ErrorAction SilentlyContinue
    if($process -and -not $process.WaitForExit(5000)){throw 'Owned Excel did not exit; no process was killed.'}
    $mutex=New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-Setup')
    $held=$mutex.WaitOne(0)
    if(-not $held){throw 'Another setup owns the product mutex.'}
    Run-Case 'GUARD-LOCK-INSTALL' 'Install.cmd -ConfirmProduct SLC-68A45C44-2026' 4
    Run-Case 'GUARD-LOCK-UNINSTALL' 'Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026' 4
    $mutex.ReleaseMutex();$held=$false
    Run-Case 'GUARD-ABSENT-UNINSTALL' 'Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026' 0
    Run-Case 'GUARD-ABSENT-REUNINSTALL' 'Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026' 0
    Run-Case 'GUARD-MISSING-XLAM-TEST' 'Test_Excel.cmd' 1
} finally {
    if($excel){$excel.Quit();[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($excel)}
    if($held){$mutex.ReleaseMutex()}
    if($mutex){$mutex.Dispose()}
    $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'guards.json') -Encoding UTF8
    Pop-Location
}
if(@($results | Where-Object status -eq 'FAIL').Count -gt 0){exit 1}
