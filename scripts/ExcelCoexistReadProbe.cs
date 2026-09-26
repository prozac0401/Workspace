// Reads only the exact synthetic workbook and its unsaved product result.
// Never changes add-in Connect, Excel flags, cells, workbook lifetime, or UI.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;

internal static class ExcelCoexistReadProbe
{
    static readonly List<string> checks = new List<string>();
    static void Check(bool ok, string label) { if (!ok) throw new Exception(label); checks.Add(label); }
    static void Release(object o) { if (o != null && Marshal.IsComObject(o)) Marshal.ReleaseComObject(o); }
    static object Value(object sheet, string address)
    { object range = ((dynamic)sheet).Range[address]; try { return ((dynamic)range).Value2; } finally { Release(range); } }
    static List<object> ReadMenus(object app)
    {
        var result = new List<object>(); object bars = null, cell = null, controls = null;
        try
        {
            bars = ((dynamic)app).CommandBars; cell = ((dynamic)bars).Item("Cell"); controls = ((dynamic)cell).Controls;
            for (int i = 1; i <= (int)((dynamic)controls).Count; i++)
            { object item = ((dynamic)controls).Item(i); try { result.Add(new { caption = (string)((dynamic)item).Caption, tag = (string)((dynamic)item).Tag, visible = (bool)((dynamic)item).Visible, enabled = (bool)((dynamic)item).Enabled }); } finally { Release(item); } }
            return result;
        }
        finally { Release(controls); Release(cell); Release(bars); }
    }
    static Dictionary<string, bool> ReadAddins(object app, string stage)
    {
        var found = new Dictionary<string, bool>(); object addins = null;
        string[] ids = { "Workspace.ExcelSelectionExport", "Workspace.VisibleCellsPaste", "FileListToExcel.ExcelAddIn" };
        try
        {
            addins = ((dynamic)app).COMAddIns;
            for (int i = 1; i <= (int)((dynamic)addins).Count; i++)
            { object item = ((dynamic)addins).Item(i); try { found[(string)((dynamic)item).ProgId] = (bool)((dynamic)item).Connect; } finally { Release(item); } }
        }
        finally { Release(addins); }
        for (int i = 0; i < ids.Length; i++)
        {
            bool expected = stage == "all" || (stage == "noexport" && i > 0) || (stage == "fileonly" && i == 2);
            Check(expected ? found.ContainsKey(ids[i]) && found[ids[i]] : !found.ContainsKey(ids[i]), "automatic add-in state: " + ids[i]);
        }
        bool roster = false;
        try
        {
            addins = ((dynamic)app).AddIns;
            for (int i = 1; i <= (int)((dynamic)addins).Count; i++)
            { object item = ((dynamic)addins).Item(i); try { if (string.Equals((string)((dynamic)item).Name, "ExcelSmartListCompare.xlam", StringComparison.OrdinalIgnoreCase)) roster = (bool)((dynamic)item).Installed; } finally { Release(item); } }
        }
        finally { Release(addins); }
        Check(roster, "existing roster add-in remains installed");
        return found;
    }
    [STAThread] static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        object app = null, books = null, source = null, sheets = null, sheet = null, active = null, resultSheets = null, resultSheet = null;
        try
        {
            if (args.Length != 4) throw new ArgumentException("PID fixture stage phase");
            int pid = int.Parse(args[0]); string fixture = Path.GetFullPath(args[1]), stage = args[2], phase = args[3];
            Check(stage == "all" || stage == "noexport" || stage == "fileonly" || stage == "none", "known installation stage");
            Check(phase == "before" || phase == "pasted" || phase == "undone" || phase == "export" || phase == "roster", "known feature phase");
            app = ExcelProbe.Attach(pid); books = ((dynamic)app).Workbooks;
            Check((int)((dynamic)books).Count == ((phase == "export" || phase == "roster") ? 2 : 1), "only owned source and expected result open");
            for (int i = 1; i <= (int)((dynamic)books).Count; i++)
            { object item = ((dynamic)books).Item(i); if (string.Equals((string)((dynamic)item).FullName, fixture, StringComparison.OrdinalIgnoreCase)) source = item; else Release(item); }
            Check(source != null, "exact owned source path");
            sheets = ((dynamic)source).Worksheets; Check((int)((dynamic)sheets).Count == 2, "two synthetic source sheets");
            sheet = ((dynamic)sheets).Item("OwnedCoexist");
            Check(Convert.ToDouble(Value(sheet, "H1")) == 85 && Convert.ToDouble(Value(sheet, "I1")) == 90 && Convert.ToDouble(Value(sheet, "J1")) == 78, "source numbers preserved");
            Check((string)Value(sheet, "E3") == "hidden3" && (string)Value(sheet, "E6") == "outside6", "hidden and outside cells preserved");
            object hidden = ((dynamic)sheet).Range["E3"], row = null;
            try { row = ((dynamic)hidden).EntireRow; Check((bool)((dynamic)row).Hidden, "hidden row preserved"); } finally { Release(row); Release(hidden); }
            string[] cells = { "E2", "E4", "E5" }, originals = { "before2", "before4", "before5" }; double[] pasted = { 85, 90, 78 };
            for (int i = 0; i < cells.Length; i++) { object value = Value(sheet, cells[i]); Check(phase == "pasted" ? value is double && (double)value == pasted[i] : value is string && (string)value == originals[i], "exact target value/type: " + cells[i]); }
            string[] addresses = { "L6", "L7", "L8", "M6", "M7", "M8" }, texts = { "Alpha", "Beta", "Beta", "Alpha", "Beta", "Gamma" };
            for (int i = 0; i < addresses.Length; i++) Check((string)Value(sheet, addresses[i]) == texts[i], "roster source preserved: " + addresses[i]);
            Check((bool)((dynamic)app).EnableEvents && (bool)((dynamic)app).ScreenUpdating && (bool)((dynamic)app).Interactive && (bool)((dynamic)app).DisplayAlerts, "Excel interactive flags restored");
            var addins = ReadAddins(app, stage);
            if (phase == "export" || phase == "roster")
            {
                active = ((dynamic)app).ActiveWorkbook;
                Check((string)((dynamic)active).Path == "", "result is an unsaved workbook");
                resultSheets = ((dynamic)active).Worksheets; resultSheet = ((dynamic)resultSheets).Item(1);
                string expectedName = phase == "export" ? "선택범위" : "명단비교_결과";
                Check((string)((dynamic)resultSheet).Name == expectedName, "product result sheet marker");
                if (phase == "export")
                {
                    for (int i = 0; i < 3; i++) Check((string)Value(resultSheet, "A" + (i + 1)) == originals[i], "visible export value " + (i + 1));
                    object used = ((dynamic)resultSheet).UsedRange, rows = null, columns = null;
                    try { rows = ((dynamic)used).Rows; columns = ((dynamic)used).Columns; Check((int)((dynamic)rows).Count == 3 && (int)((dynamic)columns).Count == 1 && !(bool)((dynamic)used).HasFormula, "export is a three-row value-only result"); }
                    finally { Release(columns); Release(rows); Release(used); }
                }
                else
                {
                    var counts = new Dictionary<string, string>();
                    Check((string)Value(resultSheet, "D8") == "첫 목록 개수" && (string)Value(resultSheet, "F8") == "둘째 목록 개수", "roster count column headers");
                    for (int r = 9; r <= 10; r++) counts[Convert.ToString(Value(resultSheet, "B" + r))] = Convert.ToString(Value(resultSheet, "D" + r)) + "/" + Convert.ToString(Value(resultSheet, "F" + r));
                    Check(counts.Count == 2 && counts.ContainsKey("Beta") && counts["Beta"] == "2/1" && counts.ContainsKey("Gamma") && counts["Gamma"] == "0/1", "roster exact multiplicity differences");
                    Check(Value(resultSheet, "B11") == null, "roster omits equal Alpha and extra difference rows");
                }
            }
            Console.WriteLine(new JavaScriptSerializer().Serialize(new { status = "passed", pid, stage, phase, excelVersion = (string)((dynamic)app).Version, excelBuild = Convert.ToString(((dynamic)app).Build), calculation = Convert.ToInt32(((dynamic)app).Calculation), checks, addins, menus = ReadMenus(app) }));
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { Release(resultSheet); Release(resultSheets); Release(active); Release(sheet); Release(sheets); Release(source); Release(books); Release(app); GC.Collect(); GC.WaitForPendingFinalizers(); }
    }
}
