using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using ImageCopySave.Engine;

namespace ImageCopySave.Tests;

public static partial class ClipboardTests
{
    private static partial class HelperProcessTests
    {
        private static ImageData OtherImage() => new(1, 2, [35, 67, 91, 255, 199, 51, 13, 79]);

        private static void SnapshotOtherCopy(string sources, string saves)
        {
            ClipboardEngine.Copy(Fixture(), ClipboardEngine.CaptureSequence());
            ImageData snapshot = ClipboardEngine.Capture();
            uint initialSequence = ClipboardEngine.CaptureSequence();
            byte[] bytes = ImageCodec.EncodePng(OtherImage());
            string source = Path.Combine(sources, "snapshot-later-copy.png");
            File.WriteAllBytes(source, bytes);
            RunProduct(0, "copy", source); // A separate real product process publishes B.
            uint newerSequence = ClipboardEngine.CaptureSequence();
            Check.That(newerSequence != initialSequence, "Other-process copy did not update the clipboard.");
            CheckImage(OtherImage(), ClipboardEngine.Capture(), "other-process image B before snapshot save");
            // This exercises the public engine snapshot/save pipeline. It does not
            // claim an Explorer command or pause inside the product save supervisor.
            string saved = AtomicPngWriter.Save(snapshot, saves);
            Check.That(saved == ExactlyOneSaved(saves), "Snapshot pipeline created an unexpected output.");
            CheckImage(Fixture(), ImageCodec.Decode(File.ReadAllBytes(saved), ".png"), "snapshot A saved after other-process copy B");
            Check.That(ClipboardEngine.CaptureSequence() == newerSequence, "Saving snapshot A changed newer clipboard B.");
            CheckImage(OtherImage(), ClipboardEngine.Capture(), "newer B preserved after snapshot A save");
            AssertSourceUnchanged(source, bytes);
        }

        private static void CorruptClipboard(string saves)
        {
            byte[] badV5 = DibCodec.EncodeV5(Fixture())[..^4];
            BitConverter.GetBytes(1024).CopyTo(badV5, 8); // Declared raster far exceeds allocator padding.
            byte[] badDib = new byte[44];
            BitConverter.GetBytes(40).CopyTo(badDib, 0);
            BitConverter.GetBytes(1).CopyTo(badDib, 4);
            BitConverter.GetBytes(int.MinValue).CopyTo(badDib, 8); // Invalid/overflowing height.
            badDib[12] = 1; badDib[14] = 32;
            (uint Format, byte[] Bytes, string Label)[] inputs =
            [
                (N.RegisterClipboardFormat("PNG"), [0x49, 0x43, 0x53, 0x2D, 0x42, 0x41, 0x44], "corrupt PNG"),
                (17, badV5, "truncated DIBV5"),
                (8, badDib, "invalid DIB height")
            ];
            foreach (var input in inputs)
            {
                SetRaw((input.Format, input.Bytes), (13, Encoding.Unicode.GetBytes("corrupt-clipboard-preserve\0")));
                uint sequence = ClipboardEngine.CaptureSequence();
                Check.That(ClipboardEngine.HasSupportedImage(), input.Label + " was not advertised.");
                Check.That(ReadRawFixture(input.Format, input.Bytes.Length).AsSpan().SequenceEqual(input.Bytes),
                    input.Label + " initial raw fixture changed.");
                using var child = Product("save", saves);
                uint code = child.WaitForExit(10000);
                Check.That(code == 1, input.Label + $": expected helper exit 1, actual {code}. " + child.DiagnosticSummary());
                child.AssertNoSurvivingChildren();
                AssertNoFiles(saves, input.Label + " rejection");
                Check.That(ClipboardEngine.CaptureSequence() == sequence, input.Label + " helper rejection changed sequence.");
                Check.That(ReadRawFixture(input.Format, input.Bytes.Length).AsSpan().SequenceEqual(input.Bytes)
                    && ReadText() == "corrupt-clipboard-preserve", input.Label + " helper rejection changed raw clipboard content.");
            }
        }

        private static byte[] ReadRawFixture(uint format, int count)
        {
            VerifyPrivateStation(ActiveStation);
            Require(N.OpenClipboard(IntPtr.Zero), "inspect owned corrupt clipboard fixture");
            try
            {
                IntPtr handle = N.GetClipboardData(format);
                Require(handle != IntPtr.Zero, "get owned clipboard fixture");
                ulong size = LifecycleNative.GlobalSize(handle).ToUInt64();
                Check.That(size >= (ulong)count && size <= 1048576, "Owned raw fixture allocation has an unexpected size.");
                IntPtr pointer = N.GlobalLock(handle);
                Require(pointer != IntPtr.Zero, "lock owned clipboard fixture");
                try
                {
                    byte[] result = new byte[count];
                    Marshal.Copy(pointer, result, 0, count);
                    return result;
                }
                finally { N.GlobalUnlock(handle); }
            }
            finally { N.CloseClipboard(); }
        }

