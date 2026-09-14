[CmdletBinding()]
param([Parameter(Mandatory=$true)][int]$OwnedPid,[Parameter(Mandatory=$true)][string]$FixtureDirectory)
$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SlcCleanupOwner {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
if(-not(Get-Process -Id $OwnedPid -ErrorAction SilentlyContinue)){Write-Output 'Owned Excel already exited.';exit 0}
$excel=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application')
try{
    [uint32]$actual=0
    [void][SlcCleanupOwner]::GetWindowThreadProcessId([IntPtr]$excel.Hwnd,[ref]$actual)
    if($actual -ne $OwnedPid){throw 'ROT returned another Excel; refusing cleanup.'}
    $prefix=[IO.Path]::GetFullPath($FixtureDirectory).TrimEnd('\')+'\'
    for($i=1;$i -le $excel.Workbooks.Count;$i++){
        $book=$excel.Workbooks.Item($i)
        try{if(-not ([string]$book.FullName).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected non-fixture workbook; refusing cleanup.'}}
        finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($book)}
    }
    for($i=$excel.Workbooks.Count;$i -ge 1;$i--){
        $book=$excel.Workbooks.Item($i);$book.Close($false);[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($book)
    }
    $excel.Quit()
    Write-Output "Normal Quit completed for owned PID $OwnedPid. Only test fixtures were closed."
}finally{
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($excel)
    $excel=$null;[GC]::Collect();[GC]::WaitForPendingFinalizers()
}
