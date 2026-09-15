[CmdletBinding()]
param([Parameter(Mandatory=$true)][int]$OwnedPid,[Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $output -Force)
Add-Type 'using System;using System.Runtime.InteropServices;public class SlcWarningOwner { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p); }'
$e=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application');[uint32]$p=0;[void][SlcWarningOwner]::GetWindowThreadProcessId([IntPtr]$e.Hwnd,[ref]$p)
if($p -ne $OwnedPid){throw 'Different Excel; no changes.'}
$q="'ExcelSmartListCompare.xlam'!"
$null=$e.Run($q+'SLC_Clear')
$book=$e.Workbooks.Add(-4167);$sheet=$book.Worksheets.Item(1);$sheet.Name='SyntheticWarnings'
$sheet.Range('A1:A20000').Value2='candidate'
$sheet.Range('H1:H2').Value2='alpha';$sheet.Range('H3').Value2='beta'
$sheet.Range('J1:K1').Merge();$sheet.Range('J1').Value2='merged'
$sheet.Range('G1').Value2=('x'*4097)
$path=Join-Path $output 'Warning-Fixture.xlsx'
if(Test-Path -LiteralPath $path){throw 'Existing fixture preserved.'}
$null=$book.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$book,@([string]$path,[int]51))
$sheet.Range('H1:H3').Select();$null=$e.Run($q+'SLC_Run')
$caption=[string]$e.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(2).Caption
$settings=@($e.ScreenUpdating,$e.EnableEvents,$e.Interactive,$e.EnableCancelKey)
$results=[Collections.Generic.List[object]]::new()
foreach($case in @(@('WARN-20000-NO','A1:A20000'),@('EMPTY-B-PRESERVED','F1:F3'),@('MERGED-B-PRESERVED','J1:K1'),@('TEXT-4097-PRESERVED','G1'))){
    $sheet.Range($case[1]).Select()
    Write-Host ('WAITING_FOR_NATIVE_DIALOG '+$case[0])
    $null=$e.Run($q+'SLC_Run')
    $after=[string]$e.CommandBars.Item('SLC_68A45C44_Toolbar').Controls.Item(2).Caption
    $actualSettings=@($e.ScreenUpdating,$e.EnableEvents,$e.Interactive,$e.EnableCancelKey)
    $passed=($after -eq $caption -and ($settings -join ',') -eq ($actualSettings -join ','))
    $results.Add([ordered]@{id=$case[0];status=if($passed){'PASS'}else{'FAIL'};pendingCaption=$after;settingsRestored=(($settings -join ',') -eq ($actualSettings -join ','))})
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'warning-cases.json') -Encoding UTF8
    if(-not $passed){throw 'Snapshot or settings were not preserved.'}
}
$sheet.Range('H1:H3').Select();$null=$e.Run($q+'SLC_Run')
$result=$e.ActiveWorkbook;$rs=$result.Worksheets.Item(1)
$summary=[string]$rs.Range('B4').Value2
$passed=($summary -eq '첫 번째 목록: 3개 항목 / 두 번째 목록: 3개 항목 / 일치 3개 / 첫 번째 목록 잔여 0개 / 두 번째 목록 잔여 0개')
$resultPath=Join-Path $output 'preserved-snapshot-result.xlsx'
$null=$result.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$result,@([string]$resultPath,[int]51))
$results.Add([ordered]@{id='PRESERVED-SNAPSHOT-COMPARE';status=if($passed){'PASS'}else{'FAIL'};summary=$summary})
$result.Close($false)
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'warning-cases.json') -Encoding UTF8
$sheet.Activate();$sheet.Range('H1:H3').Select();$null=$e.Run($q+'SLC_Run')
# Keep this owned instance and its 3-item snapshot open for the process-boundary UI test.
foreach($v in @($rs,$result,$sheet,$book,$e)){if([Runtime.InteropServices.Marshal]::IsComObject($v)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($v)}}
if(-not $passed){exit 1}
