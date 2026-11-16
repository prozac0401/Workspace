#requires -Version 5.1
#requires -PSEdition Desktop
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory,[switch]$CleanupOnly)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Close Excel normally before batch tests.' }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$runtime=Join-Path $EvidenceDirectory 'isolated-runtime'; [void][IO.Directory]::CreateDirectory($runtime)
foreach($name in @('BatchEngine.ps1','Common.ps1')) { [IO.File]::Copy((Join-Path $toolRoot ('runtime/'+$name)),(Join-Path $runtime $name)) }
$utf8=New-Object Text.UTF8Encoding($true)
$stub=@'
param([string]$RequestPath,[string]$CancellationPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$dir=[IO.Path]::GetDirectoryName($RequestPath)
$batch=[IO.Path]::GetDirectoryName($dir)
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$name=[IO.Path]::GetFileName($request.path)
$counter=Join-Path $batch ($name+'.count')
$attempt=if([IO.File]::Exists($counter)){[int][IO.File]::ReadAllText($counter)+1}else{1}
[IO.File]::WriteAllText($counter,[string]$attempt)
$mutex=New-Object Threading.Mutex($false,(Get-EngineMutexName))
if(-not $mutex.WaitOne(0)) { throw 'ReentrantMutexFailed' }
$mutex.ReleaseMutex(); $mutex.Dispose()
if($name -eq 'third.xlsx' -and $attempt -eq 1) {
 $check=Join-Path $batch 'peer.json'
 $p=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -File "'+(Join-Path $PSScriptRoot 'peer.ps1')+'" -Output "'+$check+'"') -PassThru -WindowStyle Hidden
 if(-not $p.WaitForExit(10000)) { throw 'PeerTimeout' }; $p.Dispose()
 if([IO.File]::ReadAllText($check) -ne 'Busy') { throw 'ParentMutexNotHeld' }
}
if($name -eq 'missing.xlsx') { [IO.File]::Delete($RequestPath); exit 17 }
if($name -eq 'throw.xlsx') { throw 'synthetic child interruption' }
$status='Success'; $category='ReplacedAndVerified'; $temp=''
if($name -eq 'wrong.xlsx' -or ($name -eq 'third.xlsx' -and $attempt -lt 3)) { $status='Failed'; $category='OpenFailedPossiblePasswordOrCorruption' }
if($name -eq 'locked.xlsx') { $status='Failed'; $category='FileInUse' }
if($name -eq 'skip.xlsx') { $status='Skipped'; $category='AlreadyUnencrypted' }
if($name -eq 'signed.xlsx') { $status='Skipped'; $category='SignedWorkbookUnsupported' }
if($name -eq 'cancel.xlsx') { $status='Cancelled'; $category='Cancelled'; [IO.File]::WriteAllText($CancellationPath,'cancel') }
if($name -eq 'changed.xlsx') { $status='Failed'; $category='ValidationFailed'; [IO.File]::WriteAllText([string]$request.path,'external newer bytes') }
if($name -eq 'report-error.xlsx') { $status='Failed'; $category='OpenFailedPossiblePasswordOrCorruption'; [void][IO.Directory]::CreateDirectory((Join-Path $batch 'failure-report.xlsx')) }
if($name -eq 'cleanup.xlsx') { $temp=Join-Path $dir 'owned-temp.xlsx'; [IO.File]::WriteAllText($temp,'fixture') }
if($name -eq 'secret-left.xlsx') { [IO.File]::WriteAllText((Join-Path $dir 'worker-job.json'),'fixture') }
[IO.File]::Delete($RequestPath)
Write-Json @{status=$status;category=$category;backup='';temp=$temp;inputCopy='';message=''} (Join-Path $dir 'result.json')
if($status -eq 'Success') { exit 0 }; exit 1
'@
[IO.File]::WriteAllText((Join-Path $runtime 'Engine.ps1'),$stub,$utf8)
[IO.File]::WriteAllText((Join-Path $runtime 'peer.ps1'),@'
param([string]$Output)
. (Join-Path $PSScriptRoot 'Common.ps1')
$m=New-Object Threading.Mutex($false,(Get-EngineMutexName))
$owned=$m.WaitOne(0)
if($owned){$m.ReleaseMutex()}; $m.Dispose()
[IO.File]::WriteAllText($Output,$(if($owned){'Free'}else{'Busy'}))
'@,$utf8)
$records=New-Object 'System.Collections.Generic.List[object]'
function Assert($Condition,[string]$Name) {
    $records.Add([pscustomobject]@{name=$Name;passed=[bool]$Condition})
    if(-not $Condition) { throw ('ASSERT '+$Name) }
}
$secure=ConvertTo-SecureString 'Batch-42!' -AsPlainText -Force
try { $cipher=ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
function Invoke-BatchFixture([string]$Name,[string[]]$Names,[object[]]$Issues=@(),[switch]$Cancel,[switch]$Duplicate,[switch]$Outside,[switch]$OwnData,[switch]$OwnerGone,[switch]$LockRequest) {
    $folder=Join-Path $EvidenceDirectory $Name; [void][IO.Directory]::CreateDirectory($folder)
    $entries=@()
    foreach($fileName in $Names) {
        $path=Join-Path $folder $fileName
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path,'original fixture')
        $entries+=@(@{path=$path})
    }
    if($Duplicate) { $entries+=@($entries[0]) }
    if($Outside) { $entries+=@(@{path=(Join-Path $EvidenceDirectory 'outside.xlsx')}) }
    $dir=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($dir); Set-PrivateDirectory $dir
    $root=if($OwnData){Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ExcelPasswordSafe'}else{$folder}
    $mappedIssues=@($Issues | ForEach-Object { @{path=(Join-Path $folder $_.path);category=$_.category} })
    $request=@{schemaVersion=1;root=$root;mode='Encrypt';files=@($entries);discoveryIssues=$mappedIssues;oldSecret='';newSecret=$(if($entries.Count){$cipher}else{''})}
    if($OwnerGone) { $request.ownerPid=$PID; $request.ownerStartTicks='1' }
    Write-Json $request (Join-Path $dir 'request.json')
    if($Cancel){[IO.File]::WriteAllText((Join-Path $dir 'cancel'),'cancel')}
    $batch=Join-Path $runtime 'BatchEngine.ps1'
    $requestLock=$null
    if($LockRequest) { $requestLock=[IO.File]::Open((Join-Path $dir 'request.json'),'Open','Read','Read') }
    $p=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$batch+'" -RequestPath "'+(Join-Path $dir 'request.json')+'"') -PassThru -WindowStyle Hidden
    try { if(-not $p.WaitForExit(45000)) { $p.Kill(); throw 'Batch fixture timeout' } } finally { $p.Dispose(); if($null -ne $requestLock){$requestLock.Dispose()} }
    $r=Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($LockRequest) {
        Assert ([IO.File]::Exists((Join-Path $dir 'request.json'))) ($Name+' injected request lock prevented cleanup')
        [IO.File]::Delete((Join-Path $dir 'request.json'))
    } else { Assert (-not [IO.File]::Exists((Join-Path $dir 'request.json'))) ($Name+' request ciphertext removed') }
    Add-Member -InputObject $r -MemberType NoteProperty -Name evidenceDir -Value $dir
    return $r
}
try {
    if($CleanupOnly) {
        $r=Invoke-BatchFixture 'request-cleanup' @('ok.xlsx') -LockRequest
        Assert ($r.status -eq 'Failed' -and $r.category -eq 'TemporaryCleanupIncomplete' -and [IO.File]::Exists($r.reportPath)) 'request cleanup exception still writes actionable result and report'
        Write-Json @{status='PASS';assertions=$records.Count;checks=$records.ToArray();scope='targeted outer-finally cleanup fault'} (Join-Path $EvidenceDirectory 'batch-results.json')
        Write-Output "PASS: $($records.Count) targeted batch cleanup assertions; $EvidenceDirectory"
        return
    }
    $r=Invoke-BatchFixture 'mixed' @('third.xlsx','nested\wrong.xlsx','nested\deeper\ok.xlsx','skip.xlsx','signed.xlsx')
    Assert ($r.status -eq 'PartialFailure' -and $r.items.Count -eq 5) 'recursive manifest entries retained after child exit1'
    Assert ($r.items[0].attempts -eq 3 -and $r.items[0].status -eq 'Success') 'two retries then third success'
    Assert ($r.items[1].attempts -eq 3 -and $r.items[1].status -eq 'Failed') 'wrong password exactly three total attempts'
    Assert ($r.items[2].status -eq 'Success' -and $r.items[3].status -eq 'Skipped') 'later success and desired-state skip continue'
    Assert ($r.items[4].status -eq 'Failed' -and $r.items[4].attempts -eq 1) 'unsupported signed file final failure without pointless retry'
    Assert ([IO.File]::ReadAllText((Join-Path $r.evidenceDir 'peer.json')) -eq 'Busy') 'same-thread nested mutex with outer lock still held'
    Assert ([IO.File]::Exists($r.reportPath)) 'failure workbook generated'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($r.reportPath)
    try {
        $reader=New-Object IO.StreamReader($zip.GetEntry('xl/worksheets/sheet1.xml').Open()); try { $xml=[xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
        $ns=New-Object Xml.XmlNamespaceManager($xml.NameTable); $ns.AddNamespace('s','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        Assert ($xml.SelectNodes('//s:row',$ns).Count -eq 3) 'report contains header and only two final failures'
        Assert ($xml.SelectNodes('//s:f',$ns).Count -eq 0 -and $xml.SelectNodes('//s:c[not(@t="inlineStr")]',$ns).Count -eq 0) 'report all strings, no formula execution'
        Assert ($xml.OuterXml.Contains('암호를 확인') -and $zip.Entries.Count -eq 5) 'readable Korean reason and complete OpenXML package'
    } finally { $zip.Dispose() }
    $r=Invoke-BatchFixture 'clean' @('ok.xlsx','nested\ok2.xlsx')
    Assert ($r.status -eq 'Success' -and -not $r.reportPath -and -not [IO.File]::Exists((Join-Path $r.evidenceDir 'failure-report.xlsx'))) 'all success produces no failure workbook'
    $r=Invoke-BatchFixture 'locked' @('locked.xlsx')
    Assert ($r.items[0].attempts -eq 3) 'ordinary locked failure exactly three attempts'
    $r=Invoke-BatchFixture 'cancelled-before' @('ok.xlsx','nested\ok.xlsx') -Cancel
    Assert ($r.status -eq 'Cancelled' -and $r.items[0].attempts -eq 0 -and $r.notProcessedCount -eq 2 -and -not $r.reportPath) 'pre-cancel starts no child and produces no false failure report'
    $r=Invoke-BatchFixture 'cancelled-during' @('cancel.xlsx','later.xlsx')
    Assert ($r.status -eq 'Cancelled' -and $r.items[0].status -eq 'Cancelled' -and $r.items[1].status -eq 'NotProcessed') 'cancel stops remaining manifest files'
    $r=Invoke-BatchFixture 'interrupted' @('missing.xlsx','later.xlsx')
    Assert ($r.items[0].status -eq 'NeedsInspection' -and $r.items[0].attempts -eq 1 -and $r.items[1].status -eq 'NotProcessed' -and [IO.File]::Exists($r.reportPath)) 'missing child result never retried; remaining files reported'
    $r=Invoke-BatchFixture 'child-threw' @('throw.xlsx','later.xlsx')
    Assert ($r.items[0].category -eq 'MissingChildResult' -and $r.items[0].attempts -eq 1 -and $r.items[1].status -eq 'NotProcessed') 'throwing child with no final result is never retried'
    $r=Invoke-BatchFixture 'changed' @('changed.xlsx','later.xlsx')
    Assert ($r.items[0].category -eq 'SourceChanged' -and $r.items[0].status -eq 'NeedsInspection' -and [IO.File]::ReadAllText($r.items[0].path) -eq 'external newer bytes') 'first hash pins retries and external modification survives'
    $r=Invoke-BatchFixture 'cleanup' @('cleanup.xlsx','later.xlsx')
    Assert ($r.items[0].category -eq 'TemporaryCleanupIncomplete' -and $r.items[0].attempts -eq 1 -and $r.items[1].status -eq 'NotProcessed') 'leftover work file blocks retries and further processing'
    $r=Invoke-BatchFixture 'secret-left' @('secret-left.xlsx','later.xlsx')
    Assert ($r.items[0].category -eq 'TemporaryCleanupIncomplete' -and $r.items[0].attempts -eq 1 -and $r.items[1].status -eq 'NotProcessed') 'leftover secret job blocks retry and further processing'
    $r=Invoke-BatchFixture 'discovery-only' @() @(@{path='unreadable';category='FolderAccessDenied'})
    Assert ($r.failureCount -eq 1 -and $r.items[0].attempts -eq 0 -and [IO.File]::Exists($r.reportPath)) 'discovery failure alone produces report'
    $r=Invoke-BatchFixture 'report-failure' @('report-error.xlsx')
    Assert ($r.status -eq 'Failed' -and $r.category -eq 'FailureReportFailed' -and -not $r.reportPath -and -not [IO.File]::Exists((Join-Path $r.evidenceDir 'failure-report.xlsx.pending'))) 'report write error explicit with no pending file'
    $r=Invoke-BatchFixture 'duplicates' @('ok.xlsx') -Duplicate
    Assert ($r.category -eq 'DuplicateBatchPath') 'duplicate manifest rejected before processing'
    $r=Invoke-BatchFixture 'outside' @('ok.xlsx') -Outside
    Assert ($r.category -eq 'PathOutsideRoot') 'outside root rejected before processing'
    $r=Invoke-BatchFixture 'own-data' @() -OwnData
    Assert ($r.category -eq 'AppDataExcluded') 'app backup tree excluded independently by backend'
    $r=Invoke-BatchFixture 'owner-gone' @('ok.xlsx','later.xlsx') -OwnerGone
    Assert ($r.status -eq 'Cancelled' -and $r.category -eq 'OwnerExited' -and $r.items[0].attempts -eq 0 -and -not $r.reportPath) 'owner identity mismatch stops before processing without false failure report'
    $mutex=New-Object Threading.Mutex($false,(Get-EngineMutexName)); $owned=$mutex.WaitOne(0)
    if(-not $owned) { throw 'Another real operation started; test stopped.' }
    try { $r=Invoke-BatchFixture 'concurrent' @('ok.xlsx') } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
    Assert ($r.category -eq 'AnotherOperationRunning' -and $r.items[0].attempts -eq 0 -and [IO.File]::Exists($r.reportPath)) 'other process cannot start a concurrent batch; unprocessed failure is reported'
    $r=Invoke-BatchFixture 'request-cleanup' @('ok.xlsx') -LockRequest
    Assert ($r.status -eq 'Failed' -and $r.category -eq 'TemporaryCleanupIncomplete' -and [IO.File]::Exists($r.reportPath)) 'request cleanup exception still writes actionable result and report'
    Write-Json @{status='PASS';assertions=$records.Count;checks=$records.ToArray();excel='NOT RUN; isolated fixture child engine'} (Join-Path $EvidenceDirectory 'batch-results.json')
    Write-Output "PASS: $($records.Count) batch assertions; $EvidenceDirectory"
} catch {
    Write-Json @{status='FAIL';assertions=$records.Count;checks=$records.ToArray();error=$_.Exception.Message} (Join-Path $EvidenceDirectory 'batch-results.json')
    throw
}
