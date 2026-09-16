using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string output = args.Length >= 1 ? Path.GetFullPath(args[0]) : Path.GetFullPath("artifacts/ui-preview.png");
        int width = args.Length >= 3 ? int.Parse(args[1]) : 960;
        int height = args.Length >= 3 ? int.Parse(args[2]) : 740;
        if (width < 760 || height < 680) throw new ArgumentException("Use a supported window size (at least 760 x 680).");
        var application = new FolderState.App.App(); application.InitializeComponent();
        var window = new FolderState.App.MainWindow();
        var content = (FrameworkElement)window.Content;
        content.Measure(new Size(width, height)); content.Arrange(new Rect(0, 0, width, height)); content.UpdateLayout();
        if (args.Contains("expanded"))
            foreach (var expander in Descendants(content).OfType<Expander>()) expander.IsExpanded = true;
        if (args.Contains("message") && window.FindName("ResultText") is TextBlock result)
            result.Text = "이 폴더의 상태를 바꾸지 못했습니다. 폴더를 사용하는 다른 프로그램을 닫고 다시 시도하세요.\n문제가 계속되면 작업 기록을 확인하세요. (화면 확인용 예시)";
        content.Measure(new Size(width, height)); content.Arrange(new Rect(0, 0, width, height)); content.UpdateLayout();
        if (args.Contains("bottom"))
        {
            Descendants(content).OfType<ScrollViewer>().First().ScrollToEnd();
            content.UpdateLayout();
        }
        var images = Descendants(content).OfType<Image>().ToArray();
        if (images.Length != 4 || images.Any(i => i.Source is null || i.Source.Width < 16)) throw new Exception("Status icons failed to load.");
        if (window.FindName("FolderPath") is not TextBox || window.FindName("RepairButton") is not Button) throw new Exception("Required controls are missing.");
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(content);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        Directory.CreateDirectory(Path.GetDirectoryName(output)!); using (var stream = File.Create(output)) encoder.Save(stream);
        Console.WriteLine("PASS WPF layout and four status icons. Preview: " + output);
        window.Close(); application.Shutdown(); return 0;
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        { var child = VisualTreeHelper.GetChild(parent, i); yield return child; foreach (var item in Descendants(child)) yield return item; }
    }
}
