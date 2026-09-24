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
    static string output, filter;
    static int passed, failed;
    static readonly List<string> results = new List<string>();
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static ClipboardSnapshot Source(params CellValue[] values)
    { return new ClipboardSnapshot("SyntheticTyped-test-only", 0, values.Length, 1, true, values, "No real clipboard in these cases"); }
    static ClipboardSnapshot Numbers(params double[] values) { return Source(values.Select(CellValue.Number).ToArray()); }
    static object V(string address) { return sheet.Range[address].Value2; }
    static bool Number(string address, double value) { return Convert.ToDouble(V(address)) == value; }
    static void Pump() { Application.DoEvents(); }
    static string Signature(string address)
    {
        dynamic range = sheet.Range[address];
        var text = new StringBuilder();
        foreach (dynamic cell in range.Cells)
        {
            CellState state = ExcelEngine.ReadCell((object)sheet, (int)cell.Row, (int)cell.Column);
            text.Append(state.Address).Append(':').Append(state.Formula).Append(':')
                .Append(state.Formula ? state.FormulaValue : state.Value.Value).Append(':')
                .Append(state.Formula ? state.FormulaProperty : state.Value.Kind.ToString()).Append(':')
                .Append(state.Format).Append(':').Append(cell.EntireRow.Hidden).Append(';');
            ExcelEngine.Release(cell);
        }
        ExcelEngine.Release(range);
        return text.ToString();
    }
    static void RefusePrepare(ExcelEngine engine, ClipboardSnapshot source, string checkedRange)
    {
        string before = Signature(checkedRange);
        bool refused = false;
        try { engine.Prepare(source); } catch (ValidationException) { refused = true; }
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
        try
        {
            book.Activate();
            ownedSheet = book.Worksheets.Add(Type.Missing, book.Worksheets[book.Worksheets.Count]);
            sheet = ownedSheet;
            sheet.Name = "VCP_Ext_" + Guid.NewGuid().ToString("N").Substring(0, 8);
            sheet.Range["E1:E100"].Value2 = 777.0;
            sheet.Range["E1:E100"].NumberFormat = "0.00";
            sheet.Range["E2:E4"].Select();
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
            if (ownedSheet != null)
            {
                object alerts = app.DisplayAlerts;
                try { app.DisplayAlerts = false; ownedSheet.Delete(); }
                catch (Exception error) { results.Add("CLEANUP FAIL " + error.HResult.ToString("X8")); failed++; }
                finally { app.DisplayAlerts = alerts; ExcelEngine.Release(ownedSheet); }
            }
            sheet = null;
            File.WriteAllLines(output, results, Encoding.UTF8);
        }
        Console.WriteLine(results[results.Count - 1]);
    }
    [STAThread]
    static int Main(string[] args)
    {
        output = args[1]; filter = args.Length > 2 ? args[2] : null;
        Console.WriteLine("Extended start target=" + args[0] + ";filter=" + filter + ";utc=" + DateTime.UtcNow.ToString("o"));
        app = ExcelProbe.Attach(Int32.Parse(args[0]));
        book = app.ActiveWorkbook;
        if (!((string)book.Name).StartsWith("VCP-", StringComparison.Ordinal)) throw new Exception("Owned VCP fixture required");
        results.Add("Direct Excel engine extended tests; synthetic typed snapshots; no autoload or actual clipboard claim.");
        object events = app.EnableEvents, calculation = app.Calculation, updating = app.ScreenUpdating, status = app.StatusBar;
        try
        {
            app.EnableEvents = true;
            app.ScreenUpdating = true;
            app.Calculation = -4105;
            Test("D04-three-to-two", delegate
            {
                sheet.Range["E2:E3"].Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E5");
            });
            Test("D05-two-to-three", delegate
            {
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2), "E1:E5");
            });
            Test("D14-literal-prefixes-locale-text", delegate
            {
                string[] values = { "+001", "@abc", "1-2", "1,234", "12%", "=1+1" };
                sheet.Range["E2:E7"].Select();
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
                sheet.Range["D1"].Value2 = "Keep"; sheet.Range["E1"].Value2 = "Value";
                sheet.Range["D2:D8"].Value2 = new object[,] { { 1 }, { 0 }, { 0 }, { 1 }, { 0 }, { 0 }, { 1 } };
                sheet.Range["E3"].Formula2 = "=E2*2";
                sheet.Range["E3:E4"].Interior.Color = 65535;
                sheet.Range["D1:E8"].AutoFilter(1, 1);
                sheet.Rows["5:5"].Hidden = true;
                sheet.Range["E2:E8"].Select();
                string hidden = Signature("E3:E7");
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85, 78)), null, null);
                Check(Number("E2", 85) && Number("E8", 78), "Mixed visibility mapping");
                Check(hidden == Signature("E3:E7"), "Hidden definition/value/format/state changed");
                Check((int)sheet.Range["E3:E4"].Interior.Color == 65535, "Hidden fill changed");
                Check((bool)sheet.AutoFilterMode && (bool)sheet.FilterMode, "Filter state changed");
            });
            Test("R03-outline-collapse", delegate
            {
                sheet.Rows["3:4"].Group(); sheet.Rows["6:7"].Group();
                sheet.Outline.ShowLevels(1, Type.Missing);
                Check((bool)sheet.Rows["3:3"].Hidden && (bool)sheet.Rows["7:7"].Hidden, "Outline fixture not collapsed");
                sheet.Range["E2:E8"].Select();
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85, 90, 78)), null, null);
                Check(Number("E2", 85) && Number("E5", 90) && Number("E8", 78) && Number("E3", 777), "Outline hidden mapping");
            });
            Test("R05-off-viewport", delegate
            {
                sheet.Range["E1:E100"].Select(); app.ActiveWindow.ScrollRow = 1;
                int lastVisible = (int)app.ActiveWindow.VisibleRange.Row + (int)app.ActiveWindow.VisibleRange.Rows.Count - 1;
                Check(lastVisible < 100, "Fixture must extend beyond viewport");
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(Enumerable.Range(1, 100).Select(x => (double)x).ToArray())), null, null);
                Check(Number("E1", 1) && Number("E100", 100), "Offscreen cells not processed");
            });
            Test("R06-entire-row", delegate
            {
                sheet.Rows["2:2"].Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1), "E1:E5");
            });
            Test("R10-legacy-array", delegate
            {
                sheet.Range["E2:E3"].FormulaArray = "=ROW(E2:E3)";
                sheet.Range["E2"].Select();
                Check((bool)sheet.Range["E2"].HasArray, "Legacy array fixture");
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1), "E1:E5");
            });
            Test("R10-mixed-single-array-cell", delegate
            {
                sheet.Range["E3"].FormulaArray = "=ROW(E3)";
                Check((bool)sheet.Range["E3"].HasArray && !(bool)sheet.Range["E2"].HasArray, "Mixed array fixture");
                sheet.Range["E2:E4"].Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E5");
            });
            Test("R10-mixed-spill-and-constant", delegate
            {
                sheet.Range["G2"].Formula2 = "=SEQUENCE(3)"; sheet.Range["G5"].Value2 = 777.0;
                sheet.Range["G3:G5"].Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "G1:G6");
            });
            Test("R09-mixed-merge-cell", delegate
            {
                sheet.Range["E3:F3"].Merge(); sheet.Range["E2:E4"].Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:F5");
            });
            Test("R13-mixed-validation-cell", delegate
            {
                sheet.Range["E3"].Validation.Add(1, 1, 1, "1", "10"); sheet.Range["E2:E4"].Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E5");
            });
            Test("R08-validation-outside-single-target", delegate
            {
                sheet.Range["E3"].Validation.Add(1, 1, 1, "1", "10"); sheet.Range["E2"].Select();
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85)), null, null);
                Check(Number("E2", 85) && Number("E3", 777), "Outside validation incorrectly rejected or modified");
            });
            Test("R13-hidden-only-validation-preserved", delegate
            {
                sheet.Range["E3"].Validation.Add(1, 1, 1, "1", "10");
                sheet.Range["E3"].EntireRow.Hidden = true;
                sheet.Range["E2:E4"].Select();
                string before = Signature("E3");
                string first = Convert.ToString(sheet.Range["E3"].Validation.Formula1);
                string second = Convert.ToString(sheet.Range["E3"].Validation.Formula2);
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Numbers(85, 90)), null, null);
                Check(Number("E2", 85) && Number("E4", 90), "Visible targets not written in order");
                Check(before == Signature("E3"), "Hidden validation cell value/type/format/hidden state changed");
                Check((int)sheet.Range["E3"].Validation.Type == 1 && (int)sheet.Range["E3"].Validation.Operator == 1
                    && Convert.ToString(sheet.Range["E3"].Validation.Formula1) == first
                    && Convert.ToString(sheet.Range["E3"].Validation.Formula2) == second, "Hidden validation rule changed");
            });
            Test("D08-U01-all-blank-apply-undo", delegate
            {
                sheet.Range["E2"].Formula2 = "=10+5";
                sheet.Range["E3"].NumberFormat = "@"; sheet.Range["E3"].Value2 = "00123"; sheet.Range["E3"].NumberFormat = "00000";
                sheet.Range["E4"].Value2 = true; sheet.Range["E2:E4"].Select();
                string before = Signature("E1:E5");
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Source(CellValue.Empty(), CellValue.Empty(), CellValue.Empty())), null, null);
                    Check(V("E2") == null && V("E3") == null && V("E4") == null, "All blank items did not clear exactly three cells");
                    Check(!(bool)app.CommandBars.GetEnabledMso("Undo"), "Native Undo must remain disabled after own empty write");
                    e.UndoLast(); Check(before == Signature("E1:E5"), "All blank write did not restore before types/formulas/formats");
                }
            });
            Test("U02-mixed-formula-type-format-backup", delegate
            {
                sheet.Range["E2"].Formula2 = "=10+5"; sheet.Range["E2"].NumberFormat = "00000";
                sheet.Range["E3"].NumberFormat = "@"; sheet.Range["E3"].Value2 = "00123"; sheet.Range["E3"].NumberFormat = "0.0";
                object standardFormat = sheet.Range["F1"].NumberFormat;
                sheet.Range["E4"].ClearContents(); sheet.Range["E4"].NumberFormat = standardFormat;
                sheet.Range["E2:E4"].Select(); string before = Signature("E1:E5");
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Source(CellValue.Text("=1+1"), CellValue.Number(85), CellValue.Empty())), null, null);
                    Check(!(bool)sheet.Range["E2"].HasFormula && (string)V("E2") == "=1+1", "Mixed write literal");
                    Check((string)sheet.Range["E2"].NumberFormat == "00000" && (string)sheet.Range["E3"].NumberFormat == "0.0" && Object.Equals((object)sheet.Range["E4"].NumberFormat, standardFormat), "Mixed formats changed");
                    var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
                    var epoch = (UndoEpoch)typeof(ExcelEngine).GetField("epoch", flags).GetValue(e);
                    results.Add("U02 gate available=" + epoch.Available + ";epoch=" + epoch.Version + ";savedEpoch=" + typeof(ExcelEngine).GetField("undoEpoch", flags).GetValue(e) + ";allowed=" + typeof(ExcelEngine).GetField("undoAllowed", flags).GetValue(e) + ";savedCommand=" + typeof(ExcelEngine).GetField("undoCommand", flags).GetValue(e) + ";nativeUndo=" + app.CommandBars.GetEnabledMso("Undo") + ";sortFields=" + sheet.Sort.SortFields.Count + ";selection=" + app.Selection.Address);
                    e.UndoLast(); Check(before == Signature("E1:E5"), "Mixed formula/type/format backup failed");
                }
            });
            Test("R13-table-header-total", delegate
            {
                sheet.Range["E1"].Value2 = "Data";
                dynamic table = sheet.ListObjects.Add(1, sheet.Range["E1:E4"], Type.Missing, 1);
                try
                {
                    using (var e = new ExcelEngine(app))
                    {
                        table.HeaderRowRange.Select(); RefusePrepare(e, Numbers(1), "E1:E6");
                        table.ShowTotals = true;
                        table.TotalsRowRange.Select(); RefusePrepare(e, Numbers(1), "E1:E6");
                    }
                }
                finally { ExcelEngine.Release(table); }
            });
            Test("D16-empty-string-storage", delegate
            {
                sheet.Range["E2"].Select();
                using (var e = new ExcelEngine(app)) e.Apply(e.Prepare(Source(CellValue.Text(""))), null, null);
                var state = ExcelEngine.ReadCell((object)sheet, 2, 5);
                Check(!state.Formula && (state.Value.Kind == CellValueKind.Empty || state.Value.Equals(CellValue.Text(""))), "Empty string position or literal contract");
                results.Add("D16 actual constant storage kind=" + state.Value.Kind);
            });
            Test("R12-hidden-mixed-formula-column", delegate
            {
                sheet.Range["E1"].Value2 = "Data";
                dynamic table = sheet.ListObjects.Add(1, sheet.Range["E1:E8"], Type.Missing, 1);
                object autoFill = app.AutoCorrect.AutoFillFormulasInLists;
                try
                {
                    app.AutoCorrect.AutoFillFormulasInLists = false;
                    sheet.Range["E8"].Formula2 = "=1+2";
                }
                finally { app.AutoCorrect.AutoFillFormulasInLists = autoFill; }
                Check(!(bool)sheet.Range["E2"].HasFormula && (bool)sheet.Range["E8"].HasFormula, "Fixture must remain mixed");
                sheet.Rows["8:8"].Hidden = true; sheet.Range["E2:E4"].Select();
                using (var e = new ExcelEngine(app)) RefusePrepare(e, Numbers(1, 2, 3), "E1:E8");
                Check((bool)sheet.Rows["8:8"].Hidden && (string)sheet.Range["E8"].Formula2 == "=1+2", "Hidden formula or visibility changed");
                ExcelEngine.Release((object)table);
            });
            Test("U04-identical-values-sort", delegate
            {
                sheet.Range["D2:D4"].Value2 = new object[,] { { 3 }, { 1 }, { 2 } };
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 1, 1)), null, null);
                    sheet.Range["D2:E4"].Sort(sheet.Range["D2"], 1);
                    Pump(); Check(Number("D2", 1), "Sort fixture did not reorder rows");
                    RefuseUndo(e, "D1:E5");
                }
            });
            Test("U04-preexisting-sort-configuration", delegate
            {
                sheet.Range["D2:D4"].Value2 = new object[,] { { 3 }, { 1 }, { 2 } };
                sheet.Range["D2:E4"].Sort(sheet.Range["D2"], 1);
                Check((int)sheet.Sort.SortFields.Count > 0, "Fixture requires existing sort state");
                sheet.Range["E2:E4"].Select();
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 2, 3)), null, null);
                    RefuseUndo(e, "D1:E5");
                }
            });
            Test("U04-table-identical-values-sort", delegate
            {
                sheet.Range["D1"].Value2 = "Key"; sheet.Range["E1"].Value2 = "Pasted";
                sheet.Range["D2:D4"].Value2 = new object[,] { { 3 }, { 1 }, { 2 } };
                dynamic table = sheet.ListObjects.Add(1, sheet.Range["D1:E4"], Type.Missing, 1);
                sheet.Range["E2:E4"].Select();
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 1, 1)), null, null);
                    table.Sort.SortFields.Add(table.ListColumns[1].DataBodyRange, 0, 1);
                    table.Sort.Header = 1; table.Sort.Apply(); Pump();
                    Check(Number("D2", 1), "Table sort fixture must reorder rows");
                    RefuseUndo(e, "D1:E5");
                }
                ExcelEngine.Release((object)table);
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
                    sheet.Rows["2:2"].Delete(); Pump(); RefuseUndo(e, "E1:E5");
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
                    dynamic other = app.Workbooks.Add();
                    try
                    {
                        other.Worksheets[1].Range["A1"].Value2 = "other-owned-test";
                        bool refused = false; try { e.UndoLast(); } catch (ValidationException) { refused = true; }
                        Check(refused && Number("E2", 1), "Wrong workbook Undo wrote original");
                        Check((string)other.Worksheets[1].Range["A1"].Value2 == "other-owned-test", "Wrong workbook was modified");
                    }
                    finally { other.Close(false); ExcelEngine.Release((object)other); book.Activate(); }
                }
            });
            Test("U13-later-automation-edit", delegate
            {
                using (var e = new ExcelEngine(app))
                {
                    e.Apply(e.Prepare(Numbers(1, 2, 3)), null, null);
                    sheet.Range["J1"].Value2 = 42.0; Pump();
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
        finally
        {
            app.EnableEvents = events; app.Calculation = calculation; app.ScreenUpdating = updating; app.StatusBar = status;
        }
        results.Add("SUMMARY passed=" + passed + " failed=" + failed);
        File.WriteAllLines(output, results, Encoding.UTF8);
        Console.WriteLine(results[results.Count - 1]);
        return failed == 0 ? 0 : 1;
    }
}
