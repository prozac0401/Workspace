#requires -Version 5.1
#requires -PSEdition Desktop
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Close Excel normally first.' }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$sourceRoot=Join-Path $EvidenceDirectory 'files'; [void][IO.Directory]::CreateDirectory((Join-Path $sourceRoot 'nested'))
$fixture=Join-Path $toolRoot 'upstream/1.1.0/ExcelPasswordSafe/tests/fixtures/picture_ooxml.xlsx'
$paths=@((Join-Path $sourceRoot '첫째.xlsx'),(Join-Path $sourceRoot 'nested/둘째.xlsx'))
foreach($path in $paths) { [IO.File]::Copy($fixture,$path) }
$checks=New-Object 'System.Collections.Generic.List[object]'
function Assert($Condition,[string]$Name) { $checks.Add([pscustomobject]@{name=$Name;passed=[bool]$Condition}); if(-not $Condition) { throw ('ASSERT '+$Name) } }
function Cipher([string]$Text) { if(-not $Text){return ''}; $s=ConvertTo-SecureString $Text -AsPlainText -Force; try { ConvertFrom-SecureString $s } finally { $s.Dispose() } }
function Run-Batch([string]$Root,[string[]]$Files,[string]$Mode,[string]$Old,[string]$New,[bool]$ExpectSuccess) {
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Unexpected Excel process; stop without closing user work.' }
    $dir=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($dir); Set-PrivateDirectory $dir
    $hashes=@{}; foreach($file in $Files) { $hashes[$file]=Get-Sha $file }
    $me=[Diagnostics.Process]::GetCurrentProcess(); try { $start=$me.StartTime.ToUniversalTime().Ticks.ToString() } finally { $me.Dispose() }
    Write-Json @{schemaVersion=1;root=$Root;mode=$Mode;files=@($Files | ForEach-Object { @{path=$_} });oldSecret=(Cipher $Old);newSecret=(Cipher $New);ownerPid=$PID;ownerStartTicks=$start} (Join-Path $dir 'request.json')
    $script=Join-Path $toolRoot 'runtime/BatchEngine.ps1'
    $p=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -RequestPath "'+(Join-Path $dir 'request.json')+'"') -PassThru -WindowStyle Hidden
    try { if(-not $p.WaitForExit(660000)) { $p.Kill(); throw 'Batch test timed out; inspect Excel normally.' } } finally { $p.Dispose() }
    $r=Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($ExpectSuccess) {
        Assert ($r.status -eq 'Success' -and $r.succeededCount -eq $Files.Count -and -not $r.reportPath) ($Mode+' batch success without report')
    } else { Assert ($r.status -eq 'Failed' -and $r.items[0].attempts -eq 3 -and [IO.File]::Exists($r.reportPath)) 'wrong password three total attempts and report' }
    foreach($item in $r.items) {
        Assert ((Get-Sha $item.backup) -eq $hashes[$item.path]) ($Mode+' verified private original backup '+[IO.Path]::GetFileName($item.path))
        if(-not $ExpectSuccess) { Assert ((Get-Sha $item.path) -eq $hashes[$item.path]) 'wrong-password original remains byte identical' }
    }
    foreach($attemptDir in Get-ChildItem -LiteralPath $dir -Directory) {
        $recordPath=Join-Path $attemptDir.FullName 'result.json'
        if(-not [IO.File]::Exists($recordPath)) { continue }
        $record=Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach($field in @('temp','inputCopy','recovery')) { $owned=[string]$record.$field; Assert (-not $owned -or -not [IO.File]::Exists($owned)) ($Mode+' removed '+$field) }
        Assert (-not [IO.File]::Exists((Join-Path $attemptDir.FullName 'request.json')) -and -not [IO.File]::Exists((Join-Path $attemptDir.FullName 'worker-job.json'))) ($Mode+' secret IPC removed')
    }
    Write-Host ($Mode+' / '+$r.status+' / '+$Files.Count+' file(s)')
    return $r
}
try {
    $null=Run-Batch $sourceRoot $paths 'Encrypt' '' 'Batch한글42!' $true
    $wrongRoot=Join-Path $EvidenceDirectory 'wrong-only'; [void][IO.Directory]::CreateDirectory($wrongRoot)
    $wrongPath=Join-Path $wrongRoot '실패파일.xlsx'; [IO.File]::Copy($paths[0],$wrongPath)
    $null=Run-Batch $sourceRoot $paths 'ChangePassword' 'Batch한글42!' 'Next암호99!' $true
    $null=Run-Batch $sourceRoot $paths 'Decrypt' 'Next암호99!' '' $true
    $r=Run-Batch $wrongRoot @($wrongPath) 'Decrypt' 'Wrong-42!' '' $false
    $app=$null; $books=$null; $book=$null; $sheets=$null; $sheet=$null; $range=$null
    try {
        if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Unexpected Excel process before report inspection.' }
        $app=New-Object -ComObject Excel.Application; $app.Visible=$false; $app.DisplayAlerts=$false; $app.EnableEvents=$false; $app.AutomationSecurity=3
        $books=$app.Workbooks; $book=$books.Open([string]$r.reportPath,0,$true)
        $sheets=$book.Worksheets; $sheet=$sheets.Item(1); $range=$sheet.Range('A1:H2'); $values=$range.Value2
        Assert ($values[1,1] -eq '파일명 또는 폴더명' -and $values[2,1] -eq '실패파일.xlsx' -and $values[2,4] -eq '3' -and $values[2,5] -eq '실패') 'Excel opens failure workbook and reads name/path/attempt/status'
        Assert ($range.HasFormula -eq $false) 'failure workbook contains no active formulas'
    } finally {
        Release-Com $range; Release-Com $sheet; Release-Com $sheets
        if($null -ne $book) { $book.Close($false); Release-Com $book }; Release-Com $books
        if($null -ne $app) { $app.Quit(); Release-Com $app }; [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
    Write-Json @{status='PASS';assertions=$checks.Count;checks=$checks.ToArray();filesPerOperation=2;operations=@('Encrypt','ChangePassword','Decrypt');failedFileAttempts=3;reportExcelOpen='PASS';timestamp=[DateTime]::UtcNow.ToString('o')} (Join-Path $EvidenceDirectory 'batch-excel-results.json')
    Write-Output "PASS: $($checks.Count) real Excel batch assertions; $EvidenceDirectory"
} catch { Write-Json @{status='FAIL';checks=$checks.ToArray();error=$_.Exception.Message} (Join-Path $EvidenceDirectory 'batch-excel-results.json'); throw }
