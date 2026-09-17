<#
Observes only a specifically owned synthetic-test Excel process. Observe is the
default and never clicks or sends keys. Run in native Windows PowerShell 5.1.
OutputPath must be a fresh JSONL file under this repository's artifacts folder.

AcceptLarge approves only the two exact PrepareParts product warnings.
RejectLarge declines the same exact warnings using their No button (ID 7).
DismissResult closes only allowlisted product cancellation/error messages.
Neither mode handles Office security, sign-in, save, or installation dialogs.
LegacyWording explicitly selects the RC7 warning/cancel/timeout strings audited
from XLAM SHA-256 5da5ff891232dde733d60ee6151cbfb26e251d6b75a51cb6a3f224effde4c18b.
The current wording remains the default. No macro source is executed to audit it.

Esc is opt-in, once per observer, and requires a fresh StartSignalPath file made
by the test driver AFTER the processing request starts. Signal contents are not
read. The driver removes the signal as soon as the processing call returns.
Delay starts when that signal and a modal-free Excel window are observed.
The signal is a driver claim, not proof that Excel has begun processing. A
successful SendInput call is not evidence that Excel received/cancelled work.
EscHoldMilliseconds defaults to the immediate down/up pair. A positive value
holds down for up to 500 requested milliseconds; finally always sends key-up,
including when foreground, desktop, signal, or process state changes meanwhile.
Measured timing is between injection API calls, not Excel key reception.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$OwnedPid,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=120,
    [ValidateRange(10,100)][int]$PollMilliseconds=100,
    [ValidateSet('Observe','AcceptLarge','RejectLarge','DismissResult')][string]$Mode='Observe',
    [ValidateRange(-1,3600000)][int]$EscDelayMilliseconds=-1,
    [ValidateRange(0,500)][int]$EscHoldMilliseconds=0,
    [string]$StartSignalPath,
    [switch]$LegacyWording
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1.'}
if($Mode -eq 'Observe' -and $EscDelayMilliseconds -ge 0){throw 'Observe never injects input; choose an explicit input mode.'}
if($Mode -eq 'RejectLarge' -and $EscDelayMilliseconds -ge 0){throw 'RejectLarge only declines warnings; Esc is not allowed.'}
if($EscDelayMilliseconds -ge 0 -and [string]::IsNullOrWhiteSpace($StartSignalPath)){throw 'Esc requires a fresh StartSignalPath from the test driver.'}
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifactRoot=[IO.Path]::GetFullPath((Join-Path $repository 'artifacts'))+[IO.Path]::DirectorySeparatorChar
$output=[IO.Path]::GetFullPath($OutputPath)
if(-not $output.StartsWith($artifactRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Observer output must stay under repository artifacts.'}
if(-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($output))){throw 'Create the dedicated test output directory first.'}
if(Test-Path -LiteralPath $output){throw 'Existing observer output is preserved.'}
$signal=$null
if(-not [string]::IsNullOrWhiteSpace($StartSignalPath)){
    $signal=[IO.Path]::GetFullPath($StartSignalPath)
    if($signal -eq $output -or (Test-Path -LiteralPath $signal)){throw 'StartSignalPath must be separate and absent at startup.'}
}
$owned=Get-Process -Id $OwnedPid -ErrorAction Stop
if($owned.ProcessName -ine 'EXCEL'){throw 'OwnedPid is not Excel.'}
if($owned.SessionId -ne [Diagnostics.Process]::GetCurrentProcess().SessionId){throw 'Owned Excel must be in the observer session.'}
$ownedStartUtc=$owned.StartTime.ToUniversalTime()
$ownedStartTicks=$ownedStartUtc.Ticks
$observerStartedUtc=[DateTime]::UtcNow

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public sealed class SlcObservedControl {
    public long Hwnd; public string ClassName; public int Id; public string Text;
    public bool Enabled; public bool Visible;
}
public sealed class SlcObservedDialog {
    public long Hwnd; public string Title; public SlcObservedControl[] Controls;
}
public static class SlcDialogObserverNative {
    private delegate bool EnumProc(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr param);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr param);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, StringBuilder value, int size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder value, int size);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern int GetDlgCtrlID(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetDlgItem(IntPtr hwnd, int id);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, UIntPtr wParam, StringBuilder lParam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(uint threadId);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern bool GetUserObjectInformation(IntPtr handle, int index, IntPtr info, uint length, out uint needed);
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode)] private static extern bool WTSQuerySessionInformation(IntPtr server, int session, int infoClass, out IntPtr buffer, out uint bytes);
    [DllImport("wtsapi32.dll")] private static extern void WTSFreeMemory(IntPtr buffer);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort key,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion { [FieldOffset(0)] public MouseInput mouse; [FieldOffset(0)] public KeyboardInput keyboard; }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint type; public InputUnion data; }
    [DllImport("user32.dll", SetLastError=true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    private static uint Pid(IntPtr hwnd) { uint id; GetWindowThreadProcessId(hwnd,out id); return id; }
    private static string Class(IntPtr hwnd) { var value=new StringBuilder(256); GetClassName(hwnd,value,value.Capacity); return value.ToString(); }
    private static string Caption(IntPtr hwnd) { var value=new StringBuilder(16384); GetWindowText(hwnd,value,value.Capacity); return value.ToString(); }
    private static string ControlText(IntPtr hwnd) {
        var value=new StringBuilder(16384); UIntPtr result;
        return SendMessageTimeout(hwnd,13,new UIntPtr((uint)value.Capacity),value,3,100,out result)==IntPtr.Zero ? null : value.ToString();
    }
    public static bool SameProcess(int pid, long ticks) {
        try { using(var p=Process.GetProcessById(pid)) { return !p.HasExited && p.ProcessName.Equals("EXCEL",StringComparison.OrdinalIgnoreCase) && p.StartTime.ToUniversalTime().Ticks==ticks && p.SessionId==Process.GetCurrentProcess().SessionId; } }
        catch { return false; }
    }
    public static SlcObservedDialog[] Dialogs(int pid) {
        var dialogs=new List<SlcObservedDialog>();
        EnumWindows(delegate(IntPtr hwnd,IntPtr ignored) {
            if(Pid(hwnd)!=(uint)pid || !IsWindowVisible(hwnd) || Class(hwnd)!="#32770") return true;
            var controls=new List<SlcObservedControl>();
            EnumChildWindows(hwnd,delegate(IntPtr child,IntPtr unused) {
                if(Pid(child)!=(uint)pid) return true;
                string name=Class(child);
                if(name=="Static" || name=="Button") controls.Add(new SlcObservedControl { Hwnd=child.ToInt64(),ClassName=name,Id=GetDlgCtrlID(child),Text=ControlText(child),Enabled=IsWindowEnabled(child),Visible=IsWindowVisible(child) });
                return controls.Count<64;
            },IntPtr.Zero);
            dialogs.Add(new SlcObservedDialog { Hwnd=hwnd.ToInt64(),Title=Caption(hwnd),Controls=controls.ToArray() });
            return dialogs.Count<16;
        },IntPtr.Zero);
        return dialogs.ToArray();
    }
    private static string ObjectName(IntPtr handle) {
        IntPtr memory=Marshal.AllocHGlobal(1024); uint needed;
        try { return GetUserObjectInformation(handle,2,memory,1024,out needed) ? Marshal.PtrToStringUni(memory) : null; }
        finally { Marshal.FreeHGlobal(memory); }
    }
    public static string InputDesktopBlock() {
        IntPtr state=IntPtr.Zero; uint bytes;
        try {
            if(!WTSQuerySessionInformation(IntPtr.Zero,Process.GetCurrentProcess().SessionId,8,out state,out bytes) || bytes<4 || Marshal.ReadInt32(state)!=0) return "session_not_active";
        } finally { if(state!=IntPtr.Zero) WTSFreeMemory(state); }
        if(ObjectName(GetProcessWindowStation())!="WinSta0" || ObjectName(GetThreadDesktop(GetCurrentThreadId()))!="Default") return "observer_not_interactive_default_desktop";
        IntPtr desktop=OpenInputDesktop(0,false,1);
        if(desktop==IntPtr.Zero) return "input_desktop_inaccessible_or_locked";
        try { return ObjectName(desktop)=="Default" ? null : "input_desktop_not_default_or_locked"; }
        finally { CloseDesktop(desktop); }
    }
    public static string EscBlock(int pid,long ticks) {
        if(!SameProcess(pid,ticks)) return "owned_process_changed_or_exited";
        string desktop=InputDesktopBlock(); if(desktop!=null) return desktop;
        IntPtr foreground=GetForegroundWindow();
        if(Pid(foreground)!=(uint)pid || Class(foreground)!="XLMAIN" || !IsWindowEnabled(foreground)) return "foreground_not_enabled_owned_excel_main_window";
        bool modal=false;
        EnumWindows(delegate(IntPtr hwnd,IntPtr ignored) {
            if(Pid(hwnd)==(uint)pid && IsWindowVisible(hwnd)) {
                IntPtr owner=GetWindow(hwnd,4);
                if(Class(hwnd)=="#32770" || (owner!=IntPtr.Zero && !IsWindowEnabled(owner))) modal=true;
            }
            return !modal;
        },IntPtr.Zero);
        if(modal) return "owned_modal_present";
        foreach(int key in new int[] {16,17,18,27,91,92}) if((GetAsyncKeyState(key)&0x8000)!=0) return "key_already_held";
        return null;
    }
    public static string Click(int pid,long ticks,long dialogHandle,long buttonHandle,int buttonId,string expectedTitle,string expectedBody,string expectedButtonText) {
        if(!SameProcess(pid,ticks)) return "blocked:owned_process_changed_or_exited";
        string desktop=InputDesktopBlock(); if(desktop!=null) return "blocked:"+desktop;
        IntPtr dialog=new IntPtr(dialogHandle),button=new IntPtr(buttonHandle);
        if(GetForegroundWindow()!=dialog || Pid(dialog)!=(uint)pid || Class(dialog)!="#32770" || Caption(dialog)!=expectedTitle || !IsWindowVisible(dialog)) return "blocked:dialog_changed_or_not_foreground";
        int matched=0;
        EnumChildWindows(dialog,delegate(IntPtr child,IntPtr unused) {
            if(Pid(child)==(uint)pid && Class(child)=="Static" && IsWindowVisible(child)) {
                string text=ControlText(child);
                if(text==null) matched+=100;
                else if(text.Length>0) { if(text.Replace("\r\n","\n")==expectedBody) matched++; else matched+=100; }
            }
            return matched<100;
        },IntPtr.Zero);
        if(matched!=1 || GetDlgItem(dialog,buttonId)!=button || Pid(button)!=(uint)pid || Class(button)!="Button" || !IsWindowEnabled(button) || !IsWindowVisible(button) || ControlText(button)!=expectedButtonText) return "blocked:content_or_button_changed";
        if(InputDesktopBlock()!=null || GetForegroundWindow()!=dialog || !SameProcess(pid,ticks)) return "blocked:input_guard_changed";
        UIntPtr result;
        bool sent=SendMessageTimeout(button,245,UIntPtr.Zero,IntPtr.Zero,3,500,out result)!=IntPtr.Zero;
        return sent ? "BM_CLICK_returned;product_action_unverified" : "BM_CLICK_timed_out_or_failed;no_retry";
    }
    public static string Escape(int pid,long ticks,string signalPath,int holdMilliseconds) {
        if(holdMilliseconds<0 || holdMilliseconds>500) return "blocked:invalid_hold_milliseconds";
        string reason=EscBlock(pid,ticks); if(reason!=null) return "blocked:"+reason;
        if(!System.IO.File.Exists(signalPath)) return "blocked:driver_signal_removed";
        Input down=new Input {type=1}; down.data.keyboard.key=27;
        Input up=down; up.data.keyboard.flags=2;
        if(holdMilliseconds>0) {
            uint downInserted=0,upInserted=0; int downError=0,upError=0;
            double beforeReleaseMilliseconds=0;
            var held=Stopwatch.StartNew();
            try {
                downInserted=SendInput(1,new Input[] {down},Marshal.SizeOf(typeof(Input)));
                downError=Marshal.GetLastWin32Error();
                if(downInserted==1) System.Threading.Thread.Sleep(holdMilliseconds);
            } finally {
                beforeReleaseMilliseconds=held.Elapsed.TotalMilliseconds;
                // Releasing an injected held key must not depend on later focus,
                // process, signal, or desktop checks. Do not leave Esc held down.
                upInserted=SendInput(1,new Input[] {up},Marshal.SizeOf(typeof(Input)));
                upError=Marshal.GetLastWin32Error();
            }
            return "SendInput_down_inserted="+downInserted+"/1;keyup_inserted="+upInserted+"/1;hold_requested_ms="+holdMilliseconds+
                ";down_to_keyup_call_ms="+beforeReleaseMilliseconds.ToString("F3",System.Globalization.CultureInfo.InvariantCulture)+
                ";down_win32="+downError+";keyup_win32="+upError+";Excel_reception_and_cancellation_unverified";
        }
        uint inserted=0,release=0; int error=0;
        var immediate=Stopwatch.StartNew();
        try { inserted=SendInput(2,new Input[] {down,up},Marshal.SizeOf(typeof(Input))); error=Marshal.GetLastWin32Error(); }
        finally { if(inserted!=2) release=SendInput(1,new Input[] {up},Marshal.SizeOf(typeof(Input))); }
        return "SendInput_inserted="+inserted+"/2;fallback_keyup="+release+";win32="+error+
            ";hold_requested_ms=0;paired_input_call_ms="+immediate.Elapsed.TotalMilliseconds.ToString("F3",System.Globalization.CultureInfo.InvariantCulture)+
            ";Excel_reception_and_cancellation_unverified";
    }
}
'@

$writer=[IO.StreamWriter]::new([IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read),[Text.UTF8Encoding]::new($false))
$writer.AutoFlush=$true
function Write-ObserverEvent([string]$Event,$Data){
    $record=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');event=$Event;ownedPid=$OwnedPid;ownedProcessStartUtc=$ownedStartUtc.ToString('o');data=$Data}
    $writer.WriteLine(($record | ConvertTo-Json -Depth 8 -Compress))
}
function Product-Action($Dialog){
    if(@($Dialog.Controls | Where-Object {$_.ClassName -eq 'Static' -and $_.Visible -and $null -eq $_.Text}).Count -gt 0){return $null}
    $statics=@($Dialog.Controls | Where-Object {$_.ClassName -eq 'Static' -and $_.Visible -and -not [string]::IsNullOrEmpty($_.Text)})
    if($statics.Count -ne 1){return $null}
    $body=$statics[0].Text.Replace("`r`n","`n")
    $buttons=@($Dialog.Controls | Where-Object {$_.ClassName -eq 'Button' -and $_.Visible})
    $warningTitle=if($LegacyWording){'명단 비교 - 대량 작업'}else{'명단 비교 - 선택 범위 확인'}
    if(($Mode -eq 'AcceptLarge' -or $Mode -eq 'RejectLarge') -and $Dialog.Title -ceq $warningTitle){
        $number='(?:0|[1-9][0-9]{0,2}(?:,[0-9]{3})*)'
        $scan='\A선택한 셀이 많아 숨김 여부를 확인하는 데 시간이 걸릴 수 있습니다\.\n확인할 셀: '+$number+'개\n숨긴 셀과 필터로 가려진 셀은 비교에서 뺍니다\.\n이 시험 버전에서는 Esc를 눌러도 작업이 취소되지 않을 수 있습니다\.\n계속할까요\? 범위를 줄이려면 \[아니요\]를 누르세요\.\z'
        $large='\A선택한 값을 읽고 결과를 만드는 데 시간이 걸릴 수 있습니다\.\n이번에 선택한 범위: 숨기지 않은 셀 '+$number+'개 / '+$number+'개 영역\n이번 작업에서 다룰 셀: '+$number+'개\n이 시험 버전에서는 Esc를 눌러도 작업이 취소되지 않을 수 있습니다\.\n계속할까요\? 범위를 줄이려면 \[아니요\]를 누르세요\.\z'
        if($LegacyWording){
            $scan='\A선택 범위의 가시성을 확인하는 데 시간이 걸릴 수 있습니다\.\n확인 대상: '+$number+'셀\n필터/숨김 확인 후 보이는 셀만 읽습니다\.\n값 읽기·비교를 계속할까요\? \[아니요\]가 기본입니다\.\z'
            $large='\A읽기·비교·결과 출력에 시간이 걸릴 수 있습니다\.\n이번 선택: 보이는 '+$number+'셀 / '+$number+'개 영역\n전체 처리 규모: '+$number+'셀\n계속할까요\? 실행 중 Esc로 취소할 수 있습니다\.\z'
        }
        if($buttons.Count -eq 2 -and @($buttons | Where-Object {$_.Id -eq 6 -and $_.Enabled}).Count -eq 1 -and @($buttons | Where-Object {$_.Id -eq 7 -and $_.Enabled}).Count -eq 1 -and ($body -cmatch $scan -or $body -cmatch $large)){
            if($Mode -eq 'RejectLarge'){return [pscustomobject]@{button=@($buttons | Where-Object {$_.Id -eq 7})[0];body=$body;kind='reject_exact_product_warning'}}
            return [pscustomobject]@{button=@($buttons | Where-Object {$_.Id -eq 6})[0];body=$body;kind='accept_exact_product_warning'}
        }
    }
    # RC7 runtime exposed an OK-only product MsgBox with ID 2 and text 확인.
    # The body remains exactly allowlisted; arbitrary Cancel buttons are excluded.
    if($Mode -eq 'DismissResult' -and $Dialog.Title -ceq '명단 비교' -and $buttons.Count -eq 1 -and $buttons[0].Enabled -and ($buttons[0].Id -eq 1 -or ($buttons[0].Id -eq 2 -and $buttons[0].Text -ceq '확인'))){
        $allowed=$body -ceq '작업을 취소했습니다. 담아 둔 첫 번째 목록이 있다면 그대로 남아 있습니다.'
        if(-not $LegacyWording -and $body -ceq "선택한 셀에 비교할 값이 없습니다.`n숨긴 셀, 필터로 가려진 셀, 빈칸, 오류 셀, 표의 제목·합계 셀은 비교에서 뺍니다.`n담아 둔 첫 번째 목록이 있다면 그대로 남아 있습니다."){$allowed=$true}
        $preservation='담아 둔 첫 번째 목록과 원본 내용은 바뀌지 않았습니다.'
        $known=@{
            '작업 시간이 길어져 중단했습니다. 선택 범위를 줄여 다시 실행해 주세요.'=-2147219401
            '따로 선택한 영역이 5,000개를 넘습니다. 선택 범위를 줄여 주세요.'=-2147219403
            "숨김 여부를 확인할 셀이 2,000,000개를 넘습니다.`n행이나 열 전체를 선택했다면 값이 있는 부분만 다시 선택해 주세요."=-2147219403
            '선택한 범위가 5,000개가 넘는 영역으로 나뉘어 있습니다. 선택 범위를 줄여 주세요.'=-2147219403
            '비교할 셀이 5,000개가 넘는 영역에 나뉘어 있습니다. 선택 범위를 줄여 주세요.'=-2147219403
            "한 목록에 담을 수 있는 셀은 100,000개까지입니다. 선택 범위를 줄여 주세요.`n빈칸도 이 개수에 포함합니다. 숨긴 셀과 필터로 가려진 셀은 세지 않습니다."=-2147219403
            '선택한 셀의 내용을 모두 합치면 5,000,000자를 넘습니다. 선택 범위를 줄여 주세요.'=-2147219403
            '선택한 범위에 병합된 셀이 있습니다. 병합된 셀을 빼고 다시 선택해 주세요.'=-2147219402
            '병합된 셀은 비교할 수 없습니다. 병합되지 않은 셀을 선택해 주세요.'=-2147219402
            '어떤 셀이 숨겨져 있는지 확인하지 못했습니다. 선택 범위를 줄여 다시 실행해 주세요.'=-2147219402
        }
        if($LegacyWording){
            $allowed=$body -ceq '작업을 취소했습니다. 담아 둔 첫 번째 목록은 유지됩니다.'
            $preservation='담아 둔 첫 번째 목록과 원본 데이터는 변경하지 않았습니다.'
            $known=@{'지연 보호 한도(활성 처리 약 30초)에 도달해 중단했습니다. 범위를 줄여 주세요.'=-2147219401}
        }
        foreach($message in $known.Keys){
            $expected=$message+"`n`n"+$preservation+"`n오류 코드: "+$known[$message]
            if($body -ceq $expected){$allowed=$true;break}
        }
        if(-not $LegacyWording -and $body -cmatch '\A[A-Z]{1,3}[1-9][0-9]{0,6} 셀의 내용이 4,096자를 넘습니다\. 이 셀을 빼고 다시 선택해 주세요\.\n\n담아 둔 첫 번째 목록과 원본 내용은 바뀌지 않았습니다\.\n오류 코드: -2147219403\z'){$allowed=$true}
        if($allowed){return [pscustomobject]@{button=$buttons[0];body=$body;kind='dismiss_exact_product_result'}}
    }
    return $null
}
$timer=[Diagnostics.Stopwatch]::StartNew()
$seen=@{};$attempted=@{};$signalObserved=$false;$escReadyAt=$null;$escFinished=$false;$escAttempted=$false;$lastEscBlock=$null
try{
    Write-ObserverEvent 'observer_started' ([ordered]@{mode=$Mode;legacyWording=[bool]$LegacyWording;timeoutSeconds=$TimeoutSeconds;pollMilliseconds=$PollMilliseconds;escDelayMilliseconds=$EscDelayMilliseconds;escHoldMilliseconds=$EscHoldMilliseconds;signalPath=$signal;observerStartedUtc=$observerStartedUtc.ToString('o');nativeInputReception='not_measured';desktopCheck=[SlcDialogObserverNative]::InputDesktopBlock()})
    while($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds){
        if(-not [SlcDialogObserverNative]::SameProcess($OwnedPid,$ownedStartTicks)){Write-ObserverEvent 'owned_process_exited_or_changed' @{};break}
        $dialogs=@([SlcDialogObserverNative]::Dialogs($OwnedPid))
        foreach($dialog in $dialogs){
            $snapshot=$dialog | ConvertTo-Json -Depth 6 -Compress
            $key=[string]$dialog.Hwnd
            if(-not $seen.ContainsKey($key) -or $seen[$key] -cne $snapshot){Write-ObserverEvent 'dialog_observed' $dialog;$seen[$key]=$snapshot}
            if($Mode -eq 'Observe'){continue}
            $action=Product-Action $dialog
            if($null -eq $action -or $attempted.ContainsKey($snapshot)){continue}
            $outcome=[SlcDialogObserverNative]::Click($OwnedPid,$ownedStartTicks,$dialog.Hwnd,$action.button.Hwnd,$action.button.Id,$dialog.Title,$action.body,$action.button.Text)
            # A blocked precondition is observable again. An actual send is never retried.
            if(-not $outcome.StartsWith('blocked:')){$attempted[$snapshot]=$true}
            if(-not $seen.ContainsKey('action:'+ $snapshot) -or $seen['action:'+ $snapshot] -cne $outcome){Write-ObserverEvent 'product_button_action' @{kind=$action.kind;dialogHwnd=$dialog.Hwnd;buttonId=$action.button.Id;outcome=$outcome};$seen['action:'+ $snapshot]=$outcome}
        }
        if($EscDelayMilliseconds -ge 0 -and -not $escFinished){
            if(-not $signalObserved -and [IO.File]::Exists($signal)){
                $info=Get-Item -LiteralPath $signal
                if($info.LastWriteTimeUtc -lt $observerStartedUtc -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)){
                    Write-ObserverEvent 'esc_disarmed_invalid_start_signal' @{reason='stale_or_reparse_signal'};$escFinished=$true
                }else{$signalObserved=$true;Write-ObserverEvent 'driver_processing_start_signal_observed' @{path=$signal;driverClaimOnly=$true}}
            }
            if($signalObserved -and -not $escFinished){
                if(-not [IO.File]::Exists($signal)){
                    Write-ObserverEvent 'esc_disarmed_driver_signal_removed' @{};$escFinished=$true;continue
                }
                $block=[SlcDialogObserverNative]::EscBlock($OwnedPid,$ownedStartTicks)
                if($null -eq $block){
                    if($null -eq $escReadyAt){$escReadyAt=$timer.Elapsed.TotalMilliseconds;Write-ObserverEvent 'esc_delay_started' @{delayMilliseconds=$EscDelayMilliseconds;modalFreeObserved=$true}}
                    if(($timer.Elapsed.TotalMilliseconds-$escReadyAt) -ge $EscDelayMilliseconds){
                        $outcome=[SlcDialogObserverNative]::Escape($OwnedPid,$ownedStartTicks,$signal,$EscHoldMilliseconds)
                        if(-not $outcome.StartsWith('blocked:')){$escFinished=$true;$escAttempted=$true}
                        Write-ObserverEvent 'esc_input_attempt' @{outcome=$outcome;ExcelReceptionVerified=$false;cancellationVerified=$false;foregroundRaceCannotBeExcluded=$true}
                    }
                }elseif($block -cne $lastEscBlock){Write-ObserverEvent 'esc_input_blocked' @{reason=$block};$lastEscBlock=$block}
            }
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    Write-ObserverEvent 'observer_finished' @{elapsedSeconds=$timer.Elapsed.TotalSeconds;timedOut=($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds);escAttempted=$escAttempted;escFinishedOrDisarmed=$escFinished;signalObserved=$signalObserved;productOutcome='not_inferred_from_UI_input'}
}catch{Write-ObserverEvent 'observer_error' @{message=$_.Exception.Message};throw}
finally{$writer.Dispose();$owned.Dispose()}
