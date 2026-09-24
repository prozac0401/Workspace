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
   Entry(z,"xl/workbook.xml","<workbook xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'><sheets><sheet name='SyntheticFixture' sheetId='1' r:id='rId1'/></sheets></workbook>");
   Entry(z,"xl/_rels/workbook.xml.rels","<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet' Target='worksheets/sheet1.xml'/></Relationships>");
   Entry(z,"xl/worksheets/sheet1.xml","<worksheet xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'><sheetViews><sheetView workbookViewId='0'><selection activeCell='A1' sqref='A1:B2'/></sheetView></sheetViews><sheetData><row r='1'><c r='A1' t='inlineStr'><is><t>M1 synthetic</t></is></c><c r='B1'><v>42</v></c></row><row r='2'><c r='A2' t='inlineStr'><is><t>001234</t></is></c><c r='B2'><v>17</v></c></row></sheetData></worksheet>");
  }
 }
 [STAThread] static int Main(string[] a) { Console.OutputEncoding=new UTF8Encoding(false); try {return MainCore(a);} finally {GC.Collect();GC.WaitForPendingFinalizers();GC.Collect();GC.WaitForPendingFinalizers();} }
 [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)] static int MainCore(string[] a) {try {
  if(a[0]=="start") {var file=Path.GetFullPath(a[2]);Fixture(file);var p=Process.Start(new ProcessStartInfo(a[1],"/x \""+file+"\""){UseShellExecute=true}); File.WriteAllText(file+".pid",p.Id.ToString());Console.WriteLine("pid="+p.Id);return 0;}
  int pid=int.Parse(File.ReadAllText(a[1]+".pid"));dynamic app=Attach(pid);
  if(a[0]=="inspect") {dynamic add=app.COMAddIns.Item("Workspace.ExcelSelectionExport"); Console.WriteLine("pid="+pid+";Excel="+app.Version+";Build="+app.Build+";Connected="+add.Connect+";Workbooks="+app.Workbooks.Count+";Diagnostics="+add.Object.GetDiagnostics());Console.WriteLine("Selection="+app.Selection.Address);try{Console.WriteLine("LastError="+add.Object.GetLastError());}catch{} return 0;}
  if(a[0]=="close") {foreach(dynamic book in app.Workbooks) {string full=(string)book.FullName; if(!String.Equals(full,Path.GetFullPath(a[1]),StringComparison.OrdinalIgnoreCase))throw new Exception("Unexpected workbook; will not close: "+book.Name);} app.Workbooks[1].Close(false);app.Quit();Console.WriteLine("Owned Excel closed");return 0;}
  throw new Exception("Unknown command");
 }catch(Exception e){Console.Error.WriteLine(e.ToString());return 1;} }
}