        private static void CopyPreparationRace(string sources)
        {
            byte[] olderBytes = ImageCodec.EncodePng(Fixture());
            byte[] newerBytes = ImageCodec.EncodePng(OtherImage());
            string olderSource = Path.Combine(sources, "prepare-older.png");
            string newerSource = Path.Combine(sources, "prepare-newer.png");
            File.WriteAllBytes(olderSource, olderBytes);
            File.WriteAllBytes(newerSource, newerBytes);
            using var preparation = new SourceOpenBarrier(olderSource);
            SetText("before-copy-preparation");
            uint originalSequence = ClipboardEngine.CaptureSequence();
            using var older = Product("copy", olderSource);
            preparation.WaitForBreak(older);
            // Public copy captures its expected sequence before launching the worker.
            // The file break has no initiating PID: a scanner could also trigger it.
            // The decisive result below is the older public copy rejecting its stale
            // sequence while newer B survives, not an attributed worker I/O stage.
            Check.That(ClipboardEngine.CaptureSequence() == originalSequence, "Copy changed clipboard before source preparation completed.");
            RunProduct(0, "copy", newerSource);
            uint newerSequence = ClipboardEngine.CaptureSequence();
            Check.That(newerSequence != originalSequence, "Newer process did not copy while the older preparation was held.");
            CheckImage(OtherImage(), ClipboardEngine.Capture(), "newer copy during actual helper preparation");
            preparation.Release();
            uint code = older.WaitForExit(10000);
            string diagnostic = older.DiagnosticSummary();
            Check.That(code == 1 && diagnostic.Contains("ClipboardChangedException", StringComparison.Ordinal),
                $"Older actual copy should reject its stale sequence, exit={code}. " + diagnostic);
            older.AssertNoSurvivingChildren();
            Check.That(ClipboardEngine.CaptureSequence() == newerSequence, "Older preparation overwrote newer clipboard sequence.");
            CheckImage(OtherImage(), ClipboardEngine.Capture(), "newer copy preserved after older preparation resumes");
            AssertSourceUnchanged(olderSource, olderBytes);
            AssertSourceUnchanged(newerSource, newerBytes);
        }

        private static void WorkerInflightCancel(string sources, string saves)
        {
            byte[] bytes = ImageCodec.EncodePng(Fixture());
            string source = Path.Combine(sources, "inflight-cancel-source.png");
            File.WriteAllBytes(source, bytes);
            using var preparation = new SourceOpenBarrier(source);
            SetText("inflight-worker-cancel-preserve");
            uint sequence = ClipboardEngine.CaptureSequence();
            string cancelName = "Local\\ImageCopySave-Cancel-" + Guid.NewGuid().ToString("N");
            using var cancel = new EventWaitHandle(false, EventResetMode.ManualReset, cancelName);
            using var worker = Product("--worker", "copy", source, cancelName,
                sequence.ToString(CultureInfo.InvariantCulture), ActiveStation, "Test");
            preparation.WaitForBreak(worker);
            Check.That(!cancel.WaitOne(0), "In-flight cancellation was incorrectly presignaled.");
            Check.That(ClipboardEngine.CaptureSequence() == sequence, "Worker committed before the preparation barrier.");
            cancel.Set();
            // The event started unsignaled, the process was launched, and a source-file
            // oplock break was observed before this signal. That break does not identify
            // its initiating PID or prove this worker has entered source I/O: a scanner
            // could trigger it before the worker registers cancellation. This grace
            // allows asynchronous delivery under the held oplock, without establishing
            // an exact operation stage or synchronous cancellation timing.
            Thread.Sleep(250);
            preparation.Release();
            uint code = worker.WaitForExit(10000);
            Check.That(code == 3, $"In-flight internal worker cancel expected exit 3, actual {code}. " + worker.DiagnosticSummary());
            worker.AssertNoSurvivingChildren();
            AssertSourceUnchanged(source, bytes);
            Check.That(ClipboardEngine.CaptureSequence() == sequence && ReadText() == "inflight-worker-cancel-preserve",
                "Cancellation during source preparation changed the previous clipboard.");
            AssertNoFiles(saves, "in-flight copy cancellation");
            // Proven scope: post-launch internal event request under an owned oplock
            // fixture, exit 3, preserved source/clipboard, and no surviving worker.
            // Exact worker I/O entry, public UI Ctrl+C, clipboard-retry cancellation,
            // and cancellation after the commit point are not established.
        }
    }

