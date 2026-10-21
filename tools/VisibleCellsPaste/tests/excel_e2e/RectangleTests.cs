using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using VisibleCellsPaste;

// Owns a new Excel application and temporary, unsaved synthetic workbooks only.
internal static class RectangleTests
{
    static dynamic app, book, sheet;
    static readonly List<string> results = new List<string>();
    static int passed, failed;
    static string only;
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static ClipboardSnapshot Source(int rows, int columns, params CellValue[] values)
    { return new ClipboardSnapshot("SyntheticTypedRectangle", 0, rows, columns, true, values, "test-only; no OS clipboard"); }
    static ClipboardSnapshot Numbers(int rows, int columns)
    { return Source(rows, columns, Enumerable.Range(1, rows * columns).Select(n => CellValue.Number(n)).ToArray()); }
    static void Test(string name, Action body)
    {
        if (only != null && !name.Contains(only)) return;
        try
        {
            book = app.Workbooks.Add(); sheet = book.Worksheets[1];
            sheet.Range["A1:H8"].Value2 = 777.0;
            sheet.Range["A1:H8"].NumberFormat = "0.00";
            sheet.Range["A1:H8"].Interior.Color = 65535;
            sheet.Range["A1:H8"].Font.Bold = true;
            body(); passed++; results.Add("PASS " + name);
        }
        catch (Exception error) { failed++; results.Add("FAIL " + name + " " + error); }
        finally
        {
            app.EnableEvents = true; app.ScreenUpdating = true; app.Calculation = -4105;
            if (book != null) { book.Close(false); ExcelEngine.Release((object)sheet); ExcelEngine.Release((object)book); book = null; sheet = null; }
        }
        Console.WriteLine(results[results.Count - 1]);
    }
    static string Fingerprint(HashSet<string> excluded)
    {
        var text = new StringBuilder();
        for (int row = 1; row <= 8; row++) for (int col = 1; col <= 8; col++)
        {
            CellState cell = ExcelEngine.ReadCell((object)sheet, row, col);
            if (excluded != null && excluded.Contains(cell.Address)) continue;
            text.Append(cell.Address).Append('|').Append(cell.Formula).Append('|').Append(cell.FormulaValue)
                .Append('|').Append(cell.Value.Kind).Append('|').Append(cell.Value.Value).Append('|').Append(cell.Format)
                .Append('|').Append(sheet.Cells[row, col].Interior.Color).Append('|').Append(sheet.Cells[row, col].Font.Bold)
                .Append('|').Append(sheet.Rows[row].Hidden).Append('|').Append(sheet.Columns[col].Hidden).Append(';');
        }
        return text.ToString();
    }
    static void HiddenRectangle()
    {
        sheet.Rows[3].Hidden = true; sheet.Columns[4].Hidden = true;
        sheet.Range["D2:D4"].Formula2 = "=40+2";
        sheet.Range["B3:C3"].Formula2 = "=10+5";
        sheet.Range["B2:E4"].Select();
    }
    static void CheckValues(PreparedPaste prepared)
    {
        for (int i = 0; i < prepared.Plan.Targets.Count; i++)
        {
            TargetCell target = prepared.Plan.Targets[i];
            CellState actual = ExcelEngine.ReadCell((object)sheet, target.Row, target.Column);
            CellValue expected = prepared.Plan.Source.Items[i];
            Check(!actual.Formula && (actual.Value.Equals(expected) ||
                (expected.Kind == CellValueKind.String && (string)expected.Value == "" && actual.Value.Kind == CellValueKind.Empty)), "value/type " + actual.Address);
            Check(Object.Equals(actual.Format, prepared.Before[i].Format), "format " + actual.Address);
        }
    }
    static void RejectUnchanged(ClipboardSnapshot source, string expectedCode)
    {
        string before = Fingerprint(null); bool rejected = false;
        using (var engine = new ExcelEngine((object)app))
            try { using (var unexpected = engine.Prepare(source)) { } }
            catch (ValidationException error) { rejected = expectedCode == null || error.Code == expectedCode; }
        Check(rejected, "Expected rejection " + expectedCode); Check(before == Fingerprint(null), "rejection changed cells");
    }
    static void CheckTargets(PreparedPaste prepared, string expected)
    { Check(String.Join(",", prepared.Before.Select(c => c.Address)) == expected, "visible target positions"); }
    static string SelectionAddress()
    { using (var refs = new ComScope()) { dynamic selected = refs.Own((object)app.Selection); return selected.Address; } }
    static void RejectApplyUnchanged(ExcelEngine engine, PreparedPaste prepared)
    {
        string before = Fingerprint(null); bool rejected = false;
        try { engine.Apply(prepared, null, null); }
        catch (ValidationException error) { rejected = error.Code == "VCP-TARGET-CHANGED"; }
        Check(rejected && before == Fingerprint(null), "changed anchor target was written");
    }
    [STAThread] static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        if (args.Length < 1 || args.Length > 2) throw new ArgumentException("Usage: RectangleTests.exe REPORT.txt [case-name-filter]");
        only = args.Length == 2 ? args[1] : null;
        try
        {
            app = Activator.CreateInstance(Type.GetTypeFromProgID("Excel.Application", true));
            app.DisplayAlerts = false;
            results.Add("Excel " + app.Version + " build " + app.Build + "; process architecture=" + (IntPtr.Size * 8) + "; synthetic typed source; actual Excel engine");
            Test("2x3-hidden-rows-columns-order-preservation-and-undo", delegate {
                HiddenRectangle(); string before = Fingerprint(null);
                using (var engine = new ExcelEngine((object)app))
                {
                    PreparedPaste p = engine.Prepare(Numbers(2, 3));
                    Check(String.Join(",", p.Before.Select(c => c.Address)) == "$B$2,$C$2,$E$2,$B$4,$C$4,$E$4", "row-major visible positions");
                    var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets);
                    engine.Apply(p, null, null); CheckValues(p); Check(outside == Fingerprint(targets), "hidden/outside changed");
                    engine.UndoLast(); Check(before == Fingerprint(null), "undo changed original values/formulas/formats");
                }
            });
            Test("2D-types-blanks-formulas-and-individual-formats", delegate {
                sheet.Range["B2:D3"].Select(); sheet.Range["B2"].Formula2 = "=7+8";
                sheet.Range["C2"].NumberFormat = "00000"; sheet.Range["D3"].NumberFormat = "@";
                var source = Source(2, 3, CellValue.Empty(), CellValue.Text("00123"), CellValue.Text("=1+1"), CellValue.Error(2042), CellValue.Boolean(true), CellValue.Text(""));
                string before = Fingerprint(null);
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(source); Check(p.Formulas == 1 && p.Clears == 1, "confirmation counts"); engine.Apply(p, null, null); CheckValues(p); engine.UndoLast(); }
                Check(before == Fingerprint(null), "typed undo");
            });
            Test("horizontal-source-horizontal-target-hidden-column", delegate {
                sheet.Columns[3].Hidden = true; sheet.Range["B2:E2"].Select();
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(1, 3)); engine.Apply(p, null, null); CheckValues(p); Check((double)sheet.Range["C2"].Value2 == 777, "hidden horizontal cell"); }
            });
            Test("legacy-horizontal-source-vertical-target", delegate {
                sheet.Rows[3].Hidden = true; sheet.Range["B2:B5"].Select();
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(1, 3)); engine.Apply(p, null, null); CheckValues(p); }
            });
            Test("2D-filter-and-hidden-column", delegate {
                sheet.Range["A1"].Value2 = "Keep"; sheet.Range["A2"].Value2 = "yes"; sheet.Range["A3"].Value2 = "no"; sheet.Range["A4"].Value2 = "yes";
                sheet.Range["A1:E4"].AutoFilter(1, "yes"); sheet.Columns[3].Hidden = true; sheet.Range["B2:D4"].Select();
                Check(!(bool)sheet.Rows[2].Hidden && (bool)sheet.Rows[3].Hidden && !(bool)sheet.Rows[4].Hidden, "filter fixture visibility");
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(2, 2)); var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets); engine.Apply(p, null, null); CheckValues(p); Check(outside == Fingerprint(targets), "filter preservation"); }
            });
            Test("2D-explicit-leading-hidden-column", delegate {
                sheet.Range["B2:B3"].Formula2 = "=40+2"; sheet.Columns[2].Hidden = true; sheet.Range["B2:D3"].Select();
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(Numbers(2, 2)); CheckTargets(p, "$C$2,$D$2,$C$3,$D$3");
                    var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets);
                    engine.Apply(p, null, null); CheckValues(p); Check(outside == Fingerprint(targets), "explicit leading hidden column changed");
                }
            });
            Test("same-count-different-shape-rejected", delegate { sheet.Range["B2:C4"].Select(); RejectUnchanged(Numbers(2, 3), "VCP-SHAPE-MISMATCH"); });
            Test("2D-count-mismatch-rejected", delegate { HiddenRectangle(); RejectUnchanged(Numbers(2, 2), "VCP-COUNT-MISMATCH"); });
            Test("anchor-2x3-types-hidden-order-preservation-and-undo", delegate {
                HiddenRectangle(); sheet.Range["B2"].Formula2 = "=7+8";
                sheet.Range["C2"].NumberFormat = "00000"; sheet.Range["E4"].NumberFormat = "@";
                sheet.Range["B2"].Select(); string before = Fingerprint(null);
                var source = Source(2, 3, CellValue.Empty(), CellValue.Text("00123"), CellValue.Text("=1+1"), CellValue.Error(2042), CellValue.Boolean(true), CellValue.Text(""));
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(source); CheckTargets(p, "$B$2,$C$2,$E$2,$B$4,$C$4,$E$4");
                    Check(p.Address == "$B$2" && SelectionAddress() == "$B$2", "anchor selection changed during preparation");
                    Check(p.Formulas == 1 && p.Clears == 1, "expanded confirmation counts");
                    var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets);
                    engine.Apply(p, null, null); CheckValues(p);
                    Check(outside == Fingerprint(targets) && SelectionAddress() == "$B$2", "anchor paste changed hidden/outside cells or selection");
                    engine.UndoLast(); Check(before == Fingerprint(null) && SelectionAddress() == "$B$2", "anchor undo did not restore the expanded target");
                }
            });
            Test("anchor-filter-and-hidden-column", delegate {
                sheet.Range["A1"].Value2 = "Keep"; sheet.Range["A2"].Value2 = "yes"; sheet.Range["A3"].Value2 = "no"; sheet.Range["A4"].Value2 = "yes";
                sheet.Range["A1:E4"].AutoFilter(1, "yes"); sheet.Columns[3].Hidden = true; sheet.Range["B2"].Select();
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(Numbers(2, 2)); CheckTargets(p, "$B$2,$D$2,$B$4,$D$4");
                    var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets);
                    engine.Apply(p, null, null); CheckValues(p); Check(outside == Fingerprint(targets), "anchor filter preservation");
                }
            });
            Test("anchor-horizontal-source-keeps-horizontal-shape", delegate {
                sheet.Columns[3].Hidden = true; sheet.Range["B2"].Select();
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(Numbers(1, 3)); CheckTargets(p, "$B$2,$D$2,$E$2");
                    engine.Apply(p, null, null); CheckValues(p); Check((double)sheet.Range["B3"].Value2 == 777, "anchor source was rotated into a column");
                }
            });
            Test("anchor-blank-outside-used-range-single-cell-and-undo", delegate {
                using (var refs = new ComScope())
                {
                    dynamic used = refs.Own((object)sheet.UsedRange), usedRows = refs.Own((object)used.Rows);
                    Check((int)used.Row + (int)usedRows.Count - 1 < 20, "single-cell anchor fixture is not outside UsedRange");
                }
                string outside = Fingerprint(null); sheet.Range["B20"].Select();
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(Source(1, 1, CellValue.Text("00123"))); CheckTargets(p, "$B$20");
                    Check(p.Before[0].Value.Kind == CellValueKind.Empty && p.Address == "$B$20" && SelectionAddress() == "$B$20", "blank anchor preparation");
                    object originalFormat = p.Before[0].Format;
                    engine.Apply(p, null, null); CheckValues(p);
                    Check(outside == Fingerprint(null) && SelectionAddress() == "$B$20", "blank anchor changed existing cells or selection");
                    engine.UndoLast(); CellState restored = ExcelEngine.ReadCell((object)sheet, 20, 2);
                    Check(!restored.Formula && restored.Value.Kind == CellValueKind.Empty && Object.Equals(restored.Format, originalFormat), "blank anchor undo");
                    Check(outside == Fingerprint(null) && SelectionAddress() == "$B$20", "blank anchor undo changed existing cells or selection");
                }
            });
            Test("anchor-blank-outside-used-range-horizontal-hidden-column-and-undo", delegate {
                sheet.Columns[3].Hidden = true;
                using (var refs = new ComScope())
                {
                    dynamic used = refs.Own((object)sheet.UsedRange), usedRows = refs.Own((object)used.Rows);
                    Check((int)used.Row + (int)usedRows.Count - 1 < 20, "horizontal anchor fixture is not outside UsedRange");
                }
                string outside = Fingerprint(null); sheet.Range["B20"].Select();
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(Source(1, 3, CellValue.Text("00123"), CellValue.Boolean(true), CellValue.Number(42))); CheckTargets(p, "$B$20,$D$20,$E$20");
                    Check(p.Before.All(c => c.Value.Kind == CellValueKind.Empty) && p.Address == "$B$20" && SelectionAddress() == "$B$20", "blank horizontal preparation");
                    object[] originalFormats = p.Before.Select(c => c.Format).ToArray();
                    engine.Apply(p, null, null); CheckValues(p);
                    Check(outside == Fingerprint(null) && SelectionAddress() == "$B$20" && (object)sheet.Range["C20"].Value2 == null, "blank horizontal paste preservation");
                    engine.UndoLast(); int[] columns = { 2, 4, 5 };
                    for (int i = 0; i < columns.Length; i++)
                    {
                        CellState restored = ExcelEngine.ReadCell((object)sheet, 20, columns[i]);
                        Check(!restored.Formula && restored.Value.Kind == CellValueKind.Empty && Object.Equals(restored.Format, originalFormats[i]), "blank horizontal undo");
                    }
                    Check(outside == Fingerprint(null) && SelectionAddress() == "$B$20" && (object)sheet.Range["C20"].Value2 == null, "blank horizontal undo preservation");
                }
            });
            Test("anchor-vertical-source-skips-hidden-row", delegate {
                sheet.Rows[3].Hidden = true; sheet.Range["B2"].Select();
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(3, 1)); CheckTargets(p, "$B$2,$B$4,$B$5"); engine.Apply(p, null, null); CheckValues(p); }
            });
            Test("anchor-hidden-start-skips-row-and-column", delegate {
                sheet.Rows[2].Hidden = true; sheet.Columns[2].Hidden = true; sheet.Range["B2"].Select();
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(Numbers(2, 2)); CheckTargets(p, "$C$3,$D$3,$C$4,$D$4");
                    var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets);
                    engine.Apply(p, null, null); CheckValues(p); Check(outside == Fingerprint(targets) && SelectionAddress() == "$B$2", "hidden anchor was written or selection moved");
                }
            });
            Test("anchor-bottom-boundary-rejected", delegate {
                sheet.Range["B1048576"].Value2 = 888.0; sheet.Range["B1048576"].Select();
                RejectUnchanged(Numbers(2, 1), "VCP-ANCHOR-SPACE"); Check((double)sheet.Range["B1048576"].Value2 == 888, "bottom boundary changed");
            });
            Test("anchor-right-boundary-rejected", delegate {
                sheet.Range["XFD2"].Value2 = 888.0; sheet.Range["XFD2"].Select();
                RejectUnchanged(Numbers(1, 2), "VCP-ANCHOR-SPACE"); Check((double)sheet.Range["XFD2"].Value2 == 888, "right boundary changed");
            });
            Test("anchor-full-width-physical-span-with-two-visible-columns", delegate {
                sheet.Range["XFD2"].Value2 = 888.0; sheet.Range["XFD2"].NumberFormat = "00000";
                sheet.Columns["B:XFC"].Hidden = true; sheet.Range["A2"].Select(); string before = Fingerprint(null);
                using (var engine = new ExcelEngine((object)app))
                {
                    var p = engine.Prepare(Numbers(1, 2)); CheckTargets(p, "$A$2,$XFD$2");
                    var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets);
                    engine.Apply(p, null, null); CheckValues(p); Check(outside == Fingerprint(targets) && SelectionAddress() == "$A$2", "full-width anchor preservation");
                    engine.UndoLast(); Check(before == Fingerprint(null) && (double)sheet.Range["XFD2"].Value2 == 888 && (string)sheet.Range["XFD2"].NumberFormat == "00000", "full-width anchor undo");
                }
            });
            Test("anchor-all-remaining-rows-hidden-rejected", delegate {
                sheet.Range["B1048574:B1048576"].Value2 = 888.0; sheet.Rows["1048574:1048576"].Hidden = true; sheet.Range["B1048574"].Select();
                RejectUnchanged(Numbers(1, 1), "VCP-ANCHOR-SPACE");
                Check((double)sheet.Range["B1048574"].Value2 == 888 && (double)sheet.Range["B1048576"].Value2 == 888, "hidden trailing rows changed");
            });
            Test("anchor-all-remaining-columns-hidden-rejected", delegate {
                sheet.Range["XFB2:XFD2"].Value2 = 888.0; sheet.Columns["XFB:XFD"].Hidden = true; sheet.Range["XFB2"].Select();
                RejectUnchanged(Numbers(1, 1), "VCP-ANCHOR-SPACE");
                Check((double)sheet.Range["XFB2"].Value2 == 888 && (double)sheet.Range["XFD2"].Value2 == 888, "hidden trailing columns changed");
            });
            Test("anchor-selection-change-before-write-rejected", delegate {
                sheet.Range["B2"].Select();
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(2, 2)); sheet.Range["C2"].Select(); RejectApplyUnchanged(engine, p); }
            });
            Test("anchor-visibility-shift-before-write-rejected", delegate {
                sheet.Range["B2"].Select();
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(2, 2)); sheet.Columns[3].Hidden = true; RejectApplyUnchanged(engine, p); }
            });
            Test("anchor-expanded-endpoint-validation-rejected", delegate {
                sheet.Range["C3"].Validation.Add(1, 1, 1, "1", "10"); sheet.Range["B2"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-VALIDATION");
            });
            Test("anchor-interrupted-write-rollback", delegate {
                HiddenRectangle(); sheet.Range["B2"].Select(); string before = Fingerprint(null);
                using (var engine = new ExcelEngine((object)app))
                {
                    engine.FailAfterWrites = 2; bool rejected = false;
                    try { engine.Apply(engine.Prepare(Numbers(2, 3)), null, null); } catch (InvalidOperationException) { rejected = true; }
                    Check(rejected && engine.LastOutcome == "rolled-back", "anchor rollback outcome");
                }
                Check(before == Fingerprint(null), "anchor rollback preservation");
            });
            Test("2D-visible-merge-rejected", delegate { sheet.Range["B2:C2"].Merge(); sheet.Range["B2:C3"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-MERGE-ARRAY"); });
            Test("2D-visible-validation-rejected", delegate { sheet.Range["C3"].Validation.Add(1, 1, 1, "1", "10"); sheet.Range["B2:C3"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-VALIDATION"); });
            Test("whole-row-rejected", delegate { sheet.Rows[2].Select(); RejectUnchanged(Numbers(1, 1), "VCP-SELECTION-SHAPE"); });
            Test("all-columns-hidden-rejected", delegate { sheet.Columns["B:C"].Hidden = true; sheet.Range["B2:C3"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-NO-VISIBLE"); });
            Test("2D-visibility-change-before-write-rejected", delegate {
                sheet.Range["B2:C3"].Select(); using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(2, 2)); sheet.Columns[3].Hidden = true; string before = Fingerprint(null); bool rejected = false; try { engine.Apply(p, null, null); } catch (ValidationException) { rejected = true; } Check(rejected && before == Fingerprint(null), "changed visibility was written"); }
            });
            Test("2D-interrupted-write-rollback", delegate {
                HiddenRectangle(); string before = Fingerprint(null); using (var engine = new ExcelEngine((object)app)) { engine.FailAfterWrites = 2; bool rejected = false; try { engine.Apply(engine.Prepare(Numbers(2, 3)), null, null); } catch (InvalidOperationException) { rejected = true; } Check(rejected && engine.LastOutcome == "rolled-back", "rollback outcome"); } Check(before == Fingerprint(null), "rollback preservation");
            });
            Test("2D-cancel-after-write-rollback", delegate {
                HiddenRectangle(); string before = Fingerprint(null); using (var engine = new ExcelEngine((object)app)) { engine.CancelAfterWrite = true; try { engine.Apply(engine.Prepare(Numbers(2, 3)), null, null); } catch (InvalidOperationException) { } Check(engine.LastOutcome == "rolled-back", "cancel outcome"); } Check(before == Fingerprint(null), "cancel preservation");
            });
            Test("2D-partial-recovery-blocks-further-writes", delegate {
                HiddenRectangle(); using (var engine = new ExcelEngine((object)app)) { engine.FailAfterWrites = 2; engine.FailRecoveryAt = 0; bool rejected = false; try { engine.Apply(engine.Prepare(Numbers(2, 3)), null, null); } catch (RecoveryException) { rejected = true; } Check(rejected && engine.RecoveryRequired, "partial recovery state"); try { engine.Prepare(Numbers(2, 3)); throw new Exception("Follow-up allowed"); } catch (ValidationException error) { Check(error.Code == "VCP-RECOVERY-REQUIRED", "follow-up code"); } }
            });
            Test("2D-table-hidden-formula-column-excluded", delegate {
                sheet.Range["B1:D1"].Value2 = new object[,] { { "First", "Second", "Calculated" } };
                dynamic table = sheet.ListObjects.Add(1, sheet.Range["B1:D4"], Type.Missing, 1);
                sheet.Range["D2:D4"].Formula2 = "=40+2"; sheet.Columns[4].Hidden = true; sheet.Range["B2:D3"].Select();
                using (var engine = new ExcelEngine((object)app)) { var p = engine.Prepare(Numbers(2, 2)); var targets = new HashSet<string>(p.Before.Select(c => c.Address)); string outside = Fingerprint(targets); engine.Apply(p, null, null); CheckValues(p); Check(outside == Fingerprint(targets), "hidden table formula column changed"); }
            });
            Test("2D-table-targeted-formula-column-rejected", delegate {
                sheet.Range["B1:C1"].Value2 = new object[,] { { "First", "Second" } };
                dynamic table = sheet.ListObjects.Add(1, sheet.Range["B1:C4"], Type.Missing, 1);
                sheet.Range["C2:C4"].Formula2 = "=40+2"; sheet.Rows[4].Hidden = true; sheet.Range["B2:C3"].Select();
                RejectUnchanged(Numbers(2, 2), "VCP-TABLE-FORMULA");
            });
            results.Add("SUMMARY passed=" + passed + " failed=" + failed); Console.WriteLine(results.Last());
            return failed == 0 ? 0 : 1;
        }
        finally
        {
            if (app != null) { app.Quit(); ExcelEngine.Release((object)app); }
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0]))); File.WriteAllLines(args[0], results, new UTF8Encoding(false));
            GC.Collect(); GC.WaitForPendingFinalizers();
        }
    }
}
