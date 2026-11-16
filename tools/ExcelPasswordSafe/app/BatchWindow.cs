using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Threading;

namespace ExcelPasswordSafe
{
    public sealed class BatchRow : INotifyPropertyChanged
    {
        public string Path { get; set; }
        public string Name { get; set; }
        public string FullDescription { get { return Path + "\n" + Detail; } }
        string state, attempts, detail;
        public string State { get { return state; } set { state = value; Changed("State"); } }
        public string Attempts { get { return attempts; } set { attempts = value; Changed("Attempts"); } }
        public string Detail { get { return detail; } set { detail = value; Changed("Detail"); Changed("FullDescription"); } }
        public event PropertyChangedEventHandler PropertyChanged;
        void Changed(string name) { var handler = PropertyChanged; if (handler != null) handler(this, new PropertyChangedEventArgs(name)); }
    }

    public sealed class BatchWindow : Window
    {
        readonly string folder, mode;
        readonly ObservableCollection<BatchRow> rows = new ObservableCollection<BatchRow>();
        readonly Dictionary<string, BatchRow> byPath = new Dictionary<string, BatchRow>(StringComparer.OrdinalIgnoreCase);
        readonly DataGrid grid = new DataGrid();
        readonly TextBlock count = new TextBlock(), status = new TextBlock();
        readonly PasswordBox oldPassword = new PasswordBox(), newPassword = new PasswordBox(), confirmation = new PasswordBox();
        readonly CheckBox consent = new CheckBox();
        readonly Button run = new Button(), close = new Button(), refresh = new Button(), report = new Button(), records = new Button();
        readonly ProgressBar progress = new ProgressBar();
        readonly DispatcherTimer timer = new DispatcherTimer();
        readonly Border footer = new Border();
        BatchDiscovery discovery;
        CancellationTokenSource scanCancel;
        string runDirectory, reportPath;
        bool scanning, busy, cancelRequested, finished;
        readonly bool smoke;

        public BatchWindow(string selectedFolder, string selectedMode) : this(selectedFolder, selectedMode, false) { }

