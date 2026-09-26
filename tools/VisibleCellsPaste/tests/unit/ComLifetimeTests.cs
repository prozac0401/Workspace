using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using VisibleCellsPaste;

// Real OLE IStream RCWs, never Excel. Each Acquire simulates a distinct native return into the CLR.
public sealed class LifetimeNativeHost : IDisposable {
 [DllImport("ole32.dll")]static extern int CreateStreamOnHGlobal(IntPtr memory,[MarshalAs(UnmanagedType.Bool)]bool deleteOnRelease,out IntPtr stream);
 IntPtr pointer;public object Last;
 public LifetimeNativeHost(){Marshal.ThrowExceptionForHR(CreateStreamOnHGlobal(IntPtr.Zero,true,out pointer));}
 public object Acquire(){if(pointer==IntPtr.Zero)throw new ObjectDisposedException("LifetimeNativeHost");Last=Marshal.GetObjectForIUnknown(pointer);return Last;}
 public int ReleaseBase(){if(pointer==IntPtr.Zero)return 0;IntPtr value=pointer;pointer=IntPtr.Zero;return Marshal.Release(value);}
 public void Dispose(){ReleaseBase();}
 public static bool Released(object value){try{IntPtr p=Marshal.GetIUnknownForObject(value);Marshal.Release(p);return false;}catch(InvalidComObjectException){return true;}}
}
public sealed class LifetimeActiveApplication {
 public LifetimeNativeHost Book,Sheet,Selected;
 public object ActiveWorkbook{get{return Book.Acquire();}}
 public object ActiveSheet{get{return Sheet.Acquire();}}
 public object Selection{get{return Selected.Acquire();}}
}
public sealed class LifetimePrepareApplication {
 public LifetimeNativeHost Native; public bool FailOnSheet;
 public object ActiveProtectedViewWindow{get{return null;}}
 public object StatusBar{get;set;}
 public object Selection{get{return FailOnSheet?(object)new LifetimeSelection(this):Native.Acquire();}}
}
public sealed class LifetimeSelection {
 readonly LifetimePrepareApplication app;public LifetimeSelection(LifetimePrepareApplication value){app=value;}
 public object Worksheet{get{return app.Native.Acquire();}}
}
public sealed class LifetimeRestoreSheet {
 public readonly Dictionary<int,double> Values=new Dictionary<int,double>{{2,99},{3,903},{4,99}};public bool FailFirst;
 public LifetimeRestoreRanges Range{get{return new LifetimeRestoreRanges(this);}}
}
public sealed class LifetimeRestoreRanges {
 readonly LifetimeRestoreSheet sheet;public LifetimeRestoreRanges(LifetimeRestoreSheet s){sheet=s;}
 public LifetimeRestoreRange this[string address]{get{string[] a=address.Split(':');return this[a[0],a[a.Length-1]];}}
 public LifetimeRestoreRange this[string first,string last]{get{if(first!=last)throw new Exception("Would bridge hidden row");return new LifetimeRestoreRange(sheet,Int32.Parse(first.Substring(3)));}}
}
public sealed class LifetimeRestoreRange {
 readonly LifetimeRestoreSheet sheet;readonly int row;public LifetimeRestoreRange(LifetimeRestoreSheet s,int r){sheet=s;row=r;}
 public bool HasFormula{get{return false;}}
 public object NumberFormat{get{return "0.00";}set{if(!Object.Equals(value,"0.00"))throw new Exception("Format changed");}}
 public object Value2{get{return sheet.Values[row];}set{if(sheet.FailFirst&&row==2)throw new COMException("synthetic recovery write failure");var a=value as Array;sheet.Values[row]=Convert.ToDouble(a==null?value:a.GetValue(0,0));}}
}
public sealed class LifetimeRestoreBook{public string Name{get{return "Synthetic.xlsx";}}}
// Managed Excel surface for entering the real Prepare/Apply/cancel/rollback paths.
public sealed class LifetimeApplyCollection {
 readonly object[] values;public LifetimeApplyCollection(params object[] items){values=items;}
 public int Count{get{return values.Length;}}public object this[int index]{get{return values[index-1];}}
}
public sealed class LifetimeApplyCount {public int Count{get;set;}}
public sealed class LifetimeApplyVisibility {public bool Hidden{get{return false;}}}
public sealed class LifetimeApplyWindow {public LifetimeApplyCollection SelectedSheets{get{return new LifetimeApplyCollection(new object());}}}
public sealed class LifetimeApplyBook {public bool ReadOnly{get{return false;}}public bool MultiUserEditing{get{return false;}}public string Name{get{return "Synthetic.xlsx";}}}
public sealed class LifetimeApplySort {public LifetimeApplyCollection SortFields{get{return new LifetimeApplyCollection();}}}
public sealed class LifetimeApplyBars {public bool GetEnabledMso(string name){return false;}}
public sealed class LifetimeApplyApplication {
 public readonly LifetimeApplyBook Book=new LifetimeApplyBook();public readonly LifetimeApplySheet Sheet;public readonly LifetimeApplyRange Selected;
 public Action BeforeWorkbookGrab;public bool EnableEvents{get;set;}public bool ScreenUpdating{get;set;}public object Calculation{get;set;}public object StatusBar{get;set;}
 public LifetimeApplyApplication(){Sheet=new LifetimeApplySheet(this);Selected=new LifetimeApplyRange(Sheet,2,4,false);EnableEvents=true;ScreenUpdating=true;Calculation=-4105;StatusBar="original";}
 public object ActiveProtectedViewWindow{get{return null;}}public object ActiveWorkbook{get{var callback=BeforeWorkbookGrab;BeforeWorkbookGrab=null;if(callback!=null)callback();return Book;}}
 public object ActiveSheet{get{return Sheet;}}public object Selection{get{return Selected;}}public LifetimeApplyWindow ActiveWindow{get{return new LifetimeApplyWindow();}}
 public object Intersect(object left,object right){return right;}public LifetimeApplyBars CommandBars{get{return new LifetimeApplyBars();}}
}
public sealed class LifetimeApplySheet {
 readonly LifetimeApplyApplication app;public readonly Dictionary<int,double> Values=new Dictionary<int,double>{{1,901},{2,12},{3,903},{4,14},{5,905}};public readonly List<int> Writes=new List<int>();
 public LifetimeApplySheet(LifetimeApplyApplication value){app=value;}public object Parent{get{return app.Book;}}public string Name{get{return "Synthetic";}}
 public bool ProtectContents{get{return false;}}public bool ProtectDrawingObjects{get{return false;}}public bool ProtectScenarios{get{return false;}}
 public LifetimeApplyCollection ListObjects{get{return new LifetimeApplyCollection();}}public LifetimeApplyCollection PivotTables(){return new LifetimeApplyCollection();}
 public LifetimeApplySort Sort{get{return new LifetimeApplySort();}}public LifetimeApplyRanges Range{get{return new LifetimeApplyRanges(this);}}
}
public sealed class LifetimeApplyRanges {
 readonly LifetimeApplySheet sheet;public LifetimeApplyRanges(LifetimeApplySheet value){sheet=value;}
 public LifetimeApplyRange this[string address]{get{var parts=address.Split(':');return this[parts[0],parts[parts.Length-1]];}}
 public LifetimeApplyRange this[string first,string last]{get{return new LifetimeApplyRange(sheet,Int32.Parse(first.Substring(3)),Int32.Parse(last.Substring(3)),false);}}
}
public sealed class LifetimeApplyRange {
 readonly LifetimeApplySheet sheet;readonly int first,last;readonly bool visible;
 public LifetimeApplyRange(LifetimeApplySheet value,int f,int l,bool v){sheet=value;first=f;last=l;visible=v;}
 public object Worksheet{get{return sheet;}}public int Row{get{return first;}}public int Column{get{return 5;}}public long CountLarge{get{return last-first+1;}}
 public string Address{get{return first==last?"$E$"+first:"$E$"+first+":$E$"+last;}}
 public LifetimeApplyCount Columns{get{return new LifetimeApplyCount{Count=1};}}public LifetimeApplyCount Rows{get{return new LifetimeApplyCount{Count=last-first+1};}}
 public LifetimeApplyCollection Areas{get{return visible?new LifetimeApplyCollection(new LifetimeApplyRange(sheet,2,2,false),new LifetimeApplyRange(sheet,4,4,false)):new LifetimeApplyCollection(this);}}
 public LifetimeApplyVisibility EntireColumn{get{return new LifetimeApplyVisibility();}}public LifetimeApplyVisibility EntireRow{get{return new LifetimeApplyVisibility();}}
 public bool MergeCells{get{return false;}}public bool HasArray{get{return false;}}public bool HasSpill{get{return false;}}public bool HasFormula{get{return false;}}
 public object SpecialCells(int kind){if(kind==12)return new LifetimeApplyRange(sheet,first,last,true);throw new COMException("No validation cells",unchecked((int)0x800A03EC));}
 public object NumberFormat{get{return "0.00";}set{if(!Object.Equals(value,"0.00"))throw new Exception("Format changed");}}
 public object Value2{get{if(first==last)return sheet.Values[first];var result=new object[last-first+1,1];for(int i=first;i<=last;i++)result[i-first,0]=sheet.Values[i];return result;}
  set{for(int i=first;i<=last;i++){if(i!=2&&i!=4)throw new Exception("Hidden or outside write");sheet.Writes.Add(i);var a=value as Array;sheet.Values[i]=Convert.ToDouble(a==null?value:a.GetValue(i-first,0));}}}
}

