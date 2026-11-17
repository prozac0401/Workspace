#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RequestPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$RequestPath=[IO.Path]::GetFullPath($RequestPath)
$batchDir=[IO.Path]::GetDirectoryName($RequestPath)
if([IO.Path]::GetFileName($RequestPath) -cne 'request.json' -or [IO.Path]::GetFileName($batchDir) -notmatch '^[0-9a-fA-F]{32}$') { throw 'DedicatedRunDirectoryRequired' }
Assert-NoReparse $RequestPath
Set-PrivateDirectory $batchDir
$batchResultPath=Join-Path $batchDir 'result.json'; $batchProgressPath=Join-Path $batchDir 'progress.json'; $batchCancel=Join-Path $batchDir 'cancel'
if([IO.File]::Exists($batchResultPath) -or [IO.File]::Exists($batchProgressPath)) { throw 'RunAlreadyUsed' }
$batchItems=New-Object 'System.Collections.Generic.List[object]'
$batchResult=[ordered]@{schemaVersion=1;status='Failed';category='';root='';mode='';items=@();reportPath='';failureCount=0;succeededCount=0;skippedCount=0;notProcessedCount=0;cancelledCount=0;time=''}
$batchRequest=$null; $batchMutex=$null; $batchLocked=$false; $batchStop=''; $batchEntries=@()
$batchOwnerPid=0; $batchOwnerStart=''
$batchSession=@{directory=(Join-Path $batchDir 'worker-session');token=[guid]::NewGuid().ToString('N');sequence=0;process=$null;healthy=$false;excelPid=0;excelStartTicks='';userOwnerPid=0;userOwnerStart=''}

function Get-BatchValue($Object,[string]$Name) {
    if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}
