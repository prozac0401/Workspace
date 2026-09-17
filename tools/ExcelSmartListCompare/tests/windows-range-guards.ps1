[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AddinPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedAddinSha256,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('warning-20000-no','empty-b','merged-b','item-4097','visible-100001','raw-5000001','scan-2000001')][string[]]$Case,
    [string]$ExpectedReleaseVersion='0.2.0-rc.9'
)
# Runs only public macros against saved synthetic fixtures in a new owned Excel.
# Native dialog observation/response belongs to an external bounded controller.
# No VBA injection, security preference changes, input simulation, or forced Quit.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5 -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Use Windows PowerShell 5.1 -STA.'}
$addin=[IO.Path]::GetFullPath($AddinPath)
if(-not (Test-Path -LiteralPath $addin -PathType Leaf) -or [IO.Path]::GetExtension($addin) -ine '.xlam'){throw 'An existing installed XLAM is required.'}
$output=[IO.Path]::GetFullPath($OutputDirectory)
$artifactRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../artifacts'))
if(-not $output.StartsWith($artifactRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh output directory under repository artifacts.'}
$ancestor=Split-Path -Parent $output
while($ancestor){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Evidence paths must not traverse reparse points.'}
    $ancestor=Split-Path -Parent $ancestor
}
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel detected; no application was attached or closed.'}
function Shared-Hash([string]$Path){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()}finally{$stream.Dispose()}
}
$initialAddinHash=Shared-Hash $addin
if($initialAddinHash -cne $ExpectedAddinSha256.ToLowerInvariant()){throw 'Installed add-in hash differs; no Excel was started.'}
[void][IO.Directory]::CreateDirectory($output)
$utf8=New-Object Text.UTF8Encoding($false)
$qualified="'"+([IO.Path]::GetFileName($addin)).Replace("'","''")+"'!"
$sourcePath=Join-Path $output 'Synthetic-Range-Guards.xlsx'
$preservation="`n`n담아 둔 첫 번째 목록과 원본 내용은 바뀌지 않았습니다.`n오류 코드: "
$definitions=@(
    [pscustomobject]@{id='warning-20000-no';range='A1:A20000';mode='RejectLarge';title='명단 비교 - 선택 범위 확인';body="선택한 값을 읽고 결과를 만드는 데 시간이 걸릴 수 있습니다.`n이번에 선택한 범위: 숨기지 않은 셀 20,000개 / 1개 영역`n이번 작업에서 다룰 셀: 20,003개`n이 시험 버전에서는 Esc를 눌러도 작업이 취소되지 않을 수 있습니다.`n계속할까요? 범위를 줄이려면 [아니요]를 누르세요."},
    [pscustomobject]@{id='empty-b';range='F1:F3';mode='DismissResult';title='명단 비교';body="선택한 셀에 비교할 값이 없습니다.`n숨긴 셀, 필터로 가려진 셀, 빈칸, 오류 셀, 표의 제목·합계 셀은 비교에서 뺍니다.`n담아 둔 첫 번째 목록이 있다면 그대로 남아 있습니다."},
    [pscustomobject]@{id='merged-b';range='J1:K1';mode='DismissResult';title='명단 비교';body=('병합된 셀은 비교할 수 없습니다. 병합되지 않은 셀을 선택해 주세요.'+$preservation+'-2147219402')},
    [pscustomobject]@{id='item-4097';range='G1';mode='DismissResult';title='명단 비교';body=('G1 셀의 내용이 4,096자를 넘습니다. 이 셀을 빼고 다시 선택해 주세요.'+$preservation+'-2147219403')},
    [pscustomobject]@{id='visible-100001';range='B1:B100001';mode='DismissResult';title='명단 비교';body=("한 목록에 담을 수 있는 셀은 100,000개까지입니다. 선택 범위를 줄여 주세요.`n빈칸도 이 개수에 포함합니다. 숨긴 셀과 필터로 가려진 셀은 세지 않습니다."+$preservation+'-2147219403')},
    [pscustomobject]@{id='raw-5000001';range='D1:D1221';mode='DismissResult';title='명단 비교';body=('선택한 셀의 내용을 모두 합치면 5,000,000자를 넘습니다. 선택 범위를 줄여 주세요.'+$preservation+'-2147219403')},
    [pscustomobject]@{id='scan-2000001';range='A1:C666667';mode='DismissResult';title='명단 비교';body=("숨김 여부를 확인할 셀이 2,000,000개를 넘습니다.`n행이나 열 전체를 선택했다면 값이 있는 부분만 다시 선택해 주세요."+$preservation+'-2147219403')}
)
if($Case){$definitions=@($definitions | Where-Object {$Case -contains $_.id})}
$checks=[Collections.Generic.List[object]]::new();$cases=[Collections.Generic.List[object]]::new()
$ownedBooks=[Collections.Generic.List[object]]::new();$cleanupErrors=[Collections.Generic.List[string]]::new()
$excel=$null;$addbook=$null;$source=$null;$sheet=$null;$baseline=$null;$selection=$null;$priorResult=$null;$followup=$null
$ownedPid=0;$ownedTicks=0L;$failure=$null;$caseRecord=$null
$report=[ordered]@{
    schemaVersion=1;status='STARTED';phase='preflight';currentCase=$null;owner=$null
    startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null;releaseVersion=$null
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    addinPath=$addin;addinSha256Before=$initialAddinHash;addinSha256After=$null
    sourcePath=$sourcePath;sourceHashBefore=$null;sourceHashAfter=$null;sourceSavedBefore=$null
    previousResultName=$null;previousResultSavedBefore=$null;settingsBefore=$null
    expectedDialogTitle=$null;expectedDialogBody=$null;expectedObserverMode=$null
    cases=@();checks=@();cleanupErrors=@();error=$null;failureStack=$null;ownedExcelExited=$null
    nativeDialogVerified=$false;nativeInputPerformed=$false
    scope='State/result checks only. Combine each case with an exact independent native dialog body and intended button action; completion alone does not prove rejection reason.'
}
function Save-Evidence {
    $report.checks=@($checks.ToArray());$report.cases=@($cases.ToArray());$report.cleanupErrors=@($cleanupErrors.ToArray())
    [IO.File]::WriteAllText((Join-Path $output 'range-guards.json'),($report | ConvertTo-Json -Depth 12),$utf8)
}
function Release-Com($Value){if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)}}
function Check([string]$Id,[bool]$Passed,$Actual,$Expected){
    $checks.Add([pscustomobject][ordered]@{case=$report.currentCase;id=$Id;status=if($Passed){'PASS'}else{'FAIL'};actual=$Actual;expected=$Expected})
    Save-Evidence
    if(-not $Passed){throw ('Assertion failed: '+$Id)}
}
function Cell-Text($Sheet,[string]$Address){$cell=$Sheet.Range($Address);try{return [string]$cell.Value2}finally{Release-Com $cell}}
function Fill-Text([string]$Address,[string]$Value){$range=$sheet.Range($Address);try{$range.NumberFormat='@';$range.Value2=$Value}finally{Release-Com $range}}
function Settings {
    return [ordered]@{screenUpdating=[bool]$excel.ScreenUpdating;enableEvents=[bool]$excel.EnableEvents;interactive=[bool]$excel.Interactive;enableCancelKey=[int]$excel.EnableCancelKey;calculation=[int]$excel.Calculation;displayAlerts=[bool]$excel.DisplayAlerts;automationSecurity=[int]$excel.AutomationSecurity;statusBar=$excel.StatusBar}
}
function Menu {return [string]$excel.Run(($qualified+'SLC_MenuXml'),'Cell')}
function Known-Snapshot {
    $known=@($ownedBooks | ForEach-Object {[pscustomobject]@{name=[string]$_.Name;fullName=[string]$_.FullName}})
    $snapshot=[Collections.Generic.List[object]]::new()
    for($index=1;$index -le [int]$excel.Workbooks.Count;$index++){
        # Borrow collection RCWs; never force-release aliases of owned books.
        $item=$excel.Workbooks.Item($index);$name=[string]$item.Name;$fullName=[string]$item.FullName
        if(@($known | Where-Object {$_.name -ceq $name -and $_.fullName -ceq $fullName}).Count -ne 1){throw 'Unexpected workbook; preserving it and stopping.'}
        $snapshot.Add([pscustomobject]@{name=$name;fullName=$fullName})
    }
    return $snapshot.ToArray()
}
function Own-NewResult([object[]]$Before){
    $after=[Collections.Generic.List[object]]::new()
    for($index=1;$index -le [int]$excel.Workbooks.Count;$index++){$item=$excel.Workbooks.Item($index);$after.Add([pscustomobject]@{name=[string]$item.Name;fullName=[string]$item.FullName})}
    if($after.Count -ne $Before.Count+1){throw 'Expected one additional result workbook; unrecognized books preserved.'}
    foreach($entry in $Before){if(@($after | Where-Object {$_.name -ceq $entry.name -and $_.fullName -ceq $entry.fullName}).Count -ne 1){throw 'Known workbook changed or disappeared.'}}
    $new=@($after | Where-Object {$Before.name -cnotcontains $_.name})
    if($new.Count -ne 1){throw 'New workbook identity is ambiguous.'}
    $candidate=$excel.ActiveWorkbook;$resultSheet=$null
    try{
        if([string]$candidate.Name -cne $new[0].name -or [string]$candidate.FullName -cne $new[0].fullName -or [string]$candidate.Path -cne '' -or [bool]$candidate.Saved){throw 'ActiveWorkbook is not the new unsaved result; preserved.'}
        if([int]$candidate.Sheets.Count -ne 1 -or [int]$candidate.Worksheets.Count -ne 1){throw 'Unexpected result shape; preserved.'}
        $resultSheet=$candidate.Worksheets.Item(1)
        if([string]$resultSheet.Name -cne '명단비교_결과' -or (Cell-Text $resultSheet 'A1') -cne '명단 비교 결과'){throw 'Unknown result title/sheet; preserved.'}
        $ownedBooks.Add($candidate);return ,$candidate
    }finally{Release-Com $resultSheet}
}
function Verify-Result($Book){
    $resultSheet=$Book.Worksheets.Item(1);$used=$null
    try{
        $summary=Cell-Text $resultSheet 'B4'
        $expected='첫 번째 목록: 3개 항목 / 두 번째 목록: 3개 항목 / 일치 3개 / 첫 번째 목록 남은 항목 0개 / 두 번째 목록 남은 항목 0개'
        Check 'baseline-literal-summary' ($summary -ceq $expected) $summary $expected
        $actual=@('A9','B9','C9','D9','E9','F9','G9','H9','I9','J9' | ForEach-Object {Cell-Text $resultSheet $_})
        $expectedRow=@('중복','alpha','alpha','2','alpha','2','0','0','H1','H1')
        Check 'baseline-literal-duplicate-row' (($actual -join '|') -ceq ($expectedRow -join '|')) $actual $expectedRow
        $used=$resultSheet.UsedRange
        Check 'baseline-result-no-formulas' ($used.HasFormula -eq $false) $used.HasFormula $false
        return $summary
    }finally{Release-Com $used;Release-Com $resultSheet}
}
function Verify-Preservation {
    $report.sourceHashAfter=Shared-Hash $sourcePath
    $priorSheet=$priorResult.Worksheets.Item(1)
    try{$sentinel=Cell-Text $priorSheet 'T1'}finally{Release-Com $priorSheet}
    $actualSettings=Settings
    $observations=@(
        @('source-hash',($report.sourceHashAfter -ceq $report.sourceHashBefore),$report.sourceHashAfter,$report.sourceHashBefore),
        @('source-saved',([bool]$source.Saved -eq $report.sourceSavedBefore),[bool]$source.Saved,$report.sourceSavedBefore),
        @('prior-result-sentinel',($sentinel -ceq 'USER_EDIT_SENTINEL'),$sentinel,'USER_EDIT_SENTINEL'),
        @('prior-result-unsaved',([bool]$priorResult.Saved -eq $report.previousResultSavedBefore),[bool]$priorResult.Saved,$report.previousResultSavedBefore),
        @('settings-restored',(($actualSettings | ConvertTo-Json -Compress) -ceq ($report.settingsBefore | ConvertTo-Json -Compress)),$actualSettings,$report.settingsBefore)
    )
    foreach($item in $observations){$checks.Add([pscustomobject][ordered]@{case=$report.currentCase;id=$item[0];status=if($item[1]){'PASS'}else{'FAIL'};actual=$item[2];expected=$item[3]})}
    Save-Evidence
    if(@($checks | Where-Object status -eq 'FAIL').Count){throw 'Preservation check failed.'}
}
function Close-OwnedBook($Book){if($null -ne $Book){$Book.Close($false);[void]$ownedBooks.Remove($Book);Release-Com $Book}}
Save-Evidence
try{
    Add-Type 'using System;using System.Runtime.InteropServices;public static class SlcRangeGuardOwner {[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);}'
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Excel started during preflight; no application created.'}
    $createdUtc=[DateTime]::UtcNow;$excel=New-Object -ComObject Excel.Application
    [uint32]$actualPid=0;[void][SlcRangeGuardOwner]::GetWindowThreadProcessId([IntPtr]$excel.Hwnd,[ref]$actualPid)
    if($actualPid -eq 0){throw 'Excel ownership not established; Quit refused.'}
    $process=Get-Process -Id $actualPid -ErrorAction Stop
    try{
        if($process.ProcessName -ine 'EXCEL' -or $process.StartTime.ToUniversalTime() -lt $createdUtc.AddSeconds(-2)){throw 'Excel predates this test; no application changes made.'}
        $ownedPid=[int]$actualPid;$ownedTicks=$process.StartTime.ToUniversalTime().Ticks
        $report.owner=[ordered]@{pid=$ownedPid;startTicks=$ownedTicks;hwnd=[long]$excel.Hwnd}
    }finally{$process.Dispose()}
    $excel.AutomationSecurity=2;$excel.Visible=$true
    if([int]$excel.Workbooks.Count -eq 1){
        $existing=$excel.Workbooks.Item(1)
        if([IO.Path]::GetFullPath([string]$existing.FullName) -ine $addin -or -not [bool]$existing.IsAddin){throw 'Unexpected auto-opened workbook; preserved.'}
        $addbook=$existing;$ownedBooks.Add($addbook)
    }elseif([int]$excel.Workbooks.Count -eq 0){$addbook=$excel.Workbooks.Open($addin,0,$true);$ownedBooks.Add($addbook)}
    else{throw 'Unexpected auto-opened workbooks; preserved.'}
    Check 'exact-addin-path' ([IO.Path]::GetFullPath([string]$addbook.FullName) -ieq $addin) ([string]$addbook.FullName) $addin
    Check 'exact-addin-hash-after-open' ((Shared-Hash $addin) -ceq $initialAddinHash) (Shared-Hash $addin) $initialAddinHash
    $report.releaseVersion=[string]$excel.Run(($qualified+'SLC_ReleaseVersion'))
    Check 'release-version' ($report.releaseVersion -ceq $ExpectedReleaseVersion) $report.releaseVersion $ExpectedReleaseVersion
    $report.phase='prepare-synthetic-fixtures';Save-Evidence
    $source=$excel.Workbooks.Add(-4167);$ownedBooks.Add($source);$sheet=$source.Worksheets.Item(1);$sheet.Name='SyntheticGuards'
    Fill-Text 'H1:H2' 'alpha';Fill-Text 'H3' 'beta'
    Fill-Text 'A1:A20000' 'candidate';Fill-Text 'B1:B100001' 'candidate';Fill-Text 'G1' ('x'*4097)
    Fill-Text 'D1:D1220' ('x'*4096);Fill-Text 'D1221' ('y'*2881);Fill-Text 'C666667' 'scan-boundary'
    $merge=$sheet.Range('J1:K1');try{$merge.Merge()}finally{Release-Com $merge};Fill-Text 'J1' 'merged'
    Check 'raw-fixture-character-count' ((1220*(Cell-Text $sheet 'D1').Length+(Cell-Text $sheet 'D1221').Length) -eq 5000001) (1220*(Cell-Text $sheet 'D1').Length+(Cell-Text $sheet 'D1221').Length) 5000001
    $null=$source.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$source,@([string]$sourcePath,[int]51))
    $report.sourceHashBefore=Shared-Hash $sourcePath;$report.sourceSavedBefore=[bool]$source.Saved
    Check 'source-saved-before' $report.sourceSavedBefore $report.sourceSavedBefore $true
    $baseline=$sheet.Range('H1:H3');$null=$excel.Run(($qualified+'SLC_Clear'))
    $source.Activate();$baseline.Select();$null=$excel.Run(($qualified+'SLC_Run'))
    $before=@(Known-Snapshot);$null=$excel.Run(($qualified+'SLC_Run'));$priorResult=Own-NewResult $before
    $null=Verify-Result $priorResult
    $priorSheet=$priorResult.Worksheets.Item(1);$sentinel=$null
    try{$sentinel=$priorSheet.Range('T1');$sentinel.Value2='USER_EDIT_SENTINEL'}finally{Release-Com $sentinel;Release-Com $priorSheet}
    $report.previousResultName=[string]$priorResult.Name;$report.previousResultSavedBefore=[bool]$priorResult.Saved
    Check 'prior-result-dirty-before' (-not $report.previousResultSavedBefore) $report.previousResultSavedBefore $false
    foreach($definition in $definitions){
        $report.currentCase=$definition.id;$report.phase='capture-baseline';Save-Evidence
        $source.Activate();$baseline.Select();$null=$excel.Run(($qualified+'SLC_Run'))
        $menuBefore=Menu;Check 'baseline-three-pending' ($menuBefore.Contains('3개 항목') -and $menuBefore.Contains('slc68CellCompare')) $menuBefore 'Three-item pending snapshot'
        # A user-owned status string lets restoration be tested without treating
        # a product's transient pending-count status as an application setting.
        $excel.StatusBar='RANGE_GUARD_EXTERNAL_STATUS';$report.settingsBefore=Settings
        $before=@(Known-Snapshot);$selection=$sheet.Range($definition.range);$selection.Select()
        $caseRecord=[ordered]@{id=$definition.id;range=$definition.range;status='WAITING';menuBefore=$menuBefore;menuAfter=$null;booksBefore=$before.Count;booksAfter=$null;expectedDialogTitle=$definition.title;expectedDialogBody=$definition.body;expectedObserverMode=$definition.mode;macroError=$null;followupSummary=$null;secondsIncludingDialogs=$null}
        $cases.Add($caseRecord)
        $report.expectedDialogTitle=$definition.title;$report.expectedDialogBody=$definition.body;$report.expectedObserverMode=$definition.mode
        $report.phase='waiting-case-operation';Save-Evidence;Write-Host ('WAITING_FOR_NATIVE_DIALOG '+$definition.id+' '+$definition.mode)
        $timer=[Diagnostics.Stopwatch]::StartNew()
        try{$null=$excel.Run(($qualified+'SLC_Run'))}catch{$caseRecord.macroError=$_.Exception.Message;throw}
        finally{$timer.Stop();$caseRecord.secondsIncludingDialogs=$timer.Elapsed.TotalSeconds;Release-Com $selection;$selection=$null}
        $report.phase='case-operation-returned';Save-Evidence
        $caseRecord.menuAfter=Menu;$after=@(Known-Snapshot);$caseRecord.booksAfter=$after.Count
        Check 'pending-menu-unchanged' ($caseRecord.menuAfter -ceq $menuBefore) $caseRecord.menuAfter $menuBefore
        Check 'no-new-workbook-on-rejection' (($after | ConvertTo-Json -Compress) -ceq ($before | ConvertTo-Json -Compress)) $after $before
        Verify-Preservation
        $source.Activate();$baseline.Select();$beforeFollowup=@(Known-Snapshot)
        $report.phase='followup-baseline-comparison';Save-Evidence
        $null=$excel.Run(($qualified+'SLC_Run'));$followup=Own-NewResult $beforeFollowup
        $caseRecord.followupSummary=Verify-Result $followup
        Verify-Preservation
        Check 'comparison-cleared-pending' ((Menu).Contains('slc68CellCapture')) (Menu) 'Capture menu after completed comparison'
        Close-OwnedBook $followup;$followup=$null;$caseRecord.status='STATE_CHECKS_PASS';Save-Evidence
    }
}catch{$failure=$_.Exception.Message;$report.error=$failure;$report.failureStack=$_.ScriptStackTrace;if($null -ne $caseRecord){$caseRecord.status='FAIL'}}
finally{
    $report.phase='cleanup';Save-Evidence
    foreach($value in @($selection,$baseline,$sheet)){try{Release-Com $value}catch{$cleanupErrors.Add($_.Exception.Message)}}
    $selection=$null;$baseline=$null;$sheet=$null
    for($i=$ownedBooks.Count-1;$i -ge 0;$i--){$book=$ownedBooks[$i];try{Close-OwnedBook $book}catch{$cleanupErrors.Add('Owned book cleanup: '+$_.Exception.Message)}}
    $book=$null;$addbook=$null;$source=$null;$priorResult=$null;$followup=$null;$existing=$null
    if($ownedPid -ne 0 -and $null -ne $excel){
        try{
            $process=Get-Process -Id $ownedPid -ErrorAction SilentlyContinue
            if($null -ne $process){
                try{if($process.StartTime.ToUniversalTime().Ticks -ne $ownedTicks){throw 'Excel process identity changed; Quit refused.'}}finally{$process.Dispose()}
                if([int]$excel.Workbooks.Count -ne 0){throw 'Unknown workbook remains; Quit refused.'}
                $excel.Quit()
            }
        }catch{$cleanupErrors.Add($_.Exception.Message)}
    }
    try{Release-Com $excel}catch{$cleanupErrors.Add($_.Exception.Message)}
    $excel=$null;[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    if($ownedPid -ne 0){
        $wait=[Diagnostics.Stopwatch]::StartNew();$same=$true
        do{
            $process=Get-Process -Id $ownedPid -ErrorAction SilentlyContinue;$same=$false
            if($null -ne $process){try{$same=$process.StartTime.ToUniversalTime().Ticks -eq $ownedTicks}finally{$process.Dispose()}}
            if(-not $same){break};Start-Sleep -Milliseconds 100
        }while($wait.Elapsed.TotalSeconds -lt 10)
        $report.ownedExcelExited=-not $same
        if($same){$cleanupErrors.Add('Owned Excel remains after normal Quit; no force termination.')}
    }
    try{
        $report.addinSha256After=Shared-Hash $addin
        if($report.addinSha256After -cne $report.addinSha256Before){$cleanupErrors.Add('Add-in disk hash changed.')}
        if($null -ne $report.sourceHashBefore){$report.sourceHashAfter=Shared-Hash $sourcePath;if($report.sourceHashAfter -cne $report.sourceHashBefore){$cleanupErrors.Add('Source disk hash changed after cleanup.')}}
    }catch{$cleanupErrors.Add('Final hash check: '+$_.Exception.Message)}
    $report.status=if($null -ne $failure -or $cleanupErrors.Count -gt 0 -or $cases.Count -ne $definitions.Count -or @($checks | Where-Object status -eq 'FAIL').Count){'FAIL'}else{'OBSERVED'}
    $report.phase='complete';$report.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-Evidence
}
Write-Output ('Range guards '+$report.status+'; combine state checks with external exact-dialog evidence. '+(Join-Path $output 'range-guards.json'))
if($report.status -eq 'FAIL'){exit 1}
