using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;
using VisibleCellsPaste;

// Test-only direct-engine cases. Never starts or quits Excel. The caller must supply
// an explicitly owned VCP workbook PID and a fixture directory below repo artifacts.
// This is not evidence of context-menu clicks, install lifecycle or automatic loading.
class RemainingSafetyTests
{
    static dynamic app, initialBook;
    static string output, fixtureRoot, filter;
    static int passed, failed, notRun;
    static readonly List<string> results = new List<string>();
    sealed class NotRunException : Exception { public NotRunException(string s) : base(s) {} }
    sealed class OwnedBook { public object Value; public bool Open = true; }
    sealed class CaseScope : IDisposable
    {
        readonly List<OwnedBook> books = new List<OwnedBook>();
        readonly List<object> protectedWindows = new List<object>();
        readonly ComScope ownedReferences = new ComScope();
        public readonly ComScope References = new ComScope();
        bool disposed;
        public readonly string DirectoryPath;
        public CaseScope(string id)
        {
            DirectoryPath = Path.Combine(fixtureRoot, id + "-" + Guid.NewGuid().ToString("N"));
            if (Directory.Exists(DirectoryPath)) throw new Exception("Unique fixture directory already exists");
            Directory.CreateDirectory(DirectoryPath);
        }
        public string PathFor(string name, string subfolder)
        {
            string directory = Path.Combine(DirectoryPath, subfolder);
            Directory.CreateDirectory(directory);
            string path = Path.GetFullPath(Path.Combine(directory, name));
            Check(path.StartsWith(DirectoryPath + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase), "Fixture escaped owned directory");
            Check(!File.Exists(path), "Refusing to replace an existing fixture");
            return path;
        }
        public dynamic NewBook(string file)
        {
            using (var refs = new ComScope())
            {
                dynamic workbooks = refs.Own((object)app.Workbooks);
                dynamic book = ownedReferences.Own((object)workbooks.Add());
                books.Add(new OwnedBook { Value = (object)book });
                dynamic sheet = Worksheet(refs, (object)book);
                sheet.Name = "VCPData";
                dynamic contents = CellRange(refs, (object)sheet, "E1:E8");
                contents.Value2 = 777.0;
                contents.NumberFormat = "0.00";
                CellRange(refs, (object)sheet, "E2").Select();
                book.SaveAs(file, 51);
                return book;
            }
        }
        public dynamic Open(string file, bool readOnly)
        {
            using (var refs = new ComScope())
            {
                dynamic workbooks = refs.Own((object)app.Workbooks);
                dynamic book = ownedReferences.Own((object)workbooks.Open(file, 0, readOnly));
                books.Add(new OwnedBook { Value = (object)book });
                return book;
            }
        }
        public dynamic OpenProtected(string file)
        {
            // Official API: https://learn.microsoft.com/en-us/office/vba/api/excel.protectedviewwindows.open
            using (var refs = new ComScope())
            {
                dynamic windows = refs.Own((object)app.ProtectedViewWindows);
                dynamic window = ownedReferences.Own((object)windows.Open(file));
                protectedWindows.Add((object)window);
                return window;
            }
        }
        public void Close(object book)
        {
            OwnedBook owned = books.FirstOrDefault(x => Object.ReferenceEquals(x.Value, book));
            Check(owned != null && owned.Open, "Only this case's owned open workbook may close");
            ((dynamic)book).Close(false);
            owned.Open = false;
        }
        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            // Release case-local child acquisitions before final owned window/book cleanup.
            try { References.Dispose(); }
            catch (Exception error) { RecordCleanupFailure("Case references", error); }
            try
            {
                for (int i = protectedWindows.Count - 1; i >= 0; --i)
                    try { ((dynamic)protectedWindows[i]).Close(); }
                    catch (Exception error) { RecordCleanupFailure("ProtectedView", error); }
                for (int i = books.Count - 1; i >= 0; --i)
                    if (books[i].Open)
                        try { ((dynamic)books[i].Value).Close(false); books[i].Open = false; }
                        catch (Exception error) { RecordCleanupFailure("Workbook", error); }
            }
            finally
            {
                try { ownedReferences.Dispose(); }
                catch (Exception error) { RecordCleanupFailure("Owned window/book references", error); }
            }
        }
    }
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static ClipboardSnapshot Source(params double[] values)
    {
        return new ClipboardSnapshot("SyntheticTyped-test-only", 0, values.Length, 1, true,
            values.Select(CellValue.Number).ToArray(), "No real clipboard provenance in these cases");
    }
    static void RecordCleanupFailure(string kind, Exception error)
    { failed++; results.Add("CLEANUP FAIL " + kind + ": " + error); }
    static string HashFile(string file)
    {
        using (var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        using (var hash = SHA256.Create())
            return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
    }
    static dynamic Worksheet(ComScope refs, object workbook)
    {
        dynamic sheets = refs.Own((object)((dynamic)workbook).Worksheets);
        return refs.Own((object)sheets[1]);
    }
    static dynamic CellRange(ComScope refs, object worksheet, string address)
    { return refs.Own((object)((dynamic)worksheet).Range[address]); }
    static void Restore(string kind, Action action)
    {
        try { action(); }
        catch (Exception error) { RecordCleanupFailure(kind, error); }
    }
    static string Signature(object worksheet, string address)
    {
        using (var refs = new ComScope())
        {
            dynamic range = CellRange(refs, worksheet, address);
            dynamic cells = refs.Own((object)range.Cells);
            int count = Convert.ToInt32(cells.CountLarge);
            var text = new StringBuilder();
            for (int i = 1; i <= count; i++)
                using (var cellRefs = new ComScope())
                {
                    dynamic cell = cellRefs.Own((object)cells[i]);
                    CellState state = ExcelEngine.ReadCell(worksheet, (int)cell.Row, (int)cell.Column);
                    text.Append(state.Address).Append(':').Append(state.Formula).Append(':')
                        .Append(state.Formula ? state.FormulaProperty : state.Value.Kind.ToString()).Append(':')
                        .Append(state.Formula ? state.FormulaValue : state.Value.Value).Append(':')
                        .Append(state.Format).Append(';');
                }
            return text.ToString();
        }
    }
    static void RefusePrepare(ExcelEngine engine, ClipboardSnapshot input, params string[] allowedCodes)
    {
        string code = null;
        try { using (var unexpected = engine.Prepare(input)) {} }
        catch (ValidationException error) { code = error.Code; }
        Check(code != null, "Expected prewrite validation refusal");
        if (allowedCodes.Length != 0) Check(allowedCodes.Contains(code), "Unexpected validation code " + code);
        results.Add("  refusal=" + code);
    }
    static void RefuseUndo(ExcelEngine engine, object sheet, string address)
    {
        string before = Signature(sheet, address), code = null;
        try { engine.UndoLast(); }
        catch (ValidationException error) { code = error.Code; }
        Check(code != null, "Expected stale Undo refusal");
        Check(before == Signature(sheet, address), "Refused Undo modified replacement contents/types/formats");
        results.Add("  undo_refusal=" + code);
    }
    static void Test(string id, Action<CaseScope> action)
    {
        if (filter != null && id.IndexOf(filter, StringComparison.Ordinal) < 0) return;
        Console.WriteLine("START " + id);
        var watch = Stopwatch.StartNew();
        try
        {
            using (var scope = new CaseScope(id)) action(scope);
            passed++; results.Add(id + " PASS " + watch.ElapsedMilliseconds + "ms");
        }
        catch (NotRunException error) { notRun++; results.Add(id + " NOT_RUN " + error.Message); }
        catch (Exception error) { failed++; results.Add(id + " FAIL " + error); }
        finally
        {
            try { initialBook.Activate(); }
            catch (Exception error) { RecordCleanupFailure("Restore initial workbook", error); }
            File.WriteAllLines(output, results, Encoding.UTF8);
        }
        Console.WriteLine(results[results.Count - 1]);
    }
    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length < 3) throw new ArgumentException("PID result-file owned-fixture-directory [test-filter]");
        output = Path.GetFullPath(args[1]); fixtureRoot = Path.GetFullPath(args[2]);
        filter = args.Length > 3 ? args[3] : null;
        string allowed = Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "artifacts", "visible-cells-paste")) + Path.DirectorySeparatorChar;
        Check(fixtureRoot.StartsWith(allowed, StringComparison.OrdinalIgnoreCase), "Run from repository root; fixture path must stay under artifacts/visible-cells-paste");
        Check(output.StartsWith(allowed, StringComparison.OrdinalIgnoreCase), "Result file must stay under artifacts/visible-cells-paste");
        Directory.CreateDirectory(fixtureRoot); Directory.CreateDirectory(Path.GetDirectoryName(output));
        var initialRefs = new ComScope();
        try
        {
            app = initialRefs.Own(ExcelProbe.Attach(Int32.Parse(args[0])));
            initialBook = initialRefs.Own((object)app.ActiveWorkbook);
            Check(((string)initialBook.Name).StartsWith("VCP-", StringComparison.Ordinal), "Explicitly owned VCP fixture required");
            results.Add("Synthetic owned-workbook direct engine tests. No process launch/quit; no autoload or context-menu claim.");
            results.Add("Excel=" + app.Version + ";Build=" + app.Build + ";PID=" + args[0] + ";UTC=" + DateTime.UtcNow.ToString("o"));
            object events = app.EnableEvents, calculation = app.Calculation, updating = app.ScreenUpdating, status = app.StatusBar, alerts = app.DisplayAlerts;
            results.Add("STATUS captured type="+(status==null?"null":status.GetType().AssemblyQualifiedName)+" value=["+status+"]");
            object originalSheet = initialRefs.Own((object)app.ActiveSheet), originalSelection = initialRefs.Own((object)app.Selection);
            int initialWorkbookCount, initialProtectedCount;
            using (var countRefs = new ComScope())
            {
                dynamic workbooks = countRefs.Own((object)app.Workbooks), windows = countRefs.Own((object)app.ProtectedViewWindows);
                initialWorkbookCount = (int)workbooks.Count; initialProtectedCount = (int)windows.Count;
            }
            try
            {
                app.EnableEvents = true; app.Calculation = -4105; app.ScreenUpdating = true;
                Test("R09-readonly-workbook", scope =>
                {
                    var refs = scope.References;
                    string file = scope.PathFor("VCP-ReadOnly.xlsx", "readonly");
                    dynamic book = scope.NewBook(file); scope.Close((object)book);
                    string diskBefore = HashFile(file);
                    dynamic readOnly = scope.Open(file, true), sheet = Worksheet(refs, (object)readOnly);
                    Check((bool)readOnly.ReadOnly, "Fixture is not actually read-only");
                    CellRange(refs, (object)sheet, "E2").Select(); string before = Signature((object)sheet, "E1:E3");
                    using (var engine = new ExcelEngine(app)) RefusePrepare(engine, Source(85), "VCP-READONLY");
                    Check(before == Signature((object)sheet, "E1:E3") && diskBefore == HashFile(file), "Read-only contents or file changed");
                });
                Test("R09-protected-view", scope =>
                {
                    var refs = scope.References;
                    string file = scope.PathFor("VCP-ProtectedView.xlsx", "protected-view");
                    dynamic book = scope.NewBook(file); scope.Close((object)book); string diskBefore = HashFile(file);
                    dynamic window;
                    try { window = scope.OpenProtected(file); }
                    catch (System.Runtime.InteropServices.COMException error)
                    { throw new NotRunException("Excel refused creation of a Protected View fixture: " + error.HResult.ToString("X8")); }
                    window.Activate();
                    Check(refs.Own((object)app.ActiveProtectedViewWindow) != null, "Protected View is not active");
                    dynamic protectedBook = refs.Own((object)window.Workbook);
                    Check(String.Equals((string)protectedBook.FullName, file, StringComparison.OrdinalIgnoreCase), "Wrong Protected View fixture");
                    dynamic sheet = Worksheet(refs, (object)protectedBook); string before = Signature((object)sheet, "E1:E3");
                    using (var engine = new ExcelEngine(app)) RefusePrepare(engine, Source(85), "VCP-PROTECTED-VIEW", "VCP-READONLY");
                    Check(before == Signature((object)sheet, "E1:E3") && diskBefore == HashFile(file), "Protected View contents or file changed");
                });
                Test("R10-pivot-target", scope =>
                {
                    var refs = scope.References;
                    dynamic book = scope.NewBook(scope.PathFor("VCP-Pivot.xlsx", "pivot")), sheet = Worksheet(refs, (object)book);
                    CellRange(refs, (object)sheet, "A1:B5").Value2 = new object[,] {{"Category", "Amount"}, {"A", 1.0}, {"A", 2.0}, {"B", 3.0}, {"B", 4.0}};
                    string source = "'[" + (string)book.Name + "]" + (string)sheet.Name + "'!R1C1:R5C2";
                    dynamic caches = refs.Own((object)book.PivotCaches());
                    dynamic cache = refs.Own((object)caches.Create(1, source));
                    dynamic pivot = refs.Own((object)cache.CreatePivotTable(CellRange(refs, (object)sheet, "H2"), "VCP_Pivot"));
                    dynamic category = refs.Own((object)pivot.PivotFields("Category"));
                    category.Orientation = 1;
                    category.Position = 1;
                    dynamic amount = refs.Own((object)pivot.PivotFields("Amount"));
                    refs.Own((object)pivot.AddDataField(amount, "SumAmount", -4157));
                    pivot.RefreshTable();
                    dynamic pivots = refs.Own((object)sheet.PivotTables()), dataFields = refs.Own((object)pivot.DataFields);
                    Check((int)pivots.Count == 1 && (int)dataFields.Count == 1, "Real pivot fixture not created");
                    dynamic tableRange = refs.Own((object)pivot.TableRange2), tableCells = refs.Own((object)tableRange.Cells);
                    dynamic target = refs.Own((object)tableCells[2, 2]); target.Select();
                    string before = Signature((object)sheet, "A1:B5") + Signature((object)sheet, "H2:I8");
                    string address = (string)tableRange.Address;
                    using (var engine = new ExcelEngine(app)) RefusePrepare(engine, Source(85), "VCP-PIVOT");
                    Check(before == Signature((object)sheet, "A1:B5") + Signature((object)sheet, "H2:I8") && address == (string)((dynamic)refs.Own((object)pivot.TableRange2)).Address, "Pivot or source changed");
                });
                Test("R10-grouped-sheets", scope =>
                {
                    var refs = scope.References;
                    dynamic book = scope.NewBook(scope.PathFor("VCP-Grouped.xlsx", "group")), first = Worksheet(refs, (object)book);
                    dynamic worksheets = refs.Own((object)book.Worksheets);
                    dynamic second = refs.Own((object)worksheets.Add(Type.Missing, first)); second.Name = "VCPSecond";
                    CellRange(refs, (object)first, "E2").Value2 = 111.0; CellRange(refs, (object)second, "E2").Value2 = 222.0;
                    first.Activate(); CellRange(refs, (object)first, "E2").Select(); first.Select(); second.Select(false);
                    dynamic activeWindow = refs.Own((object)app.ActiveWindow), selectedSheets = refs.Own((object)activeWindow.SelectedSheets);
                    Check((int)selectedSheets.Count == 2, "Two sheets were not grouped");
                    string before = Signature((object)first, "E2") + Signature((object)second, "E2");
                    try
                    {
                        using (var engine = new ExcelEngine(app)) RefusePrepare(engine, Source(85), "VCP-GROUPED");
                        Check(before == Signature((object)first, "E2") + Signature((object)second, "E2"), "Grouped sheets changed");
                    }
                    finally { first.Select(); }
                });
                foreach (int selectionRows in new[] { 199999, 200000 })
                {
                    Test("P04-selection-" + selectionRows, scope =>
                    {
                        var refs = scope.References;
                        dynamic book = scope.NewBook(scope.PathFor("VCP-SelectionBoundary.xlsx", "selection-" + selectionRows)), sheet = Worksheet(refs, (object)book);
                        dynamic hiddenRows = refs.Own((object)CellRange(refs, (object)sheet, "E2:E" + selectionRows).EntireRow);
                        hiddenRows.Hidden = true;
                        CellRange(refs, (object)sheet, "E1:E" + selectionRows).Select();
                        dynamic selected = refs.Own((object)app.Selection);
                        Check(Convert.ToInt64(selected.CountLarge) == selectionRows, "Selection boundary fixture count wrong");
                        using (var engine = new ExcelEngine(app)) engine.Apply(engine.Prepare(Source(85)), null, null);
                        Check(Convert.ToDouble(CellRange(refs, (object)sheet, "E1").Value2) == 85, "Visible boundary target not written");
                        dynamic sentinel = CellRange(refs, (object)sheet, "E2"), sentinelRow = refs.Own((object)sentinel.EntireRow);
                        Check(Convert.ToDouble(sentinel.Value2) == 777 && (bool)sentinelRow.Hidden, "Hidden boundary sentinel changed");
                        Check((object)CellRange(refs, (object)sheet, "E" + (selectionRows + 1)).Value2 == null, "Cell below selected boundary changed");
                    });
                }
                Test("P04-selection-200001-rejected", scope =>
                {
                    var refs = scope.References;
                    dynamic book = scope.NewBook(scope.PathFor("VCP-SelectionOverLimit.xlsx", "selection-over-limit")), sheet = Worksheet(refs, (object)book);
                    CellRange(refs, (object)sheet, "E1:E200001").Select();
                    string before = Signature((object)sheet, "E1:E8");
                    using (var engine = new ExcelEngine(app)) RefusePrepare(engine, Source(85), "VCP-SELECTION-SHAPE");
                    Check(before == Signature((object)sheet, "E1:E8") && (object)CellRange(refs, (object)sheet, "E200001").Value2 == null, "Over-limit selection modified cells");
                });
                Test("U05-sheet-replaced-same-name-state", scope =>
                {
                    var refs = scope.References;
                    dynamic book = scope.NewBook(scope.PathFor("VCP-SheetReplace.xlsx", "replace")), original = Worksheet(refs, (object)book);
                    string name = (string)original.Name;
                    dynamic worksheets = refs.Own((object)book.Worksheets);
                    dynamic replacement = refs.Own((object)worksheets.Add(Type.Missing, original));
                    CellRange(refs, (object)replacement, "E2").Value2 = 85.0; CellRange(refs, (object)replacement, "E2").NumberFormat = "0.00";
                    original.Activate(); CellRange(refs, (object)original, "E2").Select();
                    using (var engine = new ExcelEngine(app))
                    {
                        engine.Apply(engine.Prepare(Source(85)), null, null);
                        object previousAlerts = app.DisplayAlerts;
                        try { app.DisplayAlerts = false; original.Delete(); }
                        finally { app.DisplayAlerts = previousAlerts; }
                        replacement.Name = name; replacement.Activate(); CellRange(refs, (object)replacement, "E2").Select();
                        RefuseUndo(engine, (object)replacement, "E2");
                        Check(Convert.ToDouble(CellRange(refs, (object)replacement, "E2").Value2) == 85, "Replacement sheet incorrectly restored old777");
                    }
                });
                Test("U05-close-reopen-same-file-state", scope =>
                {
                    var refs = scope.References;
                    string file = scope.PathFor("VCP-Reopen.xlsx", "reopen");
                    dynamic book = scope.NewBook(file), sheet = Worksheet(refs, (object)book);
                    CellRange(refs, (object)sheet, "E2").Value2 = 85.0; book.Save();
                    CellRange(refs, (object)sheet, "E2").Value2 = 777.0; CellRange(refs, (object)sheet, "E2").Select();
                    using (var engine = new ExcelEngine(app))
                    {
                        engine.Apply(engine.Prepare(Source(85)), null, null);
                        scope.Close((object)book); string diskBefore = HashFile(file);
                        dynamic reopened = scope.Open(file, false), newSheet = Worksheet(refs, (object)reopened);
                        CellRange(refs, (object)newSheet, "E2").Select(); Check(Convert.ToDouble(CellRange(refs, (object)newSheet, "E2").Value2) == 85, "Reopened fixture did not match post-write state");
                        RefuseUndo(engine, (object)newSheet, "E1:E3");
                        Check(diskBefore == HashFile(file), "Reopen Undo modified saved file");
                    }
                });
                Test("U06-same-name-different-path-state", scope =>
                {
                    var refs = scope.References;
                    string otherPath = scope.PathFor("VCP-SameName.xlsx", "second"), originalPath = scope.PathFor("VCP-SameName.xlsx", "first");
                    dynamic other = scope.NewBook(otherPath), otherSheet = Worksheet(refs, (object)other);
                    CellRange(refs, (object)otherSheet, "E2").Value2 = 85.0; other.Save(); scope.Close((object)other);
                    dynamic original = scope.NewBook(originalPath), originalSheet2 = Worksheet(refs, (object)original);
                    string name = (string)original.Name; CellRange(refs, (object)originalSheet2, "E2").Select();
                    using (var engine = new ExcelEngine(app))
                    {
                        engine.Apply(engine.Prepare(Source(85)), null, null); scope.Close((object)original);
                        string originalHash = HashFile(originalPath), otherHash = HashFile(otherPath);
                        dynamic replacement = scope.Open(otherPath, false), replacementSheet = Worksheet(refs, (object)replacement);
                        Check((string)replacement.Name == name && !String.Equals((string)replacement.FullName, originalPath, StringComparison.OrdinalIgnoreCase), "Same-name different-file fixture invalid");
                        CellRange(refs, (object)replacementSheet, "E2").Select();
                        Check(Convert.ToDouble(CellRange(refs, (object)replacementSheet, "E2").Value2) == 85, "Replacement state must match original post-write state");
                        RefuseUndo(engine, (object)replacementSheet, "E1:E3");
                        Check(originalHash == HashFile(originalPath) && otherHash == HashFile(otherPath), "Same-name Undo changed a saved file");
                    }
                });
            }
            finally
            {
                Restore("Original workbook", () => initialBook.Activate());
                Restore("Original sheet", () => ((dynamic)originalSheet).Activate());
                Restore("Original selection", () => ((dynamic)originalSelection).Select());
                Restore("EnableEvents", () => app.EnableEvents = events);
                Restore("Calculation", () => app.Calculation = calculation);
                Restore("ScreenUpdating", () => app.ScreenUpdating = updating);
                Restore("StatusBar", () => { object beforeStatus=app.StatusBar; results.Add("STATUS cleanup-before type="+(beforeStatus==null?"null":beforeStatus.GetType().AssemblyQualifiedName)+" value=["+beforeStatus+"]"); ExcelEngine.RestoreStatusBar((object)app,status); object afterStatus=app.StatusBar; results.Add("STATUS cleanup-after type="+(afterStatus==null?"null":afterStatus.GetType().AssemblyQualifiedName)+" value=["+afterStatus+"]"); Check(Object.Equals(status,afterStatus),"Remaining StatusBar cleanup type/value mismatch"); });
                Restore("DisplayAlerts", () => app.DisplayAlerts = alerts);
                Restore("Window counts", () =>
                {
                    using (var countRefs = new ComScope())
                    {
                        dynamic workbooks = countRefs.Own((object)app.Workbooks), windows = countRefs.Own((object)app.ProtectedViewWindows);
                        Check((int)workbooks.Count == initialWorkbookCount && (int)windows.Count == initialProtectedCount, "Owned workbook/window cleanup count mismatch");
                    }
                });
            }
        }
        finally
        {
            try { initialRefs.Dispose(); }
            catch (Exception error) { RecordCleanupFailure("Initial application references", error); }
            app = null; initialBook = null;
        }
        results.Add("SUMMARY passed=" + passed + " failed=" + failed + " not_run=" + notRun);
        File.WriteAllLines(output, results, Encoding.UTF8);
        Console.WriteLine(results[results.Count - 1]);
        return failed != 0 ? 1 : notRun != 0 ? 2 : 0;
    }
}
