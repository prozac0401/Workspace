using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace ExcelPasswordSafe
{
    public sealed class WizardWindow : Window
    {
        readonly StackPanel body = new StackPanel();
        readonly ScrollViewer scroller = new ScrollViewer();
        readonly TextBlock heading = new TextBlock(), subtitle = new TextBlock(), notice = new TextBlock();
        readonly Button primary = new Button(), secondary = new Button();
        readonly PasswordField current = new PasswordField("현재 암호"), next = new PasswordField("새 암호"), confirm = new PasswordField("새 암호 확인");
        readonly ObservableCollection<WorkItem> rows = new ObservableCollection<WorkItem>();
        readonly DispatcherTimer timer = new DispatcherTimer();
        readonly bool smoke;
        Action primaryAction, secondaryAction;
        string target, mode, runDirectory, reportPath, resultCategory, resultStatus;
        bool folder, contextEntry, busy, scanning, cancelRequested, unsafeResult;
        BatchDiscovery discovery;
        CancellationTokenSource scanCancel;
        TextBlock progressText;
        double pageHeight;
        public WizardStep Step { get; private set; }

        public WizardWindow(string selectedTarget, bool isFolder, string selectedMode, bool isSmoke = false)
        {
            target = selectedTarget; folder = isFolder; mode = selectedMode; smoke = isSmoke; contextEntry = selectedMode != null;
            // Explorer's background command appends \. so a drive root cannot
            // escape its closing command-line quote. Resolve that same folder.
            if (folder && target != null && target.Length >= 3 && Char.IsLetter(target[0]) && target[1] == ':' && (target[2] == '\\' || target[2] == '/'))
                target = Path.GetFullPath(target);
            Title = "Excel 암호 관리 · " + WizardRules.DisplayVersion;
            Width = 480; Height = 410; MinWidth = 420; MinHeight = 320;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Segoe UI, Malgun Gothic"); FontSize = 13;
            Foreground = Brush("#18243C"); Background = Brushes.White;
            Resources = AppTheme.Create();
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("ExcelPasswordSafe.AppIcon.ico"))
                if (stream != null) { var icon = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad); icon.Freeze(); Icon = icon; }
            var root = new DockPanel { Background = Brushes.White }; Content = root;
            var top = new StackPanel { Margin = new Thickness(26, 21, 26, 0) };
            DockPanel.SetDock(top, Dock.Top); root.Children.Add(top);
            var brand = new DockPanel { Margin = new Thickness(0, 0, 0, 14) };
            brand.Children.Add(new Image { Source = Icon, Width = 22, Height = 22, Margin = new Thickness(0, 0, 8, 0) });
            brand.Children.Add(new TextBlock { Text = "Excel 암호 관리", FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 });
            brand.Children.Add(new TextBlock { Text = "2", HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Foreground = Brush("#7C879D"), FontSize = 12 });
            top.Children.Add(brand);
            heading.FontSize = 23; heading.FontWeight = FontWeights.SemiBold; heading.TextWrapping = TextWrapping.Wrap;
            subtitle.FontSize = 12; subtitle.Foreground = Brush("#69758A"); subtitle.TextWrapping = TextWrapping.Wrap; subtitle.Margin = new Thickness(0, 7, 0, 14);
            top.Children.Add(heading); top.Children.Add(subtitle);
            var footer = new Border { BorderBrush = Brush("#E8ECF3"), BorderThickness = new Thickness(0, 1, 0, 0), Background = Brush("#FBFCFE"), Padding = new Thickness(22, 14, 22, 14) };
            DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
            var commands = new DockPanel { LastChildFill = false }; footer.Child = commands;
            primary.Style = (Style)Resources["PrimaryButton"]; primary.MinWidth = 100; primary.IsDefault = true;
            primary.Click += delegate { if (primaryAction != null) primaryAction(); };
            secondary.Style = (Style)Resources["QuietButton"];
            secondary.Click += delegate { if (secondaryAction != null) secondaryAction(); };
            DockPanel.SetDock(primary, Dock.Right); commands.Children.Add(primary); commands.Children.Add(secondary);
            scroller.VerticalScrollBarVisibility = ScrollBarVisibility.Auto; scroller.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            scroller.Margin = new Thickness(26, 0, 26, 16); scroller.Content = body; root.Children.Add(scroller);
            notice.FontSize = 12; notice.TextWrapping = TextWrapping.Wrap; notice.Margin = new Thickness(0, 8, 0, 0);
            AutomationProperties.SetLiveSetting(notice, AutomationLiveSetting.Polite);
            foreach (var field in new[] { current, next, confirm }) field.ValueChanged += delegate { if (Step == WizardStep.Input) { SetNotice(null, false); UpdateInputButton(); } };
            timer.Interval = TimeSpan.FromMilliseconds(350); timer.Tick += delegate { ReadProgress(); };
            Closing += delegate(object sender, CancelEventArgs e) { if (busy || scanning) { e.Cancel = true; RequestCancel(); } };
            Closed += delegate { timer.Stop(); ClearPasswords(); if (scanCancel != null) scanCancel.Dispose(); };
            PreviewKeyDown += delegate(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) { if (busy || scanning) RequestCancel(); else Close(); e.Handled = true; } };
            KeyboardNavigation.SetTabNavigation(root, KeyboardNavigationMode.Cycle);
            if (!smoke) Loaded += async delegate { if (String.IsNullOrEmpty(target)) ShowTarget(); else await PrepareTarget(); };
        }

        static Brush Brush(string color) { return (Brush)new BrushConverter().ConvertFromString(color); }
        static TextBlock Text(string value, double size = 12) { return new TextBlock { Text = value, FontSize = size, TextWrapping = TextWrapping.Wrap }; }
        static void Detach(UIElement element) { var parent = LogicalTreeHelper.GetParent(element) as Panel; if (parent != null) parent.Children.Remove(element); }
        void Page(WizardStep value, string title, string description, double height)
        {
            Step = value; body.Children.Clear(); Detach(notice);
            heading.Text = title; subtitle.Text = description; notice.Text = ""; notice.Visibility = Visibility.Collapsed;
            primaryAction = secondaryAction = null; primary.IsEnabled = true; secondary.IsEnabled = true;
            primary.Visibility = secondary.Visibility = Visibility.Visible;
            pageHeight = height; FitHeight(height);
        }
        void FitHeight(double value)
        {
            if (smoke) { Height = value; return; }
            Rect area = SystemParameters.WorkArea;
            MinHeight = Math.Min(320, area.Height); MinWidth = Math.Min(420, area.Width);
            Width = Math.Min(Width, area.Width); Height = Math.Min(value, area.Height);
            if (IsLoaded) { Top = Math.Max(area.Top, Math.Min(Top, area.Bottom - Height)); Left = Math.Max(area.Left, Math.Min(Left, area.Right - Width)); }
        }
        void Commands(string first, Action action, string back, Action previous)
        {
            primary.Content = first; primaryAction = action; primary.Visibility = first == null ? Visibility.Collapsed : Visibility.Visible;
            secondary.Content = back; secondaryAction = previous; secondary.Visibility = back == null ? Visibility.Collapsed : Visibility.Visible;
        }
        void SetNotice(string message, bool error)
        {
            notice.Text = message ?? ""; notice.Foreground = error ? Brushes.Firebrick : Brush("#69758A"); notice.Visibility = String.IsNullOrEmpty(message) ? Visibility.Collapsed : Visibility.Visible;
        }
        void ClearPasswords() { current.Clear(); next.Clear(); confirm.Clear(); }
        void ResetRun() { runDirectory = reportPath = resultCategory = resultStatus = null; unsafeResult = false; cancelRequested = false; ClearPasswords(); }
        void TargetCard(string detail)
        {
            var panel = new StackPanel();
            string name = Path.GetFileName((target ?? "").TrimEnd('\\', '/'));
            if (String.IsNullOrEmpty(name)) name = target;
            var title = new TextBlock { Text = name, FontWeight = FontWeights.SemiBold, FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = target };
            panel.Children.Add(title);
            var caption = Text(detail, 11); caption.Foreground = Brush("#69758A"); caption.Margin = new Thickness(0, 5, 0, 0); panel.Children.Add(caption);
            body.Children.Add(new Border { Background = Brush("#F4F6FB"), CornerRadius = new CornerRadius(9), Padding = new Thickness(13, 10, 13, 10), Margin = new Thickness(0, 0, 0, 13), Child = panel, ToolTip = target });
        }
        Button Choice(string title, string caption, Action action)
        {
            var label = new StackPanel(); label.Children.Add(Text(title, 14));
            if (!String.IsNullOrEmpty(caption)) { var description = Text(caption, 11); description.Foreground = Brush("#69758A"); description.Margin = new Thickness(0, 3, 0, 0); label.Children.Add(description); }
            var button = new Button { Content = label, HorizontalContentAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 9), Padding = new Thickness(16, 10, 16, 10) };
            AutomationProperties.SetName(button, title); button.Click += delegate { action(); }; return button;
        }
        void ShowTarget()
        {
            ResetRun(); discovery = null; rows.Clear(); mode = null; contextEntry = false;
            Page(WizardStep.Target, "어디에 적용할까요?", "Excel 파일 하나 또는 폴더를 선택하세요.", 395);
            body.Children.Add(Choice("파일 선택", ".xlsx · .xlsm · .xlsb · .xls", delegate { PickTarget(false); }));
            body.Children.Add(Choice("폴더 선택", "하위 폴더의 Excel 파일까지 함께 처리", delegate { PickTarget(true); }));
            body.Children.Add(notice); Commands(null, null, "닫기", Close);
        }
        async void PickTarget(bool selectFolder)
        {
            try
            {
                string chosen = null;
                if (selectFolder) chosen = FolderPicker.Pick(this);
                else { var dialog = new OpenFileDialog { Title = "Excel 파일 선택", Filter = "Excel 파일|*.xlsx;*.xlsm;*.xlsb;*.xls", CheckFileExists = true, Multiselect = false }; if (dialog.ShowDialog(this) == true) chosen = dialog.FileName; }
                if (chosen == null) return;
                target = Path.GetFullPath(chosen); folder = selectFolder; if (!contextEntry) mode = null; await PrepareTarget();
            }
            catch { SetNotice("선택 창을 열지 못했습니다. 다시 시도하세요.", true); }
        }
        async Task PrepareTarget()
        {
            ResetRun(); discovery = null; rows.Clear();
            if (!folder)
            {
                string error = Workflow.ValidateFile(target);
                if (error != null) { ShowTarget(); SetNotice(error, true); return; }
                discovery = new BatchDiscovery(); discovery.Files.Add(target); AddItem(target, "Pending", "", "0");
                if (mode == null) ShowOperation(); else ShowInput(); return;
            }
            scanning = true; cancelRequested = false;
            Page(WizardStep.Progress, "Excel 파일 확인 중", "하위 폴더까지 찾고 있습니다.", 345);
            TargetCard("파일을 변경하지 않습니다."); body.Children.Add(notice);
            Commands("취소", RequestCancel, null, null);
            if (scanCancel != null) scanCancel.Dispose(); scanCancel = new CancellationTokenSource();
            try
            {
                discovery = await Task.Run(delegate { return BatchWorkflow.Discover(target, scanCancel.Token); });
                foreach (var path in discovery.Files) AddItem(path, "Pending", "", "0");
                foreach (var issue in discovery.Issues) AddItem(issue.path, "Failed", issue.category, "0");
            }
            catch (OperationCanceledException) { discovery = null; }
            catch (Exception error)
            {
                scanning = false; ShowTarget(); SetNotice(error is ArgumentException || error is DirectoryNotFoundException ? error.Message : "폴더를 읽지 못했습니다. 위치와 접근 권한을 확인하세요.", true); return;
            }
            finally { scanning = false; }
            if (discovery == null) { ShowTarget(); SetNotice("목록 확인을 취소했습니다.", false); }
            else if (rows.Count == 0) ShowEmpty();
            else if (mode == null) ShowOperation(); else ShowInput();
        }
        void ShowEmpty()
        {
            Page(WizardStep.Result, "Excel 파일이 없습니다", "지원하는 Excel 파일이 있는 폴더를 선택하세요.", 340);
            TargetCard("하위 폴더까지 확인했습니다.");
            Commands("다른 폴더 선택", delegate { PickTarget(true); }, "닫기", Close);
        }
        void ShowOperation()
        {
            ClearPasswords(); Page(WizardStep.Operation, "어떤 작업을 할까요?", folder ? "선택한 폴더의 Excel 파일에 적용합니다." : "파일의 열기 암호를 관리합니다.", 480);
            TargetCard(folder ? "Excel " + discovery.Files.Count + "개 · 하위 폴더 포함" : "선택한 파일 하나에 적용");
            body.Children.Add(Choice("암호 설정", null, delegate { mode = "Encrypt"; ShowInput(); }));
            body.Children.Add(Choice("암호 해제", null, delegate { mode = "Decrypt"; ShowInput(); }));
            body.Children.Add(Choice("암호 변경", null, delegate { mode = "ChangePassword"; ShowInput(); }));
            Commands(null, null, "다른 대상 선택", ShowTarget);
        }
        void ShowInput()
        {
            Page(WizardStep.Input, BatchWorkflow.ModeLabel(mode), folder ? "선택한 모든 파일에 같은 암호를 적용합니다." : mode == "Encrypt" ? "새 암호를 입력하세요." : "현재 파일의 암호를 입력하세요.", (mode == "ChangePassword" ? 525 : 445) + (folder ? 30 : 0));
            TargetCard(folder ? "Excel " + discovery.Files.Count + "개 · 하위 폴더 포함" : "원본 파일에 적용 · 백업 자동 보관");
            if (folder) AddDetails("대상 " + rows.Count + "개 보기");
            if (discovery.Files.Count > 0)
            {
                if (mode != "Encrypt") { Detach(current); current.Margin = new Thickness(0, 0, 0, 12); body.Children.Add(current); }
                if (mode != "Decrypt")
                {
                    var pair = new UniformGrid { Columns = 2 };
                    Detach(next); Detach(confirm); next.Margin = new Thickness(0, 0, 6, 12); confirm.Margin = new Thickness(6, 0, 0, 12); pair.Children.Add(next); pair.Children.Add(confirm); body.Children.Add(pair);
                }
                var reveal = new CheckBox { Content = "암호 표시", FontSize = 11, Foreground = Brush("#69758A"), Margin = new Thickness(0, 0, 0, 12) };
                reveal.Checked += delegate { current.Reveal(true); next.Reveal(true); confirm.Reveal(true); };
                reveal.Unchecked += delegate { current.Reveal(false); next.Reveal(false); confirm.Reveal(false); };
                body.Children.Add(reveal);
                var hint = Text(mode == "Decrypt" ? "원본을 백업한 뒤 열기 암호를 해제합니다." : "새 암호 1~15자 · 원본을 백업한 뒤 적용합니다.", 11); hint.Foreground = Brush("#69758A"); body.Children.Add(hint);
            }
            else body.Children.Add(Text("파일 목록을 읽지 못한 위치를 실패 보고서로 남깁니다. 암호 입력은 필요하지 않습니다."));
            body.Children.Add(notice);
            Commands(discovery.Files.Count == 0 ? "실패 기록 만들기" : BatchWorkflow.ModeLabel(mode), Execute, contextEntry ? "취소" : "뒤로", contextEntry ? (Action)Close : ShowOperation);
            UpdateInputButton();
            Dispatcher.BeginInvoke(new Action(delegate { if (Step == WizardStep.Input) { if (mode == "Encrypt") next.FocusInput(); else current.FocusInput(); } }), DispatcherPriority.Input);
        }
        void UpdateInputButton()
        {
            if (Step != WizardStep.Input || discovery == null) return;
            primary.IsEnabled = discovery.Files.Count == 0 || ((mode == "Encrypt" || current.Length > 0) && (mode == "Decrypt" || (next.Length > 0 && confirm.Length > 0)));
        }
        void AddDetails(string label)
        {
            var expander = new Expander { Header = label, FontSize = 11, Foreground = Brush("#69758A"), Margin = new Thickness(0, 0, 0, 13) };
            var detail = new StackPanel(); var list = new ListBox { ItemsSource = rows, Height = 145, Margin = new Thickness(0, 8, 0, 5), BorderBrush = Brush("#E3E8F1"), BorderThickness = new Thickness(1), Background = Brushes.White, HorizontalContentAlignment = HorizontalAlignment.Stretch };
            var rowPanel = new FrameworkElementFactory(typeof(StackPanel)); rowPanel.SetValue(StackPanel.MarginProperty, new Thickness(5, 5, 5, 5)); rowPanel.SetBinding(StackPanel.ToolTipProperty, new Binding("FullDescription"));
            var name = new FrameworkElementFactory(typeof(TextBlock)); name.SetBinding(TextBlock.TextProperty, new Binding("Name")); name.SetValue(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis); name.SetValue(TextBlock.FontWeightProperty, FontWeights.SemiBold); rowPanel.AppendChild(name);
            var status = new FrameworkElementFactory(typeof(TextBlock)); status.SetBinding(TextBlock.TextProperty, new Binding("Caption")); status.SetBinding(TextBlock.ForegroundProperty, new Binding("Color")); status.SetValue(TextBlock.FontSizeProperty, 11.0); status.SetValue(TextBlock.MarginProperty, new Thickness(0, 4, 0, 0)); rowPanel.AppendChild(status);
            list.ItemTemplate = new DataTemplate { VisualTree = rowPanel };
            ScrollViewer.SetHorizontalScrollBarVisibility(list, ScrollBarVisibility.Disabled);
            var selected = new TextBox { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontSize = 11, MinHeight = 0, MaxHeight = 95, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(7), Style = null, BorderThickness = new Thickness(0), Background = Brushes.Transparent };
            AutomationProperties.SetName(list, "파일별 결과"); AutomationProperties.SetName(selected, "선택 항목의 전체 경로와 결과");
            list.SelectionChanged += delegate { var item = list.SelectedItem as WorkItem; selected.Text = item == null ? "" : item.FullDescription; };
            detail.Children.Add(list); detail.Children.Add(selected); expander.Content = detail;
            expander.Expanded += delegate { FitHeight(pageHeight + 230); }; expander.Collapsed += delegate { FitHeight(pageHeight); };
            body.Children.Add(expander);
        }
        WorkItem AddItem(string path, string state, string category, string attempts)
        {
            string prefix = folder ? target.TrimEnd('\\', '/') + Path.DirectorySeparatorChar : "";
            var item = new WorkItem { Path = path, Name = folder && path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ? path.Substring(prefix.Length) : Path.GetFileName(path), State = state, Category = category, Attempts = attempts };
            if (String.IsNullOrEmpty(item.Name)) item.Name = path; rows.Add(item); return item;
        }

        async void Execute()
        {
            if (busy || scanning || discovery == null) return;
            if (discovery.Files.Count > 0)
            {
                using (var old = current.Secret) using (var fresh = next.Secret) using (var verify = confirm.Secret)
                {
                    string error = Workflow.ValidatePasswords(mode, old, fresh, verify);
                    if (error != null)
                    {
                        PasswordField field = mode != "Encrypt" && old.Length == 0 ? current : mode != "Decrypt" && fresh.Length >= 1 && fresh.Length <= 15 && !Workflow.PasswordsEqual(fresh, verify) ? confirm : next;
                        field.SetError(error); field.FocusInput(); return;
                    }
                }
                var excel = Process.GetProcessesByName("EXCEL"); bool running = excel.Length > 0; foreach (var process in excel) process.Dispose();
                if (running) { SetNotice("Excel을 모두 닫고 다시 실행하세요. 입력한 암호는 유지됩니다.", true); return; }
                if (!folder) { string error = Workflow.ValidateFile(target); if (error != null) { SetNotice(error, true); return; } }
            }
            busy = true; cancelRequested = false; unsafeResult = false; runDirectory = reportPath = null;
            string oldCipher = null, newCipher = null;
            try
            {
                if (folder) BatchWorkflow.CheckDirectory(target);
                runDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ExcelPasswordSafe", "Runs", Guid.NewGuid().ToString("N"));
                Workflow.CreatePrivateDirectory(runDirectory);
                using (var value = current.Secret) oldCipher = Workflow.ProtectPassword(value);
                using (var value = next.Secret) newCipher = Workflow.ProtectPassword(value);
                ClearPasswords(); ShowProgress();
                var request = new Dictionary<string, object> { { "schemaVersion", 1 }, { "mode", mode }, { "oldSecret", oldCipher }, { "newSecret", newCipher } };
                if (folder)
                {
                    request["root"] = target; request["files"] = discovery.Files.Select(path => new Dictionary<string, object> { { "path", path } }).ToArray(); request["discoveryIssues"] = discovery.Issues;
                    using (var owner = Process.GetCurrentProcess()) { request["ownerPid"] = owner.Id; request["ownerStartTicks"] = owner.StartTime.ToUniversalTime().Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture); }
                }
                else { request["path"] = target; request["expectedHash"] = await Task.Run(delegate { return Workflow.Hash(target); }); }
                File.WriteAllText(Path.Combine(runDirectory, "request.json"), Serializer().Serialize(request), new UTF8Encoding(false)); request.Clear(); oldCipher = newCipher = null;
                timer.Start();
                await Task.Run(delegate { using (var process = Process.Start(folder ? BatchWorkflow.StartInfo(AppDomain.CurrentDomain.BaseDirectory, runDirectory) : Workflow.EngineStartInfo(AppDomain.CurrentDomain.BaseDirectory, runDirectory))) process.WaitForExit(); });
                timer.Stop(); ReadProgress(); ReadResult();
            }
            catch { MarkUncertain("MissingResult"); }
            finally
            {
                timer.Stop(); oldCipher = newCipher = null;
                if (runDirectory != null) { try { File.Delete(Path.Combine(runDirectory, "request.json")); } catch { MarkUncertain("TemporaryCleanupIncomplete"); } }
                ClearPasswords(); busy = false; cancelRequested = false; ShowResult();
            }
        }
        void ShowProgress()
        {
            Page(WizardStep.Progress, BatchWorkflow.ModeLabel(mode) + " 중", "파일을 백업하고 저장 결과를 확인합니다.", 355);
            TargetCard(folder ? "Excel " + discovery.Files.Count + "개 · 안전한 실패는 최대 3회 시도" : "검증이 끝나면 원본에 적용합니다.");
            body.Children.Add(new ProgressBar { Height = 3, IsIndeterminate = true, Foreground = Brush("#3659D9"), Background = Brush("#EDF1F9"), Margin = new Thickness(0, 0, 0, 13) });
            progressText = Text("작업을 준비하고 있습니다."); progressText.Foreground = Brush("#69758A"); body.Children.Add(progressText); body.Children.Add(notice);
            Commands("취소", RequestCancel, null, null);
        }
        static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }; }
        static Dictionary<string, object> ReadDocument(string path) { return Serializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(path)); }
        static string Value(IDictionary<string, object> values, string key) { object value; return values.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : ""; }
        void ApplyItems(IDictionary<string, object> document)
        {
            object items; if (!document.TryGetValue("items", out items)) return;
            foreach (object raw in (IEnumerable)items)
            {
                var item = raw as IDictionary<string, object>; if (item == null) continue;
                string path = Value(item, "path"); var row = rows.FirstOrDefault(value => String.Equals(value.Path, path, StringComparison.OrdinalIgnoreCase));
                if (row == null) row = AddItem(path, "Pending", "", "0");
                row.State = Value(item, "status"); row.Category = Value(item, "category"); row.Attempts = Value(item, "attempts");
                if (WizardRules.NeedsInspection(row.Category) || row.State == "NeedsInspection") unsafeResult = true;
            }
        }
        void ReadProgress()
        {
            if (runDirectory == null) return;
            try
            {
                string items = Path.Combine(runDirectory, "items.json"); if (folder && File.Exists(items)) ApplyItems(ReadDocument(items));
                string path = Path.Combine(runDirectory, "progress.json"); if (!File.Exists(path)) return; var data = ReadDocument(path);
                if (folder)
                {
                    string active = Value(data, "path"); var row = rows.FirstOrDefault(item => String.Equals(item.Path, active, StringComparison.OrdinalIgnoreCase));
                    if (row != null && (row.State == "Pending" || row.State == "Processing")) { row.State = "Processing"; row.Attempts = Value(data, "attempt"); }
                    if (!cancelRequested && progressText != null) progressText.Text = Value(data, "index") + " / " + Value(data, "total") + "개 · " + Value(data, "attempt") + "/3회 시도\n" + (row == null ? "처리 결과 확인 중" : row.Name);
                }
                else if (!cancelRequested && progressText != null) progressText.Text = "백업 · 암호 처리 · 재열기 확인\n" + Path.GetFileName(target);
            }
            catch { /* Atomic progress updates are advisory; final result is required. */ }
        }
        void ReadResult()
        {
            string path = Path.Combine(runDirectory, "result.json"); if (!File.Exists(path)) { MarkUncertain("MissingResult"); return; }
            var result = ReadDocument(path);
            if (!ResultDocument.IsValid(result, folder, discovery.Files)) { MarkUncertain("MissingResult"); return; }
            resultStatus = Value(result, "status"); resultCategory = Value(result, "category");
            if (folder)
            {
                ApplyItems(result);
                string report = Value(result, "reportPath");
                if (!String.IsNullOrEmpty(report) && BatchWorkflow.ContainsPath(runDirectory, report) && Path.GetExtension(report).Equals(".xlsx", StringComparison.OrdinalIgnoreCase) && File.Exists(report)) reportPath = report;
                if (rows.Any(row => row.State == "Pending" || row.State == "Processing")) MarkUncertain("MissingResult");
            }
            else
            {
                var row = rows[0]; row.State = resultStatus; row.Category = resultCategory; row.Attempts = "1";
            }
            if (WizardRules.NeedsInspection(resultCategory)) unsafeResult = true;
            if (Value(result, "message") == "TemporaryCleanupIncomplete") MarkUncertain("TemporaryCleanupIncomplete");
        }
        void MarkUncertain(string category)
        {
            unsafeResult = true; resultStatus = "Failed"; resultCategory = category;
            var affected = rows.Where(item => item.State == "Pending" || item.State == "Processing").ToArray();
            if (affected.Length == 0) AddItem(target, "NeedsInspection", category, "0");
            else foreach (var row in affected) { row.State = "NeedsInspection"; row.Category = category; }
        }
        void RequestCancel()
        {
            if (cancelRequested) return;
            if (scanning && scanCancel != null) scanCancel.Cancel();
            if (busy && runDirectory != null)
            {
                try { File.WriteAllText(Path.Combine(runDirectory, "cancel"), "cancel", new UTF8Encoding(false)); }
                catch { SetNotice("취소 요청을 저장하지 못했습니다. 잠시 후 다시 시도하세요.", true); return; }
            }
            cancelRequested = true; primary.IsEnabled = false; primary.Content = "취소 중…";
            SetNotice("현재 파일의 확인이 끝나면 멈춥니다. 완료된 파일은 유지됩니다.", false);
        }
        void ShowResult()
        {
            int success = rows.Count(item => item.State == "Success"), skipped = rows.Count(item => item.State == "Skipped"), failed = rows.Count(item => item.State == "Failed" || item.State == "NeedsInspection"), remaining = rows.Count(item => item.State == "Cancelled" || item.State == "NotProcessed");
            bool cancelled = resultStatus == "Cancelled";
            string title = unsafeResult ? "기록 확인이 필요합니다" : cancelled ? "작업을 취소했습니다" : failed > 0 || remaining > 0 || resultStatus == "Failed" ? (folder ? "일부 파일을 처리하지 못했습니다" : "파일을 처리하지 못했습니다") : skipped > 0 && success == 0 ? "파일을 변경하지 않았습니다" : "작업을 마쳤습니다";
            Page(WizardStep.Result, title, unsafeResult ? "다시 실행하기 전에 백업과 현재 파일을 확인하세요." : "처리 결과를 확인하세요.", 440);
            var summary = Text("완료 " + success + "   ·   건너뜀 " + skipped + "   ·   실패 " + failed + (remaining > 0 ? "   ·   미처리 " + remaining : ""), 13); summary.FontWeight = FontWeights.SemiBold; summary.Margin = new Thickness(0, 0, 0, 15); body.Children.Add(summary);
            if (!folder && rows.Count > 0) { var message = Text(rows[0].State == "Success" ? BatchWorkflow.ModeLabel(mode) + "을 완료했습니다. 원본 백업은 기록 폴더에 보관했습니다." : rows[0].Detail); message.Margin = new Thickness(0, 0, 0, 12); body.Children.Add(message); }
            if (resultCategory == "FailureReportFailed") { var message = Text(BatchWorkflow.Reason(resultCategory)); message.Foreground = Brushes.Firebrick; body.Children.Add(message); }
            AddDetails("파일별 결과 " + rows.Count + "개 보기");
            var links = new WrapPanel(); body.Children.Add(links);
            if (reportPath != null) links.Children.Add(Link("실패 보고서 열기", delegate { OpenPath(reportPath, false); }));
            if (runDirectory != null) links.Children.Add(Link("백업·기록 보기", delegate { OpenPath(runDirectory, true); }));
            var retry = discovery == null || unsafeResult ? new string[0] : WizardRules.RetryPaths(rows, discovery.Files);
            if (retry.Length > 0)
            {
                body.Children.Add(Link("실패 " + retry.Length + "개 다시 시도", delegate
                {
                    ResetRun(); discovery = new BatchDiscovery(); discovery.Files.AddRange(retry); rows.Clear(); foreach (var path in retry) AddItem(path, "Pending", "", "0"); ShowInput();
                }));
            }
            if (!folder && !unsafeResult && (resultCategory == "AlreadyEncrypted" || resultCategory == "AlreadyUnencrypted" || resultCategory == "NotEncrypted"))
            {
                string destination = resultCategory == "AlreadyEncrypted" ? "ChangePassword" : "Encrypt";
                body.Children.Add(Link(BatchWorkflow.ModeLabel(destination) + "으로 이동", async delegate { mode = destination; await PrepareTarget(); }));
            }
            body.Children.Add(notice);
            Commands("닫기", Close, contextEntry ? null : "다른 작업", async delegate { mode = null; await PrepareTarget(); });
        }
        Button Link(string caption, Action action)
        {
            var button = new Button { Content = caption, Style = (Style)Resources["QuietButton"], HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(0, 7, 12, 7), MinHeight = 30 };
            button.Click += delegate { action(); }; return button;
        }
        void OpenPath(string path, bool directory)
        {
            try { if (directory) Process.Start(new ProcessStartInfo("explorer.exe", Workflow.QuoteArgument(path)) { UseShellExecute = false }); else Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
            catch { SetNotice("열지 못했습니다. 기록 위치를 확인하세요: " + path, true); }
        }

        public void RenderSmoke(string state)
        {
            target = @"D:\업무 자료\월간 결산"; folder = state.StartsWith("folder-", StringComparison.Ordinal) || new[] { "progress", "success", "failure", "inspection", "empty", "details" }.Contains(state);
            contextEntry = state != "target" && state != "operation";
            if (!folder) target += @"\매출 현황.xlsx";
            mode = state.Contains("decrypt") ? "Decrypt" : state.Contains("change") ? "ChangePassword" : "Encrypt";
            discovery = new BatchDiscovery(); rows.Clear();
            string first = folder ? target + @"\매출 현황.xlsx" : target;
            discovery.Files.Add(first); AddItem(first, "Pending", "", "0");
            if (folder) { discovery.Files.Add(target + @"\부서별\상세 내역.xlsx"); AddItem(discovery.Files[1], "Pending", "", "0"); }
            if (state == "target") ShowTarget();
            else if (state == "operation") ShowOperation();
            else if (state == "empty") ShowEmpty();
            else if (state == "progress") { ShowProgress(); progressText.Text = "1 / 2개 · 2/3회 시도\n부서별\\상세 내역.xlsx"; }
            else if (new[] { "success", "failure", "inspection", "details" }.Contains(state))
            {
                rows[0].State = "Success"; rows[0].Category = "ReplacedAndVerified"; rows[0].Attempts = "1";
                rows[1].State = state == "success" ? "Success" : state == "inspection" ? "NeedsInspection" : "Failed";
                rows[1].Category = state == "success" ? "ReplacedAndVerified" : state == "inspection" ? "CommitUncertain" : "OpenFailedPossiblePasswordOrCorruption"; rows[1].Attempts = "3";
                unsafeResult = state == "inspection"; resultStatus = state == "success" ? "Success" : "PartialFailure";
                runDirectory = @"C:\Users\사용자\AppData\Local\ExcelPasswordSafe\Runs\sample"; reportPath = state == "success" ? null : runDirectory + @"\failure-report.xlsx"; ShowResult();
                if (state == "details") foreach (var expander in body.Children.OfType<Expander>()) expander.IsExpanded = true;
            }
            else
            {
                ShowInput(); current.SetSmokePassword("Current42!"); next.SetSmokePassword("Next42!"); confirm.SetSmokePassword(state == "input-error" ? "Different" : "Next42!");
                if (state == "input-error") confirm.SetError("새 암호와 확인 입력이 서로 다릅니다.");
            }
        }
        public void CheckLayout()
        {
            UpdateLayout();
            if (Step == WizardStep.Operation && Width >= 480 && Height >= 480 && scroller.ScrollableHeight > 0.1)
                throw new InvalidOperationException("Operation choices must fit without a scrollbar.");
            foreach (FrameworkElement element in new FrameworkElement[] { heading, primary, secondary })
            {
                if (element.Visibility != Visibility.Visible) continue;
                Point position = element.TranslatePoint(new Point(0, 0), (UIElement)Content);
                var area = (FrameworkElement)Content;
                if (element.ActualWidth <= 0 || element.ActualHeight <= 0 || position.X < -1 || position.Y < -1 || position.X + element.ActualWidth > area.ActualWidth + 1 || position.Y + element.ActualHeight > area.ActualHeight + 1) throw new InvalidOperationException("Wizard navigation was clipped: " + Step);
            }
        }
        public void FinishSmoke() { busy = scanning = false; Close(); }
    }
}
