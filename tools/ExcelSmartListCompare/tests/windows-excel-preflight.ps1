[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SlcProcessIdentity {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
$prior = @(Get-Process EXCEL -ErrorAction SilentlyContinue | ForEach-Object Id)
$excel = $null; $book = $null; $project = $null; $ownedPid = 0
$result = [ordered]@{started=(Get-Date).ToString('o'); existingPids=$prior; ownedPid=$null; status='FAIL'}
try {
    $excel = New-Object -ComObject Excel.Application
    [uint32]$processId = 0
    [void][SlcProcessIdentity]::GetWindowThreadProcessId([IntPtr]$excel.Hwnd,[ref]$processId)
    if ($processId -eq 0 -or $prior -contains $processId) { throw 'COM did not produce a provably new Excel process; do not quit it.' }
    $ownedPid = $processId
    $result.ownedPid = $ownedPid
    $result['hwnd'] = $excel.Hwnd
    $excel.AutomationSecurity = 2
    $result['excelVersion'] = [string]$excel.Version
    $result['excelBuild'] = [string]$excel.Build
    $result['operatingSystem'] = [string]$excel.OperatingSystem
    $result['automationSecurity'] = [int]$excel.AutomationSecurity
    $result['addins'] = @($excel.AddIns | ForEach-Object { [ordered]@{name=$_.Name;fullName=$_.FullName;installed=$_.Installed} })
    $book = $excel.Workbooks.Add(-4167)
    try {
        $project = $book.VBProject
        $result['vbaComponents'] = $project.VBComponents.Count
        $result['vbaAccess'] = 'PASS'
    } catch {
        $result['vbaAccess'] = 'BLOCKED_POLICY'
        $result['vbaAccessError'] = $_.Exception.Message
    }
    $result.status = 'PASS'
} catch {
    $result['error'] = $_.Exception.Message
} finally {
    if ($ownedPid -ne 0) {
        if ($book) { $book.Close($false) }
        $excel.Quit()
    }
    foreach ($value in @($project,$book,$excel)) {
        if ($value -and [Runtime.InteropServices.Marshal]::IsComObject($value)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($value) }
    }
    $project=$null; $book=$null; $excel=$null
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
    $result['completed'] = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    [pscustomobject]$result | Select-Object status,ownedPid,excelVersion,excelBuild,operatingSystem,vbaAccess,vbaAccessError | Format-List
}
if($result.status -ne 'PASS'){exit 1}
if($result.vbaAccess -eq 'BLOCKED_POLICY'){exit 5}
