using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using VisibleCellsPaste;
// Test-only: attach to one explicitly supplied Excel PID. Preserve one exact baseline
// workbook and close only the separately created regression workbook. Never quit Excel.
class RegressionScope {
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
 static int failed;
 static void Check(bool value,string message){if(!value)throw new Exception(message);}
 static void Cleanup(string name,Action action){try{action();}catch(Exception error){failed++;Console.WriteLine("CLEANUP FAIL "+name+": "+error);}}
 static string Hash(string file){using(var input=File.Open(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant();}
 static string Describe(object value){if(value==null)return "<null>";var type=value.GetType();return "type="+type.AssemblyQualifiedName+";typeCode="+Type.GetTypeCode(type)+";isEnum="+type.IsEnum+";value=["+Convert.ToString(value,System.Globalization.CultureInfo.InvariantCulture).Replace("\r","\\r").Replace("\n","\\n")+"]";}
 static void LogGlobal(string stage,string name,object expected,object actual){Console.WriteLine("GLOBAL "+stage+" "+name+" expected{"+Describe(expected)+"} actual{"+Describe(actual)+"} equal="+Object.Equals(expected,actual));}
 static bool CompareGlobals(string stage,dynamic app,object events,object calc,object screen,object status,object alerts){object ae=app.EnableEvents,ac=app.Calculation,asc=app.ScreenUpdating,ast=app.StatusBar,aa=app.DisplayAlerts;LogGlobal(stage,"EnableEvents",events,ae);LogGlobal(stage,"Calculation",calc,ac);LogGlobal(stage,"ScreenUpdating",screen,asc);LogGlobal(stage,"StatusBar",status,ast);LogGlobal(stage,"DisplayAlerts",alerts,aa);return Object.Equals(ae,events)&&Object.Equals(ac,calc)&&Object.Equals(asc,screen)&&Object.Equals(ast,status)&&Object.Equals(aa,alerts);}
 static string Quote(string value){Check(value.IndexOf('"')<0,"Embedded quotes are not allowed in argument paths");return "\""+value+"\"";}
 static bool RunSuite(string name,int expected,string pid,string folder){
  string output=Path.Combine(folder,name+".txt");
  Check(!File.Exists(output),"Refusing to replace prior suite evidence: "+output);
  string arguments=pid+" "+Quote(output);
  if(name=="FunctionalTests")arguments+=" --synthetic-regression";
  if(name=="RemainingSafetyTests")arguments+=" "+Quote(Path.Combine(folder,"remaining-fixtures"));
  var start=new ProcessStartInfo(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,name+".exe"),arguments){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=Environment.CurrentDirectory};
  Console.WriteLine("START "+name+" UTC="+DateTime.UtcNow.ToString("o"));
  using(var process=Process.Start(start)){
   Check(process!=null,"Suite process did not start");
   var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();
   process.WaitForExit();
   File.WriteAllText(output+".console.txt",stdout.GetAwaiter().GetResult(),Encoding.UTF8);
   File.WriteAllText(output+".stderr.txt",stderr.GetAwaiter().GetResult(),Encoding.UTF8);
   Console.WriteLine("EXIT "+name+"="+process.ExitCode+" UTC="+DateTime.UtcNow.ToString("o"));
   string expectedSummary="SUMMARY passed="+expected+" failed=0"+(name=="RemainingSafetyTests"?" not_run=0":"");
   bool complete=File.Exists(output)&&File.ReadAllLines(output).Any(line=>line==expectedSummary)&&!File.ReadAllText(output).Contains("CLEANUP FAIL");
   if(process.ExitCode!=0||!complete){failed++;Console.WriteLine("HARNESS FAIL incomplete or failed suite "+name+"; expected "+expectedSummary);return false;}
  }
  return true;
 }
 [STAThread]static int Main(string[] args){
  Console.OutputEncoding=new UTF8Encoding(false);
  if(args.Length!=4)throw new ArgumentException("ownedPID outputDir newRegressionFile existingBaselineFile");
  int expectedPid=Int32.Parse(args[0]);Check(expectedPid>0,"Positive owned PID required");
  string root=Path.GetFullPath(Path.Combine(Environment.CurrentDirectory,"artifacts","visible-cells-paste"))+Path.DirectorySeparatorChar;
  string folder=Path.GetFullPath(args[1]),file=Path.GetFullPath(args[2]),baseline=Path.GetFullPath(args[3]);
  Check(new[]{folder,file,baseline}.All(p=>p.StartsWith(root,StringComparison.OrdinalIgnoreCase)),"Owned artifact paths required");
  Check(Path.GetFileName(file).StartsWith("VCP-",StringComparison.Ordinal)&&Path.GetFileName(baseline).StartsWith("VCP-",StringComparison.Ordinal),"Owned VCP fixture names required");
  Check(!File.Exists(file)&&File.Exists(baseline),"New regression fixture must not exist; exact baseline must exist");
  Check(!String.Equals(file,baseline,StringComparison.OrdinalIgnoreCase),"Regression and baseline paths must differ");
  Directory.CreateDirectory(folder);Directory.CreateDirectory(Path.GetDirectoryName(file));string baselineHash=Hash(baseline);
  var refs=new ComScope();dynamic app=null,books=null,owned=null;object originalBook=null,originalSheet=null,originalSelection=null;
  object events=null,calc=null,screen=null,status=null,alerts=null;bool captured=false;
  try{
   app=refs.Own((object)ExcelProbe.Attach(expectedPid));uint actualPid;GetWindowThreadProcessId(new IntPtr(Convert.ToInt64(app.Hwnd)),out actualPid);Check(actualPid==(uint)expectedPid,"Attached Excel PID differs from the explicit owned PID");
   books=refs.Own((object)app.Workbooks);Check((int)books.Count==1,"Exactly one explicitly named baseline workbook is required");
   originalBook=refs.Own((object)books[1]);Check(String.Equals((string)((dynamic)originalBook).FullName,baseline,StringComparison.OrdinalIgnoreCase),"Baseline workbook identity differs");
   object active=refs.Own((object)app.ActiveWorkbook);Check(ExcelEngine.Same(active,originalBook),"Baseline workbook must be active");
   dynamic protectedWindows=refs.Own((object)app.ProtectedViewWindows);Check((int)protectedWindows.Count==0,"Baseline Excel must have no Protected View windows");
   originalSheet=refs.Own((object)app.ActiveSheet);originalSelection=refs.Own((object)app.Selection);
   events=app.EnableEvents;calc=app.Calculation;screen=app.ScreenUpdating;status=app.StatusBar;alerts=app.DisplayAlerts;captured=true;CompareGlobals("captured",app,events,calc,screen,status,alerts);
   owned=refs.Own((object)books.Add());owned.SaveAs(file,51);
   Console.WriteLine("Created unique owned regression workbook; existing_workbooks=1; PID="+expectedPid);
   string[] tests={"FunctionalTests","ExtendedTests","RemainingSafetyTests"};int[] counts={20,30,10};
   for(int i=0;i<tests.Length;i++){Check(String.Equals((string)owned.FullName,file,StringComparison.OrdinalIgnoreCase),"Regression workbook identity changed");owned.Activate();if(!RunSuite(tests[i],counts[i],args[0],folder))break;}
  }catch(Exception error){failed++;Console.WriteLine("HARNESS FAIL "+error);}
  finally{
   if(owned!=null)Cleanup("owned regression workbook",delegate{Check(String.Equals((string)owned.FullName,file,StringComparison.OrdinalIgnoreCase),"Regression workbook identity changed; will not close");owned.Close(false);Console.WriteLine("Closed only owned regression workbook");});
   if(captured){
    Cleanup("global-state-before-restore",delegate{CompareGlobals("before-restore",app,events,calc,screen,status,alerts);});
    Cleanup("baseline workbook",delegate{((dynamic)originalBook).Activate();});Cleanup("baseline sheet",delegate{((dynamic)originalSheet).Activate();});Cleanup("baseline selection",delegate{((dynamic)originalSelection).Select();});
    Cleanup("EnableEvents",delegate{app.EnableEvents=events;LogGlobal("restore-immediate","EnableEvents",events,(object)app.EnableEvents);});Cleanup("Calculation",delegate{app.Calculation=calc;LogGlobal("restore-immediate","Calculation",calc,(object)app.Calculation);});Cleanup("ScreenUpdating",delegate{app.ScreenUpdating=screen;LogGlobal("restore-immediate","ScreenUpdating",screen,(object)app.ScreenUpdating);});Cleanup("StatusBar",delegate{ExcelEngine.RestoreStatusBar((object)app,status);LogGlobal("restore-immediate","StatusBar",status,(object)app.StatusBar);});Cleanup("DisplayAlerts",delegate{app.DisplayAlerts=alerts;LogGlobal("restore-immediate","DisplayAlerts",alerts,(object)app.DisplayAlerts);});
    Cleanup("baseline identity and globals",delegate{Check((int)books.Count==1,"Baseline workbook count changed");Check((string)((dynamic)originalBook).FullName==baseline,"Baseline workbook reference changed");Check(Hash(baseline)==baselineHash,"Baseline saved file changed");Check(CompareGlobals("final",app,events,calc,screen,status,alerts),"Global restoration did not verify");using(var checkRefs=new ComScope()){dynamic windows=checkRefs.Own((object)app.ProtectedViewWindows);Check((int)windows.Count==0,"A Protected View fixture remains open");object activeBook=checkRefs.Own((object)app.ActiveWorkbook),activeSheet=checkRefs.Own((object)app.ActiveSheet);dynamic selection=checkRefs.Own((object)app.Selection);Check(ExcelEngine.Same(activeBook,originalBook)&&ExcelEngine.Same(activeSheet,originalSheet)&&(string)selection.Address==(string)((dynamic)originalSelection).Address,"Original selection did not verify");}Console.WriteLine("PASS original baseline identity/count/file hash, selection and global states restored");});
   }
   Cleanup("wrapper COM references",delegate{refs.Dispose();});owned=null;originalSelection=null;originalSheet=null;originalBook=null;books=null;app=null;
  }
  Console.WriteLine("SCOPE SUMMARY failed="+failed);return failed==0?0:1;
 }
}
