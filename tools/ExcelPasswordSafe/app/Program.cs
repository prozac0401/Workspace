using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace ExcelPasswordSafe
{
    public static class Workflow
    {
        public static string QuoteArgument(string value)
        {
            var result = new StringBuilder("\"");
            int slashes = 0;
            foreach (char ch in value)
            {
                if (ch == '\\') { slashes++; continue; }
                if (ch == '"') result.Append('\\', slashes * 2 + 1);
                else result.Append('\\', slashes);
                result.Append(ch); slashes = 0;
            }
            return result.Append('\\', slashes * 2).Append('"').ToString();
        }

        // Same wire format as Windows PowerShell ConvertFrom-SecureString (no key).
        public static string ProtectPassword(SecureString password)
        {
            if (password.Length == 0) return "";
            IntPtr pointer = Marshal.SecureStringToBSTR(password);
            var bytes = new byte[password.Length * 2];
            try
            {
                Marshal.Copy(pointer, bytes, 0, bytes.Length);
                byte[] encrypted = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
                try { return BitConverter.ToString(encrypted).Replace("-", "").ToLowerInvariant(); }
                finally { Array.Clear(encrypted, 0, encrypted.Length); }
            }
            finally { Array.Clear(bytes, 0, bytes.Length); Marshal.ZeroFreeBSTR(pointer); }
        }

        public static bool PasswordsEqual(SecureString left, SecureString right)
        {
            if (left.Length != right.Length) return false;
            IntPtr a = Marshal.SecureStringToBSTR(left), b = Marshal.SecureStringToBSTR(right);
            try
            {
                int difference = 0;
                for (int i = 0; i < left.Length * 2; i++) difference |= Marshal.ReadByte(a, i) ^ Marshal.ReadByte(b, i);
                return difference == 0;
            }
            finally { Marshal.ZeroFreeBSTR(a); Marshal.ZeroFreeBSTR(b); }
        }

        public static string ValidatePasswords(string mode, SecureString oldPassword, SecureString newPassword, SecureString confirmation)
        {
            if (mode != "Encrypt" && mode != "Decrypt" && mode != "ChangePassword") return "작업을 선택하세요.";
            if (mode != "Encrypt" && oldPassword.Length == 0) return "현재 암호를 입력하세요.";
            if (mode != "Decrypt")
            {
                if (newPassword.Length < 1 || newPassword.Length > 15) return "새 암호는 1~15자로 입력하세요.";
                if (!PasswordsEqual(newPassword, confirmation)) return "새 암호와 확인 입력이 서로 다릅니다.";
                if (mode == "ChangePassword" && PasswordsEqual(oldPassword, newPassword)) return "현재 암호와 다른 새 암호를 입력하세요.";
            }
            return null;
        }

        public static string ValidateFile(string path)
        {
            try { return ValidateFileCore(path); }
            catch (UnauthorizedAccessException) { return "파일 접근 권한을 확인하고 다시 선택하세요."; }
            catch (IOException) { return "파일이나 드라이브에 접근할 수 없습니다. 위치를 확인하고 다시 선택하세요."; }
            catch (ArgumentException) { return "파일 경로가 올바르지 않습니다. 파일을 다시 선택하세요."; }
            catch (System.Security.SecurityException) { return "이 파일에 접근할 권한이 없습니다."; }
        }

        static string ValidateFileCore(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) return "Excel 파일 하나를 선택하세요.";
            if (path.Length < 3 || !Char.IsLetter(path[0]) || path[1] != ':' || (path[2] != '\\' && path[2] != '/'))
                return "로컬 드라이브의 Excel 파일을 선택하세요. 네트워크 경로는 지원하지 않습니다.";
            var drive = new DriveInfo(Path.GetPathRoot(path));
            if (drive.DriveType != DriveType.Fixed || !String.Equals(drive.DriveFormat, "NTFS", StringComparison.OrdinalIgnoreCase))
                return "로컬 고정 NTFS 드라이브의 파일을 선택하세요.";
            string extension = Path.GetExtension(path).ToLowerInvariant();
            if (extension != ".xls" && extension != ".xlsx" && extension != ".xlsm" && extension != ".xlsb")
                return "지원 형식은 .xls, .xlsx, .xlsm, .xlsb입니다.";
            if (!File.Exists(path)) return "파일을 찾을 수 없습니다. 위치를 확인하고 다시 선택하세요.";
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.Offline) != 0) return "오프라인 파일입니다. 별도 로컬 폴더에 복사한 뒤 선택하세요.";
            if ((attributes & FileAttributes.ReadOnly) != 0) return "읽기 전용 파일입니다. 파일 속성과 저장 권한을 확인하세요.";
            FileSystemInfo entry = new FileInfo(path);
            while (entry != null)
            {
                if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) return "연결·동기화 경로는 지원하지 않습니다. 별도 로컬 폴더의 파일을 선택하세요.";
                var file = entry as FileInfo;
                entry = file != null ? file.Directory : ((DirectoryInfo)entry).Parent;
            }
            if (Path.GetFileName(path).StartsWith("~$", StringComparison.Ordinal) || Path.GetFileName(path).StartsWith(".eps-", StringComparison.OrdinalIgnoreCase))
                return "작업용 임시 파일은 선택할 수 없습니다. 원본 Excel 파일을 선택하세요.";
            return null;
        }

        public static void CreatePrivateDirectory(string path)
        {
            var acl = new DirectorySecurity();
            var sid = WindowsIdentity.GetCurrent().User;
            acl.SetAccessRuleProtection(true, false);
            acl.SetOwner(sid);
            var inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            acl.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            Directory.CreateDirectory(path, acl);
        }

        public static string Hash(string path)
        {
            using (var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
        }

        public static ProcessStartInfo EngineStartInfo(string baseDirectory, string runDirectory)
        {
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            return new ProcessStartInfo(powershell,
                "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File " + QuoteArgument(Path.Combine(baseDirectory, @"runtime\Engine.ps1")) +
                " -RequestPath " + QuoteArgument(Path.Combine(runDirectory, "request.json")))
            { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = baseDirectory };
        }
    }

    public sealed class PasswordWindow : Window
    {
        readonly TextBox filePath = new TextBox();
        readonly Button browse = new Button();
        readonly RadioButton encrypt = new RadioButton(), decrypt = new RadioButton(), change = new RadioButton();
        readonly PasswordBox oldPassword = new PasswordBox(), newPassword = new PasswordBox(), confirmPassword = new PasswordBox();
        readonly StackPanel oldField = new StackPanel(), newField = new StackPanel(), confirmField = new StackPanel();
        readonly TextBlock explanation = new TextBlock(), status = new TextBlock(), backupNote = new TextBlock();
        readonly TextBlock fileName = new TextBlock(), fileType = new TextBlock(), statusCaption = new TextBlock();
        readonly Border statusCard = new Border(), statusDot = new Border();
        readonly CheckBox consent = new CheckBox();
        readonly Button apply = new Button(), close = new Button(), results = new Button();
        readonly ProgressBar progress = new ProgressBar();
        readonly DispatcherTimer timer = new DispatcherTimer();
        string runDirectory;
        bool busy, cancelRequested, statusIsError;
        string mode = "Encrypt";
        public string SmokeMode { get { return mode; } }

        public PasswordWindow(string selectedFile)
        {
            Title = "Excel 암호 관리";
            double availableWidth = Math.Max(320, SystemParameters.WorkArea.Width - 24);
            double availableHeight = Math.Max(320, SystemParameters.WorkArea.Height - 24);
            Width = Math.Min(640, availableWidth); Height = Math.Min(760, availableHeight);
            MinWidth = Math.Min(520, availableWidth); MinHeight = Math.Min(520, availableHeight);
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Malgun Gothic"); FontSize = 13;
            UseLayoutRounding = true; SnapsToDevicePixels = true;
            Background = Brush("#F4F6FB"); Foreground = Brush("#17223B");
            Resources = AppTheme.Create();
            var root = new DockPanel { LastChildFill = true, Background = Brush("#F4F6FB") };
            Content = root;
            var header = new Border { Background = Brushes.White, Padding = new Thickness(26, 18, 26, 16), BorderBrush = Brush("#E2E8F2"), BorderThickness = new Thickness(0, 0, 0, 1) };
            DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
            var heading = new DockPanel(); header.Child = heading;
            var brand = new Border { Width = 46, Height = 48, CornerRadius = new CornerRadius(13), Background = Brush("#EDF1FE"), Margin = new Thickness(0, 0, 15, 0), VerticalAlignment = VerticalAlignment.Center };
            brand.Child = new System.Windows.Shapes.Path { Data = Geometry.Parse("M 6,10 L6,7 A6,6 0 0 1 18,7 L18,10 M5,10 L19,10 Q21,10 21,12 L21,21 Q21,23 19,23 L5,23 Q3,23 3,21 L3,12 Q3,10 5,10 Z M12,15 L12,18"), Stroke = Brush("#3659D9"), StrokeThickness = 1.7, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, Stretch = Stretch.Uniform, Width = 24, Height = 28 };
            DockPanel.SetDock(brand, Dock.Left); heading.Children.Add(brand);
            var title = new StackPanel(); heading.Children.Add(title);
            title.Children.Add(new TextBlock { Text = "Excel 암호 관리", FontSize = 25, FontWeight = FontWeights.Bold, Foreground = Brush("#17223B") });
            title.Children.Add(new TextBlock { Text = "파일 하나의 암호를 간편하게 관리하세요.", FontSize = 12, Foreground = Brush("#5E6F89"), Margin = new Thickness(0, 5, 0, 0) });

            var footerBorder = new Border { Background = Brushes.White, BorderBrush = Brush("#E0E6F0"), BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(24, 12, 24, 14) };
            DockPanel.SetDock(footerBorder, Dock.Bottom); root.Children.Add(footerBorder);
            var footer = new StackPanel(); footerBorder.Child = footer;
            progress.Height = 2; progress.Foreground = Brush("#3659D9"); progress.Background = Brush("#E7ECF7"); progress.Margin = new Thickness(0, 0, 0, 5); progress.Visibility = Visibility.Collapsed; footer.Children.Add(progress);
            statusCard.CornerRadius = new CornerRadius(10); statusCard.Padding = new Thickness(13, 8, 13, 9); statusCard.MinHeight = 58; statusCard.Background = Brush("#F4F6FB"); statusCard.BorderBrush = Brush("#E8ECF4"); statusCard.BorderThickness = new Thickness(1);
            var statusBody = new StackPanel(); statusCard.Child = statusBody;
            var statusLabel = new StackPanel { Orientation = Orientation.Horizontal };
            statusDot.Width = statusDot.Height = 6; statusDot.CornerRadius = new CornerRadius(3); statusDot.Background = Brush("#6276C7"); statusDot.Margin = new Thickness(0, 0, 7, 0); statusDot.VerticalAlignment = VerticalAlignment.Center; statusLabel.Children.Add(statusDot);
            statusCaption.Text = "작업 상태"; statusCaption.FontSize = 11; statusCaption.FontWeight = FontWeights.SemiBold; statusCaption.Foreground = Brush("#67758E"); statusLabel.Children.Add(statusCaption); statusBody.Children.Add(statusLabel);
            status.Margin = new Thickness(0, 5, 0, 0); status.FontSize = 12; status.LineHeight = 18; status.TextWrapping = TextWrapping.Wrap;
            AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite); statusBody.Children.Add(status); footer.Children.Add(statusCard);
            var commands = new DockPanel { Margin = new Thickness(0, 10, 0, 0), LastChildFill = false };
            close.Content = "닫기"; close.MinWidth = 74; close.Click += delegate { if (busy) RequestCancel(); else Close(); };
            DockPanel.SetDock(close, Dock.Right); commands.Children.Add(close);
            apply.Content = "암호 설정"; apply.MinWidth = 138; apply.Margin = new Thickness(0, 0, 9, 0); apply.Style = (Style)Resources["PrimaryButton"];
            DockPanel.SetDock(apply, Dock.Right); commands.Children.Add(apply); apply.Click += ApplyClick;
            results.Content = "백업·기록 보기"; results.Style = (Style)Resources["QuietButton"]; results.Visibility = Visibility.Collapsed; results.Click += delegate { OpenRunFolder(); };
            commands.Children.Add(results); footer.Children.Add(commands);
            var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Padding = new Thickness(24, 16, 24, 10) };
            root.Children.Add(scroll);
            var body = new StackPanel(); scroll.Content = body;
            var fileCard = new Border { Background = Brushes.White, BorderBrush = Brush("#DFE5F0"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(13), Padding = new Thickness(17, 11, 17, 11) };
            var fileContent = new StackPanel(); fileCard.Child = fileContent;
            var fileHeader = new DockPanel();
            browse.Content = "파일 선택"; browse.Style = (Style)Resources["QuietButton"]; browse.MinHeight = 28; browse.Padding = new Thickness(8, 4, 8, 4); browse.Margin = new Thickness(8, -4, -7, 0); browse.Click += BrowseClick;
            DockPanel.SetDock(browse, Dock.Right); fileHeader.Children.Add(browse);
            fileHeader.Children.Add(new TextBlock { Text = "선택한 파일", FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brush("#5E6F89"), VerticalAlignment = VerticalAlignment.Center }); fileContent.Children.Add(fileHeader);
            var fileTitle = new DockPanel { Margin = new Thickness(0, 5, 0, 0) };
            var typeBadge = new Border { Background = Brush("#F1F4FA"), CornerRadius = new CornerRadius(5), Padding = new Thickness(7, 3, 7, 3), Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            fileType.Text = "EXCEL"; fileType.FontSize = 10; fileType.FontWeight = FontWeights.Bold; fileType.Foreground = Brush("#5E6F89"); typeBadge.Child = fileType; DockPanel.SetDock(typeBadge, Dock.Right); fileTitle.Children.Add(typeBadge);
            fileName.Text = "Excel 파일을 선택하세요"; fileName.FontSize = 16; fileName.FontWeight = FontWeights.SemiBold; fileName.TextTrimming = TextTrimming.CharacterEllipsis; fileName.VerticalAlignment = VerticalAlignment.Center; fileTitle.Children.Add(fileName); fileContent.Children.Add(fileTitle);
            filePath.IsReadOnly = true; filePath.TextWrapping = TextWrapping.Wrap; filePath.Padding = new Thickness(0); filePath.BorderThickness = new Thickness(0); filePath.Background = Brushes.Transparent; filePath.Foreground = Brush("#5E6F89"); filePath.FontSize = 11; filePath.Margin = new Thickness(0, 5, 0, 0); filePath.MaxHeight = 48; filePath.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            filePath.TextChanged += delegate { UpdateFilePresentation(); };
            AutomationProperties.SetName(filePath, "선택한 Excel 파일 전체 경로");
            fileContent.Children.Add(filePath); body.Children.Add(fileCard);
            body.Children.Add(Label("작업 선택", 14));
            var optionPanel = new Border { Background = Brush("#E8EDF7"), CornerRadius = new CornerRadius(10), Padding = new Thickness(3, 3, 3, 3) };
            var options = new System.Windows.Controls.Primitives.UniformGrid { Columns = 3 }; optionPanel.Child = options;
            SetupOption(encrypt, "암호 설정", "Encrypt", options);
            SetupOption(decrypt, "암호 해제", "Decrypt", options);
            SetupOption(change, "암호 변경", "ChangePassword", options);
            body.Children.Add(optionPanel);
            explanation.TextWrapping = TextWrapping.Wrap; explanation.Foreground = Brush("#5E6F89"); explanation.FontSize = 12; explanation.LineHeight = 18; explanation.Margin = new Thickness(1, 6, 0, 0); body.Children.Add(explanation);
            SetupPassword(oldField, oldPassword, "현재 암호", body);
            var passwordPair = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2 };
            SetupPassword(newField, newPassword, "새 암호", passwordPair); newField.Margin = new Thickness(0, 0, 6, 0);
            SetupPassword(confirmField, confirmPassword, "새 암호 확인", passwordPair); confirmField.Margin = new Thickness(6, 0, 0, 0); body.Children.Add(passwordPair);
            var details = new Border { Background = Brush("#EDF1F7"), CornerRadius = new CornerRadius(10), Padding = new Thickness(13, 10, 13, 10), Margin = new Thickness(0, 10, 0, 11) };
            var detailText = new StackPanel();
            detailText.Children.Add(new TextBlock { Text = "실행 전, Excel을 모두 닫아 주세요.", FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Brush("#52627D") });
            backupNote.Text = "원본을 백업한 뒤 같은 파일에 적용합니다. 백업에 암호가 없을 수 있습니다.";
            backupNote.TextWrapping = TextWrapping.Wrap; backupNote.FontSize = 11; backupNote.LineHeight = 17; backupNote.Margin = new Thickness(0, 5, 0, 0); backupNote.Foreground = Brush("#5E6F89");
            detailText.Children.Add(backupNote); details.Child = detailText; body.Children.Add(details);
            consent.Content = Text("선택한 파일의 암호를 바꾸고 원본 백업을 남깁니다.", "#61718B");
            consent.VerticalContentAlignment = VerticalAlignment.Center;
            consent.Checked += delegate { UpdateApply(); }; consent.Unchecked += delegate { UpdateApply(); };
            body.Children.Add(consent);
            int tab = 0;
            foreach (Control control in new Control[] { browse, filePath, encrypt, decrypt, change, oldPassword, newPassword, confirmPassword, consent, results, apply, close })
                System.Windows.Input.KeyboardNavigation.SetTabIndex(control, tab++);
            System.Windows.Input.KeyboardNavigation.SetTabNavigation(root, System.Windows.Input.KeyboardNavigationMode.Cycle);
            oldPassword.PasswordChanged += PasswordChanged; newPassword.PasswordChanged += PasswordChanged; confirmPassword.PasswordChanged += PasswordChanged;
            encrypt.IsChecked = true;
            if (!String.IsNullOrEmpty(selectedFile)) SetFile(selectedFile);
            else ShowStatus("Excel 파일을 선택하거나 탐색기에서 ‘Excel 암호 관리’를 누르세요.", false);
            timer.Interval = TimeSpan.FromMilliseconds(500); timer.Tick += delegate { ReadProgress(); };
            Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e) { if (busy) { e.Cancel = true; RequestCancel(); } };
            Closed += delegate { timer.Stop(); ClearPasswords(); };
            UpdateApply();
        }

        static SolidColorBrush Brush(string color) { return (SolidColorBrush)new BrushConverter().ConvertFromString(color); }
        static TextBlock Text(string text, string color) { return new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = Brush(color), FontSize = 12, LineHeight = 18 }; }
        static TextBlock Label(string text, int top) { return new TextBlock { Text = text, FontWeight = FontWeights.SemiBold, FontSize = 12, Foreground = Brush("#485B78"), Margin = new Thickness(0, top, 0, 8) }; }
        void SetupPassword(StackPanel field, PasswordBox box, string label, Panel parent)
        {
            var caption = new Label { Content = label, Target = box, Padding = new Thickness(0), FontSize = 12, Foreground = Brush("#485B78"), FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 10, 0, 6) };
            field.Children.Add(caption); field.Children.Add(box); parent.Children.Add(field); AutomationProperties.SetName(box, label);
        }
        void UpdateFilePresentation()
        {
            bool empty = String.IsNullOrEmpty(filePath.Text);
            fileName.Text = empty ? "Excel 파일을 선택하세요" : Path.GetFileName(filePath.Text);
            fileName.ToolTip = fileName.Text;
            fileType.Text = empty ? "EXCEL" : Path.GetExtension(filePath.Text).TrimStart('.').ToUpperInvariant();
            browse.Content = empty ? "파일 선택" : "파일 변경";
            filePath.ToolTip = filePath.Text;
        }
        void SetupOption(RadioButton button, string label, string operation, Panel parent)
        {
            button.Content = label; button.GroupName = "Operation";
            button.Checked += delegate { ChangeMode(operation); }; parent.Children.Add(button);
        }
        void ChangeMode(string value)
        {
            mode = value; ClearPasswords(); consent.IsChecked = false;
            oldField.Visibility = mode == "Encrypt" ? Visibility.Collapsed : Visibility.Visible;
            newField.Visibility = confirmField.Visibility = mode == "Decrypt" ? Visibility.Collapsed : Visibility.Visible;
            apply.Content = mode == "Encrypt" ? "암호 설정" : mode == "Decrypt" ? "암호 해제" : "암호 변경";
            explanation.Text = mode == "Encrypt" ? "암호가 없는 파일에 새 암호를 설정합니다. 새 암호는 1~15자입니다." :
                mode == "Decrypt" ? "현재 암호를 입력하면 암호 없이 열 수 있게 저장합니다." : "현재 암호와 다른 새 암호를 입력하세요. 새 암호는 1~15자입니다.";
            consent.Content = Text(mode == "Decrypt" ? "선택한 파일의 암호를 해제하고 원본 백업을 남깁니다." : "선택한 파일에 위 암호를 적용하고 원본 백업을 남깁니다.", "#52637F");
            ShowStatus("", false); UpdateApply();
        }
        void PasswordChanged(object sender, RoutedEventArgs e) { UpdateApply(); }
        void ClearPasswords() { oldPassword.Clear(); newPassword.Clear(); confirmPassword.Clear(); }
        void UpdateApply()
        {
            using (var oldValue = oldPassword.SecurePassword)
            using (var newValue = newPassword.SecurePassword)
            using (var confirmation = confirmPassword.SecurePassword)
                apply.IsEnabled = !busy && !String.IsNullOrEmpty(filePath.Text) && consent.IsChecked == true &&
                    (mode == "Encrypt" || oldValue.Length > 0) &&
                    (mode == "Decrypt" || (newValue.Length > 0 && confirmation.Length > 0));
        }
        void BrowseClick(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog { Title = "암호를 관리할 Excel 파일 하나 선택", Filter = "Excel 통합 문서|*.xlsx;*.xlsm;*.xlsb;*.xls", Multiselect = false, CheckFileExists = true };
            if (dialog.ShowDialog(this) == true) SetFile(dialog.FileName);
        }
        void SetFile(string path)
        {
            ClearPasswords(); consent.IsChecked = false;
            try
            {
                string full = Path.GetFullPath(path); string error = Workflow.ValidateFile(full);
                if (error != null) { ShowStatus(error, true); return; }
                filePath.Text = full; filePath.ToolTip = full; ClearPasswords(); consent.IsChecked = false;
                ShowStatus("파일 내용을 확인한 뒤 원하는 작업을 선택하세요.", false);
            }
            catch { ShowStatus("파일 경로를 읽을 수 없습니다. 파일을 다시 선택하세요.", true); }
            UpdateApply();
        }
        void SetBusy(bool value)
        {
            busy = value; browse.IsEnabled = encrypt.IsEnabled = decrypt.IsEnabled = change.IsEnabled = !value;
            oldPassword.IsEnabled = newPassword.IsEnabled = confirmPassword.IsEnabled = consent.IsEnabled = !value;
            close.Content = value ? "취소" : "닫기"; close.IsEnabled = true;
            progress.Visibility = value ? Visibility.Visible : Visibility.Collapsed; progress.IsIndeterminate = value; UpdateApply();
            statusCaption.Text = statusIsError ? "확인 필요" : value ? "처리 중" : "작업 상태";
        }
        void ShowStatus(string message, bool error)
        {
            statusIsError = error;
            status.Text = String.IsNullOrEmpty(message) ? "필요한 암호를 입력하고, 백업 안내에 동의한 뒤 실행하세요." : message;
            status.Visibility = Visibility.Visible;
            status.Foreground = Brush(error ? "#A42F50" : "#52637F");
            statusCaption.Text = error ? "확인 필요" : busy ? "처리 중" : "작업 상태";
            statusCaption.Foreground = Brush(error ? "#A42F50" : "#61718B");
            statusDot.Background = Brush(error ? "#BD4667" : "#6276C7");
            statusCard.Background = Brush(error ? "#FFF6F8" : "#F4F6FB");
            statusCard.BorderBrush = Brush(error ? "#F1DEE5" : "#E8ECF4");
        }

        async void ApplyClick(object sender, RoutedEventArgs e)
        {
            string error;
            using (var oldValue = oldPassword.SecurePassword)
            using (var newValue = newPassword.SecurePassword)
            using (var confirmValue = confirmPassword.SecurePassword) error = Workflow.ValidatePasswords(mode, oldValue, newValue, confirmValue);
            if (error != null) { ShowStatus(error, true); return; }
            error = Workflow.ValidateFile(filePath.Text);
            if (error != null) { ShowStatus(error, true); return; }
            SetBusy(true); cancelRequested = false; results.Visibility = Visibility.Collapsed;
            ShowStatus("원본을 확인하고 있습니다…", false);
            string path = filePath.Text;
            try
            {
                string enginePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, @"runtime\Engine.ps1");
                if (!File.Exists(enginePath)) throw new FileNotFoundException("Engine missing");
                runDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ExcelPasswordSafe", "Runs", Guid.NewGuid().ToString("N"));
                Workflow.CreatePrivateDirectory(runDirectory);
                string oldCipher, newCipher;
                using (var value = oldPassword.SecurePassword) oldCipher = Workflow.ProtectPassword(value);
                using (var value = newPassword.SecurePassword) newCipher = Workflow.ProtectPassword(value);
                ClearPasswords();
                string hash = await Task.Run(delegate { return Workflow.Hash(path); });
                if (cancelRequested) { ShowStatus("취소했습니다. 원본을 바꾸지 않았습니다.", false); return; }
                var request = new Dictionary<string, object> { {"schemaVersion", 1}, {"path", path}, {"mode", mode}, {"oldSecret", oldCipher}, {"newSecret", newCipher}, {"expectedHash", hash} };
                File.WriteAllText(Path.Combine(runDirectory, "request.json"), new JavaScriptSerializer().Serialize(request), new UTF8Encoding(false));
                request.Clear(); oldCipher = newCipher = null;
                ShowStatus("백업을 만들고 암호를 처리합니다. 잠시 기다려 주세요…", false);
                timer.Start();
                await Task.Run(delegate
                {
                    using (var process = Process.Start(Workflow.EngineStartInfo(AppDomain.CurrentDomain.BaseDirectory, runDirectory))) process.WaitForExit();
                });
                timer.Stop();
                string resultPath = Path.Combine(runDirectory, "result.json");
                if (!File.Exists(resultPath)) ShowStatus("처리 결과를 확인할 수 없습니다. 다시 실행하기 전에 백업·기록과 Excel 실행 상태를 확인하세요.", true);
                else
                {
                    var result = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(resultPath));
                    string state = Get(result, "status"), category = Get(result, "category");
                    if (state == "Success")
                    {
                        bool cleanupIncomplete = Get(result, "message") == "TemporaryCleanupIncomplete";
                        ShowStatus((mode == "Encrypt" ? "암호를 설정했습니다." : mode == "Decrypt" ? "암호를 해제했습니다." : "암호를 변경했습니다.") +
                            (cleanupIncomplete ? " 작업용 파일 정리가 끝나지 않았습니다. 암호가 없는 임시 파일이 남았을 수 있으니 백업·기록을 확인하세요." : " 원본 백업을 보관했습니다."), cleanupIncomplete);
                    }
                    else if (state == "Cancelled") ShowStatus("취소했습니다. 원본을 바꾸지 않았습니다.", false);
                    else
                    {
                        string guidance = mode == "Encrypt" && category == "OpenFailedPossiblePasswordOrCorruption"
                            ? "파일을 열 수 없습니다. 이미 암호가 있다면 ‘암호 해제’ 또는 ‘암호 변경’을 선택하세요. Excel에서도 파일이 열리지 않으면 파일 상태를 확인하세요."
                            : CategoryMessage(category);
                        ShowStatus(guidance + "\n확인 코드: " + category, state != "Skipped");
                    }
                }
                results.Visibility = Visibility.Visible;
            }
            catch
            {
                timer.Stop(); ShowStatus("작업을 완료하지 못했습니다. 파일 접근 권한과 설치 상태를 확인하세요. 백업·기록이 있으면 다시 실행하기 전에 확인하세요.", true);
                if (runDirectory != null && Directory.Exists(runDirectory)) results.Visibility = Visibility.Visible;
            }
            finally
            {
                if (runDirectory != null) { try { File.Delete(Path.Combine(runDirectory, "request.json")); } catch { } }
                ClearPasswords(); consent.IsChecked = false; SetBusy(false);
            }
        }
        static string Get(Dictionary<string, object> values, string key) { object value; return values.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : ""; }
        public static string CategoryMessage(string category)
        {
            switch (category)
            {
                case "AlreadyEncrypted": return "이미 암호가 있는 파일입니다. ‘암호 변경’에서 현재 암호와 새 암호를 입력하세요.";
                case "AlreadyUnencrypted": case "NotEncrypted": return "암호가 없는 파일입니다. ‘암호 설정’을 선택하세요.";
                case "OpenFailedPossiblePasswordOrCorruption": return "파일을 열 수 없습니다. 현재 암호를 확인하고, Excel에서 파일이 정상으로 열리는지 확인하세요.";
                case "ExcelOwnershipOrExistingProcess": case "ExistingExcel": case "ExcelStillRunning": return "Excel이 실행 중입니다. 작업을 저장하고 Excel을 모두 정상 종료한 뒤 다시 시도하세요.";
                case "FileInUse": return "다른 프로그램에서 파일을 사용 중입니다. 파일을 닫고 다시 시도하세요.";
                case "Busy": case "AnotherOperationRunning": return "다른 암호 작업이 실행 중입니다. 완료된 뒤 다시 시도하세요.";
                case "SourceChanged": return "파일이 선택 후 변경되었습니다. 최신 파일을 확인하고 다시 실행하세요.";
                case "AccessDenied": case "ReadOnlyAttribute": return "파일이나 폴더에 쓸 수 없습니다. 읽기 전용 속성과 저장 권한을 확인하세요.";
                case "UnsupportedLocation": case "LocalPathRequired": case "LocalNtfsRequired": case "ReparsePoint": case "OfflineFileUnsupported": return "로컬 NTFS 드라이브의 일반 파일을 선택하세요. 네트워크·연결 폴더는 지원하지 않습니다.";
                case "FileNotFound": return "파일을 찾을 수 없습니다. 파일 위치를 확인하고 다시 선택하세요.";
                case "UnsupportedOrMismatchedFormat": return "확장자와 실제 파일 형식이 다르거나 지원하지 않는 구형 형식입니다. 원본을 유지했습니다.";
                case "Excel4MacroSheetUnsupported": return "Excel 4.0 매크로 시트가 있는 파일은 지원하지 않습니다. 원본을 유지했습니다.";
                case "WorkerTimeout": return "Excel 응답 시간이 지났습니다. 원본·백업·임시 파일과 남아 있는 Excel을 확인한 뒤 다시 시도하세요.";
                case "ComRegistrationOrLibrary": return "데스크톱 Excel을 시작할 수 없습니다. Excel 설치 상태를 확인하세요.";
                case "CommitUncertain": return "저장 완료 여부가 불확실합니다. 자동으로 재시도하지 말고 백업·복구본·기록을 확인하세요.";
                case "SignedWorkbookUnsupported": return "서명된 파일은 처리하지 않았습니다. 원본의 서명을 유지합니다.";
                case "SharedWorkbookUnsupported": return "공유 통합 문서는 지원하지 않습니다. 원본을 유지했습니다.";
                case "WriteReservedUnsupported": return "쓰기 암호가 있는 파일은 지원하지 않습니다. 원본을 유지했습니다.";
                case "ValidationFailed": return "저장 후 확인을 통과하지 못했습니다. 원본을 바꾸지 않았습니다. 백업·기록을 확인하세요.";
                default: return "작업을 완료하지 못했습니다. 백업·기록의 확인 코드를 확인하세요.";
            }
        }
        void RequestCancel()
        {
            cancelRequested = true; close.IsEnabled = false;
            try { if (runDirectory != null && Directory.Exists(runDirectory)) File.WriteAllText(Path.Combine(runDirectory, "cancel"), ""); }
            catch { }
            ShowStatus("취소 요청을 보냈습니다. 현재 확인을 마친 뒤 안전하게 멈춥니다. 저장이 이미 끝났다면 결과를 알려드립니다.", false);
        }
        void ReadProgress()
        {
            if (cancelRequested || runDirectory == null) return;
            try
            {
                string path = Path.Combine(runDirectory, "progress.json");
                if (!File.Exists(path)) return;
                var value = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(path));
                string stage = Get(value, "stage");
                if (stage == "Backup") ShowStatus("원본 백업을 만들고 있습니다…", false);
                else if (stage == "Worker" || stage == "Transform") ShowStatus("Excel에서 암호를 처리하고 저장 결과를 확인합니다…", false);
                else if (stage == "Commit") ShowStatus("확인한 결과를 원본 위치에 저장합니다…", false);
            }
            catch { }
        }
        void OpenRunFolder()
        {
            if (runDirectory == null || !Directory.Exists(runDirectory)) return;
            Process.Start(new ProcessStartInfo("explorer.exe", Workflow.QuoteArgument(runDirectory)) { UseShellExecute = false });
        }
        public void SetSmokeState(string value)
        {
            filePath.Text = @"D:\업무 자료\2026년 예산.xlsx";
            if (value == "Encrypt") encrypt.IsChecked = true;
            else if (value == "Decrypt") decrypt.IsChecked = true;
            else change.IsChecked = true;
            if (value == "Encrypt" || value == "Decrypt" || value == "ChangePassword")
            {
                if (mode != "Encrypt") oldPassword.Password = "Before-42!";
                if (mode != "Decrypt") newPassword.Password = confirmPassword.Password = "After-99!";
                consent.IsChecked = true;
                ShowStatus("입력한 내용을 확인한 뒤 선택한 작업을 실행하세요.", false);
            }
            if (value == "Success") { ShowStatus("암호를 변경했습니다. 원본 백업을 보관했습니다.", false); results.Visibility = Visibility.Visible; }
            if (value == "Error") ShowStatus(CategoryMessage("OpenFailedPossiblePasswordOrCorruption"), true);
            if (value == "Busy") { SetBusy(true); ShowStatus("Excel에서 암호를 처리하고 저장 결과를 확인합니다…", false); }
        }
        public void VerifySmokeLayout()
        {
            foreach (FrameworkElement element in new FrameworkElement[] { status, apply, close })
            {
                Point location = element.TranslatePoint(new Point(0, 0), this);
                if (!element.IsVisible || element.ActualWidth < 1 || element.ActualHeight < 1 || location.X < 0 || location.Y < 0 || location.X + element.ActualWidth > ActualWidth || location.Y + element.ActualHeight > ActualHeight)
                    throw new InvalidOperationException("The fixed status and actions must remain visible.");
            }
        }
        public void EndSmoke() { busy = false; Close(); }
    }

    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            try
            {
                if (args.Length == 2 && args[0] == "--smoke") return RenderSmoke(args[1]);
                if (args.Length == 4 && args[0] == "--folder" && args[2] == "--mode" && BatchWorkflow.IsMode(args[3]))
                {
                    var batchWindow = new BatchWindow(args[1], args[3]);
                    application.ShutdownMode = ShutdownMode.OnMainWindowClose;
                    application.Run(batchWindow); return 0;
                }
                string file = null;
                if (args.Length == 2 && args[0] == "--file") file = args[1];
                else if (args.Length != 0) { MessageBox.Show("사용법: ExcelPasswordSafe.exe --file \"Excel 파일 경로\"\n폴더: --folder \"폴더 경로\" --mode Encrypt|Decrypt|ChangePassword", "Excel 암호 관리"); return 2; }
                var window = new PasswordWindow(file);
                application.ShutdownMode = ShutdownMode.OnMainWindowClose;
                application.Run(window); return 0;
            }
            catch { MessageBox.Show("프로그램을 시작할 수 없습니다. 설치 상태를 확인하세요.", "Excel 암호 관리", MessageBoxButton.OK, MessageBoxImage.Error); return 1; }
        }
        static int RenderSmoke(string output)
        {
            Directory.CreateDirectory(output);
            int rendered = 0;
            foreach (string state in new[] { "Encrypt", "Decrypt", "ChangePassword", "Success", "Error", "Busy" })
            {
                var window = new PasswordWindow(null); window.SetSmokeState(state); window.Show();
                window.Dispatcher.Invoke(DispatcherPriority.Loaded, new Action(delegate { })); window.UpdateLayout();
                window.VerifySmokeLayout();
                var surface = (FrameworkElement)window.Content;
                foreach (int dpi in new[] { 96, 144, 192 })
                {
                    var bitmap = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth * dpi / 96), (int)Math.Ceiling(surface.ActualHeight * dpi / 96), dpi, dpi, PixelFormats.Pbgra32);
                    bitmap.Render(surface);
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using (var stream = File.Create(Path.Combine(output, state + "-" + dpi + ".png"))) encoder.Save(stream);
                    rendered++;
                }
                window.Width = 520; window.Height = 520; window.UpdateLayout();
                window.VerifySmokeLayout();
                var small = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32); small.Render(surface);
                var smallEncoder = new PngBitmapEncoder(); smallEncoder.Frames.Add(BitmapFrame.Create(small));
                using (var stream = File.Create(Path.Combine(output, state + "-small.png"))) smallEncoder.Save(stream);
                rendered++;
                window.EndSmoke();
            }
            foreach (string state in new[] { "Encrypt", "Decrypt", "ChangePassword", "Failure", "Busy" })
            {
                var window = BatchWindow.Smoke(state); window.Show();
                window.Dispatcher.Invoke(DispatcherPriority.Loaded, new Action(delegate { })); window.UpdateLayout(); window.VerifySmokeLayout();
                var surface = (FrameworkElement)window.Content;
                foreach (int dpi in new[] { 96, 144, 192 })
                {
                    var bitmap = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth * dpi / 96), (int)Math.Ceiling(surface.ActualHeight * dpi / 96), dpi, dpi, PixelFormats.Pbgra32); bitmap.Render(surface);
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using (var stream = File.Create(Path.Combine(output, "Folder-" + state + "-" + dpi + ".png"))) encoder.Save(stream);
                    rendered++;
                }
                window.Width = 620; window.Height = 560; window.UpdateLayout(); window.VerifySmokeLayout();
                var small = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32); small.Render(surface);
                var smallEncoder = new PngBitmapEncoder(); smallEncoder.Frames.Add(BitmapFrame.Create(small));
                using (var stream = File.Create(Path.Combine(output, "Folder-" + state + "-small.png"))) smallEncoder.Save(stream);
                rendered++; window.EndSmoke();
            }
            File.WriteAllText(Path.Combine(output, "smoke-result.json"), "{\"status\":\"PASS\",\"renders\":" + rendered + ",\"states\":11,\"dpi\":[96,144,192],\"smallViewport\":\"file520x520;folder620x560\",\"note\":\"WPF render only; physical high-DPI monitors and interactive Explorer/Excel verification are separate.\"}");
            return 0;
        }
    }
}
