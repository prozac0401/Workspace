[CmdletBinding(DefaultParameterSetName='Observe')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Observe')][ValidateRange(1,2147483647)][int]$OwnedPid,
    [Parameter(Mandatory=$true,ParameterSetName='Observe')][Alias('StartTimeUtcTicks','OwnedStartTicks')][long]$StartTicks,
    [Parameter(Mandatory=$true,ParameterSetName='Observe')][long]$Hwnd,
    [Parameter(Mandatory=$true,ParameterSetName='Observe')][string]$OutputPath,
    [Parameter(ParameterSetName='Observe')][ValidateRange(1,3000)][int]$MaxNodes=600,
    [Parameter(ParameterSetName='Observe')][ValidateRange(1,50)][int]$MaxDepth=20,
    [Parameter(ParameterSetName='Observe')][ValidateRange(3,60)][int]$TimeoutSeconds=20,
    [Parameter(ParameterSetName='Observe')][switch]$CaptureWindow,
    [Parameter(Mandatory=$true,ParameterSetName='SelfTest')][switch]$SelfTest,
    [Parameter(DontShow=$true,ParameterSetName='Observe')][switch]$InternalWorker,
    [Parameter(DontShow=$true,ParameterSetName='Observe')][string]$WorkerNonce
)
# Read-only observer for an explicitly identified synthetic Excel process.
# No input, activation, UI patterns, policy changes or desktop capture are used.
# The parent bounds provider/PrintWindow hangs by stopping only its worker process.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Use Windows PowerShell 5.1.'}

function Load-ObserverTypes {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Drawing
    if(-not ('SlcOwnedUi.Native' -as [type])){
        Add-Type @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
namespace SlcOwnedUi {
    public static class Native {
        public delegate bool EnumProc(IntPtr hwnd, IntPtr parameter);
        [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] private static extern bool EnumThreadWindows(uint threadId, EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int capacity);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, StringBuilder text, int capacity);
        [DllImport("user32.dll", SetLastError=true)] public static extern bool PrintWindow(IntPtr hwnd, IntPtr dc, uint flags);
        public static int WindowPid(IntPtr hwnd) { uint pid; GetWindowThreadProcessId(hwnd, out pid); return (int)pid; }
        // Enumerate only threads belonging to the requested process. Other apps'
        // windows are never enumerated for text, UIA properties or screenshots.
        public static long[] OwnedWindows(int pid, int milliseconds) {
            var found=new List<long>(); var seen=new HashSet<long>(); var clock=Stopwatch.StartNew();
            using(var process=Process.GetProcessById(pid)) {
                foreach(ProcessThread thread in process.Threads) {
                    try {
                        if(clock.ElapsedMilliseconds>=milliseconds) break;
                        EnumProc callback=delegate(IntPtr hwnd, IntPtr state) {
                            if(clock.ElapsedMilliseconds>=milliseconds) return false;
                            long handle=hwnd.ToInt64();
                            if(WindowPid(hwnd)==pid && seen.Add(handle)) found.Add(handle);
                            return true;
                        };
                        EnumThreadWindows((uint)thread.Id, callback, IntPtr.Zero);
                        GC.KeepAlive(callback);
                    } finally { thread.Dispose(); }
                }
            }
            return found.ToArray();
        }
        public static string Title(IntPtr hwnd) { var text=new StringBuilder(4096); GetWindowText(hwnd,text,text.Capacity); return text.ToString(); }
        public static string ClassName(IntPtr hwnd) { var text=new StringBuilder(512); GetClassName(hwnd,text,text.Capacity); return text.ToString(); }
    }
}
'@
    }
}
function Get-BitmapStatistics($Bitmap){
    $colors=[Collections.Generic.HashSet[int]]::new();$samples=0;$black=0;$white=0
    for($row=0;$row -lt 16;$row++){
        for($column=0;$column -lt 16;$column++){
            $x=[Math]::Min($Bitmap.Width-1,[int][Math]::Floor($column*($Bitmap.Width-1)/15.0))
            $y=[Math]::Min($Bitmap.Height-1,[int][Math]::Floor($row*($Bitmap.Height-1)/15.0))
            $pixel=$Bitmap.GetPixel($x,$y);[void]$colors.Add($pixel.ToArgb());$samples++
            if($pixel.R -eq 0 -and $pixel.G -eq 0 -and $pixel.B -eq 0){$black++}
            if($pixel.R -eq 255 -and $pixel.G -eq 255 -and $pixel.B -eq 255){$white++}
        }
    }
    return [ordered]@{
        sampledPixels=$samples;sampledDistinctColors=$colors.Count;uniformSample=($colors.Count -le 1)
        blackFraction=$black/[double]$samples;whiteFraction=$white/[double]$samples
        limitation='Uniform sampling detects a possibly blank capture; nonuniform pixels do not prove complete/correct rendering.'
    }
}
function Get-FiniteBounds($Rectangle){
    if($Rectangle.IsEmpty){return $null}
    $result=[ordered]@{}
    foreach($pair in @(@('left',$Rectangle.Left),@('top',$Rectangle.Top),@('width',$Rectangle.Width),@('height',$Rectangle.Height))){
        $value=[double]$pair[1]
        $result[$pair[0]]=if([double]::IsNaN($value) -or [double]::IsInfinity($value)){$null}else{$value}
    }
    return $result
}
if($SelfTest){
    # No process lookup, HWND enumeration, UIA tree access or native calls occur.
    Load-ObserverTypes
    $bitmap=New-Object Drawing.Bitmap(32,32)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::Black)
        $uniform=Get-BitmapStatistics $bitmap
        $graphics.FillRectangle([Drawing.Brushes]::White,0,0,16,32)
        $split=Get-BitmapStatistics $bitmap
        if(-not $uniform.uniformSample -or $uniform.blackFraction -ne 1 -or $split.uniformSample -or $split.sampledDistinctColors -ne 2){throw 'Synthetic bitmap classification failed.'}
        $bounds=Get-FiniteBounds ([pscustomobject]@{IsEmpty=$false;Left=[double]::PositiveInfinity;Top=2;Width=3;Height=4})
        if($null -ne $bounds.left -or $bounds.top -ne 2){throw 'Non-finite bounds conversion failed.'}
        [ordered]@{status='PASS';checks=@('PS5 UIA assemblies load','native declarations compile without native calls','uniform synthetic bitmap detected','two-color synthetic bitmap not uniform','non-finite bounds are JSON-safe');uiOrExcelAccess=$false} | ConvertTo-Json -Depth 4
    }finally{$graphics.Dispose();$bitmap.Dispose()}
    exit 0
}

