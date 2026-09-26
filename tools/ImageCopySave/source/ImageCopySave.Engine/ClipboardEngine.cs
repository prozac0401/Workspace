using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ImageCopySave.Engine;

/// <summary>Win32 clipboard snapshot and eager publication. Does not reference source files.</summary>
public static class ClipboardEngine
{
    private const uint CfBitmap = 2, CfDib = 8, CfDibV5 = 17;
    private const int Attempts = 12, RetryMilliseconds = 25;
    // DIB headers/masks/color tables accompany the bounded normalized buffer.
    private const long MaxDibBytes = ImageLimits.MaxBufferBytes + 124L;
    private static uint Png => Native.RegisterClipboardFormat("PNG");

    /// <summary>Metadata only; lock contention and failed format registration fail closed.</summary>
    public static bool HasSupportedImage()
    {
        if (!OperatingSystem.IsWindows()) return false;
        uint png = Png;
        if (png == 0 || !Native.OpenClipboard(IntPtr.Zero)) return false;
        try { return Native.IsClipboardFormatAvailable(png) || Native.IsClipboardFormatAvailable(CfDibV5)
            || Native.IsClipboardFormatAvailable(CfDib) || Native.IsClipboardFormatAvailable(CfBitmap); }
        finally { Native.CloseClipboard(); }
    }

    public static uint CaptureSequence()
    {
        EnsureWindows();
        return Native.GetClipboardSequenceNumber();
    }

