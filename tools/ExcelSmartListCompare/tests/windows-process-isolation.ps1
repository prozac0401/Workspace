[CmdletBinding()]
param([Parameter(Mandatory=$true)][int]$FirstPid,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$AddinPath=(Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare\ExcelSmartListCompare.xlam'),[long]$FirstStartTicks=0)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/windows-e2e'))+'\'
if(-not $output.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a new directory under test artifacts.'}
$first=Get-Process -Id $FirstPid
if($first.ProcessName -ne 'EXCEL'){throw 'First process is not Excel'}
$firstStarted=$first.StartTime
if($FirstStartTicks -ne 0 -and $firstStarted.ToUniversalTime().Ticks -ne $FirstStartTicks){throw 'First process identity changed; no workbook changes.'}
[void](New-Item -ItemType Directory -Path $output)
Add-Type 'using System;using System.Runtime.InteropServices;public class SlcIsolationOwner { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p); }'
$record=[ordered]@{status='STARTED';firstPid=$FirstPid;firstStarted=$firstStarted.ToString('o');started=(Get-Date).ToString('o');checks=@()}
$e=$null;$book=$null;$result=$null;$addin=$null;$secondPid=0
$firstExcel=$null;$firstBook=$null;$firstResult=$null
$firstOwned=[Collections.Generic.List[object]]::new();$secondOwned=[Collections.Generic.List[object]]::new()
$firstAddin=$null;$secondOwnedProcess=$false;$secondStartTicks=0L
$addinPath=[IO.Path]::GetFullPath($AddinPath)
if(-not(Test-Path -LiteralPath $addinPath -PathType Leaf)){throw 'Exact installed add-in was not found.'}
function Release-Com($v){if($null -ne $v -and [Runtime.InteropServices.Marshal]::IsComObject($v)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($v)}}
function Check($name,$passed){$record.checks+=@{name=$name;passed=[bool]$passed};if(-not $passed){throw $name}}
function Get-KnownBookSnapshot($application,$knownBooks){
 $snapshot=[Collections.Generic.List[object]]::new()
 for($i=1;$i -le [int]$application.Workbooks.Count;$i++){
  $current=$application.Workbooks.Item($i)
  $recognized=$false
  foreach($known in $knownBooks){if([object]::ReferenceEquals($current,$known)){$recognized=$true;break}}
  if(-not $recognized -and [bool]$current.IsAddin -and [IO.Path]::GetFullPath([string]$current.FullName) -ieq $addinPath){$recognized=$true}
  if(-not $recognized){throw 'Unexpected workbook; preserving it and stopping isolation test.'}
  $snapshot.Add([pscustomobject]@{name=[string]$current.Name;fullName=[string]$current.FullName})
  $current=$null
 }
 return $snapshot.ToArray()
}
function Get-VerifiedIsolationResult($application,[object[]]$before){
 $after=[Collections.Generic.List[object]]::new()
 for($i=1;$i -le [int]$application.Workbooks.Count;$i++){
  $current=$application.Workbooks.Item($i)
  $after.Add([pscustomobject]@{name=[string]$current.Name;fullName=[string]$current.FullName});$current=$null
 }
 if($after.Count -ne $before.Count+1){throw 'Expected exactly one additional result; preserving unrecognized workbooks.'}
 foreach($entry in $before){if(@($after|Where-Object{$_.name -ceq $entry.name -and $_.fullName -ceq $entry.fullName}).Count -ne 1){throw 'Known workbook changed or disappeared.'}}
 $names=@($before|ForEach-Object{$_.name});$added=@($after|Where-Object{$names -cnotcontains $_.name})
 if($added.Count -ne 1){throw 'Ambiguous additional workbook; preserving it.'}
 $candidate=$application.ActiveWorkbook
 if([string]$candidate.Name -cne $added[0].name -or [string]$candidate.FullName -cne $added[0].fullName -or [string]$candidate.Path -cne '' -or [bool]$candidate.Saved){throw 'Active workbook is not the new unsaved result.'}
 if([int]$candidate.Sheets.Count -ne 1 -or [int]$candidate.Worksheets.Count -ne 1){throw 'Unexpected result workbook shape.'}
 $tab=$candidate.Worksheets.Item(1);$title=$tab.Range('A1')
 if([string]$tab.Name -cne '명단비교_결과' -or [string]$title.Value2 -cne '명단 비교 결과'){throw 'Unexpected result sheet or title; preserving it.'}
 $title=$null;$tab=$null
 return ,$candidate
}
try{
 $firstExcel=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application');[uint32]$firstOwner=0
 [void][SlcIsolationOwner]::GetWindowThreadProcessId([IntPtr]$firstExcel.Hwnd,[ref]$firstOwner)
 if($firstOwner -ne $FirstPid){throw 'ROT returned another first process; no workbook changes.'}
 $firstAddin=$firstExcel.Workbooks.Item('ExcelSmartListCompare.xlam')
 if([IO.Path]::GetFullPath([string]$firstAddin.FullName) -ine $addinPath -or -not [bool]$firstAddin.IsAddin){throw 'First process loaded a different add-in.'}
 $q="'ExcelSmartListCompare.xlam'!";$null=@(Get-KnownBookSnapshot $firstExcel $firstOwned);$null=$firstExcel.Run($q+'SLC_Clear')
 $null=@(Get-KnownBookSnapshot $firstExcel $firstOwned)
 $firstBook=$firstExcel.Workbooks.Add(-4167);$firstOwned.Add($firstBook);$firstSheet=$firstBook.Worksheets.Item(1)
 $firstSheet.Range('A1:A3').Value2='first-only';$firstSheet.Range('B1:B4').Value2='other'
 $firstSheet.Range('A1:A3').Select();$null=@(Get-KnownBookSnapshot $firstExcel $firstOwned);$null=$firstExcel.Run($q+'SLC_Run')
 $firstCaption=[string]$firstExcel.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(2).Caption
 Check 'first process captured three-item snapshot' ($firstCaption.Contains('3개 항목'))
 $priorPids=@(Get-Process EXCEL -ErrorAction SilentlyContinue|ForEach-Object Id)
 $e=New-Object -ComObject Excel.Application;[uint32]$secondPid=0;[void][SlcIsolationOwner]::GetWindowThreadProcessId([IntPtr]$e.Hwnd,[ref]$secondPid)
 if($secondPid -eq 0 -or $priorPids -contains $secondPid){$e=$null;throw 'COM did not return a new Excel; no workbooks modified.'}
 $secondStartTicks=(Get-Process -Id $secondPid).StartTime.ToUniversalTime().Ticks;$secondOwnedProcess=$true
 $record['secondPid']=$secondPid;$record['secondStarted']=(Get-Process -Id $secondPid).StartTime.ToString('o')
 $e.Visible=$false;$e.AutomationSecurity=2
 $null=@(Get-KnownBookSnapshot $e $secondOwned)
 $addin=$e.Workbooks.Open($addinPath,0,$true)
 if([IO.Path]::GetFullPath([string]$addin.FullName) -ine $addinPath -or -not [bool]$addin.IsAddin){throw 'Second process loaded a different add-in.'}
 $secondOwned.Add($addin)
 $q="'ExcelSmartListCompare.xlam'!";$null=$e.Run($q+'SLC_AttachUI')
 $before=[string]$e.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(2).Caption
 $record['initialCaption']=$before
 Check 'second process starts without first snapshot' ($before -ceq '')
 $null=@(Get-KnownBookSnapshot $e $secondOwned)
 $book=$e.Workbooks.Add(-4167);$secondOwned.Add($book);$sheet=$book.Worksheets.Item(1);$sheet.Range('A1:A2').Value2='apple';$sheet.Range('B1:B3').Value2='pear'
 $sheet.Range('A1:A2').Select();$null=@(Get-KnownBookSnapshot $e $secondOwned);$null=$e.Run($q+'SLC_Run')
 $after=[string]$e.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(2).Caption;$record['capturedCaption']=$after
 Check 'second process owns its two-item snapshot' ($after.Contains('2개 항목'))
 $sheet.Range('B1:B3').Select();$beforeSecond=@(Get-KnownBookSnapshot $e $secondOwned);$null=$e.Run($q+'SLC_Run');$result=Get-VerifiedIsolationResult $e $beforeSecond;$secondOwned.Add($result)
 $summary=[string]$result.Worksheets.Item(1).Range('B4').Value2;$record['summary']=$summary
 Check 'second process comparison uses only its own snapshot' ($summary -ceq '첫 번째 목록: 2개 항목 / 두 번째 목록: 3개 항목 / 일치 0개 / 첫 번째 목록 남은 항목 2개 / 두 번째 목록 남은 항목 3개')
 $file=Join-Path $output 'Second-Process-Result.xlsx';$null=$result.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$result,@([string]$file,[int]51))
 Check 'first process remains running with same identity' ((Get-Process -Id $FirstPid).StartTime -eq $firstStarted)
 Check 'first process snapshot caption unchanged' ([string]$firstExcel.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(2).Caption -ceq $firstCaption)
 $firstBook.Activate();$firstSheet.Range('B1:B4').Select();$beforeFirst=@(Get-KnownBookSnapshot $firstExcel $firstOwned);$null=$firstExcel.Run($q+'SLC_Run');$firstResult=Get-VerifiedIsolationResult $firstExcel $beforeFirst;$firstOwned.Add($firstResult)
 Check 'first process still compares its own snapshot' ([string]$firstResult.Worksheets.Item(1).Range('B4').Value2 -ceq '첫 번째 목록: 3개 항목 / 두 번째 목록: 4개 항목 / 일치 0개 / 첫 번째 목록 남은 항목 3개 / 두 번째 목록 남은 항목 4개')
 $record.status='PASS'
}catch{$record.status='FAIL';$record['error']=$_.Exception.Message;throw}
finally{
 $cleanupErrors=[Collections.Generic.List[string]]::new()
 foreach($ownedList in @($firstOwned,$secondOwned)){
  for($i=$ownedList.Count-1;$i -ge 0;$i--){$ownedBook=$ownedList[$i];try{$ownedBook.Close($false)}catch{$cleanupErrors.Add($_.Exception.Message)}finally{Release-Com $ownedBook}}
 }
 if($null -ne $e -and $secondOwnedProcess){
  try{
   $process=Get-Process -Id $secondPid -ErrorAction Stop
   if($process.StartTime.ToUniversalTime().Ticks -ne $secondStartTicks){throw 'Second process identity changed; Quit refused.'}
   if([int]$e.Workbooks.Count -ne 0){throw 'Unexpected workbook remains in second Excel; Quit refused.'}
   $e.Quit()
  }catch{$cleanupErrors.Add($_.Exception.Message)}
 }
 # Do not FinalRelease borrowed workbook aliases; only owned roots above are closed.
 $sheet=$null;$firstSheet=$null;$result=$null;$book=$null;$addin=$null;$firstResult=$null;$firstBook=$null
 Release-Com $firstAddin;Release-Com $e;Release-Com $firstExcel
 [GC]::Collect();[GC]::WaitForPendingFinalizers()
 if($secondOwnedProcess){
  $timer=[Diagnostics.Stopwatch]::StartNew();$stillOwned=$false
  do{$process=Get-Process -Id $secondPid -ErrorAction SilentlyContinue;$stillOwned=$null -ne $process -and $process.StartTime.ToUniversalTime().Ticks -eq $secondStartTicks;if(-not $stillOwned){break};Start-Sleep -Milliseconds 100}while($timer.Elapsed.TotalSeconds -lt 15)
  $record['secondOwnedExcelExited']=(-not $stillOwned)
  if($stillOwned){$cleanupErrors.Add('Owned second Excel remains after normal Quit; no process was killed.')}
 }
 $record['cleanupErrors']=$cleanupErrors.ToArray();if($cleanupErrors.Count){$record.status='FAIL'}
 $record['finished']=(Get-Date).ToString('o');$record|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
}
if($record.status -ne 'PASS'){exit 1}