    /// <summary>
    /// Test-owned file-open barrier using the documented local batch oplock API.
    /// Break completion does not identify its initiating PID; process liveness does
    /// not attribute the break to a worker or establish that worker's I/O stage.
    /// </summary>
    private sealed class SourceOpenBarrier : IDisposable
    {
        private IntPtr file, signal, overlapped;
        private bool pending, retainNativeStorage;
        public SourceOpenBarrier(string source)
        {
            string full = Path.GetFullPath(source);
            string owner = Path.GetFullPath(Path.Combine(WorkerDirectory, "product-source"));
            Check.That(string.Equals(Path.GetDirectoryName(full), owner, StringComparison.OrdinalIgnoreCase)
                && (File.GetAttributes(full) & FileAttributes.ReparsePoint) == 0,
                "Oplock fixture must be an ordinary owned source file.");
            try
            {
                signal = LifecycleNative.CreateEvent(IntPtr.Zero, true, false, null);
                Require(signal != IntPtr.Zero, "create source preparation event");
                var attributes = new N.SecurityAttributes { Length = Marshal.SizeOf<N.SecurityAttributes>() };
                file = N.CreateFile(full, 0xC0000000 /* GENERIC_READ | WRITE */, 7, ref attributes, 3,
                    0x40200080 /* OVERLAPPED | OPEN_REPARSE_POINT | NORMAL */, IntPtr.Zero);
                if (file == new IntPtr(-1)) { file = IntPtr.Zero; throw new Win32Exception(Marshal.GetLastWin32Error(), "open owned oplock source"); }
                overlapped = Marshal.AllocHGlobal(Marshal.SizeOf<LifecycleNative.Overlapped>());
                Marshal.StructureToPtr(new LifecycleNative.Overlapped { Event = signal }, overlapped, false);
                // https://learn.microsoft.com/windows/win32/api/winioctl/ni-winioctl-fsctl_request_batch_oplock
                // CTL_CODE(FILE_DEVICE_FILE_SYSTEM, 2, METHOD_BUFFERED, FILE_ANY_ACCESS).
                bool completed = LifecycleNative.DeviceIoControl(file, 0x00090008, IntPtr.Zero, 0,
                    IntPtr.Zero, 0, IntPtr.Zero, overlapped);
                int error = Marshal.GetLastWin32Error();
                if (!completed && error is 1 or 50 or 300)
                    throw new TestUnavailableException($"Owned-source batch oplock prerequisite unavailable (native {error}); preparation timing was not inferred.");
                if (completed || error != 997 /* ERROR_IO_PENDING */)
                    throw new Win32Exception(error, "expected an asynchronous owned-source batch oplock");
                pending = true;
                Check.That(N.WaitForSingleObject(signal, 0) == 258, "Source oplock broke before any product worker was launched.");
            }
            catch { Dispose(); throw; }
        }

        public void WaitForBreak(NativeChild worker)
        {
            var timer = Stopwatch.StartNew();
            while (N.WaitForSingleObject(signal, 20) != 0)
            {
                Check.That(worker.IsRunning, "Product exited before source preparation barrier. " + worker.DiagnosticSummary());
                if (timer.ElapsedMilliseconds >= 5000)
                    throw new TimeoutException("Actual product source-open oplock break was not observed.");
            }
            // This confirms the file's break notification, not which opener caused it.
            Require(LifecycleNative.GetOverlappedResult(file, overlapped, out _, false), "observe source preparation oplock break");
            pending = false;
            Check.That(worker.IsRunning, "Product did not remain alive at source preparation barrier.");
        }

        public void Release() => Dispose();

        public void Dispose()
        {
            if (retainNativeStorage) return;
            if (file != IntPtr.Zero && pending)
            {
                LifecycleNative.CancelIoEx(file, overlapped);
                uint wait = N.WaitForSingleObject(signal, 2000);
                if (wait != 0)
                {
                    N.CloseHandle(file); file = IntPtr.Zero;
                    wait = N.WaitForSingleObject(signal, 2000);
                    if (wait != 0)
                    {
                        // Never free OVERLAPPED/event storage while the kernel may still
                        // reference it. The bounded case process/job is the final owner.
                        retainNativeStorage = true;
                        throw new TimeoutException("Owned oplock cancellation did not complete; its native storage remains until case process exit.");
                    }
                }
                pending = false;
            }
            if (file != IntPtr.Zero) { N.CloseHandle(file); file = IntPtr.Zero; } // Acknowledge break and release blocked opener.
            if (overlapped != IntPtr.Zero) { Marshal.FreeHGlobal(overlapped); overlapped = IntPtr.Zero; }
            if (signal != IntPtr.Zero) { N.CloseHandle(signal); signal = IntPtr.Zero; }
        }
    }

    private static class LifecycleNative
    {
        [StructLayout(LayoutKind.Sequential)] internal struct Overlapped
        { internal nuint Internal, InternalHigh; internal uint Offset, OffsetHigh; internal IntPtr Event; }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr CreateEvent(IntPtr security, [MarshalAs(UnmanagedType.Bool)] bool manualReset, [MarshalAs(UnmanagedType.Bool)] bool initialState, string? name);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool DeviceIoControl(IntPtr file, uint code, IntPtr input, uint inputLength, IntPtr output, uint outputLength, IntPtr returned, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetOverlappedResult(IntPtr file, IntPtr overlapped, out uint transferred, [MarshalAs(UnmanagedType.Bool)] bool wait);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CancelIoEx(IntPtr file, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern UIntPtr GlobalSize(IntPtr value);
    }
}