    /// <summary>
    /// Copy one preferred representation while holding the clipboard lock, then decode independently.
    /// GetClipboardData may synchronously invoke an external delayed renderer. Its native call cannot
    /// be safely interrupted by a token: the caller MUST run this in a time-limited disposable helper.
    /// Sequence changes due to delayed rendering are deliberately not mistaken for new user copies.
    /// </summary>
    public static ImageData Capture(CancellationToken cancellationToken = default, uint? expectedSequence = null)
    {
        EnsureWindows();
        cancellationToken.ThrowIfCancellationRequested();
        uint png = Png;
        if (png == 0) throw Failure("register-format", false);
        byte[]? bytes = null;
        ImageData? bitmap = null;
        uint selected = 0;
        // Give this synchronous read a distinct, live opener on the calling thread. The API
        // excludes a different opener window while the clipboard is open. Opening does not take
        // ownership of the content: Capture never calls EmptyClipboard or SetClipboardData.
        // Keep the window alive through handle-to-byte copying, then close before decoding.
        // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-openclipboard
        using (var opener = new OwnerWindow())
        {
            Open(opener.Handle, cancellationToken);
            try
            {
                // Shell captures this at Invoke, before launching the helper. Reject a newer
                // copy under the lock, before asking an external provider to render anything.
                // Delayed rendering may itself change the sequence after this point; that is
                // accepted while our lock keeps the selected snapshot coherent.
                if (expectedSequence.HasValue && Native.GetClipboardSequenceNumber() != expectedSequence.Value)
                    throw new ClipboardChangedException();
                selected = SelectReadFormat(png, cancellationToken);
                if (selected != 0)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    IntPtr handle = Native.GetClipboardData(selected);
                    if (handle == IntPtr.Zero) throw Failure("read", false);
                    if (selected == CfBitmap) bitmap = SnapshotBitmap(handle);
                    else bytes = SnapshotMemory(handle, selected == png);
                }
            }
            finally { Native.CloseClipboard(); }
        }
        cancellationToken.ThrowIfCancellationRequested();
        if (bitmap != null) return bitmap;
        if (bytes == null) throw new InvalidDataException("The clipboard no longer contains a supported image.");
        ImageData result = selected == png ? ImageCodec.Decode(TrimPngAllocation(bytes), ".png") : DibCodec.Decode(TrimDibAllocation(bytes));
        result.Validate();
        cancellationToken.ThrowIfCancellationRequested();
        return result;
    }

    /// <summary>All encoding/allocation precedes EmptyClipboard. Once commit starts, it is not cancelled.</summary>
    public static void Copy(ImageData image, uint expectedSequence, CancellationToken cancellationToken = default)
    {
        EnsureWindows();
        cancellationToken.ThrowIfCancellationRequested();
        image.Validate();
        uint png = Png;
        if (png == 0) throw Failure("register-format", false);
        // Prepare every resource before touching existing clipboard content.
        using var pngMemory = OwnedMemory.Create(ImageCodec.EncodePng(image));
        cancellationToken.ThrowIfCancellationRequested();
        using var dibMemory = OwnedMemory.Create(DibCodec.EncodeV5(image));
        cancellationToken.ThrowIfCancellationRequested();
        using var owner = new OwnerWindow();
        Open(owner.Handle, cancellationToken);
        bool changed = false;
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Native.GetClipboardSequenceNumber() != expectedSequence)
                throw new ClipboardChangedException();
            if (!Native.EmptyClipboard()) throw Failure("empty", false);
            changed = true;
            Publish(png, pngMemory);
            Publish(CfDibV5, dibMemory);
        }
        catch (ClipboardOperationException) { throw; }
        catch (ClipboardChangedException) { throw; }
        catch (OperationCanceledException) when (!changed) { throw; }
        catch (Exception exception)
        {
            throw new ClipboardOperationException("Clipboard commit failed.", "commit", changed, exception);
        }
        finally { Native.CloseClipboard(); }
        // Eager HGLOBAL payloads are now Windows-owned and survive destruction of this window/process.
    }

    private static uint SelectReadFormat(uint png, CancellationToken cancellationToken)
    {
        // PNG is an explicitly registered representation, never a synthesized Win32 bitmap format.
        // It preserves straight alpha and is our preferred interoperable representation.
        if (Native.IsClipboardFormatAvailable(png)) return png;

        // Do not rank IsClipboardFormatAvailable(DIBV5) above an original DIB/CF_BITMAP:
        // Windows advertises synthesized conversions too. EnumClipboardFormats enumerates the
        // producer's original format before its synthesized alternatives. Honor the documented
        // producer order (most descriptive first) within this family, avoiding unintended GDI
        // conversions and preserving the original format's alpha contract. A CF_BITMAP remains
        // opaque; an original DIBV5 retains its declared alpha. Producers that publish independent
        // formats in a poorer-first order cannot be distinguished from synthesis by this API.
        // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-enumclipboardformats
        uint previous = 0;
        for (int count = 0; count < ushort.MaxValue; count++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            uint format = Native.EnumClipboardFormats(previous);
            if (format == 0)
            {
                if (Marshal.GetLastWin32Error() != 0) throw Failure("enumerate", false);
                return 0;
            }
            if (format == CfDibV5 || format == CfDib || format == CfBitmap) return format;
            previous = format;
        }
        throw new InvalidDataException("Clipboard format enumeration exceeds the safety limit.");
    }

    private static void Publish(uint format, OwnedMemory memory)
    {
        if (Native.SetClipboardData(format, memory.Handle) == IntPtr.Zero)
            throw Failure("publish", true);
        memory.Transfer();
    }

    private static byte[] SnapshotMemory(IntPtr handle, bool compressed)
    {
        ulong size = Native.GlobalSize(handle).ToUInt64();
        if (size == 0 || size > int.MaxValue) throw new InvalidDataException("Invalid clipboard allocation size.");
        if (compressed) ImageLimits.ValidatePayload((long)size);
        else if (size > MaxDibBytes) throw new InvalidDataException("Clipboard bitmap exceeds the safety limit.");
        IntPtr address = Native.GlobalLock(handle);
        if (address == IntPtr.Zero) throw Failure("lock-memory", false);
        try
        {
            var bytes = new byte[(int)size];
            Marshal.Copy(address, bytes, 0, bytes.Length);
            return bytes;
        }
        finally { Native.GlobalUnlock(handle); }
    }

    private static byte[] TrimPngAllocation(byte[] bytes)
    {
        // GlobalSize reports allocation capacity, which may exceed encoded PNG length. Only the
        // clipboard allocation boundary is trimmed; ImageCodec still validates signature/chunks/CRC.
        int offset = 8;
        while (offset <= bytes.Length - 12)
        {
            uint length = System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(offset, 4));
            long next = (long)offset + length + 12;
            if (next > bytes.Length || next > int.MaxValue) break;
            if (length == 0 && bytes.AsSpan(offset + 4, 4).SequenceEqual("IEND"u8))
                return next == bytes.Length ? bytes : bytes[..checked((int)next)];
            offset = (int)next;
        }
        return bytes;
    }

    private static byte[] TrimDibAllocation(byte[] bytes)
    {
        if (bytes.Length < 40) return bytes;
        var data = bytes.AsSpan();
        uint header = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(data);
        int width = System.Buffers.Binary.BinaryPrimitives.ReadInt32LittleEndian(data[4..]);
        int height = System.Buffers.Binary.BinaryPrimitives.ReadInt32LittleEndian(data[8..]);
        ushort bits = System.Buffers.Binary.BinaryPrimitives.ReadUInt16LittleEndian(data[14..]);
        uint compression = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(data[16..]);
        // INFO40 + BI_BITFIELDS has externally appended masks and can be ambiguous: do not trim it.
        // V4/V5 carry masks inside their header; BI_RGB has no external masks.
        if (header is not (40 or 108 or 124) || width <= 0 || width > ImageLimits.MaxDimension ||
            height == int.MinValue || Math.Abs((long)height) > ImageLimits.MaxDimension ||
            bits is not (24 or 32) || (compression != 0 && !(header >= 108 && compression == 3)) ||
            System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(data[32..]) != 0)
            return bytes;
        long stride = ((long)width * bits + 31) / 32 * 4;
        long end = header + stride * Math.Abs((long)height);
        return end >= header && end <= bytes.Length ? bytes[..checked((int)end)] : bytes;
    }

    private static ImageData SnapshotBitmap(IntPtr bitmap)
    {
        if (Native.GetObject(bitmap, Marshal.SizeOf<Native.Bitmap>(), out Native.Bitmap info) == 0)
            throw Failure("bitmap-header", false);
        if (info.Height <= 0) throw new InvalidDataException("Invalid clipboard bitmap height.");
        int length = ImageLimits.ValidateDimensions(info.Width, info.Height);
        var pixels = new byte[length];
        var header = new Native.BitmapInfoHeader
        {
            Size = 40, Width = info.Width, Height = -info.Height, Planes = 1, BitCount = 32,
            Compression = 0, SizeImage = checked((uint)length)
        };
        IntPtr dc = Native.CreateCompatibleDC(IntPtr.Zero);
        if (dc == IntPtr.Zero) throw Failure("bitmap-dc", false);
        try
        {
            int rows = Native.GetDIBits(dc, bitmap, 0, checked((uint)info.Height), pixels, ref header, 0);
            if (rows != info.Height) throw Failure("bitmap-pixels", false);
        }
        finally { Native.DeleteDC(dc); }
        // CF_BITMAP/BI_RGB has no portable alpha contract. PNG/DIBV5 are preferred when offered.
        for (int i = 3; i < pixels.Length; i += 4) pixels[i] = 255;
        return new ImageData(info.Width, info.Height, pixels);
    }

    private static void Open(IntPtr owner, CancellationToken cancellationToken)
    {
        for (int attempt = 0; attempt < Attempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Native.OpenClipboard(owner)) return;
            if (attempt + 1 < Attempts && cancellationToken.WaitHandle.WaitOne(RetryMilliseconds))
                cancellationToken.ThrowIfCancellationRequested();
        }
        throw Failure("open", false);
    }

    private static ClipboardOperationException Failure(string stage, bool changed)
        => new("Clipboard operation failed.", stage, changed, new Win32Exception(Marshal.GetLastWin32Error()));

    private static void EnsureWindows()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Windows is required.");
    }

    private sealed class OwnerWindow : IDisposable
    {
        public IntPtr Handle { get; }
        public OwnerWindow()
        {
            Handle = Native.CreateWindowEx(0, "STATIC", "ImageCopySaveClipboard", 0, 0, 0, 0, 0,
                new IntPtr(-3), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (Handle == IntPtr.Zero) throw Failure("owner-window", false);
        }
        public void Dispose() => Native.DestroyWindow(Handle);
    }

    private sealed class OwnedMemory : IDisposable
    {
        public IntPtr Handle { get; private set; }
        private OwnedMemory(IntPtr handle) => Handle = handle;
        public static OwnedMemory Create(byte[] bytes)
        {
            var memory = new OwnedMemory(Native.GlobalAlloc(0x0002, checked((nuint)bytes.Length)));
            if (memory.Handle == IntPtr.Zero) throw new OutOfMemoryException("Could not prepare clipboard memory.");
            try
            {
                IntPtr address = Native.GlobalLock(memory.Handle);
                if (address == IntPtr.Zero) throw Failure("prepare-memory", false);
                try { Marshal.Copy(bytes, 0, address, bytes.Length); }
                finally { Native.GlobalUnlock(memory.Handle); }
                return memory;
            }
            catch { memory.Dispose(); throw; }
        }
        public void Transfer() => Handle = IntPtr.Zero;
        public void Dispose()
        {
            if (Handle != IntPtr.Zero) { Native.GlobalFree(Handle); Handle = IntPtr.Zero; }
        }
    }

    private static class Native
    {
        [StructLayout(LayoutKind.Sequential)] internal struct Bitmap
        {
            internal int Type, Width, Height, WidthBytes;
            internal ushort Planes, BitsPixel;
            internal IntPtr Bits;
        }
        [StructLayout(LayoutKind.Sequential)] internal struct BitmapInfoHeader
        {
            internal uint Size;
            internal int Width, Height;
            internal ushort Planes, BitCount;
            internal uint Compression, SizeImage;
            internal int XPelsPerMeter, YPelsPerMeter;
            internal uint ClrUsed, ClrImportant;
        }
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool OpenClipboard(IntPtr owner);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseClipboard();
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool EmptyClipboard();
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsClipboardFormatAvailable(uint format);
        [DllImport("user32.dll", SetLastError = true)] internal static extern uint EnumClipboardFormats(uint format);
        [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr GetClipboardData(uint format);
        [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr SetClipboardData(uint format, IntPtr data);
        [DllImport("user32.dll")] internal static extern uint GetClipboardSequenceNumber();
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern uint RegisterClipboardFormat(string name);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern IntPtr GlobalAlloc(uint flags, nuint size);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern IntPtr GlobalLock(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GlobalUnlock(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern UIntPtr GlobalSize(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern IntPtr GlobalFree(IntPtr handle);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateWindowEx(uint exStyle, string className, string name, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool DestroyWindow(IntPtr window);
        [DllImport("gdi32.dll", EntryPoint = "GetObjectW", SetLastError = true)] internal static extern int GetObject(IntPtr value, int size, out Bitmap bitmap);
        [DllImport("gdi32.dll", SetLastError = true)] internal static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll", SetLastError = true)] internal static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint first, uint count, [Out] byte[] pixels, ref BitmapInfoHeader info, uint usage);
    }
}

public sealed class ClipboardChangedException : IOException
{
    public ClipboardChangedException() : base("A newer clipboard copy was detected; the previous content was preserved.") { }
}

public sealed class ClipboardOperationException : IOException
{
    public string Stage { get; }
    public bool ClipboardMayHaveChanged { get; }
    public ClipboardOperationException(string message, string stage, bool clipboardMayHaveChanged, Exception? inner = null)
        : base(message, inner) { Stage = stage; ClipboardMayHaveChanged = clipboardMayHaveChanged; }
}
