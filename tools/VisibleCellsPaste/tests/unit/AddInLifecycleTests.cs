using System;
using System.Reflection;
using System.Runtime.InteropServices;
using VisibleCellsPaste;
public sealed class FakeAddInInstance { public object Object {get;set;} }
public sealed class FailingAddInInstance { public object Object {set {throw new InvalidOperationException("synthetic connection failure");}} }
public sealed class FakeStatusBarApplication {
 public string Failure;
 public object Current="owned";
 public object StatusBar {
  get {if(Failure=="invalid-get")throw new InvalidComObjectException("synthetic status getter shutdown");if(Failure=="other-get")throw new InvalidOperationException("synthetic status display failure");return Current;}
  set {if(Failure=="invalid-set")throw new InvalidComObjectException("synthetic status setter shutdown");Current=value;}
 }
}
internal static class AddInLifecycleTests {
 [DllImport("ole32.dll")] static extern int CreateStreamOnHGlobal(IntPtr memory,[MarshalAs(UnmanagedType.Bool)]bool deleteOnRelease,out IntPtr stream);
 static object NewComReference(){IntPtr pointer;Marshal.ThrowExceptionForHR(CreateStreamOnHGlobal(IntPtr.Zero,true,out pointer));try{return Marshal.GetObjectForIUnknown(pointer);}finally{Marshal.Release(pointer);}}
 static PreparedPaste OwnedSnapshot(object book,object sheet,object selection){var scope=new ComScope();scope.Own(book);scope.Own(sheet);scope.Own(selection);var p=(PreparedPaste)typeof(PreparedPaste).GetConstructor(F,null,new[]{typeof(ComScope)},null).Invoke(new object[]{scope});p.Book=book;p.Sheet=sheet;p.Selection=selection;return p;}
 static bool IsReleased(object value){try{IntPtr pointer=Marshal.GetIUnknownForObject(value);Marshal.Release(pointer);return false;}catch(InvalidComObjectException){return true;}}
 static int passed; static readonly BindingFlags F=BindingFlags.Instance|BindingFlags.NonPublic;
 static object Field(object value,string name){return value.GetType().GetField(name,F).GetValue(value);}
 static void SetField(object value,string name,object field){value.GetType().GetField(name,F).SetValue(value,field);}
 static void Check(bool ok,string name){if(!ok)throw new Exception(name);passed++;Console.WriteLine("PASS "+name);}
 static void ShutdownWithStatus(string failure,bool expectFailure,string name) {
  Array custom=new object[0];var addin=new AddIn();var app=new FakeStatusBarApplication{Failure=failure};
  addin.OnConnection(app,1,new FakeAddInInstance(),ref custom);
  object engine=Field(addin,"engine"),epoch=Field(engine,"epoch");
  bool workDisposed=false,statusDisposed=false;
  var workTimer=new System.Windows.Forms.Timer();workTimer.Disposed+=delegate{workDisposed=true;};
  var statusTimer=new System.Windows.Forms.Timer();statusTimer.Disposed+=delegate{statusDisposed=true;};
  SetField(addin,"timer",workTimer);SetField(addin,"statusTimer",statusTimer);
  SetField(addin,"ownStatus","owned");SetField(addin,"oldStatus","original");
  SetField(addin,"pending",new PreparedPaste());SetField(addin,"busy",true);
  bool rejected=false;try{addin.OnBeginShutdown(ref custom);}catch(InvalidOperationException){rejected=true;}
  Check(rejected==expectFailure&&workDisposed&&statusDisposed&&(bool)Field(epoch,"disposed")
   &&Field(addin,"timer")==null&&Field(addin,"statusTimer")==null&&Field(addin,"pending")==null
   &&Field(addin,"engine")==null&&Field(addin,"application")==null&&!(bool)Field(addin,"busy")
   &&addin.GetDiagnostics().Contains("connected=False")&&(failure!=null||Object.Equals(app.Current,"original")),name);
 }
 [STAThread] static int Main(){try{Array custom=new object[0];var addin=new AddIn();var instance=new FakeAddInInstance();var app=new object();
 addin.OnConnection(app,1,instance,ref custom);object first=Field(addin,"engine");object firstEpoch=Field(first,"epoch");
 Check(Object.ReferenceEquals(instance.Object,addin)&&addin.GetDiagnostics().Contains("connected=True"),"connection exposes callback object");
 addin.OnConnection(app,1,instance,ref custom);
 Check((bool)Field(firstEpoch,"disposed")&&!Object.ReferenceEquals(first,Field(addin,"engine")),"repeat connection disposes prior observer");
 addin.OnDisconnection(1,ref custom);addin.OnDisconnection(1,ref custom);
 Check(Field(addin,"engine")==null&&Field(addin,"application")==null&&addin.GetDiagnostics().Contains("connected=False"),"repeated disconnect leaves no app reference");
 bool rejected=false;try{addin.OnConnection(app,1,new FailingAddInInstance(),ref custom);}catch(InvalidOperationException){rejected=true;}
 Check(rejected&&Field(addin,"engine")==null&&Field(addin,"application")==null&&addin.GetDiagnostics().Contains("connected=False"),"partial connection failure cleans observer and reference");
 ShutdownWithStatus(null,false,"shutdown restores owned status and disposes both timers and observer");
 ShutdownWithStatus("invalid-get",false,"invalid COM status getter still completes shutdown cleanup");
 ShutdownWithStatus("invalid-set",false,"invalid COM status setter still completes shutdown cleanup");
 ShutdownWithStatus("other-get",true,"unexpected status failure propagates after guaranteed shutdown cleanup");
 object pasteControl=NewComReference();addin.Paste(pasteControl);Check(IsReleased(pasteControl),"disconnected paste releases its marshaled callback reference");
 object undoControl=NewComReference();addin.Undo(undoControl);Check(IsReleased(undoControl),"disconnected undo releases its marshaled callback reference");
 object busyControl=NewComReference();SetField(addin,"connected",true);SetField(addin,"busy",true);addin.Paste(busyControl);Check(IsReleased(busyControl)&&(bool)Field(addin,"busy"),"busy refusal releases callback without changing active operation");SetField(addin,"connected",false);SetField(addin,"busy",false);
 object firstControl=NewComReference();IntPtr sharedPointer=Marshal.GetIUnknownForObject(firstControl);object secondControl;try{secondControl=Marshal.GetObjectForIUnknown(sharedPointer);}finally{Marshal.Release(sharedPointer);}
 addin.Paste(firstControl);Check(!IsReleased(secondControl),"one callback does not final-release another acquired reference");addin.Undo(secondControl);Check(IsReleased(secondControl),"each independently marshaled callback reference is released once");
 object invalidInstance=NewComReference();bool invalidInstanceRejected=false;try{addin.OnConnection(new object(),1,invalidInstance,ref custom);}catch{invalidInstanceRejected=true;}Check(invalidInstanceRejected&&IsReleased(invalidInstance)&&Field(addin,"engine")==null,"failed connection releases its own COM add-in instance argument");
 var pendingBook=NewComReference();var pendingSheet=NewComReference();var pendingSelection=NewComReference();var pendingAddin=new AddIn();pendingAddin.OnConnection(new object(),1,new FakeAddInInstance(),ref custom);SetField(pendingAddin,"pending",OwnedSnapshot(pendingBook,pendingSheet,pendingSelection));pendingAddin.OnBeginShutdown(ref custom);Check(IsReleased(pendingBook)&&IsReleased(pendingSheet)&&IsReleased(pendingSelection),"shutdown releases every owned pending snapshot reference");
 var abandonedBook=NewComReference();var abandonedAddin=new AddIn();SetField(abandonedAddin,"pending",OwnedSnapshot(abandonedBook,null,null));SetField(abandonedAddin,"timer",new System.Windows.Forms.Timer());SetField(abandonedAddin,"busy",true);typeof(AddIn).GetMethod("RunPending",F).Invoke(abandonedAddin,new object[]{null,EventArgs.Empty});Check(IsReleased(abandonedBook)&&!(bool)Field(abandonedAddin,"busy"),"disconnected deferred command disposes untransferred work");
 var reconnectAddin=new AddIn();reconnectAddin.OnConnection(new FakeStatusBarApplication{Failure="other-get"},1,new FakeAddInInstance(),ref custom);SetField(reconnectAddin,"statusTimer",new System.Windows.Forms.Timer());SetField(reconnectAddin,"ownStatus","owned");SetField(reconnectAddin,"oldStatus","original");object reconnectInstance=NewComReference();bool reconnectRejected=false;try{reconnectAddin.OnConnection(new object(),1,reconnectInstance,ref custom);}catch(InvalidOperationException){reconnectRejected=true;}Check(reconnectRejected&&IsReleased(reconnectInstance)&&Field(reconnectAddin,"engine")==null&&Field(reconnectAddin,"application")==null,"prior disconnect failure still releases the new connection argument");
 Console.WriteLine("SUMMARY passed="+passed+" failed=0");return 0;
 }catch(Exception e){Console.WriteLine("FAIL "+e);return 1;}}
}
