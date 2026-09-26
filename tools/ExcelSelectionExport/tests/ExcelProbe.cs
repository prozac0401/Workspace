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
 static void Release(object value) { if(value!=null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
 [STAThread] static int Main(string[] a) {
  Console.OutputEncoding=new UTF8Encoding(false);
  int code;
  try {code=MainCore(a);} finally {GC.Collect();GC.WaitForPendingFinalizers();GC.Collect();GC.WaitForPendingFinalizers();}
  if(code==0 && a[0]=="close") {
   int pid=int.Parse(File.ReadAllText(a[1]+".pid"));
   try {using(var process=Process.GetProcessById(pid)) {
    if(!process.WaitForExit(15000)) {Console.Error.WriteLine("FAIL: owned Excel remains after Close/Quit and COM release; pid="+pid);return 2;}
   }} catch(ArgumentException) { }
   Console.WriteLine("PASS: owned Excel process exited naturally; pid="+pid);
  }
  return code;
 }
 [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)] static int MainCore(string[] a) {try {
  if(a[0]=="start") {var file=Path.GetFullPath(a[2]);Fixture(file);var p=Process.Start(new ProcessStartInfo(a[1],"/x \""+file+"\""){UseShellExecute=true}); File.WriteAllText(file+".pid",p.Id.ToString());Console.WriteLine("pid="+p.Id);return 0;}
  int pid=int.Parse(File.ReadAllText(a[1]+".pid"));object app=Attach(pid);
  try {
   object books=((dynamic)app).Workbooks;
   try {
    if(a[0]=="inspect") {
     object adds=null,add=null,callback=null,selection=null;
     try {
      adds=((dynamic)app).COMAddIns;add=((dynamic)adds).Item("Workspace.ExcelSelectionExport");callback=((dynamic)add).Object;
      Console.WriteLine("pid="+pid+";Excel="+((dynamic)app).Version+";Build="+((dynamic)app).Build+";Connected="+((dynamic)add).Connect+";Workbooks="+((dynamic)books).Count+";Diagnostics="+((dynamic)callback).GetDiagnostics());
      selection=((dynamic)app).Selection;Console.WriteLine("Selection="+((dynamic)selection).Address);
      Console.WriteLine("LastError="+((dynamic)callback).GetLastError());return 0;
     } finally {Release(selection);Release(callback);Release(add);Release(adds);}
    }
    if(a[0]=="close") {
     if((int)((dynamic)books).Count!=1)throw new Exception("Expected exactly one owned fixture; refusing Close/Quit.");
     object book=((dynamic)books).Item(1);
     try {
      if(!String.Equals((string)((dynamic)book).FullName,Path.GetFullPath(a[1]),StringComparison.OrdinalIgnoreCase))throw new Exception("Unexpected workbook; refusing Close/Quit.");
      ((dynamic)book).Close(false);
     } finally {Release(book);}
     ((dynamic)app).Quit();Console.WriteLine("Close/Quit requested for owned fixture");return 0;
    }
    throw new Exception("Unknown command");
   } finally {Release(books);}
  } finally {Release(app);}
 }catch(Exception e){Console.Error.WriteLine(e.ToString());return 1;} }
}
