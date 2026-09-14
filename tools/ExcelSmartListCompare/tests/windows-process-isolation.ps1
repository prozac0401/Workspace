[CmdletBinding()]
param([Parameter(Mandatory=$true)][int]$FirstPid,[Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
$allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/windows-e2e'))+'\'
if(-not $output.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a new directory under test artifacts.'}
$first=Get-Process -Id $FirstPid
if($first.ProcessName -ne 'EXCEL'){throw 'First process is not Excel'}
$firstStarted=$first.StartTime
[void](New-Item -ItemType Directory -Path $output)
Add-Type 'using System;using System.Runtime.InteropServices;public class SlcIsolationOwner { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p); }'
$record=[ordered]@{status='STARTED';firstPid=$FirstPid;firstStarted=$firstStarted.ToString('o');started=(Get-Date).ToString('o');checks=@()}
$e=$null;$book=$null;$result=$null;$addin=$null;$secondPid=0
$firstExcel=$null;$firstBook=$null;$firstResult=$null
function Release-Com($v){if($null -ne $v -and [Runtime.InteropServices.Marshal]::IsComObject($v)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($v)}}
function Check($name,$passed){$record.checks+=@{name=$name;passed=[bool]$passed};if(-not $passed){throw $name}}
try{
 $firstExcel=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application');[uint32]$firstOwner=0
 [void][SlcIsolationOwner]::GetWindowThreadProcessId([IntPtr]$firstExcel.Hwnd,[ref]$firstOwner)
 if($firstOwner -ne $FirstPid){throw 'ROT returned another first process; no workbook changes.'}
 $q="'ExcelSmartListCompare.xlam'!";$null=$firstExcel.Run($q+'SLC_Clear')
 $firstBook=$firstExcel.Workbooks.Add(-4167);$firstSheet=$firstBook.Worksheets.Item(1)
 $firstSheet.Range('A1:A3').Value2='first-only';$firstSheet.Range('B1:B4').Value2='other'
 $firstSheet.Range('A1:A3').Select();$null=$firstExcel.Run($q+'SLC_Run')
 $firstCaption=[string]$firstExcel.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(1).Caption
 Check 'first process captured three-item snapshot' ($firstCaption.Contains('3건'))
 $e=New-Object -ComObject Excel.Application;[uint32]$secondPid=0;[void][SlcIsolationOwner]::GetWindowThreadProcessId([IntPtr]$e.Hwnd,[ref]$secondPid)
 if($secondPid -eq $FirstPid){$e=$null;throw 'COM returned first Excel; no workbooks modified.'}
 $record['secondPid']=$secondPid;$record['secondStarted']=(Get-Process -Id $secondPid).StartTime.ToString('o')
 $e.Visible=$false;$e.AutomationSecurity=2
 $addinPath=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare\ExcelSmartListCompare.xlam'))
 if(-not (Test-Path -LiteralPath $addinPath -PathType Leaf)){throw 'Installed add-in was not found.'}
 $addin=$e.Workbooks.Open($addinPath,0,$true)
 $q="'ExcelSmartListCompare.xlam'!";$null=$e.Run($q+'SLC_AttachUI')
 $before=[string]$e.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(1).Caption
 $record['initialCaption']=$before
 Check 'second process starts without first snapshot' (-not $before.Contains('건'))
 $book=$e.Workbooks.Add(-4167);$sheet=$book.Worksheets.Item(1);$sheet.Range('A1:A2').Value2='apple';$sheet.Range('B1:B3').Value2='pear'
 $sheet.Range('A1:A2').Select();$null=$e.Run($q+'SLC_Run')
 $after=[string]$e.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(1).Caption;$record['capturedCaption']=$after
 Check 'second process owns its two-item snapshot' ($after.Contains('2건'))
 $sheet.Range('B1:B3').Select();$null=$e.Run($q+'SLC_Run');$result=$e.ActiveWorkbook
 $summary=[string]$result.Worksheets.Item(1).Range('B4').Value2;$record['summary']=$summary
 Check 'second process comparison uses only its own snapshot' ($summary -ceq 'A 2 / B 3 / 일치 0 / A 잔여 2 / B 잔여 3')
 $file=Join-Path $output 'Second-Process-Result.xlsx';$null=$result.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$result,@([string]$file,[int]51))
 Check 'first process remains running with same identity' ((Get-Process -Id $FirstPid).StartTime -eq $firstStarted)
 Check 'first process snapshot caption unchanged' ([string]$firstExcel.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(1).Caption -ceq $firstCaption)
 $firstBook.Activate();$firstSheet.Range('B1:B4').Select();$null=$firstExcel.Run($q+'SLC_Run');$firstResult=$firstExcel.ActiveWorkbook
 Check 'first process still compares its own snapshot' ([string]$firstResult.Worksheets.Item(1).Range('B4').Value2 -ceq 'A 3 / B 4 / 일치 0 / A 잔여 3 / B 잔여 4')
 $record.status='PASS'
}catch{$record.status='FAIL';$record['error']=$_.Exception.Message;throw}
finally{
 if($null -ne $firstResult){$firstResult.Close($false)}
 if($null -ne $firstBook){$firstBook.Close($false)}
 if($null -ne $result){$result.Close($false)}
 if($null -ne $book){$book.Close($false)}
 if($null -ne $e){$e.Quit()}
 foreach($v in @($result,$book,$addin,$e,$firstResult,$firstBook,$firstExcel)){Release-Com $v}
 [GC]::Collect();[GC]::WaitForPendingFinalizers()
 $record['finished']=(Get-Date).ToString('o');$record|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
}
