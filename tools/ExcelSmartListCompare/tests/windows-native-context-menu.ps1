[CmdletBinding(DefaultParameterSetName='Run')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Run')][string]$RequestPath,
    [Parameter(Mandatory=$true,ParameterSetName='Run')][string]$OutputDirectory,
    [Parameter(ParameterSetName='Run')][ValidateSet('Observe','OpenMenu','ExpandProduct','InvokeProduct')][string]$Mode='Observe',
    [Parameter(ParameterSetName='Run')][ValidateSet('Capture','Compare','Clear','Replace')][string]$Command='Capture',
    [Parameter(ParameterSetName='Run')][ValidateRange(5,60)][int]$TimeoutSeconds=30,
    [Parameter(Mandatory=$true,ParameterSetName='SelfTest')][switch]$SelfTest,
    [Parameter(DontShow=$true,ParameterSetName='Run')][switch]$InternalWorker,
    [Parameter(DontShow=$true,ParameterSetName='Run')][string]$Nonce
)
# Test support only: never starts/quits Excel, opens/saves/closes workbooks,
# calls Application.Run, changes a selection, or responds to a dialog.
# Request JSON (private, below repository artifacts):
# {"schemaVersion":1,"pid":123,"startTicks":123,"hwnd":123,
#  "fixtures":[{"path":"D:\\...\\artifacts\\...\\First.xlsx","sha256":"64 hex"}],
#  "activeFixture":"D:\\...\\artifacts\\...\\First.xlsx",
#  "selectionAddress":"$A$1:$A$3","contextKind":"Cell",
#  "addin":{"path":"D:\\...\\ExcelSmartListCompare.xlam","sha256":"64 hex"}}
# All visible ordinary workbooks must be saved synthetic fixtures in that exact
# list. The caller prepares/owns their selection and independently verifies the
# product outcome. Native invocation is evidence of a UI action, not its result.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Use Windows PowerShell 5.1.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifacts=[IO.Path]::GetFullPath((Join-Path $repo 'artifacts')).TrimEnd('\')+'\'
$utf8=New-Object Text.UTF8Encoding($false)
$labels=@{Capture='첫 번째 목록 담기';Compare='두 번째 목록 담아 비교';Clear='첫 번째 목록 비우기';Replace='첫 번째 목록 바꾸기'}
function Get-SharedReadSha256([string]$Path){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()}
    finally{$stream.Dispose()}
}
function Assert-Shape($Request){
    if($Request.schemaVersion -ne 1 -or [int]$Request.pid -le 0 -or [long]$Request.startTicks -le 0 -or [long]$Request.hwnd -le 0){throw 'Invalid owner request.'}
    if($Request.contextKind -cnotin @('Cell','Row','Column')){throw 'Only Cell/Row/Column context tests are permitted.'}
    if([string]$Request.selectionAddress -notmatch '^\$[A-Z]+\$[0-9]+(:\$[A-Z]+\$[0-9]+)?$'){
        # Whole-row/column selections have Excel's $1:$1 or $A:$A address.
        if([string]$Request.selectionAddress -notmatch '^(\$[0-9]+:\$[0-9]+|\$[A-Z]+:\$[A-Z]+)$'){throw 'A single exact A1-style selection is required.'}
    }
    if(@($Request.fixtures).Count -lt 1 -or @($Request.fixtures).Count -gt 4){throw 'One to four saved synthetic fixtures are required.'}
    $paths=@()
    foreach($item in @($Request.fixtures)){
        if([string]$item.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [IO.Path]::GetExtension([string]$item.path) -ine '.xlsx'){throw 'Invalid fixture path/hash.'}
        $path=[IO.Path]::GetFullPath([string]$item.path)
        if(-not $path.StartsWith($artifacts,[StringComparison]::OrdinalIgnoreCase) -or $paths -contains $path){throw 'Fixtures must be distinct repository artifacts.'}
        $paths+=$path
    }
    if($paths -notcontains [IO.Path]::GetFullPath([string]$Request.activeFixture)){throw 'Active workbook must be one of the known fixtures.'}
    if([string]$Request.addin.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [IO.Path]::GetFileName([string]$Request.addin.path) -cne 'ExcelSmartListCompare.xlam'){throw 'An exact product XLAM path/hash is required.'}
}
function Assert-NoReparse([string]$Path){
    $ancestor=[IO.Path]::GetFullPath($Path)
    while($ancestor){
        if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Test paths must not traverse reparse points.'}
        $ancestor=Split-Path -Parent $ancestor
    }
}
function Add-MenuRuntimeIdentity([Collections.Generic.HashSet[string]]$SeenRuntimeIds,[int[]]$RuntimeId){
    if($null -eq $RuntimeId -or $RuntimeId.Count -eq 0){throw 'UIA runtime identity is unavailable; ambiguous traversal is preserved.'}
    # Runtime IDs identify the same live UIA element across separate root walks.
    # Names, coordinates and native window handles are not element identities.
    return $SeenRuntimeIds.Add(($RuntimeId -join ':'))
}
function Get-NodeNativeAncestor($Node,$Walker,[int]$OwnerPid){
    $ancestor=$Node
    for($depth=0;$depth -lt 32 -and $null -ne $ancestor;$depth++){
        $current=$ancestor.Current
        if([int]$current.ProcessId -ne $OwnerPid){throw 'UIA native ancestor belongs to a different process.'}
        if([long]$current.NativeWindowHandle -ne 0){return [long]$current.NativeWindowHandle}
        $ancestor=$Walker.GetParent($ancestor)
    }
    throw 'UIA menu item has no bounded owned native ancestor.'
}
function Find-ExactItem($Nodes,[string]$Name){
    $matched=@($Nodes|Where-Object{$_.name -ceq $Name -and $_.controlType -ceq 'ControlType.MenuItem' -and $_.enabled})
    if($matched.Count -ne 1){throw ('Expected exactly one visible enabled native menu item: '+$Name+'; found '+$matched.Count)}
    return $matched[0]
}
function Load-Types {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
namespace SlcNativeMenu {
 public static class Native {
  private delegate bool EnumProc(IntPtr h,IntPtr p);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
  [StructLayout(LayoutKind.Sequential)] private struct GuiInfo { public uint cbSize,flags; public IntPtr active,focus,capture,menuOwner,moveSize,caret; public Rect caretRect; }
  [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int x,y; public uint data,flags,time; public UIntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort key,scan; public uint flags,time; public UIntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] private struct Union { [FieldOffset(0)] public MouseInput mouse; [FieldOffset(0)] public KeyboardInput keyboard; }
  [StructLayout(LayoutKind.Sequential)] private struct Input { public uint type; public Union data; }
  [DllImport("user32.dll")] private static extern bool EnumThreadWindows(uint id,EnumProc callback,IntPtr parameter);
  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] private static extern bool IsChild(IntPtr parent,IntPtr child);
  [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr h,uint flags);
  [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint id,ref GuiInfo info);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr h,StringBuilder b,int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
  [DllImport("user32.dll",SetLastError=true)] private static extern uint SendInput(uint count,Input[] input,int size);
  [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
  [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr h);
  [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(uint thread);
  [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] private static extern IntPtr GetProcessWindowStation();
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern bool GetUserObjectInformation(IntPtr h,int index,IntPtr value,uint size,out uint needed);
  [DllImport("wtsapi32.dll",CharSet=CharSet.Unicode)] private static extern bool WTSQuerySessionInformation(IntPtr server,int session,int info,out IntPtr buffer,out uint bytes);
  [DllImport("wtsapi32.dll")] private static extern void WTSFreeMemory(IntPtr b);
  public static int Pid(IntPtr h) { uint id; GetWindowThreadProcessId(h,out id); return (int)id; }
  public static string Class(IntPtr h) { var b=new StringBuilder(256); GetClassName(h,b,b.Capacity); return b.ToString(); }
  public static long Foreground() { return GetForegroundWindow().ToInt64(); }
  public static long Root(long hwnd) { return GetAncestor(new IntPtr(hwnd),2).ToInt64(); }
  public static long RootOwner(long hwnd) { return GetAncestor(new IntPtr(hwnd),3).ToInt64(); }
  public static bool Enabled(long hwnd) { return IsWindowEnabled(new IntPtr(hwnd)); }
  public static string MenuForegroundBlock(int ownerPid,long main,long menu,long foreground,int foregroundPid,int menuPid,string menuClass,long menuRootOwner,bool menuVisible,bool menuEnabled) {
   if(ownerPid<=0 || main<=0 || menu<=0 || foreground<=0 || menuPid!=ownerPid || foregroundPid!=ownerPid) return "menu_or_foreground_owner_changed";
   if(!menuVisible || !menuEnabled) return "observed_menu_window_unavailable";
   if(menuRootOwner!=main) return "observed_menu_root_owner_differs";
   if(menu==main) { if(menuClass!="XLMAIN") return "observed_main_class_changed"; }
   else if(menuClass!="Net UI Tool Window" && menuClass!="#32768") return "observed_menu_class_unrecognized";
   if(foreground!=main && foreground!=menu) return "foreground_is_not_exact_main_or_observed_menu";
   return null;
  }
  public static bool SameProcess(int pid,long ticks) {
   try { using(var p=Process.GetProcessById(pid)) { return !p.HasExited && p.ProcessName.Equals("EXCEL",StringComparison.OrdinalIgnoreCase) && p.StartTime.ToUniversalTime().Ticks==ticks && p.SessionId==Process.GetCurrentProcess().SessionId; } } catch { return false; }
  }
  public static long[] Windows(int pid) {
   var values=new List<long>(); var seen=new HashSet<long>();
   using(var p=Process.GetProcessById(pid)) foreach(ProcessThread thread in p.Threads) {
    try { EnumProc callback=delegate(IntPtr h,IntPtr ignored) { if(Pid(h)==pid && IsWindowVisible(h) && seen.Add(h.ToInt64())) values.Add(h.ToInt64()); return values.Count<64; }; EnumThreadWindows((uint)thread.Id,callback,IntPtr.Zero); GC.KeepAlive(callback); }
    finally {thread.Dispose();}
   }
   return values.ToArray();
  }
  private static string ObjectName(IntPtr h) {
   IntPtr memory=Marshal.AllocHGlobal(1024); uint needed;
   try {return GetUserObjectInformation(h,2,memory,1024,out needed)?Marshal.PtrToStringUni(memory):null;} finally {Marshal.FreeHGlobal(memory);}
  }
  public static string DesktopBlock() {
   IntPtr state=IntPtr.Zero; uint bytes;
   try { if(!WTSQuerySessionInformation(IntPtr.Zero,Process.GetCurrentProcess().SessionId,8,out state,out bytes) || bytes<4 || Marshal.ReadInt32(state)!=0) return "session_not_active"; } finally {if(state!=IntPtr.Zero) WTSFreeMemory(state);}
   if(ObjectName(GetProcessWindowStation())!="WinSta0" || ObjectName(GetThreadDesktop(GetCurrentThreadId()))!="Default") return "not_interactive_default_desktop";
   IntPtr desktop=OpenInputDesktop(0,false,1); if(desktop==IntPtr.Zero) return "input_desktop_unavailable";
   try {return ObjectName(desktop)=="Default"?null:"input_desktop_not_default";} finally {CloseDesktop(desktop);}
  }
  public static string Guard(int pid,long ticks,long hwnd,bool input) {
   if(!SameProcess(pid,ticks)) return "owned_process_changed";
   IntPtr main=new IntPtr(hwnd);
   if(Pid(main)!=pid || Class(main)!="XLMAIN" || !IsWindowVisible(main) || !IsWindowEnabled(main) || IsIconic(main)) return "main_window_unavailable_or_disabled";
   string desktop=DesktopBlock(); if(desktop!=null) return desktop;
   foreach(long value in Windows(pid)) {
    string name=Class(new IntPtr(value));
    if(name=="#32770" || name=="NUIDialog" || name=="bosa_sdm_XL9") return "owned_dialog_present";
   }
   if(input && GetForegroundWindow()!=main) return "exact_main_window_not_foreground";
   return null;
  }
  public static uint[] ShiftF10(int pid,long ticks,long hwnd) {
   string reason=Guard(pid,ticks,hwnd,true); if(reason!=null) throw new InvalidOperationException(reason);
   foreach(int key in new int[]{0x10,0x11,0x12,0x5B,0x5C,0x79}) if((GetAsyncKeyState(key)&0x8000)!=0) throw new InvalidOperationException("user_modifier_or_F10_already_down");
   uint ignored; uint thread=GetWindowThreadProcessId(new IntPtr(hwnd),out ignored);
   var gui=new GuiInfo(); gui.cbSize=(uint)Marshal.SizeOf(typeof(GuiInfo));
   if(!GetGUIThreadInfo(thread,ref gui) || Pid(gui.focus)!=pid || !IsChild(new IntPtr(hwnd),gui.focus) || Class(gui.focus)!="EXCEL7") throw new InvalidOperationException("focus_is_not_owned_worksheet_grid");
   var inputs=new Input[]{Key(0x10,false),Key(0x79,false),Key(0x79,true),Key(0x10,true)};
   uint inserted=0,released=0;
   try {inserted=SendInput(4,inputs,Marshal.SizeOf(typeof(Input)));}
   finally {released=SendInput(2,new Input[]{Key(0x79,true),Key(0x10,true)},Marshal.SizeOf(typeof(Input)));}
   return new uint[]{inserted,released};
  }
  private static Input Key(ushort key,bool up) {var i=new Input();i.type=1;i.data.keyboard.key=key;i.data.keyboard.flags=up?2U:0U;return i;}
  public static int InputSize() {return Marshal.SizeOf(typeof(Input));}
 }
}
'@
}
if($SelfTest){
    # Only assembly loads, C# compilation and pure managed synthetic checks.
    Load-Types
    $fixture=Join-Path $artifacts 'selftest-never-created.xlsx'
    $sample=[pscustomobject]@{schemaVersion=1;pid=1;startTicks=1;hwnd=1;fixtures=@([pscustomobject]@{path=$fixture;sha256=('a'*64)});activeFixture=$fixture;selectionAddress='$A$1:$A$3';contextKind='Cell';addin=[pscustomobject]@{path='C:\never-opened\ExcelSmartListCompare.xlam';sha256=('b'*64)}}
    Assert-Shape $sample
    $rejected=0
    foreach($bad in @('Unknown','cell','SecurityDialog')){$sample.contextKind=$bad;try{Assert-Shape $sample}catch{$rejected++}}
    if($rejected -ne 3 -or [SlcNativeMenu.Native]::InputSize() -ne $(if([IntPtr]::Size -eq 8){40}else{28})){throw 'Managed self-test failed.'}
    $hashTestDirectory=Join-Path $artifacts ('excel-native-context-selftest/'+[guid]::NewGuid().ToString('N'))
    Assert-NoReparse $hashTestDirectory
    [void][IO.Directory]::CreateDirectory($hashTestDirectory)
    $hashFixture=Join-Path $hashTestDirectory 'locked.private.txt'
    [IO.File]::WriteAllText($hashFixture,'synthetic shared-read hash fixture',$utf8)
    $expectedHash=(Get-FileHash -LiteralPath $hashFixture -Algorithm SHA256).Hash.ToLowerInvariant()
    $writer=[IO.File]::Open($hashFixture,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    try{
        $ordinaryRejected=$false
        try{$null=Get-FileHash -LiteralPath $hashFixture -Algorithm SHA256 -ErrorAction Stop}catch{$ordinaryRejected=$true}
        $sharedHash=Get-SharedReadSha256 $hashFixture
        if(-not $ordinaryRejected -or $sharedHash -cne $expectedHash){throw 'Shared readonly hash regression failed.'}
    }finally{$writer.Dispose()}
    if((Get-FileHash -LiteralPath $hashFixture -Algorithm SHA256).Hash -ine $expectedHash){throw 'Hash fixture was modified.'}
    $runtimeIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $mockNodes=[Collections.Generic.List[object]]::new()
    foreach($identity in @(@(42,7,11),@(42,7,11))){
        if(Add-MenuRuntimeIdentity $runtimeIds $identity){$mockNodes.Add([pscustomobject]@{name='명단 비교';controlType='ControlType.MenuItem';enabled=$true;runtimeId=$identity})}
    }
    if($mockNodes.Count -ne 1){throw 'Repeated runtime identity was not deduplicated.'}
    $null=Find-ExactItem $mockNodes.ToArray() '명단 비교'
    if(-not (Add-MenuRuntimeIdentity $runtimeIds @(42,7,12))){throw 'Different runtime identities were merged.'}
    $mockNodes.Add([pscustomobject]@{name='명단 비교';controlType='ControlType.MenuItem';enabled=$true;runtimeId=@(42,7,12)})
    $ambiguousRejected=$false
    try{$null=Find-ExactItem $mockNodes.ToArray() '명단 비교'}catch{$ambiguousRejected=$true}
    if(-not $ambiguousRejected){throw 'Different menu identities with equal captions must remain ambiguous.'}
    $missingIdentityRejected=$false
    try{$null=Add-MenuRuntimeIdentity $runtimeIds @()}catch{$missingIdentityRejected=$true}
    if(-not $missingIdentityRejected){throw 'Missing runtime identity must fail closed.'}
    $menuGuardChecks=@(
        @{foreground=20;foregroundPid=7;menuPid=7;menuClass='Net UI Tool Window';rootOwner=10;visible=$true;enabled=$true;allowed=$true},
        @{foreground=10;foregroundPid=7;menuPid=7;menuClass='Net UI Tool Window';rootOwner=10;visible=$true;enabled=$true;allowed=$true},
        @{foreground=30;foregroundPid=7;menuPid=7;menuClass='Net UI Tool Window';rootOwner=10;visible=$true;enabled=$true;allowed=$false},
        @{foreground=20;foregroundPid=8;menuPid=7;menuClass='Net UI Tool Window';rootOwner=10;visible=$true;enabled=$true;allowed=$false},
        @{foreground=20;foregroundPid=7;menuPid=8;menuClass='Net UI Tool Window';rootOwner=10;visible=$true;enabled=$true;allowed=$false},
        @{foreground=20;foregroundPid=7;menuPid=7;menuClass='Net UI Tool Window';rootOwner=11;visible=$true;enabled=$true;allowed=$false},
        @{foreground=20;foregroundPid=7;menuPid=7;menuClass='#32770';rootOwner=10;visible=$true;enabled=$true;allowed=$false},
        @{foreground=20;foregroundPid=7;menuPid=7;menuClass='Net UI Tool Window';rootOwner=10;visible=$false;enabled=$true;allowed=$false},
        @{foreground=20;foregroundPid=7;menuPid=7;menuClass='Net UI Tool Window';rootOwner=10;visible=$true;enabled=$false;allowed=$false}
    )
    foreach($case in $menuGuardChecks){
        $block=[SlcNativeMenu.Native]::MenuForegroundBlock(7,10,20,$case.foreground,$case.foregroundPid,$case.menuPid,$case.menuClass,$case.rootOwner,$case.visible,$case.enabled)
        if(([string]::IsNullOrEmpty($block)) -ne $case.allowed){throw 'Exact observed-menu foreground regression failed.'}
    }
    $mockWalker=New-Object PSObject
    $mockWalker|Add-Member -MemberType ScriptMethod -Name GetParent -Value {param($Element) return $Element.Parent}
    $traversalParent=[pscustomobject]@{Current=[pscustomobject]@{ProcessId=7;NativeWindowHandle=100};Parent=$null}
    $submenuParent=[pscustomobject]@{Current=[pscustomobject]@{ProcessId=7;NativeWindowHandle=200};Parent=$traversalParent}
    $mockItem=[pscustomobject]@{Current=[pscustomobject]@{ProcessId=7;NativeWindowHandle=0};Parent=$submenuParent}
    if((Get-NodeNativeAncestor $mockItem $mockWalker 7) -ne 200){throw 'Menu association must use the nearest native ancestor, not the traversal root.'}
    $mockItem.Current.NativeWindowHandle=300
    if((Get-NodeNativeAncestor $mockItem $mockWalker 7) -ne 300){throw 'The menu element native handle must precede its parent.'}
    $mockItem.Current.NativeWindowHandle=0;$submenuParent.Current.ProcessId=8
    $foreignParentRejected=$false
    try{$null=Get-NodeNativeAncestor $mockItem $mockWalker 7}catch{$foreignParentRejected=$true}
    if(-not $foreignParentRejected){throw 'Foreign native ancestors must fail closed.'}
    $mockItem.Parent=$null;$missingParentRejected=$false
    try{$null=Get-NodeNativeAncestor $mockItem $mockWalker 7}catch{$missingParentRejected=$true}
    if(-not $missingParentRejected){throw 'Missing native ancestors must fail closed.'}
    [ordered]@{status='PASS';checks=@('request schema and strict context whitelist','UIA assemblies loaded','native declarations compiled','architecture-correct INPUT layout','default hash rejected while writer held FileShare.Read','shared readonly hash succeeded with unchanged bytes','same UIA runtime identity across roots deduplicated','same-caption different runtime identities remain ambiguous','missing runtime identity rejected','9 exact-menu foreground ownership decisions','nearest native submenu ancestor beats traversal root','direct native handle beats ancestor','foreign and missing native ancestors rejected');nativeUiOrExcelCalls=$false;hashFixture=$hashFixture}|ConvertTo-Json
    exit 0
}
$requestFile=[IO.Path]::GetFullPath($RequestPath)
$output=[IO.Path]::GetFullPath($OutputDirectory)
foreach($path in @($requestFile,$output)){
    if(-not $path.StartsWith($artifacts,[StringComparison]::OrdinalIgnoreCase)){throw 'Request/evidence must be under repository artifacts.'}
    Assert-NoReparse $path
}
$requestHash=(Get-FileHash -LiteralPath $requestFile -Algorithm SHA256).Hash.ToLowerInvariant()
$request=Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8|ConvertFrom-Json
Assert-Shape $request
foreach($item in @($request.fixtures)+@($request.addin)){Assert-NoReparse ([string]$item.path)}
$reportPath=Join-Path $output 'native-context.private.json'
function Save-Report {
    $temporary=$reportPath+'.writing'
    [IO.File]::WriteAllText($temporary,($report|ConvertTo-Json -Depth 16),$utf8)
    if(Test-Path -LiteralPath $reportPath){[IO.File]::Replace($temporary,$reportPath,[NullString]::Value)}else{[IO.File]::Move($temporary,$reportPath)}
}
if(-not $InternalWorker){
    if(Test-Path -LiteralPath $output){throw 'Existing evidence is preserved; choose a fresh output directory.'}
    [void][IO.Directory]::CreateDirectory($output)
    $Nonce=[guid]::NewGuid().ToString('N')
    $report=[ordered]@{schemaVersion=1;kind='SLC-native-context-test';nonce=$Nonce;status='STARTED';mode=$Mode;command=$Command;requestSha256=$requestHash;testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();owner=[ordered]@{pid=$request.pid;startTicks=$request.startTicks;hwnd=$request.hwnd};startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null;phase='starting';actions=@();observations=@();captures=@();errors=@();worker=$null;workerExitCode=$null;workerStopped=$false;limitations=@('UI invocation does not prove a product outcome; the owning driver must verify it independently.','Only saved synthetic fixtures are permitted. Exact third-party imitation of product menu captions cannot be excluded.','PrintWindow images require visual review; capture success does not prove correct rendering.','No dialogs are handled, no Excel process is terminated, and no workbook or selection is changed by COM.')}
    Save-Report
    $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-STA','-File',('"'+$PSCommandPath+'"'),'-RequestPath',('"'+$requestFile+'"'),'-OutputDirectory',('"'+$output+'"'),'-Mode',$Mode,'-Command',$Command,'-TimeoutSeconds',[string]$TimeoutSeconds,'-InternalWorker','-Nonce',$Nonce)
    $worker=$null;$identity=$null;$timeout=$false;$stopped=$false;$errorText=$null;$workerExit=$null
    try{
        $worker=Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'worker.stdout.private.log') -RedirectStandardError (Join-Path $output 'worker.stderr.private.log')
        $identity=[ordered]@{pid=$worker.Id;startTicks=$worker.StartTime.ToUniversalTime().Ticks}
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while(-not $worker.WaitForExit(200)){
            if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timeout=$true;break}
        }
    }catch{$errorText=$_.Exception.Message}
    finally{
        if($null -ne $worker){
            try{if(-not $worker.HasExited){$worker.Kill();$stopped=$true;[void]$worker.WaitForExit(3000)};if($worker.HasExited){$workerExit=$worker.ExitCode}}
            catch{$errorText='Helper worker cleanup failed: '+$_.Exception.Message}
            finally{$worker.Dispose()}
        }
        $report=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8|ConvertFrom-Json
        $report.worker=$identity;$report.workerExitCode=$workerExit;$report.workerStopped=$stopped
        if($timeout){$report.status='TIMEOUT';$report.errors+=@('Only the helper worker was stopped. Excel/menu state is preserved for the owning driver.')}
        elseif($errorText){$report.status='FAIL';$report.errors+=@($errorText)}
        elseif($report.status -eq 'STARTED'){$report.status='FAIL';$report.errors+=@('Worker exited without a completed result; inspect the private stderr log.')}
        $report.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-Report
    }
    Write-Output ($report.status+': '+$reportPath)
    if($report.status -in @('FAIL','TIMEOUT')){exit 1};exit 0
}
if(-not (Test-Path -LiteralPath $reportPath)){throw 'A parent-created request is required.'}
$report=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8|ConvertFrom-Json
if($report.kind -cne 'SLC-native-context-test' -or $report.nonce -cne $Nonce -or $report.requestSha256 -cne $requestHash -or $report.mode -cne $Mode -or $report.command -cne $Command -or $report.testScriptSha256 -cne (Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()){throw 'Worker request identity changed.'}
$excel=$null
function Release-Com($Value){if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($Value)}}
function Assert-Native([bool]$InputAction=$false){
    $block=[SlcNativeMenu.Native]::Guard([int]$request.pid,[long]$request.startTicks,[long]$request.hwnd,$InputAction)
    if($block){throw ('Native guard: '+$block)}
}
function Assert-Fixtures {
    Assert-Native
    if((Get-FileHash -LiteralPath $requestFile).Hash -ine $requestHash){throw 'Request changed during test.'}
    foreach($item in @($request.fixtures)+@($request.addin)){
        if((Get-SharedReadSha256 ([string]$item.path)) -ine [string]$item.sha256){throw 'Known fixture or product bytes changed.'}
    }
    if($null -eq $script:excel){$script:excel=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application')}
    if([SlcNativeMenu.Native]::Pid([IntPtr][long]$excel.Hwnd) -ne [int]$request.pid -or [long]$excel.Hwnd -ne [long]$request.hwnd){throw 'COM returned a different Excel window; no workbook content was read.'}
    $books=$null;$active=$null;$selection=$null;$areas=$null;$rows=$null;$columns=$null;$sheet=$null;$allRows=$null;$allColumns=$null
    try{
        $books=$excel.Workbooks;$actual=@()
        for($index=1;$index -le $books.Count;$index++){
            $book=$books.Item($index)
            try{
                $full=[IO.Path]::GetFullPath([string]$book.FullName)
                if([bool]$book.IsAddin){if($full -ine [IO.Path]::GetFullPath([string]$request.addin.path)){throw 'Unknown add-in workbook; preserved.'};continue}
                if([string]$book.Path -eq '' -or -not [bool]$book.Saved){throw 'Unsaved/modified ordinary workbook; preserved.'}
                $actual+=$full
            }finally{Release-Com $book}
        }
        $expected=@($request.fixtures|ForEach-Object{[IO.Path]::GetFullPath([string]$_.path)})
        if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -notcontains $_}).Count){throw 'Unexpected workbook set; preserved.'}
        $active=$excel.ActiveWorkbook
        if([IO.Path]::GetFullPath([string]$active.FullName) -ine [IO.Path]::GetFullPath([string]$request.activeFixture)){throw 'Active workbook differs from the requested synthetic fixture.'}
        $selection=$excel.Selection;$areas=$selection.Areas
        if($areas.Count -ne 1 -or [string]$selection.Address($true,$true,1,$false) -cne [string]$request.selectionAddress){throw 'Actual selection differs from the exact requested address.'}
        $rows=$selection.Rows;$columns=$selection.Columns;$sheet=$selection.Worksheet;$allRows=$sheet.Rows;$allColumns=$sheet.Columns
        $kind=if($columns.Count -eq $allColumns.Count){'Row'}elseif($rows.Count -eq $allRows.Count){'Column'}else{'Cell'}
        if($kind -cne [string]$request.contextKind -or ($rows.Count -eq $allRows.Count -and $columns.Count -eq $allColumns.Count)){throw 'Selection shape differs from the requested native menu kind.'}
    }finally{foreach($value in @($allColumns,$allRows,$sheet,$columns,$rows,$areas,$selection,$active,$books)){Release-Com $value}}
}
function Get-MenuNodes {
    Assert-Native
    $result=[Collections.Generic.List[object]]::new();$seen=0
    $runtimeIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $walker=[Windows.Automation.TreeWalker]::RawViewWalker
    # Popup windows precede main windows so large worksheet trees cannot hide menus.
    $handles=@([SlcNativeMenu.Native]::Windows([int]$request.pid)|Sort-Object @{Expression={if([SlcNativeMenu.Native]::Class([IntPtr]$_) -eq 'XLMAIN'){1}else{0}}})
    foreach($handle in $handles){
        if([SlcNativeMenu.Native]::Pid([IntPtr]$handle) -ne [int]$request.pid){throw 'Window ownership changed.'}
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$handle)
        if($null -eq $root){continue}
        $stack=[Collections.Generic.Stack[object]]::new();$stack.Push([pscustomobject]@{element=$root;depth=0;inMenu=$false})
        while($stack.Count -gt 0){
            if($seen -ge 1600){throw 'UIA traversal bound reached; no ambiguous action is permitted.'}
            $item=$stack.Pop();$node=$item.element
            if([int]$node.Current.ProcessId -ne [int]$request.pid){continue}
            $current=$node.Current;$seen++
            $runtimeId=[int[]]$node.GetRuntimeId()
            if(-not (Add-MenuRuntimeIdentity $runtimeIds $runtimeId)){continue}
            $isMenu=$current.ControlType -eq [Windows.Automation.ControlType]::Menu
            $inMenu=$item.inMenu -or $isMenu
            $windowPattern=$null
            if($node.TryGetCurrentPattern([Windows.Automation.WindowPattern]::Pattern,[ref]$windowPattern) -and $windowPattern.Current.IsModal){throw 'A modal UIA window is present; preserved.'}
            if(-not $current.IsOffscreen -and ($isMenu -or ($inMenu -and $current.ControlType -eq [Windows.Automation.ControlType]::MenuItem))){
                $nativeAncestor=Get-NodeNativeAncestor $node $walker ([int]$request.pid)
                $associatedWindow=[SlcNativeMenu.Native]::Root($nativeAncestor)
                if([SlcNativeMenu.Native]::Pid([IntPtr]$nativeAncestor) -ne [int]$request.pid -or [SlcNativeMenu.Native]::Pid([IntPtr]$associatedWindow) -ne [int]$request.pid -or -not [SlcNativeMenu.Native]::IsWindowVisible([IntPtr]$associatedWindow) -or [SlcNativeMenu.Native]::RootOwner($associatedWindow) -ne [long]$request.hwnd){throw 'Associated menu window is not a visible root of the exact owned main window.'}
                $result.Add([pscustomobject]@{element=$node;hwnd=$associatedWindow;traversalHwnd=[long]$handle;nativeAncestorHwnd=$nativeAncestor;runtimeId=$runtimeId;realNativeHwnd=[long]$current.NativeWindowHandle;name=$current.Name;controlType=$current.ControlType.ProgrammaticName;enabled=$current.IsEnabled;automationId=$current.AutomationId;className=$current.ClassName})
            }
            if($item.depth -ge 24){continue}
            $child=$walker.GetFirstChild($node);$children=[Collections.Generic.List[object]]::new()
            while($null -ne $child){
                if($children.Count -ge 500){throw 'UIA sibling bound reached.'}
                $children.Add($child);$child=$walker.GetNextSibling($child)
            }
            for($i=$children.Count-1;$i -ge 0;$i--){$stack.Push([pscustomobject]@{element=$children[$i];depth=$item.depth+1;inMenu=$inMenu})}
        }
    }
    return @($result.ToArray())
}
function Save-Captures([string]$Phase,$Nodes){
    Assert-Fixtures
    $handles=@([long]$request.hwnd)+@($Nodes|ForEach-Object{[long]$_.hwnd})|Select-Object -Unique
    foreach($handle in $handles){
        Assert-Native
        if([SlcNativeMenu.Native]::Pid([IntPtr]$handle) -ne [int]$request.pid){throw 'Capture window ownership changed.'}
        $rect=New-Object SlcNativeMenu.Native+Rect
        if(-not [SlcNativeMenu.Native]::GetWindowRect([IntPtr]$handle,[ref]$rect)){throw 'Capture bounds unavailable.'}
        $width=$rect.Right-$rect.Left;$height=$rect.Bottom-$rect.Top
        if($width -le 0 -or $height -le 0 -or $width -gt 8192 -or $height -gt 8192 -or [long]$width*$height -gt 32000000){throw 'Capture dimensions exceed bounds.'}
        $file=Join-Path $output ($Phase+'-'+$handle+'.private.png')
        if(Test-Path -LiteralPath $file){throw 'Existing screenshot is preserved.'}
        $bitmap=New-Object Drawing.Bitmap($width,$height);$graphics=[Drawing.Graphics]::FromImage($bitmap);$dc=[IntPtr]::Zero
        try{
            $graphics.Clear([Drawing.Color]::Black);$dc=$graphics.GetHdc()
            $ok=[SlcNativeMenu.Native]::PrintWindow([IntPtr]$handle,$dc,2)
            $graphics.ReleaseHdc($dc);$dc=[IntPtr]::Zero
            Assert-Native
            $colors=[Collections.Generic.HashSet[int]]::new()
            for($y=0;$y -lt 16;$y++){for($x=0;$x -lt 16;$x++){[void]$colors.Add($bitmap.GetPixel([int][Math]::Floor($x*($width-1)/15.0),[int][Math]::Floor($y*($height-1)/15.0)).ToArgb())}}
            if($ok){$bitmap.Save($file,[Drawing.Imaging.ImageFormat]::Png)}
            $report.captures+=@([ordered]@{phase=$Phase;hwnd=$handle;apiSucceeded=$ok;path=$(if($ok){$file}else{$null});sampledDistinctColors=$colors.Count;status=$(if(-not $ok){'PRINTWINDOW_FAILED'}elseif($colors.Count -le 1){'POSSIBLY_BLANK'}else{'CAPTURED_REVIEW_REQUIRED'})});Save-Report
        }finally{if($dc -ne [IntPtr]::Zero){$graphics.ReleaseHdc($dc)};$graphics.Dispose();$bitmap.Dispose()}
    }
}
function Observe-Menus([string]$Phase){
    $nodes=@(Get-MenuNodes)
    $report.observations+=@([ordered]@{phase=$Phase;contextKind=$request.contextKind;selectionAddress=$request.selectionAddress;nodes=@($nodes|Select-Object hwnd,traversalHwnd,nativeAncestorHwnd,runtimeId,realNativeHwnd,name,controlType,enabled,automationId,className)})
    Save-Report
    Save-Captures $Phase $nodes
    return $nodes
}
function Assert-Item($Item,[string]$Name){
    Assert-Fixtures;Assert-Native
    $current=$Item.element.Current
    if($current.ProcessId -ne [int]$request.pid -or $current.Name -cne $Name -or $current.ControlType -ne [Windows.Automation.ControlType]::MenuItem -or $current.IsOffscreen -or -not $current.IsEnabled){throw 'Native menu target changed before action.'}
    $currentRuntimeId=[int[]]$Item.element.GetRuntimeId()
    if($currentRuntimeId.Count -eq 0 -or ($currentRuntimeId -join ':') -cne ($Item.runtimeId -join ':')){throw 'Native menu runtime identity changed before action.'}
    $currentNativeAncestor=Get-NodeNativeAncestor $Item.element ([Windows.Automation.TreeWalker]::RawViewWalker) ([int]$request.pid)
    if($currentNativeAncestor -ne [long]$Item.nativeAncestorHwnd -or [SlcNativeMenu.Native]::Root($currentNativeAncestor) -ne [long]$Item.hwnd){throw 'Native menu associated window changed before action.'}
    $foreground=[SlcNativeMenu.Native]::Foreground();$menu=[long]$Item.hwnd
    $foregroundPid=[SlcNativeMenu.Native]::Pid([IntPtr]$foreground);$menuPid=[SlcNativeMenu.Native]::Pid([IntPtr]$menu)
    $menuClass=[SlcNativeMenu.Native]::Class([IntPtr]$menu);$menuRootOwner=[SlcNativeMenu.Native]::RootOwner($menu)
    $menuVisible=[SlcNativeMenu.Native]::IsWindowVisible([IntPtr]$menu);$menuEnabled=[SlcNativeMenu.Native]::Enabled($menu)
    $block=[SlcNativeMenu.Native]::MenuForegroundBlock([int]$request.pid,[long]$request.hwnd,$menu,$foreground,$foregroundPid,$menuPid,$menuClass,$menuRootOwner,$menuVisible,$menuEnabled)
    $report.observations+=@([ordered]@{phase='menu-item-guard';name=$Name;runtimeId=$currentRuntimeId;realNativeHwnd=[long]$current.NativeWindowHandle;foregroundHwnd=$foreground;foregroundPid=$foregroundPid;foregroundClass=[SlcNativeMenu.Native]::Class([IntPtr]$foreground);foregroundRootOwner=[SlcNativeMenu.Native]::RootOwner($foreground);observedMenuHwnd=$menu;observedMenuClass=$menuClass;observedMenuRootOwner=$menuRootOwner;blockedReason=$block;nodes=@()})
    Save-Report
    if($block){throw ('Native menu guard: '+$block)}
    if([SlcNativeMenu.Native]::Foreground() -ne $foreground){throw 'Foreground changed while verifying the exact observed menu.'}
}
try{
    Load-Types
    $report.phase='verifying-fixtures';Save-Report;Assert-Fixtures
    $nodes=@(Observe-Menus 'initial')
    if($Mode -ne 'Observe'){
        if(@($nodes|Where-Object{$_.controlType -ceq 'ControlType.Menu'}).Count -eq 0){
            Assert-Fixtures;Assert-Native $true
            $report.phase='sending-ShiftF10';Save-Report
            $inserted=[SlcNativeMenu.Native]::ShiftF10([int]$request.pid,[long]$request.startTicks,[long]$request.hwnd)
            $report.actions+=@([ordered]@{action='ShiftF10';inserted=$inserted[0];expected=4;releaseInserted=$inserted[1];reception='unconfirmed';utc=[DateTime]::UtcNow.ToString('o')});Save-Report
            if($inserted[0] -ne 4 -or $inserted[1] -ne 2){throw 'ShiftF10 input insertion was incomplete.'}
            Start-Sleep -Milliseconds 250
            $nodes=@(Observe-Menus 'opened')
        }
        $product=Find-ExactItem $nodes '명단 비교'
        if($Mode -in @('ExpandProduct','InvokeProduct')){
            Assert-Item $product '명단 비교'
            $pattern=$null
            if(-not $product.element.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$pattern)){throw 'Product submenu exposes no ExpandCollapse pattern; no coordinate fallback is used.'}
            $report.phase='expanding-product';Save-Report
            $pattern.Expand()
            $report.actions+=@([ordered]@{action='ExpandCollapse.Expand';name='명단 비교';returned=$true;utc=[DateTime]::UtcNow.ToString('o')});Save-Report
            Start-Sleep -Milliseconds 250
            $nodes=@(Observe-Menus 'expanded')
        }
        if($Mode -eq 'InvokeProduct'){
            $label=[string]$labels[$Command];$item=Find-ExactItem $nodes $label
            Assert-Item $item $label
            $pattern=$null
            if(-not $item.element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)){throw 'Product command exposes no Invoke pattern; no coordinate or macro fallback is used.'}
            $report.phase='invoking-product';Save-Report
            # Capture precedes invocation. Compare may create a new result book;
            # this helper never assumes ownership of it or captures its contents.
            $pattern.Invoke()
            $report.actions+=@([ordered]@{action='InvokePattern.Invoke';name=$label;returned=$true;productOutcome='NOT_VERIFIED';utc=[DateTime]::UtcNow.ToString('o')});Save-Report
        }
    }
    $report.status=if($Mode -eq 'Observe'){'OBSERVED'}elseif($Mode -eq 'InvokeProduct'){'INVOKED_OUTCOME_UNVERIFIED'}else{'MENU_OBSERVED'}
}catch{$report.status='FAIL';$report.errors+=@($_.Exception.Message)}
finally{
    Release-Com $excel;$excel=$null
    $report.phase='complete';$report.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-Report
}
if($report.status -eq 'FAIL'){exit 1}
