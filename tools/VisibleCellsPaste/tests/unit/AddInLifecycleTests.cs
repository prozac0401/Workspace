using System;
using System.Reflection;
using System.Runtime.InteropServices;
using VisibleCellsPaste;
public sealed class FakeAddInInstance { public object Object {get;set;} }
public sealed class FailingAddInInstance { public object Object {set {throw new InvalidOperationException("synthetic connection failure");}} }
public sealed class FakeStatusBarApplication {
 public string Failure; public int Gets,Sets;
 public object Current="owned";
 public object StatusBar {
  get {Gets++;if(Failure=="invalid-get")throw new InvalidComObjectException("synthetic status getter shutdown");if(Failure=="verification-get")throw new InvalidOperationException("synthetic status restoration verification failure");if(Failure=="other-get")throw new ApplicationException("synthetic unexpected display failure");return Current;}
  set {Sets++;if(Failure=="invalid-set")throw new InvalidComObjectException("synthetic status setter shutdown");Current=value;}
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
  bool rejected=false;try{addin.OnBeginShutdown(ref custom);}catch(ApplicationException){rejected=true;}
  Check(rejected==expectFailure&&workDisposed&&statusDisposed&&(bool)Field(epoch,"disposed")
   &&Field(addin,"timer")==null&&Field(addin,"statusTimer")==null&&Field(addin,"pending")==null
   &&Field(addin,"engine")==null&&Field(addin,"application")==null&&!(bool)Field(addin,"busy")
   &&addin.GetDiagnostics().Contains("connected=False")&&(failure!=null||Object.Equals(app.Current,"original")),name);
 }
 static object AdditionalComAcquisition(object value){IntPtr pointer=Marshal.GetIUnknownForObject(value);try{return Marshal.GetObjectForIUnknown(pointer);}finally{Marshal.Release(pointer);}}
 static void NativeApplicationOwnership(){
  // Installed Microsoft Extensibility PIA marks custom [In] SAFEARRAY(VARIANT)*, not [Out].
  string[] callbacks={"OnConnection","OnDisconnection","OnAddInsUpdate","OnStartupComplete","OnBeginShutdown"};
  for(int i=0;i<callbacks.Length;i++){
   var method=typeof(IDTExtensibility2).GetMethod(callbacks[i]);var parameters=method.GetParameters();var customParameter=parameters[parameters.Length-1];
   var implementation=typeof(AddIn).GetMethod(callbacks[i]);var implementationParameters=implementation.GetParameters();var customImplementation=implementationParameters[implementationParameters.Length-1];
   var marshal=(MarshalAsAttribute)Attribute.GetCustomAttribute(customParameter,typeof(MarshalAsAttribute));
   var disp=(DispIdAttribute)Attribute.GetCustomAttribute(method,typeof(DispIdAttribute));
   Check(customParameter.ParameterType==typeof(Array).MakeByRefType()&&customParameter.IsIn&&!customParameter.IsOut
    &&customImplementation.IsIn&&!customImplementation.IsOut&&marshal!=null&&marshal.Value==UnmanagedType.SafeArray&&marshal.SafeArraySubType==VarEnum.VT_VARIANT&&disp.Value==i+1,
    "Extensibility "+callbacks[i]+" matches input-only SAFEARRAY contract");
  }
  Array custom=new object[0];
  var normal=new AddIn();object nativeApp=NewComReference();normal.OnConnection(nativeApp,1,new FakeAddInInstance(),ref custom);
  Check(!IsReleased(nativeApp)&&Object.ReferenceEquals(Field(normal,"application"),nativeApp),"native connection retains its own Application acquisition");
  object nativeEpoch=Field(Field(normal,"engine"),"epoch");object pendingBook=NewComReference();SetField(normal,"pending",OwnedSnapshot(pendingBook,null,null));normal.OnBeginShutdown(ref custom);
  Check(IsReleased(nativeApp)&&IsReleased(pendingBook)&&(bool)Field(nativeEpoch,"disposed")&&Field(normal,"application")==null,"shutdown cleans pending work and observer before releasing owned Application");
  var repeated=new AddIn();object repeatedApp=NewComReference(),externalApp=AdditionalComAcquisition(repeatedApp);repeated.OnConnection(repeatedApp,1,new FakeAddInInstance(),ref custom);repeated.OnDisconnection(1,ref custom);repeated.OnDisconnection(1,ref custom);repeated.OnBeginShutdown(ref custom);
  bool externalSurvives=!IsReleased(externalApp);Marshal.ReleaseComObject(externalApp);Check(externalSurvives&&IsReleased(externalApp),"repeated disconnect releases one Application acquisition and preserves another owner");
  var same=new AddIn();object first=NewComReference(),second=AdditionalComAcquisition(first);same.OnConnection(first,1,new FakeAddInInstance(),ref custom);object firstEpoch=Field(Field(same,"engine"),"epoch");same.OnConnection(second,1,new FakeAddInInstance(),ref custom);
  bool transferred=Object.ReferenceEquals(first,second)&&!IsReleased(second)&&(bool)Field(firstEpoch,"disposed");same.OnDisconnection(1,ref custom);Check(transferred&&IsReleased(second),"same RCW reconnect accounts for both independent incoming acquisitions");
  var replacement=new AddIn();object oldApp=NewComReference(),newApp=NewComReference();replacement.OnConnection(oldApp,1,new FakeAddInInstance(),ref custom);replacement.OnConnection(newApp,1,new FakeAddInInstance(),ref custom);
  bool replaced=IsReleased(oldApp)&&!IsReleased(newApp);replacement.OnBeginShutdown(ref custom);Check(replaced&&IsReleased(newApp),"different Application reconnect releases old ownership and later the new ownership");
  var failed=new AddIn();object failedApp=NewComReference(),otherOwner=AdditionalComAcquisition(failedApp);bool rejected=false;try{failed.OnConnection(failedApp,1,new FailingAddInInstance(),ref custom);}catch(InvalidOperationException){rejected=true;}
  bool retained=!IsReleased(otherOwner);Marshal.ReleaseComObject(otherOwner);Check(rejected&&retained&&IsReleased(otherOwner)&&Field(failed,"application")==null&&Field(failed,"engine")==null,"partial connection failure consumes only the transferred Application acquisition");
  var prior=new AddIn();object priorApp=NewComReference();prior.OnConnection(priorApp,1,new FakeAddInInstance(),ref custom);SetField(prior,"statusTimer",new System.Windows.Forms.Timer());SetField(prior,"ownStatus","owned");SetField(prior,"oldStatus",false);
  object incoming=NewComReference(),incomingInstance=NewComReference();bool priorFailed=false;try{prior.OnConnection(incoming,1,incomingInstance,ref custom);}catch(Exception){priorFailed=true;}
  Check(priorFailed&&IsReleased(priorApp)&&IsReleased(incoming)&&IsReleased(incomingInstance)&&Field(prior,"application")==null&&Field(prior,"engine")==null,"prior COM status failure releases old ownership and both unaccepted incoming acquisitions");
 }
 static object InvokePrivate(object value,string method,params object[] args){try{return value.GetType().GetMethod(method,F).Invoke(value,args);}catch(TargetInvocationException e){throw e.InnerException;}}
 static void Active(AddIn addin,Action action){InvokePrivate(addin,"RunActive",action);}
 static void DeferredDisconnectOwnership(){
  Array custom=new object[0];
  var active=new AddIn();object app=NewComReference(),book=NewComReference();active.OnConnection(app,1,new FakeAddInInstance(),ref custom);object engine=Field(active,"engine"),epoch=Field(engine,"epoch");SetField(active,"pending",OwnedSnapshot(book,null,null));bool timerDisposed=false;var workTimer=new System.Windows.Forms.Timer();workTimer.Disposed+=delegate{timerDisposed=true;};SetField(active,"timer",workTimer);bool disconnectDelivered=false;
  using(var messageTimer=new System.Windows.Forms.Timer()){
   messageTimer.Interval=1;messageTimer.Tick+=delegate{messageTimer.Stop();active.OnDisconnection(1,ref custom);disconnectDelivered=true;};messageTimer.Start();
   Active(active,delegate{
    var deadline=DateTime.UtcNow.AddSeconds(3);while(!disconnectDelivered&&DateTime.UtcNow<deadline){System.Windows.Forms.Application.DoEvents();System.Threading.Thread.Sleep(1);}
    Check(disconnectDelivered&&!IsReleased(app)&&!IsReleased(book)&&Object.ReferenceEquals(Field(active,"engine"),engine)&&!(bool)Field(epoch,"disposed")&&!timerDisposed,
     "DoEvents disconnection defers engine, snapshot and Application release until active work unwinds");
    Check((bool)InvokePrivate(active,"CancelPending",new object[]{null}),"disconnection observed during DoEvents requests cancellation before further writes");
   });
  }
  Check(IsReleased(app)&&IsReleased(book)&&(bool)Field(epoch,"disposed")&&timerDisposed&&Field(active,"engine")==null&&(int)Field(active,"activeDepth")==0,
   "outer operation unwind completes deferred cleanup exactly once");
  var nested=new AddIn();object nestedApp=NewComReference();nested.OnConnection(nestedApp,1,new FakeAddInInstance(),ref custom);
  Active(nested,delegate{Active(nested,delegate{nested.OnBeginShutdown(ref custom);});Check(!IsReleased(nestedApp)&&Field(nested,"engine")!=null,"nested operation unwind retains borrowed Application until the outer boundary");});
  Check(IsReleased(nestedApp),"last nested boundary releases the Application acquisition");
  var failed=new AddIn();object failedApp=NewComReference();failed.OnConnection(failedApp,1,new FakeAddInInstance(),ref custom);bool operationFailed=false;
  try{Active(failed,delegate{failed.OnDisconnection(1,ref custom);throw new InvalidOperationException("synthetic active operation failure");});}catch(InvalidOperationException){operationFailed=true;}
  Check(operationFailed&&IsReleased(failedApp)&&Field(failed,"engine")==null&&(int)Field(failed,"activeDepth")==0,"active exception still completes deferred shutdown on unwind");
  var same=new AddIn();object sameApp=NewComReference();same.OnConnection(sameApp,1,new FakeAddInInstance(),ref custom);object originalEngine=Field(same,"engine"),extra=AdditionalComAcquisition(sameApp),newInstance=NewComReference();bool reconnectRejected=false;
  Active(same,delegate{try{same.OnConnection(extra,1,newInstance,ref custom);}catch(InvalidOperationException){reconnectRejected=true;}Check(reconnectRejected&&!IsReleased(sameApp)&&IsReleased(newInstance)&&Object.ReferenceEquals(originalEngine,Field(same,"engine"))&&same.GetDiagnostics().Contains("connected=True"),"active same-RCW reconnect rejects only the new acquisitions and preserves the running engine");});
  same.OnDisconnection(1,ref custom);Check(IsReleased(sameApp),"active reconnect refusal leaves exactly the original Application acquisition to release");
  var closed=new AddIn();object closedApp=NewComReference(),unaccepted=NewComReference(),unacceptedInstance=NewComReference();closed.OnConnection(closedApp,1,new FakeAddInInstance(),ref custom);bool closedRejected=false;
  Active(closed,delegate{closed.OnDisconnection(1,ref custom);try{closed.OnConnection(unaccepted,1,unacceptedInstance,ref custom);}catch(InvalidOperationException){closedRejected=true;}Check(closedRejected&&IsReleased(unaccepted)&&IsReleased(unacceptedInstance)&&!IsReleased(closedApp),"reconnect after deferred disconnect returns new ownership without freeing active ownership");});
  Check(IsReleased(closedApp),"deferred-disconnect reconnect refusal still releases original ownership at unwind");
  var modal=new AddIn();var fakeApp=new FakeStatusBarApplication();modal.OnConnection(fakeApp,1,new FakeAddInInstance(),ref custom);object modalBook=NewComReference();SetField(modal,"pending",OwnedSnapshot(modalBook,null,null));
  Active(modal,delegate{modal.OnDisconnection(1,ref custom);InvokePrivate(modal,"QueuePending");InvokePrivate(modal,"ShowStatus","must not display");Check(Field(modal,"timer")==null&&Field(modal,"statusTimer")==null&&fakeApp.Gets==0&&fakeApp.Sets==0&&!IsReleased(modalBook),"disconnect during modal work prevents new work/status timers while retaining pending cleanup ownership");});
  Check(IsReleased(modalBook),"modal unwind releases the pending snapshot after canceled scheduling");
  var cleanup=new AddIn();object cleanupApp=NewComReference(),cleanupIncoming=NewComReference(),cleanupInstance=NewComReference();cleanup.OnConnection(cleanupApp,1,new FakeAddInInstance(),ref custom);int disposeEvents=0;bool cleanupRejected=false;var cleanupTimer=new System.Windows.Forms.Timer();
  cleanupTimer.Disposed+=delegate{disposeEvents++;cleanup.OnBeginShutdown(ref custom);try{cleanup.OnConnection(cleanupIncoming,1,cleanupInstance,ref custom);}catch(InvalidOperationException){cleanupRejected=true;}};SetField(cleanup,"timer",cleanupTimer);cleanup.OnDisconnection(1,ref custom);
  Check(disposeEvents==1&&cleanupRejected&&IsReleased(cleanupIncoming)&&IsReleased(cleanupInstance)&&IsReleased(cleanupApp)&&Field(cleanup,"engine")==null,"cleanup reentry neither repeats disposal nor accepts new Application ownership");
  var queued=new AddIn();object queuedApp=NewComReference(),queuedBook=NewComReference();queued.OnConnection(queuedApp,1,new FakeAddInInstance(),ref custom);SetField(queued,"pending",OwnedSnapshot(queuedBook,null,null));InvokePrivate(queued,"QueuePending");queued.OnDisconnection(1,ref custom);
  Check(IsReleased(queuedApp)&&IsReleased(queuedBook)&&Field(queued,"timer")==null,"queued but inactive work is cleaned immediately on disconnect");
  var late=new AddIn();object lateApp=NewComReference(),lateExternal=AdditionalComAcquisition(lateApp);late.OnConnection(lateApp,1,new FakeAddInInstance(),ref custom);SetField(late,"pending",OwnedSnapshot(NewComReference(),null,null));InvokePrivate(late,"QueuePending");late.OnDisconnection(1,ref custom);string lateOutcome=(string)Field(late,"outcome");InvokePrivate(late,"RunPending",null,EventArgs.Empty);
  bool lateUnchanged=!IsReleased(lateExternal)&&Field(late,"timer")==null&&Field(late,"pending")==null&&Object.Equals(Field(late,"outcome"),lateOutcome)&&!late.GetDiagnostics().Contains("outcome=success");Marshal.ReleaseComObject(lateExternal);
  Check(lateUnchanged&&IsReleased(lateExternal),"late timer tick after disconnect is harmless and does not report an unexecuted paste as success");
  var latePending=new AddIn();object lateBook=NewComReference();SetField(latePending,"pending",OwnedSnapshot(lateBook,null,null));SetField(latePending,"outcome","pending");InvokePrivate(latePending,"RunPending",null,EventArgs.Empty);
  Check(IsReleased(lateBook)&&Field(latePending,"pending")==null&&Object.Equals(Field(latePending,"outcome"),"pending"),"disconnected deferred work without a timer is consumed without executing or reporting success");
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
 ShutdownWithStatus("verification-get",false,"status verification failure remains best effort during shutdown cleanup");
 ShutdownWithStatus("other-get",true,"unexpected status failure propagates after guaranteed shutdown cleanup");
 object pasteControl=NewComReference();addin.Paste(pasteControl);Check(IsReleased(pasteControl),"disconnected paste releases its marshaled callback reference");
 object undoControl=NewComReference();addin.Undo(undoControl);Check(IsReleased(undoControl),"disconnected undo releases its marshaled callback reference");
 object busyControl=NewComReference();SetField(addin,"connected",true);SetField(addin,"busy",true);addin.Paste(busyControl);Check(IsReleased(busyControl)&&(bool)Field(addin,"busy"),"busy refusal releases callback without changing active operation");SetField(addin,"connected",false);SetField(addin,"busy",false);
 object firstControl=NewComReference();IntPtr sharedPointer=Marshal.GetIUnknownForObject(firstControl);object secondControl;try{secondControl=Marshal.GetObjectForIUnknown(sharedPointer);}finally{Marshal.Release(sharedPointer);}
 addin.Paste(firstControl);Check(!IsReleased(secondControl),"one callback does not final-release another acquired reference");addin.Undo(secondControl);Check(IsReleased(secondControl),"each independently marshaled callback reference is released once");
 object invalidInstance=NewComReference();bool invalidInstanceRejected=false;try{addin.OnConnection(new object(),1,invalidInstance,ref custom);}catch{invalidInstanceRejected=true;}Check(invalidInstanceRejected&&IsReleased(invalidInstance)&&Field(addin,"engine")==null,"failed connection releases its own COM add-in instance argument");
 var pendingBook=NewComReference();var pendingSheet=NewComReference();var pendingSelection=NewComReference();var pendingAddin=new AddIn();pendingAddin.OnConnection(new object(),1,new FakeAddInInstance(),ref custom);SetField(pendingAddin,"pending",OwnedSnapshot(pendingBook,pendingSheet,pendingSelection));pendingAddin.OnBeginShutdown(ref custom);Check(IsReleased(pendingBook)&&IsReleased(pendingSheet)&&IsReleased(pendingSelection),"shutdown releases every owned pending snapshot reference");
 var abandonedBook=NewComReference();var abandonedAddin=new AddIn();SetField(abandonedAddin,"pending",OwnedSnapshot(abandonedBook,null,null));SetField(abandonedAddin,"timer",new System.Windows.Forms.Timer());SetField(abandonedAddin,"busy",true);typeof(AddIn).GetMethod("RunPending",F).Invoke(abandonedAddin,new object[]{null,EventArgs.Empty});Check(IsReleased(abandonedBook)&&!(bool)Field(abandonedAddin,"busy"),"disconnected deferred command disposes untransferred work");
 var reconnectAddin=new AddIn();reconnectAddin.OnConnection(new FakeStatusBarApplication{Failure="other-get"},1,new FakeAddInInstance(),ref custom);SetField(reconnectAddin,"statusTimer",new System.Windows.Forms.Timer());SetField(reconnectAddin,"ownStatus","owned");SetField(reconnectAddin,"oldStatus","original");object reconnectInstance=NewComReference(),reconnectApplication=NewComReference();bool reconnectRejected=false;try{reconnectAddin.OnConnection(reconnectApplication,1,reconnectInstance,ref custom);}catch(ApplicationException){reconnectRejected=true;}Check(reconnectRejected&&IsReleased(reconnectApplication)&&IsReleased(reconnectInstance)&&Field(reconnectAddin,"engine")==null&&Field(reconnectAddin,"application")==null,"prior disconnect failure releases both unaccepted native connection arguments");
 NativeApplicationOwnership();
 DeferredDisconnectOwnership();
 Console.WriteLine("SUMMARY passed="+passed+" failed=0");return 0;
 }catch(Exception e){Console.WriteLine("FAIL "+e);return 1;}}
}