$output=[IO.Path]::GetFullPath($OutputPath)
if([IO.Path]::GetExtension($output) -ine '.json'){throw 'OutputPath must name a fresh JSON evidence file.'}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifactRoot=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts')).TrimEnd('\')+'\'
if(-not $output.StartsWith($artifactRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence must remain below this repository artifacts directory.'}
$directory=Split-Path -Parent $output;$ancestor=$directory
while($ancestor){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'Evidence paths must not traverse a reparse point.'
    }
    $ancestor=Split-Path -Parent $ancestor
}
$basePath=Join-Path $directory ([IO.Path]::GetFileNameWithoutExtension($output))
$png=$basePath+'.owned-window.png';$stdout=$basePath+'.worker.stdout.private.log';$stderr=$basePath+'.worker.stderr.private.log'
$utf8=New-Object Text.UTF8Encoding($false)
function Assert-OwnedProcess {
    $process=Get-Process -Id $OwnedPid -ErrorAction Stop
    try{
        if($process.ProcessName -ine 'EXCEL' -or $process.StartTime.ToUniversalTime().Ticks -ne $StartTicks){
            throw 'PID/start-time identity is not the requested Excel process; no UI was read.'
        }
    }finally{$process.Dispose()}
}
function Assert-OwnedWindow([long]$Handle){
    Assert-OwnedProcess
    if(-not [SlcOwnedUi.Native]::IsWindow([IntPtr]$Handle) -or [SlcOwnedUi.Native]::WindowPid([IntPtr]$Handle) -ne $OwnedPid){
        throw 'HWND does not belong to the requested Excel identity; no further UI is read.'
    }
}
function Save-Report {
    $temporary=$output+'.writing'
    [IO.File]::WriteAllText($temporary,($report | ConvertTo-Json -Depth 14),$utf8)
    if([IO.File]::Exists($output)){[IO.File]::Replace($temporary,$output,[NullString]::Value)}
    else{[IO.File]::Move($temporary,$output)}
}
if(-not $InternalWorker){
    foreach($path in @($output,$output+'.writing',$png,$stdout,$stderr)){if(Test-Path -LiteralPath $path){throw 'Existing evidence is preserved; choose a fresh OutputPath.'}}
    Assert-OwnedProcess
    [void][IO.Directory]::CreateDirectory($directory)
    $nonce=[guid]::NewGuid().ToString('N')
    $report=[ordered]@{
        schemaVersion=1;kind='SLC-owned-read-only-UI-observation';requestId=$nonce;status='STARTED';phase='starting-worker'
        owner=[ordered]@{pid=$OwnedPid;startTicks=$StartTicks;hwnd=$Hwnd};startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null
        bounds=[ordered]@{maxNodes=$MaxNodes;maxDepth=$MaxDepth;timeoutSeconds=$TimeoutSeconds}
        captureRequested=[bool]$CaptureWindow;windows=@();nodes=@();truncated=$false;errors=@();capture=$null
        worker=$null;workerExitCode=$null;workerStopped=$false;testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        scope='Only target Excel thread windows and their owned UIA descendants; no input, activation or desktop capture.'
    }
    Save-Report
    $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if(Test-Path -LiteralPath (Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe')){
        $powershell=Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-STA','-File',('"'+$PSCommandPath+'"'),'-InternalWorker','-WorkerNonce',$nonce,
        '-OwnedPid',[string]$OwnedPid,'-StartTicks',[string]$StartTicks,'-Hwnd',[string]$Hwnd,'-OutputPath',('"'+$output+'"'),
        '-MaxNodes',[string]$MaxNodes,'-MaxDepth',[string]$MaxDepth,'-TimeoutSeconds',[string]$TimeoutSeconds)
    if($CaptureWindow){$arguments+='-CaptureWindow'}
    $worker=$null;$timedOut=$false;$parentError=$null;$workerIdentity=$null;$workerStopped=$false
    try{
        # No execution-policy override: the child follows the existing policy.
        $worker=Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $workerIdentity=[ordered]@{pid=$worker.Id;startedUtc=$worker.StartTime.ToUniversalTime().ToString('o');startTicks=$worker.StartTime.ToUniversalTime().Ticks}
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while(-not $worker.WaitForExit(250)){
            if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){
                $timedOut=$true
                # Kill this held child handle only. Never terminate Excel or a tree.
                if(-not $worker.HasExited){$worker.Kill();$workerStopped=$true;[void]$worker.WaitForExit(3000)}
                break
            }
        }
        if($worker.HasExited){$workerExit=$worker.ExitCode}else{$workerExit=$null}
    }catch{$parentError=$_.Exception.Message}
    finally{
        if($null -ne $worker){
            try{
                # A parent-side error must not leave an observer reading UI after
                # the caller believes the bounded observation has ended.
                if(-not $worker.HasExited){$worker.Kill();$workerStopped=$true;[void]$worker.WaitForExit(3000)}
            }catch{$parentError='Observer worker cleanup failed: '+$_.Exception.Message}
            finally{$worker.Dispose()}
        }
        $report=Get-Content -LiteralPath $output -Raw -Encoding UTF8 | ConvertFrom-Json
        $report.worker=$workerIdentity;$report.workerStopped=$workerStopped
        if($null -ne (Get-Variable workerExit -ErrorAction SilentlyContinue)){$report.workerExitCode=$workerExit}
        if($timedOut){$report.status='TIMEOUT';$report.truncated=$true;$report.errors+=@('Observer worker exceeded the time limit; only the observer process was stopped.')}
        elseif($null -ne $parentError){$report.status='FAIL';$report.errors+=@($parentError)}
        elseif($report.status -eq 'STARTED'){$report.status='FAIL';$report.errors+=@('Worker exited before writing an observation result; inspect its private error log.')}
        $report.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-Report
    }
    Write-Output ($report.status+': '+$output)
    if($report.status -in @('FAIL','TIMEOUT')){exit 1}
    exit 0
}

# Worker may update only the parent's exact owned, nonce-bound evidence record.
if([string]::IsNullOrWhiteSpace($WorkerNonce) -or -not (Test-Path -LiteralPath $output -PathType Leaf)){throw 'A parent observation request is required.'}
$report=Get-Content -LiteralPath $output -Raw -Encoding UTF8 | ConvertFrom-Json
if($report.kind -cne 'SLC-owned-read-only-UI-observation' -or $report.requestId -cne $WorkerNonce -or
    $report.owner.pid -ne $OwnedPid -or $report.owner.startTicks -ne $StartTicks -or $report.owner.hwnd -ne $Hwnd){throw 'Worker request identity mismatch; no UI was read.'}
if((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $report.testScriptSha256){throw 'Observer script changed after the request; no UI was read.'}
$windows=[Collections.Generic.List[object]]::new();$nodes=[Collections.Generic.List[object]]::new()
$clock=[Diagnostics.Stopwatch]::StartNew();$workerFailure=$null
function Flush-Observation {
    $report.windows=@($windows.ToArray());$report.nodes=@($nodes.ToArray());Save-Report
}
function Remaining-Milliseconds {return [Math]::Max(0,[int]($TimeoutSeconds*1000-$clock.Elapsed.TotalMilliseconds))}
try{
    Load-ObserverTypes
    Assert-OwnedWindow $Hwnd
    $report.phase='enumerating-owned-windows';Flush-Observation
    $handles=@([SlcOwnedUi.Native]::OwnedWindows($OwnedPid,(Remaining-Milliseconds)))
    if($handles -notcontains $Hwnd){$handles=@($Hwnd)+$handles}
    foreach($handle in $handles){
        if((Remaining-Milliseconds) -le 0){$report.truncated=$true;break}
        Assert-OwnedWindow $handle
        $rect=New-Object SlcOwnedUi.Native+Rect
        $hasRect=[SlcOwnedUi.Native]::GetWindowRect([IntPtr]$handle,[ref]$rect)
        $windows.Add([pscustomobject][ordered]@{
            hwnd=$handle;title=[SlcOwnedUi.Native]::Title([IntPtr]$handle);className=[SlcOwnedUi.Native]::ClassName([IntPtr]$handle)
            visible=[SlcOwnedUi.Native]::IsWindowVisible([IntPtr]$handle);minimized=[SlcOwnedUi.Native]::IsIconic([IntPtr]$handle)
            bounds=if($hasRect){[ordered]@{left=$rect.Left;top=$rect.Top;width=$rect.Right-$rect.Left;height=$rect.Bottom-$rect.Top}}else{$null}
        })
    }
    $report.phase='reading-owned-uia-tree';Flush-Observation
    $walker=[Windows.Automation.TreeWalker]::RawViewWalker
    foreach($window in $windows){
        if($nodes.Count -ge $MaxNodes -or (Remaining-Milliseconds) -le 0){$report.truncated=$true;break}
        Assert-OwnedWindow $window.hwnd
        try{$root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$window.hwnd)}
        catch{$report.errors+=@('UIA root unavailable for owned HWND '+$window.hwnd+': '+$_.Exception.Message);continue}
        if($null -eq $root){continue}
        $stack=[Collections.Generic.Stack[object]]::new()
        $stack.Push([pscustomobject]@{element=$root;parent=$null;depth=0})
        while($stack.Count -gt 0){
            if($nodes.Count -ge $MaxNodes -or (Remaining-Milliseconds) -le 0){$report.truncated=$true;break}
            Assert-OwnedProcess
            $item=$stack.Pop();$element=$item.element
            try{
                # Check ownership before reading names/content. Never descend into
                # a subtree exposed by a provider from another process.
                if([int]$element.Current.ProcessId -ne $OwnedPid){continue}
                $current=$element.Current;$box=$current.BoundingRectangle;$index=$nodes.Count
                $nodes.Add([pscustomobject][ordered]@{
                    index=$index;parentIndex=$item.parent;depth=$item.depth;windowHwnd=$window.hwnd
                    processId=$OwnedPid;nativeWindowHandle=$current.NativeWindowHandle
                    name=$current.Name;controlType=$current.ControlType.ProgrammaticName
                    automationId=$current.AutomationId;className=$current.ClassName;enabled=$current.IsEnabled;offscreen=$current.IsOffscreen
                    bounds=(Get-FiniteBounds $box)
                })
                if($nodes.Count%20 -eq 0){Flush-Observation}
                if($item.depth -ge $MaxDepth){$report.truncated=$true;continue}
                # Collect siblings with a bound; push in reverse for stable DFS.
                $children=[Collections.Generic.List[object]]::new();$child=$walker.GetFirstChild($element)
                while($null -ne $child){
                    if($children.Count+$nodes.Count+$stack.Count -ge $MaxNodes -or (Remaining-Milliseconds) -le 0){$report.truncated=$true;break}
                    $children.Add($child);$child=$walker.GetNextSibling($child)
                }
                for($indexChild=$children.Count-1;$indexChild -ge 0;$indexChild--){
                    $stack.Push([pscustomobject]@{element=$children[$indexChild];parent=$index;depth=$item.depth+1})
                }
            }catch{$report.errors+=@('Owned UIA node unavailable: '+$_.Exception.Message)}
        }
    }
    Flush-Observation
    if($CaptureWindow){
        if((Remaining-Milliseconds) -le 0){$report.capture=[pscustomobject]@{status='NOT_RUN_TIME_LIMIT';path=$null}}
        else{
            Assert-OwnedWindow $Hwnd
            $report.phase='capturing-owned-window';$report.capture=[pscustomobject]@{status='STARTED';hwnd=$Hwnd;path=$png;apiSucceeded=$null;possiblyBlank=$null;statistics=$null;error=$null};Flush-Observation
            $rect=New-Object SlcOwnedUi.Native+Rect
            if(-not [SlcOwnedUi.Native]::GetWindowRect([IntPtr]$Hwnd,[ref]$rect)){throw 'Owned window bounds unavailable for capture.'}
            $width=$rect.Right-$rect.Left;$height=$rect.Bottom-$rect.Top
            if($width -le 0 -or $height -le 0 -or $width -gt 8192 -or $height -gt 8192 -or [long]$width*$height -gt 32000000){throw 'Owned window bitmap dimensions exceed capture bounds.'}
            $bitmap=New-Object Drawing.Bitmap($width,$height);$graphics=[Drawing.Graphics]::FromImage($bitmap);$dc=[IntPtr]::Zero
            try{
                $graphics.Clear([Drawing.Color]::Black);$dc=$graphics.GetHdc()
                $printed=[SlcOwnedUi.Native]::PrintWindow([IntPtr]$Hwnd,$dc,2)
                $graphics.ReleaseHdc($dc);$dc=[IntPtr]::Zero
                Assert-OwnedWindow $Hwnd
                $report.capture.apiSucceeded=$printed
                if($printed){
                    $statistics=Get-BitmapStatistics $bitmap
                    $bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
                    $report.capture.statistics=$statistics;$report.capture.possiblyBlank=$statistics.uniformSample
                    $report.capture.status=if($statistics.uniformSample){'POSSIBLY_BLANK'}else{'CAPTURED_REVIEW_REQUIRED'}
                }else{$report.capture.status='PRINTWINDOW_RETURNED_FALSE';$report.capture.path=$null}
            }finally{if($dc -ne [IntPtr]::Zero){$graphics.ReleaseHdc($dc)};$graphics.Dispose();$bitmap.Dispose()}
        }
    }
    $report.status=if($report.truncated -or $report.errors.Count -gt 0){'PARTIAL'}else{'OBSERVED'}
}catch{$workerFailure=$_.Exception.Message;$report.errors+=@($workerFailure);$report.status='FAIL'}
finally{$report.phase='complete';$report.finishedUtc=[DateTime]::UtcNow.ToString('o');Flush-Observation}
if($null -ne $workerFailure){exit 1}
