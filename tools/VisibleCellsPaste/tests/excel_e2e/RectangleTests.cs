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
            try { engine.Prepare(source); }
            catch (ValidationException error) { rejected = expectedCode == null || error.Code == expectedCode; }
        Check(rejected, "Expected rejection " + expectedCode); Check(before == Fingerprint(null), "rejection changed cells");
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
            Test("same-count-different-shape-rejected", delegate { sheet.Range["B2:C4"].Select(); RejectUnchanged(Numbers(2, 3), "VCP-SHAPE-MISMATCH"); });
            Test("2D-count-mismatch-rejected", delegate { HiddenRectangle(); RejectUnchanged(Numbers(2, 2), "VCP-COUNT-MISMATCH"); });
            Test("2D-no-single-cell-auto-expansion", delegate { sheet.Range["B2"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-COUNT-MISMATCH"); });
            Test("2D-visible-merge-rejected", delegate { sheet.Range["B2:C2"].Merge(); sheet.Range["B2:C3"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-MERGE-ARRAY"); });
            Test("2D-visible-validation-rejected", delegate { sheet.Range["C3"].Validation.Add(1, 1, 1, "1", "10"); sheet.Range["B2:C3"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-VALIDATION"); });
            Test("whole-row-rejected", delegate { sheet.Rows[2].Select(); RejectUnchanged(Numbers(1, 1), "VCP-SELECTION-SHAPE"); });
            Test("all-columns-hidden-rejected", delegate { sheet.Columns["B:C"].Hidden = true; sheet.Range["B2:C3"].Select(); RejectUnchanged(Numbers(2, 2), "VCP-HIDDEN-COLUMN"); });
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
