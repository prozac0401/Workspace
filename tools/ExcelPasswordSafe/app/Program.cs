using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace ExcelPasswordSafe
{
    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            bool smoke = args.Length == 2 && args[0] == "--smoke";
            var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            try
            {
                if (smoke) return RenderSmoke(args[1]);
                string target = null, mode = null;
                bool folder = false;
                if (args.Length == 2 && args[0] == "--file") target = args[1];
                else if (args.Length == 4 && (args[0] == "--folder" || args[0] == "--file") && args[2] == "--mode" && BatchWorkflow.IsMode(args[3]))
                {
                    target = args[1]; folder = args[0] == "--folder"; mode = args[3];
                }
                else if (args.Length != 0)
                {
                    MessageBox.Show("파일: --file \"Excel 파일 경로\" --mode Encrypt|Decrypt|ChangePassword\n폴더: --folder \"폴더 경로\" --mode Encrypt|Decrypt|ChangePassword",
                        "Excel 암호 관리", MessageBoxButton.OK, MessageBoxImage.Information);
                    return 2;
                }
                application.ShutdownMode = ShutdownMode.OnMainWindowClose;
                return application.Run(new WizardWindow(target, folder, mode));
            }
            catch
            {
                // Automated rendering must fail with an exit code, never wait
                // for an unseen startup error dialog during a release build.
                if (!smoke) MessageBox.Show("프로그램을 시작할 수 없습니다. 설치 상태를 확인하세요.", "Excel 암호 관리", MessageBoxButton.OK, MessageBoxImage.Error);
                return 1;
            }
        }

        static int RenderSmoke(string output)
        {
            output = Path.GetFullPath(output);
            Directory.CreateDirectory(output);
            string[] states = { "target", "operation", "encrypt", "decrypt", "change", "folder-encrypt", "folder-decrypt", "folder-change",
                "progress", "success", "failure", "inspection", "empty", "input-error", "details" };
            int[] dpis = { 96, 144, 192 };
            var renders = new List<object>();
            string status = "FAIL", error = null, currentState = null;
            try
            {
                foreach (string state in states)
                {
                    currentState = state;
                    var window = new WizardWindow(null, false, null, true);
                    try
                    {
                        window.ShowInTaskbar = false; window.ShowActivated = false;
                        window.WindowStartupLocation = WindowStartupLocation.Manual;
                        window.Left = -10000; window.Top = -10000;
                        window.RenderSmoke(state);
                        window.Show();
                        window.Dispatcher.Invoke(DispatcherPriority.Loaded, new Action(delegate { }));
                        window.UpdateLayout(); window.CheckLayout();
                        foreach (int dpi in dpis) renders.Add(Render(window, output, state, dpi, false));
                        window.Width = 420; window.Height = 360;
                        window.UpdateLayout(); window.CheckLayout();
                        if (Math.Abs(window.ActualWidth - 420) > 1 || Math.Abs(window.ActualHeight - 360) > 1)
                            throw new InvalidOperationException("The small-window check must actually use a 420x360 window.");
                        renders.Add(Render(window, output, state, 96, true));
                    }
                    finally { window.FinishSmoke(); }
                }
                status = "PASS";
            }
            catch (Exception ex) { error = ex.ToString(); }
            var record = new {
                status, renders = renders.Count, states = states.Length, dpi = dpis, smallViewport = "420x360", currentState, error, images = renders,
                note = "WPF client-content rendering and actual layout/footer checks. DPI values scale exported images; physical high-DPI monitors and interactive Explorer/Excel checks are separate.",
                timestamp = DateTime.UtcNow.ToString("o")
            };
            File.WriteAllText(Path.Combine(output, "smoke-result.json"), new JavaScriptSerializer().Serialize(record), new UTF8Encoding(false));
            return status == "PASS" ? 0 : 1;
        }

        static object Render(WizardWindow window, string output, string state, int dpi, bool small)
        {
            var surface = window.Content as FrameworkElement;
            if (surface == null || surface.ActualWidth < 1 || surface.ActualHeight < 1)
                throw new InvalidOperationException("The wizard has no laid-out client content.");
            int width = (int)Math.Ceiling(surface.ActualWidth * dpi / 96.0);
            int height = (int)Math.Ceiling(surface.ActualHeight * dpi / 96.0);
            var bitmap = new RenderTargetBitmap(width, height, dpi, dpi, PixelFormats.Pbgra32);
            bitmap.Render(surface);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            string fileName = state + (small ? "-small" : "-" + dpi) + ".png";
            using (var stream = File.Create(Path.Combine(output, fileName))) encoder.Save(stream);
            return new { state, step = window.Step.ToString(), dpi, small, fileName, width, height,
                windowWidth = window.ActualWidth, windowHeight = window.ActualHeight,
                clientWidth = surface.ActualWidth, clientHeight = surface.ActualHeight, layout = "PASS" };
        }
    }
}
