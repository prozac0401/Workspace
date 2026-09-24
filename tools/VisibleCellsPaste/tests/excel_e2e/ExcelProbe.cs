using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
class ExcelProbe {
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
 static void Entry(ZipArchive z,string name,string value) { using(var w=new StreamWriter(z.CreateEntry(name).Open(),new UTF8Encoding(false)))w.Write(value); }
 static void Fixture(string p) {
  Directory.CreateDirectory(Path.GetDirectoryName(p));
  using(var f=new FileStream(p,FileMode.CreateNew))using(var z=new ZipArchive(f,ZipArchiveMode.Create)) {
   Entry(z,"[Content_Types].xml","<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='application/xml'/><Override PartName='/xl/workbook.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml'/><Override PartName='/xl/worksheets/sheet1.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'/></Types>");
   Entry(z,"_rels/.rels","<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument' Target='xl/workbook.xml'/></Relationships>");
   Entry(z,"xl/workbook.xml","<workbook xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'><sheets><sheet name='VCPSynthetic' sheetId='1' r:id='rId1'/></sheets></workbook>");
   Entry(z,"xl/_rels/workbook.xml.rels","<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet' Target='worksheets/sheet1.xml'/></Relationships>");
   Entry(z,"xl/worksheets/sheet1.xml","<worksheet xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'><sheetViews><sheetView workbookViewId='0'><selection activeCell='A1' sqref='A1:A5'/></sheetView></sheetViews><sheetData><row r='1'><c r='A1'><v>85</v></c><c r='E1' t='inlineStr'><is><t>대상</t></is></c></row><row r='2'><c r='A2' t='inlineStr'><is><t>00123</t></is></c></row><row r='3'/><row r='4'><c r='A4' t='inlineStr'><is><t>한글&#10;줄바꿈</t></is></c></row><row r='5'/></sheetData></worksheet>");
  }
 }
 [STAThread] static int Main(string[] a) { Console.OutputEncoding=new UTF8Encoding(false); try {return MainCore(a);} finally {GC.Collect();GC.WaitForPendingFinalizers();GC.Collect();GC.WaitForPendingFinalizers();} }
 [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)] static int MainCore(string[] a) {try {
  if(a[0]=="start") {var file=Path.GetFullPath(a[2]);Fixture(file);var p=Process.Start(new ProcessStartInfo(a[1],"/x \""+file+"\""){UseShellExecute=true}); File.WriteAllText(file+".pid",p.Id.ToString());Console.WriteLine("pid="+p.Id);return 0;}
  int pid=int.Parse(File.ReadAllText(a[1]+".pid"));dynamic app=Attach(pid);
  if(a[0]=="prepare-cases") {dynamic s=app.Workbooks[1].Worksheets[1];if(!((string)app.Workbooks[1].Name).StartsWith("VCP-"))throw new Exception("Owned fixture required");s.Cells.Clear();s.Range["A1"].Value2=85;s.Range["A2"].NumberFormat="@";s.Range["A2"].Value2="00123";s.Range["A4"].Value2="한글\n줄바꿈";s.Range["H1:J1"].Value2=new object[,]{{85,90,78}};s.Range["P1"].Formula2="=1+1";s.Range["P2"].Formula2="=\"\"";s.Range["P3"].Formula2="=TRUE()";s.Range["P4"].Formula2="=NA()";s.Range["S1"].Value2=45200;s.Range["S1"].NumberFormat="yyyy-mm-dd";s.Range["A1:A5"].Select();Console.WriteLine("Prepared synthetic cases");return 0;}
  if(a[0]=="prepare-filter") {dynamic s=app.Workbooks[1].Worksheets[1];if(!((string)app.Workbooks[1].Name).StartsWith("VCP-"))throw new Exception("Owned fixture required");s.Cells.Clear();s.Range["A1:B4"].Value2=new object[,]{{"Value","Keep"},{85,"yes"},{90,"no"},{78,"yes"}};s.Range["A1:B4"].AutoFilter(2,"yes");s.Range["A2:A4"].Select();Console.WriteLine("Prepared filtered source: visible85,78; hidden90");return 0;}
  if(a[0]=="inspect") {dynamic add=app.COMAddIns.Item("Workspace.VisibleCellsPaste"); Console.WriteLine("pid="+pid+";Excel="+app.Version+";Build="+app.Build+";Connected="+add.Connect+";Workbooks="+app.Workbooks.Count+";Diagnostics="+add.Object.GetDiagnostics());Console.WriteLine("Selection="+app.Selection.Address);try{Console.WriteLine("LastError="+add.Object.GetLastError());}catch{} return 0;}
  if(a[0]=="close") {foreach(dynamic book in app.Workbooks) {string full=(string)book.FullName; if(!String.Equals(full,Path.GetFullPath(a[1]),StringComparison.OrdinalIgnoreCase))throw new Exception("Unexpected workbook; will not close: "+book.Name);} app.Workbooks[1].Close(false);app.Quit();Console.WriteLine("Owned Excel closed");return 0;}
  throw new Exception("Unknown command");
 }catch(Exception e){Console.Error.WriteLine(e.ToString());return 1;} }
}
