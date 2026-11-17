using System.Runtime.InteropServices;

namespace ExcelPasswordSafe.Crypto {
    // Kept separate so fault tests can compile an isolated replacement; the
    // product contains only these Windows imports and has no fault switches.
    internal static class NativeHashApi {
        [DllImport("bcrypt.dll", EntryPoint="BCryptOpenAlgorithmProvider", CharSet=CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int OpenAlgorithm(out IntPtr result, string algorithm, string provider, uint flags);
        [DllImport("bcrypt.dll", EntryPoint="BCryptGetProperty", CharSet=CharSet.Unicode)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int GetProperty(IntPtr handle, string property, out int result, int size, out int returned, uint flags);
        [DllImport("bcrypt.dll", EntryPoint="BCryptCreateHash")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int CreateHash(IntPtr algorithm, out IntPtr hash, IntPtr buffer, int length, IntPtr secret, int secretLength, uint flags);
        [DllImport("bcrypt.dll", EntryPoint="BCryptHashData")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int HashData(IntPtr hash, [In] byte[] input, int length, uint flags);
        [DllImport("bcrypt.dll", EntryPoint="BCryptFinishHash")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int FinishHash(IntPtr hash, [Out] byte[] output, int length, uint flags);
        [DllImport("bcrypt.dll", EntryPoint="BCryptDestroyHash")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int DestroyHash(IntPtr hash);
        [DllImport("bcrypt.dll", EntryPoint="BCryptCloseAlgorithmProvider")]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        internal static extern int CloseAlgorithm(IntPtr algorithm, uint flags);
    }
}
