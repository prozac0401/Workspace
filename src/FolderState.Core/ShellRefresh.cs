using System.Runtime.InteropServices;

namespace FolderState.Core;

internal static class ShellRefresh
{
    public static void Notify(string folder)
    {
        if (!OperatingSystem.IsWindows()) return;
        const uint pathUnicode = 0x0005, flushNoWait = 0x2000;
        SHChangeNotify(0x2000, pathUnicode | flushNoWait, folder, IntPtr.Zero); // SHCNE_UPDATEITEM
        SHChangeNotify(0x1000, pathUnicode | flushNoWait, Path.GetDirectoryName(folder)!, IntPtr.Zero); // SHCNE_UPDATEDIR
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern void SHChangeNotify(uint eventId, uint flags, string item1, IntPtr item2);
}