function Resolve-BatchPath([string]$Path,[string]$Root,[bool]$AllowRoot=$false) {
    if($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2).Contains(':')) { throw 'InvalidBatchPath' }
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if(-not $full.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase) -and -not ($AllowRoot -and $full.Equals($Root,[StringComparison]::OrdinalIgnoreCase))) { throw 'PathOutsideRoot' }
    return $full
}
function Assert-OutsideAppData([string]$Path) {
    $owned=[IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'),'ExcelPasswordSafe').TrimEnd('\')
    if($Path.Equals($owned,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($owned+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'AppDataExcluded' }
}
function Get-BatchReason([string]$Category) {
    switch($Category) {
        'OpenFailedPossiblePasswordOrCorruption' { '암호를 확인하고 Excel에서 파일이 정상으로 열리는지 확인하세요.' }
        'FileInUse' { '파일을 사용 중인 프로그램을 닫고 다시 시도하세요.' }
        'ReadOnlyAttribute' { '읽기 전용 파일입니다. 파일 속성을 확인하세요.' }
        'AccessDenied' { '파일 또는 폴더 접근 권한이 없습니다.' }
        'FolderAccessDenied' { '하위 폴더를 읽을 권한이 없어 그 안의 파일을 확인하지 못했습니다.' }
        'FolderReadFailed' { '하위 폴더의 파일 목록을 읽지 못했습니다.' }
        'FileEntryReadFailed' { '파일 정보를 읽지 못했습니다.' }
        'EntryReadFailed' { '파일 또는 폴더 정보를 읽지 못했습니다.' }
        'FolderChangedOrUnsupported' { '폴더가 변경되었거나 지원하지 않는 경로입니다.' }
        'ExistingExcel' { 'Excel이 실행 중입니다. 작업을 저장하고 Excel을 정상 종료한 뒤 다시 시도하세요.' }
        'AnotherOperationRunning' { '다른 암호 작업이 실행 중입니다. 완료 후 다시 시도하세요.' }
        'ReparsePoint' { '연결·재분석 경로는 처리하지 않습니다.' }
        'OfflineFileUnsupported' { '오프라인 파일이나 폴더는 별도 로컬 복사본으로 처리하세요.' }
        'AppDataExcluded' { '앱의 원본 백업과 실행 기록 폴더는 처리 대상에서 제외했습니다.' }
        'SourceChanged' { '처리 중 파일이 변경되어 재시도를 중단했습니다. 최신 파일을 확인하세요.' }
        'CommitUncertain' { '저장 여부가 불확실합니다. 원본·백업·복구본을 확인하세요.' }
        'TemporaryCleanupIncomplete' { '작업용 파일 정리가 끝나지 않았습니다. 실행 기록을 확인하세요.' }
        'WorkerTimeout' { 'Excel 응답 시간이 지났습니다. 남은 Excel과 작업 파일을 확인하세요.' }
        'ExcelStillRunning' { 'Excel이 종료되지 않았습니다. 정상 종료 후 실행 기록을 확인하세요.' }
        'WorkerSessionUnsafe' { 'Excel 상태를 확인할 수 없어 중단했습니다. 실행 기록과 열린 Excel을 확인하세요.' }
        'SignedWorkbookUnsupported' { '서명된 통합 문서는 지원하지 않습니다.' }
        'SharedWorkbookUnsupported' { '공유 통합 문서는 지원하지 않습니다.' }
        'WriteReservedUnsupported' { '쓰기 암호가 있는 통합 문서는 지원하지 않습니다.' }
        'UnsupportedOrMismatchedFormat' { '확장자와 실제 형식이 다르거나 지원하지 않는 구형 형식입니다.' }
        'Excel4MacroSheetUnsupported' { 'Excel 4.0 매크로 시트는 지원하지 않습니다.' }
        'FileNotFound' { '파일을 찾을 수 없습니다.' }
        'ValidationFailed' { '저장 후 검증을 통과하지 못했습니다. 원본을 유지했습니다.' }
        default { '작업을 완료하지 못했습니다. 실행 기록과 확인 코드를 확인하세요.' }
    }
}
function Get-BatchCancellation {
    if([IO.File]::Exists($batchCancel)) { return 'Cancelled' }
    if($batchOwnerPid -gt 0) {
        $owner=$null
        try {
            $owner=[Diagnostics.Process]::GetProcessById($batchOwnerPid)
            if($owner.HasExited -or $owner.StartTime.ToUniversalTime().Ticks.ToString() -cne $batchOwnerStart) { return 'OwnerExited' }
        } catch { return 'OwnerExited' }
        finally { if($null -ne $owner) { $owner.Dispose() } }
    }
    return ''
}
function New-BatchItem([string]$Path,[string]$State,[string]$Category,[int]$Attempts=0) {
    [pscustomobject]@{path=$Path;status=$State;category=$Category;attempts=$Attempts;maxAttempts=3;backup='';runDirectory='';time=[DateTime]::UtcNow.ToString('o')}
}
function Save-BatchProgress([string]$Stage,[int]$Index,[int]$Attempt,[string]$Path) {
    Write-Json @{schemaVersion=1;stage=$Stage;index=$Index;total=$batchEntries.Count;path=$Path;attempt=$Attempt;maxAttempts=3;completed=$batchItems.Count;message=$Stage} $batchProgressPath
}
function Write-BatchFailureReport([object[]]$Items,[string]$Path,[string]$Mode) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $pending=$Path+'.pending'
    $stream=$null; $archive=$null
    function Add-ZipText([string]$Name,[string]$Text) {
        $entry=$archive.CreateEntry($Name,[IO.Compression.CompressionLevel]::Optimal)
        $writer=New-Object IO.StreamWriter($entry.Open(),(New-Object Text.UTF8Encoding($false)))
        try { $writer.Write($Text) } finally { $writer.Dispose() }
    }
    function Xml-Cell([string]$Text) {
        # Excel cells are inline strings even when a path/reason starts with '='.
        $safe=[regex]::Replace($Text,'[\x00-\x08\x0B\x0C\x0E-\x1F]','')
        if($safe.Length -gt 32767) { $safe=$safe.Substring(0,32767) }
        return '<c t="inlineStr"><is><t xml:space="preserve">'+[Security.SecurityElement]::Escape($safe)+'</t></is></c>'
    }
    try {
        $stream=[IO.File]::Open($pending,'CreateNew','ReadWrite','None')
        $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        Add-ZipText '[Content_Types].xml' '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
        Add-ZipText '_rels/.rels' '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        Add-ZipText 'xl/workbook.xml' '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="실패 기록" sheetId="1" r:id="rId1"/></sheets></workbook>'
        Add-ZipText 'xl/_rels/workbook.xml.rels' '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
        $sheet=New-Object Text.StringBuilder
        [void]$sheet.Append('<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="32" customWidth="1"/><col min="2" max="2" width="72" customWidth="1"/><col min="3" max="5" width="20" customWidth="1"/><col min="6" max="7" width="72" customWidth="1"/><col min="8" max="8" width="28" customWidth="1"/></cols><sheetData><row r="1">')
        foreach($header in @('파일명 또는 폴더명','전체 경로','작업','시도 횟수','결과','실패 이유 · 확인 코드','원본 백업','UTC 시각')) { [void]$sheet.Append((Xml-Cell $header)) }
        [void]$sheet.Append('</row>'); $row=1
        foreach($item in $Items) {
            $row++; [void]$sheet.Append('<row r="'+$row+'">')
            $operation=switch($Mode){'Encrypt'{'암호 설정'} 'Decrypt'{'암호 해제'} 'ChangePassword'{'암호 변경'} default{$Mode}}
            $statusName=switch($item.status){'Failed'{'실패'} 'NeedsInspection'{'확인 필요'} 'NotProcessed'{'미처리'} 'Cancelled'{'취소'} 'Skipped'{'건너뜀'} 'Success'{'완료'} default{$item.status}}
            $reason=(Get-BatchReason $item.category)+' ('+$item.category+')'
            if($item.status -eq 'NotProcessed') { $reason='앞선 확인 필요 상태 때문에 처리하지 않았습니다. '+$reason }
            foreach($value in @([IO.Path]::GetFileName($item.path),$item.path,$operation,[string]$item.attempts,$statusName,$reason,$item.backup,$item.time)) { [void]$sheet.Append((Xml-Cell ([string]$value))) }
            [void]$sheet.Append('</row>')
        }
        [void]$sheet.Append('</sheetData><autoFilter ref="A1:H'+$row+'"/></worksheet>')
        Add-ZipText 'xl/worksheets/sheet1.xml' $sheet.ToString()
        $archive.Dispose(); $archive=$null; $stream.Flush($true); $stream.Dispose(); $stream=$null
        [IO.File]::Move($pending,$Path)
    } finally {
        if($null -ne $archive) { $archive.Dispose() }; if($null -ne $stream) { $stream.Dispose() }
        if([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) }
    }
}
try {
    $batchRequest=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($batchRequest.schemaVersion -ne 1 -or $batchRequest.mode -notin @('Encrypt','Decrypt','ChangePassword')) { throw 'InvalidBatchRequest' }
    $ownerValue=Get-BatchValue $batchRequest 'ownerPid'
    if($null -ne $ownerValue) {
        $batchOwnerPid=[int]$ownerValue; $batchOwnerStart=[string](Get-BatchValue $batchRequest 'ownerStartTicks')
        if($batchOwnerPid -lt 1 -or $batchOwnerStart -notmatch '^\d+$') { throw 'InvalidBatchRequest' }
    }
    $batchSession.userOwnerPid=$batchOwnerPid; $batchSession.userOwnerStart=$batchOwnerStart
    $rootPath=[string]$batchRequest.root
    if($rootPath -notmatch '^[A-Za-z]:[\\/]' -or $rootPath.Substring(2).Contains(':')) { throw 'LocalPathRequired' }
    $rootPath=[IO.Path]::GetFullPath($rootPath).TrimEnd('\')
    Assert-OutsideAppData $rootPath
    if(-not [IO.Directory]::Exists($rootPath+'\')) { throw 'DirectoryNotFound' }
    Assert-NoReparse ($rootPath+'\')
    $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($rootPath+'\'))
    if($drive.DriveType -ne [IO.DriveType]::Fixed -or $drive.DriveFormat -ne 'NTFS') { throw 'LocalNtfsRequired' }
    $batchResult.root=$rootPath; $batchResult.mode=$batchRequest.mode
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $plan=New-Object 'System.Collections.Generic.List[object]'
    foreach($entry in @($batchRequest.files)) {
        if($null -eq $entry) { continue }
        $path=Resolve-BatchPath ([string]$entry.path) $rootPath
        Assert-OutsideAppData $path
        if(-not $seen.Add($path)) { throw 'DuplicateBatchPath' }
        $name=[IO.Path]::GetFileName($path)
        if([IO.Path]::GetExtension($path).ToLowerInvariant() -notin @('.xls','.xlsx','.xlsm','.xlsb') -or $name.StartsWith('~$') -or $name.StartsWith('.eps-',[StringComparison]::OrdinalIgnoreCase)) { throw 'UnsupportedBatchPath' }
        $hash=[string](Get-BatchValue $entry 'expectedHash')
        if($hash -and $hash -notmatch '^[0-9a-fA-F]{64}$') { throw 'InvalidSourceHash' }
        $plan.Add([pscustomobject]@{path=$path;expectedHash=$hash})
    }
    $batchEntries=@($plan.ToArray())
    foreach($issue in @(Get-BatchValue $batchRequest 'discoveryIssues')) {
        if($null -eq $issue) { continue }
        $issuePath=Resolve-BatchPath ([string]$issue.path) $rootPath $true
        $batchItems.Add((New-BatchItem $issuePath 'Failed' ([string]$issue.category)))
    }
    if($batchEntries.Count -gt 0) { Assert-Request ([pscustomobject]@{schemaVersion=1;path='';mode=$batchRequest.mode;oldSecret=$batchRequest.oldSecret;newSecret=$batchRequest.newSecret;expectedHash=('0'*64)}) }
    [IO.File]::Delete($RequestPath)
    $batchMutex=New-Object Threading.Mutex($false,(Get-EngineMutexName))
    try { $batchLocked=$batchMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $batchLocked=$true }
    if(-not $batchLocked) { throw 'AnotherOperationRunning' }
    if($batchEntries.Count -gt 0 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'ExistingExcel' }
    for($index=0;$index -lt $batchEntries.Count;$index++) {
        $entry=$batchEntries[$index]
        if(-not $batchStop) { $batchStop=Get-BatchCancellation }
        if($batchStop) {
            $batchItems.Add((New-BatchItem $entry.path 'NotProcessed' $batchStop)); continue
        }
        $item=New-BatchItem $entry.path 'Failed' ''
        $batchItems.Add($item)
        for($attempt=1;$attempt -le 3;$attempt++) {
            $item.attempts=$attempt
            Save-BatchProgress 'Processing' ($index+1) $attempt $entry.path
            $childResult=$null; $attemptDir=''
            try {
                Assert-NotCancelled $batchDir
                if((Get-BatchCancellation) -eq 'OwnerExited') { throw 'OwnerExited' }
                $null=Assert-LocalWorkbook $entry.path
                $currentHash=Get-Sha $entry.path
                if(-not $entry.expectedHash) { $entry.expectedHash=$currentHash }
                if($currentHash -ne $entry.expectedHash) { throw 'SourceChanged' }
                $attemptDir=Join-Path $batchDir ([guid]::NewGuid().ToString('N'))
                [void][IO.Directory]::CreateDirectory($attemptDir); Set-PrivateDirectory $attemptDir
                $item.runDirectory=$attemptDir
                Write-Json @{schemaVersion=1;path=$entry.path;mode=$batchRequest.mode;oldSecret=$batchRequest.oldSecret;newSecret=$batchRequest.newSecret;expectedHash=$entry.expectedHash} (Join-Path $attemptDir 'request.json')
                # Same STA thread: the named mutex is reentrant. Engine releases
                # only its acquisition; the batch retains ownership throughout.
                & (Join-Path $PSScriptRoot 'Engine.ps1') -RequestPath (Join-Path $attemptDir 'request.json') -CancellationPath $batchCancel -WorkerSession $batchSession | Out-Null
                $childPath=Join-Path $attemptDir 'result.json'
                if(-not [IO.File]::Exists($childPath)) { throw 'MissingChildResult' }
                $childResult=Get-Content -LiteralPath $childPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $item.category=[string]$childResult.category; $item.backup=[string]$childResult.backup; $item.status=[string]$childResult.status
                if($item.status -notin @('Success','Skipped','Failed','Cancelled')) { throw 'InvalidChildResult' }
                if((Get-BatchValue $childResult 'message') -eq 'TemporaryCleanupIncomplete') { throw 'TemporaryCleanupIncomplete' }
                if([IO.File]::Exists((Join-Path $attemptDir 'request.json')) -or [IO.File]::Exists((Join-Path $attemptDir 'worker-job.json'))) { throw 'TemporaryCleanupIncomplete' }
                foreach($ownedProperty in @('temp','inputCopy')) {
                    $ownedPath=[string](Get-BatchValue $childResult $ownedProperty)
                    if($ownedPath -and [IO.File]::Exists($ownedPath) -and $item.category -notin @('CommitUncertain','WorkerTimeout','WorkerInterrupted','WorkerCrashed','ExcelStillRunning','WorkerSessionUnsafe')) { throw 'TemporaryCleanupIncomplete' }
                }
                if($item.status -eq 'Skipped' -and $item.category -notin @('AlreadyEncrypted','AlreadyUnencrypted')) { $item.status='Failed' }
            } catch {
                $message=$_.Exception.Message
                $known=@('Cancelled','OwnerExited','SourceChanged','MissingChildResult','InvalidChildResult','TemporaryCleanupIncomplete','ReadOnlyAttribute','OfflineFileUnsupported','FileInUse','FileNotFound','LocalPathRequired','LocalNtfsRequired','UnsupportedExtension','TemporaryFileNotSupported')
                $item.category=if($message -in $known){$message}elseif($message -like 'ReparsePoint:*'){'ReparsePoint'}else{Get-Category $_ 'Batch'}
                if($attemptDir -and $null -eq $childResult -and $item.category -notin @('Cancelled','SourceChanged')) { $item.category='MissingChildResult' }
                $item.status=if($item.category -in @('Cancelled','OwnerExited')){'Cancelled'}else{'Failed'}
            } finally {
                if($attemptDir) {
                    $secret=Join-Path $attemptDir 'request.json'
                    if([IO.File]::Exists($secret)) { try { [IO.File]::Delete($secret) } catch { $item.status='Failed'; $item.category='TemporaryCleanupIncomplete' } }
                }
                $item.time=[DateTime]::UtcNow.ToString('o')
            }
            if($item.status -in @('Success','Skipped')) { break }
            if($item.status -eq 'Cancelled') { $batchStop=$item.category; break }
            $unsafe=@('CommitUncertain','SourceChanged','WorkerTimeout','WorkerInterrupted','WorkerCrashed','ExcelStillRunning','WorkerSessionUnsafe','ExistingExcel','ExcelOwnershipOrExistingProcess','MissingChildResult','InvalidChildResult','TemporaryCleanupIncomplete','BackupChanged','TempChanged','SnapshotChanged')
            if($item.category -in $unsafe) { $item.status='NeedsInspection'; $batchStop=$item.category; break }
            $retry=@('OpenFailedPossiblePasswordOrCorruption','FileInUse','ReadOnlyAttribute','AccessDenied','ComServerError','ValidationFailed','FileNotFound','BatchFailed','PreflightFailed','BackupFailed','ComCleanupFailed','SaveAsFailed','ComStartFailed','CommitFailed')
            if($attempt -eq 3 -or $item.category -notin $retry) { break }
            for($wait=0;$wait -lt 4;$wait++) { if(Get-BatchCancellation) { break }; Start-Sleep -Milliseconds 125 }
            $cancelReason=Get-BatchCancellation
            if($cancelReason) { $item.status='Cancelled'; $item.category=$cancelReason; $batchStop=$cancelReason; break }
        }
        Write-Json @{schemaVersion=1;root=$batchResult.root;mode=$batchResult.mode;items=$batchItems.ToArray()} (Join-Path $batchDir 'items.json')
    }
    $batchResult.category=if($batchStop){$batchStop}else{'Completed'}
} catch {
    $batchResult.category=$_.Exception.Message
    if($batchResult.category -notin @('AnotherOperationRunning','ExistingExcel','InvalidBatchRequest','InvalidBatchPath','PathOutsideRoot','DuplicateBatchPath','UnsupportedBatchPath','InvalidSourceHash','CurrentPasswordRequired','NewPasswordLength','PasswordUnchanged','LocalPathRequired','LocalNtfsRequired','DirectoryNotFound','AppDataExcluded')) { $batchResult.category='BatchFailed' }
    $done=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $batchItems) { [void]$done.Add($item.path) }
    foreach($entry in $batchEntries) { if(-not $done.Contains($entry.path)) { $batchItems.Add((New-BatchItem $entry.path 'NotProcessed' $batchResult.category)) } }
} finally {
    if($null -ne $batchSession.process) {
        $sessionError=''
        try {
            [IO.File]::WriteAllText((Join-Path $batchSession.directory 'stop'),'stop')
            if(-not $batchSession.process.WaitForExit(30000)) {
                # This is our PowerShell child only; never terminate Excel.
                $batchSession.process.Kill(); [void]$batchSession.process.WaitForExit(5000)
                throw 'WorkerSessionUnsafe'
            }
            $finishedPath=Join-Path $batchSession.directory 'finished.json'
            if(-not [IO.File]::Exists($finishedPath)) { throw 'WorkerSessionUnsafe' }
            $finished=Get-Content -LiteralPath $finishedPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if($finished.sessionToken -cne $batchSession.token -or $finished.status -ne 'Stopped' -or $finished.workbooksClosed -ne $true -or $finished.excelExited -ne $true) { throw 'WorkerSessionUnsafe' }
            if($batchSession.excelPid -gt 0 -and ($finished.excelPid -ne $batchSession.excelPid -or [string]$finished.excelStartTicks -cne $batchSession.excelStartTicks -or (Test-ProcessIdentity $batchSession.excelPid $batchSession.excelStartTicks))) { throw 'WorkerSessionUnsafe' }
        } catch { $sessionError='WorkerSessionUnsafe' }
        finally { $batchSession.process.Dispose() }
        if($sessionError) {
            $batchResult.category=$sessionError
            $sessionItem=New-BatchItem $(if($batchResult.root){$batchResult.root}else{$batchDir}) 'NeedsInspection' $sessionError
            $sessionItem.runDirectory=$batchSession.directory; $batchItems.Add($sessionItem)
        }
    }
    try {
        if([IO.File]::Exists($RequestPath)) { [IO.File]::Delete($RequestPath) }
    } catch {
        $batchResult.category='TemporaryCleanupIncomplete'
        $cleanupItem=New-BatchItem $(if($batchResult.root){$batchResult.root}else{$batchDir}) 'NeedsInspection' 'TemporaryCleanupIncomplete'
        $cleanupItem.runDirectory=$batchDir; $batchItems.Add($cleanupItem)
    } finally {
        $batchRequest=$null
        if($null -ne $batchMutex) { try { if($batchLocked) { $batchMutex.ReleaseMutex() } } finally { $batchMutex.Dispose() } }
    }
    $batchResult.items=@($batchItems.ToArray())
    $batchResult.failureCount=@($batchItems | Where-Object { $_.status -in @('Failed','NeedsInspection') }).Count
    $batchResult.succeededCount=@($batchItems | Where-Object { $_.status -eq 'Success' }).Count
    $batchResult.skippedCount=@($batchItems | Where-Object { $_.status -eq 'Skipped' }).Count
    $batchResult.notProcessedCount=@($batchItems | Where-Object { $_.status -eq 'NotProcessed' }).Count
    $batchResult.cancelledCount=@($batchItems | Where-Object { $_.status -eq 'Cancelled' }).Count
    if($batchResult.failureCount -gt 0 -or ($batchResult.notProcessedCount -gt 0 -and $batchStop -notin @('Cancelled','OwnerExited'))) {
        $batchResult.status=if($batchResult.succeededCount -gt 0 -or $batchResult.skippedCount -gt 0){'PartialFailure'}else{'Failed'}
        try {
            $report=Join-Path $batchDir 'failure-report.xlsx'
            Write-BatchFailureReport @($batchItems | Where-Object { $_.status -in @('Failed','NeedsInspection','NotProcessed') }) $report $batchResult.mode
            $batchResult.reportPath=$report
        } catch { $batchResult.status='Failed'; $batchResult.category='FailureReportFailed'; $batchResult.reportPath='' }
    } elseif($batchStop -in @('Cancelled','OwnerExited')) { $batchResult.status='Cancelled' }
    elseif($batchResult.category -eq 'Completed') { $batchResult.status='Success' }
    else { $batchResult.status='Failed' }
    $batchResult.time=[DateTime]::UtcNow.ToString('o')
    Write-Json $batchResult $batchResultPath
}
if($batchResult.status -eq 'Success') { exit 0 }
if($batchResult.status -eq 'Cancelled') { exit 2 }
exit 1
