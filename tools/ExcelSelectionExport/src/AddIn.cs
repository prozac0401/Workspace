using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Reflection;
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]
[assembly: ComVisible(false)]
namespace ExcelSelectionExport {
 [ComVisible(true), Guid("B65AD801-ABAF-11D0-BB8B-00A0C90F2744"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
 public interface IDTExtensibility2 {
  [DispId(1)] void OnConnection([MarshalAs(UnmanagedType.IDispatch)] object application, int connectMode, [MarshalAs(UnmanagedType.IDispatch)] object addInInst, [In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom);
  [DispId(2)] void OnDisconnection(int removeMode, [In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom);
  [DispId(3)] void OnAddInsUpdate([In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom);
  [DispId(4)] void OnStartupComplete([In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom);
  [DispId(5)] void OnBeginShutdown([In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom);
 }
 [ComVisible(true), Guid("000C0396-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
 public interface IRibbonExtensibility { [DispId(1)] string GetCustomUI(string ribbonId); }
 [ComVisible(true), Guid("5AA04C49-1739-4704-A1CE-09E5B10A44A2"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
 public interface ICallbacks {
  [DispId(10)] void Export([MarshalAs(UnmanagedType.IDispatch)] object control);
  [DispId(11)] void RibbonLoaded([MarshalAs(UnmanagedType.IDispatch)] object ribbon);
  [DispId(12)] string GetDiagnostics();
  [DispId(13)] string GetLastError();
 }
 [ComVisible(true), Guid("2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1"), ProgId("Workspace.ExcelSelectionExport"), ClassInterface(ClassInterfaceType.None), ComDefaultInterface(typeof(ICallbacks))]
 public sealed class AddIn : StandardOleMarshalObject, IDTExtensibility2, IRibbonExtensibility, ICallbacks {
  private object application; private object ribbon; private object addinInstance; private int clicks; private bool connected; private bool busy; private string outcome="none"; private string lastError="";
  private System.Windows.Forms.Timer resultTimer; private object resultWindow;
  private System.Windows.Forms.Timer exportTimer; private ExportEngine.PreparedMenuExport pendingExport;
  public void OnConnection(object app, int mode, object instance, [In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom) { application=app; addinInstance=instance; connected=true; ((dynamic)instance).Object=this; }
  public void OnDisconnection(int mode, [In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom) { Disconnect(); }
  public void OnAddInsUpdate([In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom) { }
  public void OnStartupComplete([In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom) { }
  public void OnBeginShutdown([In, Out, MarshalAs(UnmanagedType.SafeArray, SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom) { Disconnect(); }
  private void Disconnect() {
   connected=false;
   CancelPreparedExport();
   CancelResultDisplay();
   object instance=addinInstance; addinInstance=null;
   object oldRibbon=ribbon; ribbon=null; object oldApplication=application; application=null;
   try { if(instance!=null) ((dynamic)instance).Object=null; }
   catch(COMException) {}
   catch(InvalidComObjectException) {}
   finally { Release(oldRibbon); Release(instance); Release(oldApplication); }
  }
  private static void Release(object value) {if(value!=null && Marshal.IsComObject(value))try{Marshal.ReleaseComObject(value);}catch(InvalidComObjectException){}}
  public void RibbonLoaded(object value) { ribbon=value; }
  public string GetDiagnostics() { return "stage=Export;connected="+connected+";ribbon="+(ribbon!=null)+";clicks="+clicks+";bitness="+(IntPtr.Size*8)+";outcome="+outcome+";busy="+busy; }
  public string GetLastError() { return lastError; }
  private sealed class ExcelWindow : IWin32Window {
   private readonly IntPtr handle;
   public ExcelWindow(object app) { handle=new IntPtr(Convert.ToInt64(((dynamic)app).Hwnd)); }
   public IntPtr Handle { get { return handle; } }
  }
  public string GetCustomUI(string ribbonId) {
   return "<customUI xmlns='http://schemas.microsoft.com/office/2009/07/customui' onLoad='RibbonLoaded'><contextMenus>"+
    "<contextMenu idMso='ContextMenuCell'><menu id='WorkspaceSelectionExportCell' label='선택범위 내보내기'><button id='WorkspaceSelectionExportNew' label='새 Excel로' onAction='Export'/></menu></contextMenu>"+
    "<contextMenu idMso='ContextMenuListRange'><menu id='WorkspaceSelectionExportTable' label='선택범위 내보내기'><button id='WorkspaceSelectionExportTableNew' label='새 Excel로' onAction='Export'/></menu></contextMenu></contextMenus></customUI>";
  }
  public void Export(object control) {
   if (!connected || application==null || busy) return;
   clicks++; busy=true; outcome="running"; lastError="";
   try { SchedulePreparedExport(ExportEngine.PrepareMenu(application)); }
   catch(OperationCanceledException) { outcome="canceled"; }
   catch(Exception ex) {
    outcome="error:"+ex.GetType().Name; lastError=ex.ToString();
    string message=ex is InvalidOperationException ? ex.Message : "내보내기를 완료하지 못했습니다. 원본을 그대로 두었습니다. Excel에서 진행 중인 작업을 마친 뒤 다시 시도해 주세요. ("+ex.HResult.ToString("X8")+")";
    MessageBox.Show(new ExcelWindow(application),message,"선택범위 내보내기",MessageBoxButtons.OK,MessageBoxIcon.Information);
   }
   finally { if(exportTimer==null && resultTimer==null) busy=false; }
  }
  private void SchedulePreparedExport(ExportEngine.PreparedMenuExport prepared) {
   pendingExport=prepared;
   try {
    exportTimer=new System.Windows.Forms.Timer(); exportTimer.Interval=50;
    exportTimer.Tick+=RunPreparedExport;
    outcome="run-pending"; exportTimer.Start();
   } catch { CancelPreparedExport(); throw; }
  }
  private void StopExportTimer() {
   var timer=exportTimer; exportTimer=null;
   if(timer==null) return;
   timer.Stop(); timer.Tick-=RunPreparedExport; timer.Dispose();
  }
  private void CancelPreparedExport() {
   var prepared=pendingExport; pendingExport=null;
   try { StopExportTimer(); }
   finally { if(prepared!=null) {prepared.Dispose();outcome="canceled:disconnected";} busy=false; }
  }
  private void RunPreparedExport(object sender,EventArgs args) {
   var prepared=pendingExport; pendingExport=null;
   try {
    StopExportTimer();
    if(prepared==null || !connected || application==null) return;
    outcome="running";
    object window=prepared.Run();
    if(!connected || application==null) {Release(window);outcome="display-canceled:disconnected";return;}
    ScheduleResultDisplay(window);
   } catch(OperationCanceledException) {outcome="canceled";}
   catch(Exception ex) {
    outcome="error:"+ex.GetType().Name; lastError=ex.ToString();
    if(connected && application!=null) {
     string message=ex is InvalidOperationException ? ex.Message : "내보내기를 완료하지 못했습니다. 원본을 그대로 두었습니다. 진행 중인 작업을 마친 뒤 다시 시도해 주세요. ("+ex.HResult.ToString("X8")+")";
     try {MessageBox.Show(new ExcelWindow(application),message,"선택범위 내보내기",MessageBoxButtons.OK,MessageBoxIcon.Information);}
     catch(Exception noticeError) {lastError+="\n오류 안내 실패: "+noticeError.ToString();}
    }
   } finally {
    if(prepared!=null) prepared.Dispose();
    if(resultTimer==null) busy=false;
   }
  }
  private void ScheduleResultDisplay(object window) {
   if(window==null) throw new InvalidOperationException("새 통합문서의 결과 창을 확인하지 못했습니다.");
   resultWindow=window;
   try {
    resultTimer=new System.Windows.Forms.Timer();
    resultTimer.Interval=50;
    resultTimer.Tick+=ActivateResultWindow;
    outcome="display-pending";
    resultTimer.Start();
   } catch(Exception ex) { CancelResultDisplay(); throw new InvalidOperationException("새 통합문서는 만들어졌지만 결과 창 표시를 예약하지 못했습니다. Excel의 창 목록에서 결과를 확인해 주세요.",ex); }
  }
  private void StopResultTimer() {
   var timer=resultTimer; resultTimer=null;
   if(timer==null) return;
   timer.Stop(); timer.Tick-=ActivateResultWindow; timer.Dispose();
  }
  private void CancelResultDisplay() {
   object window=resultWindow; resultWindow=null;
   try { StopResultTimer(); if(window!=null) outcome="display-canceled:disconnected"; }
   finally { Release(window); busy=false; }
  }
  [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
  private void ActivateResultWindow(object sender,EventArgs args) {
   object window=resultWindow; resultWindow=null;
   try {
    StopResultTimer();
    if(window==null) return;
    if(!connected || application==null) {outcome="display-canceled:disconnected";return;}
    ((dynamic)window).Activate();
    // Template loading and closing the progress dialog can leave the source SDI
    // window in front even after Excel accepts Activate. Raise the exact result
    // window on the deferred UI callback (never an arbitrary Excel process).
    if(Marshal.IsComObject(window)) {
     long expectedHandle=Convert.ToInt64(((dynamic)window).Hwnd);
     SetForegroundWindow(new IntPtr(expectedHandle));
     object activeWindow=((dynamic)application).ActiveWindow;
     try {
      if(activeWindow==null || Convert.ToInt64(((dynamic)activeWindow).Hwnd)!=expectedHandle)
       throw new InvalidOperationException("새 통합문서가 활성 창으로 전환되지 않았습니다.");
     } finally {Release(activeWindow);}
    }
    outcome="success";
   } catch(Exception ex) {
    outcome="display-error:"+ex.GetType().Name; lastError=ex.ToString();
    if(connected && application!=null) {
     try { MessageBox.Show(new ExcelWindow(application),"내보낸 새 통합문서는 만들어졌지만 결과 창으로 전환하지 못했습니다. Excel의 창 목록에서 결과 통합문서를 확인해 주세요.","선택범위 내보내기",MessageBoxButtons.OK,MessageBoxIcon.Information); }
     catch(Exception noticeError) {lastError+="\n표시 오류 안내 실패: "+noticeError.ToString();}
    }
   } finally {Release(window);busy=false;}
  }
 }
}
