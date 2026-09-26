// Read-only verification of actual UI operations. Never invokes a product command,
// edits cells, closes workbooks, or terminates Excel. create writes a new fixture.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;

internal static class UiSmokeProbe
{
    static int checks;
    static void Check(bool ok, string label) { if (!ok) throw new Exception(label); Console.WriteLine("PASS " + label); checks++; }
    static void Release(object value) { if (value != null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
    static void Entry(ZipArchive archive, string name, string value)
    { using (var writer = new StreamWriter(archive.CreateEntry(name).Open(), new UTF8Encoding(false))) writer.Write(value); }
    static void Create(string path)
    {
        path = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        using (var file = new FileStream(path, FileMode.CreateNew))
        using (var zip = new ZipArchive(file, ZipArchiveMode.Create))
        {
            Entry(zip,"[Content_Types].xml","<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='application/xml'/><Override PartName='/xl/workbook.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml'/><Override PartName='/xl/worksheets/sheet1.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'/></Types>");
            Entry(zip,"_rels/.rels","<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument' Target='xl/workbook.xml'/></Relationships>");
            Entry(zip,"xl/workbook.xml","<workbook xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main' xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships'><sheets><sheet name='OwnedVcpSmoke' sheetId='1' r:id='rId1'/></sheets></workbook>");
            Entry(zip,"xl/_rels/workbook.xml.rels","<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rId1' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet' Target='worksheets/sheet1.xml'/></Relationships>");
            Entry(zip,"xl/worksheets/sheet1.xml","<worksheet xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'><sheetViews><sheetView workbookViewId='0'><selection activeCell='H1' sqref='H1:J1'/></sheetView></sheetViews><sheetData><row r='1'><c r='H1'><v>85</v></c><c r='I1'><v>90</v></c><c r='J1'><v>78</v></c></row><row r='2'><c r='E2' t='inlineStr'><is><t>before2</t></is></c></row><row r='3' hidden='1'><c r='E3' t='inlineStr'><is><t>hidden3</t></is></c></row><row r='4'><c r='E4' t='inlineStr'><is><t>before4</t></is></c></row><row r='5'><c r='E5' t='inlineStr'><is><t>before5</t></is></c></row><row r='6'><c r='E6' t='inlineStr'><is><t>outside6</t></is></c></row></sheetData></worksheet>");
        }
    }
    static object Value(object sheet, string address)
    { object range = ((dynamic)sheet).Range[address]; try { return ((dynamic)range).Value2; } finally { Release(range); } }
    [STAThread] static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        try { return Run(args); }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { GC.Collect(); GC.WaitForPendingFinalizers(); }
    }
    static int Run(string[] args)
    {
        if (args[0] == "create") { Create(args[1]); Console.WriteLine("Created new synthetic fixture"); return 0; }
        if (args[0] == "start")
        {
            var running = Process.GetProcessesByName("EXCEL");
            try { if (running.Length != 0) throw new Exception("Close Excel before starting a serial fixture test."); }
            finally { foreach (var existing in running) existing.Dispose(); }
            string file = Path.GetFullPath(args[2]);
            if (!File.Exists(file)) throw new FileNotFoundException("Create the fixture first.");
            using (var process = Process.Start(new ProcessStartInfo(args[1], " /x \"" + file + "\"") { UseShellExecute = true }))
            { File.WriteAllText(file + ".pid", process.Id.ToString()); Console.WriteLine("pid=" + process.Id); }
            return 0;
        }
        object app = ExcelProbe.Attach(int.Parse(args[1]));
        object books = null, book = null, sheets = null, sheet = null;
        try
        {
            books = ((dynamic)app).Workbooks;
            Check((int)((dynamic)books).Count == 1, "exactly one workbook open");
            book = ((dynamic)books).Item(1); sheets = ((dynamic)book).Worksheets;
            Check((int)((dynamic)sheets).Count == 1, "exactly one worksheet");
            sheet = ((dynamic)sheets).Item(1);
            if (args[0] == "empty")
            {
                Check((string)((dynamic)book).Path == "" && (bool)((dynamic)book).Saved, "unmodified unsaved blank workbook");
                object used = ((dynamic)sheet).UsedRange;
                try { Check((double)((dynamic)used).CountLarge == 1 && ((dynamic)used).Value2 == null && !(bool)((dynamic)used).HasFormula, "single empty used cell and no formula"); }
                finally { Release(used); }
                Console.WriteLine("SAFE_EMPTY_WORKBOOK"); return 0;
            }
            string fixture = Path.GetFullPath(args[2]);
            Check(string.Equals((string)((dynamic)book).FullName,fixture,StringComparison.OrdinalIgnoreCase), "exact owned fixture path");
            Check((string)((dynamic)sheet).Name == "OwnedVcpSmoke", "owned fixture marker");
            Check(Convert.ToDouble(Value(sheet,"H1")) == 85 && Convert.ToDouble(Value(sheet,"I1")) == 90 && Convert.ToDouble(Value(sheet,"J1")) == 78, "source values preserved");
            Check((string)Value(sheet,"E3") == "hidden3", "hidden target value preserved");
            Check((string)Value(sheet,"E6") == "outside6", "outside selection value preserved");
            object hidden = ((dynamic)sheet).Range["E3"], row = null;
            try { row = ((dynamic)hidden).EntireRow; Check((bool)((dynamic)row).Hidden, "row remains hidden"); }
            finally { Release(row); Release(hidden); }
            bool pasted = args[0] == "pasted";
            Check(pasted || args[0] == "before" || args[0] == "undone", "known verification phase");
            string[] cells = {"E2","E4","E5"}; double[] numbers = {85,90,78}; string[] previous = {"before2","before4","before5"};
            for (int i=0; i<cells.Length; i++) { object value=Value(sheet,cells[i]); Check(pasted ? value is double && (double)value == numbers[i] : value is string && (string)value == previous[i], "exact value/type at " + cells[i]); }
            object addins = null, addin = null, callback = null;
            try
            {
                addins = ((dynamic)app).COMAddIns; addin = ((dynamic)addins).Item("Workspace.VisibleCellsPaste");
                Check((bool)((dynamic)addin).Connect, "installed add-in connected");
                callback = ((dynamic)addin).Object;
                Console.WriteLine("DIAGNOSTICS " + ((dynamic)callback).GetDiagnostics());
            }
            finally { Release(callback); Release(addin); Release(addins); }
            Console.WriteLine(checks + " checks passed; phase=" + args[0]); return 0;
        }
        finally { Release(sheet); Release(sheets); Release(book); Release(books); Release(app); }
    }
}
