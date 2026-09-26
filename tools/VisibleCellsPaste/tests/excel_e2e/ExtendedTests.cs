using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using VisibleCellsPaste;

// Test-only direct engine coverage. This is not installation, automatic loading,
// real context-menu interaction or actual Excel clipboard provenance evidence.
class ExtendedTests
{
    static dynamic app, book, sheet;
    static ComScope caseRefs;
    static readonly List<object> caseBooks = new List<object>();
    static dynamic Own(object value) { return caseRefs.Own(value); }
    static dynamic R(string address) { return Own((object)sheet.Range[address]); }
    static dynamic Rows(string address) { dynamic rows = Own((object)sheet.Rows); return Own((object)rows[address]); }
    static dynamic SortFields() { dynamic sort = Own((object)sheet.Sort); return Own((object)sort.SortFields); }
    static void Cleanup(string name, Action action) { try { action(); } catch (Exception error) { failed++; results.Add("CLEANUP FAIL " + name + ": " + error); } }
    static dynamic NewOtherBook() { dynamic books = Own((object)app.Workbooks); object other = Own((object)books.Add()); caseBooks.Add(other); return other; }
    static void CloseOtherBook(object other) { ((dynamic)other).Close(false); caseBooks.Remove(other); }
    static string output, filter;
    static int passed, failed;
    static readonly List<string> results = new List<string>();
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static ClipboardSnapshot Source(params CellValue[] values)
    { return new ClipboardSnapshot("SyntheticTyped-test-only", 0, values.Length, 1, true, values, "No real clipboard in these cases"); }
    static ClipboardSnapshot Numbers(params double[] values) { return Source(values.Select(CellValue.Number).ToArray()); }
    static object V(string address) { return R(address).Value2; }
    static bool Number(string address, double value) { return Convert.ToDouble(V(address)) == value; }
    static void Pump() { Application.DoEvents(); }
    static string Signature(string address)
    {
        var text = new StringBuilder();
        using (var refs = new ComScope())
        {
            dynamic range = refs.Own((object)sheet.Range[address]), cells = refs.Own((object)range.Cells);
            int count = Convert.ToInt32(range.CountLarge);
            for (int i = 1; i <= count; i++) using (var cellRefs = new ComScope())
            {
                dynamic cell = cellRefs.Own((object)cells[i]), row = cellRefs.Own((object)cell.EntireRow);
                CellState state = ExcelEngine.ReadCell((object)sheet, (int)cell.Row, (int)cell.Column);
                text.Append(state.Address).Append(':').Append(state.Formula).Append(':')
                    .Append(state.Formula ? state.FormulaValue : state.Value.Value).Append(':')
                    .Append(state.Formula ? state.FormulaProperty : state.Value.Kind.ToString()).Append(':')
                    .Append(state.Format).Append(':').Append(row.Hidden).Append(';');
            }
        }
        return text.ToString();
    }
    static void RefusePrepare(ExcelEngine engine, ClipboardSnapshot source, string checkedRange)
    {
        string before = Signature(checkedRange);
        bool refused = false;
        try { using (var unexpected = engine.Prepare(source)) {} } catch (ValidationException) { refused = true; }
        Check(refused, "Expected prewrite validation refusal");
        Check(before == Signature(checkedRange), "Validation refusal modified cells");
    }
    static void RefuseUndo(ExcelEngine engine, string checkedRange)
    {
        string before = Signature(checkedRange);
        bool refused = false;
        try { engine.UndoLast(); } catch (ValidationException) { refused = true; }
        Check(refused, "Expected Undo refusal");
        Check(before == Signature(checkedRange), "Refused Undo modified cells");
    }
    static void Test(string id, Action action)
    {
        if (filter != null && id.IndexOf(filter, StringComparison.Ordinal) < 0) return;
        Console.WriteLine("START " + id);
        var watch = Stopwatch.StartNew();
        dynamic ownedSheet = null;
        caseRefs = new ComScope();
        try
        {
            book.Activate();
            dynamic sheets = Own((object)book.Worksheets);
            object last = Own((object)sheets[(int)sheets.Count]);
            ownedSheet = Own((object)sheets.Add(Type.Missing, last));
            sheet = ownedSheet;
            sheet.Name = "VCP_Ext_" + Guid.NewGuid().ToString("N").Substring(0, 8);
            R("E1:E100").Value2 = 777.0;
            R("E1:E100").NumberFormat = "0.00";
            R("E2:E4").Select();
            Pump();
            action();
            passed++;
            results.Add(id + " PASS " + watch.ElapsedMilliseconds + "ms");
        }
        catch (Exception error)
        {
            failed++;
            results.Add(id + " FAIL " + error);
        }
        finally
        {
            for (int i = caseBooks.Count - 1; i >= 0; i--) { object other = caseBooks[i]; Cleanup("owned other workbook", delegate { ((dynamic)other).Close(false); }); }
            caseBooks.Clear();
            if (ownedSheet != null)
            {
                object alerts = null; bool captured = false;
                try { alerts = app.DisplayAlerts; captured = true; app.DisplayAlerts = false; ownedSheet.Delete(); }
                catch (Exception error) { results.Add("CLEANUP FAIL sheet: " + error); failed++; }
                finally { if (captured) Cleanup("DisplayAlerts", delegate { app.DisplayAlerts = alerts; }); }
            }
            Cleanup("case references", delegate { caseRefs.Dispose(); });
            caseRefs = null; sheet = null;
            File.WriteAllLines(output, results, Encoding.UTF8);
        }
        Console.WriteLine(results[results.Count - 1]);
    }
    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length < 2) throw new ArgumentException("ownedPID result-file [test-filter]");
        output = Path.GetFullPath(args[1]); filter = args.Length > 2 ? args[2] : null;
        string boundary = Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "artifacts", "visible-cells-paste")) + Path.DirectorySeparatorChar;
        Check(output.StartsWith(boundary, StringComparison.OrdinalIgnoreCase), "Owned result path required");
        Directory.CreateDirectory(Path.GetDirectoryName(output));
        Console.WriteLine("Extended start target=" + args[0] + ";filter=" + filter + ";utc=" + DateTime.UtcNow.ToString("o"));
        var refs = new ComScope(); object events = null, calculation = null, updating = null, status = null, alerts = null, originalSheet = null, originalSelection = null; bool captured = false;
        try
        {
            app = refs.Own((object)ExcelProbe.Attach(Int32.Parse(args[0])));
            book = refs.Own((object)app.ActiveWorkbook);
            Check(((string)book.Name).StartsWith("VCP-", StringComparison.Ordinal) && Path.GetFullPath((string)book.FullName).StartsWith(boundary, StringComparison.OrdinalIgnoreCase), "Owned VCP artifact fixture required");
            originalSheet = refs.Own((object)app.ActiveSheet); originalSelection = refs.Own((object)app.Selection);
            events = app.EnableEvents; calculation = app.Calculation; updating = app.ScreenUpdating; status = app.StatusBar; alerts = app.DisplayAlerts; captured = true; results.Add("STATUS captured type="+(status==null?"null":status.GetType().AssemblyQualifiedName)+" value=["+status+"]");
            results.Add("Direct Excel engine extended tests; synthetic typed snapshots; no autoload or actual clipboard claim.");
            app.EnableEvents = true;
            app.ScreenUpdating = true;
            app.Calculation = -4105;
            Test("D04-three-to-two", delegate
            {
                R("E2:E3").Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E5");
            });
            Test("D05-two-to-three", delegate
            {
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2), "E1:E5");
            });
            Test("D14-literal-prefixes-locale-text", delegate
            {
                string[] values = { "+001", "@abc", "1-2", "1,234", "12%", "=1+1" };
                R("E2:E7").Select();
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Source(values.Select(CellValue.Text).ToArray())), null, null);
                    for (int i = 0; i < values.Length; i++)
                    {
                        CellState actual = ExcelEngine.ReadCell((object)sheet, 2 + i, 5);
                        Check(!actual.Formula && actual.Value.Kind == CellValueKind.String && (string)actual.Value.Value == values[i], "Literal string changed");
                        Check((string)actual.Format == "0.00", "Original number format changed");
                    }
                }
            });
            Test("D02-horizontal-typed-plan", delegate
            {
                var src = new ClipboardSnapshot("SyntheticTyped-test-only", 0, 1, 3, true,
                    new[] { CellValue.Number(85), CellValue.Number(90), CellValue.Number(78) }, "Horizontal dimensions, not real clipboard");
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(src), null, null);
                Check(Number("E2", 85) && Number("E3", 90) && Number("E4", 78), "Horizontal order");
            });
            Test("R01-R02-autofilter-manual-mixed", delegate
            {
                R("D1").Value2 = "Keep"; R("E1").Value2 = "Value";
                R("D2:D8").Value2 = new object[,] { { 1 }, { 0 }, { 0 }, { 1 }, { 0 }, { 0 }, { 1 } };
                R("E3").Formula2 = "=E2*2";
                Own((object)R("E3:E4").Interior).Color = 65535;
                R("D1:E8").AutoFilter(1, 1);
                Rows("5:5").Hidden = true;
                R("E2:E8").Select();
                string hidden = Signature("E3:E7");
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85, 78)), null, null);
                Check(Number("E2", 85) && Number("E8", 78), "Mixed visibility mapping");
                Check(hidden == Signature("E3:E7"), "Hidden definition/value/format/state changed");
                Check((int)Own((object)R("E3:E4").Interior).Color == 65535, "Hidden fill changed");
                Check((bool)sheet.AutoFilterMode && (bool)sheet.FilterMode, "Filter state changed");
            });
            Test("R03-outline-collapse", delegate
            {
                Rows("3:4").Group(); Rows("6:7").Group();
                Own((object)sheet.Outline).ShowLevels(1, Type.Missing);
                Check((bool)Rows("3:3").Hidden && (bool)Rows("7:7").Hidden, "Outline fixture not collapsed");
                R("E2:E8").Select();
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85, 90, 78)), null, null);
                Check(Number("E2", 85) && Number("E5", 90) && Number("E8", 78) && Number("E3", 777), "Outline hidden mapping");
            });
            Test("R05-off-viewport", delegate
            {
                R("E1:E100").Select(); dynamic window = Own((object)app.ActiveWindow); window.ScrollRow = 1;
                dynamic visible = Own((object)window.VisibleRange), visibleRows = Own((object)visible.Rows);
                int lastVisible = (int)visible.Row + (int)visibleRows.Count - 1;
                Check(lastVisible < 100, "Fixture must extend beyond viewport");
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(Enumerable.Range(1, 100).Select(x => (double)x).ToArray())), null, null);
                Check(Number("E1", 1) && Number("E100", 100), "Offscreen cells not processed");
            });
            Test("R06-entire-row", delegate
            {
                Rows("2:2").Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1), "E1:E5");
            });
            Test("R10-legacy-array", delegate
            {
                R("E2:E3").FormulaArray = "=ROW(E2:E3)";
                R("E2").Select();
                Check((bool)R("E2").HasArray, "Legacy array fixture");
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1), "E1:E5");
            });
            Test("R10-mixed-single-array-cell", delegate
            {
                R("E3").FormulaArray = "=ROW(E3)";
                Check((bool)R("E3").HasArray && !(bool)R("E2").HasArray, "Mixed array fixture");
                R("E2:E4").Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E5");
            });
            Test("R10-mixed-spill-and-constant", delegate
            {
                R("G2").Formula2 = "=SEQUENCE(3)"; R("G5").Value2 = 777.0;
                R("G3:G5").Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "G1:G6");
            });
            Test("R09-mixed-merge-cell", delegate
            {
                R("E3:F3").Merge(); R("E2:E4").Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:F5");
            });
            Test("R13-mixed-validation-cell", delegate
            {
                Own((object)R("E3").Validation).Add(1, 1, 1, "1", "10"); R("E2:E4").Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E5");
            });
            Test("R08-validation-outside-single-target", delegate
            {
                Own((object)R("E3").Validation).Add(1, 1, 1, "1", "10"); R("E2").Select();
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85)), null, null);
                Check(Number("E2", 85) && Number("E3", 777), "Outside validation incorrectly rejected or modified");
            });
            Test("R13-hidden-only-validation-preserved", delegate
            {
                Own((object)R("E3").Validation).Add(1, 1, 1, "1", "10");
                Own((object)R("E3").EntireRow).Hidden = true;
                R("E2:E4").Select();
                string before = Signature("E3");
                string first = Convert.ToString(Own((object)R("E3").Validation).Formula1);
                string second = Convert.ToString(Own((object)R("E3").Validation).Formula2);
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85, 90)), null, null);
                Check(Number("E2", 85) && Number("E4", 90), "Visible targets not written in order");
                Check(before == Signature("E3"), "Hidden validation cell value/type/format/hidden state changed");
                Check((int)Own((object)R("E3").Validation).Type == 1 && (int)Own((object)R("E3").Validation).Operator == 1
                    && Convert.ToString(Own((object)R("E3").Validation).Formula1) == first
                    && Convert.ToString(Own((object)R("E3").Validation).Formula2) == second, "Hidden validation rule changed");
            });
            Test("D08-U01-all-blank-apply-undo", delegate
            {
                R("E2").Formula2 = "=10+5";
                R("E3").NumberFormat = "@"; R("E3").Value2 = "00123"; R("E3").NumberFormat = "00000";
                R("E4").Value2 = true; R("E2:E4").Select();
                string before = Signature("E1:E5");
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Source(CellValue.Empty(), CellValue.Empty(), CellValue.Empty())), null, null);
                    Check(V("E2") == null && V("E3") == null && V("E4") == null, "All blank items did not clear exactly three cells");
                    Check(!(bool)Own((object)app.CommandBars).GetEnabledMso("Undo"), "Native Undo must remain disabled after own empty write");
                    e.UndoLast(); Check(before == Signature("E1:E5"), "All blank write did not restore before types/formulas/formats");
                }
            });
            Test("U02-mixed-formula-type-format-backup", delegate
            {
                R("E2").Formula2 = "=10+5"; R("E2").NumberFormat = "00000";
                R("E3").NumberFormat = "@"; R("E3").Value2 = "00123"; R("E3").NumberFormat = "0.0";
                object standardFormat = R("F1").NumberFormat;
                R("E4").ClearContents(); R("E4").NumberFormat = standardFormat;
                R("E2:E4").Select(); string before = Signature("E1:E5");
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Source(CellValue.Text("=1+1"), CellValue.Number(85), CellValue.Empty())), null, null);
                    Check(!(bool)R("E2").HasFormula && (string)V("E2") == "=1+1", "Mixed write literal");
                    Check((string)R("E2").NumberFormat == "00000" && (string)R("E3").NumberFormat == "0.0" && Object.Equals((object)R("E4").NumberFormat, standardFormat), "Mixed formats changed");
                    var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
                    var epoch = (UndoEpoch)typeof(ExcelEngine).GetField("epoch", flags).GetValue(e);
                    results.Add("U02 gate available=" + epoch.Available + ";epoch=" + epoch.Version + ";savedEpoch=" + typeof(ExcelEngine).GetField("undoEpoch", flags).GetValue(e) + ";allowed=" + typeof(ExcelEngine).GetField("undoAllowed", flags).GetValue(e) + ";savedCommand=" + typeof(ExcelEngine).GetField("undoCommand", flags).GetValue(e) + ";nativeUndo=" + Own((object)app.CommandBars).GetEnabledMso("Undo") + ";sortFields=" + SortFields().Count + ";selection=" + Own((object)app.Selection).Address);
                    e.UndoLast(); Check(before == Signature("E1:E5"), "Mixed formula/type/format backup failed");
                }
            });
            Test("R13-table-header-total", delegate
            {
                R("E1").Value2 = "Data";
                dynamic tables = Own((object)sheet.ListObjects); dynamic table = Own((object)tables.Add(1, R("E1:E4"), Type.Missing, 1));
                try
                {
                    using (var e = new ExcelEngine(app))
                    {
                        Own((object)table.HeaderRowRange).Select(); RefusePrepare(e, Numbers(1), "E1:E6");
                        table.ShowTotals = true;
                        Own((object)table.TotalsRowRange).Select(); RefusePrepare(e, Numbers(1), "E1:E6");
                    }
                }
                finally { /* Table acquisition belongs to the case scope. */ }
            });
            Test("D16-empty-string-storage", delegate
            {
                R("E2").Select();
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Source(CellValue.Text(""))), null, null);
                var state = ExcelEngine.ReadCell((object)sheet, 2, 5);
                Check(!state.Formula && (state.Value.Kind == CellValueKind.Empty || state.Value.Equals(CellValue.Text(""))), "Empty string position or literal contract");
                results.Add("D16 actual constant storage kind=" + state.Value.Kind);
            });
            Test("R12-hidden-mixed-formula-column", delegate
            {
                R("E1").Value2 = "Data";
                dynamic tables = Own((object)sheet.ListObjects); dynamic table = Own((object)tables.Add(1, R("E1:E8"), Type.Missing, 1));
                object autoFill = Own((object)app.AutoCorrect).AutoFillFormulasInLists;
                try
                {
                    Own((object)app.AutoCorrect).AutoFillFormulasInLists = false;
                    R("E8").Formula2 = "=1+2";
                }
                finally { Own((object)app.AutoCorrect).AutoFillFormulasInLists = autoFill; }
                Check(!(bool)R("E2").HasFormula && (bool)R("E8").HasFormula, "Fixture must remain mixed");
                Rows("8:8").Hidden = true; R("E2:E4").Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E8");
                Check((bool)Rows("8:8").Hidden && (string)R("E8").Formula2 == "=1+2", "Hidden formula or visibility changed");
            });
            Test("U04-identical-values-sort", delegate
            {
                R("D2:D4").Value2 = new object[,] { { 3 }, { 1 }, { 2 } };
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 1, 1)), null, null);
                    R("D2:E4").Sort(R("D2"), 1);
                    Pump(); Check(Number("D2", 1), "Sort fixture did not reorder rows");
                    RefuseUndo(e, "D1:E5");
                }
            });
            Test("U04-preexisting-sort-configuration", delegate
            {
                R("D2:D4").Value2 = new object[,] { { 3 }, { 1 }, { 2 } };
                R("D2:E4").Sort(R("D2"), 1);
                Check((int)SortFields().Count > 0, "Fixture requires existing sort state");
                R("E2:E4").Select();
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 2, 3)), null, null);
                    RefuseUndo(e, "D1:E5");
                }
            });
            Test("U04-table-identical-values-sort", delegate
            {
                R("D1").Value2 = "Key"; R("E1").Value2 = "Pasted";
                R("D2:D4").Value2 = new object[,] { { 3 }, { 1 }, { 2 } };
                dynamic tables = Own((object)sheet.ListObjects); dynamic table = Own((object)tables.Add(1, R("D1:E4"), Type.Missing, 1));
                R("E2:E4").Select();
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 1, 1)), null, null);
                    dynamic sort = Own((object)table.Sort), fields = Own((object)sort.SortFields), columns = Own((object)table.ListColumns), firstColumn = Own((object)columns[1]);
                    object sortKey = Own((object)firstColumn.DataBodyRange); Own((object)fields.Add(sortKey, 0, 1));
                    sort.Header = 1; sort.Apply(); Pump();
                    Check(Number("D2", 1), "Table sort fixture must reorder rows");
                    RefuseUndo(e, "D1:E5");
                }
            });
            Test("U01-normal-immediate-undo", delegate
            {
                string before = Signature("E1:E5");
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(85, 90, 78)), null, null);
                    e.UndoLast();
                    Check(before == Signature("E1:E5"), "Normal immediate Undo regressed");
                }
            });
            Test("U04-row-delete", delegate
            {
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 1, 1)), null, null);
                    Rows("2:2").Delete(); Pump(); RefuseUndo(e, "E1:E5");
                }
            });
            Test("U05-sheet-rename", delegate
            {
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 2, 3)), null, null);
                    sheet.Name = "VCP_Renamed_" + Guid.NewGuid().ToString("N").Substring(0, 6);
                    Pump(); RefuseUndo(e, "E1:E5");
                }
            });
            Test("U07-other-owned-workbook", delegate
            {
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 2, 3)), null, null);
                    dynamic other = NewOtherBook();
                    dynamic otherSheets = Own((object)other.Worksheets), otherSheet = Own((object)otherSheets[1]), otherRange = Own((object)otherSheet.Range["A1"]);
                    try
                    {
                        otherRange.Value2 = "other-owned-test";
                        bool refused = false; try { e.UndoLast(); } catch (ValidationException) { refused = true; }
                        Check(refused && Number("E2", 1), "Wrong workbook Undo wrote original");
                        Check((string)otherRange.Value2 == "other-owned-test", "Wrong workbook was modified");
                    }
                    finally { try { CloseOtherBook((object)other); } finally { book.Activate(); } }
                }
            });
            Test("U13-later-automation-edit", delegate
            {
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 2, 3)), null, null);
                    R("J1").Value2 = 42.0; Pump();
                    RefuseUndo(e, "E1:E5"); Check(Number("J1", 42), "Later edit changed");
                }
            });
            Test("U14-reentrant-engine-call", delegate
            {
                using (var e = new ExcelEngine(app))
                {
                    var prepared = e.Prepare(Numbers(1, 2, 3));
                    bool tried = false, refused = false;
                    e.Apply(prepared, delegate
                    {
                        if (!tried)
                        {
                            tried = true;
                            try { e.Apply(prepared, null, null); } catch (ValidationException) { refused = true; }
                        }
                        return false;
                    }, null);
                    Check(tried && refused && Number("E2", 1) && Number("E4", 3), "Reentrant command not blocked");
                }
            });
            Test("U10-prewrite-cancel", delegate
            {
                string before = Signature("E1:E5");
                using (var e = new ExcelEngine(app))
                {
                    bool canceled = false;
                    try { e.Apply(e.Prepare(Numbers(1, 2, 3)), delegate { return true; }, null); }
                    catch (OperationCanceledException) { canceled = true; }
                    Check(canceled && e.LastOutcome == "no-change" && before == Signature("E1:E5"), "Prewrite cancel modified cells");
                }
            });
        }
        catch (Exception error) { failed++; results.Add("HARNESS FAIL " + error); }
        finally
        {
            if (captured)
            {
                Cleanup("original workbook", delegate { book.Activate(); });
                Cleanup("original sheet", delegate { ((dynamic)originalSheet).Activate(); });
                Cleanup("original selection", delegate { ((dynamic)originalSelection).Select(); });
                Cleanup("EnableEvents", delegate { app.EnableEvents = events; });
                Cleanup("Calculation", delegate { app.Calculation = calculation; });
                Cleanup("ScreenUpdating", delegate { app.ScreenUpdating = updating; });
                Cleanup("StatusBar", delegate { object beforeStatus=app.StatusBar; results.Add("STATUS cleanup-before type="+(beforeStatus==null?"null":beforeStatus.GetType().AssemblyQualifiedName)+" value=["+beforeStatus+"]"); ExcelEngine.RestoreStatusBar((object)app,status); object afterStatus=app.StatusBar; results.Add("STATUS cleanup-after type="+(afterStatus==null?"null":afterStatus.GetType().AssemblyQualifiedName)+" value=["+afterStatus+"]"); Check(Object.Equals(status,afterStatus),"Extended StatusBar cleanup type/value mismatch"); });
                Cleanup("DisplayAlerts", delegate { app.DisplayAlerts = alerts; });
            }
            Cleanup("suite references", delegate { refs.Dispose(); });
            sheet = null; book = null; app = null;
        }
        results.Add("SUMMARY passed=" + passed + " failed=" + failed);
        File.WriteAllLines(output, results, Encoding.UTF8);
        Console.WriteLine(results[results.Count - 1]);
        return failed == 0 ? 0 : 1;
    }
}
