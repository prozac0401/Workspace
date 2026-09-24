using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace VisibleCellsPaste {
 public sealed class CellState {
  public int Row; public int Column; public string Address; public bool Formula; public string FormulaProperty; public object FormulaValue; public object Format; public CellValue Value;
 }
 public sealed class PreparedPaste {
  public object Book, Sheet, Selection; public string Address, SheetName; public PastePlan Plan; public CellState[] Before; public int Formulas, Clears;
 }
 public sealed class RecoveryException : Exception {
  public readonly string[] FailedAddresses; public readonly string OriginalCode; public readonly string[] RecoveryCodes;
  public RecoveryException(string original,List<string> addresses,List<string> codes):base("일부 셀의 복구를 확인하지 못했습니다. 자동 저장하지 않았습니다. 영향 가능 범위와 복구 실패 주소를 확인해 주세요.") {OriginalCode=original;FailedAddresses=addresses.ToArray();RecoveryCodes=codes.ToArray();}
 }
 public sealed class ExcelEngine : IDisposable {
  readonly dynamic app; readonly UndoEpoch epoch; bool busy; PreparedPaste undo; CellState[] after; long undoEpoch; string undoCommand; bool undoAllowed;
  public bool RecoveryRequired {get;private set;} public string RecoveryDetail {get;private set;}
  public string LastOutcome {get;private set;} public int LastCount {get;private set;}
#if VCP_TESTING
  public int FailAfterWrites=-1, FailRecoveryAt=-1; public bool CancelAfterWrite;
#endif
  public ExcelEngine(object application) {app=application;epoch=new UndoEpoch(application);LastOutcome="idle";}
  public void Dispose(){epoch.Dispose();undo=null;after=null;}
  static ValidationException Reject(string code,string message){return new ValidationException(code,message+"\n변경된 셀은 없습니다.");}
  public static bool Same(object a,object b) {
   if(a==null||b==null)return false; if(!Marshal.IsComObject(a)||!Marshal.IsComObject(b))return Object.ReferenceEquals(a,b);
   IntPtr p=Marshal.GetIUnknownForObject(a);try{IntPtr q=Marshal.GetIUnknownForObject(b);try{return p==q;}finally{Marshal.Release(q);}}finally{Marshal.Release(p);}
  }
  static object At(object value,int index) {var a=value as Array;return a==null?value:a.GetValue(a.GetLowerBound(0)+index,a.GetLowerBound(1));}
  public static CellValue ReadValue(object value) {
   if(value==null||value is DBNull)return CellValue.Empty();
   var error=value as ErrorWrapper;if(error!=null)return CellValue.Error(error.ErrorCode & 0xffff);
   if(value is int && (int)value<0)return CellValue.Error((int)value & 0xffff);
   if(value is string)return CellValue.Text((string)value);if(value is bool)return CellValue.Boolean((bool)value);
   return CellValue.Number(Convert.ToDouble(value,System.Globalization.CultureInfo.InvariantCulture));
  }
  public static CellState ReadCell(dynamic sheet,int row,int col) {
   dynamic c=sheet.Cells[row,col];try {var s=new CellState{Row=row,Column=col,Address=(string)c.Address,Format=c.NumberFormat,Formula=Convert.ToBoolean(c.HasFormula),Value=ReadValue((object)c.Value2)};
    if(s.Formula){try{s.FormulaValue=c.Formula2;s.FormulaProperty="Formula2";}catch(COMException){s.FormulaValue=c.Formula;s.FormulaProperty="Formula";}}
    return s;
   }finally{Release(c);}
  }
  public static void Release(object obj){if(obj!=null&&Marshal.IsComObject(obj))try{Marshal.ReleaseComObject(obj);}catch(InvalidComObjectException){}}
  static bool HasAnyFormula(dynamic range) {object v=range.HasFormula;return !(v is bool && !(bool)v);}
  bool Intersects(object left,object right){object r=app.Intersect(left,right);try{return r!=null;}finally{Release(r);}}
  void GuardTable(dynamic sheet,dynamic selection) {
   foreach(dynamic table in sheet.ListObjects) {
    dynamic body=table.DataBodyRange; if(Intersects(table.Range,selection)) {
     if(body==null)throw Reject("VCP-TABLE-EMPTY","빈 표의 헤더에는 붙여넣을 수 없습니다.");
     if(Intersects(table.HeaderRowRange,selection))throw Reject("VCP-TABLE-HEADER","표 헤더는 지원하지 않습니다.");
     if((bool)table.ShowTotals && Intersects(table.TotalsRowRange,selection))throw Reject("VCP-TABLE-TOTAL","표 합계 행은 지원하지 않습니다.");
     foreach(dynamic column in table.ListColumns)if(Intersects(column.Range,selection)&&HasAnyFormula(column.DataBodyRange))throw Reject("VCP-TABLE-FORMULA","수식이 포함된 표 열은 숨긴 행을 포함해 지원하지 않습니다.");
    }
   }
   foreach(dynamic pivot in sheet.PivotTables())if(Intersects(pivot.TableRange2,selection))throw Reject("VCP-PIVOT","피벗 결과 셀은 지원하지 않습니다.");
  }
  void GuardProtectedView() {
   object protectedWindow=app.ActiveProtectedViewWindow;
   try{if(protectedWindow!=null)throw Reject("VCP-PROTECTED-VIEW","제한된 보기에서는 실행할 수 없습니다.");}finally{Release(protectedWindow);}
  }
  public PreparedPaste Prepare(ClipboardSnapshot source) {
   if(busy)throw Reject("VCP-BUSY","이미 작업 중입니다.");if(RecoveryRequired)throw Reject("VCP-RECOVERY-REQUIRED","복구 확인이 필요합니다. 이 Excel에서 후속 쓰기를 차단했습니다.");
   // Protected View can reject even StatusBar access; identify it before selection or presentation access.
   GuardProtectedView();
   object previous=app.StatusBar;try{app.StatusBar="보이는 칸 붙여넣기 · 검사 중";return PrepareCore(source);}finally{app.StatusBar=previous;}
  }
  private PreparedPaste PrepareCore(ClipboardSnapshot source) {
   dynamic selected=app.Selection; dynamic sheet,book;
   try{sheet=selected.Worksheet;book=sheet.Parent;}catch{throw Reject("VCP-SELECTION","워크시트의 한 열 범위를 선택해 주세요.");}
   if(Convert.ToBoolean(book.ReadOnly))throw Reject("VCP-READONLY","읽기 전용 파일은 지원하지 않습니다.");
   if(Convert.ToBoolean(sheet.ProtectContents)||Convert.ToBoolean(sheet.ProtectDrawingObjects)||Convert.ToBoolean(sheet.ProtectScenarios))throw Reject("VCP-PROTECTED","보호된 시트는 지원하지 않습니다.");
   if((int)app.ActiveWindow.SelectedSheets.Count!=1)throw Reject("VCP-GROUPED","여러 시트를 그룹 선택한 상태는 지원하지 않습니다.");
   long count=Convert.ToInt64(selected.CountLarge);int cols=(int)selected.Columns.Count,areas=(int)selected.Areas.Count;
   int first=(int)selected.Row,col=(int)selected.Column,last=first+(int)selected.Rows.Count-1;
   if(areas!=1||cols!=1||count>=Limits.ExcelRows||count>Limits.MaxSelectionCells)throw Reject("VCP-SELECTION-SHAPE","연속된 한 열의 최대 200,000칸을 선택해 주세요. 전체 행·열과 직접 만든 다중 선택은 지원하지 않습니다.");
   if(Convert.ToBoolean(selected.EntireColumn.Hidden))throw Reject("VCP-HIDDEN-COLUMN","선택한 열이 숨겨져 있습니다.");
   try{if(Convert.ToBoolean(book.MultiUserEditing))throw Reject("VCP-SHARED","공유 통합문서는 지원하지 않습니다.");}catch(COMException){}
   dynamic visible;try{visible=selected.SpecialCells(12);}catch(COMException){throw Reject("VCP-NO-VISIBLE","선택한 범위에 보이는 칸이 없습니다.");}
   dynamic clipped=app.Intersect(selected,visible);if(clipped==null)throw Reject("VCP-NO-VISIBLE","선택한 범위에 보이는 칸이 없습니다.");
   if((int)clipped.Areas.Count>Limits.MaxSegments)throw Reject("VCP-SEGMENT-LIMIT","보이는 연속 구간은 최대 20,000개입니다.");
   var targets=new List<TargetCell>();string sheetKey=Guid.NewGuid().ToString("N");
   foreach(dynamic area in clipped.Areas) {
    if(!Same((object)area.Worksheet,(object)sheet))throw Reject("VCP-BOUNDARY","대상 워크시트가 달라졌습니다.");
    if(Convert.ToInt64(area.CountLarge)+targets.Count>Limits.MaxItems)throw Reject("VCP-ITEM-LIMIT","보이는 칸은 최대 50,000개입니다.");
    int start=(int)area.Row,end=start+(int)area.Rows.Count-1;
    if((int)area.Column!=col||(int)area.Columns.Count!=1||start<first||end>last)throw Reject("VCP-BOUNDARY","선택 밖의 셀이 감지됐습니다.");
    object hidden=area.EntireRow.Hidden;
    if(!(hidden is bool)||Convert.ToBoolean(hidden))throw Reject("VCP-HIDDEN","대상 가시 상태가 달라졌습니다.");
    object merge=area.MergeCells,array=area.HasArray;
    if(!(merge is bool)||Convert.ToBoolean(merge)||!(array is bool)||Convert.ToBoolean(array))throw Reject("VCP-MERGE-ARRAY","병합 셀과 배열 수식은 지원하지 않습니다.");
    try{object spill=area.HasSpill;if(!(spill is bool)||Convert.ToBoolean(spill))throw Reject("VCP-SPILL","동적 배열 spill 범위는 지원하지 않습니다.");}catch(COMException e){if((uint)e.HResult!=0x80020003)throw;}
    for(int row=start;row<=end;row++)targets.Add(new TargetCell(sheetKey,row,col,false));

   }
   // Query once: single-cell SpecialCells can expand to the used range.
   // Intersect with the already clipped visible target, preserving hidden/outside rules.
   object validation=null;try{validation=selected.SpecialCells(-4174);}catch(COMException e){if((uint)e.HResult!=0x800A03EC)throw;}
   if(validation!=null){try{if(Intersects(clipped,validation))throw Reject("VCP-VALIDATION","데이터 유효성 검사 규칙이 있는 칸은 지원하지 않습니다.");}finally{Release(validation);}}
   GuardTable(sheet,selected);
   var selection=new SelectionSnapshot(sheetKey,first,last,col,cols,count,areas,false,false,targets);
   var plan=Planner.Build(source,selection);
   var prepared=new PreparedPaste{Book=book,Sheet=sheet,Selection=selected,Address=(string)selected.Address,SheetName=(string)sheet.Name,Plan=plan};
   app.StatusBar="보이는 칸 붙여넣기 · 백업 검사";
   prepared.Before=CellSnapshotReader.Capture(sheet,plan);
   for(int i=0;i<prepared.Before.Length;i++){var s=prepared.Before[i];if(s.Formula)prepared.Formulas++;if(source.Items[i].Kind==CellValueKind.Empty&&s.Value.Kind!=CellValueKind.Empty)prepared.Clears++;}

   return prepared;
  }
  static bool EqualState(CellState a,CellState b){return a.Address==b.Address&&a.Formula==b.Formula&&Object.Equals(a.Format,b.Format)&&(a.Formula? a.FormulaProperty==b.FormulaProperty&&Object.Equals(a.FormulaValue,b.FormulaValue):a.Value.Equals(b.Value));}
  void Revalidate(PreparedPaste p) {
   if(!Same((object)app.ActiveWorkbook,p.Book)||!Same((object)app.ActiveSheet,p.Sheet)||(string)app.Selection.Address!=p.Address||(string)((dynamic)p.Sheet).Name!=p.SheetName)throw Reject("VCP-TARGET-CHANGED","선택이나 대상 파일이 달라졌습니다. 다시 선택해 주세요.");
   var fresh=Prepare(p.Plan.Source);
   if(fresh.Before.Length!=p.Before.Length)throw Reject("VCP-TARGET-CHANGED","대상 가시 상태가 달라졌습니다.");
   for(int i=0;i<p.Before.Length;i++)if(!EqualState(p.Before[i],fresh.Before[i]))throw Reject("VCP-TARGET-CHANGED","확인 중 대상 내용·서식·가시 상태가 달라졌습니다.");
  }
  static object NativeValue(CellValue v){if(v.Kind==CellValueKind.Error)return new ErrorWrapper(unchecked((int)0x800A0000)|v.ErrorCode);return v.Value;}
  void WriteRun(PreparedPaste p,int start,int n) {
   dynamic sheet=p.Sheet;var first=p.Plan.Targets[start];dynamic range=sheet.Range[sheet.Cells[first.Row,first.Column],sheet.Cells[first.Row+n-1,first.Column]];
   try {
    var kind=p.Plan.Source.Items[start].Kind;
    if(kind==CellValueKind.Empty){range.Value2=null;return;}
    var values=new object[n,1];for(int i=0;i<n;i++)values[i,0]=NativeValue(p.Plan.Source.Items[start+i]);
    if(kind==CellValueKind.String) {
     range.NumberFormat="@";
     try{range.Value2=values;}finally{for(int i=0;i<n;i++){dynamic c=sheet.Cells[first.Row+i,first.Column];try{c.NumberFormat=p.Before[start+i].Format;}finally{Release(c);}}}
    }else range.Value2=values;
   }finally{Release(range);}
  }
  public static void RestoreCell(object worksheet,CellState s) {
   dynamic sheet=worksheet;dynamic c=sheet.Cells[s.Row,s.Column];try{
    if(s.Formula){if(s.FormulaProperty=="Formula2")c.Formula2=s.FormulaValue;else c.Formula=s.FormulaValue;}
    else if(s.Value.Kind==CellValueKind.Empty)c.Value2=null;
    else if(s.Value.Kind==CellValueKind.String){c.NumberFormat="@";c.Value2=s.Value.Value;}
    else c.Value2=NativeValue(s.Value);
   }finally {try{c.NumberFormat=s.Format;}finally{Release(c);}}
  }
  bool Expected(CellValue expected,CellState actual){return !actual.Formula&&(expected.Equals(actual.Value)||(expected.Kind==CellValueKind.String&&(string)expected.Value==""&&actual.Value.Kind==CellValueKind.Empty));}
  static bool SameRestoreRun(CellState first,CellState next,int offset){return next.Row==first.Row+offset&&next.Column==first.Column&&first.Formula==next.Formula&&Object.Equals(first.Format,next.Format)&&(first.Formula?first.FormulaProperty==next.FormulaProperty:first.Value.Kind==next.Value.Kind);}
  static void RestoreRun(object worksheet,CellState[] states,int start,int count){
   dynamic sheet=worksheet;var first=states[start];dynamic range=sheet.Range[first.Address,states[start+count-1].Address];
   try{
    if(!first.Formula&&first.Value.Kind==CellValueKind.Empty){range.Value2=null;return;}
    var values=new object[count,1];for(int i=0;i<count;i++)values[i,0]=first.Formula?states[start+i].FormulaValue:NativeValue(states[start+i].Value);
    if(first.Formula){if(first.FormulaProperty=="Formula2")range.Formula2=values;else range.Formula=values;}
    else {if(first.Value.Kind==CellValueKind.String)range.NumberFormat="@";range.Value2=values;}
   }finally{try{range.NumberFormat=first.Format;}finally{Release(range);}}
  }
  void Rollback(PreparedPaste p,string original) {
   var failed=new List<string>();var codes=new List<string>();var known=new HashSet<string>();
   Action<CellState,string> failure=delegate(CellState state,string code){if(known.Add(state.Address)){failed.Add(state.Address);codes.Add(code);}};
   for(int i=0;i<p.Before.Length;) {
    int n=1;while(i+n<p.Before.Length&&n<512&&SameRestoreRun(p.Before[i],p.Before[i+n],n)) {
#if VCP_TESTING
     if(FailRecoveryAt==i||FailRecoveryAt==i+n)break;
#endif
     n++;
    }
    try{
#if VCP_TESTING
     if(FailRecoveryAt==i)throw new COMException("Synthetic rollback failure",unchecked((int)0x80004005));
#endif
     RestoreRun(p.Sheet,p.Before,i,n);
    }catch(Exception e){for(int j=i;j<i+n;j++)failure(p.Before[j],e.HResult.ToString("X8"));}
    i+=n;
   }
   try{var current=CellSnapshotReader.Capture(p.Sheet,p.Plan);for(int i=0;i<p.Before.Length;i++)if(!EqualState(p.Before[i],current[i]))failure(p.Before[i],"VERIFY");}
   catch(Exception e){foreach(var state in p.Before)failure(state,e.HResult.ToString("X8"));}
   if(failed.Count>0){RecoveryRequired=true;undoAllowed=false;undo=p;RecoveryDetail="영향 가능 범위: "+((dynamic)p.Book).Name+" / "+p.SheetName+" / "+p.Address+"\n복구 실패: "+String.Join(", ",failed)+"\n원래 오류: "+original+"\n복구 오류: "+String.Join(", ",codes);throw new RecoveryException(original,failed,codes);}
  }
  bool SortHistoryClear(object worksheet){try{dynamic sheet=worksheet;if((int)sheet.Sort.SortFields.Count!=0)return false;foreach(dynamic table in sheet.ListObjects)if((int)table.Sort.SortFields.Count!=0)return false;return true;}catch{return false;}}
  string UndoSignature(){try{return Convert.ToBoolean(app.CommandBars.GetEnabledMso("Undo"))?"enabled":"disabled";}catch{return "unknown";}}
  void RecoverAfterWrite(PreparedPaste p,Exception error,Action<string> progress) {
   // Presentation failure must not prevent restoration of already touched cells.
   if(progress!=null)try{progress("복구 중");}catch(Exception){}
   try{Rollback(p,error.HResult.ToString("X8"));LastOutcome="rolled-back";}catch{LastOutcome="recovery-required";throw;}
  }
  void BeginWrite(out bool events,out bool screen,out object calculation,out object status,out bool oldSuppress) {
   // Snapshot every global before entering the transaction: a failed getter must not strand busy.
   try{events=(bool)app.EnableEvents;screen=(bool)app.ScreenUpdating;calculation=app.Calculation;status=app.StatusBar;oldSuppress=epoch.Suppress;}
   catch{LastOutcome="no-change";throw;}
   busy=true;
  }
  public void Apply(PreparedPaste p,Func<bool> cancel,Action<string> progress) {
   Revalidate(p);if(busy)throw Reject("VCP-BUSY","이미 작업 중입니다.");bool touched=false;bool events,screen,oldSuppress;object calculation,status;BeginWrite(out events,out screen,out calculation,out status,out oldSuppress);
   try {
    epoch.Suppress=true;app.EnableEvents=false;app.ScreenUpdating=false;app.Calculation=-4135;
    int writes=0;
    foreach(var segment in p.Plan.Segments)for(int start=segment.StartIndex;start<segment.StartIndex+segment.Count;) {
     if(cancel!=null&&cancel())throw new OperationCanceledException();
     int n=1;var kind=p.Plan.Source.Items[start].Kind;
     while(start+n<segment.StartIndex+segment.Count&&p.Plan.Source.Items[start+n].Kind==kind&&n<512)n++;
     if(progress!=null)progress("쓰기 "+start+" / "+p.Before.Length);app.StatusBar="보이는 칸 붙여넣기 · 쓰기 "+start+" / "+p.Before.Length;
     touched=true;WriteRun(p,start,n);writes++;start+=n;
#if VCP_TESTING
     if(writes==FailAfterWrites)throw new COMException("Synthetic write failure",unchecked((int)0x80004005));
     if(CancelAfterWrite)throw new OperationCanceledException();
#endif
    }
    if(progress!=null)progress("검증 중");var result=CellSnapshotReader.Capture(p.Sheet,p.Plan);
    for(int i=0;i<p.Before.Length;i++){if(cancel!=null&&cancel())throw new OperationCanceledException();if(!Expected(p.Plan.Source.Items[i],result[i])||!Object.Equals(p.Before[i].Format,result[i].Format))throw new Exception("VCP-VERIFY-TYPE-OR-FORMAT");}
    undo=p;after=result;undoAllowed=events&&epoch.Available&&SortHistoryClear(p.Sheet);undoEpoch=epoch.Version;undoCommand=UndoSignature();if(undoCommand!="disabled")undoAllowed=false;
    LastOutcome="success";LastCount=result.Length;
   } catch(Exception error) {
    if(touched){RecoverAfterWrite(p,error,progress);throw new InvalidOperationException("붙여넣기를 완료하지 못했습니다. 이번 작업으로 바뀐 내용을 작업 전 상태로 되돌렸습니다.\n오류 코드: VCP-WRITE-"+error.HResult.ToString("X8"),error);}
    LastOutcome="no-change";throw;
   } finally {
    RestoreGlobals(calculation,screen,status,events,oldSuppress);
   }
  }
  public void UndoLast() {
   if(busy||RecoveryRequired)throw Reject("VCP-UNDO-BUSY","지금은 되돌릴 수 없습니다.");
   if(undo==null)throw Reject("VCP-UNDO-NONE","되돌릴 붙여넣기 기록이 없습니다.");
   if(!Same((object)app.ActiveWorkbook,undo.Book))throw Reject("VCP-UNDO-WORKBOOK","붙여넣기한 원래 파일로 이동해 주세요.");
   if(!undoAllowed||!SortHistoryClear(undo.Sheet)||!epoch.Available||epoch.Version!=undoEpoch||!(bool)app.EnableEvents||UndoSignature()!=undoCommand||!Same((object)app.ActiveSheet,undo.Sheet)||(string)((dynamic)undo.Sheet).Name!=undo.SheetName||(string)app.Selection.Address!=undo.Address)throw Reject("VCP-UNDO-INVALID","이 시트의 정렬 설정·편집 또는 구조 변경으로 안전하게 되돌릴 수 없습니다.");
   var current=Prepare(undo.Plan.Source);if(current.Before.Length!=after.Length)throw Reject("VCP-UNDO-STRUCTURE","대상 구조가 달라졌습니다.");
   for(int i=0;i<after.Length;i++)if(!EqualState(after[i],current.Before[i])){undoAllowed=false;throw Reject("VCP-UNDO-CONFLICT","붙여넣기 이후 내용이나 서식이 바뀌어 되돌릴 수 없습니다.");}
   bool events=(bool)app.EnableEvents,screen=(bool)app.ScreenUpdating;object calc=app.Calculation,status=app.StatusBar;bool oldSuppress=epoch.Suppress;busy=true;
   try{epoch.Suppress=true;app.EnableEvents=false;app.ScreenUpdating=false;app.Calculation=-4135;Rollback(undo,"VCP-UNDO");undo=null;after=null;undoAllowed=false;LastOutcome="undone";}
   catch{LastOutcome="recovery-required";throw;}
   finally{RestoreGlobals(calc,screen,status,events,oldSuppress);}
  }
  void RestoreGlobals(object calculation,bool screen,object status,bool events,bool oldSuppress) {
   var errors=new List<string>();
   try{app.Calculation=calculation;}catch(Exception e){errors.Add("Calculation:"+e.HResult.ToString("X8"));}
   try{app.ScreenUpdating=screen;}catch(Exception e){errors.Add("ScreenUpdating:"+e.HResult.ToString("X8"));}
   try{app.StatusBar=status;}catch(Exception e){errors.Add("StatusBar:"+e.HResult.ToString("X8"));}
   try{app.EnableEvents=events;}catch(Exception e){errors.Add("EnableEvents:"+e.HResult.ToString("X8"));}
   epoch.Suppress=oldSuppress;busy=false;
   if(errors.Count>0){undoAllowed=false;RecoveryRequired=true;RecoveryDetail=(RecoveryDetail??"")+"\n데이터 처리 결과: "+LastOutcome+"\n전역 상태 복구 실패: "+String.Join(", ",errors);LastOutcome="state-restore-failed";throw new InvalidOperationException(RecoveryDetail+"\n자동 저장하지 않았습니다. 후속 쓰기를 차단했습니다.");}
  }

 }
}
