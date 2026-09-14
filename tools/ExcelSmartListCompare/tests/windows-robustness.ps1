[CmdletBinding()]
param([Parameter(Mandatory=$true)][int]$OwnedPid,
 [Parameter(Mandatory=$true)][ValidateSet('Visible19999','Visible20000No','Combined20000No','Visible100000','Visible100001','Areas500No','Areas5001','Scan200000No','Scan2000001','Item4096','Item4097','Chars5000000','Chars5000001','Worst100k','Worst100kTimeout','LargeCancel','Repeated50')][string]$Case,
 [Parameter(Mandatory=$true)][string]$OutputDirectory)
# Run from Windows PowerShell 5.1 STA against an explicitly owned, normally started Excel.
# Native warnings are observed and answered by the operator; never suppressed here.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
$evidenceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/windows-e2e'))+'\'
if(-not $output.StartsWith($evidenceRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Use the tool artifacts/windows-e2e subtree.'}
if(Test-Path -LiteralPath $output){throw 'Use a fresh case evidence directory.'}
[void](New-Item -ItemType Directory -Path $output)
Add-Type 'using System;using System.Runtime.InteropServices;public class SlcRobustOwner { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p); }'
$e=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application');[uint32]$owner=0
[void][SlcRobustOwner]::GetWindowThreadProcessId([IntPtr]$e.Hwnd,[ref]$owner)
if($owner -ne $OwnedPid){throw 'Different Excel; no workbook changes.'}
$q="'ExcelSmartListCompare.xlam'!"
$record=[ordered]@{id=$Case;status='STARTED';pid=$OwnedPid;started=(Get-Date).ToString('o');phase='prepare';checks=@()}
$books=[Collections.Generic.List[object]]::new()
function Release-Com($v){if($null -ne $v -and [Runtime.InteropServices.Marshal]::IsComObject($v)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($v)}}
function Evidence { $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8 }
function Check([string]$name,[bool]$passed){$record.checks+=@{name=$name;passed=$passed};Evidence;if(-not $passed){throw $name}}
function Caption {return [string]$e.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(1).Caption}
function Settings {return (@($e.ScreenUpdating,$e.EnableEvents,$e.Interactive,$e.EnableCancelKey,$e.Calculation) -join ',')}
function Shared-Hash([string]$path){$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$sha=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($sha.ComputeHash($stream))}finally{$sha.Dispose();$stream.Dispose()}}
function Run([string]$phase){$record.phase=$phase;Evidence;Write-Host ('RUN '+$Case+' '+$phase);$null=$e.Run($q+'SLC_Run')}
function FillUnique($sheet,[string]$prefix,[int]$count){
 # Excel calculates deterministic synthetic values; no clipboard or array marshaling.
 $range=$sheet.Range('A1:A'+$count)
 try{
  $range.FormulaR1C1='="'+$prefix+'"&TEXT(ROW()-1,"000000")';$range.Calculate()
  if([string]$sheet.Range('A1').Value2 -cne ($prefix+'000000') -or [string]$sheet.Range('A'+$count).Value2 -cne ($prefix+($count-1).ToString('D6'))){throw 'Synthetic unique values were not generated correctly.'}
 }finally{Release-Com $range}
}
function Areas($sheet,[int]$count){
 $result=$null
 for($i=0;$i -lt $count;$i+=20){$addresses=@();for($j=$i;$j -lt [Math]::Min($i+20,$count);$j++){$addresses+='A'+(2*$j+1)};$part=$sheet.Range(($addresses -join ','));$part.Value2='fragment';if($null -eq $result){$result=$part}else{$old=$result;$result=$e.Union($old,$part);Release-Com $old;Release-Com $part}}
 return ,$result
}
try {
 $null=$e.Run($q+'SLC_Clear')
 $book=$e.Workbooks.Add(-4167);$books.Add($book);$a=$book.Worksheets.Item(1);$a.Name='SyntheticA';$b=$book.Worksheets.Add();$b.Name='SyntheticB'
 $a.Range('H1:H2').Value2='alpha';$a.Range('H3').Value2='beta';$b.Range('H1').Value2='alpha';$b.Range('H2').Value2='beta';$b.Range('H3').Value2='gamma'
 $base=$a.Range('H1:H3');$selected=$b.Range('H1:H3');$mode='reject';$expected='';$count=0
 switch($Case){
  'Visible19999' {$mode='capture';$count=19999;$a.Range('A1:A19999').Value2='candidate';$selected=$a.Range('A1:A19999')}
  'Visible20000No' {$b.Range('A1:A20000').Value2='candidate';$selected=$b.Range('A1:A20000')}
  'Combined20000No' {$a.Range('A1:A15000').Value2='baseline';$base=$a.Range('A1:A15000');$b.Range('A1:A5000').Value2='candidate';$selected=$b.Range('A1:A5000')}
  'Visible100000' {$mode='capture';$count=100000;$a.Range('A1:A100000').Value2='candidate';$selected=$a.Range('A1:A100000')}
  'Visible100001' {$b.Range('A1:A100001').Value2='candidate';$selected=$b.Range('A1:A100001')}
  'Areas500No' {$selected=Areas $b 500}
  'Areas5001' {$selected=Areas $b 5001}
  'Scan200000No' {$b.Range('A1').Value2='first';$b.Range('T10000').Value2='last';$selected=$b.Range('A1:T10000')}
  'Scan2000001' {$b.Range('A1').Value2='first';$b.Range('C666667').Value2='last';$selected=$b.Range('A1:C666667')}
  'Item4096' {$mode='result';$b.Range('A1').Value2=('x'*4096);$selected=$b.Range('A1');$expected='A 3 / B 1 / 일치 0 / A 잔여 3 / B 잔여 1'}
  'Item4097' {$b.Range('A1').Value2=('x'*4097);$selected=$b.Range('A1')}
  'Chars5000000' {$mode='result';$b.Range('A1:A1220').Value2=('x'*4096);$b.Range('A1221').Value2=('y'*2880);$selected=$b.Range('A1:A1221');$expected='A 3 / B 1221 / 일치 0 / A 잔여 3 / B 잔여 1221'}
  'Chars5000001' {$b.Range('A1:A1220').Value2=('x'*4096);$b.Range('A1221').Value2=('y'*2881);$selected=$b.Range('A1:A1221')}
  'Worst100k' {$mode='worst';FillUnique $a 'A_' 100000;FillUnique $b 'B_' 100000;$base=$a.Range('A1:A100000');$selected=$b.Range('A1:A100000');$expected='A 100000 / B 100000 / 일치 0 / A 잔여 100000 / B 잔여 100000'}
  'Worst100kTimeout' {$mode='timeout';FillUnique $a 'A_' 100000;FillUnique $b 'B_' 100000;$base=$a.Range('A1:A100000');$selected=$b.Range('A1:A100000')}
  'LargeCancel' {FillUnique $b 'C_' 100000;$selected=$b.Range('A1:A100000')}
  'Repeated50' {$mode='repeat';$expected='A 3 / B 3 / 일치 2 / A 잔여 1 / B 잔여 1'}
 }
 $source=Join-Path $output 'Synthetic-Source.xlsx'
 $null=$book.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$book,@([string]$source,[int]51))
 $hash=Shared-Hash $source
 $record['sourceHashBefore']=$hash
 $initial=Settings;$record['settingsBefore']=$initial;$record['memoryBeforeBytes']=(Get-Process -Id $OwnedPid).PrivateMemorySize64
 $timer=[Diagnostics.Stopwatch]::StartNew()
 if($mode -eq 'repeat'){
  $samples=@();$first=$null
  for($i=0;$i -lt 50;$i++){
   $null=$e.Run($q+'SLC_Clear');$a.Activate();$base.Select();$null=$e.Run($q+'SLC_Run');$b.Activate();$selected.Select();$null=$e.Run($q+'SLC_Run')
   $result=$e.ActiveWorkbook;if([string]$result.Name -eq [string]$book.Name){throw 'Missing repeated result'}
   $rs=$result.Worksheets.Item(1)
   Check ('repeat-'+($i+1)+'-summary-settings') (([string]$rs.Range('B4').Value2 -ceq $expected) -and (Settings) -ceq $initial)
   if($i -eq 0){$first=$result;$books.Add($first);$rs.Range('T1').Value2='USER_EDIT_KEEP'}else{$result.Close($false);Release-Com $result}
   Release-Com $rs
   if(($i+1)%10 -eq 0){$samples+=@{iteration=$i+1;privateBytes=(Get-Process -Id $OwnedPid).PrivateMemorySize64;seconds=$timer.Elapsed.TotalSeconds};Write-Host ('completed '+($i+1))}
  }
  Check 'previous edited result preserved' ([string]$first.Worksheets.Item(1).Range('T1').Value2 -ceq 'USER_EDIT_KEEP');$record['memorySamples']=$samples
 }else{
  if($mode -ne 'capture'){$a.Activate();$base.Select();Run 'capture-baseline'}
  $before=Caption;$book.Activate();$selected.Worksheet.Activate();$selected.Select();$bookCount=$e.Workbooks.Count
  Run 'candidate-selection-native-dialog-if-applicable'
  if($mode -eq 'capture'){Check 'captured exact count' ((Caption).Contains($count.ToString('#,##0')+'건'))}
  elseif($mode -eq 'reject' -or $mode -eq 'timeout'){
   $record['captionBefore']=$before;$record['captionAfter']=Caption
   Check 'baseline preserved' ((Caption) -ceq $before);Check 'no partial result workbook' ($e.Workbooks.Count -eq $bookCount)
   # Demonstrate that the next ordinary comparison still works after rejection.
   if($mode -ne 'timeout' -and $Case -ne 'Combined20000No'){$a.Activate();$base.Select();Run 'compare-preserved-baseline';$result=$e.ActiveWorkbook;$books.Add($result);Check 'preserved baseline compares correctly' ([string]$result.Worksheets.Item(1).Range('B4').Value2 -ceq 'A 3 / B 3 / 일치 3 / A 잔여 0 / B 잔여 0')}
  }else{
   $result=$e.ActiveWorkbook;Check 'new result workbook' ([string]$result.Name -ne [string]$book.Name);$books.Add($result);$rs=$result.Worksheets.Item(1)
   $record['summary']=[string]$rs.Range('B4').Value2;Check 'literal summary' ($record.summary -ceq $expected);Check 'result has no formulas' ($rs.UsedRange.HasFormula -eq $false)
   if($mode -eq 'worst'){Check 'all 200000 difference rows output' ($rs.UsedRange.Rows.Count -eq 200008);Check 'last B value present' ([string]$rs.Range('E200008').Value2 -ceq 'B_099999')}
   if($Case -eq 'Item4096'){Check '4096 characters retained' ([string]$rs.Range('E11').Value2).Length.Equals(4096)}
   $resultFile=Join-Path $output 'Verified-Result.xlsx';$null=$result.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$result,@([string]$resultFile,[int]51));Release-Com $rs
  }
 }
 $record['secondsIncludingOperatorDialogs']=$timer.Elapsed.TotalSeconds;$record['memoryAfterBytes']=(Get-Process -Id $OwnedPid).PrivateMemorySize64
 Check 'Excel settings restored' ((Settings) -ceq $initial)
 Check 'saved source bytes unchanged' ((Shared-Hash $source) -ceq $hash)
 $record.status='PASS'
}catch{$record.status='FAIL';$record['error']=$_.Exception.Message;throw}
finally{
 $record.phase='complete';$record['finished']=(Get-Date).ToString('o');Evidence
 for($i=$books.Count-1;$i -ge 0;$i--){try{$books[$i].Close($false)}finally{Release-Com $books[$i]}}
 foreach($v in @($selected,$base,$a,$b,$e)){Release-Com $v}
 [GC]::Collect();[GC]::WaitForPendingFinalizers()
}
