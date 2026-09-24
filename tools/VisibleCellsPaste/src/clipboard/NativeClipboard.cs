using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace VisibleCellsPaste
{
    public static class NativeClipboard
    {
        [DllImport("user32.dll", SetLastError = true)] private static extern bool OpenClipboard(IntPtr window);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool CloseClipboard();
        [DllImport("user32.dll", SetLastError = true)] private static extern uint EnumClipboardFormats(uint format);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClipboardFormatName(uint format, StringBuilder name, int size);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterClipboardFormat(string name);
        [DllImport("user32.dll")] private static extern bool IsClipboardFormatAvailable(uint format);
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr GetClipboardData(uint format);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalLock(IntPtr memory);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GlobalUnlock(IntPtr memory);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern UIntPtr GlobalSize(IntPtr memory);
        [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
        [DllImport("user32.dll")] public static extern IntPtr GetClipboardOwner();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);

        private static void OpenReadOnly()
        {
            for (int attempt = 0; attempt < 4; attempt++)
            {
                if (OpenClipboard(IntPtr.Zero)) return;
                Thread.Sleep(25);
            }
            throw new ValidationException("VCP-CLIPBOARD-BUSY", "클립보드를 읽을 수 없습니다. 잠시 후 다시 시도해 주세요. 변경된 셀은 없습니다.");
        }
        public static ReadOnlyCollection<string> ProbeFormats()
        {
            OpenReadOnly();
            try
            {
                var result = new List<string>();
                uint format = 0;
                while ((format = EnumClipboardFormats(format)) != 0)
                {
                    var name = new StringBuilder(256);
                    if (GetClipboardFormatName(format, name, name.Capacity) == 0) name.Append("CF_" + format);
                    result.Add(format + ":" + name.ToString());
                }
                return result.AsReadOnly();
            }
            finally { CloseClipboard(); }
        }
        public static bool HasFormat(string format) { return IsClipboardFormatAvailable(RegisterClipboardFormat(format)); }
        public static byte[] ReadFormatBytes(string name)
        {
            uint sequence;
            return ReadFormatBytes(name, out sequence);
        }
        public static byte[] ReadFormatBytes(string name, out uint capturedSequence)
        { return ReadFormatBytes(name, Limits.MaxPayloadBytes, out capturedSequence); }

        public static byte[] ReadFormatBytes(string name, int maximumBytes, out uint capturedSequence)
        {
            if (maximumBytes <= 0 || maximumBytes > Limits.MaxPayloadBytes)
                throw new ValidationException("VCP-CLIPBOARD-LIMIT", "읽을 클립보드 데이터 합계는 최대 32 MiB입니다. 변경된 셀은 없습니다.");
            for (int attempt = 0; attempt < 3; attempt++)
            {
                uint before = GetClipboardSequenceNumber();
                byte[] payload;
                OpenReadOnly();
                try
                {
                    uint format = RegisterClipboardFormat(name);
                    if (!IsClipboardFormatAvailable(format))
                        throw new ValidationException("VCP-CLIPBOARD-FORMAT", "필요한 Excel 구조화 복사 형식이 없습니다. Excel에서 한 행 또는 한 열을 다시 복사해 주세요. 변경된 셀은 없습니다.");
                    IntPtr handle = GetClipboardData(format);
                    if (handle == IntPtr.Zero) throw new ValidationException("VCP-CLIPBOARD-DATA", "Excel 복사 데이터를 읽을 수 없습니다. 변경된 셀은 없습니다.");
                    ulong size = GlobalSize(handle).ToUInt64();
                    if (size == 0 || size > (ulong)maximumBytes)
                        throw new ValidationException("VCP-CLIPBOARD-LIMIT", "클립보드 데이터는 0보다 크고 최대 32 MiB여야 합니다. 변경된 셀은 없습니다.");
                    IntPtr pointer = GlobalLock(handle);
                    if (pointer == IntPtr.Zero) throw new ValidationException("VCP-CLIPBOARD-LOCK", "복사 데이터를 잠글 수 없습니다. 변경된 셀은 없습니다.");
                    try { payload = new byte[(int)size]; Marshal.Copy(pointer, payload, 0, payload.Length); }
                    finally { GlobalUnlock(handle); }
                }
                finally { CloseClipboard(); }
                uint after = GetClipboardSequenceNumber();
                if (before == after) { capturedSequence = after; return payload; }
                Thread.Sleep(25);
            }
            throw new ValidationException("VCP-CLIPBOARD-CHANGED", "읽는 동안 복사 데이터가 바뀌었습니다. 다시 복사해 주세요. 변경된 셀은 없습니다.");
        }
    }
}
