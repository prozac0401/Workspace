using System;
using System.Linq;
using System.Xml.Linq;
using System.Runtime.InteropServices;
using ExcelSelectionExport;
using System.Reflection;
using System.Diagnostics;
using System.Threading;
using System.Windows.Forms;
public class FakeAddIn {public object Object {get;set;}}
public class NoDataAccess { public object Workbooks {get {throw new Exception("Startup touched workbook data");}} }
public class ResultWindowFake { public int Activations; public void Activate() { Activations++; } }
class M1Tests {
 static int count;
 static void Check(bool ok,string label){if(!ok)throw new Exception(label);Console.WriteLine("PASS "+label);count++;}
 [STAThread] static int Main(){try {
  Check(typeof(StandardOleMarshalObject).IsAssignableFrom(typeof(AddIn)),"Callbacks marshal to the owning Excel STA");
  var addin=new AddIn();Array custom=new object[0];var owner=new FakeAddIn();
  addin.OnConnection(new NoDataAccess(),0,owner,ref custom);
  Check(owner.Object==addin,"Connection exposes compiled callback object");
  Check(addin.GetDiagnostics().Contains("clicks=0"),"Startup does not execute command");
  var xml=XDocument.Parse(addin.GetCustomUI("Microsoft.Excel.Workbook"));
  var ns=xml.Root.Name.Namespace;
  Check(xml.Descendants(ns+"contextMenu").Count()==2,"Cell and Table context menus");
  Check(xml.Descendants(ns+"button").All(x=>(string)x.Attribute("onAction")=="Export"),"Ribbon binds compiled Export callback");
  var ids=xml.Descendants().Attributes("id").Select(x=>x.Value).ToArray();
  Check(ids.Distinct().Count()==ids.Length && ids.All(x=>x.StartsWith("WorkspaceSelectionExport")),"Only unique owned Ribbon IDs");
  Check(typeof(IDTExtensibility2).GUID.ToString()=="b65ad801-abaf-11d0-bb8b-00a0c90f2744","IDTExtensibility2 ABI identity");
  Check(typeof(IRibbonExtensibility).GUID.ToString()=="000c0396-0000-0000-c000-000000000046","IRibbonExtensibility ABI identity");
  Check(((InterfaceTypeAttribute)Attribute.GetCustomAttribute(typeof(IDTExtensibility2),typeof(InterfaceTypeAttribute))).Value==ComInterfaceType.InterfaceIsDual,"Dual COM ABI");
  Check(typeof(IDTExtensibility2).GetMethods().All(m => {var p=m.GetParameters().Last();var a=(MarshalAsAttribute)Attribute.GetCustomAttribute(p,typeof(MarshalAsAttribute));return a!=null && a.Value==UnmanagedType.SafeArray && a.SafeArraySubType==VarEnum.VT_VARIANT;}),"Office SAFEARRAY custom parameters");
  var flags=BindingFlags.Instance|BindingFlags.NonPublic;
  var schedule=typeof(AddIn).GetMethod("ScheduleResultDisplay",flags);
  var busyField=typeof(AddIn).GetField("busy",flags);
  var pendingField=typeof(AddIn).GetField("resultWindow",flags);
  var timerField=typeof(AddIn).GetField("resultTimer",flags);
  var result=new ResultWindowFake(); busyField.SetValue(addin,true);
  schedule.Invoke(addin,new object[]{result});
  Check(result.Activations==0 && addin.GetDiagnostics().Contains("display-pending") && addin.GetDiagnostics().Contains("busy=True"),"Result activation waits for callback return and keeps busy guard");
  var wait=Stopwatch.StartNew();
  while(result.Activations==0 && wait.ElapsedMilliseconds<2000) {Application.DoEvents();Thread.Sleep(5);}
  Check(result.Activations==1 && addin.GetDiagnostics().Contains("outcome=success") && addin.GetDiagnostics().Contains("busy=False"),"STA timer activates the exact completed result once");
  Check(pendingField.GetValue(addin)==null && timerField.GetValue(addin)==null,"Completed activation releases pending window and timer roots");
  var extraWait=Stopwatch.StartNew();
  while(extraWait.ElapsedMilliseconds<100) {Application.DoEvents();Thread.Sleep(5);}
  Check(result.Activations==1,"Result activation timer does not repeat");
  var canceledResult=new ResultWindowFake();busyField.SetValue(addin,true);
  schedule.Invoke(addin,new object[]{canceledResult});
  addin.OnDisconnection(1,ref custom);
  Application.DoEvents();
  Check(canceledResult.Activations==0 && pendingField.GetValue(addin)==null && timerField.GetValue(addin)==null && addin.GetDiagnostics().Contains("busy=False"),"Disconnect cancels deferred display and releases its roots");
  Check(addin.GetDiagnostics().Contains("connected=False"),"Disconnect drops application and menu references");
  var pendingAddin=new AddIn();var pendingOwner=new FakeAddIn();
  pendingAddin.OnConnection(new NoDataAccess(),0,pendingOwner,ref custom);
  var jobType=typeof(ExportEngine).GetNestedType("ExportJob",BindingFlags.NonPublic);
  var preparedType=typeof(ExportEngine).GetNestedType("PreparedMenuExport",BindingFlags.NonPublic);
  var job=jobType.GetConstructor(flags,null,new Type[]{typeof(object)},null).Invoke(new object[]{new NoDataAccess()});
  var prepared=preparedType.GetConstructor(flags,null,new Type[]{jobType},null).Invoke(new object[]{job});
  var scheduleExport=typeof(AddIn).GetMethod("SchedulePreparedExport",flags);
  var pendingExportField=typeof(AddIn).GetField("pendingExport",flags);
  var exportTimerField=typeof(AddIn).GetField("exportTimer",flags);
  busyField.SetValue(pendingAddin,true);scheduleExport.Invoke(pendingAddin,new object[]{prepared});
  Check(pendingAddin.GetDiagnostics().Contains("run-pending")&&pendingAddin.GetDiagnostics().Contains("busy=True")&&Object.ReferenceEquals(pendingExportField.GetValue(pendingAddin),prepared),"Prepared source remains pinned until deferred engine execution");
  pendingAddin.OnDisconnection(1,ref custom);
  Check(pendingExportField.GetValue(pendingAddin)==null&&exportTimerField.GetValue(pendingAddin)==null&&pendingAddin.GetDiagnostics().Contains("busy=False")&&(bool)jobType.GetField("cancel",flags).GetValue(job),"Disconnect disposes the queued job before any engine work");
  var canceledWait=Stopwatch.StartNew();while(canceledWait.ElapsedMilliseconds<100){Application.DoEvents();Thread.Sleep(5);}
  Check(pendingAddin.GetDiagnostics().Contains("canceled:disconnected"),"Canceled queued engine cannot restart from a stale timer message");
  Console.WriteLine(count+" checks passed");return 0;
 }catch(Exception e){Console.Error.WriteLine(e);return 1;}}
}
