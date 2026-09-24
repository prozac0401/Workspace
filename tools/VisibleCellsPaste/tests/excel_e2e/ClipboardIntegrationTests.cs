using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using VisibleCellsPaste;

internal static class ClipboardIntegrationTests
{
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    private static readonly List<string> Results = new List<string>();
    private static int failures;
    private static string Escape(string value) { return "\"" + (value ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t") + "\""; }
    private static void Record(string id, bool pass, string detail)
    {
        if (!pass) failures++;
        string state = pass ? "PASS" : "FAIL";
        Results.Add("{\"id\":" + Escape(id) + ",\"status\":" + Escape(state) + ",\"detail\":" + Escape(detail) + "}");
        Console.WriteLine(state + " " + id + " " + detail);
    }
    private static uint ActualPid(dynamic application)
    { uint pid; GetWindowThreadProcessId(new IntPtr(Convert.ToInt64(application.Hwnd, CultureInfo.InvariantCulture)), out pid); return pid; }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static string Kinds(ClipboardSnapshot snapshot)
    { return String.Join(",", snapshot.Items.GroupBy(x => x.Kind).Select(g => g.Key + "=" + g.Count())); }

    [STAThread]
    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        string report = null;
        try { return MainCore(args, out report); }
        catch (Exception error) { Record("UNHANDLED", false, error.GetType().Name + ": " + error.Message); return 1; }
        finally
        {
            if (report != null)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(report)));
                File.WriteAllText(report, "{\"scope\":\"synthetic owned Excel processes only\",\"utc\":" + Escape(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)) + ",\"failed\":" + failures + ",\"results\":[" + String.Join(",", Results) + "]}", new UTF8Encoding(false));
            }
            GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect(); GC.WaitForPendingFinalizers();
        }
    }

    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static int MainCore(string[] args, out string report)
    {
        report = null;
        bool inspect = args.Length > 0 && args[0] == "--inspect-only";
        int offset = inspect ? 1 : 0;
        if (args.Length < offset + 3) throw new ArgumentException("Usage: [--inspect-only] SOURCE_PID TARGET_PID REPORT.json [copy|cut|RxC|code:EXPECTED_CODE]");
        int sourcePid = Int32.Parse(args[offset], CultureInfo.InvariantCulture);
        int targetPid = Int32.Parse(args[offset + 1], CultureInfo.InvariantCulture);
        report = args[offset + 2];
        string expected = args.Length > offset + 3 ? args[offset + 3] : "copy";
        Check(sourcePid != targetPid, "Source and target must be separately owned Excel processes.");
        dynamic source = ExcelProbe.Attach(sourcePid);
        dynamic target = ExcelProbe.Attach(targetPid);
        Check(ActualPid(source) == (uint)sourcePid && ActualPid(target) == (uint)targetPid, "PID-bound object-model identity mismatch.");
        Record("R15-process-identities", true, "sourcePid=" + sourcePid + ";targetPid=" + targetPid);
        int mode = Convert.ToInt32(source.CutCopyMode, CultureInfo.InvariantCulture);
        uint ownerPid; NativeClipboard.GetWindowThreadProcessId(NativeClipboard.GetClipboardOwner(), out ownerPid);
        Check(ownerPid == (uint)sourcePid, "Clipboard owner is not the explicitly owned source process.");
        Record("source-copy-state", true, "source CutCopyMode=" + mode + "; clipboard owner PID matches; no source cells were read or written");
        uint before = NativeClipboard.GetClipboardSequenceNumber();
        if (mode == 1 && NativeClipboard.HasFormat("XML Spreadsheet"))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(report)));
            File.WriteAllBytes(Path.ChangeExtension(report, ".synthetic.xml.bin"), NativeClipboard.ReadFormatBytes("XML Spreadsheet"));
        }
        ClipboardSnapshot snapshot = null;
        string rejection = null;
        try { snapshot = ClipboardReader.ReadSnapshot(0); }
        catch (ValidationException error) { rejection = error.Code; }
        uint after = NativeClipboard.GetClipboardSequenceNumber();
        Record("R18-read-preserves-clipboard-sequence", before == after, "before=" + before + ";after=" + after);
        if (expected == "cut" || expected.StartsWith("code:", StringComparison.Ordinal))
        {
            string expectedCode = expected == "cut" ? "VCP-CLIPBOARD-CUT" : expected.Substring(5);
            Record(expected == "cut" ? "R19-cut-rejected-no-write" : "expected-rejection-no-write", rejection == expectedCode && snapshot == null, "expected=" + expectedCode + ";actual=" + rejection);
            Record("source-cut-mode-preserved", Convert.ToInt32(source.CutCopyMode, CultureInfo.InvariantCulture) == mode, "source cut/copy state unchanged; no destination workbook created");
            return failures == 0 ? 0 : 1;
        }
        Check(snapshot != null, "Snapshot rejected: " + rejection);
        Record("M0-typed-snapshot", snapshot.ShapeIsVerified && snapshot.ClipboardSequence == before, "rows=" + snapshot.SourceRows + ";columns=" + snapshot.SourceColumns + ";count=" + snapshot.Items.Count + ";kinds=" + Kinds(snapshot));
        if (expected.Contains("x") && !expected.StartsWith("fixture:", StringComparison.Ordinal))
        {
            string[] shape = expected.Split('x');
            Check(shape.Length == 2, "Expected shape must be RxC.");
            Record("expected-shape", snapshot.SourceRows == Int32.Parse(shape[0], CultureInfo.InvariantCulture) && snapshot.SourceColumns == Int32.Parse(shape[1], CultureInfo.InvariantCulture), "expected=" + expected);
        }
        if (snapshot.Items.Count <= 64)
        {
            string typedItems = String.Join(";", snapshot.Items.Select((item, index) => index + ":" + item.Kind + ":" + (item.Value == null ? "<empty>" : Convert.ToString(item.Value, CultureInfo.InvariantCulture))));
            Record("synthetic-typed-items", true, typedItems);
        }
        if (expected.StartsWith("fixture:", StringComparison.Ordinal))
        {
            CellValue[] expectedItems;
            switch (expected.Substring(8))
            {
                case "vertical": expectedItems = new[] { CellValue.Number(85), CellValue.Text("00123"), CellValue.Empty(), CellValue.Text("한글\n줄바꿈"), CellValue.Empty() }; break;
                case "horizontal": expectedItems = new[] { CellValue.Number(85), CellValue.Number(90), CellValue.Number(78) }; break;
                case "blank": expectedItems = new[] { CellValue.Empty(), CellValue.Empty(), CellValue.Empty() }; break;
                case "formulas": expectedItems = new[] { CellValue.Number(2), CellValue.Text(""), CellValue.Boolean(true), CellValue.Error(2042) }; break;
                default: throw new ArgumentException("Unknown expected fixture.");
            }
            int expectedRows = expected == "fixture:horizontal" ? 1 : expectedItems.Length;
            int expectedColumns = expected == "fixture:horizontal" ? expectedItems.Length : 1;
            Record("synthetic-fixture-values", snapshot.Items.SequenceEqual(expectedItems) && snapshot.SourceRows == expectedRows && snapshot.SourceColumns == expectedColumns, "expected fixture=" + expected.Substring(8) + ";shape=" + expectedRows + "x" + expectedColumns);
        }
        if (inspect) return failures == 0 ? 0 : 1;
        CellValue[] values = { CellValue.Number(85), CellValue.Text("00123"), CellValue.Empty(), CellValue.Text("한글\n줄바꿈"), CellValue.Empty() };
        Check(snapshot.SourceRows == 5 && snapshot.SourceColumns == 1 && snapshot.Items.Count == 5, "Apply mode requires the five-row M0 fixture.");
        for (int i = 0; i < values.Length; i++) Check(values[i].Equals(snapshot.Items[i]), "M0 source typed item mismatch at " + i);
        dynamic book = null;
        try
        {
            book = target.Workbooks.Add();
            dynamic sheet = book.Worksheets[1]; sheet.Name = "VCPClipboardTarget";
            sheet.Range["A1:H8"].Value2 = "outside-preserve";
            sheet.Range["E2:E6"].NumberFormat = "0.000";
            sheet.Range["E2:E6"].Value2 = "before";
            sheet.Range["F1"].Formula = "=40+2";
            sheet.Range["F1"].NumberFormat = "00000";
            sheet.Range["E2:E6"].Select();
            using (var engine = new ExcelEngine((object)target))
            {
                PreparedPaste prepared = engine.Prepare(snapshot);
                Check(prepared.Plan.Targets.Count == 5, "Unexpected destination plan size.");
                engine.Apply(prepared, null, null);
                for (int i = 0; i < values.Length; i++)
                {
                    CellState cell = ExcelEngine.ReadCell(sheet, i + 2, 5);
                    Check(!cell.Formula && values[i].Equals(cell.Value), "Target typed item mismatch at " + i);
                    Check(Object.Equals(cell.Format, "0.000"), "Target number format changed at " + i);
                }
                Record("R15-live-cross-process-apply", true, "Five typed source items applied to E2:E6; blanks and string00123 retained; target formats retained");
                for (int row = 1; row <= 8; row++) for (int column = 1; column <= 8; column++)
                {
                    if (column == 5 && row >= 2 && row <= 6) continue;
                    CellState cell = ExcelEngine.ReadCell(sheet, row, column);
                    if (row == 1 && column == 6) Check(cell.Formula && Convert.ToString(cell.FormulaValue, CultureInfo.InvariantCulture) == "=40+2" && Object.Equals(cell.Format, "00000"), "Outside formula or format changed.");
                    else Check(!cell.Formula && cell.Value.Equals(CellValue.Text("outside-preserve")), "Outside sentinel changed.");
                }
                Record("R15-selection-boundary", true, "All non-target cells in A1:H8 retained constants/formula/number-format sentinels");
                for (int i = 0; i < values.Length; i++) Check(snapshot.Items[i].Equals(values[i]), "Immutable snapshot changed after writes.");
                Record("D20-immutable-snapshot", true, "All five source items retained after target writes; no source range lookup");
            }
            return failures == 0 ? 0 : 1;
        }
        finally
        {
            if (book != null) { book.Close(false); ExcelEngine.Release((object)book); }
            ExcelEngine.Release((object)target); ExcelEngine.Release((object)source);
        }
    }
}
