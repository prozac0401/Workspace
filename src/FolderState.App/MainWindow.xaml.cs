using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using FolderState.Core;
using Microsoft.Win32;

namespace FolderState.App;

public partial class MainWindow : Window
{
    private readonly FolderStateEngine engine;
    private bool busy;
    private bool initializing = true;
    private bool ready;
    private bool recoveryPending;
    private string? confirmedFolder;
    private string? confirmedInput;
    private StateInfo? currentState;

    public MainWindow() : this(Commands.CreateEngine()) { }

    // The smoke runner supplies an engine whose log and fixture paths are isolated.
    public MainWindow(FolderStateEngine engine)
    {
        this.engine = engine;
        InitializeComponent();
        foreach (var pair in new[] { (todoImage, "todo"), (doingImage, "doing"), (doneImage, "done"), (issueImage, "issue") })
        {
            try
            {
                pair.Item1.Source = System.Windows.Media.Imaging.BitmapDecoder.Create(
                    new Uri(Path.Combine(AppContext.BaseDirectory, "icons", pair.Item2 + ".ico")),
                    System.Windows.Media.Imaging.BitmapCreateOptions.PreservePixelFormat,
                    System.Windows.Media.Imaging.BitmapCacheOption.OnLoad).Frames.OrderByDescending(frame => frame.PixelWidth).First();
            }
            catch (Exception ex) when (ex is IOException or FormatException or NotSupportedException or UnauthorizedAccessException)
            {
                SetResult("! 아이콘 파일 확인 필요", "FolderState 설치 파일을 다시 열고 ‘프로그램 복구’를 눌러 주세요.", ResultKind.Warning);
            }
        }
        VersionText.Text = "v" + typeof(Commands).Assembly.GetName().Version?.ToString(3);
        initializing = false;
        UpdateControls();
    }

    private enum ResultKind { Information, Success, Warning, Error }
    private IconMode SelectedMode => PortableMode.IsChecked == true ? IconMode.Portable : IconMode.Local;
    private bool HasConfirmedTarget => confirmedFolder is not null && confirmedInput == FolderPath.Text;

    private void UpdateControls()
    {
        bool available = !busy;
        BrowseButton.IsEnabled = FolderPath.IsEnabled = available;
        ConfirmButton.IsEnabled = available && !string.IsNullOrWhiteSpace(FolderPath.Text);
        bool usable = available && HasConfirmedTarget;
        StateButtons.IsEnabled = usable && ready;
        RepairButton.IsEnabled = usable && (recoveryPending || (ready && currentState is not null));
        ResetButton.IsEnabled = usable && ready && currentState is not null;
        LocalMode.IsEnabled = PortableMode.IsEnabled = usable && ready && currentState is not null;
        ModeApplyButton.IsEnabled = usable && ready && currentState is not null && SelectedMode != currentState.Mode;
        OpenFolderButton.IsEnabled = usable;
        ModeHint.Text = currentState is null
            ? "먼저 상태를 저장한 뒤 아이콘 위치를 바꿀 수 있습니다. 첫 상태는 이 PC의 아이콘을 사용합니다."
            : SelectedMode == currentState.Mode
                ? "다른 PC로 옮길 때는 ‘선택한 폴더 안’을 고를 수 있습니다. 상태와 상태 변경 시각은 유지됩니다."
                : "아직 위치를 바꾸지 않았습니다. ‘아이콘 저장 위치 적용’을 누르세요. 상태 버튼은 저장된 위치를 유지합니다.";
    }

    private void ClearSelection()
    {
        ready = recoveryPending = false;
        confirmedFolder = confirmedInput = null;
        currentState = null;
        LocalMode.IsChecked = true;
        SelectedFolderText.Text = "확인된 폴더가 없습니다.";
        CurrentState.Text = "폴더를 선택하거나 입력한 경로를 확인하세요.";
        TimestampText.Text = "";
        ModeSummary.Text = "";
        MarkCurrentState();
    }