        BatchWindow(string selectedFolder, string selectedMode, bool isSmoke)
        {
            if (!BatchWorkflow.IsMode(selectedMode)) throw new ArgumentException("Unknown operation");
            folder = Path.GetFullPath(selectedFolder); mode = selectedMode; smoke = isSmoke;
            Title = "폴더 Excel 암호 관리";
            double availableWidth = Math.Max(320, SystemParameters.WorkArea.Width - 24);
            double availableHeight = Math.Max(320, SystemParameters.WorkArea.Height - 24);
            Width = Math.Min(900, availableWidth); Height = Math.Min(850, availableHeight);
            MinWidth = Math.Min(620, availableWidth); MinHeight = Math.Min(560, availableHeight); WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Malgun Gothic"); FontSize = 13;
            UseLayoutRounding = true; SnapsToDevicePixels = true;
            Background = Brush("#F4F6FB"); Foreground = Brush("#17223B"); Resources = AppTheme.Create();
            var root = new DockPanel { LastChildFill = true, Background = Brush("#F4F6FB") }; Content = root;
            var header = new Border { Background = Brushes.White, Padding = new Thickness(24, 18, 24, 15), BorderBrush = Brush("#E2E8F2"), BorderThickness = new Thickness(0, 0, 0, 1) };
            DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
            var heading = new StackPanel(); header.Child = heading;
            heading.Children.Add(new TextBlock { Text = "폴더 Excel 암호 관리", FontSize = 24, FontWeight = FontWeights.Bold });
            heading.Children.Add(Text("하위 폴더까지 확인하고, 파일별 결과를 기록합니다.", "#52637F", 12, 5));

            footer.Background = Brushes.White; footer.Padding = new Thickness(22, 12, 22, 14);
            footer.BorderBrush = Brush("#E0E6F0"); footer.BorderThickness = new Thickness(0, 1, 0, 0);
            DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
            var foot = new StackPanel(); footer.Child = foot;
            progress.Height = 2; progress.Foreground = Brush("#3659D9"); progress.Background = Brush("#E7ECF7"); progress.Visibility = Visibility.Collapsed; foot.Children.Add(progress);
            status.TextWrapping = TextWrapping.Wrap; status.FontSize = 12; status.LineHeight = 18; status.Foreground = Brush("#52637F");
            AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
            foot.Children.Add(new Border { Background = Brush("#F4F6FB"), CornerRadius = new CornerRadius(9), Padding = new Thickness(12, 10, 12, 10), Margin = new Thickness(0, 7, 0, 10), Child = status });
            var commands = new DockPanel { LastChildFill = false }; foot.Children.Add(commands);
            close.Content = "닫기"; close.MinWidth = 70; close.Click += delegate { if (busy || scanning) RequestCancel(); else Close(); };
            DockPanel.SetDock(close, Dock.Right); commands.Children.Add(close);
            run.Content = BatchWorkflow.ModeLabel(mode); run.MinWidth = 114; run.Margin = new Thickness(0, 0, 8, 0); run.Style = (Style)Resources["PrimaryButton"];
            run.Click += ApplyClick; DockPanel.SetDock(run, Dock.Right); commands.Children.Add(run);
            report.Content = "실패 보고서 열기"; report.Style = (Style)Resources["QuietButton"]; report.Visibility = Visibility.Collapsed; report.Click += delegate { OpenReport(); }; commands.Children.Add(report);
            records.Content = "백업·기록 보기"; records.Style = (Style)Resources["QuietButton"]; records.Visibility = Visibility.Collapsed; records.Click += delegate { OpenRecords(); }; commands.Children.Add(records);

            var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Padding = new Thickness(22, 15, 22, 16) }; root.Children.Add(scroll);
            var body = new StackPanel(); scroll.Content = body;
            var folderBody = new StackPanel();
            folderBody.Children.Add(Text("선택한 폴더 · 하위 폴더 포함", "#52637F", 11, 0));
            var path = new TextBox { Text = folder, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = Brush("#17223B"), FontSize = 13, FontWeight = FontWeights.SemiBold, Padding = new Thickness(0), TextWrapping = TextWrapping.Wrap, MaxHeight = 52, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 5, 0, 0) };
            AutomationProperties.SetName(path, "선택한 폴더 전체 경로"); folderBody.Children.Add(path);
            body.Children.Add(new Border { Background = Brushes.White, CornerRadius = new CornerRadius(11), BorderBrush = Brush("#DFE5F0"), BorderThickness = new Thickness(1), Padding = new Thickness(14, 10, 14, 10), Child = folderBody });
            var listHeading = new DockPanel { Margin = new Thickness(0, 10, 0, 5) };
            refresh.Content = "목록 새로고침"; refresh.Style = (Style)Resources["QuietButton"]; refresh.Padding = new Thickness(7, 5, 7, 5); refresh.Click += async delegate { await RefreshTargets(); };
            DockPanel.SetDock(refresh, Dock.Right); listHeading.Children.Add(refresh);
            count.FontWeight = FontWeights.SemiBold; count.VerticalAlignment = VerticalAlignment.Center; listHeading.Children.Add(count); body.Children.Add(listHeading);
            grid.ItemsSource = rows; grid.AutoGenerateColumns = false; grid.IsReadOnly = true; grid.CanUserAddRows = false; grid.CanUserDeleteRows = false;
            grid.HeadersVisibility = DataGridHeadersVisibility.Column; grid.GridLinesVisibility = DataGridGridLinesVisibility.Horizontal;
            grid.HorizontalGridLinesBrush = Brush("#E8ECF4"); grid.RowBackground = Brushes.White; grid.AlternatingRowBackground = Brush("#F7F9FC");
            grid.BorderBrush = Brush("#DFE5F0"); grid.BorderThickness = new Thickness(1); grid.Height = 185; grid.MinRowHeight = 30;
            grid.EnableRowVirtualization = true; grid.EnableColumnVirtualization = true; grid.SelectionMode = DataGridSelectionMode.Single;
            var rowStyle = new Style(typeof(DataGridRow)); rowStyle.Setters.Add(new Setter(ToolTipProperty, new Binding("FullDescription"))); grid.RowStyle = rowStyle;
            ScrollViewer.SetHorizontalScrollBarVisibility(grid, ScrollBarVisibility.Auto);
            grid.Columns.Add(new DataGridTextColumn { Header = "파일 / 폴더", Binding = new Binding("Name"), Width = new DataGridLength(1, DataGridLengthUnitType.Star), MinWidth = 170 });
            grid.Columns.Add(new DataGridTextColumn { Header = "결과", Binding = new Binding("State"), Width = 88 });
            grid.Columns.Add(new DataGridTextColumn { Header = "시도", Binding = new Binding("Attempts"), Width = 50 });
            grid.Columns.Add(new DataGridTextColumn { Header = "설명", Binding = new Binding("Detail"), Width = new DataGridLength(1, DataGridLengthUnitType.Star), MinWidth = 170 });
            AutomationProperties.SetName(grid, "처리 대상과 파일별 결과"); body.Children.Add(grid);
            body.Children.Add(Text(BatchWorkflow.ModeLabel(mode) + " · 모든 대상에 같은 암호 사용", "#17223B", 15, 13));
            body.Children.Add(Text(mode == "Encrypt" ? "암호가 없는 파일에 설정합니다. 이미 암호가 있는 파일은 바꾸지 않습니다." : "현재 암호가 다른 파일은 실패로 기록합니다. 완료한 파일은 그대로 유지합니다.", "#52637F", 11, 4));
            if (mode != "Encrypt") AddPassword(body, oldPassword, "현재 암호");
            if (mode != "Decrypt")
            {
                var pair = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2 };
                var left = new StackPanel { Margin = new Thickness(0, 0, 6, 0) }; var right = new StackPanel { Margin = new Thickness(6, 0, 0, 0) };
                AddPassword(left, newPassword, "새 암호 (1~15자)"); AddPassword(right, confirmation, "새 암호 확인"); pair.Children.Add(left); pair.Children.Add(right); body.Children.Add(pair);
            }
            body.Children.Add(Text("실행 전 Excel을 모두 닫아 주세요. 실패는 안전한 경우 최대 3회 시도하고 Excel 보고서를 남깁니다.", "#52637F", 11, 10));
            body.Children.Add(Text("작업용 중간 파일은 정리합니다. 원본 백업은 별도로 보관하며, 암호가 없을 수 있습니다.", "#52637F", 11, 3));
            consent.Content = Text("목록에 표시된 파일에 적용하고 원본 백업을 남깁니다.", "#52637F", 12, 0); consent.Margin = new Thickness(0, 11, 0, 0);
            consent.Checked += delegate { UpdateControls(); }; consent.Unchecked += delegate { UpdateControls(); }; body.Children.Add(consent);
            oldPassword.PasswordChanged += delegate { UpdateControls(); }; newPassword.PasswordChanged += delegate { UpdateControls(); }; confirmation.PasswordChanged += delegate { UpdateControls(); };
            int tab = 0;
            foreach (Control control in new Control[] { path, refresh, grid, oldPassword, newPassword, confirmation, consent, report, records, run, close }) System.Windows.Input.KeyboardNavigation.SetTabIndex(control, tab++);
            System.Windows.Input.KeyboardNavigation.SetTabNavigation(root, System.Windows.Input.KeyboardNavigationMode.Cycle);
            timer.Interval = TimeSpan.FromMilliseconds(350); timer.Tick += delegate { ReadProgress(); };
            Closing += delegate(object sender, CancelEventArgs e) { if (busy || scanning) { e.Cancel = true; RequestCancel(); } };
            Closed += delegate { timer.Stop(); ClearPasswords(); if (scanCancel != null) scanCancel.Dispose(); };
            if (!smoke) Loaded += async delegate { await RefreshTargets(); };
            SetStatus("폴더 안의 Excel 파일을 확인합니다.", false); UpdateControls();
        }

        static SolidColorBrush Brush(string value) { return (SolidColorBrush)new BrushConverter().ConvertFromString(value); }
        static TextBlock Text(string value, string color, double size, double top) { return new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap, Foreground = Brush(color), FontSize = size, LineHeight = size + 6, Margin = new Thickness(0, top, 0, 0) }; }
        void AddPassword(Panel parent, PasswordBox box, string label)
        {
            parent.Children.Add(new Label { Content = label, Target = box, Padding = new Thickness(0), Foreground = Brush("#485B78"), FontSize = 11, Margin = new Thickness(0, 7, 0, 4) });
            box.MinHeight = 38; parent.Children.Add(box); AutomationProperties.SetName(box, label);
        }
        void ClearPasswords() { oldPassword.Clear(); newPassword.Clear(); confirmation.Clear(); }
        void SetStatus(string message, bool error) { status.Text = message; status.Foreground = Brush(error ? "#A42F50" : "#52637F"); }
        void UpdateControls()
        {
            bool idle = !busy && !scanning;
            refresh.IsEnabled = idle; oldPassword.IsEnabled = newPassword.IsEnabled = confirmation.IsEnabled = consent.IsEnabled = idle && !finished;
            close.Content = idle ? "닫기" : "취소"; close.IsEnabled = !cancelRequested || idle;
            progress.Visibility = idle ? Visibility.Collapsed : Visibility.Visible; progress.IsIndeterminate = !idle;
            bool hasFiles = discovery != null && discovery.Files.Count > 0;
            bool hasIssues = discovery != null && discovery.Issues.Count > 0;
            run.Content = !hasFiles && hasIssues ? "실패 기록 만들기" : BatchWorkflow.ModeLabel(mode);
            using (var old = oldPassword.SecurePassword) using (var next = newPassword.SecurePassword) using (var verify = confirmation.SecurePassword)
                run.IsEnabled = idle && !finished && (hasFiles || hasIssues) && consent.IsChecked == true &&
                    (!hasFiles || ((mode == "Encrypt" || old.Length > 0) && (mode == "Decrypt" || (next.Length > 0 && verify.Length > 0))));
        }

        async Task RefreshTargets()
        {
            if (busy || scanning) return;
            scanning = true; cancelRequested = false; finished = false; discovery = null; rows.Clear(); byPath.Clear(); ClearPasswords(); consent.IsChecked = false;
            runDirectory = null; reportPath = null; report.Visibility = records.Visibility = Visibility.Collapsed;
            if (scanCancel != null) scanCancel.Dispose(); scanCancel = new CancellationTokenSource();
            count.Text = "하위 폴더를 확인하는 중…"; SetStatus("파일 목록을 확인하고 있습니다. 아직 파일을 변경하지 않습니다.", false); UpdateControls();
            try
            {
                discovery = await Task.Run(delegate { return BatchWorkflow.Discover(folder, scanCancel.Token); });
                foreach (string path in discovery.Files) AddRow(path, "대기", "0", "");
                foreach (var issue in discovery.Issues) AddRow(issue.path, "확인 필요", "0", BatchWorkflow.Reason(issue.category));
                count.Text = "처리 대상 " + discovery.Files.Count + "개 · 확인 필요 " + discovery.Issues.Count + "개";
                SetStatus(discovery.Files.Count + discovery.Issues.Count == 0 ? "처리할 Excel 파일이 없습니다." : "목록을 확인하고 암호를 입력하세요. 새로 추가된 파일은 목록 새로고침 후 포함됩니다.", false);
            }
            catch (OperationCanceledException) { count.Text = "목록 확인 취소"; SetStatus("목록 확인을 취소했습니다. 파일을 변경하지 않았습니다.", false); }
            catch (Exception error) { count.Text = "폴더 확인 필요"; SetStatus(error is ArgumentException || error is DirectoryNotFoundException ? error.Message : "폴더를 읽지 못했습니다. 경로와 접근 권한을 확인하세요.", true); }
            finally { scanning = false; cancelRequested = false; UpdateControls(); }
        }
        void AddRow(string path, string state, string attempts, string detail)
        {
            string prefix = folder.TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
            var row = new BatchRow { Path = path, Name = path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ? path.Substring(prefix.Length) : path, State = state, Attempts = attempts, Detail = detail };
            rows.Add(row); byPath[path] = row;
        }

        async void ApplyClick(object sender, RoutedEventArgs e)
        {
            if (busy || scanning || discovery == null || finished) return;
            if (discovery.Files.Count > 0)
            {
                string error;
                using (var old = oldPassword.SecurePassword) using (var next = newPassword.SecurePassword) using (var verify = confirmation.SecurePassword)
                    error = Workflow.ValidatePasswords(mode, old, next, verify);
                if (error != null) { SetStatus(error, true); return; }
            }
            busy = true; cancelRequested = false; UpdateControls();
            try
            {
                BatchWorkflow.CheckDirectory(folder);
                runDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ExcelPasswordSafe", "Runs", Guid.NewGuid().ToString("N"));
                Workflow.CreatePrivateDirectory(runDirectory);
                string oldCipher, newCipher;
                using (var value = oldPassword.SecurePassword) oldCipher = Workflow.ProtectPassword(value);
                using (var value = newPassword.SecurePassword) newCipher = Workflow.ProtectPassword(value);
                ClearPasswords();
                var files = discovery.Files.Select(delegate(string path) { return new Dictionary<string, object> { { "path", path } }; }).ToArray();
                var request = new Dictionary<string, object> { { "schemaVersion", 1 }, { "root", folder }, { "mode", mode }, { "files", files }, { "discoveryIssues", discovery.Issues }, { "oldSecret", oldCipher }, { "newSecret", newCipher } };
                using (var owner = Process.GetCurrentProcess())
                {
                    request["ownerPid"] = owner.Id;
                    request["ownerStartTicks"] = owner.StartTime.ToUniversalTime().Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture);
                }
                var serializer = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue };
                File.WriteAllText(Path.Combine(runDirectory, "request.json"), serializer.Serialize(request), new UTF8Encoding(false));
                request.Clear(); oldCipher = newCipher = null;
                SetStatus("파일별로 원본을 백업하고 처리합니다. 실패한 파일은 안전한 경우 최대 3회 시도합니다.", false);
                timer.Start();
                await Task.Run(delegate { using (var process = Process.Start(BatchWorkflow.StartInfo(AppDomain.CurrentDomain.BaseDirectory, runDirectory))) process.WaitForExit(); });
                timer.Stop(); ReadProgress(); ReadResult();
            }
            catch
            {
                foreach (var row in rows.Where(delegate(BatchRow value) { return value.State == "처리 중"; })) { row.State = "확인 필요"; row.Detail = "결과 확인 후 다시 실행하세요."; }
                SetStatus("작업 결과를 확인하지 못했습니다. 다시 실행하기 전에 백업·기록을 확인하세요.", true);
            }
            finally
            {
                timer.Stop();
                if (runDirectory != null)
                {
                    try { File.Delete(Path.Combine(runDirectory, "request.json")); }
                    catch { SetStatus("작업 요청 파일을 정리하지 못했습니다. 백업·기록 보기에서 파일 접근 권한을 확인하세요.", true); }
                    records.Visibility = Visibility.Visible;
                }
                ClearPasswords(); consent.IsChecked = false; busy = false; finished = true; cancelRequested = false; UpdateControls();
            }
        }

        static string Value(IDictionary<string, object> values, string key) { object value; return values.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : ""; }
        static string StateLabel(string state)
        {
            switch (state) { case "Success": return "완료"; case "Skipped": return "건너뜀"; case "Failed": return "실패"; case "Cancelled": return "취소"; case "NotProcessed": return "미처리"; case "NeedsInspection": return "확인 필요"; default: return state; }
        }
        void ApplyItems(IDictionary<string, object> document)
        {
            object value;
            if (!document.TryGetValue("items", out value) || !(value is IEnumerable)) return;
            foreach (object item in (IEnumerable)value)
            {
                var data = item as IDictionary<string, object>; if (data == null) continue;
                string path = Value(data, "path");
                if (String.IsNullOrEmpty(path)) continue;
                BatchRow row;
                if (!byPath.TryGetValue(path, out row))
                {
                    AddRow(path, "대기", "0", "");
                    row = byPath[path];
                }
                row.State = StateLabel(Value(data, "status")); row.Attempts = Value(data, "attempts");
                row.Detail = BatchWorkflow.Reason(Value(data, "category"));
            }
        }
        void ReadProgress()
        {
            if (runDirectory == null) return;
            try
            {
                string itemsPath = Path.Combine(runDirectory, "items.json");
                if (File.Exists(itemsPath))
                {
                    var items = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(itemsPath));
                    ApplyItems(items);
                }
                string path = Path.Combine(runDirectory, "progress.json"); if (!File.Exists(path)) return;
                var document = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(path));
                ApplyItems(document);
                BatchRow row;
                if (byPath.TryGetValue(Value(document, "path"), out row) && (row.State == "대기" || row.State == "처리 중")) { row.State = "처리 중"; row.Attempts = Value(document, "attempt"); row.Detail = "파일 처리 및 저장 결과 확인"; }
                if (!cancelRequested) SetStatus("전체 " + Value(document, "total") + "개 중 " + Value(document, "index") + "번째 · " + Value(document, "attempt") + "/3회 시도\n" + (row == null ? "파일을 확인하고 있습니다." : row.Name), false);
            }
            catch { /* The atomic progress document may not be available yet. */ }
        }
        void ReadResult()
        {
            string path = Path.Combine(runDirectory, "result.json");
            if (!File.Exists(path)) { SetStatus("처리 결과가 없습니다. 다시 실행하기 전에 백업·기록을 확인하세요.", true); return; }
            var document = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(path));
            ApplyItems(document);
            string candidate = Value(document, "reportPath");
            if (!String.IsNullOrEmpty(candidate) && BatchWorkflow.ContainsPath(runDirectory, candidate) && Path.GetExtension(candidate).Equals(".xlsx", StringComparison.OrdinalIgnoreCase) && File.Exists(candidate))
            { reportPath = candidate; report.Visibility = Visibility.Visible; }
            string summary = "완료 " + rows.Count(delegate(BatchRow row) { return row.State == "완료"; }) + "개 · 실패/확인 " + rows.Count(delegate(BatchRow row) { return row.State == "실패" || row.State == "확인 필요"; }) + "개 · 건너뜀 " + rows.Count(delegate(BatchRow row) { return row.State == "건너뜀"; }) + "개 · 취소/미처리 " + rows.Count(delegate(BatchRow row) { return row.State == "취소" || row.State == "미처리" || row.State == "대기"; }) + "개";
            string category = Value(document, "category");
            if (category == "FailureReportFailed") summary += "\n" + BatchWorkflow.Reason(category);
            else if (reportPath != null) summary += "\n실패 보고서 열기에서 처리하지 못한 파일과 이유를 확인하세요.";
            else if (Value(document, "status") == "Cancelled") summary += "\n취소했습니다. 이미 완료된 파일은 유지합니다.";
            else if (Value(document, "status") == "Failed") summary += "\n" + BatchWorkflow.Reason(category);
            SetStatus(summary, Value(document, "status") == "Failed" || Value(document, "status") == "PartialFailure");
        }
        void RequestCancel()
        {
            cancelRequested = true;
            if (scanning && scanCancel != null) scanCancel.Cancel();
            if (busy && runDirectory != null)
            {
                try { File.WriteAllText(Path.Combine(runDirectory, "cancel"), "cancel", new UTF8Encoding(false)); }
                catch { cancelRequested = false; SetStatus("취소 요청을 저장하지 못했습니다. 잠시 후 다시 시도하세요.", true); UpdateControls(); return; }
            }
            SetStatus("취소를 요청했습니다. 진행 중인 파일의 확인이 끝나면 멈춥니다. 이미 완료된 파일은 유지합니다.", false); UpdateControls();
        }
        void OpenReport()
        {
            try { if (reportPath != null && File.Exists(reportPath)) Process.Start(new ProcessStartInfo(reportPath) { UseShellExecute = true }); }
            catch { SetStatus("실패 보고서를 열지 못했습니다. 백업·기록 보기에서 failure-report.xlsx를 확인하세요.", true); }
        }
        void OpenRecords()
        {
            try { if (runDirectory != null && Directory.Exists(runDirectory)) Process.Start(new ProcessStartInfo("explorer.exe", Workflow.QuoteArgument(runDirectory)) { UseShellExecute = false }); }
            catch { SetStatus("기록 폴더를 열지 못했습니다: " + runDirectory, true); }
        }

        public static BatchWindow Smoke(string state)
        {
            string mode = state == "Decrypt" ? "Decrypt" : state == "Encrypt" ? "Encrypt" : "ChangePassword";
            var window = new BatchWindow(@"D:\업무 자료\2026년", mode, true);
            window.discovery = new BatchDiscovery();
            foreach (string name in new[] { "예산.xlsx", @"1분기\정산.xlsx", @"2분기\매출.xlsm" })
            { string path = Path.Combine(window.folder, name); window.discovery.Files.Add(path); window.AddRow(path, "대기", "0", ""); }
            window.count.Text = "처리 대상 3개 · 하위 폴더 포함";
            window.consent.IsChecked = true; window.oldPassword.Password = "현재암호"; window.newPassword.Password = window.confirmation.Password = "새암호";
            window.SetStatus("목록의 3개 파일에 같은 암호를 적용합니다.", false);
            if (state == "Busy") { window.busy = true; window.ClearPasswords(); window.rows[0].State = "완료"; window.rows[0].Attempts = "1"; window.rows[1].State = "처리 중"; window.rows[1].Attempts = "2"; window.SetStatus("전체 3개 중 2번째 · 2/3회 시도\n1분기\\정산.xlsx", false); }
            if (state == "Failure") { window.finished = true; window.rows[0].State = window.rows[2].State = "완료"; window.rows[1].State = "실패"; window.rows[1].Attempts = "3"; window.rows[1].Detail = "현재 암호를 확인하세요."; window.report.Visibility = window.records.Visibility = Visibility.Visible; window.ClearPasswords(); window.consent.IsChecked = false; window.SetStatus("완료 2개 · 실패 1개\n실패 보고서에서 파일과 이유를 확인하세요.", true); }
            window.UpdateControls(); return window;
        }
        public void VerifySmokeLayout()
        {
            UpdateLayout();
            foreach (FrameworkElement element in new FrameworkElement[] { footer, run, close, status })
            {
                Rect bounds = element.TransformToAncestor(this).TransformBounds(new Rect(0, 0, element.ActualWidth, element.ActualHeight));
                if (bounds.Bottom > ActualHeight + 1 || bounds.Top < -1 || element.ActualHeight <= 0) throw new InvalidOperationException("Folder status/actions are clipped.");
            }
        }
        public void EndSmoke() { busy = false; scanning = false; Close(); }
    }
}
