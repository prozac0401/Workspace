// API integration for an existing, task-owned Excel PID. This harness does not
// start Excel, open user workbooks, save results, or replace the M1 menu UI test.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace ExcelSelectionExport.IntegrationTests
{
    internal static class FunctionalTests
    {
        private delegate bool EnumProc(IntPtr window, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr window, EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int maximum);
        [DllImport("oleacc.dll")] private static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId, ref Guid iid, [MarshalAs(UnmanagedType.IDispatch)] out object result);
        private static dynamic application;
        private static dynamic startupFixture;
        private static object attachmentWindow;
        private static string startupPath;
        private static int checks, passedCases;
        private static readonly int[] Edges = { 7, 8, 9, 10 };
        private static readonly string[] Cases = { "structure", "types", "dates1900", "dates1904", "singlecell", "formatting", "mergefull", "dynamicarray", "table", "conditionalformat", "manualcached" };

        private sealed class Fixture
        {
            internal object Book, Sheet, Range;
            internal int[] Rows, Columns;
            internal string ExpectedMerge;
            internal bool CompareDisplay;
            internal bool FullXmlSnapshot = true;
        }

        [STAThread]
        private static int Main(string[] args)
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            int result = 1;
            try { result = Run(args); }
            finally
            {
                try { ClearConnectionRoots(); }
                finally
                {
                    // Run and ClearConnectionRoots must leave their frames first:
                    // dynamic property-chain COM temporaries must be released before
                    // process exit, including when a test or explicit release fails.
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                }
            }
            return result;
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static int Run(string[] args)
        {
            try
            {
                if (args.Length < 1 || args.Length > 2)
                    throw new ArgumentException("Usage: FunctionalTests.exe <owned-fixture.xlsx.pid> [all|" + String.Join("|", Cases) + "]");
                string marker = Path.GetFullPath(args[0]);
                if (!marker.EndsWith(".xlsx.pid", StringComparison.OrdinalIgnoreCase))
                    throw new ArgumentException("The exact .xlsx.pid marker created by ExcelProbe is required.");
                startupPath = marker.Substring(0, marker.Length - 4);
                if (!File.Exists(startupPath)) throw new Exception("Owned startup fixture is missing.");
                int pid;
                if (!Int32.TryParse(File.ReadAllText(marker).Trim(), out pid) || pid <= 0) throw new Exception("Invalid PID marker.");
                application = Attach(pid);
                uint attachedPid;
                GetWindowThreadProcessId(new IntPtr((int)application.Hwnd), out attachedPid);
                if (attachedPid != pid) throw new Exception("Attached process differs from the owned PID.");
                if ((int)application.Workbooks.Count != 1)
                    throw new Exception("Refusing to run: owned process must contain only its startup fixture.");
                startupFixture = application.Workbooks[1];
                if (!String.Equals((string)startupFixture.FullName, startupPath, StringComparison.OrdinalIgnoreCase))
                    throw new Exception("Refusing to run: startup workbook does not match the PID marker.");
                dynamic addin = application.COMAddIns.Item("Workspace.ExcelSelectionExport");
                if (!(bool)addin.Connect || addin.Object == null) throw new Exception("Compiled add-in is not connected.");
                string diagnostics = (string)addin.Object.GetDiagnostics();
                if (diagnostics.IndexOf("stage=M1;", StringComparison.OrdinalIgnoreCase) >= 0)
                    throw new Exception("M1-only payload detected: install the functional build first to avoid its modal confirmation.");
                string selected = args.Length == 2 ? args[1] : "all";
                if (selected != "all" && Array.IndexOf(Cases, selected) < 0) throw new ArgumentException("Unknown case: " + selected);
                Console.WriteLine("MODE=API_INTEGRATION; actual context-menu UI activation is tested separately");
                Console.WriteLine("Excel=" + application.Version + ";Build=" + application.Build + ";PID=" + pid);
                Console.WriteLine("DIAGNOSTICS_BEFORE " + diagnostics);
                foreach (string name in Cases) if (selected == "all" || selected == name) RunCase(name, addin);
                startupFixture.Activate();
                Check((int)application.Workbooks.Count == 1, "Only startup fixture remains");
                Console.WriteLine("PASS " + passedCases + " positive API cases; " + checks + " assertions");
                Console.WriteLine("NOT_RUN invalid selections, cancellation, limits, external-link formula, multi-process concurrency, clipboard, undo, install lifecycle, isolated profile, reboot, x86 host");
                return 0;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine("FAIL " + exception);
                try { Console.Error.WriteLine("DIAGNOSTICS_FAILURE " + application.COMAddIns.Item("Workspace.ExcelSelectionExport").Object.GetDiagnostics()); } catch { }
                return 1;
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static dynamic Attach(int pid)
        {
            object result = null;
            EnumProc child = delegate(IntPtr window, IntPtr unused)
            {
                var name = new StringBuilder(256);
                GetClassName(window, name, name.Capacity);
                if (name.ToString() == "EXCEL7")
                {
                    Guid dispatch = new Guid("00020400-0000-0000-C000-000000000046");
                    object native;
                    if (AccessibleObjectFromWindow(window, 0xfffffff0, ref dispatch, out native) == 0) result = native;
                }
                return result == null;
            };
            EnumWindows(delegate(IntPtr window, IntPtr unused)
            {
                uint process;
                GetWindowThreadProcessId(window, out process);
                if (process == pid) EnumChildWindows(window, child, IntPtr.Zero);
                return result == null;
            }, IntPtr.Zero);
            if (result == null) throw new Exception("No workbook window for owned Excel PID " + pid);
            attachmentWindow = result;
            object app = ((dynamic)result).Application;
            result = null;
            return app;
        }

        private static void RunCase(string name, dynamic addin)
        {
            Fixture fixture = null;
            object output = null;
            bool engineMayBeBusy = false;
            string sourceIdentity = "fixture not prepared";
            bool restoreCalculation = name == "manualcached";
            int originalCalculation = restoreCalculation ? (int)application.Calculation : 0;
            var elapsed = System.Diagnostics.Stopwatch.StartNew();
            Console.WriteLine("BEGIN " + name);
            try
            {
                fixture = CreateFixture(name);
                dynamic book = fixture.Book, sheet = fixture.Sheet, range = fixture.Range;
                book.Activate(); sheet.Activate(); range.Select();
                object[,] expected = ProjectValues(range, fixture.Rows, fixture.Columns);
                string sourceBefore = Snapshot(fixture);
                string globals = GlobalSnapshot();
                int before = (int)application.Workbooks.Count;
                sourceIdentity = (string)book.FullName;
                Console.WriteLine("CALLBACK_BEGIN " + name);
                // Export's unused control parameter is declared IDispatch. A literal
                // null becomes VT_EMPTY through the DLR; use the owned application's
                // real IDispatch for this API test. Actual UI supplies IRibbonControl.
                // Once dispatch begins, an RPC/diagnostic failure does not prove
                // the asynchronous job stopped. Preserve its documents until a
                // reliable busy=False observation permits harness cleanup.
                engineMayBeBusy = true;
                addin.Object.Export((object)application);
                string lastDiagnostics = (string)addin.Object.GetDiagnostics();
                Console.WriteLine("CALLBACK_END " + name + ";" + lastDiagnostics);
                var completionWait = System.Diagnostics.Stopwatch.StartNew();
                string previousDiagnostics = lastDiagnostics;
                while (true)
                {
                    bool busyTrue = lastDiagnostics.IndexOf(";busy=True", StringComparison.Ordinal) >= 0;
                    bool busyFalse = lastDiagnostics.IndexOf(";busy=False", StringComparison.Ordinal) >= 0;
                    if (busyTrue == busyFalse)
                        throw new Exception("Cannot determine asynchronous engine state; preserving owned documents; diagnostics=" + lastDiagnostics);
                    engineMayBeBusy = busyTrue;
                    if (lastDiagnostics.IndexOf(";outcome=error:", StringComparison.Ordinal) >= 0
                        || lastDiagnostics.IndexOf(";outcome=canceled;", StringComparison.Ordinal) >= 0)
                        throw new Exception("Asynchronous export ended without success; diagnostics=" + lastDiagnostics);
                    if (busyFalse)
                    {
                        if (lastDiagnostics.IndexOf(";outcome=success;", StringComparison.Ordinal) >= 0) break;
                        // Pending/running with busy=False is not a safe completion.
                        engineMayBeBusy = true;
                        throw new Exception("Asynchronous export returned a nonterminal or unexpected idle outcome; preserving owned documents; diagnostics=" + lastDiagnostics);
                    }
                    if (completionWait.ElapsedMilliseconds >= 120000)
                        throw new Exception("Engine completion timed out after " + completionWait.ElapsedMilliseconds +
                            "ms while busy; source=" + sourceIdentity + ";startupFixture=" + startupPath +
                            ";documents will remain open; diagnostics=" + lastDiagnostics);
                    System.Threading.Thread.Sleep(25);
                    lastDiagnostics = (string)addin.Object.GetDiagnostics();
                    if (!String.Equals(lastDiagnostics, previousDiagnostics, StringComparison.Ordinal))
                    {
                        Console.WriteLine("ENGINE_STATE " + name + ";wait_ms=" + completionWait.ElapsedMilliseconds + ";" + lastDiagnostics);
                        previousDiagnostics = lastDiagnostics;
                    }
                }
                Console.WriteLine("ENGINE_COMPLETED " + name + ";wait_ms=" + completionWait.ElapsedMilliseconds);
                // Office may restore its previous window after the context-menu
                // dispatch returns. The add-in queues final activation, so observe
                // completion without activating any workbook from this harness.
                var activationWait = System.Diagnostics.Stopwatch.StartNew();
                dynamic candidate = null;
                string lastActive = "none";
                string sourceName = (string)book.Name;
                do
                {
                    lastDiagnostics = (string)addin.Object.GetDiagnostics();
                    bool completed = lastDiagnostics.IndexOf(";busy=False", StringComparison.Ordinal) >= 0
                        && lastDiagnostics.IndexOf(";outcome=success;", StringComparison.Ordinal) >= 0;
                    if (lastDiagnostics.IndexOf(";busy=False", StringComparison.Ordinal) < 0)
                    {
                        engineMayBeBusy = true;
                        throw new Exception("Engine no longer reports idle during activation verification; preserving owned documents; diagnostics=" + lastDiagnostics);
                    }
                    if (!completed)
                        throw new Exception("Export lost its successful outcome during activation verification; diagnostics=" + lastDiagnostics);
                    object probe = application.ActiveWorkbook;
                    try
                    {
                        if (probe != null)
                        {
                            dynamic active = probe;
                            string activeName = (string)active.Name;
                            string activeFullName = (string)active.FullName;
                            bool unsaved = String.IsNullOrEmpty((string)active.Path);
                            lastActive = activeName + ";unsaved=" + unsaved;
                            bool newOutput = unsaved
                                && !String.Equals(activeName, sourceName, StringComparison.OrdinalIgnoreCase)
                                && !String.Equals(activeFullName, startupPath, StringComparison.OrdinalIgnoreCase);
                            if (completed && newOutput)
                            {
                                candidate = probe; probe = null;
                                break;
                            }
                        }
                    }
                    finally { ReleaseOne(probe); }
                    if (activationWait.ElapsedMilliseconds >= 3000) break;
                    System.Threading.Thread.Sleep(25);
                } while (activationWait.ElapsedMilliseconds < 3000);
                if (candidate == null)
                    throw new Exception("Timed out after " + activationWait.ElapsedMilliseconds +
                        "ms waiting for callback busy=False/outcome=success and a new unsaved active output; lastActive=" +
                        lastActive + ";diagnostics=" + lastDiagnostics + ". Harness will not activate or close an unowned candidate.");
                Console.WriteLine("OUTPUT_ACTIVATED " + name + ";wait_ms=" + activationWait.ElapsedMilliseconds + ";" + lastDiagnostics);
                Check((int)application.Workbooks.Count == before + 1, name + ": exactly one output");
                if (String.Equals((string)candidate.Name, (string)book.Name, StringComparison.OrdinalIgnoreCase)
                    || String.Equals((string)candidate.FullName, startupPath, StringComparison.OrdinalIgnoreCase)
                    || !String.IsNullOrEmpty((string)candidate.Path))
                    throw new Exception("Output is not a new unsaved workbook; harness will not close it.");
                output = candidate;
                dynamic destination = candidate.Worksheets[1];
                AssertOutput(candidate, destination, expected, name);
                if (name == "manualcached")
                {
                    CheckValue(3.0, destination.Cells[1, 1].Value2, "manualcached: changed input value exported");
                    CheckValue(2.0, destination.Cells[1, 2].Value2, "manualcached: existing cached result exported without recalculation");
                    CheckValue("=A1*2", sheet.Range["B1"].Formula, "manualcached: source formula retained");
                    CheckValue(2.0, sheet.Range["B1"].Value2, "manualcached: source cached result unchanged");
                    Check((int)application.Calculation == -4135, "manualcached: calculation mode remains manual during export");
                }
                CheckValue(book.Date1904, candidate.Date1904, name + ": date system");
                Check(sourceBefore == Snapshot(fixture), name + ": source data, formulas, styles, hidden states, filters and Saved unchanged");
                Check(globals == GlobalSnapshot(), name + ": Excel global states and StatusBar type restored");
                AssertDimensions(sheet, range, destination, fixture.Rows, fixture.Columns, name);
                if (fixture.CompareDisplay) AssertDisplayedFormats(range, destination, fixture.Rows, fixture.Columns, name);
                if (fixture.ExpectedMerge != null)
                {
                    Check((bool)destination.Cells[1, 1].MergeCells, name + ": result merge present");
                    CheckValue(fixture.ExpectedMerge, destination.Cells[1, 1].MergeArea.Address, name + ": mapped merge coordinates");
                }
                else
                {
                    object merged = destination.Range[destination.Cells[1, 1], destination.Cells[expected.GetLength(0), expected.GetLength(1)]].MergeCells;
                    Check(merged != null && !Convert.ToBoolean(merged, CultureInfo.InvariantCulture), name + ": no unexpected merge");
                }
                passedCases++;
                Console.WriteLine("PASS_CASE " + name + ";elapsed_ms=" + elapsed.ElapsedMilliseconds);
            }
            finally
            {
                try
                {
                    if (engineMayBeBusy)
                    {
                        Console.Error.WriteLine("PRESERVED_ACTIVE_ENGINE source=" + sourceIdentity +
                            ";startupFixture=" + startupPath +
                            ";close=skipped;activate=skipped;calculationRestore=skipped;originalCalculation=" + originalCalculation);
                        // Release only the harness references. Do not close a
                        // document, activate another window, or alter calculation
                        // while the add-in may still be using its own COM roots.
                        ReleaseOne(output); output = null;
                        ClearFixtureReferences(fixture); fixture = null;
                    }
                    else
                    {
                        // Close only exact synthetic objects, never startup fixture or saved files.
                        try
                        {
                            if (output != null) CloseOwned(output, "output");
                        }
                        finally
                        {
                            ReleaseOne(output); output = null;
                            try
                            {
                                if (fixture != null) CloseOwned(fixture.Book, "synthetic source");
                            }
                            finally
                            {
                                ClearFixtureReferences(fixture); fixture = null;
                                if (startupFixture != null) startupFixture.Activate();
                            }
                        }
                    }
                }
                finally
                {
                    // Restore after completed or pre-dispatch failures. Close the
                    // synthetic formula source before restoring automatic calculation.
                    // A possibly active asynchronous job retains its existing mode.
                    if (restoreCalculation && !engineMayBeBusy)
                    {
                        application.Calculation = originalCalculation;
                        Check((int)application.Calculation == originalCalculation, "manualcached: original calculation mode restored by harness");
                        Console.WriteLine("CALCULATION_RESTORED manualcached;mode=" + originalCalculation);
                    }
                }
            }
        }

        private static Fixture CreateFixture(string name)
        {
            dynamic book = application.Workbooks.Add(-4167);
            var fixture = new Fixture { Book = book };
            try
            {
                dynamic sheet = book.Worksheets[1];
                fixture.Sheet = sheet;
                sheet.Name = "SyntheticSource";
                dynamic decoy = book.Worksheets.Add(Type.Missing, sheet, 1, -4167);
                decoy.Name = "SyntheticHiddenOtherSheet";
                decoy.Cells[1, 1].Value2 = "must never enter exported workbook";
                decoy.Visible = 0;
                sheet.Activate();
                sheet.Range["Z1"].Value2 = "outside-selection sentinel";
                switch (name)
                {
                    case "structure":
                        fixture.FullXmlSnapshot = true;
                        var values = new object[100, 4];
                        values[0, 0] = "ID"; values[0, 1] = "Value"; values[0, 2] = "Filter";
                        for (int row = 2; row <= 100; row++)
                        {
                            values[row - 1, 0] = row == 4 ? null : (object)row;
                            values[row - 1, 1] = row == 4 || row % 3 == 0 ? null : "row-" + row;
                            values[row - 1, 2] = row;
                        }
                        sheet.Range["A1:D100"].Value2 = values;
                        sheet.Range["A1:D100"].AutoFilter(3, "<=20", Type.Missing, Type.Missing, Type.Missing);
                        sheet.Rows[5].Hidden = true; sheet.Rows[10].Hidden = true; sheet.Columns[3].Hidden = true;
                        fixture.Range = sheet.Range["A1:D100"];
                        var visible = new List<int>();
                        for (int row = 1; row <= 100; row++) if (!(bool)sheet.Rows[row].Hidden) visible.Add(row);
                        Check(visible.Count == 18, "structure fixture has exactly 18 visible rows");
                        fixture.Rows = visible.ToArray(); fixture.Columns = new[] { 1, 2, 4 };
                        break;
                    case "types":
                        string[] literals = { "001234", "=1+1", "+123", "-123", "@name", "'leading", "'", "#N/A", "  앞뒤 공백  ", "한글\nsecond line" };
                        for (int i = 0; i < literals.Length; i++)
                        {
                            sheet.Cells[i + 1, 1].Value2 = "literal-" + (i + 1);
                            SetLiteral(sheet.Cells[i + 1, 2], literals[i]);
                        }
                        sheet.Cells[11, 1].Value2 = "zero number format";
                        sheet.Cells[11, 2].Value2 = 123; sheet.Cells[11, 2].NumberFormat = "000000";
                        sheet.Cells[12, 2].Value2 = 0.125; sheet.Cells[12, 2].NumberFormat = "0.0%";
                        sheet.Cells[13, 2].Value2 = 1234.5; sheet.Cells[13, 2].NumberFormat = "$#,##0.00";
                        sheet.Cells[14, 2].Value2 = true;
                        sheet.Cells[15, 2].Formula = "=2+3";
                        sheet.Cells[16, 2].Formula = "=NA()";
                        sheet.Cells[17, 2].Formula = "=1/0";
                        sheet.Cells[18, 2].Formula = "=\"\"";
                        sheet.Calculate();
                        fixture.Range = sheet.Range["A1:B18"]; fixture.CompareDisplay = true;
                        AddExcludedMetadata(book, sheet, sheet.Range["A1"]);
                        break;
                    case "dates1900":
                    case "dates1904":
                        book.Date1904 = name == "dates1904";
                        sheet.Range["B2:C3"].Value2 = new object[,] { { 44562.5, 0.25 }, { 123.456, 0.5 } };
                        sheet.Range["B2"].NumberFormat = "yyyy-mm-dd hh:mm";
                        sheet.Range["C2"].NumberFormat = "hh:mm:ss";
                        sheet.Range["B3"].NumberFormat = "0.000"; sheet.Range["C3"].NumberFormat = "0.00%";
                        fixture.Range = sheet.Range["B2:C3"]; fixture.CompareDisplay = true;
                        break;
                    case "singlecell":
                        SetLiteral(sheet.Range["B3"], "001234");
                        fixture.Range = sheet.Range["B3"];
                        break;
                    case "manualcached":
                        sheet.Range["A1"].Value2 = 1.0;
                        sheet.Range["B1"].Formula = "=A1*2";
                        sheet.Calculate();
                        CheckValue(2.0, sheet.Range["B1"].Value2, "manualcached fixture starts with calculated result 2");
                        application.Calculation = -4135; // xlCalculationManual, restored in RunCase finally.
                        sheet.Range["A1"].Value2 = 3.0;
                        CheckValue(3.0, sheet.Range["A1"].Value2, "manualcached fixture input changed to 3");
                        CheckValue(2.0, sheet.Range["B1"].Value2, "manualcached fixture retains stale cached result 2");
                        Check((int)application.Calculation == -4135, "manualcached fixture uses manual calculation");
                        Console.WriteLine("MANUAL_CACHED_STATE CalculationState=" + application.CalculationState + ";expectedInput=3;expectedCached=2");
                        fixture.Range = sheet.Range["A1:B1"];
                        break;
                    case "formatting":
                        sheet.Range["B2:C3"].Value2 = new object[,] { { "첫째\nsecond", 42.125 }, { "정렬", 0.25 } };
                        dynamic formatted = sheet.Range["B2:C3"];
                        // Arial plus Korean text may become mixed-font content in
                        // Excel. This positive case requires an actually uniform
                        // Korean-capable font; mixed-font rejection is a separate limit.
                        formatted.Font.Name = "맑은 고딕"; formatted.Font.Size = 13;
                        formatted.Font.Bold = true; formatted.Font.Italic = true; formatted.Font.Color = 0x553311;
                        formatted.Interior.Color = 0xDDEEFF; formatted.HorizontalAlignment = -4108;
                        formatted.VerticalAlignment = -4160; formatted.WrapText = true;
                        foreach (int index in Edges)
                        {
                            formatted.Borders[index].LineStyle = 1;
                            formatted.Borders[index].Weight = 2;
                            formatted.Borders[index].Color = 0x224466;
                        }
                        sheet.Range["C2"].NumberFormat = "0.000"; sheet.Range["C3"].NumberFormat = "0%";
                        sheet.Range["B3"].Font.Superscript = true;
                        sheet.Range["C3"].Font.Subscript = true;
                        Check((bool)sheet.Range["B3"].Font.Superscript && (bool)sheet.Range["C3"].Font.Subscript,
                            "formatting fixture has whole-cell superscript and subscript");
                        for (int formatRow = 1; formatRow <= 2; formatRow++)
                            for (int formatColumn = 1; formatColumn <= 2; formatColumn++)
                            {
                                dynamic formatCell = formatted.Cells[formatRow, formatColumn];
                                object baseName = formatCell.Font.Name;
                                object displayedName = formatCell.DisplayFormat.Font.Name;
                                Check(baseName is string && !String.IsNullOrWhiteSpace((string)baseName)
                                    && displayedName is string && !String.IsNullOrWhiteSpace((string)displayedName),
                                    "FIXTURE_PRECONDITION formatting requires concrete base/display font names at " +
                                    formatCell.Address + ";base=" + Represent(baseName) + ";display=" + Represent(displayedName));
                            }
                        sheet.Columns[2].ColumnWidth = 18.5; sheet.Columns[3].ColumnWidth = 29.25;
                        sheet.Rows[2].RowHeight = 33; sheet.Rows[3].RowHeight = 41.25;
                        fixture.Range = formatted; fixture.CompareDisplay = true;
                        book.Saved = true; // A clean synthetic original must remain clean.
                        break;
                    case "mergefull":
                        sheet.Range["B2"].Value2 = "전체 병합"; sheet.Range["B2:C3"].Merge(false);
                        sheet.Range["D2"].Value2 = 42;
                        sheet.Range["B4:D4"].Value2 = new object[,] { { "아래", null, 7 } };
                        fixture.Range = sheet.Range["B2:D4"]; fixture.ExpectedMerge = "$A$1:$B$2";
                        break;
                    case "dynamicarray":
                        sheet.Range["B2"].Formula2 = "=SEQUENCE(2,3,10,2)"; sheet.Calculate();
                        Check(Convert.ToDouble(sheet.Range["D3"].Value2, CultureInfo.InvariantCulture) == 20, "dynamic-array fixture spills 2x3");
                        fixture.Range = sheet.Range["B2:D3"];
                        break;
                    case "table":
                        sheet.Range["A1:C5"].Value2 = new object[,] { { "ID", "Text", "Amount" }, { 1, "a", 10 }, { 2, null, 20 }, { 3, "c", 30 }, { 4, "d", 40 } };
                        dynamic table = sheet.ListObjects.Add(1, sheet.Range["A1:C5"], Type.Missing, 1, Type.Missing);
                        table.ShowTotals = true; table.ListColumns[3].TotalsCalculation = 1; sheet.Calculate();
                        fixture.Range = table.Range; fixture.CompareDisplay = true;
                        break;
                    case "conditionalformat":
                        sheet.Range["A1:B4"].Value2 = new object[,] { { "one", 1 }, { "two", 2 }, { "three", 3 }, { "four", 4 } };
                        dynamic rule = sheet.Range["B1:B4"].FormatConditions.Add(1, 5, "2");
                        rule.Interior.Color = 0x0033FF; rule.Font.Color = 0xFFFFFF; rule.Font.Bold = true;
                        fixture.Range = sheet.Range["A1:B4"]; fixture.CompareDisplay = true;
                        break;
                    default: throw new ArgumentException(name);
                }
                dynamic selected = fixture.Range;
                if (fixture.Rows == null) fixture.Rows = Sequence((int)selected.Rows.Count);
                if (fixture.Columns == null) fixture.Columns = Sequence((int)selected.Columns.Count);
                return fixture;
            }
            catch
            {
                try { CloseOwned(book, "incomplete synthetic source"); }
                finally { ClearFixtureReferences(fixture); }
                throw;
            }
        }

        private static void AddExcludedMetadata(dynamic book, dynamic sheet, dynamic anchor)
        {
            anchor.AddComment("Synthetic note: must not export");
            sheet.Hyperlinks.Add(anchor, "https://example.invalid/never-fetch", Type.Missing, "Synthetic link", "literal-1");
            book.Names.Add("ESE_Synthetic_Name", "='SyntheticSource'!$A$1");
            sheet.Range["A18"].Validation.Add(1, 1, 1, "1", "100");
        }

        private static void SetLiteral(dynamic cell, string value)
        {
            cell.NumberFormat = "@"; cell.Value2 = value;
            if (!String.Equals((string)cell.Value2, value, StringComparison.Ordinal)) cell.Value2 = "'" + value;
            CheckValue(value, cell.Value2, "Synthetic literal prepared exactly");
            Check(!(bool)cell.HasFormula, "Synthetic literal is not a formula");
        }

        private static object[,] ProjectValues(dynamic range, int[] rows, int[] columns)
        {
            object raw = range.Value2;
            Array array = raw as Array;
            var values = new object[rows.Length, columns.Length];
            for (int row = 0; row < rows.Length; row++)
                for (int column = 0; column < columns.Length; column++)
                    values[row, column] = array == null ? raw : array.GetValue(rows[row] - 1 + array.GetLowerBound(0), columns[column] - 1 + array.GetLowerBound(1));
            return values;
        }

        private static void AssertOutput(dynamic book, dynamic sheet, object[,] expected, string name)
        {
            Check(String.IsNullOrEmpty((string)book.Path) && !(bool)book.Saved, name + ": output awaits user save");
            Check((int)book.Sheets.Count == 1 && (int)book.Worksheets.Count == 1, name + ": one worksheet only");
            Check(!(bool)book.HasVBProject, name + ": no VBA");
            Check((int)book.Names.Count == 0, name + ": no names");
            Check((int)book.Connections.Count == 0, name + ": no connections");
            Check(book.LinkSources(1) == null && book.LinkSources(2) == null, name + ": no Excel/OLE links");
            Check((int)sheet.Comments.Count == 0, name + ": no comments");
            Check((int)sheet.Hyperlinks.Count == 0, name + ": no hyperlinks");
            Check((int)sheet.ListObjects.Count == 0, name + ": no automatic table");
            Check((int)sheet.Shapes.Count == 0, name + ": no shapes");
            Check((int)sheet.UsedRange.FormatConditions.Count == 0, name + ": no conditional-format rules");
            dynamic used = sheet.UsedRange;
            Check((int)used.Row == 1 && (int)used.Column == 1 && (int)used.Rows.Count <= expected.GetLength(0) && (int)used.Columns.Count <= expected.GetLength(1), name + ": expected output bounds; actual=" + used.Address + ";expectedRows=" + expected.GetLength(0) + ";expectedColumns=" + expected.GetLength(1));
            for (int row = 0; row < expected.GetLength(0); row++)
                for (int column = 0; column < expected.GetLength(1); column++)
                {
                    dynamic cell = sheet.Cells[row + 1, column + 1];
                    CheckValue(expected[row, column], cell.Value2, name + ": value " + (row + 1) + "," + (column + 1));
                    Check(!(bool)cell.HasFormula, name + ": formula absent");
                    Check(!HasValidation(cell), name + ": validation absent");
                }
        }

        private static bool HasValidation(dynamic cell)
        {
            try { object type = cell.Validation.Type; return type != null; }
            catch (COMException exception)
            {
                if (exception.ErrorCode == unchecked((int)0x800A03EC)) return false;
                throw;
            }
        }

        private static void AssertDimensions(dynamic sourceSheet, dynamic selected, dynamic output, int[] rows, int[] columns, string name)
        {
            int sourceRow = (int)selected.Row, sourceColumn = (int)selected.Column;
            for (int i = 0; i < rows.Length; i++)
            {
                CheckNear(sourceSheet.Rows[sourceRow + rows[i] - 1].RowHeight, output.Rows[i + 1].RowHeight, name + ": row height");
                Check(!(bool)output.Rows[i + 1].Hidden, name + ": visible row");
            }
            for (int i = 0; i < columns.Length; i++)
            {
                CheckNear(sourceSheet.Columns[sourceColumn + columns[i] - 1].ColumnWidth, output.Columns[i + 1].ColumnWidth, name + ": column width");
                Check(!(bool)output.Columns[i + 1].Hidden, name + ": visible column");
            }
        }

        private static void AssertDisplayedFormats(dynamic selected, dynamic output, int[] rows, int[] columns, string name)
        {
            for (int row = 0; row < rows.Length; row++)
                for (int column = 0; column < columns.Length; column++)
                {
                    dynamic sourceCell = selected.Cells[rows[row], columns[column]];
                    dynamic targetCell = output.Cells[row + 1, column + 1];
                    CheckValue(Style(sourceCell.DisplayFormat), Style(targetCell), name + ": static displayed format " + (row + 1) + "," + (column + 1));
                }
        }

        private static string Snapshot(Fixture fixture)
        {
            dynamic book = fixture.Book, sheet = fixture.Sheet, range = fixture.Range;
            var text = new StringBuilder();
            Append(text, book.Saved); Append(text, book.Date1904); Append(text, book.Sheets.Count);
            Append(text, book.Names.Count); Append(text, book.Connections.Count);
            Append(text, sheet.Range["Z1"].Value2); Append(text, sheet.AutoFilterMode); Append(text, sheet.FilterMode);
            Append(text, range.Value2); Append(text, range.Formula);
            Append(text, sheet.Comments.Count); Append(text, sheet.Hyperlinks.Count);
            if (fixture.FullXmlSnapshot)
            {
                // xlRangeValueXMLSpreadsheet includes values, formats, formulas
                // and names in one COM read. Compare the complete XML verbatim:
                // do not discard mixed styles, inside borders or diagonal borders.
                object xml = range.Value[11];
                Check(xml is string && !String.IsNullOrEmpty((string)xml), "Source returns a complete XML Spreadsheet snapshot");
                Append(text, xml);
            }
            int firstRow = (int)range.Row, firstColumn = (int)range.Column;
            for (int row = 1; row <= (int)range.Rows.Count; row++)
            {
                Append(text, sheet.Rows[firstRow + row - 1].Hidden);
                Append(text, sheet.Rows[firstRow + row - 1].RowHeight);
                for (int column = 1; !fixture.FullXmlSnapshot && column <= (int)range.Columns.Count; column++)
                {
                    dynamic cell = range.Cells[row, column];
                    Append(text, Style(cell)); Append(text, cell.MergeCells);
                    if ((bool)cell.MergeCells) Append(text, cell.MergeArea.Address);
                }
            }
            for (int column = 1; column <= (int)range.Columns.Count; column++)
            {
                Append(text, sheet.Columns[firstColumn + column - 1].Hidden);
                Append(text, sheet.Columns[firstColumn + column - 1].ColumnWidth);
            }
            if ((bool)sheet.AutoFilterMode)
            {
                dynamic filters = sheet.AutoFilter.Filters;
                Append(text, filters.Count);
                for (int i = 1; i <= (int)filters.Count; i++)
                {
                    dynamic filter = filters[i]; Append(text, filter.On);
                    if ((bool)filter.On)
                    {
                        Append(text, filter.Operator); Append(text, filter.Criteria1);
                        try { Append(text, filter.Criteria2); } catch (COMException) { Append(text, "no Criteria2"); }
                    }
                }
            }
            return text.ToString();
        }

        private static string GlobalSnapshot()
        {
            var text = new StringBuilder();
            Append(text, application.ScreenUpdating); Append(text, application.EnableEvents); Append(text, application.Interactive);
            Append(text, application.DisplayAlerts); Append(text, application.Calculation); Append(text, application.StatusBar);
            return text.ToString();
        }

        private static string Style(dynamic cell)
        {
            var text = new StringBuilder();
            Append(text, cell.NumberFormatLocal); Append(text, cell.Font.Name); Append(text, cell.Font.Size);
            Append(text, cell.Font.Bold); Append(text, cell.Font.Italic); Append(text, cell.Font.Color);
            Append(text, cell.Font.Superscript); Append(text, cell.Font.Subscript);
            Append(text, cell.Interior.Color); Append(text, cell.Interior.Pattern);
            Append(text, cell.HorizontalAlignment); Append(text, cell.VerticalAlignment); Append(text, cell.WrapText);
            foreach (int index in Edges)
            {
                dynamic border = cell.Borders[index];
                object line = border.LineStyle; Append(text, line);
                if (Convert.ToInt32(line, CultureInfo.InvariantCulture) != -4142)
                {
                    Append(text, border.Weight); Append(text, border.Color);
                }
            }
            return text.ToString();
        }

        private static void Append(StringBuilder text, object value)
        {
            string representation = Represent(value);
            text.Append(representation.Length).Append(':').Append(representation).Append(';');
        }

        private static string Represent(object value)
        {
            if (value == null) return "null";
            var error = value as ErrorWrapper;
            if (error != null) return "error:" + error.ErrorCode;
            var array = value as Array;
            if (array != null)
            {
                var text = new StringBuilder("array:");
                text.Append(array.Rank).Append(':');
                for (int i = 0; i < array.Rank; i++) text.Append(array.GetLength(i)).Append(',');
                foreach (object item in array) Append(text, item);
                return text.ToString();
            }
            if (value is double) return "double:" + ((double)value).ToString("R", CultureInfo.InvariantCulture);
            if (value is float) return "float:" + ((float)value).ToString("R", CultureInfo.InvariantCulture);
            return value.GetType().FullName + ":" + Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        private static int[] Sequence(int count)
        {
            var values = new int[count];
            for (int i = 0; i < count; i++) values[i] = i + 1;
            return values;
        }

        private static void CloseOwned(dynamic book, string role)
        {
            if (book == null) return;
            if (!String.IsNullOrEmpty((string)book.Path) || String.Equals((string)book.FullName, startupPath, StringComparison.OrdinalIgnoreCase))
                throw new Exception("Refusing to close " + role + ": ownership or unsaved-state check failed.");
            book.Close(false);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ClearFixtureReferences(Fixture fixture)
        {
            if (fixture == null) return;
            object range = fixture.Range, sheet = fixture.Sheet, book = fixture.Book;
            fixture.Range = null; fixture.Sheet = null; fixture.Book = null;
            ReleaseOne(range); ReleaseOne(sheet); ReleaseOne(book);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ClearConnectionRoots()
        {
            object fixture = startupFixture, app = application, window = attachmentWindow;
            startupFixture = null; application = null; attachmentWindow = null; startupPath = null;
            // Each is an acquired reference. Never FinalRelease a potentially shared
            // application RCW and never close or Quit the preserved startup instance.
            ReleaseOne(fixture); ReleaseOne(app); ReleaseOne(window);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ReleaseOne(object value)
        {
            if (value == null || !Marshal.IsComObject(value)) return;
            try { Marshal.ReleaseComObject(value); }
            catch (InvalidComObjectException) { }
        }

        private static void CheckValue(object expected, object actual, string label)
        {
            string left = Represent(expected), right = Represent(actual);
            if (left != right) throw new Exception(label + "; expected=" + left + "; actual=" + right);
            checks++;
        }

        private static void CheckNear(object expected, object actual, string label)
        {
            double left = Convert.ToDouble(expected, CultureInfo.InvariantCulture);
            double right = Convert.ToDouble(actual, CultureInfo.InvariantCulture);
            Check(Math.Abs(left - right) <= 0.05, label);
        }

        private static void Check(bool condition, string label)
        {
            if (!condition) throw new Exception(label);
            checks++;
        }
    }
}
