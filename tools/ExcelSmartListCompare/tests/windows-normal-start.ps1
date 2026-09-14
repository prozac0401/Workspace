[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$FixturePath,[Parameter(Mandatory=$true)][string]$OutputPath,[switch]$ExpectInstalled)
# Observe normal startup only: never opens an XLAM or attaches the product UI.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel; no process changed.'}
$fixture=[IO.Path]::GetFullPath($FixturePath)
if(-not(Test-Path -LiteralPath $fixture -PathType Leaf)){throw 'Synthetic fixture missing.'}
$output=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $output){throw 'Use a fresh evidence filename.'}
[void](New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force)
$pathKey=Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe'
Add-Type 'using System;using System.Runtime.InteropServices;public class SlcNormalOwner { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p); }'
$process=Start-Process -FilePath ([string]$pathKey.GetValue('')) -ArgumentList @('/x',('"'+$fixture+'"')) -WindowStyle Normal -PassThru
$record=[ordered]@{started=(Get-Date).ToString('o');pid=$process.Id;fixture=$fixture;expectedInstalled=[bool]$ExpectInstalled;status='STARTED'}
$record | ConvertTo-Json | Set-Content -LiteralPath $output -Encoding UTF8
Write-Host ('Owned normal Excel PID '+$process.Id)
$excel=$null;$book=$null
function Release-Com($v){if($null -ne $v -and [Runtime.InteropServices.Marshal]::IsComObject($v)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($v)}}
try {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do {try{$excel=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application')}catch{Start-Sleep -Milliseconds 200}}while($null -eq $excel -and $timer.Elapsed.TotalSeconds -lt 30)
    if($null -eq $excel){throw 'New Excel not available within 30 seconds; left for inspection.'}
    [uint32]$owner=0;[void][SlcNormalOwner]::GetWindowThreadProcessId([IntPtr]$excel.Hwnd,[ref]$owner)
    if($owner -ne $process.Id){throw 'Different Excel was returned; no workbook was changed.'}
    $record['hwnd']=$excel.Hwnd
    $record['version']=[string]$excel.Version
    $loaded=$false
    try{$book=$excel.Workbooks.Item('ExcelSmartListCompare.xlam');$loaded=($null -ne $book -and $book.IsAddin)}catch{}
    $record['automaticallyLoaded']=$loaded
    $counts=[ordered]@{}
    foreach($name in @('Cell','Row','Column')){
        $bar=$excel.CommandBars.Item($name);$count=0
        for($i=1;$i -le $bar.Controls.Count;$i++){$control=$bar.Controls.Item($i);if([string]$control.Tag -eq 'SLC_68A45C44_2026'){$count++};Release-Com $control}
        $counts[$name]=$count;Release-Com $bar
    }
    $buttons=0
    try{$bar=$excel.CommandBars.Item('SLC_68A45C44_Toolbar');$buttons=$bar.Controls.Count;Release-Com $bar}catch{}
    $record['popupCounts']=$counts;$record['toolbarButtons']=$buttons
    $expected=if($ExpectInstalled){1}else{0}
    if($loaded -ne [bool]$ExpectInstalled -or @($counts.Values | Where-Object {$_ -ne $expected}).Count -or $buttons -ne (4*$expected)){throw 'Normal startup load/menu assertions failed.'}
    $record['status']='PASS'
}catch{$record['status']='FAIL';$record['error']=$_.Exception.Message;throw}
finally{
    $record['observedAt']=(Get-Date).ToString('o')
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $output -Encoding UTF8
    Release-Com $book;Release-Com $excel;$book=$null;$excel=$null
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    $process.Dispose()
    # Deliberately leave the owned visible fixture open for native UI tests.
}
