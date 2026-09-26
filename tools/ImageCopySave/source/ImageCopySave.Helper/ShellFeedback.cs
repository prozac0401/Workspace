using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace ImageCopySave.Helper;

// Per-command transient feedback only: no main window, tray icon or resident watcher.
internal static class ShellFeedback
{
    // Offscreen smoke rendering: never Show a window or touch any clipboard.
    public static void RenderSamples(string directory)
    {
        if (!Path.IsPathFullyQualified(directory) || !Directory.Exists(directory))
            throw new ArgumentException("An existing absolute rendering directory is required.");
        var request = new ShellRequest("save", @"C:\작업 폴더", 0, 0);
        foreach (string kind in new[] { "progress", "saved", "error" })
        {
            var window = new FeedbackWindow(0, () => { });
            if (kind != "progress") window.SetResultContent(request, kind == "saved"
                ? new WorkerResult(0, @"C:\작업 폴더\그림_20260925_183000.png" + "\n", "")
                : new WorkerResult(1, "", "복사한 내용이 바뀌어 작업을 중단했습니다. 새 복사 내용은 그대로 유지됩니다."));
            var content = (FrameworkElement)window.Content;
            content.Measure(new Size(448, 360));
            content.Arrange(new Rect(new Point(), new Size(448, content.DesiredSize.Height)));
            content.UpdateLayout();
            var image = new RenderTargetBitmap(448, (int)Math.Ceiling(content.ActualHeight), 96, 96, PixelFormats.Pbgra32);
            image.Render(content);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var output = new FileStream(Path.Combine(directory, "helper-" + kind + ".png"), FileMode.Create, FileAccess.Write, FileShare.None);
            encoder.Save(output);
        }
    }

    public static int Run(ShellRequest request, Func<CancellationToken, Action, WorkerResult> operation)
    {
        var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var cancellation = new CancellationTokenSource();
        var window = new FeedbackWindow(request.ParentWindow, () => cancellation.Cancel());
        int exitCode = 1;
        _ = Task.Run(() =>
        {
            WorkerResult result;
            try
            {
                result = operation(cancellation.Token,
                    () => window.Dispatcher.BeginInvoke(new Action(window.ShowProgress)));
            }
            catch (Exception exception) when (exception is not StackOverflowException)
            {
                // Starting the worker failed. Exception messages can contain private paths.
                result = new WorkerResult(1, "", "그림 작업을 시작하지 못했습니다. 원본 파일은 변경하지 않았습니다.");
            }
            _ = window.Dispatcher.BeginInvoke(new Action(() =>
            {
                exitCode = result.ExitCode;
                window.Complete(request, result);
                var close = new DispatcherTimer { Interval = TimeSpan.FromSeconds(result.ExitCode == 0 ? 3 : 8) };
                close.Tick += (_, _) => { close.Stop(); window.AllowClose = true; window.Close(); };
                close.Start();
            }));
        });
        window.Closed += (_, _) => application.Shutdown(exitCode);
        return application.Run();
    }

