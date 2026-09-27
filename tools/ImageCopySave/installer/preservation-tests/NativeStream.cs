using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace ImageCopySave.PreservationTests {
    // Test-only stream I/O. FileStream(string, ...) in Windows PowerShell's
    // .NET Framework rejects ADS syntax; retain Win32's safe handle instead.
    public static class NativeStream {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, ExactSpelling=true)]
        private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        public static FileStream Open(string path, bool createNew) {
            if (String.IsNullOrWhiteSpace(path) || path.IndexOf(':', 2) < 0) throw new ArgumentException("Expected a named file stream.");
            var handle=CreateFileW(path, createNew ? 0x40000000u : 0x80000000u, createNew ? 0u : 1u, IntPtr.Zero, createNew ? 1u : 3u, 0x80u, IntPtr.Zero);
            if(handle.IsInvalid) {var error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
            try {return new FileStream(handle,createNew ? FileAccess.Write : FileAccess.Read);} catch {handle.Dispose();throw;}
        }
    }
}
