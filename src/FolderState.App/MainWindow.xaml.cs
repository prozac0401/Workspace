using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using FolderState.Core;
using Microsoft.Win32;

namespace FolderState.App;
public partial class MainWindow : Window
{
    private readonly FolderStateEngine engine = Commands.CreateEngine();
    private bool busy;
    public MainWindow() { InitializeComponent();
        foreach (var pair in new[] { (todoImage, "todo"), (doingImage, "doing"), (doneImage, "done"), (issueImage, "issue") })
        { try { pair.Item1.Source = System.Windows.Media.Imaging.BitmapDecoder.Create(new Uri(Path.Combine(AppContext.BaseDirectory, "icons", pair.Item2 + ".ico")), System.Windows.Media.Imaging.BitmapCreateOptions.PreservePixelFormat, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad).Frames.OrderByDescending(frame => frame.PixelWidth).First(); } catch (Exception ex) when (ex is IOException or FormatException or NotSupportedException or UnauthorizedAccessException) { ResultText.Text = "아이콘 파일을 열 수 없습니다. FolderState 설치 파일을 다시 열고 ‘프로그램 복구’를 눌러 주세요."; } }
        VersionText.Text = "v" + typeof(Commands).Assembly.GetName().Version?.ToString(3); }
    private async void Browse_Click(object sender, RoutedEventArgs e)
    { var dialog = new OpenFolderDialog { Title = "진행 상황을 표시할 폴더를 선택하세요", Multiselect = false }; if (dialog.ShowDialog(this) == true) { FolderPath.Text = dialog.FolderName; await Refresh(); } }
    private async void Path_KeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter && !busy) await Refresh(); }
    private void Controls(bool enabled)
    {
        busy = !enabled; BrowseButton.IsEnabled = FolderPath.IsEnabled = LocalMode.IsEnabled = PortableMode.IsEnabled = enabled;
        StateButtons.IsEnabled = RepairButton.IsEnabled = ResetButton.IsEnabled = enabled && !string.IsNullOrWhiteSpace(FolderPath.Text);
    }
    private async Task Refresh()
    {
        string folder = FolderPath.Text; Controls(false);
        try
        {
            var state = await Task.Run(() => engine.ReadState(folder));
            CurrentState.Text = state is null ? "아직 상태를 표시하지 않은 폴더입니다." : $"현재 상태: {state.Status.Label()}\n마지막으로 바꾼 때: {state.Updated:yyyy-MM-dd HH:mm}";
            if (state is not null) { LocalMode.IsChecked = state.Mode == IconMode.Local; PortableMode.IsChecked = state.Mode == IconMode.Portable; }
        }
        catch (Exception ex) { CurrentState.Text = "저장된 상태를 읽지 못했습니다. 아래 안내를 확인해 주세요."; ResultText.Text = FolderStateEngine.Describe(ex).Message; }
        finally { Controls(true); }
    }
    private async Task Apply(Func<string, OperationResult> operation)
    {
        if (busy) return; string folder = FolderPath.Text; Controls(false); ResultText.Text = "요청한 작업을 처리하고 있습니다. 잠시 기다려 주세요…";
        try
        {
            var result = await Task.Run(() => operation(folder));
            ResultText.Text = result.Message + (result.Warning is null ? "" : "\n" + result.Warning);
            if (result.Success) await Refresh();
        }
        catch (Exception ex) { ResultText.Text = FolderStateEngine.Describe(ex).Message; }
        finally { Controls(true); }
    }
    private async void State_Click(object sender, RoutedEventArgs e)
    { var state = Enum.Parse<WorkStatus>((string)((Button)sender).Tag); var mode = PortableMode.IsChecked == true ? IconMode.Portable : IconMode.Local; await Apply(folder => engine.Set(folder, state, mode)); }
    private async void Repair_Click(object sender, RoutedEventArgs e) => await Apply(engine.Repair);
    private async void Reset_Click(object sender, RoutedEventArgs e) => await Apply(engine.Reset);
    private void Help_Click(object sender, RoutedEventArgs e) => Open(Path.Combine(AppContext.BaseDirectory, "help.html"));
    private void Logs_Click(object sender, RoutedEventArgs e)
    {
        try { var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FolderState", "logs"); Directory.CreateDirectory(directory); Open(directory); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { ResultText.Text = FolderStateEngine.Describe(ex).Message; }
    }
    private void Open(string target)
    { try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch (Exception ex) { ResultText.Text = FolderStateEngine.Describe(ex).Message; } }
}
