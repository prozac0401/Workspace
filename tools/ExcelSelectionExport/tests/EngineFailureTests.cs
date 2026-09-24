// Direct engine API integration only. Load an explicitly supplied shipping DLL,
// attach only to an existing owned fixture PID, and create disposable sources.
// This is neither a Ribbon callback test nor an installation/auto-load test.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace ExcelSelectionExport.IntegrationTests
{
    internal static class EngineFailureTests
    {
        private delegate bool EnumProc(IntPtr window, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr window, EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int maximum);
        [DllImport("oleacc.dll")] private static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId, ref Guid iid, [MarshalAs(UnmanagedType.IDispatch)] out object result);

        private static dynamic application, startupFixture;
        private static object attachmentWindow;
        private static string startupPath;
        private static MethodInfo runEngine;
        private static int checks, passedCases, notRunCases;
        private static readonly string[] Cases =
        {
            "partialmerge", "hiddencutmerge", "ctrlunion", "wholerow", "wholecol",
            "multisheet", "zerovisible", "inputlimit", "visiblelimit", "stringlimit"
        };

        private sealed class Fixture
        {
            internal object Book, Sheet, Selection, Inspection, ExtraSheet;
            internal string ExpectedReason;
            internal bool LongLiteralStrings;
        }

        private sealed class FixtureUnavailableException : Exception
        {
            internal FixtureUnavailableException(string reason) : base(reason) { }
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
                    // Release DLR property-chain temporaries after Run's stack frame
                    // has left; never rely on process exit for Excel COM rundown.
                    GC.Collect(); GC.WaitForPendingFinalizers();
                    GC.Collect(); GC.WaitForPendingFinalizers();
                }
            }
            return result;
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static int Run(string[] args)
        {
            try
            {
                if (args.Length < 2 || args.Length > 3)
                    throw new ArgumentException("Usage: EngineFailureTests.exe <owned-fixture.xlsx.pid> <shipping-AddIn.dll> [all|" + String.Join("|", Cases) + "]");
                string marker = Path.GetFullPath(args[0]);
                if (!marker.EndsWith(".xlsx.pid", StringComparison.OrdinalIgnoreCase))
                    throw new ArgumentException("The exact .xlsx.pid marker created by ExcelProbe is required.");
                startupPath = marker.Substring(0, marker.Length - 4);
                if (!File.Exists(startupPath)) throw new Exception("Owned startup fixture is missing.");
                int pid;
                if (!Int32.TryParse(File.ReadAllText(marker).Trim(), out pid) || pid <= 0) throw new Exception("Invalid PID marker.");
                string dll = Path.GetFullPath(args[1]);
                if (!String.Equals(Path.GetFileName(dll), "ExcelSelectionExport.AddIn.dll", StringComparison.OrdinalIgnoreCase) || !File.Exists(dll))
                    throw new ArgumentException("Supply the exact existing shipping ExcelSelectionExport.AddIn.dll.");
                string selected = args.Length == 3 ? args[2] : "all";
                if (selected != "all" && Array.IndexOf(Cases, selected) < 0) throw new ArgumentException("Unknown case: " + selected);
                Assembly payload = Assembly.LoadFrom(dll);
                Type engine = payload.GetType("ExcelSelectionExport.ExportEngine", true, false);
                runEngine = engine.GetMethod("Run", BindingFlags.Public | BindingFlags.Static, null, new[] { typeof(object) }, null);
                if (runEngine == null || runEngine.ReturnType != typeof(void)) throw new Exception("Expected public static ExportEngine.Run(object) entry point.");

                application = Attach(pid);
                uint attachedPid;
                GetWindowThreadProcessId(new IntPtr((int)application.Hwnd), out attachedPid);
                if (attachedPid != pid) throw new Exception("Attached process differs from the owned PID.");
                if ((int)application.Workbooks.Count != 1)
                    throw new Exception("Refusing to run: owned process must contain only its startup fixture.");
                startupFixture = application.Workbooks[1];
                if (!String.Equals((string)startupFixture.FullName, startupPath, StringComparison.OrdinalIgnoreCase))
                    throw new Exception("Refusing to run: startup workbook does not match the PID marker.");
                Check((bool)application.EnableEvents && (bool)application.Interactive, "Owned Excel starts with events and interaction enabled");
                string startupBefore = StartupSnapshot();
                string initialGlobals = GlobalSnapshot();
                Console.WriteLine("MODE=DIRECT_ENGINE_API_INTEGRATION; no actual Ribbon callback; no installed add-in override");
                Console.WriteLine("PAYLOAD=" + dll + ";SHA256=" + FileHash(dll) + ";Assembly=" + payload.FullName);
                Console.WriteLine("Excel=" + application.Version + ";Build=" + application.Build + ";PID=" + pid);
                foreach (string name in Cases)
                {
                    if (selected != "all" && selected != name) continue;
                    try { RunCase(name); }
                    catch (FixtureUnavailableException unavailable)
                    {
                        // This is a known limitation of preparing a real Excel
                        // selection, not a passed product rejection or a generic
                        // exception exemption. Other failures still terminate.
                        notRunCases++;
                        Console.WriteLine("NOT_RUN_CASE " + name + ";reason=" + unavailable.Message);
                    }
                }
                startupFixture.Activate();
                Check((int)application.Workbooks.Count == 1, "Only owned startup fixture remains");
                Check(startupBefore == StartupSnapshot(), "Preserved startup fixture state unchanged");
                Check(initialGlobals == GlobalSnapshot(), "Global state unchanged across all cases");
                Console.WriteLine("EXECUTED_PASS=" + passedCases + ";NOT_RUN=" + notRunCases + ";assertions=" + checks);
                Console.WriteLine(notRunCases == 0
                    ? "PASS all requested direct engine rejection cases executed"
                    : "PARTIAL requested rejection coverage; exit 0 means executed cases passed, not full acceptance");
                Console.WriteLine("NOT_RUN actual failure-message UI, cancellation, policy/protected view, rollback after output creation, clipboard, undo, isolated profile, reboot, x86 host");
                return 0;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine("FAIL " + error);
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

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void RunCase(string name)
        {
            Fixture fixture = null;
            var timer = System.Diagnostics.Stopwatch.StartNew();
            Console.WriteLine("BEGIN " + name);
            try
            {
                fixture = CreateFixture(name);
                string sourceBefore = SourceSnapshot(fixture);
                string globalsBefore = GlobalSnapshot();
                string selectionBefore = SelectionSnapshot();
                int booksBefore = (int)application.Workbooks.Count;
                Exception failure = null;
                try
                {
                    Console.WriteLine("ENGINE_BEGIN " + name);
                    runEngine.Invoke(null, new object[] { (object)application });
                }
                catch (TargetInvocationException invocation)
                {
                    failure = invocation.InnerException;
                }
                Console.WriteLine("ENGINE_END " + name + ";failure=" + (failure == null ? "none" : failure.GetType().FullName));
                // A different preflight failure must not pass the intended case.
                Check(failure is InvalidOperationException, name + ": expected InvalidOperationException; actual=" + (failure == null ? "success" : failure.ToString()));
                Check(failure.Message.IndexOf(fixture.ExpectedReason, StringComparison.Ordinal) >= 0,
                    name + ": expected reason=" + fixture.ExpectedReason + "; actual=" + failure.ToString());
                Check((int)application.Workbooks.Count == booksBefore, name + ": no output or other workbook added/removed");
                Check(sourceBefore == SourceSnapshot(fixture), name + ": source data, formulas, styles, merge, hidden, filter and Saved state unchanged");
                Check(globalsBefore == GlobalSnapshot(), name + ": Excel global states restored");
                Check(selectionBefore == SelectionSnapshot(), name + ": selection and sheet group unchanged");
                passedCases++;
                Console.WriteLine("PASS_CASE " + name + ";elapsed_ms=" + timer.ElapsedMilliseconds + ";reason=" + failure.Message.Replace("\r", " ").Replace("\n", " "));
            }
            finally
            {
                if (fixture != null)
                {
                    try { CloseOwned(fixture.Book); }
                    finally { ClearFixtureReferences(fixture); fixture = null; }
                }
                if (startupFixture != null) startupFixture.Activate();
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
                sheet.Name = "SyntheticFailureSource";
                sheet.Range["A1:D6"].Value2 = new object[,]
                {
                    { "sentinel", 123.0, true, "001234" },
                    { "row2", null, 2.0, "끝" },
                    { "row3", 3.0, null, " " },
                    { "row4", 4.0, "four", null },
                    { "row5", null, null, null },
                    { "row6", null, null, null }
                };
                sheet.Range["D6"].Formula = "=2+3";
                sheet.Range["A1"].Font.Bold = true;
                sheet.Range["A1"].Interior.Color = 0xDDEEFF;
                sheet.Range["Z1"].Value2 = "outside-selection sentinel";
                sheet.Calculate();
                fixture.Inspection = sheet.Range["A1:D12"];
                switch (name)
                {
                    case "partialmerge":
                        sheet.Range["B2:C3"].ClearContents();
                        sheet.Range["B2"].Value2 = "partial merge sentinel";
                        sheet.Range["B2:C3"].Merge(false);
                        fixture.Selection = sheet.Range["A1:B3"];
                        fixture.ExpectedReason = "일부만 포함";
                        break;
                    case "hiddencutmerge":
                        sheet.Range["B2:C3"].ClearContents();
                        sheet.Range["B2"].Value2 = "hidden merge sentinel";
                        sheet.Range["B2:C3"].Merge(false);
                        sheet.Rows[3].Hidden = true;
                        fixture.Selection = sheet.Range["A1:D4"];
                        fixture.ExpectedReason = "일부 행이나 열이 숨겨져";
                        break;
                    case "ctrlunion":
                        fixture.Selection = sheet.Range["A1:B2,D4:D5"];
                        fixture.ExpectedReason = "떨어진 여러 범위";
                        break;
                    case "wholerow":
                        fixture.Selection = sheet.Rows[2];
                        fixture.ExpectedReason = "전체 행이나 열 대신";
                        break;
                    case "wholecol":
                        fixture.Selection = sheet.Columns[2];
                        fixture.ExpectedReason = "전체 행이나 열 대신";
                        break;
                    case "multisheet":
                        dynamic extra = book.Worksheets.Add(Type.Missing, sheet, 1, -4167);
                        fixture.ExtraSheet = extra;
                        extra.Name = "SyntheticGroupedSheet";
                        extra.Range["A1"].Value2 = "group sentinel";
                        fixture.Selection = sheet.Range["A1:B3"];
                        fixture.ExpectedReason = "시트를 하나만 선택";
                        break;
                    case "zerovisible":
                        sheet.Rows["1:3"].Hidden = true;
                        fixture.Selection = sheet.Range["A1:B3"];
                        fixture.ExpectedReason = "보이는 행이 없습니다";
                        break;
                    case "inputlimit":
                        fixture.Selection = sheet.Range[sheet.Cells[1, 1], sheet.Cells[1001, 1000]];
                        fixture.ExpectedReason = "1,000,000";
                        break;
                    case "visiblelimit":
                        // 317 * 316 = 100,172: exceed the output limit with only
                        // 633 row/column visibility checks and stay below the input limit.
                        fixture.Selection = sheet.Range[sheet.Cells[1, 1], sheet.Cells[317, 316]];
                        fixture.ExpectedReason = "100,000";
                        break;
                    case "stringlimit":
                        fixture.LongLiteralStrings = true;
                        // 306 * 32,767 = 10,026,702, below the warning's 20,000-cell
                        // threshold. No large-warning dialog is needed to reach rejection.
                        var strings = new object[306, 1];
                        string text = new String('가', 32767);
                        for (int i = 0; i < strings.GetLength(0); i++) strings[i, 0] = text;
                        sheet.Range["A1:A306"].NumberFormat = "@";
                        sheet.Range["A1:A306"].Value2 = strings;
                        fixture.Selection = sheet.Range["A1:A306"];
                        ReleaseOne(fixture.Inspection);
                        fixture.Inspection = sheet.Range["A1:D306"];
                        Check(((string)sheet.Range["A1"].Value2).Length == 32767
                            && ((string)sheet.Range["A306"].Value2).Length == 32767, "stringlimit: Excel retained 32,767 characters per cell");
                        fixture.ExpectedReason = "10,000,000";
                        break;
                    default: throw new ArgumentException(name);
                }
                book.Activate(); sheet.Activate();
                ((dynamic)fixture.Selection).Select();
                if (name == "multisheet")
                {
                    ((dynamic)fixture.ExtraSheet).Select(false);
                    Check((int)application.ActiveWindow.SelectedSheets.Count == 2, "multisheet: two sheets grouped");
                }
                else Check((int)application.ActiveWindow.SelectedSheets.Count == 1, name + ": one selected sheet");
                if (name == "partialmerge")
                {
                    // Excel may expand an interactive selection around a merge.
                    // That makes the fixture invalid, not the rejection a PASS.
                    if ((int)application.Selection.Column != 1 || (int)application.Selection.Columns.Count != 2)
                        throw new FixtureUnavailableException("Excel expanded the requested A1:B3 selection around the merge; actual=" +
                            (string)application.Selection.Address + ";the partial-merge engine path was not invoked");
                    Check(true, "partialmerge: Excel retained selection ending at column B");
                }
                if (name == "ctrlunion") Check((int)application.Selection.Areas.Count == 2, "ctrlunion: two disjoint areas");
                if (name == "inputlimit") Check(Convert.ToDouble(application.Selection.CountLarge, CultureInfo.InvariantCulture) == 1001000, "inputlimit: 1,001,000 input positions");
                if (name == "visiblelimit") Check(Convert.ToDouble(application.Selection.CountLarge, CultureInfo.InvariantCulture) == 100172, "visiblelimit: 100,172 visible cells");
                book.Saved = true; // A clean synthetic source must remain clean on failure.
                return fixture;
            }
            catch
            {
                try { CloseOwned(book); }
                finally { ClearFixtureReferences(fixture); }
                throw;
            }
        }

        private static string SourceSnapshot(Fixture fixture)
        {
            dynamic book = fixture.Book, sheet = fixture.Sheet, inspection = fixture.Inspection;
            var text = new StringBuilder();
            Append(text, book.FullName); Append(text, book.Saved); Append(text, book.Date1904);
            Append(text, book.Sheets.Count); Append(text, book.Names.Count); Append(text, book.Connections.Count);
            if (fixture.LongLiteralStrings)
            {
                // Verify each long literal with Value2 and HasFormula. Avoid an
                // unnecessary Formula read for this known literal-only column,
                // while still comparing every formula outside that column.
                for (int start = 1; start <= 306; start += 32)
                {
                    dynamic block = sheet.Range["A" + start + ":A" + Math.Min(306, start + 31)];
                    try { Check(block.HasFormula is bool && !(bool)block.HasFormula, "long literal block remains formula-free"); Append(text, block.Value2); }
                    finally { ReleaseOne(block); }
                }
                dynamic remaining = sheet.Range["B1:D306"];
                try { Append(text, remaining.Value2); Append(text, remaining.Formula); }
                finally { ReleaseOne(remaining); }
            }
            else { Append(text, inspection.Value2); Append(text, inspection.Formula); }
            Append(text, sheet.Range["Z1"].Value2); Append(text, sheet.AutoFilterMode); Append(text, sheet.FilterMode);
            Append(text, sheet.Comments.Count); Append(text, sheet.Hyperlinks.Count);
            for (int row = 1; row <= 12; row++)
            {
                Append(text, sheet.Rows[row].Hidden); Append(text, sheet.Rows[row].RowHeight);
                for (int col = 1; col <= 4; col++)
                {
                    dynamic cell = sheet.Cells[row, col];
                    Append(text, cell.NumberFormat); Append(text, cell.Font.Name); Append(text, cell.Font.Size);
                    Append(text, cell.Font.Bold); Append(text, cell.Font.Italic); Append(text, cell.Font.Color);
                    Append(text, cell.Interior.Color); Append(text, cell.HorizontalAlignment);
                    Append(text, cell.VerticalAlignment); Append(text, cell.WrapText); Append(text, cell.MergeCells);
                    if ((bool)cell.MergeCells) Append(text, cell.MergeArea.Address);
                }
            }
            for (int col = 1; col <= 4; col++)
            {
                Append(text, sheet.Columns[col].Hidden); Append(text, sheet.Columns[col].ColumnWidth);
            }
            if (fixture.ExtraSheet != null)
            {
                dynamic extra = fixture.ExtraSheet;
                Append(text, extra.Name); Append(text, extra.Range["A1"].Value2); Append(text, extra.Range["A1"].Formula);
            }
            // Keep diagnostics compact even for the 10M-character fixture.
            return TextHash(text.ToString());
        }

        private static string SelectionSnapshot()
        {
            var text = new StringBuilder();
            Append(text, application.ActiveWorkbook.Name); Append(text, application.ActiveSheet.Name);
            Append(text, application.ActiveWindow.SelectedSheets.Count);
            Append(text, application.Selection.Address); Append(text, application.Selection.Areas.Count);
            return text.ToString();
        }

        private static string GlobalSnapshot()
        {
            var text = new StringBuilder();
            Append(text, application.ScreenUpdating); Append(text, application.EnableEvents); Append(text, application.Interactive);
            Append(text, application.DisplayAlerts); Append(text, application.Calculation); Append(text, application.StatusBar);
            return text.ToString();
        }

        private static string StartupSnapshot()
        {
            var text = new StringBuilder();
            Append(text, startupFixture.FullName); Append(text, startupFixture.Saved);
            Append(text, startupFixture.Sheets.Count); Append(text, startupFixture.Date1904);
            // Only task-owned fixture metadata is inspected; no user workbook reads.
            return text.ToString();
        }

        private static void Append(StringBuilder text, object value)
        {
            if (value == null) { text.Append("null;"); return; }
            Array array = value as Array;
            if (array != null)
            {
                text.Append("array:").Append(array.Rank).Append(':');
                for (int i = 0; i < array.Rank; i++) text.Append(array.GetLength(i)).Append(',');
                foreach (object item in array) Append(text, item);
                return;
            }
            var error = value as ErrorWrapper;
            string representation = error != null ? "error:" + error.ErrorCode
                : value is double ? "double:" + ((double)value).ToString("R", CultureInfo.InvariantCulture)
                : value.GetType().FullName + ":" + Convert.ToString(value, CultureInfo.InvariantCulture);
            text.Append(representation.Length).Append(':').Append(representation).Append(';');
        }

        private static string FileHash(string file)
        {
            using (var hash = SHA256.Create())
            using (var stream = File.OpenRead(file))
                return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
        }

        private static string TextHash(string text)
        {
            using (var hash = SHA256.Create())
                return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-", "").ToLowerInvariant();
        }

        private static void CloseOwned(dynamic book)
        {
            if (book == null) return;
            if (!String.IsNullOrEmpty((string)book.Path) || String.Equals((string)book.FullName, startupPath, StringComparison.OrdinalIgnoreCase))
                throw new Exception("Refusing to close source: ownership or unsaved-state check failed.");
            book.Close(false);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ClearFixtureReferences(Fixture fixture)
        {
            if (fixture == null) return;
            object selected = fixture.Selection, inspection = fixture.Inspection;
            object extra = fixture.ExtraSheet, sheet = fixture.Sheet, book = fixture.Book;
            fixture.Selection = null; fixture.Inspection = null; fixture.ExtraSheet = null; fixture.Sheet = null; fixture.Book = null;
            ReleaseOne(selected); ReleaseOne(inspection); ReleaseOne(extra); ReleaseOne(sheet); ReleaseOne(book);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ClearConnectionRoots()
        {
            object fixture = startupFixture, app = application, window = attachmentWindow;
            startupFixture = null; application = null; attachmentWindow = null; startupPath = null; runEngine = null;
            ReleaseOne(fixture); ReleaseOne(app); ReleaseOne(window);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ReleaseOne(object value)
        {
            if (value == null || !Marshal.IsComObject(value)) return;
            try { Marshal.ReleaseComObject(value); }
            catch (InvalidComObjectException) { }
        }

        private static void Check(bool condition, string label)
        {
            if (!condition) throw new Exception(label);
            checks++;
        }
    }
}