    private void Path_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (initializing) return;
        ClearSelection();
        SetResult("폴더 확인 필요", "입력한 경로의 ‘폴더 확인’을 누르거나 Enter를 누르세요.");
        UpdateControls();
    }

    private async void Browse_Click(object sender, RoutedEventArgs e)
    {
        if (busy) return;
        var dialog = new OpenFolderDialog { Title = "진행 상황을 표시할 폴더를 선택하세요", Multiselect = false };
        if (dialog.ShowDialog(this) != true) return;
        FolderPath.Text = dialog.FolderName;
        await Refresh();
    }

    private async void Path_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || busy) return;
        e.Handled = true;
        await Refresh();
    }

    private async void Confirm_Click(object sender, RoutedEventArgs e) => await Refresh();

    private async Task Refresh()
    {
        if (busy) return;
        string input = FolderPath.Text;
        ClearSelection();
        busy = true;
        UpdateControls();
        SetResult("폴더 확인 중", "저장된 상태를 읽고 있습니다…");
        try
        {
            var error = await ReadSelection(input);
            if (error is not null) ShowReadError(error.Value);
            else SetResult("폴더 확인 완료", TargetSummary(confirmedFolder!) + "\n현재 상태를 확인한 뒤 상태 버튼을 누르세요.");
        }
        finally { busy = false; UpdateControls(); }
    }

    private async Task<(string Code, string Message)?> ReadSelection(string input)
    {
        ready = recoveryPending = false;
        currentState = null;
        confirmedFolder = confirmedInput = null;
        try
        {
            var state = await Task.Run(() => engine.ReadState(input));
            if (FolderPath.Text != input) return ("selection_changed", "경로가 바뀌었습니다. 폴더를 다시 확인하세요.");
            confirmedFolder = Path.TrimEndingDirectorySeparator(Path.GetFullPath(input));
            confirmedInput = input;
            currentState = state;
            ready = true;
            SelectedFolderText.Text = "선택한 폴더: " + Path.GetFileName(confirmedFolder);
            CurrentState.Text = state is null ? "아직 상태를 표시하지 않은 폴더입니다." : "현재 상태: " + state.Status.Label();
            TimestampText.Text = state is null ? "" : $"상태 변경 시각: {state.Updated:yyyy-MM-dd HH:mm}";
            ModeSummary.Text = state is null ? "첫 상태의 아이콘 위치: 이 PC" : "저장된 아이콘 위치: " + ModeLabel(state.Mode);
            LocalMode.IsChecked = state is null || state.Mode == IconMode.Local;
            PortableMode.IsChecked = state?.Mode == IconMode.Portable;
            MarkCurrentState();
            return null;
        }
        catch (Exception ex)
        {
            var error = FolderStateEngine.Describe(ex);
            if (FolderPath.Text != input) return ("selection_changed", "경로가 바뀌었습니다. 폴더를 다시 확인하세요.");
            LocalMode.IsChecked = true;
            SelectedFolderText.Text = "확인할 경로: " + input;
            CurrentState.Text = "저장된 상태를 확인하지 못했습니다.";
            TimestampText.Text = ModeSummary.Text = "";
            if (error.Code == "recovery_pending")
            {
                confirmedFolder = Path.TrimEndingDirectorySeparator(Path.GetFullPath(input));
                confirmedInput = input;
                recoveryPending = true;
                CurrentState.Text = "이전 작업의 복구가 필요합니다.";
            }
            MarkCurrentState();
            return error;
        }
    }

    private void ShowReadError((string Code, string Message) error) => SetResult(
        error.Code == "recovery_pending" ? "! 이전 작업 복구 필요" : "! 폴더 확인 실패",
        FolderPath.Text + "\n" + error.Message,
        error.Code == "recovery_pending" ? ResultKind.Warning : ResultKind.Error);

    private async Task Apply(Func<string, OperationResult> operation)
    {
        if (busy) return;
        if (!HasConfirmedTarget || (!ready && !recoveryPending))
        {
            SetResult("폴더 확인 필요", "적용할 폴더를 먼저 확인하세요.", ResultKind.Warning);
            return;
        }
        string folder = confirmedFolder!;
        string input = confirmedInput!;
        busy = true;
        UpdateControls();
        SetResult("작업 중", TargetSummary(folder) + "\n요청한 작업을 처리하고 있습니다…");
        try
        {
            var result = await Task.Run(() => operation(folder));
            // Re-read even after failure: recovery may have restored an initially unmarked folder.
            var readError = await ReadSelection(input);
            var kind = !result.Success ? ResultKind.Error : result.Warning is not null || readError is not null ? ResultKind.Warning : ResultKind.Success;
            string title = !result.Success ? "! 작업을 완료하지 못했습니다" : kind == ResultKind.Warning ? "! 작업 완료 · 추가 확인 필요" : "✓ 작업 완료";
            string message = TargetSummary(result.TargetPath) + "\n" + result.Message;
            if (result.Warning is not null) message += "\n" + result.Warning;
            if (readError is not null) message += "\n현재 상태 다시 확인: " + readError.Value.Message;
            SetResult(title, message, kind);
        }
        catch (Exception ex)
        {
            // An unexpected failure must not leave stale state available for another write.
            ClearSelection();
            SetResult("! 작업 결과 확인 필요", TargetSummary(folder) + "\n" + FolderStateEngine.Describe(ex).Message + "\n폴더 확인을 눌러 현재 상태를 다시 읽어 주세요.", ResultKind.Error);
        }
        finally { busy = false; UpdateControls(); }
    }

    private async void State_Click(object sender, RoutedEventArgs e)
    {
        if (!StateButtons.IsEnabled) return;
        var status = Enum.Parse<WorkStatus>((string)((Button)sender).Tag);
        // A state change preserves the stored mode; moving icons is a separate action.
        await Apply(folder => engine.Set(folder, status));
    }

    private async void Repair_Click(object sender, RoutedEventArgs e)
    { if (RepairButton.IsEnabled) await Apply(engine.Repair); }
    private async void Reset_Click(object sender, RoutedEventArgs e)
    { if (ResetButton.IsEnabled) await Apply(engine.Reset); }
    private void Mode_Checked(object sender, RoutedEventArgs e)
    { if (!initializing) UpdateControls(); }
    private async void ModeApply_Click(object sender, RoutedEventArgs e)
    {
        if (!ModeApplyButton.IsEnabled) return;
        var mode = SelectedMode;
        await Apply(folder => engine.ChangeMode(folder, mode));
    }

    private void MarkCurrentState()
    {
        foreach (Button button in StateButtons.Children)
        {
            bool selected = currentState is not null && (string)button.Tag == currentState.Status.ToString();
            button.Background = Brush(selected ? "#E8F3F3" : "#FFFFFF");
            button.BorderBrush = Brush(selected ? "#087F8C" : "#CBD5E1");
            var badge = ((StackPanel)button.Content).Children.OfType<TextBlock>().Last();
            badge.Visibility = selected ? Visibility.Visible : Visibility.Hidden;
            AutomationProperties.SetItemStatus(button, selected ? "현재 저장된 상태" : "");
        }
    }

    private static string ModeLabel(IconMode mode) => mode == IconMode.Local ? "이 PC" : "선택한 폴더 안";
    private static string TargetSummary(string folder) => "대상: " + folder;
    private static Brush Brush(string color) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
    private void SetResult(string title, string message, ResultKind kind = ResultKind.Information)
    {
        ResultTitle.Text = title;
        ResultText.Text = message;
        ResultPanel.Background = Brush(kind switch { ResultKind.Success => "#EAF5EE", ResultKind.Warning => "#FFF3D6", ResultKind.Error => "#FDEDEE", _ => "#EAF0F6" });
        ResultTitle.Foreground = Brush(kind switch { ResultKind.Success => "#21613B", ResultKind.Warning => "#785400", ResultKind.Error => "#A12C35", _ => "#304B68" });
        if (UIElementAutomationPeer.FromElement(ResultText) is AutomationPeer peer)
            peer.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    { if (OpenFolderButton.IsEnabled && HasConfirmedTarget) Open(confirmedFolder!); }
    private void Help_Click(object sender, RoutedEventArgs e) => Open(Path.Combine(AppContext.BaseDirectory, "help.html"));
    private void Troubleshooting_Click(object sender, RoutedEventArgs e) => Open(Path.Combine(AppContext.BaseDirectory, "help.html"));
    private void Logs_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FolderState", "logs");
            Directory.CreateDirectory(directory);
            Open(directory);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        { SetResult("! 작업 기록을 열지 못했습니다", FolderStateEngine.Describe(ex).Message, ResultKind.Error); }
    }
    private void Open(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); }
        catch (Exception ex) { SetResult("! 열지 못했습니다", FolderStateEngine.Describe(ex).Message, ResultKind.Error); }
    }
}
