using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace VisibleCellsPaste {
 public sealed class CellState {
  public int Row; public int Column; public string Address; public bool Formula; public string FormulaProperty; public object FormulaValue; public object Format; public CellValue Value;
 }
 public sealed class PreparedPaste : IDisposable {
  readonly ComScope references; public bool IsDisposed {get;private set;}
  public object Book, Sheet, Selection; public string Address, SheetName; public PastePlan Plan; public CellState[] Before; public int Formulas, Clears;
  public PreparedPaste(){}
  internal PreparedPaste(ComScope acquiredReferences){references=acquiredReferences;}
  internal void CheckLive(){if(IsDisposed)throw new ObjectDisposedException("PreparedPaste");}
  public void Dispose(){if(IsDisposed)return;IsDisposed=true;try{if(references!=null)references.Dispose();}finally{Book=null;Sheet=null;Selection=null;}}
 }
 public sealed class RecoveryException : Exception {
  public readonly string[] FailedAddresses; public readonly string OriginalCode; public readonly string[] RecoveryCodes;
  public RecoveryException(string original,List<string> addresses,List<string> codes):base("일부 셀의 복구를 확인하지 못했습니다. 자동 저장하지 않았습니다. 영향 가능 범위와 복구 실패 주소를 확인해 주세요.") {OriginalCode=original;FailedAddresses=addresses.ToArray();RecoveryCodes=codes.ToArray();}
 }
 public sealed class ExcelEngine : IDisposable {
  readonly dynamic app; readonly UndoEpoch epoch; bool busy; PreparedPaste undo,inFlight; CellState[] after; long undoEpoch; string undoCommand; bool undoAllowed;
  public bool RecoveryRequired {get;private set;} public string RecoveryDetail {get;private set;}
  public string LastOutcome {get;private set;} public int LastCount {get;private set;}
#if VCP_TESTING
  public int FailAfterWrites=-1, FailRecoveryAt=-1; public bool CancelAfterWrite;
#endif
  public ExcelEngine(object application) {app=application;epoch=new UndoEpoch(application);LastOutcome="idle";}
  public void Dispose(){try{epoch.Dispose();}finally{ClearUndo();}}
  void KeepUndo(PreparedPaste value){PreparedPaste previous=undo;if(Object.ReferenceEquals(previous,value))return;undo=value;after=null;undoAllowed=false;if(previous!=null)previous.Dispose();}
  void ClearUndo(){PreparedPaste previous=undo;undo=null;after=null;undoAllowed=false;if(previous!=null)previous.Dispose();}
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
   using(var refs=new ComScope()){
    dynamic cells=refs.Own((object)sheet.Cells);dynamic c=refs.Own((object)cells[row,col]);
    var s=new CellState{Row=row,Column=col,Address=(string)c.Address,Format=c.NumberFormat,Formula=Convert.ToBoolean(c.HasFormula),Value=ReadValue((object)c.Value2)};
    if(s.Formula){try{s.FormulaValue=c.Formula2;s.FormulaProperty="Formula2";}catch(COMException){s.FormulaValue=c.Formula;s.FormulaProperty="Formula";}}
    return s;
   }
  }
  public static void Release(object obj){if(obj!=null&&Marshal.IsComObject(obj))try{Marshal.ReleaseComObject(obj);}catch(InvalidComObjectException){}}
  public static void RestoreStatusBar(object target,object prior) {
   if(target==null)throw new ArgumentNullException("target");
   RestoreStatusBarCore(target,prior,Marshal.IsComObject(target));
  }
  static void RestoreStatusBarCore(object target,object prior,bool verifyDefaultControl) {
   dynamic excel=target;excel.StatusBar=prior;
   if(!verifyDefaultControl||!(prior is bool)||(bool)prior)return;
   // False is Excel's documented reset. Some Excel builds return BSTR "FALSE" after that PUT.
   // A verified empty-string reset restores Excel ownership; a literal saved string stays a string.
   object current=excel.StatusBar;if(current is bool&&!(bool)current)return;
   excel.StatusBar=String.Empty;current=excel.StatusBar;
   if(!(current is bool)||(bool)current)throw new InvalidOperationException("VCP-STATUSBAR-RESTORE: Excel 상태 표시줄의 기본 상태 복원을 확인하지 못했습니다.");
  }
  static bool HasAnyFormula(dynamic range) {object v=range.HasFormula;return !(v is bool && !(bool)v);}
  bool Intersects(object left,object right){object r=app.Intersect(left,right);try{return r!=null;}finally{Release(r);}}
  void GuardTable(dynamic sheet,dynamic selection) {
   using(var collections=new ComScope()){
    dynamic tables=collections.Own((object)sheet.ListObjects);int count=(int)tables.Count;
    for(int i=1;i<=count;i++)using(var refs=new ComScope()){
     dynamic table=refs.Own((object)tables[i]);dynamic body=refs.Own((object)table.DataBodyRange);object tableRange=refs.Own((object)table.Range);
     if(Intersects(tableRange,selection)){
      if(body==null)throw Reject("VCP-TABLE-EMPTY","빈 표의 헤더에는 붙여넣을 수 없습니다.");
      if(Intersects(refs.Own((object)table.HeaderRowRange),selection))throw Reject("VCP-TABLE-HEADER","표 헤더는 지원하지 않습니다.");
      if((bool)table.ShowTotals&&Intersects(refs.Own((object)table.TotalsRowRange),selection))throw Reject("VCP-TABLE-TOTAL","표 합계 행은 지원하지 않습니다.");
      dynamic columns=refs.Own((object)table.ListColumns);int columnCount=(int)columns.Count;
      for(int j=1;j<=columnCount;j++)using(var columnRefs=new ComScope()){
       dynamic column=columnRefs.Own((object)columns[j]);object columnRange=columnRefs.Own((object)column.Range);
       if(Intersects(columnRange,selection)&&HasAnyFormula(columnRefs.Own((object)column.DataBodyRange)))throw Reject("VCP-TABLE-FORMULA","수식이 포함된 표 열은 숨긴 행을 포함해 지원하지 않습니다.");
      }
     }
    }
    dynamic pivots=collections.Own((object)sheet.PivotTables());int pivotCount=(int)pivots.Count;
    for(int i=1;i<=pivotCount;i++)using(var refs=new ComScope()){
     dynamic pivot=refs.Own((object)pivots[i]);if(Intersects(refs.Own((object)pivot.TableRange2),selection))throw Reject("VCP-PIVOT","피벗 결과 셀은 지원하지 않습니다.");
    }
   }
  }
  void GuardProtectedView() {
   object protectedWindow=app.ActiveProtectedViewWindow;
   try{if(protectedWindow!=null)throw Reject("VCP-PROTECTED-VIEW","제한된 보기에서는 실행할 수 없습니다.");}finally{Release(protectedWindow);}
  }
  public PreparedPaste Prepare(ClipboardSnapshot source) {
   if(busy)throw Reject("VCP-BUSY","이미 작업 중입니다.");if(RecoveryRequired)throw Reject("VCP-RECOVERY-REQUIRED","복구 확인이 필요합니다. 이 Excel에서 후속 쓰기를 차단했습니다.");
   GuardProtectedView();object previous=app.StatusBar;PreparedPaste prepared=null;
   try{
    try{app.StatusBar="보이는 칸 붙여넣기 · 검사 중";prepared=PrepareCore(source);}finally{try{RestoreStatusBar((object)app,previous);}catch(Exception error){FailStateRestoration(new[]{"StatusBar:"+error.HResult.ToString("X8")});}}
    return prepared;
   }catch{if(prepared!=null)prepared.Dispose();throw;}
  }
  private PreparedPaste PrepareCore(ClipboardSnapshot source) {
   var retained=new ComScope();
   try{using(var refs=new ComScope()){
    dynamic selected=retained.Own((object)app.Selection);dynamic sheet,book;
    try{sheet=retained.Own((object)selected.Worksheet);book=retained.Own((object)sheet.Parent);}catch{throw Reject("VCP-SELECTION","워크시트의 한 열 범위를 선택해 주세요.");}
    if(Convert.ToBoolean(book.ReadOnly))throw Reject("VCP-READONLY","읽기 전용 파일은 지원하지 않습니다.");
    if(Convert.ToBoolean(sheet.ProtectContents)||Convert.ToBoolean(sheet.ProtectDrawingObjects)||Convert.ToBoolean(sheet.ProtectScenarios))throw Reject("VCP-PROTECTED","보호된 시트는 지원하지 않습니다.");
    dynamic window=refs.Own((object)app.ActiveWindow);dynamic selectedSheets=refs.Own((object)window.SelectedSheets);
    if((int)selectedSheets.Count!=1)throw Reject("VCP-GROUPED","여러 시트를 그룹 선택한 상태는 지원하지 않습니다.");
    dynamic columns=refs.Own((object)selected.Columns),selectedAreas=refs.Own((object)selected.Areas),rows=refs.Own((object)selected.Rows);
    long count=Convert.ToInt64(selected.CountLarge);int cols=(int)columns.Count,areas=(int)selectedAreas.Count;
    int first=(int)selected.Row,col=(int)selected.Column,last=first+(int)rows.Count-1;
    if(areas!=1||cols!=1||count>=Limits.ExcelRows||count>Limits.MaxSelectionCells)throw Reject("VCP-SELECTION-SHAPE","연속된 한 열의 최대 200,000칸을 선택해 주세요. 전체 행·열과 직접 만든 다중 선택은 지원하지 않습니다.");
    dynamic entireColumn=refs.Own((object)selected.EntireColumn);if(Convert.ToBoolean(entireColumn.Hidden))throw Reject("VCP-HIDDEN-COLUMN","선택한 열이 숨겨져 있습니다.");
    try{if(Convert.ToBoolean(book.MultiUserEditing))throw Reject("VCP-SHARED","공유 통합문서는 지원하지 않습니다.");}catch(COMException){}
    dynamic visible;try{visible=refs.Own((object)selected.SpecialCells(12));}catch(COMException){throw Reject("VCP-NO-VISIBLE","선택한 범위에 보이는 칸이 없습니다.");}
    dynamic clipped=refs.Own((object)app.Intersect(selected,visible));if(clipped==null)throw Reject("VCP-NO-VISIBLE","선택한 범위에 보이는 칸이 없습니다.");
    dynamic visibleAreas=refs.Own((object)clipped.Areas);int visibleAreaCount=(int)visibleAreas.Count;
    if(visibleAreaCount>Limits.MaxSegments)throw Reject("VCP-SEGMENT-LIMIT","보이는 연속 구간은 최대 20,000개입니다.");
    var targets=new List<TargetCell>();string sheetKey=Guid.NewGuid().ToString("N");
    for(int areaIndex=1;areaIndex<=visibleAreaCount;areaIndex++)using(var areaRefs=new ComScope()){
     dynamic area=areaRefs.Own((object)visibleAreas[areaIndex]);object areaSheet=areaRefs.Own((object)area.Worksheet);
     if(!Same(areaSheet,(object)sheet))throw Reject("VCP-BOUNDARY","대상 워크시트가 달라졌습니다.");
     if(Convert.ToInt64(area.CountLarge)+targets.Count>Limits.MaxItems)throw Reject("VCP-ITEM-LIMIT","보이는 칸은 최대 50,000개입니다.");
     dynamic areaRows=areaRefs.Own((object)area.Rows),areaColumns=areaRefs.Own((object)area.Columns),entireRow=areaRefs.Own((object)area.EntireRow);
     int start=(int)area.Row,end=start+(int)areaRows.Count-1;
     if((int)area.Column!=col||(int)areaColumns.Count!=1||start<first||end>last)throw Reject("VCP-BOUNDARY","선택 밖의 셀이 감지됐습니다.");
     object hidden=entireRow.Hidden;if(!(hidden is bool)||Convert.ToBoolean(hidden))throw Reject("VCP-HIDDEN","대상 가시 상태가 달라졌습니다.");
     object merge=area.MergeCells,array=area.HasArray;
     if(!(merge is bool)||Convert.ToBoolean(merge)||!(array is bool)||Convert.ToBoolean(array))throw Reject("VCP-MERGE-ARRAY","병합 셀과 배열 수식은 지원하지 않습니다.");
     try{object spill=area.HasSpill;if(!(spill is bool)||Convert.ToBoolean(spill))throw Reject("VCP-SPILL","동적 배열 spill 범위는 지원하지 않습니다.");}catch(COMException error){if((uint)error.HResult!=0x80020003)throw;}
     for(int row=start;row<=end;row++)targets.Add(new TargetCell(sheetKey,row,col,false));
    }
    object validation=null;try{validation=refs.Own((object)selected.SpecialCells(-4174));}catch(COMException error){if((uint)error.HResult!=0x800A03EC)throw;}
    if(validation!=null&&Intersects(clipped,validation))throw Reject("VCP-VALIDATION","데이터 유효성 검사 규칙이 있는 칸은 지원하지 않습니다.");
    GuardTable(sheet,selected);
    var selection=new SelectionSnapshot(sheetKey,first,last,col,cols,count,areas,false,false,targets);var plan=Planner.Build(source,selection);
    var prepared=new PreparedPaste(retained){Book=book,Sheet=sheet,Selection=selected,Address=(string)selected.Address,SheetName=(string)sheet.Name,Plan=plan};
    app.StatusBar="보이는 칸 붙여넣기 · 백업 검사";prepared.Before=CellSnapshotReader.Capture(sheet,plan);
    for(int i=0;i<prepared.Before.Length;i++){var state=prepared.Before[i];if(state.Formula)prepared.Formulas++;if(source.Items[i].Kind==CellValueKind.Empty&&state.Value.Kind!=CellValueKind.Empty)prepared.Clears++;}
    return prepared;
   }}catch{retained.Dispose();throw;}
  }
  static bool EqualState(CellState a,CellState b){return a.Address==b.Address&&a.Formula==b.Formula&&Object.Equals(a.Format,b.Format)&&(a.Formula? a.FormulaProperty==b.FormulaProperty&&Object.Equals(a.FormulaValue,b.FormulaValue):a.Value.Equals(b.Value));}
  void Revalidate(PreparedPaste p) {
   p.CheckLive();
   using(var refs=new ComScope()){
    object book=refs.Own((object)app.ActiveWorkbook),sheet=refs.Own((object)app.ActiveSheet);dynamic selected=refs.Own((object)app.Selection);
    if(!Same(book,p.Book)||!Same(sheet,p.Sheet)||(string)selected.Address!=p.Address||(string)((dynamic)p.Sheet).Name!=p.SheetName)throw Reject("VCP-TARGET-CHANGED","선택이나 대상 파일이 달라졌습니다. 다시 선택해 주세요.");
    using(var fresh=Prepare(p.Plan.Source)){
     if(fresh.Before.Length!=p.Before.Length)throw Reject("VCP-TARGET-CHANGED","대상 가시 상태가 달라졌습니다.");
     for(int i=0;i<p.Before.Length;i++)if(!EqualState(p.Before[i],fresh.Before[i]))throw Reject("VCP-TARGET-CHANGED","확인 중 대상 내용·서식·가시 상태가 달라졌습니다.");
    }
   }
  }
  static object NativeValue(CellValue v){if(v.Kind==CellValueKind.Error)return new ErrorWrapper(unchecked((int)0x800A0000)|v.ErrorCode);return v.Value;}
  void WriteRun(PreparedPaste p,int start,int n) {
   dynamic sheet=p.Sheet;var first=p.Plan.Targets[start];
   using(var refs=new ComScope()){
    dynamic range=refs.Own((object)sheet.Range[p.Before[start].Address,p.Before[start+n-1].Address]);var kind=p.Plan.Source.Items[start].Kind;
    if(kind==CellValueKind.Empty){range.Value2=null;return;}
    var values=new object[n,1];for(int i=0;i<n;i++)values[i,0]=NativeValue(p.Plan.Source.Items[start+i]);
    if(kind==CellValueKind.String){
     range.NumberFormat="@";
     try{range.Value2=values;}finally{
      dynamic cells=refs.Own((object)sheet.Cells);
      for(int i=0;i<n;i++)using(var cellRefs=new ComScope()){dynamic cell=cellRefs.Own((object)cells[first.Row+i,first.Column]);cell.NumberFormat=p.Before[start+i].Format;}
     }
    }else range.Value2=values;
   }
  }
  public static void RestoreCell(object worksheet,CellState s) {
   dynamic sheet=worksheet;using(var refs=new ComScope()){
    dynamic cells=refs.Own((object)sheet.Cells),cell=refs.Own((object)cells[s.Row,s.Column]);
    try{
     if(s.Formula){if(s.FormulaProperty=="Formula2")cell.Formula2=s.FormulaValue;else cell.Formula=s.FormulaValue;}
     else if(s.Value.Kind==CellValueKind.Empty)cell.Value2=null;
     else if(s.Value.Kind==CellValueKind.String){cell.NumberFormat="@";cell.Value2=s.Value.Value;}
     else cell.Value2=NativeValue(s.Value);
    }finally{cell.NumberFormat=s.Format;}
   }
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
   if(failed.Count>0){RecoveryRequired=true;undoAllowed=false;KeepUndo(p);RecoveryDetail="영향 가능 범위: "+((dynamic)p.Book).Name+" / "+p.SheetName+" / "+p.Address+"\n복구 실패: "+String.Join(", ",failed)+"\n원래 오류: "+original+"\n복구 오류: "+String.Join(", ",codes);throw new RecoveryException(original,failed,codes);}
  }
  bool SortHistoryClear(object worksheet){
   try{dynamic sheet=worksheet;using(var refs=new ComScope()){
    dynamic sort=refs.Own((object)sheet.Sort),fields=refs.Own((object)sort.SortFields);if((int)fields.Count!=0)return false;
    dynamic tables=refs.Own((object)sheet.ListObjects);int count=(int)tables.Count;
    for(int i=1;i<=count;i++)using(var tableRefs=new ComScope()){
     dynamic table=tableRefs.Own((object)tables[i]),tableSort=tableRefs.Own((object)table.Sort),tableFields=tableRefs.Own((object)tableSort.SortFields);
     if((int)tableFields.Count!=0)return false;
    }
    return true;
   }}catch{return false;}
  }
  string UndoSignature(){try{using(var refs=new ComScope()){dynamic bars=refs.Own((object)app.CommandBars);return Convert.ToBoolean(bars.GetEnabledMso("Undo"))?"enabled":"disabled";}}catch{return "unknown";}}
  void RecoverAfterWrite(PreparedPaste p,Exception error,Action<string> progress) {
   // Presentation failure must not prevent restoration of already touched cells.
   if(progress!=null)try{progress("복구 중");}catch(Exception){}
   try{Rollback(p,error.HResult.ToString("X8"));if(Object.ReferenceEquals(undo,p))ClearUndo();LastOutcome="rolled-back";}catch{LastOutcome="recovery-required";throw;}
  }
  void BeginWrite(out bool events,out bool screen,out object calculation,out object status,out bool oldSuppress) {
   // Snapshot every global before entering the transaction: a failed getter must not strand busy.
   try{events=(bool)app.EnableEvents;screen=(bool)app.ScreenUpdating;calculation=app.Calculation;status=app.StatusBar;oldSuppress=epoch.Suppress;}
   catch{LastOutcome="no-change";throw;}
   busy=true;
  }
  // Apply consumes new ownership; reentry cannot consume a record already owned by this engine.
  public void Apply(PreparedPaste p,Func<bool> cancel,Action<string> progress) {
   if(p==null)throw new ArgumentNullException("p");
   if(inFlight!=null||busy){
    if(!Object.ReferenceEquals(inFlight,p)&&!Object.ReferenceEquals(undo,p))p.Dispose();
    throw Reject("VCP-BUSY","이미 작업 중입니다.");
   }
   inFlight=p;bool completed=false;
   try{ApplyOwned(p,cancel,progress);completed=true;}finally{
    try{
     if(!completed&&!RecoveryRequired&&Object.ReferenceEquals(undo,p))ClearUndo();
     if(!Object.ReferenceEquals(undo,p))p.Dispose();
    }finally{inFlight=null;}
   }
  }
  void ApplyOwned(PreparedPaste p,Func<bool> cancel,Action<string> progress) {
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
    KeepUndo(p);after=result;undoAllowed=events&&epoch.Available&&SortHistoryClear(p.Sheet);undoEpoch=epoch.Version;undoCommand=UndoSignature();if(undoCommand!="disabled")undoAllowed=false;
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
   using(var refs=new ComScope()){
    if(!Same(refs.Own((object)app.ActiveWorkbook),undo.Book))throw Reject("VCP-UNDO-WORKBOOK","붙여넣기한 원래 파일로 이동해 주세요.");
    if(!undoAllowed||!SortHistoryClear(undo.Sheet)||!epoch.Available||epoch.Version!=undoEpoch||!(bool)app.EnableEvents||UndoSignature()!=undoCommand)throw Reject("VCP-UNDO-INVALID","이 시트의 정렬 설정·편집 또는 구조 변경으로 안전하게 되돌릴 수 없습니다.");
    object sheet=refs.Own((object)app.ActiveSheet);dynamic selected=refs.Own((object)app.Selection);
    if(!Same(sheet,undo.Sheet)||(string)((dynamic)undo.Sheet).Name!=undo.SheetName||(string)selected.Address!=undo.Address)throw Reject("VCP-UNDO-INVALID","이 시트의 정렬 설정·편집 또는 구조 변경으로 안전하게 되돌릴 수 없습니다.");
    using(var current=Prepare(undo.Plan.Source)){
     if(current.Before.Length!=after.Length)throw Reject("VCP-UNDO-STRUCTURE","대상 구조가 달라졌습니다.");
     for(int i=0;i<after.Length;i++)if(!EqualState(after[i],current.Before[i])){undoAllowed=false;throw Reject("VCP-UNDO-CONFLICT","붙여넣기 이후 내용이나 서식이 바뀌어 되돌릴 수 없습니다.");}
     bool events=(bool)app.EnableEvents,screen=(bool)app.ScreenUpdating;object calc=app.Calculation,status=app.StatusBar;bool oldSuppress=epoch.Suppress;busy=true;
     try{epoch.Suppress=true;app.EnableEvents=false;app.ScreenUpdating=false;app.Calculation=-4135;Rollback(undo,"VCP-UNDO");ClearUndo();LastOutcome="undone";}
     catch{LastOutcome="recovery-required";throw;}
     finally{RestoreGlobals(calc,screen,status,events,oldSuppress);}
    }
   }
  }
  void RestoreGlobals(object calculation,bool screen,object status,bool events,bool oldSuppress) {
   var errors=new List<string>();
   try{app.Calculation=calculation;}catch(Exception e){errors.Add("Calculation:"+e.HResult.ToString("X8"));}
   try{app.ScreenUpdating=screen;}catch(Exception e){errors.Add("ScreenUpdating:"+e.HResult.ToString("X8"));}
   try{RestoreStatusBar((object)app,status);}catch(Exception e){errors.Add("StatusBar:"+e.HResult.ToString("X8"));}
   try{app.EnableEvents=events;}catch(Exception e){errors.Add("EnableEvents:"+e.HResult.ToString("X8"));}
   epoch.Suppress=oldSuppress;busy=false;
   if(errors.Count>0)FailStateRestoration(errors);
  }
  void FailStateRestoration(IEnumerable<string> errors) {
   undoAllowed=false;RecoveryRequired=true;RecoveryDetail=(RecoveryDetail??"")+"\n데이터 처리 결과: "+LastOutcome+"\n전역 상태 복구 실패: "+String.Join(", ",errors);LastOutcome="state-restore-failed";throw new InvalidOperationException(RecoveryDetail+"\n자동 저장하지 않았습니다. 후속 쓰기를 차단했습니다.");
  }

 }
}
