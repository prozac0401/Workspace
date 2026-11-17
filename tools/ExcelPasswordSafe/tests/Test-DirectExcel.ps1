#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RuntimeDirectory,[Parameter(Mandatory=$true)][string]$EvidenceDirectory,[switch]$SmallOnly)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $RuntimeDirectory 'Common.ps1')
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'STA required.' }
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Excel is running; do not touch it.' }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$checks=New-Object 'System.Collections.Generic.List[object]'
$timings=New-Object 'System.Collections.Generic.List[object]'
function Check([bool]$Condition,[string]$Name) {
    $checks.Add(@{name=$Name;passed=$Condition})
    Write-Json @{status=$(if($Condition){'PASS'}else{'FAIL'});checks=$checks.ToArray();timings=$timings.ToArray()} (Join-Path $EvidenceDirectory 'direct-excel-results.json')
    if(-not $Condition) { throw ('Check failed: '+$Name) }
}
function Wait-Excel {
    for($i=0;$i -lt 120 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count;$i++) { Start-Sleep -Milliseconds 250 }
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Excel remains running. Stop without killing it.' }
}
function With-Excel([string]$Path,[string]$Password,[string]$SavePath='',[int]$Format=0,[string]$SavePassword='',[switch]$Reject) {
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Unexpected Excel; no attachment permitted.' }
    $app=$null;$books=$null;$book=$null;$answer=$null
    try {
        $app=New-Object -ComObject Excel.Application
        $app.Visible=$false; $app.DisplayAlerts=$false; $app.EnableEvents=$false; $app.AutomationSecurity=3; $app.AskToUpdateLinks=$false
        $books=$app.Workbooks
        $missing=[Type]::Missing
        $pass=if($Password){$Password}else{'NoPassword-42!'}
        $rejected=$false
        try { $book=$books.Open($Path,0,$true,$missing,$pass,'NoWrite-42!',$true,$missing,$missing,$false,$false,$missing,$false,$false) }
        catch { if(-not $Reject -or (Get-HResults $_) -notmatch '0x800A03EC') { throw }; $rejected=$true }
        if($Reject) { Check ($rejected -and $null -eq $book) ('Excel rejects password: '+[IO.Path]::GetFileName($Path)); return }
        $answer=@{signature=(Get-WorkbookSignature $book);hasPassword=[bool]$book.HasPassword;format=[int]$book.FileFormat}
        if($SavePath) { $book.SaveAs($SavePath,$Format,$SavePassword,'',$false,$false,1,2,$false,$missing,$missing,$false) }
    } finally {
        if($null -ne $book) { $book.Close($false); Release-Com $book }
        if($null -ne $books -and $books.Count -ne 0) { throw 'Unexpected workbook; keep Excel for inspection.' }
        Release-Com $books
        if($null -ne $app) { $app.Quit(); Release-Com $app }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        Wait-Excel
    }
    return $answer
}
function Protect-Test([string]$Text) {
    if(-not $Text) { return '' }
    $secure=ConvertTo-SecureString $Text -AsPlainText -Force
    try { ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
}
function Operate([string]$Path,[string]$Mode,[string]$Old,[string]$New,[string]$Expected='Success') {
    Wait-Excel
    $before=Get-Sha $Path
    $run=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run); Set-PrivateDirectory $run
    $request=Join-Path $run 'request.json'
    Write-Json @{schemaVersion=1;path=$Path;mode=$Mode;expectedHash=$before;oldSecret=(Protect-Test $Old);newSecret=(Protect-Test $New)} $request
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+(Join-Path $RuntimeDirectory 'Engine.ps1')+'" -RequestPath "'+$request+'"') -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $run 'stderr.log')
    try { if(-not $p.WaitForExit(180000)) { [IO.File]::WriteAllText((Join-Path $run 'cancel'),'cancel'); throw 'Operation timed out; cancellation requested.' } } finally { $watch.Stop(); $p.Dispose() }
    $r=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $timings.Add(@{file=[IO.Path]::GetFileName($Path);mode=$Mode;milliseconds=$watch.Elapsed.TotalMilliseconds;backend=$r.backend;status=$r.status;run=$run})
    Check ($r.status -eq $Expected) ($Mode+' '+[IO.Path]::GetFileName($Path)+' status '+$r.status+' '+$r.category)
    Check ($r.backend -eq 'DirectOoxml') ($Mode+' uses direct backend')
    Check ((Get-Sha $r.backup) -eq $before) 'byte-identical original backup'
    if($Expected -eq 'Success') { Check ((Get-Sha $Path) -eq $r.resultHash -and $r.recoveryRemoved) 'atomic replacement and recovery cleanup' }
    else { Check ((Get-Sha $Path) -eq $before) 'failed/skipped source untouched' }
    foreach($file in @($request,(Join-Path $run 'worker-job.json'),$r.temp,$r.inputCopy,$r.recovery)) { if($file) { Check (-not [IO.File]::Exists($file)) 'no owned intermediate remains' } }
    Check (@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count -eq 0) 'direct operation leaves no Excel process'
}
$fixtures=Join-Path $toolRoot 'upstream/1.1.0/ExcelPasswordSafe/tests/fixtures'
$xlsx=Join-Path $EvidenceDirectory 'normal.xlsx'
$xlsm=Join-Path $EvidenceDirectory 'macro.xlsm'
$strict=Join-Path $EvidenceDirectory 'strict.xlsx'
[IO.File]::Copy((Join-Path $fixtures 'picture_ooxml.xlsx'),$xlsx)
if(-not $SmallOnly) {
[IO.File]::Copy((Join-Path $fixtures 'picture_vba.xlsm'),$xlsm)
$null=With-Excel $xlsx '' $strict 61 ''
# Minimal, valid OOXML checks CFB mini-stream interoperability below 4096 bytes.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tiny=Join-Path $EvidenceDirectory 'tiny.xlsx'
$parts=@{
 '[Content_Types].xml'='<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
 '_rels/.rels'='<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
 'xl/workbook.xml'='<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sample" sheetId="1" r:id="r1"/></sheets></workbook>'
 'xl/_rels/workbook.xml.rels'='<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
 'xl/worksheets/sheet1.xml'='<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1"><v>42</v></c></row></sheetData></worksheet>'
}
$zip=[IO.Compression.ZipFile]::Open($tiny,[IO.Compression.ZipArchiveMode]::Create)
try { foreach($key in $parts.Keys) { $entry=$zip.CreateEntry($key);$writer=New-Object IO.StreamWriter($entry.Open(),(New-Object Text.UTF8Encoding($false)));try{$writer.Write($parts[$key])}finally{$writer.Dispose()} } } finally { $zip.Dispose() }
Check ((Get-Item -LiteralPath $tiny).Length -lt 4096) 'tiny fixture is under mini-stream threshold'
}
$testFiles=if($SmallOnly){@($xlsx)}else{@($xlsx,$xlsm,$strict,$tiny)}
foreach($path in $testFiles) {
    $original=Get-Sha $path
    $baseline=With-Excel $path ''
    Operate $path 'Encrypt' '' 'Test한글42!'
    $opened=With-Excel $path 'Test한글42!'
    Check ($opened.signature -ceq $baseline.signature -and $opened.hasPassword) 'Excel opens direct encrypted bytes with identical content signature'
    With-Excel $path 'Wrong42!' -Reject
    Operate $path 'ChangePassword' 'Wrong42!' 'Next암호99!' 'Failed'
    Operate $path 'ChangePassword' 'Test한글42!' 'Next암호99!'
    $opened=With-Excel $path 'Next암호99!'
    Check ($opened.signature -ceq $baseline.signature -and $opened.hasPassword) 'Excel opens changed password with identical content signature'
    With-Excel $path 'Test한글42!' -Reject
    Operate $path 'Decrypt' 'Next암호99!' ''
    Check ((Get-Sha $path) -ceq $original) 'entire plaintext ZIP restored byte for byte, including VBA/pictures'
    $opened=With-Excel $path ''
    Check ($opened.signature -ceq $baseline.signature -and -not $opened.hasPassword) 'Excel opens direct decrypted output'
    $excelEncrypted=Join-Path $EvidenceDirectory ('excel-'+[IO.Path]::GetFileName($path))
    $null=With-Excel $path '' $excelEncrypted $baseline.format 'Excel암호42!'
    Operate $excelEncrypted 'Decrypt' 'Excel암호42!' ''
    $opened=With-Excel $excelEncrypted ''
    Check ($opened.signature -ceq $baseline.signature -and -not $opened.hasPassword) 'direct backend decrypts Excel-produced encryption'
}
Write-Json @{status='PASS';scope=$(if($SmallOnly){'normal xlsx only'}else{'normal xlsx, macro xlsm, Strict xlsx, tiny xlsx'});count=$checks.Count;checks=$checks.ToArray();timings=$timings.ToArray();runtime=@(Get-ChildItem -LiteralPath $RuntimeDirectory -File | ForEach-Object {@{name=$_.Name;sha256=(Get-Sha $_.FullName)}})} (Join-Path $EvidenceDirectory 'direct-excel-results.json')
Write-Output ('PASS: '+$checks.Count+' real Excel interoperability checks; '+$EvidenceDirectory)
