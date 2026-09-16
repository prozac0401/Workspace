[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [hashtable]$ScriptParameters=@{},
    [string]$ParametersPath,
    [string]$RunId=((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)),
    [ValidateRange(2,3600)][int]$TimeoutSeconds=120,
    [ValidateRange(2,3)][int]$SampleSeconds=2,
    [ValidateRange(1,100)][double]$MaxBaselineCpuPercent=65,
    [ValidateRange(1,100)][double]$MaxBaselineMemoryPercent=80,
    [ValidateRange(0,1024)][double]$MinAvailableMemoryGB=2,
    [switch]$AllowExistingExcel
)
# Opt-in, serialized supervision. No Office/UI automation or policy changes.
# Only the exact child wrapper may be stopped; Excel is observed, never killed.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Windows is required.'}
if($RunId -notmatch '^[A-Za-z0-9_-]+$'){throw 'RunId must be a simple directory name.'}
if($ParametersPath -and $ScriptParameters.Count){throw 'Use ScriptParameters or ParametersPath, not both.'}
$scriptFile=(Get-Item -LiteralPath $ScriptPath).FullName
if([IO.Path]::GetExtension($scriptFile) -ine '.ps1'){throw 'ScriptPath must identify a PowerShell script.'}
if($ParametersPath){
    $parsed=Get-Content -LiteralPath $ParametersPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($null -eq $parsed -or $parsed -isnot [pscustomobject]){throw 'ParametersPath must contain a JSON object.'}
    foreach($property in $parsed.PSObject.Properties){$ScriptParameters[$property.Name]=$property.Value}
}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifacts=Join-Path $repoRoot 'artifacts'
$output=Join-Path $artifacts ('excel-bounded/'+$RunId)
# Evidence must remain local even if an ancestor has been replaced by a junction.
$ancestor=$output
while($ancestor -and $ancestor.Length -ge $artifacts.Length){
    if(Test-Path -LiteralPath $ancestor){
        if((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Evidence directory cannot pass through a reparse point.'}
    }
    $ancestor=Split-Path -Parent $ancestor
}
if(Test-Path -LiteralPath $output){throw 'Run directory already exists; choose a new RunId.'}
[void][IO.Directory]::CreateDirectory($output)
$utf8=New-Object Text.UTF8Encoding($false)
$summary=[ordered]@{
    schemaVersion=1;status='NOT_RUN';reason=$null;startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null
    scriptPath=$scriptFile;timeoutSeconds=$TimeoutSeconds;sampleSeconds=$SampleSeconds
    allowExistingExcel=[bool]$AllowExistingExcel
    baselineLimits=[ordered]@{cpuPercent=$MaxBaselineCpuPercent;memoryUsedPercent=$MaxBaselineMemoryPercent;availableMemoryGB=$MinAvailableMemoryGB}
    child=$null;childExitCode=$null;targetStatus='NOT_RUN';wrapperStopped=$false;logCaptureComplete=$null
    observedNewExcelAtExit=@();observedNewExcel=@();excelExitGraceSeconds=0;error=$null
    telemetry='telemetry.private.jsonl';stdout='stdout.private.log';stderr='stderr.private.log'
}
$exitCode=1;$mutex=$null;$locked=$false;$child=$null;$stdoutStream=$null;$stderrStream=$null
$stdoutTask=$null;$stderrTask=$null;$previousCpu=$null;$initialExcel=@();$initialExcelRead=$false
function Save-Summary {
    $summary.finishedUtc=[DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $output 'result.private.json'),($summary | ConvertTo-Json -Depth 12),$utf8)
}
function Get-ExcelSnapshot {
    @(Get-Process -Name EXCEL -ErrorAction SilentlyContinue | ForEach-Object {
        $started=$null
        try{$started=$_.StartTime.ToUniversalTime().ToString('o')}catch{}
        [ordered]@{pid=$_.Id;startedUtc=$started;workingSetMB=[math]::Round($_.WorkingSet64/1MB,1)}
    })
}
function Stop-OwnedWrapper {
    if($null -eq $child){return}
    $child.Refresh()
    if($child.HasExited){return}
    $observed=Get-Process -Id $child.Id -ErrorAction SilentlyContinue
    if($null -eq $observed -or $observed.StartTime.ToUniversalTime().Ticks -ne $summary.child.startTimeUtcTicks){
        throw 'Child identity changed; no process was stopped.'
    }
    # Kill() on this held Process handle never kills a process tree.
    $child.Kill()
    [void]$child.WaitForExit(3000)
    $summary.wrapperStopped=$true
}
try {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex=New-Object Threading.Mutex($false,('Local\SLC-BoundedTest-'+$sid))
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){
        $summary.status='BLOCKED_ENV';$summary.reason='Another bounded test is already running in this user session.';$exitCode=4
    } else {
        if(-not ('SlcBoundedResources' -as [type])){
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SlcBoundedResources {
    [StructLayout(LayoutKind.Sequential)] public struct FileTime { public uint Low; public uint High; }
    [StructLayout(LayoutKind.Sequential)] public class Memory {
        public uint Length = (uint)Marshal.SizeOf(typeof(Memory)); public uint Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx([In,Out] Memory memory);
    static ulong Ticks(FileTime v) { return ((ulong)v.High << 32) | v.Low; }
    public static ulong[] Cpu() {
        FileTime i,k,u; if(!GetSystemTimes(out i,out k,out u)) throw new System.ComponentModel.Win32Exception();
        return new ulong[]{Ticks(i),Ticks(k)+Ticks(u)};
    }
    public static Memory Ram() {
        var m=new Memory(); if(!GlobalMemoryStatusEx(m)) throw new System.ComponentModel.Win32Exception(); return m;
    }
}
'@
        }
        function Write-Sample([string]$phase) {
            $cpu=[SlcBoundedResources]::Cpu();$memory=[SlcBoundedResources]::Ram();$cpuPercent=$null
            if($null -ne $script:previousCpu -and $cpu[1] -gt $script:previousCpu[1]){
                $cpuPercent=[math]::Round(100*(1-([double]($cpu[0]-$script:previousCpu[0])/($cpu[1]-$script:previousCpu[1]))),1)
            }
            $script:previousCpu=$cpu
            $childState=$null
            if($null -ne $child){
                $child.Refresh()
                if(-not $child.HasExited){
                    $childState=[ordered]@{pid=$child.Id;startedUtc=$summary.child.startedUtc;cpuSeconds=[math]::Round($child.TotalProcessorTime.TotalSeconds,3);workingSetMB=[math]::Round($child.WorkingSet64/1MB,1);privateMemoryMB=[math]::Round($child.PrivateMemorySize64/1MB,1);priority=[string]$child.PriorityClass}
                }
            }
            $sample=[ordered]@{timestampUtc=[DateTime]::UtcNow.ToString('o');phase=$phase;cpuPercent=$cpuPercent;logicalProcessors=[Environment]::ProcessorCount;memoryUsedPercent=[math]::Round(100*(1-([double]$memory.AvailablePhysical/$memory.TotalPhysical)),1);availableMemoryGB=[math]::Round($memory.AvailablePhysical/1GB,2);totalMemoryGB=[math]::Round($memory.TotalPhysical/1GB,2);child=$childState;excelProcesses=@(Get-ExcelSnapshot)}
            [IO.File]::AppendAllText((Join-Path $output 'telemetry.private.jsonl'),(($sample | ConvertTo-Json -Depth 8 -Compress)+[Environment]::NewLine),$utf8)
            return $sample
        }
        $initialExcel=@(Get-ExcelSnapshot);$initialExcelRead=$true
        $null=Write-Sample 'baseline-start'
        Start-Sleep -Seconds $SampleSeconds
        $baseline=Write-Sample 'baseline'
        $summary.baseline=$baseline
        if(-not $AllowExistingExcel -and $baseline.excelProcesses.Count -gt 0){
            $summary.status='BLOCKED_ENV';$summary.reason='Excel is already running; no child test was started.';$exitCode=3
        } elseif($baseline.cpuPercent -gt $MaxBaselineCpuPercent -or $baseline.memoryUsedPercent -gt $MaxBaselineMemoryPercent -or $baseline.availableMemoryGB -lt $MinAvailableMemoryGB){
            $summary.status='BLOCKED_ENV';$summary.reason='Baseline resource limits exceeded; no child test was started.';$exitCode=75
        } else {
            $request=[ordered]@{scriptPath=$scriptFile;parameters=$ScriptParameters;gatePath=(Join-Path $output 'start.gate')}
            $requestFile=Join-Path $output 'request.private.json'
            [IO.File]::WriteAllText($requestFile,($request | ConvertTo-Json -Depth 20),$utf8)
            $worker=Join-Path $output 'worker.ps1'
            [IO.File]::WriteAllText($worker,@'
param([Parameter(Mandatory=$true)][string]$RequestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$wait=[Diagnostics.Stopwatch]::StartNew()
while(-not (Test-Path -LiteralPath $request.gatePath)){
    if($wait.Elapsed.TotalSeconds -ge 10){throw 'Supervisor did not allow test startup.'}
    Start-Sleep -Milliseconds 100
}
$parameters=@{}
foreach($property in $request.parameters.PSObject.Properties){$parameters[$property.Name]=$property.Value}
$global:LASTEXITCODE=0
try { & $request.scriptPath @parameters; exit $LASTEXITCODE }
catch { [Console]::Error.WriteLine($_.ToString()); exit 1 }
'@,$utf8)
            $start=New-Object Diagnostics.ProcessStartInfo
            $start.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
            # File names are passed as arguments, never interpolated into PowerShell source.
            $start.Arguments='-NoLogo -NoProfile -NonInteractive -STA -File "'+$worker+'" -RequestPath "'+$requestFile+'"'
            $start.WorkingDirectory=Split-Path -Parent $scriptFile
            $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
            $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
            $start.EnvironmentVariables['PSModulePath']=(Join-Path $env:ProgramFiles 'WindowsPowerShell/Modules')+';'+(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/Modules')
            $child=New-Object Diagnostics.Process;$child.StartInfo=$start
            if(-not $child.Start()){throw 'Child process did not start.'}
            $null=$child.Handle
            $summary.child=[ordered]@{pid=$child.Id;startedUtc=$child.StartTime.ToUniversalTime().ToString('o');startTimeUtcTicks=$child.StartTime.ToUniversalTime().Ticks;priority='BelowNormal'}
            $child.PriorityClass=[Diagnostics.ProcessPriorityClass]::BelowNormal
            $stdoutStream=[IO.File]::Create((Join-Path $output 'stdout.private.log'))
            $stderrStream=[IO.File]::Create((Join-Path $output 'stderr.private.log'))
            $stdoutTask=$child.StandardOutput.BaseStream.CopyToAsync($stdoutStream)
            $stderrTask=$child.StandardError.BaseStream.CopyToAsync($stderrStream)
            # Refuse an Excel process opened during preparation, before executing the test.
            if(-not $AllowExistingExcel -and @(Get-ExcelSnapshot).Count -gt 0){
                $summary.status='BLOCKED_ENV';$summary.reason='Excel opened during preflight; target script was not started.';$exitCode=3
                Stop-OwnedWrapper
            } else {
                [IO.File]::WriteAllText($request.gatePath,'start',$utf8)
                $timer=[Diagnostics.Stopwatch]::StartNew()
                $null=Write-Sample 'running'
                while(-not $child.WaitForExit($SampleSeconds*1000)){
                    $null=Write-Sample 'running'
                    if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){
                        $summary.status='FAIL';$summary.reason='Deadline reached; only the owned wrapper was stopped. Inspect reported Excel processes before another test.';$exitCode=124
                        Stop-OwnedWrapper
                        break
                    }
                }
                $child.Refresh()
                if($summary.status -eq 'NOT_RUN'){
                    $exitCode=$child.ExitCode;$summary.childExitCode=$exitCode
                    $summary.status=if($exitCode -eq 0){'PASS'}else{'FAIL'}
                    $summary.targetStatus=$summary.status
                    $summary.reason='Target script completed; this status only reflects its exit code.'
                }
                $summary.durationSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3)
                $null=Write-Sample 'finished'
            }
        }
    }
} catch {
    $summary.status='FAIL';$summary.reason='Supervisor failure.';$summary.error=$_.Exception.Message;$exitCode=1
    try{Stop-OwnedWrapper}catch{$summary.error+='; cleanup: '+$_.Exception.Message}
} finally {
    # A host interruption must not release the serial lock while its wrapper runs.
    if($null -ne $child){
        try{
            $child.Refresh()
            if(-not $child.HasExited){
                Stop-OwnedWrapper
                $summary.status='FAIL';$summary.reason='Supervisor interrupted; the exact owned wrapper was stopped.';$exitCode=125
            }
        }catch{$summary.status='FAIL';$summary.error='Could not finish owned-wrapper cleanup: '+$_.Exception.Message;$exitCode=1}
    }
    if($initialExcelRead){
        $initialKeys=@($initialExcel | ForEach-Object {([string]$_.pid)+'|'+$_.startedUtc})
        $summary.observedNewExcel=@(Get-ExcelSnapshot | Where-Object {$initialKeys -notcontains (([string]$_.pid)+'|'+$_.startedUtc)})
        $summary.observedNewExcelAtExit=@($summary.observedNewExcel)
        if($summary.observedNewExcel.Count -gt 0){
            # Quit can return just before EXCEL.EXE exits. Observe a short grace
            # period under the same serial lock; never infer process ownership.
            $exitGrace=[Diagnostics.Stopwatch]::StartNew()
            while($summary.observedNewExcel.Count -gt 0 -and $exitGrace.ElapsedMilliseconds -lt 3000){
                $remainingMs=[math]::Max(1,[math]::Min(250,3000-$exitGrace.ElapsedMilliseconds))
                Start-Sleep -Milliseconds $remainingMs
                $summary.observedNewExcel=@(Get-ExcelSnapshot | Where-Object {$initialKeys -notcontains (([string]$_.pid)+'|'+$_.startedUtc)})
            }
            $summary.excelExitGraceSeconds=[math]::Round($exitGrace.Elapsed.TotalSeconds,3)
        }
        if($summary.observedNewExcel.Count -gt 0 -and $summary.status -eq 'PASS'){
            $summary.status='FAIL';$summary.reason='New Excel processes remain; ownership is not assumed and no Excel process was stopped.';$exitCode=76
        }
    }
    foreach($copyTask in @($stdoutTask,$stderrTask)){if($null -ne $copyTask){try{[void]$copyTask.Wait(1000)}catch{}}}
    if($null -ne $stdoutTask -and $null -ne $stderrTask){
        $summary.logCaptureComplete=($stdoutTask.IsCompleted -and -not $stdoutTask.IsFaulted -and -not $stdoutTask.IsCanceled -and $stderrTask.IsCompleted -and -not $stderrTask.IsFaulted -and -not $stderrTask.IsCanceled)
        if(-not $summary.logCaptureComplete -and $summary.status -eq 'PASS'){
            $summary.status='FAIL';$summary.reason='Child output capture did not finish; inspect remaining processes. No descendant process was stopped.';$exitCode=77
        }
    }
    foreach($stream in @($stdoutStream,$stderrStream)){if($null -ne $stream){$stream.Dispose()}}
    if($null -ne $child){$child.Dispose()}
    Save-Summary
    if($locked){$mutex.ReleaseMutex()}
    if($null -ne $mutex){$mutex.Dispose()}
}
Write-Output ($summary.status+': '+$summary.reason)
Write-Output ('Local evidence: '+$output)
exit $exitCode