    internal static string ResultMessage(ShellRequest request, WorkerResult result)
    {
        if (result.ExitCode == 0)
            return request.Operation == "copy" ? "그림으로 복사했습니다" : "그림을 저장했습니다\n" + result.Output.TrimEnd('\r', '\n');
        if (string.IsNullOrWhiteSpace(result.Error)) return "그림 작업을 완료하지 못했습니다. 다시 실행해 주세요.";
        try
        {
            using JsonDocument detail = JsonDocument.Parse(result.Error.Trim());
            JsonElement root = detail.RootElement;
            // Completion is authoritative even if the completed action's result could not
            // be delivered. In particular, a copied image necessarily changed the clipboard.
            if (root.TryGetProperty("operationCompleted", out JsonElement completed) && completed.ValueKind == JsonValueKind.True)
                return "그림 작업은 완료했지만 결과를 전달하지 못했습니다. 완료된 작업은 취소되지 않았습니다.";
            if (root.TryGetProperty("stage", out JsonElement stage) && stage.GetString() == "supervision")
                return "작업 상태를 확인하지 못했습니다. 파일 저장 완료 여부와 클립보드 보존 여부는 불확실합니다.";
            if (root.TryGetProperty("error", out JsonElement kind) && kind.GetString() == "ClipboardChangedException")
                return "복사한 내용이 바뀌어 작업을 중단했습니다. 새 복사 내용은 그대로 유지됩니다.";
            if (root.TryGetProperty("clipboardMayHaveChanged", out JsonElement changed) && changed.ValueKind == JsonValueKind.True)
                return "그림 작업을 완료하지 못했습니다. 클립보드 내용이 바뀌었을 수 있습니다. 다시 복사해 주세요.";
            string? error = kind.ValueKind == JsonValueKind.String ? kind.GetString() : null;
            if (error == "ClipboardOperationException")
                return request.Operation == "save" ? "복사한 그림을 읽지 못했습니다. 다시 실행해 주세요."
                    : "클립보드에 그림을 복사하지 못했습니다. 기존 복사 내용은 그대로 유지됩니다. 다시 실행해 주세요.";
            int? nativeCode = root.TryGetProperty("nativeCode", out JsonElement native) && native.ValueKind == JsonValueKind.Number &&
                native.TryGetInt32(out int code) ? code : null;
            if (nativeCode == null && root.TryGetProperty("code", out JsonElement hresult) && hresult.ValueKind == JsonValueKind.Number && hresult.TryGetInt32(out int value) &&
                (unchecked((uint)value) & 0xFFFF0000) == 0x80070000)
                nativeCode = value & 0xFFFF;
            if (nativeCode is 39 or 112)
                return "저장 공간이 부족하여 그림을 저장하지 못했습니다. 대상 드라이브의 여유 공간을 확인해 주세요.";
            if (nativeCode == 5 || error == "UnauthorizedAccessException")
                return request.Operation == "save" ? "이 폴더에 그림을 저장할 권한이 없습니다. 폴더의 쓰기 권한을 확인해 주세요."
                    : "원본 그림 파일을 읽을 권한이 없어 복사하지 못했습니다. 기존 복사 내용은 그대로 유지됩니다.";
            if (nativeCode is 2 or 3 || error is "FileNotFoundException" or "DirectoryNotFoundException")
                return request.Operation == "save" ? "저장할 폴더를 찾지 못했습니다. 폴더가 이동되거나 삭제되었는지 확인해 주세요."
                    : "원본 그림 파일을 찾지 못했습니다. 파일이 이동되거나 삭제되었는지 확인해 주세요.";
            if (error == "InvalidDataException")
                return "그림 데이터가 손상되었거나 지원하는 형식·크기 범위를 벗어났습니다. 원본은 변경하지 않았습니다.";
            if (error == "OutOfMemoryException")
                return "이 그림을 처리할 메모리가 부족합니다. 원본은 변경하지 않았습니다.";
            if (root.TryGetProperty("message", out JsonElement message)) return message.GetString() ?? "그림 작업을 완료하지 못했습니다.";
        }
        catch (JsonException) { }
        // This stream comes solely from our fixed, bounded worker diagnostics.
        return result.Error.Trim();
    }

    private sealed class FeedbackWindow : Window
    {
        private readonly nint parent;
        private readonly Action cancel;
        private readonly TextBlock message;
        private readonly Button button;
        private bool completed;
        public bool AllowClose { get; set; }

