// Synthetic input for actual Explorer UI acceptance. Never reads clipboard data.
using System;
using System.Windows.Forms;

internal static class ClipboardFixture
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 2 || args[1] != "--acknowledge-clipboard-overwrite" ||
            (args[0] != "clear" && args[0] != "text"))
        {
            Console.Error.WriteLine("Usage: ClipboardFixture clear|text --acknowledge-clipboard-overwrite");
            return 64;
        }
        try
        {
            if (args[0] == "clear") Clipboard.Clear();
            else Clipboard.SetText("ImageCopySave G0 synthetic text");
            Console.WriteLine("PASS synthetic clipboard fixture: " + args[0]);
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error.GetType().Name + ": " + error.Message);
            return 1;
        }
    }
}
