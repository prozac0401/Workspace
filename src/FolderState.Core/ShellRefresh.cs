using System.Runtime.InteropServices;

namespace FolderState.Core;

internal static class ShellRefresh
{
    // Windows caches desktop.ini customization independently from the image list.
    // Re-assert the same owned IconResource through the Shell API. The engine
    // journals this step, verifies exact INI bytes and restores final attributes.
    public static string? UpdateIcon(string folder, string icon)
    {
        if (!OperatingSystem.IsWindows()) return null;
        if (folder.Length >= 260)
            return "상태는 저장했습니다. 긴 경로는 Windows 폴더 설정 갱신 API의 범위를 넘어 화면 반영이 지연될 수 있습니다.";
        int initialized = CoInitializeEx(IntPtr.Zero, 0);
        try
        {
            if (initialized < 0 && initialized != unchecked((int)0x80010106)) Marshal.ThrowExceptionForHR(initialized);
            using var iconText = new UnicodeString(icon);
            var settings = new FolderCustomSettings { Size = (uint)Marshal.SizeOf<FolderCustomSettings>(), Mask = 0x10, IconFile = iconText.Pointer };
            Marshal.ThrowExceptionForHR(SHGetSetFolderCustomSettings(ref settings, folder, 2)); // FCS_FORCEWRITE, FCSM_ICONFILE
            return null;
        }
        catch (Exception ex) when (ex is ExternalException)
        { return "상태는 저장했지만 Windows 폴더 설정 캐시를 갱신하지 못했습니다. 해당 창을 새로고침해 주세요."; }
        finally { if (initialized >= 0) CoUninitialize(); }
    }
    private sealed class UnicodeString(string value) : IDisposable
    {
        public IntPtr Pointer { get; } = Marshal.StringToCoTaskMemUni(value);
        public void Dispose() => Marshal.FreeCoTaskMem(Pointer);
    }
    public static string? Notify(string folder)
    {
        if (!OperatingSystem.IsWindows()) return null;
        IntPtr pidl = IntPtr.Zero;
        int initialized = CoInitializeEx(IntPtr.Zero, 0); // MTA; an existing STA is also usable.
        try
        {
            if (initialized < 0 && initialized != unchecked((int)0x80010106)) Marshal.ThrowExceptionForHR(initialized);
            Marshal.ThrowExceptionForHR(SHParseDisplayName(folder, IntPtr.Zero, out pidl, 0, out _));
            // A PIDL avoids SHCNF_PATH's MAX_PATH limit. Deliver this item notification
            // before exiting; a following parent UPDATEDIR can coalesce the item update.
            SHChangeNotify(0x2000, 0x1000, pidl, IntPtr.Zero); // UPDATEITEM | IDLIST | FLUSH
            return null;
        }
        catch (Exception ex) when (ex is COMException or ExternalException)
        { return "상태는 저장했지만 탐색기에 갱신 알림을 전달하지 못했습니다. 해당 창을 새로고침해 주세요."; }
        finally
        {
            if (pidl != IntPtr.Zero) Marshal.FreeCoTaskMem(pidl);
            if (initialized >= 0) CoUninitialize();
        }
    }
    [DllImport("ole32.dll")] private static extern int CoInitializeEx(IntPtr reserved, uint mode);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHParseDisplayName(string name, IntPtr bindContext, out IntPtr pidl, uint attributes, out uint found);
    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
    [StructLayout(LayoutKind.Sequential)]
    private struct FolderCustomSettings
    {
        public uint Size, Mask;
        public IntPtr ViewId, WebViewTemplate;
        public uint WebViewTemplateChars;
        public IntPtr WebViewTemplateVersion, InfoTip;
        public uint InfoTipChars;
        public IntPtr ClassId;
        public uint Flags;
        public IntPtr IconFile;
        public uint IconFileChars;
        public int IconIndex;
        public IntPtr Logo;
        public uint LogoChars;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHGetSetFolderCustomSettings(ref FolderCustomSettings settings, string path, uint readWrite);
}