        public FeedbackWindow(nint parent, Action cancel)
        {
            this.parent = parent;
            this.cancel = cancel;
            Title = "그림 복사·저장";
            Width = 448;
            SizeToContent = SizeToContent.Height;
            MaxHeight = 360;
            ResizeMode = ResizeMode.NoResize;
            WindowStyle = WindowStyle.None;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = true;
            Background = SystemColors.WindowBrush;
            Foreground = SystemColors.WindowTextBrush;
            FontFamily = new FontFamily("Segoe UI");
            FontSize = 14;
            var panel = new StackPanel { Margin = new Thickness(20) };
            panel.Children.Add(new TextBlock { Text = "그림 복사·저장", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) });
            message = new TextBlock { Text = "그림 처리 중입니다…", TextWrapping = TextWrapping.Wrap, MaxHeight = 220 };
            panel.Children.Add(message);
            button = new Button { Content = "취소", MinWidth = 72, Padding = new Thickness(12, 5, 12, 5),
                HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0), Focusable = false };
            button.Click += (_, _) =>
            {
                if (completed) { AllowClose = true; Close(); }
                else RequestCancel();
            };
            panel.Children.Add(button);
            Content = new Border { Background = SystemColors.WindowBrush, BorderBrush = SystemColors.ActiveBorderBrush,
                BorderThickness = new Thickness(1), Child = panel };
            SourceInitialized += (_, _) =>
            {
                nint handle = new WindowInteropHelper(this).Handle;
                nint style = Native.GetWindowLongPtr(handle, -20);
                _ = Native.SetWindowLongPtr(handle, -20, style | 0x08000000 | 0x00000080); // NOACTIVATE | TOOLWINDOW
                HwndSource.FromHwnd(handle)?.AddHook(NoActivation);
            };
            ContentRendered += (_, _) => Position();
            Closing += (_, e) =>
            {
                if (!AllowClose && !completed) { e.Cancel = true; RequestCancel(); }
            };
        }

        private nint NoActivation(nint hwnd, int messageId, nint wParam, nint lParam, ref bool handled)
        {
            if (messageId == 0x21) { handled = true; return 3; } // WM_MOUSEACTIVATE / MA_NOACTIVATE
            return 0;
        }

        private void RequestCancel()
        {
            cancel();
            button.IsEnabled = false;
            message.Text = "작업을 중단하는 중입니다…";
        }

        public void ShowProgress()
        {
            if (completed) return;
            if (!IsVisible) Show();
        }

        public void Complete(ShellRequest request, WorkerResult result)
        {
            completed = true;
            SetResultContent(request, result);
            if (!IsVisible) Show();
            UpdateLayout();
            Position();
        }

        public void SetResultContent(ShellRequest request, WorkerResult result)
        {
            message.Text = ResultMessage(request, result);
            button.Content = "닫기";
            button.IsEnabled = true;
            // Success requires no confirmation click; the timer closes this window.
            button.Visibility = result.ExitCode == 0 ? Visibility.Collapsed : Visibility.Visible;
        }

        private void Position()
        {
            // A parent HWND supplies only a display anchor. Never use it to infer a folder,
            // activate Explorer or create a new Explorer window.
            nint monitor = Native.MonitorFromWindow(Native.IsWindow(parent) ? parent : 0, 2);
            var info = new Native.MonitorInfo { Size = Marshal.SizeOf<Native.MonitorInfo>() };
            if (!Native.GetMonitorInfo(monitor, ref info)) return;
            HwndSource? source = PresentationSource.FromVisual(this) as HwndSource;
            Matrix scale = source?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;
            Point bottomRight = scale.Transform(new Point(info.Work.Right, info.Work.Bottom));
            Left = bottomRight.X - ActualWidth - 20;
            Top = bottomRight.Y - ActualHeight - 20;
        }
    }

    private static class Native
    {
        [StructLayout(LayoutKind.Sequential)] internal struct Rect { internal int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] internal struct MonitorInfo { internal int Size; internal Rect Monitor, Work; internal uint Flags; }
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsWindow(nint window);
        [DllImport("user32.dll")] internal static extern nint MonitorFromWindow(nint window, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] internal static extern nint GetWindowLongPtr(nint window, int index);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] internal static extern nint SetWindowLongPtr(nint window, int index, nint value);
    }
}
