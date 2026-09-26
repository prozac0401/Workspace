// Read-only checkpoints for real UI Undo/Redo. Edits and Ctrl+Z/Ctrl+Y must
// be performed through Excel's UI; COM writes cannot seed native history.
using System;using System.IO;using System.Runtime.InteropServices;using System.Text;
class UndoHistoryTests {

 delegate bool EnumProc(IntPtr hwnd, IntPtr param);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc p,IntPtr l);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h,uint id,ref Guid iid,[MarshalAs(UnmanagedType.IDispatch)] out object o);
 public static dynamic Attach(int pid) {
  object result=null;
  EnumProc child=delegate(IntPtr h,IntPtr unused) { var b=new StringBuilder(256); GetClassName(h,b,256); if(b.ToString()=="EXCEL7") {Guid g=new Guid("00020400-0000-0000-C000-000000000046"); object o; if(AccessibleObjectFromWindow(h,0xfffffff0,ref g,out o)==0) result=o;} return result==null;};
  EnumWindows(delegate(IntPtr h,IntPtr unused) {uint p;GetWindowThreadProcessId(h,out p);if(p==pid) EnumChildWindows(h,child,IntPtr.Zero);return result==null;},IntPtr.Zero);
  if(result==null)throw new Exception("No workbook window for owned Excel pid "+pid);
  try { return ((dynamic)result).Application; } finally { Marshal.ReleaseComObject(result); }
 }

 static int count;
 static void Check(bool ok,string label){if(!ok)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
 [STAThread] static int Main(string[] args){Console.OutputEncoding=new UTF8Encoding(false);try{return Run(args);}catch(Exception e){Console.Error.WriteLine(e);return 1;}finally{GC.Collect();GC.WaitForPendingFinalizers();GC.Collect();GC.WaitForPendingFinalizers();}}
 static int Run(string[] args){
 if(args.Length!=2)throw new ArgumentException("UndoHistoryTests.exe <ExcelProbe fixture.xlsx.pid> before|exported|undo1|undo2|undo3|redo1|redo2|redo3");
 string marker=Path.GetFullPath(args[0]);if(!marker.EndsWith(".xlsx.pid",StringComparison.OrdinalIgnoreCase))throw new Exception("Owned fixture marker required");
 string sourcePath=marker.Substring(0,marker.Length-4);if(!File.Exists(sourcePath))throw new Exception("Missing source fixture");
 int pid=int.Parse(File.ReadAllText(marker));dynamic app=Attach(pid);dynamic books=app.Workbooks,source=null,result=null;
 try{
 uint actual;GetWindowThreadProcessId(new IntPtr((int)app.Hwnd),out actual);Check(actual==pid,"Exact fixture process");
 int expectedBooks=args[1]=="before"?1:2;Check((int)books.Count==expectedBooks,"Expected original/result workbook count");
 for(int i=1;i<=books.Count;i++){dynamic b=books[i];if(String.Equals((string)b.FullName,sourcePath,StringComparison.OrdinalIgnoreCase))source=b;else{Check(String.IsNullOrEmpty((string)b.Path),"Only unsaved result alongside fixture");result=b;}}
 Check(source!=null,"Exact owned source file");
 int stage;switch(args[1]){case "before":case "exported":case "redo3":stage=0;break;case "undo1":case "redo2":stage=1;break;case "undo2":case "redo1":stage=2;break;case "undo3":stage=3;break;default:throw new Exception("Unknown checkpoint");}
 dynamic s=source.Worksheets[1];
 Check((string)s.Range["A1"].Value2==(stage<3?"History-A":"M1 synthetic"),"Original A1 history value");
 Check((double)s.Range["B1"].Value2==(stage<2?314:42),"Original B1 history value");
 Check((double)s.Range["B2"].Value2==(stage<1?315:17),"Original B2 history value");
 Check((bool)s.Range["B2"].HasFormula==(stage<1),"Original formula restored in correct history order");
 if(stage<1)Check((string)s.Range["B2"].Formula=="=B1+1","Original formula text");
 dynamic bars=app.CommandBars;bool undo=bars.GetEnabledMso("Undo"),redo=bars.GetEnabledMso("Redo");
 Check(undo==(stage<3),"Undo state for checkpoint");Check(redo==(stage>0),"Redo state for checkpoint");Marshal.ReleaseComObject((object)bars);
 if(result!=null){dynamic rs=result.Worksheets[1];Check((int)result.Sheets.Count==1,"One output sheet");Check((string)rs.Range["A1"].Value2=="History-A"&&(double)rs.Range["B1"].Value2==314&&(double)rs.Range["B2"].Value2==315,"Result stays at exported snapshot while source history moves");Check((bool)rs.Range["A1:B2"].HasFormula==false,"Output contains values only");Check((bool)result.Saved==false&&String.IsNullOrEmpty((string)result.Path),"Output is unsaved and has no temporary path");Marshal.ReleaseComObject((object)rs);}
 Marshal.ReleaseComObject((object)s);
 Console.WriteLine("PASS "+count+" assertions; checkpoint="+args[1]+"; Excel="+app.Version+"; Build="+app.Build+"; PID="+pid);return 0;
 }finally{if(result!=null)Marshal.ReleaseComObject((object)result);if(source!=null)Marshal.ReleaseComObject((object)source);Marshal.ReleaseComObject((object)books);Marshal.ReleaseComObject((object)app);}
 }
}