public sealed class EpochTestConnection : System.Runtime.InteropServices.ComTypes.IConnectionPoint
{
 public string Failure; public int Advises,Unadvises; public object Sink; public Action OnUnadvise; public readonly HashSet<int> Cookies=new HashSet<int>{99};
 public void GetConnectionInterface(out Guid iid){iid=new Guid("00024413-0000-0000-C000-000000000046");}
 public void GetConnectionPointContainer(out System.Runtime.InteropServices.ComTypes.IConnectionPointContainer source){source=null;throw new NotSupportedException();}
 public void Advise(object sink,out int cookie){Advises++;Sink=sink;cookie=Failure=="advise-before-cookie"||Failure=="zero-cookie"?0:73;if(cookie!=0)Cookies.Add(cookie);if(Failure=="advise-before-cookie"||Failure=="advise-after-cookie")throw new COMException("Synthetic Advise failure");}
 public void Unadvise(int cookie){Unadvises++;if(OnUnadvise!=null)OnUnadvise();if(cookie!=73)throw new Exception("Wrong or foreign subscription cookie");Cookies.Remove(cookie);if(Failure=="unadvise")throw new COMException("Synthetic Unadvise failure");}
 public void EnumConnections(out System.Runtime.InteropServices.ComTypes.IEnumConnections values){values=null;throw new NotSupportedException();}
}
public sealed class EpochTestSource : System.Runtime.InteropServices.ComTypes.IConnectionPointContainer
{
 public readonly EpochTestConnection Point=new EpochTestConnection(); public bool FailFind,NullPoint; public int Finds; public Guid Requested;
 public void EnumConnectionPoints(out System.Runtime.InteropServices.ComTypes.IEnumConnectionPoints values){values=null;throw new NotSupportedException();}
 public void FindConnectionPoint(ref Guid iid,out System.Runtime.InteropServices.ComTypes.IConnectionPoint point){Finds++;Requested=iid;point=null;if(FailFind)throw new COMException("Synthetic FindConnectionPoint failure");if(!NullPoint)point=Point;}
}

