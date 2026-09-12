using System.Windows;
using FolderState.Core;

namespace FolderState.App;
public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Length == 0) { MainWindow = new MainWindow(); MainWindow.Show(); return; }
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        try
        {
            var command = Commands.Parse(e.Args);
            if (command.Action == "status")
            { var state = await Task.Run(() => Commands.CreateEngine().ReadState(command.Folders[0])); MessageBox.Show(state?.Status.Label() ?? "상태 미지정", "FolderState"); Shutdown(0); return; }
            var results = await Task.Run(() => Commands.Run(Commands.CreateEngine(), command));
            var failures = results.Where(r => !r.Success || r.Warning is not null).ToArray();
            if (failures.Length > 0) MessageBox.Show(string.Join("\n\n", failures.Select(r => $"{r.TargetPath}\n{r.Message}\n{r.Warning}")), "FolderState · 작업 결과", MessageBoxButton.OK, MessageBoxImage.Warning);
            Shutdown(results.All(r => r.Success) ? 0 : 1);
        }
        catch (Exception ex) { MessageBox.Show(FolderStateEngine.Describe(ex).Message, "FolderState", MessageBoxButton.OK, MessageBoxImage.Warning); Shutdown(1); }
    }
}
