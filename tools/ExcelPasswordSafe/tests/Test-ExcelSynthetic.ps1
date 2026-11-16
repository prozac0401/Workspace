#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory,[switch]$Quick,[switch]$UnicodeOnly)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Run with powershell.exe -STA.' }
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Excel is running; save work and close normally first.' }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$results=New-Object 'System.Collections.Generic.List[object]'
$fixtureRoot=Join-Path $toolRoot 'upstream/1.1.0/ExcelPasswordSafe/tests/fixtures'
$engine=Join-Path $toolRoot 'runtime/Engine.ps1'
$singleFormat=$Quick -or $UnicodeOnly
function Wait-ExcelExit {
    for($i=0;$i -lt 120 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count;$i++) { Start-Sleep -Milliseconds 250 }
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Excel remains running; suite stopped without force-killing it.' }
}
function Protect-Test([string]$Text) {
    if(-not $Text) { return '' }
    $secure=ConvertTo-SecureString $Text -AsPlainText -Force
    try { ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
}
function Invoke-Case([string]$Path,[string]$Case,[string]$Mode,[string]$Old,[string]$New,[string]$ExpectedStatus,[string]$ExpectedCategory,[switch]$CancelDuringWorker) {
    Wait-ExcelExit
    $before=Get-Sha $Path
    $run=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run); Set-PrivateDirectory $run
    $request=Join-Path $run 'request.json'
    Write-Json @{schemaVersion=1;path=$Path;mode=$Mode;oldSecret=Protect-Test $Old;newSecret=Protect-Test $New;expectedHash=$before} $request
    $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$engine+'" -RequestPath "'+$request+'"') -PassThru -WindowStyle Hidden
    $cancelSent=$false; $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        while(-not $p.WaitForExit(250)) {
            if($CancelDuringWorker -and -not $cancelSent) {
                $progressPath=Join-Path $run 'progress.json'
                if([IO.File]::Exists($progressPath)) {
                    $progress=Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if($progress.stage -eq 'Worker') { [IO.File]::WriteAllText((Join-Path $run 'cancel'),'cancel'); $cancelSent=$true }
                }
            }
            if($watch.Elapsed.TotalSeconds -gt 220) { $p.Kill(); throw 'Controller test timed out. Inspect remaining Excel normally.' }
        }
    } finally { $p.Dispose() }
    $r=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $passed=$r.status -eq $ExpectedStatus -and $r.category -eq $ExpectedCategory
    if($CancelDuringWorker) { $passed=$passed -and $cancelSent }
    if($ExpectedStatus -eq 'Success') {
        $state=Get-Content -LiteralPath (Join-Path $run 'state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $passed=$passed -and (Get-Sha $r.backup) -eq $before -and (Get-Sha $r.recovery) -eq $before -and (Get-Sha $Path) -eq $r.resultHash -and $state.state -eq 'Committed'
    } else { $passed=$passed -and (Get-Sha $Path) -eq $before }
    $passed=$passed -and -not [IO.File]::Exists($request) -and -not [IO.File]::Exists((Join-Path $run 'worker-job.json'))
    $record=[pscustomobject]@{fixture=[IO.Path]::GetFileName($Path);case=$Case;passed=$passed;status=$r.status;category=$r.category;stage=$r.stage;hresults=$r.hresults;run=$run;sourceHash=$before;resultHash=Get-Sha $Path}
    $results.Add($record)
    $record | Export-Csv -LiteralPath (Join-Path $EvidenceDirectory 'excel-results.csv') -Append -NoTypeInformation -Encoding UTF8
    Write-Host ($record.fixture+' / '+$Case+' / '+$r.category+' / passed='+$passed)
    Wait-ExcelExit
    if(-not $passed) { throw ('Case failed: '+$Case+' '+$r.category+'; '+$run) }
}
function Get-VbaHash([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry=$archive.GetEntry('xl/vbaProject.bin')
        if($null -eq $entry) { throw 'VBA payload missing' }
        $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
        try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $sha.Dispose(); $stream.Dispose() }
    } finally { $archive.Dispose() }
}
$app=$null; $books=$null; $book=$null; $fixtures=New-Object 'System.Collections.Generic.List[string]'
try {
    . (Join-Path $toolRoot 'upstream/1.1.0/ExcelPasswordSafe/tests/Get-ExcelTestEnvironment.ps1')
    if(-not $singleFormat) {
        $app=New-Object -ComObject Excel.Application
        $app.Visible=$false; $app.DisplayAlerts=$false; $app.EnableEvents=$false; $app.AutomationSecurity=3
        $books=$app.Workbooks
    }
    $null=Get-ExcelTestEnvironment -ExcelApplication $app -OutputPath (Join-Path $EvidenceDirectory 'environment.json')
    $names=if($singleFormat){@('picture_ooxml.xlsx')}else{@('picture_ooxml.xlsx','picture_biff8.xls','picture_vba.xlsm')}
    foreach($name in $names) {
        $path=Join-Path $EvidenceDirectory ('한글 [검증] & $ '+$name)
        [IO.File]::Copy((Join-Path $fixtureRoot $name),$path)
        $fixtures.Add($path)
    }
    if(-not $singleFormat) {
        foreach($pair in @(@('binary.xlsb',50),@('strict.xlsx',61))) {
            $path=Join-Path $EvidenceDirectory $pair[0]
            $book=$books.Open((Join-Path $fixtureRoot 'picture_ooxml.xlsx'),0,$true)
            $book.SaveAs($path,[int]$pair[1]); $book.Close($false); Release-Com $book; $book=$null
            $fixtures.Add($path)
        }
    }
} finally {
    if($null -ne $book) { $book.Close($false); Release-Com $book }
    Release-Com $books
    if($null -ne $app) { $app.Quit(); Release-Com $app }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
Wait-ExcelExit
try {
    foreach($path in $fixtures) {
        if($UnicodeOnly) {
            Invoke-Case $path 'UnicodeEncrypt' 'Encrypt' '' 'Test한글42!' 'Success' 'ReplacedAndVerified'
            Invoke-Case $path 'UnicodeChange' 'ChangePassword' 'Test한글42!' 'Next암호99!' 'Success' 'ReplacedAndVerified'
            Invoke-Case $path 'UnicodeDecrypt' 'Decrypt' 'Next암호99!' '' 'Success' 'ReplacedAndVerified'
            continue
        }
        $vbaBefore=if([IO.Path]::GetExtension($path) -eq '.xlsm'){Get-VbaHash $path}else{''}
        Invoke-Case $path 'Encrypt' 'Encrypt' '' 'Before-42!' 'Success' 'ReplacedAndVerified'
        Invoke-Case $path 'ChangeWrongCurrent' 'ChangePassword' 'Incorrect-1' 'After-99!' 'Failed' 'OpenFailedPossiblePasswordOrCorruption'
        Invoke-Case $path 'ChangePassword' 'ChangePassword' 'Before-42!' 'After-99!' 'Success' 'ReplacedAndVerified'
        Invoke-Case $path 'OldPasswordRejected' 'Decrypt' 'Before-42!' '' 'Failed' 'OpenFailedPossiblePasswordOrCorruption'
        Invoke-Case $path 'Decrypt' 'Decrypt' 'After-99!' '' 'Success' 'ReplacedAndVerified'
        Invoke-Case $path 'ChangeUnencrypted' 'ChangePassword' 'NotPresent-1' 'After-99!' 'Skipped' 'AlreadyUnencrypted'
        if($vbaBefore) { Write-Json @{before=$vbaBefore;after=Get-VbaHash $path;byteIdentical=$vbaBefore -eq (Get-VbaHash $path)} (Join-Path $EvidenceDirectory 'vba-preservation.json') }
    }
    if(-not $UnicodeOnly) { Invoke-Case $fixtures[0] 'CancelDuringWorker' 'Encrypt' '' 'Cancel-42!' 'Cancelled' 'Cancelled' -CancelDuringWorker }
    Write-Json @{status='PASS';count=$results.Count;results=$results.ToArray();timestamp=[DateTime]::UtcNow.ToString('o')} (Join-Path $EvidenceDirectory 'excel-summary.json')
    Write-Output "PASS: $($results.Count) real Excel cases; $EvidenceDirectory"
} catch {
    Write-Json @{status='FAIL';count=$results.Count;results=$results.ToArray();error=$_.Exception.Message} (Join-Path $EvidenceDirectory 'excel-summary.json')
    throw
}
