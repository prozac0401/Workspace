using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace ExcelSelectionExport
{
    // Every Excel call is made on the callback's STA. DTOs never retain a COM object.
    public static class ExportEngine
    {
        public static void Run(object application)
        {
            object resultWindow = RunForMenu(application);
            ExportEngine.Release(resultWindow);
        }

        // The caller owns the returned result-window reference.
        internal static object RunForMenu(object application)
        {
            using (var prepared = PrepareMenu(application)) return prepared.Run();
        }

        internal static PreparedMenuExport PrepareMenu(object application)
        {
            if (application == null) throw new InvalidOperationException("Excel 연결이 끝났습니다. Excel을 다시 시작해 주세요.");
            if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
                throw new InvalidOperationException("Excel 화면에서 내보내기 메뉴를 눌러 주세요.");
            var job = new ExportJob(application);
            try
            {
                // Pin Selection/Workbook/Worksheet and start change guards now;
                // no cell values or new workbook are touched before menu return.
                job.Start();
                return new PreparedMenuExport(job);
            }
            catch
            {
                try { job.Rollback(); }
                finally { job.Dispose(); }
                throw;
            }
        }

        internal sealed class PreparedMenuExport : IDisposable
        {
            ExportJob job;
            internal PreparedMenuExport(ExportJob value) { job = value; }
            internal object Run()
            {
                var current = job;
                if (current == null) throw new InvalidOperationException("이미 끝났거나 취소된 내보내기 요청입니다.");
                job = null;
                object resultWindow = null;
                try
                {
                    using (current)
                    {
                        try
                        {
                            var clock = Stopwatch.StartNew();
                            while (!current.Finished && clock.ElapsedMilliseconds < 700) current.Advance();
                            if (!current.Finished)
                            {
                                using (var progress = new ProgressWindow(current))
                                    progress.ShowDialog(new ExcelWindow(current.WindowHandle));
                            }
                            current.Complete();
                            resultWindow = current.AcquireResultWindow();
                        }
                        catch
                        {
                            current.Rollback();
                            throw;
                        }
                    }
                    return resultWindow;
                }
                catch { ExportEngine.Release(resultWindow); throw; }
            }
            public void Dispose()
            {
                var pending = job; job = null;
                if (pending == null) return;
                pending.Cancel();
                try { pending.Rollback(); }
                finally { pending.Dispose(); }
            }
        }

        sealed class ExcelWindow : IWin32Window
        {
            readonly IntPtr handle;
            public ExcelWindow(IntPtr value) { handle = value; }
            public IntPtr Handle { get { return handle; } }
        }

        sealed class ProgressWindow : Form
        {
            readonly ExportJob job;
            readonly Label status = new Label();
            readonly Button cancel = new Button();
            readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
            bool ending;
            public ProgressWindow(ExportJob value)
            {
                job = value;
                Text = "선택범위 내보내기";
                FormBorderStyle = FormBorderStyle.FixedDialog;
                StartPosition = FormStartPosition.CenterParent;
                MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false;
                ClientSize = new System.Drawing.Size(430, 112);
                status.SetBounds(18, 18, 394, 43);
                cancel.Text = "취소"; cancel.SetBounds(330, 71, 82, 28);
                Controls.Add(status); Controls.Add(cancel);
                CancelButton = cancel;
                cancel.Click += delegate { job.Cancel(); cancel.Enabled = false; status.Text = "작업을 정리하고 있습니다."; };
                FormClosing += delegate(object sender, FormClosingEventArgs e) { if (!ending) { e.Cancel = true; job.Cancel(); } };
                timer.Interval = 15;
                timer.Tick += delegate
                {
                    timer.Stop();
                    job.Advance();
                    status.Text = job.Status;
                    if (job.Finished) { ending = true; Close(); }
                    else timer.Start();
                };
                Shown += delegate { status.Text = job.Status; timer.Start(); };
            }
            protected override void Dispose(bool disposing) { if (disposing) timer.Dispose(); base.Dispose(disposing); }
        }

        internal sealed class ExportJob : IDisposable
        {
            const int MaximumStrings = 10000000;
            readonly object appObject;
            readonly dynamic app;
            readonly List<object> owned = new List<object>();
            readonly List<MergeInfo> merges = new List<MergeInfo>();
            readonly Dictionary<string, bool> mergeKeys = new Dictionary<string, bool>();
            readonly Dictionary<string, CellFormat> formats = new Dictionary<string, CellFormat>(StringComparer.Ordinal);
            readonly List<int> rows = new List<int>();
            readonly List<int> columns = new List<int>();
            dynamic selection, sheet, book, cells, sheetRows, sheetColumns;
            dynamic output, outputSheet, outputCells;
            object outputApplication;
            OutputWorkspace outputWorkspace;
            VisibleRangePlan plan;
            object[,] values;
            CellFormat[,] cellFormats;
            double[] rowHeights, columnWidths, columnPoints;
            string normalFont;
            double normalSize;
            bool normalBold, normalItalic;
            int firstRow, firstColumn, rowCount, columnCount, initialCalculationMode;
            bool date1904, oldInteractive, oldScreenUpdating, oldEvents, changedState, sourcePhase = true;
            bool cancel, finished, successful, unsupportedEffects, hooks;
            string sourceChanged;
            Exception failure;
            IEnumerator<int> work;
            readonly Guid appEvents = new Guid("00024413-0000-0000-C000-000000000046");
            SheetChangeHandler onChange;
            SheetCalculateHandler onCalculate;
            WorkbookCloseHandler onClose;
            internal string Status = "선택 범위를 확인하고 있습니다.";
            internal IntPtr WindowHandle;
            internal bool Finished { get { return finished; } }
            delegate void SheetChangeHandler([MarshalAs(UnmanagedType.IDispatch)] object sh, [MarshalAs(UnmanagedType.IDispatch)] object target);
            delegate void SheetCalculateHandler([MarshalAs(UnmanagedType.IDispatch)] object sh);
            delegate void WorkbookCloseHandler([MarshalAs(UnmanagedType.IDispatch)] object wb, [In, Out] ref bool cancelClose);

            internal ExportJob(object application) { appObject = application; app = application; }
            object Keep(object value) { if (value != null) owned.Add(value); return value; }
            internal void Start()
            {
                try
                {
                    WindowHandle = new IntPtr(Convert.ToInt64(app.Hwnd, CultureInfo.InvariantCulture));
                    oldInteractive = Convert.ToBoolean(app.Interactive);
                    oldScreenUpdating = Convert.ToBoolean(app.ScreenUpdating);
                    oldEvents = Convert.ToBoolean(app.EnableEvents);
                    if (!oldInteractive) throw new InvalidOperationException("Excel에서 진행 중인 작업을 마친 뒤 다시 내보내 주세요.");
                    if (!oldEvents) throw new InvalidOperationException("Excel의 이벤트 처리가 꺼져 있어 원본 변경을 감지할 수 없습니다. 작업을 저장하고 Excel을 다시 시작한 뒤 내보내 주세요.");
                    initialCalculationMode = Convert.ToInt32(app.Calculation);
                    EnsureCalculationState(false);
                    object protectedWindow = app.ActiveProtectedViewWindow;
                    try { if (protectedWindow != null) throw new InvalidOperationException("보호된 보기에서는 내보낼 수 없습니다. 조직에서 허용한 일반 문서에서 실행해 주세요."); }
                    finally { ExportEngine.Release((object)protectedWindow); }
                    dynamic window = app.ActiveWindow;
                    try
                    {
                        if (window == null) throw new InvalidOperationException("워크시트에서 내보낼 셀을 선택해 주세요.");
                        dynamic selectedSheets = window.SelectedSheets;
                        try { if (Convert.ToInt32(selectedSheets.Count) != 1) throw new InvalidOperationException("시트를 하나만 선택한 뒤 내보내 주세요."); }
                        finally { ExportEngine.Release((object)selectedSheets); }
                    }
                    finally { ExportEngine.Release((object)window); }
                    selection = Keep((object)app.Selection);
                    if (selection == null) throw new InvalidOperationException("내보낼 직사각형 셀 범위를 선택해 주세요.");
                    dynamic areas = null;
                    try
                    {
                        areas = selection.Areas;
                        if (Convert.ToInt32(areas.Count) != 1) throw new InvalidOperationException("떨어진 여러 범위는 내보낼 수 없습니다. 직사각형 범위 하나를 선택해 주세요.");
                        sheet = Keep((object)selection.Worksheet);
                        if (Convert.ToInt32(sheet.Type) != -4167) throw new InvalidOperationException("워크시트의 셀 범위를 선택해 주세요.");
                    }
                    catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
                    { throw new InvalidOperationException("차트나 개체 대신 직사각형 셀 범위를 선택해 주세요."); }
                    finally { ExportEngine.Release((object)areas); }
                    book = Keep((object)sheet.Parent);
                    cells = Keep((object)sheet.Cells);
                    sheetRows = Keep((object)sheet.Rows);
                    sheetColumns = Keep((object)sheet.Columns);
                    firstRow = Convert.ToInt32(selection.Row); firstColumn = Convert.ToInt32(selection.Column);
                    dynamic rangeRows = selection.Rows, rangeColumns = selection.Columns;
                    try { rowCount = Convert.ToInt32(rangeRows.Count); columnCount = Convert.ToInt32(rangeColumns.Count); }
                    finally { ExportEngine.Release((object)rangeColumns); ExportEngine.Release((object)rangeRows); }
                    if (rowCount >= 1048576 || columnCount >= 16384)
                        throw new InvalidOperationException("전체 행이나 열 대신 필요한 셀 범위를 한정해 다시 선택해 주세요.");
                    if ((long)rowCount * columnCount > 1000000)
                        throw new InvalidOperationException("선택 범위는 숨긴 셀을 포함하여 1,000,000칸 이하여야 합니다. 범위를 나누어 내보내 주세요.");
                    date1904 = Convert.ToBoolean(book.Date1904);
                    onChange = delegate(object sh, object target) { if (sourcePhase && ExportEngine.Same(sh, (object)sheet)) sourceChanged = "작업 중 원본 값이 변경되었습니다. 다시 선택하여 내보내 주세요."; };
                    onCalculate = delegate(object sh) { if (sourcePhase && ExportEngine.Same(sh, (object)sheet)) sourceChanged = "작업 중 원본이 다시 계산되었습니다. 계산이 끝난 뒤 다시 내보내 주세요."; };
                    onClose = delegate(object wb, ref bool closing) { if (sourcePhase && ExportEngine.Same(wb, (object)book)) sourceChanged = "작업 중 원본 통합문서가 닫혀 내보내기를 중단했습니다."; };
                    // Excel Application event dispids: SheetChange, SheetCalculate, WorkbookBeforeClose.
                    ComEventsHelper.Combine(appObject, appEvents, 1564, onChange);
                    hooks = true;
                    ComEventsHelper.Combine(appObject, appEvents, 1563, onCalculate);
                    ComEventsHelper.Combine(appObject, appEvents, 1570, onClose);
                    changedState = true;
                    app.Interactive = false;
                    app.ScreenUpdating = false;
                    work = Execute().GetEnumerator();
                }
                catch (COMException ex) { throw new InvalidOperationException("선택 범위와 Excel 상태를 확인하지 못했습니다. 셀 편집이나 대화상자를 마친 뒤 다시 시도해 주세요.", ex); }
            }

            internal void Advance()
            {
                if (finished) return;
                var slice = Stopwatch.StartNew();
                try
                {
                    Check();
                    do
                    {
                        if (!work.MoveNext()) { finished = true; return; }
                        if (cancel) throw new OperationCanceledException("내보내기를 취소했습니다.");
                    } while (slice.ElapsedMilliseconds < 25);
                }
                catch (Exception ex) { failure = ex; finished = true; }
            }
            internal void Cancel() { cancel = true; }
            void Check()
            {
                if (cancel) throw new OperationCanceledException("내보내기를 취소했습니다.");
                if (sourceChanged != null) throw new InvalidOperationException(sourceChanged);
                if (sourcePhase)
                {
                    EnsureCalculationState(true);
                    // A closed workbook/sheet rejects these calls even if events were suppressed externally.
                    string ignoredBookName = Convert.ToString(book.Name);
                    string ignoredSheetName = Convert.ToString(sheet.Name);
                    if (!Convert.ToBoolean(app.EnableEvents))
                        throw new InvalidOperationException("작업 중 Excel 이벤트 처리가 중단되어 내보내기를 멈췄습니다. 다시 시도해 주세요.");
                }
            }

            void EnsureCalculationState(bool duringSnapshot)
            {
                int state = Convert.ToInt32(app.CalculationState);
                int mode = Convert.ToInt32(app.Calculation);
                if (mode != initialCalculationMode)
                    throw new InvalidOperationException("작업 중 Excel 계산 모드가 바뀌어 내보내기를 중단했습니다. 다시 내보내 주세요.");
                if (ExportEngine.CanReadCachedValues(state, mode)) return;
                if (state == 1)
                    throw new InvalidOperationException(duringSnapshot ? "작업 중 Excel 계산이 시작되었습니다. 계산이 끝난 뒤 다시 내보내 주세요." : "Excel 계산이 진행 중입니다. 계산이 끝난 뒤 다시 내보내 주세요.");
                if (state == 2)
                    throw new InvalidOperationException("Excel의 자동 계산이 대기 중입니다. 계산이 끝난 뒤 다시 내보내 주세요.");
                throw new InvalidOperationException("Excel의 계산 상태를 확인하지 못했습니다. 진행 중인 작업을 마친 뒤 다시 시도해 주세요.");
            }

            IEnumerable<int> Execute()
            {
                Status = "보이는 열을 확인하고 있습니다.";
                // Read visibility metadata before any values. EntireColumn/EntireRow is never read for values.
                for (int c = firstColumn; c < firstColumn + columnCount; c++)
                {
                    dynamic column = sheetColumns[c];
                    try { if (!Convert.ToBoolean(column.Hidden)) columns.Add(c); }
                    finally { ExportEngine.Release((object)column); }
                    if ((c - firstColumn) % 32 == 0) { Status = "보이는 열 확인 · " + (c - firstColumn + 1) + " / " + columnCount; yield return 0; }
                }
                if (columns.Count == 0) throw new InvalidOperationException("선택 범위에 보이는 열이 없습니다.");
                // A bulk Hidden value is not a visibility map: filter/manual hiding
                // may be mixed. Inspect every row before reading any source values.
                for (int r = firstRow; r < firstRow + rowCount; r++)
                {
                    dynamic row = sheetRows[r];
                    object hidden;
                    try { hidden = row.Hidden; }
                    finally { ExportEngine.Release((object)row); }
                    if (!(hidden is bool))
                        throw new InvalidOperationException("원본 행의 숨김 상태를 확인하지 못했습니다. 범위를 다시 선택해 주세요.");
                    if (!(bool)hidden)
                    {
                        rows.Add(r);
                        if ((long)rows.Count * columns.Count > 100000)
                            throw new InvalidOperationException("보이는 셀은 100,000칸까지 내보낼 수 있습니다. 범위를 나누어 다시 선택해 주세요.");
                    }
                    if ((r - firstRow + 1) % 16 == 0 || r == firstRow + rowCount - 1)
                    {
                        Status = "보이는 행 확인 · " + (r - firstRow + 1) + " / " + rowCount;
                        yield return 0;
                    }
                }
                plan = VisibleRangePlan.Create(firstRow, firstColumn, rowCount, columnCount, rows, columns);
                values = new object[rows.Count, columns.Count];
                cellFormats = new CellFormat[rows.Count, columns.Count];
                rowHeights = new double[rows.Count]; columnWidths = new double[columns.Count]; columnPoints = new double[columns.Count];
                dynamic conditions = selection.FormatConditions;
                try
                {
                    for (int i = 1; i <= Convert.ToInt32(conditions.Count); i++)
                    {
                        dynamic condition = conditions[i];
                        try { int type = Convert.ToInt32(condition.Type); if (type == 4 || type == 6) unsupportedEffects = true; }
                        finally { ExportEngine.Release((object)condition); }
                        yield return 0;
                    }
                }
                finally { ExportEngine.Release((object)conditions); }
                // One combined warning before expensive per-cell display formatting.
                if (plan.CellCount > 20000 || unsupportedEffects)
                {
                    string warning = plan.CellCount > 20000 ? "보이는 셀 " + plan.CellCount.ToString("N0", CultureInfo.CurrentCulture) + "개의 값과 서식을 읽습니다. 시간이 걸릴 수 있습니다.\n\n" : "";
                    if (unsupportedEffects) warning += "조건부 서식의 데이터 막대와 아이콘은 새 통합문서에 포함되지 않습니다. 값과 지원되는 글자·배경·테두리 서식은 유지합니다.\n\n";
                    warning += "계속 내보낼까요?";
                    DialogResult answer = MessageBox.Show(new ExcelWindow(WindowHandle), warning, "선택범위 내보내기", MessageBoxButtons.OKCancel, MessageBoxIcon.Information);
                    if (answer != DialogResult.OK) throw new OperationCanceledException("내보내기를 취소했습니다.");
                    Check();
                }
                dynamic styles = book.Styles, normal = null, normalFontObject = null;
                try
                {
                    normal = styles["Normal"]; normalFontObject = normal.Font;
                    normalFont = Convert.ToString(normalFontObject.Name); normalSize = Convert.ToDouble(normalFontObject.Size);
                    normalBold = Convert.ToBoolean(normalFontObject.Bold); normalItalic = Convert.ToBoolean(normalFontObject.Italic);
                }
                finally { ExportEngine.Release((object)normalFontObject); ExportEngine.Release((object)normal); ExportEngine.Release((object)styles); }
                for (int c = 0; c < columns.Count; c++)
                {
                    dynamic column = sheetColumns[columns[c]];
                    try { columnWidths[c] = Convert.ToDouble(column.ColumnWidth); columnPoints[c] = Convert.ToDouble(column.Width); }
                    finally { ExportEngine.Release((object)column); }
                    yield return 0;
                }
                for (int r = 0; r < rows.Count; r++)
                {
                    dynamic row = sheetRows[rows[r]];
                    try { rowHeights[r] = Convert.ToDouble(row.RowHeight); }
                    finally { ExportEngine.Release((object)row); }
                    for (int c = 0; c < columns.Count; c++)
                    {
                        dynamic cell = cells[rows[r], columns[c]];
                        try
                        {
                            if (Convert.ToBoolean(cell.MergeCells))
                            {
                                dynamic merge = cell.MergeArea;
                                dynamic mr = null, mc = null;
                                try
                                {
                                    mr = merge.Rows; mc = merge.Columns;
                                    int top = Convert.ToInt32(merge.Row), left = Convert.ToInt32(merge.Column);
                                    int height = Convert.ToInt32(mr.Count), width = Convert.ToInt32(mc.Count);
                                    string key = top + ":" + left + ":" + height + ":" + width;
                                    if (!mergeKeys.ContainsKey(key))
                                    {
                                        plan.ValidateMerge(top, left, height, width);
                                        mergeKeys.Add(key, true);
                                        merges.Add(new MergeInfo { Row = plan.OutputRow(top), Column = plan.OutputColumn(left), Rows = height, Columns = width });
                                    }
                                }
                                finally { ExportEngine.Release((object)mc); ExportEngine.Release((object)mr); ExportEngine.Release((object)merge); }
                            }
                            CellFormat format = CellFormat.Read((object)cell);
                            string formatKey = format.Key();
                            CellFormat shared;
                            if (!formats.TryGetValue(formatKey, out shared)) { shared = format; formats.Add(formatKey, shared); }
                            cellFormats[r, c] = shared;
                        }
                        finally { ExportEngine.Release((object)cell); }
                        Status = "병합과 표시 서식 읽기 · " + ((long)r * columns.Count + c + 1) + " / " + plan.CellCount;
                        yield return 0;
                    }
                }
                long stringLength = 0, valuesRead = 0;
                foreach (IndexRun rr in ExportEngine.Runs(rows))
                foreach (IndexRun cc in ExportEngine.Runs(columns))
                {
                    // A cell may contain 32,767 characters. Bound each COM allocation before
                    // enforcing the aggregate 10M-character limit, even for huge long-text selections.
                    for (int columnOffset = 0; columnOffset < cc.Count; columnOffset += 256)
                    {
                        int width = Math.Min(256, cc.Count - columnOffset);
                        int rowsPerRead = Math.Max(1, 256 / width);
                        for (int rowOffset = 0; rowOffset < rr.Count; rowOffset += rowsPerRead)
                        {
                            int height = Math.Min(rowsPerRead, rr.Count - rowOffset);
                            dynamic block = ExportEngine.Range((object)cells, rr.Source + rowOffset, cc.Source + columnOffset,
                                rr.Source + rowOffset + height - 1, cc.Source + columnOffset + width - 1);
                            object raw;
                            try { raw = block.Value2; }
                            finally { ExportEngine.Release((object)block); }
                            Array array = raw as Array;
                            int rLower = array == null ? 0 : array.GetLowerBound(0), cLower = array == null ? 0 : array.GetLowerBound(1);
                            for (int r = 0; r < height; r++)
                            for (int c = 0; c < width; c++)
                            {
                                object value = array == null ? raw : array.GetValue(r + rLower, c + cLower);
                                string text = value as string;
                                if (text != null)
                                {
                                    stringLength += text.Length;
                                    if (stringLength > MaximumStrings) throw new InvalidOperationException("선택한 문자열의 합계가 10,000,000자를 넘었습니다. 범위를 나누어 내보내 주세요.");
                                }
                                values[rr.Output + rowOffset + r, cc.Output + columnOffset + c] = ExportEngine.NormalizeValue(value);
                            }
                            valuesRead += (long)height * width;
                            Status = "보이는 셀 값 읽기 · " + valuesRead + " / " + plan.CellCount;
                            yield return 0;
                        }
                    }
                }
                Check();
                sourcePhase = false;
                // Snapshot is complete. Other add-ins must not attach sheets/links to our new document via events.
                app.EnableEvents = false;
                // Some workbook/style mutations clear Excel's shared native Undo history.
                // Build only in an owned, hidden Excel instance; the source receives a
                // completed template with Workbooks.Add and no subsequent data setters.
                Status = "새 통합문서의 값과 서식을 준비하고 있습니다.";
                outputWorkspace = new OutputWorkspace(appObject);
                outputApplication = outputWorkspace.Application;
                dynamic workbooks = ((dynamic)outputApplication).Workbooks;
                try { output = workbooks.Add(-4167); }
                finally { ExportEngine.Release((object)workbooks); }
                output.Date1904 = date1904;
                dynamic outputSheets = output.Worksheets;
                try { outputSheet = outputSheets[1]; }
                finally { ExportEngine.Release((object)outputSheets); }
                outputSheet.Name = "선택범위";
                outputCells = outputSheet.Cells;
                dynamic outStyles = output.Styles, outNormal = null, outFont = null;
                try { outNormal = outStyles["Normal"]; outFont = outNormal.Font; outFont.Name = normalFont; outFont.Size = normalSize; outFont.Bold = normalBold; outFont.Italic = normalItalic; }
                finally { ExportEngine.Release((object)outFont); ExportEngine.Release((object)outNormal); ExportEngine.Release((object)outStyles); }
                yield return 0;
                // Keep each write bounded as well as each source read, so cancellation can
                // be processed between COM calls even for the largest permitted text payload.
                long valuesWritten = 0;
                foreach (CellBlock block in ExportEngine.Blocks(rows.Count, columns.Count))
                {
                    var writeValues = new object[block.Rows, block.Columns];
                    for (int r = 0; r < block.Rows; r++)
                    for (int c = 0; c < block.Columns; c++)
                    {
                        object value = values[block.Row + r, block.Column + c];
                        string text = value as string;
                        // Excel consumes one apostrophe even in a preformatted Text cell.
                        writeValues[r, c] = text != null && text.StartsWith("'", StringComparison.Ordinal) ? "'" + text : value;
                    }
                    dynamic destination = ExportEngine.Range((object)outputCells, block.Row + 1, block.Column + 1,
                        block.Row + block.Rows, block.Column + block.Columns);
                    try { destination.NumberFormat = "@"; destination.Value2 = writeValues; }
                    finally { ExportEngine.Release((object)destination); }
                    valuesWritten += (long)block.Rows * block.Columns;
                    Status = "새 통합문서에 값 기록 · " + valuesWritten + " / " + plan.CellCount;
                    yield return 0;
                }
                for (int r = 0; r < rows.Count; r++)
                {
                    int c = 0;
                    while (c < columns.Count)
                    {
                        CellFormat format = cellFormats[r, c];
                        int end = c;
                        if (format.CanGroup)
                            while (end + 1 < columns.Count && Object.ReferenceEquals(format, cellFormats[r, end + 1])) end++;
                        dynamic target = ExportEngine.Range((object)outputCells, r + 1, c + 1, r + 1, end + 1);
                        try { format.Apply((object)target, end > c); }
                        finally { ExportEngine.Release((object)target); }
                        c = end + 1;
                        Status = "새 통합문서 서식 적용 · " + ((long)r * columns.Count + c) + " / " + plan.CellCount;
                        yield return 0;
                    }
                }
                foreach (MergeInfo merge in merges)
                {
                    dynamic target = ExportEngine.Range((object)outputCells, merge.Row, merge.Column, merge.Row + merge.Rows - 1, merge.Column + merge.Columns - 1);
                    try { target.Merge(false); }
                    finally { ExportEngine.Release((object)target); }
                    yield return 0;
                }
                dynamic outputColumns = outputSheet.Columns, outputRows = outputSheet.Rows;
                try
                {
                    for (int c = 0; c < columns.Count; c++)
                    {
                        dynamic column = outputColumns[c + 1];
                        try
                        {
                            column.ColumnWidth = columnWidths[c];
                            for (int correction = 0; correction < 3; correction++)
                            {
                                double actual = Convert.ToDouble(column.Width);
                                if (Math.Abs(actual - columnPoints[c]) <= 0.8 || actual <= 0) break;
                                double adjusted = Convert.ToDouble(column.ColumnWidth) * columnPoints[c] / actual;
                                column.ColumnWidth = Math.Max(0.1, Math.Min(255.0, adjusted));
                            }
                        }
                        finally { ExportEngine.Release((object)column); }
                        yield return 0;
                    }
                    for (int r = 0; r < rows.Count; r++)
                    {
                        dynamic row = outputRows[r + 1];
                        try { row.RowHeight = rowHeights[r]; }
                        finally { ExportEngine.Release((object)row); }
                        if (r % 32 == 0) yield return 0;
                    }
                }
                finally { ExportEngine.Release((object)outputRows); ExportEngine.Release((object)outputColumns); }
                Status = "수식과 외부 연결이 남지 않았는지 확인하고 있습니다.";
                VerifyOutput();
                foreach (int verified in VerifyValues()) yield return verified;
                Check();
                Status = "완성된 내용을 새 Excel 창으로 열고 있습니다.";
                string template = outputWorkspace.SaveTemplate((object)output);
                CloseOutput();
                outputWorkspace.CloseApplication();
                Check();
                // The original instance only opens the completed template. Keep all
                // names, styles, values and sizes in the template to preserve Undo.
                PrepareOutputUi();
                outputApplication = appObject;
                workbooks = app.Workbooks;
                try { output = workbooks.Add(template); }
                finally { ExportEngine.Release((object)workbooks); }
                GuardOutputUi();
                // A template-based workbook starts with Saved=true despite having
                // no file path. This flag restores the normal save-on-close prompt;
                // it does not mutate cells/styles or clear the native Undo stack.
                output.Saved = false;
                outputSheets = output.Worksheets;
                try { outputSheet = outputSheets[1]; }
                finally { ExportEngine.Release((object)outputSheets); }
                outputCells = outputSheet.Cells;
                VerifyOutput();
                foreach (int verified in VerifyValues()) yield return verified;
                outputWorkspace.Dispose();
                outputWorkspace = null;
                successful = true;
                yield return 0;
            }

            void VerifyOutput()
            {
                dynamic target = ExportEngine.Range((object)outputCells, 1, 1, rows.Count, columns.Count);
                try
                {
                    object hasFormula = target.HasFormula;
                    if (!(hasFormula is bool) || (bool)hasFormula) throw new InvalidOperationException("새 통합문서에 수식이 남아 있어 결과를 폐기했습니다.");
                    dynamic comments = outputSheet.Comments, hyperlinks = target.Hyperlinks, conditions = target.FormatConditions;
                    try
                    {
                        if (Convert.ToInt32(comments.Count) != 0 || Convert.ToInt32(hyperlinks.Count) != 0 || Convert.ToInt32(conditions.Count) != 0)
                            throw new InvalidOperationException("새 통합문서에 허용하지 않은 부가 정보가 있어 결과를 폐기했습니다.");
                    }
                    finally { ExportEngine.Release((object)conditions); ExportEngine.Release((object)hyperlinks); ExportEngine.Release((object)comments); }
                }
                finally { ExportEngine.Release((object)target); }
                dynamic allSheets = output.Sheets, connections = output.Connections, names = output.Names;
                try
                {
                    if (Convert.ToInt32(allSheets.Count) != 1 || Convert.ToBoolean(output.HasVBProject) || Convert.ToInt32(connections.Count) != 0 || Convert.ToInt32(names.Count) != 0 || !String.IsNullOrEmpty(Convert.ToString(output.Path)))
                        throw new InvalidOperationException("새 통합문서의 시트·매크로·연결 상태가 예상과 달라 결과를 폐기했습니다.");
                    if (output.LinkSources(1) != null || output.LinkSources(2) != null)
                        throw new InvalidOperationException("새 통합문서에 외부 연결이 있어 결과를 폐기했습니다.");
                }
                finally { ExportEngine.Release((object)names); ExportEngine.Release((object)connections); ExportEngine.Release((object)allSheets); }
            }
            IEnumerable<int> VerifyValues()
            {
                long verified = 0;
                foreach (CellBlock block in ExportEngine.Blocks(rows.Count, columns.Count))
                {
                    dynamic target = ExportEngine.Range((object)outputCells, block.Row + 1, block.Column + 1,
                        block.Row + block.Rows, block.Column + block.Columns);
                    object raw;
                    try { raw = target.Value2; }
                    finally { ExportEngine.Release((object)target); }
                    Array array = raw as Array;
                    int rLower = array == null ? 0 : array.GetLowerBound(0);
                    int cLower = array == null ? 0 : array.GetLowerBound(1);
                    for (int r = 0; r < block.Rows; r++)
                    for (int c = 0; c < block.Columns; c++)
                    {
                        object expected = values[block.Row + r, block.Column + c];
                        object actual = array == null ? raw : array.GetValue(r + rLower, c + cLower);
                        bool equal;
                        var error = expected as ErrorWrapper;
                        if (error != null)
                            equal = (actual is int && (int)actual == error.ErrorCode) || (actual is uint && unchecked((int)(uint)actual) == error.ErrorCode);
                        else equal = Object.Equals(expected, actual);
                        if (!equal)
                            throw new InvalidOperationException("새 통합문서의 값이나 타입이 원본 계산 결과와 달라 결과를 폐기했습니다. (결과 " + (block.Row + r + 1) + "행 " + (block.Column + c + 1) + "열)");
                    }
                    verified += (long)block.Rows * block.Columns;
                    Status = "내보낸 값 확인 · " + verified + " / " + plan.CellCount;
                    yield return 0;
                }
            }

            internal void Complete()
            {
                if (failure != null)
                {
                    if (failure is OperationCanceledException) throw failure;
                    if (failure is InvalidOperationException) throw failure;
                    throw new InvalidOperationException("내보내기를 완료하지 못했습니다. 원본은 변경하지 않았으며 불완전한 결과만 닫습니다. (" + failure.GetType().Name + ")", failure);
                }
                if (!successful) throw new InvalidOperationException("내보내기가 완료되지 않았습니다.");
                // Excel can restore the previous window when UI state is restored.
                // Finish restoration before bringing the completed result forward.
                RestoreState();
                if (changedState)
                    throw new InvalidOperationException("Excel 화면·입력·이벤트 상태를 완전히 복원하지 못해 내보내기를 완료하지 않았습니다. 불완전한 결과를 정리하고 상태 복원을 다시 시도합니다. Excel 상태를 확인해 주세요.");
                output.Activate();
                outputSheet.Activate();
                VerifyOutput();
            }
            internal object AcquireResultWindow()
            {
                dynamic windows = output.Windows;
                try
                {
                    if (Convert.ToInt32(windows.Count) != 1)
                        throw new InvalidOperationException("새 통합문서의 결과 창을 확인하지 못했습니다.");
                    return (object)windows[1];
                }
                finally { ExportEngine.Release((object)windows); }
            }
            void GuardOutputUi()
            {
                // The result window already exists. Prevent edits between bounded
                // write chunks; changedState keeps partial failures recoverable.
                app.Interactive = false;
                app.ScreenUpdating = false;
            }
            void PrepareOutputUi()
            {
                Exception failure = null;
                try { app.ScreenUpdating = oldScreenUpdating; }
                catch (Exception error) { failure = error; }
                try { app.Interactive = oldInteractive; }
                catch (Exception error) { if (failure == null) failure = error; }
                // Keep changedState set: output events remain disabled, and Dispose
                // must retry every original flag if creation or later writing fails.
                if (failure != null)
                    throw new InvalidOperationException("새 통합문서를 만들기 전 Excel 화면 상태를 복원하지 못했습니다. 원본을 유지하고 작업을 중단했습니다.", failure);
            }
            void RestoreState()
            {
                if (!changedState) return;
                // Restore independently. Retry from Dispose if any setter failed.
                bool restored = true;
                try { app.EnableEvents = oldEvents; } catch { restored = false; }
                try { app.ScreenUpdating = oldScreenUpdating; } catch { restored = false; }
                try { app.Interactive = oldInteractive; } catch { restored = false; }
                changedState = !restored;
            }
            void ReleaseOutput()
            {
                ExportEngine.Release((object)outputCells); ExportEngine.Release((object)outputSheet); ExportEngine.Release((object)output);
                outputCells = null; outputSheet = null; output = null;
            }
            void CloseOutput()
            {
                if (output == null) return;
                dynamic owner = outputApplication ?? appObject;
                bool alerts = Convert.ToBoolean(owner.DisplayAlerts);
                bool closed = false;
                try { owner.DisplayAlerts = false; output.Close(false); closed = true; }
                finally
                {
                    try { owner.DisplayAlerts = alerts; }
                    finally { if (closed) ReleaseOutput(); }
                }
            }
            internal void Rollback()
            {
                try { CloseOutput(); }
                finally { successful = false; }
            }
            public void Dispose()
            {
                if (work != null) { try { work.Dispose(); } catch { } work = null; }
                if (hooks)
                {
                    try { ComEventsHelper.Remove(appObject, appEvents, 1564, onChange); } catch { }
                    try { ComEventsHelper.Remove(appObject, appEvents, 1563, onCalculate); } catch { }
                    try { ComEventsHelper.Remove(appObject, appEvents, 1570, onClose); } catch { }
                }
                RestoreState();
                try
                {
                    // Rollback may fail transiently. Retry only this operation's
                    // unfinished workbook, never a successfully returned result.
                    if (!successful) CloseOutput();
                }
                finally
                {
                    ReleaseOutput();
                    outputApplication = null;
                    try { if (outputWorkspace != null) outputWorkspace.Dispose(); }
                    finally
                    {
                        for (int i = owned.Count - 1; i >= 0; i--) ExportEngine.Release((object)owned[i]);
                        owned.Clear();
                        selection = null; sheet = null; book = null; cells = null; sheetRows = null; sheetColumns = null;
                    }
                }
            }
        }

        // Pending in manual mode represents a retained result, not an active calculation.
        // Never calculate, refresh, or change the mode merely to make a cached snapshot.
        internal static bool CanReadCachedValues(int state, int mode)
        {
            return state == 0 || (state == 2 && mode == -4135);
        }
        struct CellBlock { internal int Row, Column, Rows, Columns; }
        static IEnumerable<CellBlock> Blocks(int rowCount, int columnCount)
        {
            for (int column = 0; column < columnCount; column += 256)
            {
                int width = Math.Min(256, columnCount - column);
                int rowsPerBlock = Math.Max(1, 256 / width);
                for (int row = 0; row < rowCount; row += rowsPerBlock)
                    yield return new CellBlock { Row = row, Column = column, Rows = Math.Min(rowsPerBlock, rowCount - row), Columns = width };
            }
        }

        static object NormalizeValue(object value)
        {
            if (value == null || value is double || value is string || value is bool) return value;
            if (value is ErrorWrapper) return value;
            // Excel numeric Value2 values are doubles; VT_ERROR is unwrapped as Int32/UInt32 by COM.
            if (value is int) return new ErrorWrapper((int)value);
            if (value is uint) return new ErrorWrapper(unchecked((int)(uint)value));
            throw new InvalidOperationException("지원하지 않는 셀 값 형식이 있습니다: " + value.GetType().Name + ". 값을 확인한 뒤 범위를 나누어 내보내 주세요.");
        }
        static bool Same(object a, object b)
        {
            if (a == null || b == null) return false;
            if (Object.ReferenceEquals(a, b)) return true;
            IntPtr pa = IntPtr.Zero, pb = IntPtr.Zero;
            try { pa = Marshal.GetIUnknownForObject(a); pb = Marshal.GetIUnknownForObject(b); return pa == pb; }
            catch { return false; }
            finally { if (pb != IntPtr.Zero) Marshal.Release(pb); if (pa != IntPtr.Zero) Marshal.Release(pa); }
        }
        static void Release(object value)
        {
            if (value != null && Marshal.IsComObject(value))
                try { Marshal.ReleaseComObject(value); } catch (InvalidComObjectException) { }
        }
        static object Range(object cellCollection, int row, int column, int endRow, int endColumn)
        {
            dynamic cells = cellCollection;
            dynamic first = null, last = null, parent = null;
            try { first = cells[row, column]; last = cells[endRow, endColumn]; parent = cells.Parent; return parent.Range[first, last]; }
            finally { ExportEngine.Release((object)parent); ExportEngine.Release((object)last); ExportEngine.Release((object)first); }
        }
        struct IndexRun { internal int Source, Output, Count; }
        static IEnumerable<IndexRun> Runs(IList<int> indices)
        {
            int i = 0;
            while (i < indices.Count)
            {
                int start = i;
                while (i + 1 < indices.Count && indices[i + 1] == indices[i] + 1) i++;
                yield return new IndexRun { Source = indices[start], Output = start, Count = i - start + 1 };
                i++;
            }
        }
        sealed class MergeInfo { internal int Row, Column, Rows, Columns; }

        sealed class BorderFormat
        {
            internal int Style, Weight, Color;
            internal string Key() { return Style + ":" + Weight + ":" + Color; }
            internal void Apply(object borderObject)
            {
                dynamic border = borderObject;
                if (Style != -4142) { border.Weight = Weight; border.Color = Color; }
                border.LineStyle = Style;
            }
        }
        sealed class CellFormat
        {
            static readonly int[] BorderIds = { 7, 8, 9, 10, 5, 6 };
            internal string FontName, NumberFormatLocal;
            internal double Size;
            internal bool Bold, Italic, Strike, Superscript, Subscript, Wrap, Shrink;
            internal int Underline, FontColor, Pattern, FillColor, PatternColor, Horizontal, Vertical, Orientation, Indent, ReadingOrder;
            internal BorderFormat[] Borders = new BorderFormat[6];
            internal bool CanGroup { get { return Borders[0].Key() == Borders[3].Key() && Borders[4].Style == -4142 && Borders[5].Style == -4142; } }
            static object Need(object value)
            {
                if (value == null || value == DBNull.Value) throw new InvalidOperationException("한 셀 안에 서로 다른 글꼴이나 지원하지 않는 혼합 서식이 있습니다. 해당 셀을 제외하고 내보내 주세요.");
                return value;
            }
            internal static CellFormat Read(object cellObject)
            {
                dynamic cell = cellObject;
                var result = new CellFormat();
                dynamic display = null, font = null, interior = null, borders = null;
                try
                {
                    display = cell.DisplayFormat; font = display.Font; interior = display.Interior; borders = display.Borders;
                    result.FontName = Convert.ToString(CellFormat.Need((object)font.Name)); result.Size = Convert.ToDouble(CellFormat.Need((object)font.Size));
                    result.Bold = Convert.ToBoolean(CellFormat.Need((object)font.Bold)); result.Italic = Convert.ToBoolean(CellFormat.Need((object)font.Italic));
                    result.Strike = Convert.ToBoolean(CellFormat.Need((object)font.Strikethrough)); result.Underline = Convert.ToInt32(CellFormat.Need((object)font.Underline));
                    result.Superscript = Convert.ToBoolean(CellFormat.Need((object)font.Superscript)); result.Subscript = Convert.ToBoolean(CellFormat.Need((object)font.Subscript));
                    result.FontColor = Convert.ToInt32(CellFormat.Need((object)font.Color));
                    // Capture and apply in the same Excel UI language, including localized General.
                    result.NumberFormatLocal = Convert.ToString(CellFormat.Need((object)display.NumberFormatLocal));
                    result.Pattern = Convert.ToInt32(CellFormat.Need((object)interior.Pattern));
                    if (result.Pattern == 4000 || result.Pattern == 4001)
                        throw new InvalidOperationException("그라데이션 셀 배경은 현재 지원하지 않습니다. 해당 셀을 제외하고 내보내 주세요.");
                    result.FillColor = Convert.ToInt32(CellFormat.Need((object)interior.Color)); result.PatternColor = Convert.ToInt32(CellFormat.Need((object)interior.PatternColor));
                    result.Horizontal = Convert.ToInt32(CellFormat.Need((object)display.HorizontalAlignment)); result.Vertical = Convert.ToInt32(CellFormat.Need((object)display.VerticalAlignment));
                    result.Wrap = Convert.ToBoolean(CellFormat.Need((object)display.WrapText)); result.Shrink = Convert.ToBoolean(CellFormat.Need((object)display.ShrinkToFit));
                    result.Orientation = Convert.ToInt32(CellFormat.Need((object)display.Orientation)); result.Indent = Convert.ToInt32(CellFormat.Need((object)display.IndentLevel));
                    result.ReadingOrder = Convert.ToInt32(CellFormat.Need((object)display.ReadingOrder));
                    for (int i = 0; i < BorderIds.Length; i++)
                    {
                        dynamic border = borders[BorderIds[i]];
                        try
                        {
                            var item = new BorderFormat(); item.Style = Convert.ToInt32(CellFormat.Need((object)border.LineStyle));
                            if (item.Style != -4142) { item.Weight = Convert.ToInt32(CellFormat.Need((object)border.Weight)); item.Color = Convert.ToInt32(CellFormat.Need((object)border.Color)); }
                            result.Borders[i] = item;
                        }
                        finally { ExportEngine.Release((object)border); }
                    }
                    return result;
                }
                finally { ExportEngine.Release((object)borders); ExportEngine.Release((object)interior); ExportEngine.Release((object)font); ExportEngine.Release((object)display); }
            }
            internal string Key()
            {
                string[] parts = new[] { FontName, NumberFormatLocal, Size.ToString("R", CultureInfo.InvariantCulture), Bold.ToString(), Italic.ToString(), Strike.ToString(), Superscript.ToString(), Subscript.ToString(), Underline.ToString(), FontColor.ToString(), Pattern.ToString(), FillColor.ToString(), PatternColor.ToString(), Horizontal.ToString(), Vertical.ToString(), Wrap.ToString(), Shrink.ToString(), Orientation.ToString(), Indent.ToString(), ReadingOrder.ToString(), Borders[0].Key(), Borders[1].Key(), Borders[2].Key(), Borders[3].Key(), Borders[4].Key(), Borders[5].Key() };
                var key = new System.Text.StringBuilder();
                foreach (string part in parts) key.Append(part.Length).Append(':').Append(part);
                return key.ToString();
            }
            internal void Apply(object targetObject, bool grouped)
            {
                dynamic target = targetObject;
                dynamic font = null, interior = null, borders = null;
                try
                {
                    target.NumberFormatLocal = NumberFormatLocal;
                    font = target.Font; font.Name = FontName; font.Size = Size; font.Bold = Bold; font.Italic = Italic; font.Strikethrough = Strike; font.Underline = Underline; font.Color = FontColor;
                    font.Superscript = Superscript; font.Subscript = Subscript;
                    interior = target.Interior;
                    if (Pattern != -4142) { interior.Color = FillColor; interior.PatternColor = PatternColor; }
                    interior.Pattern = Pattern;
                    target.HorizontalAlignment = Horizontal; target.VerticalAlignment = Vertical; target.WrapText = Wrap; target.ShrinkToFit = Shrink;
                    target.Orientation = Orientation; target.IndentLevel = Indent; target.ReadingOrder = ReadingOrder;
                    borders = target.Borders;
                    for (int i = 0; i < BorderIds.Length; i++)
                    {
                        if (Borders[i].Style == -4142) continue;
                        dynamic border = borders[BorderIds[i]];
                        try { Borders[i].Apply((object)border); }
                        finally { ExportEngine.Release((object)border); }
                    }
                    if (grouped && Borders[0].Style != -4142)
                    {
                        dynamic border = borders[11];
                        try { Borders[0].Apply((object)border); }
                        finally { ExportEngine.Release((object)border); }
                    }
                }
                finally { ExportEngine.Release((object)borders); ExportEngine.Release((object)interior); ExportEngine.Release((object)font); }
            }
        }
    }
}
