using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using VisibleCellsPaste;

// Fault injection only: no Excel process or system clipboard is used.
public sealed class EntryApplication {
 public string FailedGetter;
 public readonly List<string> Gets=new List<string>();
 public int Sets,CellAccesses;
 object Read(string name,object value){Gets.Add(name);if(FailedGetter==name)throw new COMException("synthetic getter failure",unchecked((int)0x800A03EC));return value;}
 public bool EnableEvents{get{return (bool)Read("EnableEvents",false);}set{Sets++;}}
 public bool ScreenUpdating{get{return (bool)Read("ScreenUpdating",true);}set{Sets++;}}
 public object Calculation{get{return Read("Calculation",-4105);}set{Sets++;}}
 public object StatusBar{get{return Read("StatusBar","original");}set{Sets++;}}
 public object Cells{get{CellAccesses++;throw new Exception("Unexpected cell access");}}
}
public sealed class PresentationApplication {
 public string Failure;
 public object Current="original";
 public int Gets,Sets;
 public object StatusBar {
  get{Gets++;if(Failure=="com-get")throw new COMException("synthetic getter failure");if(Failure=="invalid-get")throw new InvalidComObjectException("synthetic disconnected COM");if(Failure=="other-get")throw new InvalidOperationException("synthetic presentation failure");return Current;}
  set{Sets++;if(Failure=="verification-set")throw new InvalidOperationException("VCP-STATUSBAR-RESTORE: synthetic verification failure");if(Failure=="com-set")throw new COMException("synthetic setter failure");if(Failure=="invalid-set")throw new InvalidComObjectException("synthetic disconnected COM");Current=value;if(Failure=="after-set")throw new COMException("synthetic partial setter failure");}
 }
}
public sealed class RecoveryTestSheet {
 public readonly Dictionary<int,double> Values=new Dictionary<int,double>{{1,901},{2,99},{3,903},{4,99},{5,905}};
 public readonly Dictionary<int,object> Formats=new Dictionary<int,object>{{2,"0.00"},{4,"0.00"}};
 public readonly List<int> Writes=new List<int>();
 public bool FailRow2;
 public RecoveryTestRanges Range{get{return new RecoveryTestRanges(this);}}
}
public sealed class RecoveryTestRanges {
 readonly RecoveryTestSheet sheet;public RecoveryTestRanges(RecoveryTestSheet s){sheet=s;}
 public RecoveryTestRange this[string address]{get{string[] a=address.Split(':');return this[a[0],a[a.Length-1]];}}
 public RecoveryTestRange this[string first,string last]{get{return new RecoveryTestRange(sheet,Int32.Parse(first.Substring(3)),Int32.Parse(last.Substring(3)));}}
}
public sealed class RecoveryTestRange {
 readonly RecoveryTestSheet sheet;readonly int first,last;
 public RecoveryTestRange(RecoveryTestSheet s,int f,int l){sheet=s;first=f;last=l;}
 public bool HasFormula{get{return false;}}
 public object NumberFormat{get{return sheet.Formats[first];}set{for(int r=first;r<=last;r++)sheet.Formats[r]=value;}}
 public object Value2{get{if(first==last)return sheet.Values[first];var a=new object[last-first+1,1];for(int r=first;r<=last;r++)a[r-first,0]=sheet.Values[r];return a;}
  set{for(int r=first;r<=last;r++){sheet.Writes.Add(r);if(sheet.FailRow2&&r==2)throw new COMException("synthetic restore failure");var a=value as Array;sheet.Values[r]=Convert.ToDouble(a==null?value:a.GetValue(r-first,0));}}}
}
public sealed class RecoveryTestBook{public string Name{get{return "Synthetic.xlsx";}}}
internal static class PresentationAndEntryTests {
 const BindingFlags F=BindingFlags.Instance|BindingFlags.NonPublic;
 static int passed,failed;
 static object Get(object o,string name){return o.GetType().GetField(name,F).GetValue(o);}
 static void Set(object o,string name,object value){o.GetType().GetField(name,F).SetValue(o,value);}
 static void Outcome(ExcelEngine e,string value){typeof(ExcelEngine).GetProperty("LastOutcome").GetSetMethod(true).Invoke(e,new object[]{value});}
 static Exception Invoke(object o,string method,object[] args){try{o.GetType().GetMethod(method,F).Invoke(o,args);return null;}catch(TargetInvocationException e){return e.InnerException;}}
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);}
 static void Test(string name,Action action){try{action();passed++;Console.WriteLine("PASS "+name);}catch(Exception e){failed++;Console.WriteLine("FAIL "+name+": "+e);}}
 static object[] EmptyArgs(){return new object[]{false,false,null,null,false};}
 static void GetterFailure(string property){
  var app=new EntryApplication{FailedGetter=property};using(var engine=new ExcelEngine(app)){
   Outcome(engine,"success");Set(engine,"undoAllowed",true);
   var epoch=(UndoEpoch)Get(engine,"epoch");epoch.Suppress=true;
   Exception error=Invoke(engine,"BeginWrite",EmptyArgs());
   Check(error is COMException,"The failed getter did not propagate");
   Check(!(bool)Get(engine,"busy")&&engine.LastOutcome=="no-change"&&!engine.RecoveryRequired,"Getter failure stranded busy or reported mutated data");
   Check((bool)Get(engine,"undoAllowed")&&epoch.Suppress,"Read failure damaged earlier undo/suppression state");
   Check(app.Sets==0&&app.CellAccesses==0,"A snapshot getter failure changed global or cell state");
   Check(app.Gets.Last()==property,"Global snapshot continued after the failed getter");
   app.FailedGetter=null;app.Gets.Clear();object[] captured=EmptyArgs();
   Check(Invoke(engine,"BeginWrite",captured)==null&&(bool)Get(engine,"busy"),"A fresh transaction could not enter after a getter failure");
   Check(Object.Equals(captured[0],false)&&Object.Equals(captured[1],true)&&Object.Equals(captured[2],-4105)&&Object.Equals(captured[3],"original")&&Object.Equals(captured[4],true),"Retry did not capture original state accurately");
   Check(Invoke(engine,"RestoreGlobals",new object[]{captured[2],captured[1],captured[3],captured[0],captured[4]})==null&&!(bool)Get(engine,"busy"),"Retry cleanup did not release busy");
  }
 }
 static void StatusFailure(string failure,string completed){
  var app=new PresentationApplication{Failure=failure};var addin=new AddIn();using(var engine=new ExcelEngine(app)){
   Outcome(engine,completed);Set(addin,"application",app);Set(addin,"connected",true);Set(addin,"engine",engine);Set(addin,"outcome",completed);
   Exception error=Invoke(addin,"ShowStatus",new object[]{"synthetic completed feedback"});
   Check(error==null,"Presentation failure escaped into the operation error notice");
   Check(app.Gets>0&&(!failure.Contains("set")||app.Sets>0),"Connected presentation fault injection was not reached");
   Check((string)Get(addin,"outcome")==completed&&engine.LastOutcome==completed&&!engine.RecoveryRequired,"Completed data outcome was changed by presentation failure");
   Check(Get(addin,"statusTimer")==null&&Get(addin,"ownStatus")==null,"Failed feedback retained a timer or claimed status ownership");
   if(failure=="after-set")Check(Object.Equals(app.Current,"original"),"Partially assigned status was not restored");
  }
 }
 static void RecoveryDespiteProgressFailure(bool failRestore){
  var sheet=new RecoveryTestSheet{FailRow2=failRestore};var source=new ClipboardSnapshot("unit",1,2,1,true,new[]{CellValue.Number(1),CellValue.Number(2)},"synthetic");
  var selected=new SelectionSnapshot("sheet",2,4,5,1,3,1,false,false,new[]{new TargetCell("sheet",2,5,false),new TargetCell("sheet",4,5,false)});
  var p=new PreparedPaste{Sheet=sheet,Book=new RecoveryTestBook(),SheetName="Synthetic",Address="$E$2:$E$4",Plan=Planner.Build(source,selected),Before=new[]{new CellState{Row=2,Column=5,Address="$E$2",Format="0.00",Value=CellValue.Number(12)},new CellState{Row=4,Column=5,Address="$E$4",Format="0.00",Value=CellValue.Number(14)}}};
  using(var engine=new ExcelEngine(new object())){
   int calls=0;Action<string> progress=delegate(string text){calls++;throw new InvalidOperationException("synthetic progress failure");};
   Exception error=Invoke(engine,"RecoverAfterWrite",new object[]{p,new COMException("original write failure"),progress});
   Check(calls==1&&sheet.Writes.SequenceEqual(new[]{2,4}),"Progress error skipped restoration or changed hidden/outside cells");
   Check(sheet.Values[1]==901&&sheet.Values[3]==903&&sheet.Values[5]==905&&sheet.Values[4]==14,"Hidden/outside values or later restore damaged");
   if(failRestore)Check(error is RecoveryException&&engine.RecoveryRequired&&engine.LastOutcome=="recovery-required","Restore error was hidden by presentation error");
   else Check(error==null&&sheet.Values[2]==12&&engine.LastOutcome=="rolled-back"&&!engine.RecoveryRequired,"Touched cells were not fully restored");
  }
 }
 static void NoticeForState(string state){
  using(var engine=new ExcelEngine(new object())){Outcome(engine,state);var addin=new AddIn();Set(addin,"engine",engine);
   var method=typeof(AddIn).GetMethod("BuildNoticeMessage",F);string message=(string)method.Invoke(addin,new object[]{new COMException("synthetic late error")});
   bool noChange=state=="idle"||state=="no-change";
   Check(message.Contains("변경된 셀은 없습니다")==noChange,"Notice falsely claimed unchanged data for "+state);
   Check(message.Contains("오류 코드:"),"Notice lost the error code");
   if(state=="recovery-required"||state=="state-restore-failed")Check(message.Contains("후속 쓰기를 차단"),"Recovery block not explained");
  }
 }
 [STAThread] static int Main(){
  foreach(string property in new[]{"EnableEvents","ScreenUpdating","Calculation","StatusBar"}){string copy=property;Test("pre-write "+copy+" getter failure leaves no mutations and allows retry",delegate{GetterFailure(copy);});}
  foreach(string failure in new[]{"com-get","invalid-get","other-get","com-set","invalid-set","after-set"}){string copy=failure;Test("completed paste survives status "+copy,delegate{StatusFailure(copy,"success");});}
  Test("completed undo survives status setter failure",delegate{StatusFailure("com-set","undone");});
  Test("replacing prior status disposes its timer even if restoration throws",delegate{
   var app=new PresentationApplication{Failure="other-get"};var addin=new AddIn();var timer=new System.Windows.Forms.Timer();bool disposed=false;timer.Disposed+=delegate{disposed=true;};
   Set(addin,"application",app);Set(addin,"connected",true);Set(addin,"statusTimer",timer);Set(addin,"ownStatus","previous");Set(addin,"oldStatus","original");Set(addin,"outcome","success");
   Check(Invoke(addin,"ShowStatus",new object[]{"new"})==null&&disposed&&Get(addin,"statusTimer")==null&&(string)Get(addin,"outcome")=="success","Prior status cleanup escaped or leaked timer");
  });
  Test("progress failure cannot bypass restoration of touched visible cells",delegate{RecoveryDespiteProgressFailure(false);});
  Test("progress failure cannot hide partial cell restoration failure",delegate{RecoveryDespiteProgressFailure(true);});
  foreach(string state in new[]{"success","undone","recovery-required","state-restore-failed","idle","no-change"}){string copy=state;Test("notice reports conservative data outcome "+copy,delegate{NoticeForState(copy);});}
  Test("new validation refusal is accurate after an earlier successful paste",delegate{using(var engine=new ExcelEngine(new object())){Outcome(engine,"success");var addin=new AddIn();Set(addin,"engine",engine);var error=new ValidationException("VCP-COUNT","Counts differ. 변경된 셀은 없습니다.");string message=(string)typeof(AddIn).GetMethod("BuildNoticeMessage",F).Invoke(addin,new object[]{error});Check(message==error.Message,"Stale success replaced current no-write validation");}});
  Test("verified rollback keeps its precise failure explanation",delegate{using(var engine=new ExcelEngine(new object())){Outcome(engine,"rolled-back");var addin=new AddIn();Set(addin,"engine",engine);var error=new InvalidOperationException("원래 내용으로 되돌렸습니다.");string message=(string)typeof(AddIn).GetMethod("BuildNoticeMessage",F).Invoke(addin,new object[]{error});Check(message==error.Message,"Rollback explanation was lost");}});

  foreach(string completed in new[]{"success","undone"}){string saved=completed;Test("completed "+saved+" survives default-control verification failure",delegate{
   var app=new PresentationApplication{Failure="verification-set",Current="owned feedback"};var addin=new AddIn();
   using(var engine=new ExcelEngine(app)){
    Outcome(engine,saved);Set(addin,"application",app);Set(addin,"engine",engine);Set(addin,"outcome",saved);Set(addin,"ownStatus","owned feedback");Set(addin,"oldStatus",false);
    Check(Invoke(addin,"RestoreStatus",new object[0])==null,"Verification failure escaped the timer restoration boundary");
    Check(Get(addin,"ownStatus")==null&&(string)Get(addin,"outcome")==saved&&engine.LastOutcome==saved&&!engine.RecoveryRequired,"Presentation failure corrupted the completed outcome");
   }
  });}
  Test("disconnect finishes cleanup when status verification fails",delegate{
   var app=new PresentationApplication{Failure="verification-set",Current="owned feedback"};var addin=new AddIn();var timer=new System.Windows.Forms.Timer();bool disposed=false;timer.Disposed+=delegate{disposed=true;};var pending=new PreparedPaste();
   Set(addin,"application",app);Set(addin,"engine",new ExcelEngine(app));Set(addin,"connected",true);Set(addin,"statusTimer",timer);Set(addin,"pending",pending);Set(addin,"ownStatus","owned feedback");Set(addin,"oldStatus",false);
   Array custom=new object[0];addin.OnDisconnection(0,ref custom);
   Check(disposed&&pending.IsDisposed&&Get(addin,"statusTimer")==null&&Get(addin,"ownStatus")==null&&Get(addin,"engine")==null&&Get(addin,"application")==null&&!(bool)Get(addin,"connected"),"Status verification failure skipped connection cleanup");
  });
  Test("status restoration never overwrites another owner's later message",delegate{
   var app=new PresentationApplication{Current="another owner"};var addin=new AddIn();Set(addin,"application",app);Set(addin,"ownStatus","owned feedback");Set(addin,"oldStatus",false);
   Check(Invoke(addin,"RestoreStatus",new object[0])==null&&app.Sets==0&&Object.Equals(app.Current,"another owner")&&Get(addin,"ownStatus")==null,"Later status owner was overwritten");
  });
  Console.WriteLine("RESULT: "+passed+" passed; "+failed+" failed");return failed==0?0:1;
 }
}
