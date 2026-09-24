using System;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Windows.Forms;
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]
[assembly: ComVisible(false)]
namespace VisibleCellsPaste {
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

[ComVisible(true),Guid("4CA82BBA-721E-4629-9678-B439B70C2AAF"),InterfaceType(ComInterfaceType.InterfaceIsDual)]
public interface ICallbacks {
[DispId(10)] void Paste(object control); [DispId(11)] void Undo(object control); [DispId(12)] string GetDiagnostics();
}
[ComVisible(true),Guid("856B2219-6225-42ED-8FF1-2D06E5913AC8"),ProgId("Workspace.VisibleCellsPaste"),ClassInterface(ClassInterfaceType.None),ComDefaultInterface(typeof(ICallbacks))]
public sealed class AddIn : StandardOleMarshalObject, IDTExtensibility2, IRibbonExtensibility, ICallbacks {
private object application; private bool connected; private int clicks; private ExcelEngine engine; private bool busy; private string outcome="idle"; private System.Windows.Forms.Timer timer; private PreparedPaste pending;
public void OnConnection(object app,int mode,object instance,[In,Out,MarshalAs(UnmanagedType.SafeArray,SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom) {if(connected||engine!=null)Disconnect();application=app;try{engine=new ExcelEngine(app);((dynamic)instance).Object=this;connected=true;}catch{Disconnect();throw;}}
public void OnDisconnection(int mode,[In,Out,MarshalAs(UnmanagedType.SafeArray,SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom) {Disconnect();}
public void OnAddInsUpdate([In,Out,MarshalAs(UnmanagedType.SafeArray,SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom){}
public void OnStartupComplete([In,Out,MarshalAs(UnmanagedType.SafeArray,SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom){}
public void OnBeginShutdown([In,Out,MarshalAs(UnmanagedType.SafeArray,SafeArraySubType=VarEnum.VT_VARIANT)] ref Array custom){Disconnect();}
public string GetCustomUI(string id) {return "<customUI xmlns='http://schemas.microsoft.com/office/2009/07/customui'><contextMenus><contextMenu idMso='ContextMenuCell'><button id='VCPVisibleCellsPastePasteCellV1' insertBeforeMso='Cut' tag='VCP.VisibleCellsPaste.Paste.v1' label='보이는 칸에 붙여넣기' onAction='Paste'/><button id='VCPVisibleCellsPasteUndoCellV1' insertBeforeMso='Cut' tag='VCP.VisibleCellsPaste.Undo.v1' label='마지막 붙여넣기 되돌리기' onAction='Undo'/></contextMenu><contextMenu idMso='ContextMenuListRange'><button id='VCPVisibleCellsPastePasteTableV1' insertBeforeMso='Cut' tag='VCP.VisibleCellsPaste.Paste.v1' label='보이는 칸에 붙여넣기' onAction='Paste'/><button id='VCPVisibleCellsPasteUndoTableV1' insertBeforeMso='Cut' tag='VCP.VisibleCellsPaste.Undo.v1' label='마지막 붙여넣기 되돌리기' onAction='Undo'/></contextMenu></contextMenus></customUI>";}
public void Paste(object control){
 if(!connected||busy)return;busy=true;clicks++;
 try {var source=ClipboardReader.ReadSnapshot(Convert.ToInt32(((dynamic)application).CutCopyMode));pending=engine.Prepare(source);
 if(pending.Formulas>0||pending.Clears>0||pending.Plan.RequiresSizeConfirmation) {string msg="보이는 "+pending.Before.Length+"칸에 복사한 순서대로 입력합니다.\n기존 수식 "+pending.Formulas+"개가 값으로 바뀌고, 내용이 있는 "+pending.Clears+"칸이 빈칸으로 지워집니다.\n복사한 순서대로 입력합니다. 이름이나 사번을 찾아 연결하지 않습니다. 원본과 대상의 개수가 같아도 사람의 순서까지 일치한다는 뜻은 아닙니다.";if(MessageBox.Show(new Owner(application),msg,"보이는 칸 붙여넣기",MessageBoxButtons.OKCancel,MessageBoxIcon.Warning)!=DialogResult.OK){pending=null;busy=false;return;}}
 timer=new System.Windows.Forms.Timer();timer.Interval=50;timer.Tick+=RunPending;timer.Start();outcome="pending";
 }catch(Exception e){pending=null;busy=false;Notice(e);}
}
public void Undo(object control){if(!connected||busy)return;busy=true;try{engine.UndoLast();outcome="undone";ShowStatus("마지막 붙여넣기를 되돌렸습니다.");}catch(Exception e){Notice(e);}finally{busy=false;}}
public string GetDiagnostics(){return "stage=M2;connected="+connected+";clicks="+clicks+";bitness="+(IntPtr.Size*8)+";outcome="+outcome+";engine="+(engine==null?"none":engine.LastOutcome);}

private sealed class Owner:IWin32Window {readonly IntPtr hwnd;public Owner(object a){hwnd=new IntPtr(Convert.ToInt64(((dynamic)a).Hwnd));}public IntPtr Handle{get{return hwnd;}}}
private void Disconnect(){
 connected=false;
 try {
  if(timer!=null){timer.Stop();timer.Dispose();timer=null;}
  if(statusTimer!=null){statusTimer.Stop();statusTimer.Dispose();statusTimer=null;RestoreStatus();}
 }finally{
  pending=null;
  try{if(engine!=null)engine.Dispose();}
  finally{engine=null;application=null;busy=false;}
 }
}
private void RunPending(object sender,EventArgs args){timer.Stop();timer.Dispose();timer=null;var work=pending;pending=null;try{if(work==null||!connected)return;if(work.Plan.RequiresSizeConfirmation){using(var progress=new ProgressDialog()){Exception failure=null;progress.Shown+=delegate{progress.BeginInvoke((Action)delegate{try{engine.Apply(work,delegate{Application.DoEvents();return progress.Canceled;},delegate(string text){progress.SetStage(text);});}catch(Exception e){failure=e;}finally{progress.Finish();}});};progress.ShowDialog(new Owner(application));if(failure!=null)throw failure;}}else engine.Apply(work,null,null);outcome="success";ShowStatus("보이는 "+engine.LastCount+"칸에 붙여넣었습니다.");}catch(Exception e){Notice(e);}finally{busy=false;}}
private string BuildNoticeMessage(Exception error){
 if(error is ValidationException)return error.Message;
 string state=engine==null?null:engine.LastOutcome;
 string detail=engine==null?null:engine.RecoveryDetail;
 if((engine!=null&&engine.RecoveryRequired)||state=="recovery-required"||state=="state-restore-failed"||error is RecoveryException)
  return "복구를 끝까지 확인하지 못했습니다. 후속 쓰기를 차단했습니다. 셀 내용과 Excel 상태를 확인해 주세요.\n"+(detail??error.Message)+"\n오류 코드: "+error.HResult.ToString("X8");
 if(error is InvalidOperationException)return error.Message;
 string message;
 if(state=="success")message="마지막 붙여넣기는 완료된 상태입니다. 추가 오류가 발생했으므로 셀 내용을 확인해 주세요.";
 else if(state=="undone")message="마지막 붙여넣기는 되돌린 상태입니다. 추가 오류가 발생했으므로 셀 내용을 확인해 주세요.";
 else if(state=="rolled-back")message="붙여넣기 변경 내용을 작업 전 상태로 되돌렸습니다.";
 else if(state=="no-change"||state=="idle")message="쓰기 전 검사를 완료하지 못했습니다. 변경된 셀은 없습니다.";
 else message="실행 결과를 확인하지 못했습니다. 셀 내용을 확인해 주세요.";
 return message+"\n오류 코드: "+error.HResult.ToString("X8");
}
private void Notice(Exception error){outcome=error is RecoveryException||(engine!=null&&engine.RecoveryRequired)?"recovery-required":"error";MessageBox.Show(new Owner(application),BuildNoticeMessage(error),"보이는 칸 붙여넣기",MessageBoxButtons.OK,MessageBoxIcon.Information);}
private System.Windows.Forms.Timer statusTimer;private object oldStatus;private string ownStatus;
private void ShowStatus(string text){
 // Success feedback is best effort and must never turn a completed write/undo into a failure notice.
 try{if(statusTimer!=null){statusTimer.Stop();statusTimer.Dispose();statusTimer=null;RestoreStatus();}oldStatus=((dynamic)application).StatusBar;ownStatus=text;((dynamic)application).StatusBar=text;statusTimer=new System.Windows.Forms.Timer();statusTimer.Interval=2500;statusTimer.Tick+=delegate{statusTimer.Stop();statusTimer.Dispose();statusTimer=null;RestoreStatus();};statusTimer.Start();}
 catch(Exception){
  if(statusTimer!=null){try{statusTimer.Stop();statusTimer.Dispose();}catch(Exception){}statusTimer=null;}
  try{RestoreStatus();}catch(Exception){}ownStatus=null;
 }
}
private void RestoreStatus(){try{if(application!=null&&Object.Equals((object)((dynamic)application).StatusBar,ownStatus))((dynamic)application).StatusBar=oldStatus;}catch(COMException){}catch(InvalidComObjectException){}ownStatus=null;}

}
}
