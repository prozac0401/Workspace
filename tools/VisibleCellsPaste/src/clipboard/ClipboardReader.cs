using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace VisibleCellsPaste
{
    public sealed class CopyEvidence
    {
        public uint OwnerProcessId { get; private set; }
        public long OwnerWindow { get; private set; }
        public int CutCopyMode { get; private set; }
        public string Method { get; private set; }
        internal CopyEvidence(uint pid, IntPtr window, int mode, string method)
        { OwnerProcessId = pid; OwnerWindow = window.ToInt64(); CutCopyMode = mode; Method = method; }
        public override string ToString() { return "ownerPid=" + OwnerProcessId + ";CutCopyMode=" + CutCopyMode + ";" + Method; }
    }

    public static class ClipboardReader
    {
        private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lparam);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lparam);
        [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr lparam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int size);
        [DllImport("oleacc.dll")] private static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint objectId, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out object result);

        // currentCutCopyMode belongs to this add-in's Excel process, never to an arbitrary active Excel instance.
        public static ClipboardSnapshot ReadSnapshot(int currentCutCopyMode)
        {
            for (int attempt = 0; attempt < 3; attempt++)
            {
                uint before = NativeClipboard.GetClipboardSequenceNumber();
                CopyEvidence proof = ProbeCopyEvidence(currentCutCopyMode);
                long total = 0;
                if (NativeClipboard.HasFormat("Preferred DropEffect"))
                {
                    uint effectSequence;
                    byte[] effect = NativeClipboard.ReadFormatBytes("Preferred DropEffect", out effectSequence);
                    total += effect.Length;
                    if (effect.Length < 4 || (BitConverter.ToUInt32(effect, 0) & 2) != 0)
                        throw new ValidationException("VCP-CLIPBOARD-CUT", "잘라내기 이동은 지원하지 않습니다. Ctrl+C로 다시 복사해 주세요. 변경된 셀은 없습니다.");
                    if (effectSequence != before) continue;
                }
                uint capturedSequence;
                byte[] xml = NativeClipboard.ReadFormatBytes("XML Spreadsheet", (int)(Limits.MaxPayloadBytes - total), out capturedSequence);
                total += xml.Length;
                if (total > Limits.MaxPayloadBytes)
                    throw new ValidationException("VCP-CLIPBOARD-LIMIT", "읽을 클립보드 데이터 합계는 최대 32 MiB입니다. 변경된 셀은 없습니다.");
                if (before != capturedSequence) continue;
                ClipboardSnapshot snapshot;
                try { snapshot = SpreadsheetXmlParser.Parse(xml, capturedSequence, proof.ToString()); }
                catch (ValidationException error)
                {
                    if (error.Code != "VCP-XML-DATE-SERIAL" || !NativeClipboard.HasFormat("Biff12")) throw;
                    uint nativeSequence;
                    byte[] native = NativeClipboard.ReadFormatBytes("Biff12", (int)(Limits.MaxPayloadBytes - total), out nativeSequence);
                    if (nativeSequence != before) continue;
                    snapshot = SpreadsheetXmlParser.ParseWithNative(xml, native, capturedSequence, proof.ToString());
                }
                // Recheck ownership and mode after delayed rendering; retain no application or source-cell references.
                CopyEvidence afterProof = ProbeCopyEvidence(currentCutCopyMode);
                if (before != capturedSequence || before != NativeClipboard.GetClipboardSequenceNumber() ||
                    proof.OwnerProcessId != afterProof.OwnerProcessId || proof.OwnerWindow != afterProof.OwnerWindow) continue;
                return snapshot;
            }
            throw new ValidationException("VCP-CLIPBOARD-CHANGED", "읽는 동안 복사 데이터가 바뀌었습니다. 다시 복사해 주세요. 변경된 셀은 없습니다.");
        }

        public static CopyEvidence ProbeCopyEvidence(int currentCutCopyMode)
        {
            IntPtr owner = NativeClipboard.GetClipboardOwner();
            uint pid;
            NativeClipboard.GetWindowThreadProcessId(owner, out pid);
            if (owner == IntPtr.Zero || pid == 0) throw UnknownSource();
            try
            {
                using (Process process = Process.GetProcessById((int)pid))
                {
                    if (!String.Equals(process.ProcessName, "EXCEL", StringComparison.OrdinalIgnoreCase)) throw UnknownSource();
                }
            }
            catch (ArgumentException) { throw UnknownSource(); }
            catch (InvalidOperationException) { throw UnknownSource(); }
            catch (Win32Exception) { throw UnknownSource(); }
            if (pid == (uint)Process.GetCurrentProcess().Id)
                return RequireCopy(pid, owner, currentCutCopyMode, "current Excel process");

            // An owner-PID-bound native Excel object model is used only to inspect CutCopyMode.
            // This never reads a source range or assumes that a currently active cell is the copied range.
            var windows = new List<IntPtr>();
            EnumWindowsProc children = delegate(IntPtr window, IntPtr ignored)
            {
                uint childPid; NativeClipboard.GetWindowThreadProcessId(window, out childPid);
                if (childPid == pid)
                {
                    var name = new StringBuilder(128); GetClassName(window, name, name.Capacity);
                    if (String.Equals(name.ToString(), "EXCEL7", StringComparison.OrdinalIgnoreCase)) windows.Add(window);
                }
                return true;
            };
            EnumWindows(delegate(IntPtr window, IntPtr ignored)
            {
                uint windowPid; NativeClipboard.GetWindowThreadProcessId(window, out windowPid);
                if (windowPid == pid) { children(window, IntPtr.Zero); EnumChildWindows(window, children, IntPtr.Zero); }
                return true;
            }, IntPtr.Zero);

#if VCP_DIAGNOSTIC
            Console.Error.WriteLine("Native Excel windows=" + windows.Count);
#endif
            foreach (IntPtr window in windows)
            {
                object native = null, app = null;
                try
                {
                    Guid iid = new Guid("00020400-0000-0000-C000-000000000046");
                    int hr = AccessibleObjectFromWindow(window, 0xfffffff0, ref iid, out native);
#if VCP_DIAGNOSTIC
                    Console.Error.WriteLine("Window=" + window + "; HRESULT=" + hr + "; native=" + (native != null));
#endif
                    if (hr != 0 || native == null) continue;
                    app = Get(native, "Application");
                    int mode = Convert.ToInt32(Get(app, "CutCopyMode"), CultureInfo.InvariantCulture);
                    return RequireCopy(pid, owner, mode, "clipboard-owner PID native object model");
                }
                catch (ValidationException) { throw; }
                catch (COMException ex) { DiagnosticException(ex); }
                catch (TargetInvocationException ex) { DiagnosticException(ex); }
                finally
                {
                    if (app != null && !Object.ReferenceEquals(app, native) && Marshal.IsComObject(app)) Marshal.ReleaseComObject(app);
                    if (native != null && Marshal.IsComObject(native)) Marshal.ReleaseComObject(native);
                }
            }
            throw UnknownSource();
        }
        [Conditional("VCP_DIAGNOSTIC")]
        private static void DiagnosticException(Exception error) { Console.Error.WriteLine(error); }
        private static object Get(object value, string name)
        { return value.GetType().InvokeMember(name, BindingFlags.GetProperty, null, value, null, CultureInfo.GetCultureInfo("en-US")); }
        private static CopyEvidence RequireCopy(uint pid, IntPtr owner, int mode, string method)
        {
            if (mode == 2)
                throw new ValidationException("VCP-CLIPBOARD-CUT", "잘라내기 이동은 지원하지 않습니다. Ctrl+C로 다시 복사해 주세요. 변경된 셀은 없습니다.");
            if (mode != 1) throw UnknownSource();
            return new CopyEvidence(pid, owner, mode, method);
        }
        private static ValidationException UnknownSource()
        {
            return new ValidationException("VCP-CLIPBOARD-COPY-UNVERIFIED", "Excel의 일반 복사인지 확인할 수 없습니다. 원본 Excel을 열어 둔 상태에서 Ctrl+C로 다시 복사해 주세요. 변경된 셀은 없습니다.");
        }
    }
}
