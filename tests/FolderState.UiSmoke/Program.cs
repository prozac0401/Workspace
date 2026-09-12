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
        string output = args.Length == 1 ? Path.GetFullPath(args[0]) : Path.GetFullPath("artifacts/ui-preview.png");
        var application = new FolderState.App.App(); application.InitializeComponent();
        var window = new FolderState.App.MainWindow();
        var content = (FrameworkElement)window.Content;
        content.Measure(new Size(960, 740)); content.Arrange(new Rect(0, 0, 960, 740)); content.UpdateLayout();
        var images = Descendants(content).OfType<Image>().ToArray();
        if (images.Length != 4 || images.Any(i => i.Source is null || i.Source.Width < 16)) throw new Exception("Status icons failed to load.");
        if (window.FindName("FolderPath") is not TextBox || window.FindName("RepairButton") is not Button) throw new Exception("Required controls are missing.");
        var bitmap = new RenderTargetBitmap(960, 740, 96, 96, PixelFormats.Pbgra32); bitmap.Render(content);
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
