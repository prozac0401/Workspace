using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32;

// Starts only a new owned Excel process with a newly created synthetic workbook.
// Does not enable add-ins or change security settings. The optional report path runs
// one owned cycle with the actual clipboard/installed Paste smoke before normal cleanup.
internal static class InstalledStartupProbe
{
    static void Release(object item) { if (item != null && Marshal.IsComObject(item)) Marshal.ReleaseComObject(item); }
    static void Entry(ZipArchive zip, string name, string text)
    { using (var writer = new StreamWriter(zip.CreateEntry(name).Open(), new UTF8Encoding(false))) writer.Write(text); }
    static string Fixture()
    {
        string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "VCP-installed-startup-" + Guid.NewGuid().ToString("N") + ".xlsx");
        using (var file = new FileStream(path, FileMode.CreateNew))
        using (var zip = new ZipArchive(file, ZipArchiveMode.Create))
        {
            Entry(zip, "[Content_Types].xml", "<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='application/xml'/><Override PartName='/xl/workbook.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml'/><Override PartName='/xl/worksheets/sheet1.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'/></Types>");
            Entry(zip, "_rels/.rels", "<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument' Target='xl/workbook.xml'/></Relationships>");
            Entry(zip, "xl/workbook.xml", "<workbook xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'><sheets><sheet name='VcpOwnedStartup' sheetId='1' r:id='rId1'/></sheets></workbook>");
            Entry(zip, "xl/_rels/workbook.xml.rels", "<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet' Target='worksheets/sheet1.xml'/></Relationships>");
            Entry(zip, "xl/worksheets/sheet1.xml", "<worksheet xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'><sheetData><row r='1'><c r='A1' t='inlineStr'><is><t>Owned startup fixture</t></is></c></row></sheetData></worksheet>");
        }
        return path;
    }
    static string ExcelPath()
    {
        foreach (RegistryView view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        using (var hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
        using (var key = hive.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\excel.exe"))
        { string path = key == null ? null : key.GetValue("") as string; if (path != null && File.Exists(path.Trim('"'))) return path.Trim('"'); }
        throw new Exception("Excel executable was not found.");
    }
    static void Cycle(int cycle, string clipboardReport = null)
    {
        var existing = Process.GetProcessesByName("EXCEL");
        try { if (existing.Length != 0) throw new Exception("Existing Excel must be preserved; startup probe refused."); }
        finally { foreach (var process in existing) process.Dispose(); }
        string path = Fixture();
        using (var process = Process.Start(new ProcessStartInfo(ExcelPath(), "/x \"" + path + "\"") { UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden }))
        {
            object app = null, books = null, book = null, addins = null, addin = null, callback = null;
            bool ownedWorkbook = false;
            try
            {
                for (int i = 0; i < 100 && app == null; i++)
                { try { app = ExcelProbe.Attach(process.Id); } catch { if (process.HasExited) throw; Thread.Sleep(200); } }
                if (app == null) throw new Exception("Could not attach to owned Excel process " + process.Id);
                books = ((dynamic)app).Workbooks;
                if ((int)((dynamic)books).Count != 1) throw new Exception("Unexpected workbook count; will not close Excel.");
                book = ((dynamic)books).Item(1);
                if (!String.Equals((string)((dynamic)book).FullName, path, StringComparison.OrdinalIgnoreCase)) throw new Exception("Unexpected workbook; will not close Excel.");
                ownedWorkbook = true;
                addins = ((dynamic)app).COMAddIns;
                addin = ((dynamic)addins).Item("Workspace.VisibleCellsPaste");
                if (!(bool)((dynamic)addin).Connect) throw new Exception("Installed add-in did not connect automatically.");
                callback = ((dynamic)addin).Object;
                string diagnostics = ((dynamic)callback).GetDiagnostics();
                if (!diagnostics.Contains("connected=True") || !diagnostics.Contains("clicks=0") || !diagnostics.Contains("bitness=64")) throw new Exception("Unexpected add-in diagnostics: " + diagnostics);
                Console.WriteLine("PASS installed startup cycle=" + cycle + "; Excel=" + ((dynamic)app).Version + "; Build=" + ((dynamic)app).Build + "; " + diagnostics);
                if (clipboardReport != null && InstalledRectangleClipboardProbe.RunOwned(process.Id, path, clipboardReport) != 0)
                    throw new Exception("Installed rectangle clipboard probe failed. See " + clipboardReport);
            }
            finally
            {
                try
                {
                    if (ownedWorkbook)
                    {
                        if ((int)((dynamic)books).Count != 1 || !String.Equals((string)((dynamic)book).FullName, path, StringComparison.OrdinalIgnoreCase))
                            throw new Exception("Workbook ownership changed; Excel was preserved.");
                        Console.WriteLine("BEGIN owned workbook normal close cycle=" + cycle);
                        ((dynamic)book).Close(false);
                        if ((int)((dynamic)books).Count != 0) throw new Exception("Another workbook appeared; Excel was preserved.");
                        Console.WriteLine("BEGIN owned Excel normal quit cycle=" + cycle);
                        ((dynamic)app).Quit();
                    }
                }
                finally
                {
                    try { Release(callback); }
                    finally { try { Release(addin); }
                    finally { try { Release(addins); }
                    finally { try { Release(book); }
                    finally { try { Release(books); }
                    finally { Release(app); } } } } }
                    GC.Collect(); GC.WaitForPendingFinalizers();
                }
            }
            if (!process.WaitForExit(15000)) throw new Exception("Owned Excel did not exit normally; no forced termination.");
            Console.WriteLine("PASS owned Excel normal exit cycle=" + cycle);
        }
    }
    [STAThread] static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        try
        {
            if (args.Length == 0) { Cycle(1); Cycle(2); }
            else if (args.Length == 1) Cycle(1, Path.GetFullPath(args[0]));
            else throw new ArgumentException("Usage: InstalledStartupProbe.exe [CLIPBOARD_REPORT.txt]");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