internal static class ComLifetimeTests {
 const BindingFlags Hidden=BindingFlags.Instance|BindingFlags.NonPublic;
 static int passed,failed;
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);}
 static void Test(string name,Action action){try{action();passed++;Console.WriteLine("PASS "+name);}catch(Exception e){failed++;Console.WriteLine("FAIL "+name+": "+e);}}
 static void Call(object instance,string method,params object[] args){try{instance.GetType().GetMethod(method,Hidden).Invoke(instance,args);}catch(TargetInvocationException e){throw e.InnerException;}}
 static ComScope CountingScope(Action<object> release){return (ComScope)typeof(ComScope).GetConstructor(Hidden,null,new[]{typeof(Action<object>)},null).Invoke(new object[]{release});}
 static PreparedPaste Prepared(ComScope refs){return (PreparedPaste)typeof(PreparedPaste).GetConstructor(Hidden,null,new[]{typeof(ComScope)},null).Invoke(new object[]{refs});}
 static ClipboardSnapshot Source(){return new ClipboardSnapshot("unit",1,1,1,true,new[]{CellValue.Number(85)},"No Excel or clipboard used");}
 sealed class Bundle : IDisposable {
  public readonly LifetimeNativeHost Book=new LifetimeNativeHost(),Sheet=new LifetimeNativeHost(),Selection=new LifetimeNativeHost();
  public readonly PreparedPaste Paste;
  public Bundle(){var refs=new ComScope();Paste=Prepared(refs);Paste.Book=refs.Own(Book.Acquire());Paste.Sheet=refs.Own(Sheet.Acquire());Paste.Selection=refs.Own(Selection.Acquire());Paste.Address="$E$2";Paste.SheetName="Synthetic";}
  public bool Released{get{return LifetimeNativeHost.Released(Book.Last)&&LifetimeNativeHost.Released(Sheet.Last)&&LifetimeNativeHost.Released(Selection.Last);}}
  public void Dispose(){try{Paste.Dispose();}finally{Book.Dispose();Sheet.Dispose();Selection.Dispose();}}
 }
 static PreparedPaste RestorePrepared(ComScope scope,LifetimeRestoreSheet sheet){
  var source=new ClipboardSnapshot("unit",1,2,1,true,new[]{CellValue.Number(1),CellValue.Number(2)},"No real Excel");
  var selection=new SelectionSnapshot("sheet",2,4,5,1,3,1,false,false,new[]{new TargetCell("sheet",2,5,false),new TargetCell("sheet",4,5,false)});
  var p=Prepared(scope);p.Book=new LifetimeRestoreBook();p.Sheet=sheet;p.Selection=new object();p.SheetName="Synthetic";p.Address="$E$2:$E$4";p.Plan=Planner.Build(source,selection);
  p.Before=new[]{new CellState{Row=2,Column=5,Address="$E$2",Format="0.00",Value=CellValue.Number(12)},new CellState{Row=4,Column=5,Address="$E$4",Format="0.00",Value=CellValue.Number(14)}};return p;
 }
 static void Reentry(string mode){
  using(var native=new LifetimeNativeHost())using(var fresh=new Bundle()){
   var app=new LifetimeApplyApplication();var engine=new ExcelEngine(app);
   var source=new ClipboardSnapshot("unit",1,2,1,true,new[]{CellValue.Number(1),CellValue.Number(2)},"No Excel or clipboard");
   var p=engine.Prepare(source);var refs=(ComScope)typeof(PreparedPaste).GetField("references",Hidden).GetValue(p);object sentinel=refs.Own(native.Acquire());int refused=0,cancelCalls=0;bool attempted=false;
   Action nested=delegate{
    attempted=true;bool blocked=false;PreparedPaste candidate=mode=="different"?fresh.Paste:p;
    try{engine.Apply(candidate,null,null);}catch(ValidationException e){blocked=e.Code=="VCP-BUSY";}
    Check(blocked,"Nested Apply did not reject with busy");refused++;
    Check(!p.IsDisposed&&p.Book!=null&&p.Sheet!=null&&!LifetimeNativeHost.Released(sentinel),"Nested refusal consumed outer ownership");
    if(mode=="different")Check(fresh.Paste.IsDisposed&&fresh.Released,"Nested new ownership was not consumed");
   };
   if(mode=="prevalidation")app.BeforeWorkbookGrab=nested;
   bool rolledBack=false;
   try{engine.Apply(p,delegate{
    cancelCalls++;if(!attempted&&(mode!="rollback"||cancelCalls==2))nested();
    return mode=="rollback"&&cancelCalls==2;
   },null);}catch(InvalidOperationException e){if(mode!="rollback")throw;rolledBack=e.InnerException is OperationCanceledException;}
   Check(refused==1&&attempted,"Expected one real callback reentry");
   Check(!engine.RecoveryRequired&&app.EnableEvents&&app.ScreenUpdating&&Object.Equals(app.Calculation,-4105)&&Object.Equals(app.StatusBar,"original"),"Outer transaction globals or recovery state damaged");
   Check(app.Sheet.Values[1]==901&&app.Sheet.Values[3]==903&&app.Sheet.Values[5]==905,"Reentry altered hidden or outside cells");
   Check(typeof(ExcelEngine).GetField("inFlight",Hidden).GetValue(engine)==null&&!(bool)typeof(ExcelEngine).GetField("busy",Hidden).GetValue(engine),"Operation entry state stayed occupied");
   if(mode=="rollback"){
    Check(rolledBack&&engine.LastOutcome=="rolled-back"&&app.Sheet.Values[2]==12&&app.Sheet.Values[4]==14&&app.Sheet.Writes.SequenceEqual(new[]{2,2,4}),"Callback cancellation skipped actual touched-cell restoration");
    Check(p.IsDisposed&&LifetimeNativeHost.Released(sentinel),"Rolled-back record ownership leaked");
   }else{
    Check(engine.LastOutcome=="success"&&app.Sheet.Values[2]==1&&app.Sheet.Values[4]==2&&app.Sheet.Writes.SequenceEqual(new[]{2,4}),"Outer Apply did not complete after reentry refusal");
    Check(!p.IsDisposed&&!LifetimeNativeHost.Released(sentinel),"Successful outer Undo ownership was discarded");
   }
   engine.Dispose();Check(p.IsDisposed&&LifetimeNativeHost.Released(sentinel),"Engine shutdown retained outer ownership");
  }
 }

 [UnmanagedFunctionPointer(CallingConvention.StdCall)]
 delegate int NativeEventInvoke(IntPtr self,int dispId,ref Guid iid,uint lcid,ushort flags,IntPtr parameters,IntPtr result,IntPtr exception,IntPtr argumentError);
 [UnmanagedFunctionPointer(CallingConvention.StdCall)]
 delegate int NativeTypeInfoCount(IntPtr self,out uint count);
 [UnmanagedFunctionPointer(CallingConvention.StdCall)]
 delegate int NativeTypeInfo(IntPtr self,uint index,uint lcid,out IntPtr info);
 [StructLayout(LayoutKind.Sequential)]
 struct EventParameters {public IntPtr Arguments,NamedIds;public uint Count,NamedCount;}
 static readonly Guid EventsIid=new Guid("00024413-0000-0000-C000-000000000046"),DispatchIid=new Guid("00020400-0000-0000-C000-000000000046");
 sealed class NativeEventProbe:IDisposable {
  public readonly UndoEpoch Epoch;public readonly object Sink;public IntPtr Pointer;readonly NativeEventInvoke invoke;
  public NativeEventProbe(){
   Epoch=new UndoEpoch(new object());
   Sink=typeof(UndoEpoch.EventSink).GetConstructor(Hidden,null,new[]{typeof(UndoEpoch)},null).Invoke(new object[]{Epoch});
   IntPtr unknown=Marshal.GetIUnknownForObject(Sink);try{Guid iid=EventsIid;Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown,ref iid,out Pointer));}finally{Marshal.Release(unknown);}
   invoke=(NativeEventInvoke)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(Pointer),6*IntPtr.Size),typeof(NativeEventInvoke));
  }
  public int Invoke(int dispId,IntPtr parameters,IntPtr result){Guid iid=Guid.Empty;return invoke(Pointer,dispId,ref iid,0,1,parameters,result,IntPtr.Zero,IntPtr.Zero);}
  public int InvokeWithIid(int dispId,Guid iid){return invoke(Pointer,dispId,ref iid,0,1,new IntPtr(1),IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);}
  public IntPtr Slot(int index){return Marshal.ReadIntPtr(Marshal.ReadIntPtr(Pointer),index*IntPtr.Size);}
  public void Dispose(){Epoch.Dispose();if(Pointer!=IntPtr.Zero){Marshal.Release(Pointer);Pointer=IntPtr.Zero;}GC.KeepAlive(Sink);}
 }
 static UndoEpoch ConnectEpoch(EpochTestSource source,Action<object> release){
  return (UndoEpoch)typeof(UndoEpoch).GetConstructor(Hidden,null,new[]{typeof(System.Runtime.InteropServices.ComTypes.IConnectionPointContainer),typeof(Action<object>)},null).Invoke(new object[]{source,release});
 }
 static void RawEventTests(){
  Test("event sink exposes exact AppEvents and IDispatch QI with stable IUnknown identity",delegate{using(var probe=new NativeEventProbe()){
   Guid dispatch=DispatchIid;IntPtr dispatchPointer;Marshal.ThrowExceptionForHR(Marshal.QueryInterface(probe.Pointer,ref dispatch,out dispatchPointer));
   try{Guid unknown=new Guid("00000000-0000-0000-C000-000000000046");IntPtr a,b;Marshal.ThrowExceptionForHR(Marshal.QueryInterface(probe.Pointer,ref unknown,out a));try{Marshal.ThrowExceptionForHR(Marshal.QueryInterface(dispatchPointer,ref unknown,out b));try{Check(a==b,"QI changed COM identity");}finally{Marshal.Release(b);}}finally{Marshal.Release(a);}}finally{Marshal.Release(dispatchPointer);}
   Guid missing=new Guid("786338C4-6BCB-4DD1-8F00-6D57BBFE2BBF");IntPtr unavailable;Check(Marshal.QueryInterface(probe.Pointer,ref missing,out unavailable)==unchecked((int)0x80004002)&&unavailable==IntPtr.Zero,"Unknown QI incorrectly exposed an interface");
   Guid managed=new Guid("C3FCC19E-A970-11D2-8B5A-00A0C9B7C9C4");Check(Marshal.QueryInterface(probe.Pointer,ref managed,out unavailable)==unchecked((int)0x80004002)&&unavailable==IntPtr.Zero,"Sink exposed the managed-object unwrapping interface");
  }});
  Test("native IDispatch type-info slots use the expected ABI",delegate{using(var probe=new NativeEventProbe()){
   var countCall=(NativeTypeInfoCount)Marshal.GetDelegateForFunctionPointer(probe.Slot(3),typeof(NativeTypeInfoCount));uint count=999;Check(countCall(probe.Pointer,out count)==0&&count==0,"GetTypeInfoCount slot/signature mismatch");
   var infoCall=(NativeTypeInfo)Marshal.GetDelegateForFunctionPointer(probe.Slot(4),typeof(NativeTypeInfo));IntPtr info=new IntPtr(1);Check(infoCall(probe.Pointer,0,0,out info)==unchecked((int)0x80004001)&&info==IntPtr.Zero,"GetTypeInfo did not fail with a cleared pointer");
  }});
  Test("all fourteen native event IDs invalidate without reading DISPPARAMS",delegate{using(var probe=new NativeEventProbe()){
   int[] ids={1558,1561,1562,1564,1565,1567,1568,1569,1570,1571,1573,1556,1557,3079};long version=probe.Epoch.Version;
   foreach(int id in ids){Check(probe.Invoke(id,new IntPtr(1),IntPtr.Zero)==0,"Native event failed: "+id);Check(probe.Epoch.Version==++version,"Observed event missing: "+id);}
  }});
  Test("native unknown suppressed and disposed events preserve conservative epoch rules",delegate{using(var probe=new NativeEventProbe()){
   long before=probe.Epoch.Version;Check(probe.Invoke(9999,new IntPtr(1),IntPtr.Zero)==0&&probe.Epoch.Version==before,"Unknown event changed epoch");
   probe.Epoch.Suppress=true;probe.Invoke(1564,new IntPtr(1),IntPtr.Zero);Check(probe.Epoch.Version==before,"Suppressed own event changed epoch");probe.Epoch.Invalidate();Check(probe.Epoch.Version==before+1,"Explicit invalidation incorrectly obeyed suppression");
   probe.Epoch.Suppress=false;probe.Epoch.Dispose();long disposed=probe.Epoch.Version;probe.Invoke(1570,new IntPtr(1),IntPtr.Zero);Check(probe.Epoch.Version==disposed&&!probe.Epoch.Available,"Callback after Dispose revived observer");probe.Epoch.Dispose();Check(probe.Epoch.Version==disposed,"Repeat Dispose changed epoch");
  }});
  Test("native byref Cancel arguments and canaries stay unchanged while result is VT_EMPTY",delegate{using(var probe=new NativeEventProbe()){
   int variantSize=IntPtr.Size==8?24:16;IntPtr block=Marshal.AllocHGlobal(112),parameters=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(EventParameters))),result=Marshal.AllocHGlobal(variantSize);
   try{
    byte[] original=Enumerable.Repeat((byte)0x5a,112).ToArray();Marshal.Copy(original,0,block,original.Length);
    IntPtr args=IntPtr.Add(block,8),cancel=IntPtr.Add(block,96);Marshal.WriteInt16(cancel,-1);Marshal.WriteInt16(args,unchecked((short)0x400b));Marshal.WriteIntPtr(args,8,cancel);
    Marshal.WriteInt16(IntPtr.Add(args,variantSize),9);Marshal.WriteIntPtr(IntPtr.Add(args,variantSize),8,new IntPtr(1));
    Marshal.StructureToPtr(new EventParameters{Arguments=args,Count=2},parameters,false);Marshal.Copy(block,original,0,original.Length);
    byte[] filled=Enumerable.Repeat((byte)0xcc,variantSize).ToArray();Marshal.Copy(filled,0,result,filled.Length);
    Check(probe.Invoke(1570,parameters,result)==0,"BeforeClose native callback failed");
    byte[] after=new byte[original.Length];Marshal.Copy(block,after,0,after.Length);Check(original.SequenceEqual(after)&&Marshal.ReadInt16(cancel)==-1,"Event argument or Cancel changed");
    Check(Marshal.ReadInt16(result)==0,"Void event result was not VT_EMPTY");
   }finally{Marshal.FreeHGlobal(result);Marshal.FreeHGlobal(parameters);Marshal.FreeHGlobal(block);}
  }});
  Test("native non-null riid refuses without dereferencing arguments or observing",delegate{using(var probe=new NativeEventProbe()){
   long before=probe.Epoch.Version;Check(probe.InvokeWithIid(1564,EventsIid)==unchecked((int)0x80020001)&&probe.Epoch.Version==before,"Invalid Invoke riid was accepted");
  }});
  Test("dedicated subscription owns one connection point and never unadvises a peer",delegate{
   var source=new EpochTestSource();var released=new List<object>();var epoch=ConnectEpoch(source,released.Add);
   Check(epoch.Available&&source.Finds==1&&source.Requested==EventsIid&&source.Point.Advises==1,"Did not establish exactly one event subscription");
   epoch.Dispose();epoch.Dispose();Check(source.Point.Unadvises==1&&released.Count==1&&Object.ReferenceEquals(released[0],source.Point)&&source.Point.Cookies.SetEquals(new[]{99}),"Subscription released a borrowed source or peer cookie");
  });
  Test("failed FindConnectionPoint leaves Undo unavailable with no ownership release",delegate{
   var source=new EpochTestSource{FailFind=true};int released=0;using(var epoch=ConnectEpoch(source,delegate(object value){released++;})){Check(!epoch.Available&&epoch.Version>0&&source.Point.Advises==0&&released==0,"Find failure created a partial subscription");}
  });
  Test("null connection point fails closed without calling Advise",delegate{
   var source=new EpochTestSource{NullPoint=true};int released=0;using(var epoch=ConnectEpoch(source,delegate(object value){released++;})){Check(!epoch.Available&&source.Point.Advises==0&&released==0,"Null connection was treated as available");}
  });
  foreach(string failure in new[]{"advise-before-cookie","advise-after-cookie","zero-cookie"}){string mode=failure;Test("partial event attach releases its acquired point: "+mode,delegate{
   var source=new EpochTestSource();source.Point.Failure=mode;int released=0;var epoch=ConnectEpoch(source,delegate(object value){Check(Object.ReferenceEquals(value,source.Point),"Released wrong connection");released++;});
   Check(!epoch.Available&&released==1&&source.Point.Unadvises==(mode=="advise-after-cookie"?1:0)&&source.Point.Cookies.SetEquals(new[]{99}),"Failed attach leaked its point/cookie or enabled Undo");
   epoch.Dispose();Check(released==1,"Failed attach was released twice");
  });}
  Test("Unadvise failure still releases owned connection exactly once",delegate{
   var source=new EpochTestSource();source.Point.Failure="unadvise";int released=0;var epoch=ConnectEpoch(source,delegate(object value){released++;});
   IntPtr pointer=Marshal.GetComInterfaceForObject(source.Point.Sink,typeof(IRawExcelEventDispatch),CustomQueryInterfaceMode.Ignore);
   try{var invoke=(NativeEventInvoke)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(pointer),6*IntPtr.Size),typeof(NativeEventInvoke));Action late=delegate{long before=epoch.Version;Guid iid=Guid.Empty;Check(invoke(pointer,1564,ref iid,0,1,new IntPtr(1),IntPtr.Zero,IntPtr.Zero,IntPtr.Zero)==0&&epoch.Version==before,"Late event revived disposed epoch");};source.Point.OnUnadvise=late;epoch.Dispose();late();epoch.Dispose();}
   finally{Marshal.Release(pointer);}
   Check(!epoch.Available&&released==1&&source.Point.Unadvises==1&&source.Point.Cookies.SetEquals(new[]{99}),"Unadvise failure skipped RCW release or touched peer");
  });
  Test("connection release exception cannot revive or repeat disposed observer cleanup",delegate{
   var source=new EpochTestSource();int released=0;var epoch=ConnectEpoch(source,delegate(object value){released++;throw new InvalidOperationException("Synthetic connection release failure");});epoch.Dispose();long version=epoch.Version;epoch.Dispose();
   Check(!epoch.Available&&released==1&&source.Point.Unadvises==1&&epoch.Version==version,"Release failure made disposal non-idempotent");
  });
 }

 [STAThread]static int Main(){
  RawEventTests();
  Test("scope releases a real acquired RCW before native host shutdown",delegate{using(var h=new LifetimeNativeHost()){object o;using(var refs=new ComScope()){o=refs.Own(h.Acquire());Check(!LifetimeNativeHost.Released(o),"Reference released while in scope");}Check(LifetimeNativeHost.Released(o),"RCW deferred until CLR shutdown");Check(h.ReleaseBase()==0,"Native reference leaked");}});
  Test("repeated native returns of same identity are released by acquisition count",delegate{using(var h=new LifetimeNativeHost()){var refs=new ComScope();object a=refs.Own(h.Acquire()),b=refs.Own(h.Acquire());Check(Object.ReferenceEquals(a,b),"Expected shared RCW identity");refs.Dispose();refs.Dispose();Check(LifetimeNativeHost.Released(a)&&h.ReleaseBase()==0,"Duplicate acquisition leaked or repeated Dispose over-released");}});
  Test("one owned acquisition never final-releases a borrowed acquisition",delegate{using(var h=new LifetimeNativeHost()){object owned=h.Acquire(),borrowed=h.Acquire();using(var refs=new ComScope()){refs.Own(owned);}Check(!LifetimeNativeHost.Released(borrowed),"Scope final-released another owner's reference");Marshal.ReleaseComObject(borrowed);Check(LifetimeNativeHost.Released(borrowed)&&h.ReleaseBase()==0,"Owned acquisition was not released exactly once");}});
  Test("exception unwinding releases acquired references without touching borrowed ones",delegate{using(var a=new LifetimeNativeHost())using(var b=new LifetimeNativeHost()){object borrowed=b.Acquire();try{using(var refs=new ComScope()){refs.Own(a.Acquire());throw new InvalidOperationException("synthetic failure");}}catch(InvalidOperationException){}Check(LifetimeNativeHost.Released(a.Last)&&!LifetimeNativeHost.Released(borrowed),"Failure cleanup ownership mismatch");Marshal.ReleaseComObject(borrowed);}});
  Test("scope drains every acquisition in reverse order even when a release fails",delegate{object same=new object(),other=new object();var seen=new List<object>();var refs=CountingScope(delegate(object o){seen.Add(o);if(Object.ReferenceEquals(o,other))throw new InvalidOperationException("synthetic release failure");});refs.Own(same);refs.Own(other);refs.Own(same);bool thrown=false;try{refs.Dispose();}catch(InvalidOperationException){thrown=true;}refs.Dispose();Check(thrown&&seen.SequenceEqual(new[]{same,other,same}),"Cleanup deduplicated identity or stopped at failure");});
  Test("late acquisition passed to a disposed scope is released before refusal",delegate{using(var h=new LifetimeNativeHost()){var refs=new ComScope();refs.Dispose();bool thrown=false;try{refs.Own(h.Acquire());}catch(ObjectDisposedException){thrown=true;}Check(thrown&&LifetimeNativeHost.Released(h.Last)&&h.ReleaseBase()==0,"Disposed scope leaked its incoming acquisition");}});
  Test("prepared paste disposes all retained book sheet selection references once",delegate{using(var b=new Bundle()){b.Paste.Dispose();b.Paste.Dispose();Check(b.Released&&b.Paste.IsDisposed&&b.Paste.Book==null&&b.Paste.Sheet==null&&b.Paste.Selection==null,"Prepared references remained live");}});
  Test("prepared paste disposal preserves another owner's acquired book reference",delegate{using(var b=new Bundle()){object borrowed=b.Book.Acquire();b.Paste.Dispose();Check(!LifetimeNativeHost.Released(borrowed)&&LifetimeNativeHost.Released(b.Sheet.Last)&&LifetimeNativeHost.Released(b.Selection.Last),"Prepared disposal crossed ownership boundary");Marshal.ReleaseComObject(borrowed);Check(b.Released,"Prepared retained acquisition leaked");}});
  Test("partial Prepare failure releases native selection acquired before validation",delegate{using(var h=new LifetimeNativeHost()){var app=new LifetimePrepareApplication{Native=h,StatusBar="original"};using(var engine=new ExcelEngine(app)){bool refused=false;try{engine.Prepare(Source());}catch(ValidationException e){refused=e.Code=="VCP-SELECTION";}Check(refused&&LifetimeNativeHost.Released(h.Last)&&Object.Equals(app.StatusBar,"original"),"Failed Prepare kept selection or status");}}});
  Test("partial Prepare failure also releases a sheet acquired before Parent fails",delegate{using(var h=new LifetimeNativeHost()){var app=new LifetimePrepareApplication{Native=h,FailOnSheet=true,StatusBar="original"};using(var engine=new ExcelEngine(app)){bool refused=false;try{engine.Prepare(Source());}catch(ValidationException e){refused=e.Code=="VCP-SELECTION";}Check(refused&&LifetimeNativeHost.Released(h.Last),"Intermediate sheet survived failed Prepare");}}});
  Test("rejected Apply consumes its prepared references and transient active objects",delegate{using(var b=new Bundle())using(var activeBook=new LifetimeNativeHost()){var app=new LifetimeActiveApplication{Book=activeBook,Sheet=b.Sheet,Selected=b.Selection};using(var engine=new ExcelEngine(app)){bool refused=false;try{engine.Apply(b.Paste,null,null);}catch(ValidationException e){refused=e.Code=="VCP-TARGET-CHANGED";}Check(refused&&b.Paste.IsDisposed&&b.Released&&LifetimeNativeHost.Released(activeBook.Last),"Apply refusal leaked prepared or revalidation acquisitions");}}});
  Test("replacing undo releases prior record while retaining the new record",delegate{using(var first=new Bundle())using(var second=new Bundle())using(var engine=new ExcelEngine(new object())){Call(engine,"KeepUndo",first.Paste);Call(engine,"KeepUndo",second.Paste);Check(first.Released&&first.Paste.IsDisposed&&!second.Paste.IsDisposed&&!second.Released,"Undo replacement ownership wrong");Call(engine,"ClearUndo");Check(second.Released&&second.Paste.IsDisposed,"New Undo record was not released");}});
  Test("keeping the identical undo record does not release it prematurely",delegate{using(var b=new Bundle())using(var engine=new ExcelEngine(new object())){Call(engine,"KeepUndo",b.Paste);Call(engine,"KeepUndo",b.Paste);Check(!b.Paste.IsDisposed&&!b.Released,"Identical undo record disposed");Call(engine,"ClearUndo");Check(b.Released,"Identical record leaked at final clear");}});
  Test("engine shutdown disposes its undo record and is repeatable",delegate{using(var b=new Bundle()){var engine=new ExcelEngine(new object());Call(engine,"KeepUndo",b.Paste);engine.Dispose();engine.Dispose();Check(b.Paste.IsDisposed&&b.Released,"Engine shutdown retained workbook references");}});
  Test("Undo refusal releases only temporary active workbook acquisition",delegate{using(var b=new Bundle()){var app=new LifetimeActiveApplication{Book=b.Book,Sheet=b.Sheet,Selected=b.Selection};var engine=new ExcelEngine(app);Call(engine,"KeepUndo",b.Paste);bool refused=false;try{engine.UndoLast();}catch(ValidationException e){refused=e.Code=="VCP-UNDO-INVALID";}Check(refused&&!b.Paste.IsDisposed&&!LifetimeNativeHost.Released(b.Book.Last),"Undo refusal discarded owned record");engine.Dispose();Check(b.Released,"Undo refusal left an extra active-workbook acquisition");}});
  Test("IUnknown identity comparison balances temporary native AddRefs",delegate{using(var h=new LifetimeNativeHost()){object value=h.Acquire();for(int i=0;i<10;i++)Check(ExcelEngine.Same(value,value),"Identity changed");Marshal.ReleaseComObject(value);Check(LifetimeNativeHost.Released(value)&&h.ReleaseBase()==0,"Identity comparison leaked native references");}});
  Test("failed undo replacement clears stale state and successful rollback releases new ownership",delegate{using(var native=new LifetimeNativeHost())using(var engine=new ExcelEngine(new object())){
   var priorScope=CountingScope(delegate(object value){throw new InvalidOperationException("synthetic prior release failure");});priorScope.Own(new object());var prior=Prepared(priorScope);Call(engine,"KeepUndo",prior);
   typeof(ExcelEngine).GetField("after",Hidden).SetValue(engine,new CellState[1]);typeof(ExcelEngine).GetField("undoAllowed",Hidden).SetValue(engine,true);
   var scope=new ComScope();object sentinel=scope.Own(native.Acquire());var sheet=new LifetimeRestoreSheet();var p=RestorePrepared(scope,sheet);bool failedTransfer=false;
   try{Call(engine,"KeepUndo",p);}catch(InvalidOperationException){failedTransfer=true;}
   Check(failedTransfer&&prior.IsDisposed&&typeof(ExcelEngine).GetField("after",Hidden).GetValue(engine)==null&&!(bool)typeof(ExcelEngine).GetField("undoAllowed",Hidden).GetValue(engine),"Prior undo metadata survived failed ownership transfer");
   Call(engine,"RecoverAfterWrite",p,new COMException("original write failure"),null);
   Check(engine.LastOutcome=="rolled-back"&&!engine.RecoveryRequired&&p.IsDisposed&&LifetimeNativeHost.Released(sentinel)&&typeof(ExcelEngine).GetField("undo",Hidden).GetValue(engine)==null,"Rolled-back failed transfer retained new workbook ownership");
   Check(sheet.Values[2]==12&&sheet.Values[3]==903&&sheet.Values[4]==14,"Rollback altered hidden row or missed original values");
  }});
  Test("partial recovery retains native ownership only until recovery record disposal",delegate{using(var native=new LifetimeNativeHost()){
   var engine=new ExcelEngine(new object());var scope=new ComScope();object sentinel=scope.Own(native.Acquire());var p=RestorePrepared(scope,new LifetimeRestoreSheet{FailFirst=true});bool failedRecovery=false;
   try{Call(engine,"RecoverAfterWrite",p,new COMException("original write failure"),null);}catch(RecoveryException){failedRecovery=true;}
   Check(failedRecovery&&engine.RecoveryRequired&&engine.LastOutcome=="recovery-required"&&!p.IsDisposed&&!LifetimeNativeHost.Released(sentinel)&&Object.ReferenceEquals(typeof(ExcelEngine).GetField("undo",Hidden).GetValue(engine),p),"Recovery-required record lost its ownership");
   engine.Dispose();Check(p.IsDisposed&&LifetimeNativeHost.Released(sentinel),"Recovery record retained native reference at engine shutdown");
  }});
  Test("same prepared reentry from actual Apply cancel callback preserves outer success",delegate{Reentry("same");});
  Test("new prepared reentry is consumed without damaging the active Apply",delegate{Reentry("different");});
  Test("same prepared reentry after a write preserves actual cancellation rollback",delegate{Reentry("rollback");});
  Test("same prepared reentry during real target revalidation is refused before ownership transfer",delegate{Reentry("prevalidation");});
  Console.WriteLine("RESULT: "+passed+" passed; "+failed+" failed");return failed==0?0:1;
 }
}
