// Synthetic input for actual Explorer UI acceptance. Never reads clipboard data.
using System;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Globalization;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

internal static class ClipboardFixture
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool metadata = args.Length == 1 && args[0] == "metadata";
        bool sequence = args.Length == 1 && args[0] == "sequence";
        bool ordinary = args.Length == 2 && args[1] == "--acknowledge-clipboard-overwrite" &&
            (args[0] == "clear" || args[0] == "text" || args[0] == "url-only" || args[0] == "html-only" ||
             args[0] == "image-only" || args[0] == "mixed-image");
        bool fileDrop = args.Length == 3 && args[0] == "filedrop-only" &&
            args[2] == "--acknowledge-clipboard-overwrite";
        if (!metadata && !sequence && !ordinary && !fileDrop)
        {
            Console.Error.WriteLine("Usage: ClipboardFixture clear|text|url-only|html-only|image-only|mixed-image --acknowledge-clipboard-overwrite");
            Console.Error.WriteLine("       ClipboardFixture filedrop-only <absolute synthetic fixture file> --acknowledge-clipboard-overwrite");
            Console.Error.WriteLine("       ClipboardFixture metadata|sequence");
            return 64;
        }
        try
        {
            if (metadata) { PrintFormatNames(); return 0; }
            if (sequence) { Console.WriteLine(GetClipboardSequenceNumber().ToString(CultureInfo.InvariantCulture)); return 0; }
            if (fileDrop)
            {
                // Validate the explicit fixture path before replacing any clipboard data.
                // The file's contents are never opened or read.
                string path = args[1];
                string root = Path.GetPathRoot(path);
                if (String.IsNullOrEmpty(root) || root.Length != 3 || root[1] != ':' ||
                    (root[2] != '\\' && root[2] != '/') || !File.Exists(path) ||
                    (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                {
                    Console.Error.WriteLine("An existing absolute local synthetic file without a reparse attribute is required.");
                    return 64;
                }
                var files = new StringCollection();
                files.Add(Path.GetFullPath(path));
                Clipboard.SetFileDropList(files);
            }
            else if (args[0] == "clear") Clipboard.Clear();
            else if (args[0] == "text") Clipboard.SetText("ImageCopySave G0 synthetic text");
            else if (args[0] == "url-only") Clipboard.SetText("https://example.invalid/image.png");
            else if (args[0] == "image-only" || args[0] == "mixed-image") PublishImage(args[0] == "mixed-image");
            else
            {
                var data = new DataObject();
                data.SetData(DataFormats.Html, false, HtmlFixture());
                Clipboard.SetDataObject(data, true);
            }
            Console.WriteLine("PASS synthetic clipboard fixture: " + args[0]);
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error.GetType().Name + ": clipboard fixture operation failed.");
            return 1;
        }
    }

    private static void PublishImage(bool withText)
    {
        // Entirely synthetic pixels; no user file or existing clipboard content is read.
        using (var bitmap = new Bitmap(8, 8, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
        {
            for (int y = 0; y < bitmap.Height; y++)
                for (int x = 0; x < bitmap.Width; x++)
                    bitmap.SetPixel(x, y, Color.FromArgb(255, x * 31, y * 31, 64));
            var data = new DataObject();
            data.SetData(DataFormats.Bitmap, true, bitmap);
            if (withText) data.SetData(DataFormats.UnicodeText, false, "ImageCopySave G0 synthetic image and text");
            Clipboard.SetDataObject(data, true);
        }
    }

    private static string HtmlFixture()
    {
        const string html = "<html><body><!--StartFragment--><p>ImageCopySave synthetic HTML fixture</p><!--EndFragment--></body></html>";
        const string header = "Version:0.9\r\nStartHTML:{0:D10}\r\nEndHTML:{1:D10}\r\nStartFragment:{2:D10}\r\nEndFragment:{3:D10}\r\n";
        int start = Encoding.UTF8.GetByteCount(String.Format(CultureInfo.InvariantCulture, header, 0, 0, 0, 0));
        int fragment = html.IndexOf("<!--StartFragment-->", StringComparison.Ordinal) + "<!--StartFragment-->".Length;
        int fragmentEnd = html.IndexOf("<!--EndFragment-->", StringComparison.Ordinal);
        return String.Format(CultureInfo.InvariantCulture, header, start, start + Encoding.UTF8.GetByteCount(html),
            start + Encoding.UTF8.GetByteCount(html.Substring(0, fragment)),
            start + Encoding.UTF8.GetByteCount(html.Substring(0, fragmentEnd))) + html;
    }

    private static void PrintFormatNames()
    {
        // Native metadata enumeration only: no GetClipboardData, OLE data object,
        // delayed rendering request, user-content snapshot or automatic restore.
        if (!OpenClipboard(IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            string[] standard = { "", "CF_TEXT", "CF_BITMAP", "CF_METAFILEPICT", "CF_SYLK", "CF_DIF",
                "CF_TIFF", "CF_OEMTEXT", "CF_DIB", "CF_PALETTE", "CF_PENDATA", "CF_RIFF", "CF_WAVE",
                "CF_UNICODETEXT", "CF_ENHMETAFILE", "CF_HDROP", "CF_LOCALE", "CF_DIBV5" };
            uint format = 0;
            while (true)
            {
                SetLastError(0);
                format = EnumClipboardFormats(format);
                if (format == 0)
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error != 0) throw new Win32Exception(error);
                    break;
                }
                if (format < standard.Length) Console.WriteLine(standard[format]);
                else
                {
                    var name = new StringBuilder(256);
                    Console.WriteLine(GetClipboardFormatName(format, name, name.Capacity) > 0
                        ? name.ToString() : "format-" + format.ToString(CultureInfo.InvariantCulture));
                }
            }
        }
        finally { CloseClipboard(); }
    }

    [DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint EnumClipboardFormats(uint format);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClipboardFormatName(uint format, StringBuilder name, int length);
    [DllImport("kernel32.dll")]
    private static extern void SetLastError(uint code);
}
