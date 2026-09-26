using System.Buffers.Binary;

namespace ImageCopySave.Engine;

/// <summary>Strict, bounded DIB reader. Supports INFO/V4/V5 24-bit RGB and 32-bit RGB/standard BGRA masks.
/// Palette/RLE/JPEG/PNG-in-DIB, calibrated/embedded/linked profiles and arbitrary masks are rejected.</summary>
public static class DibCodec
{
    private const uint Srgb = 0x73524742;
    private sealed record Layout(int Width, int Height, bool TopDown, int Bits, int Stride, int Offset, bool Alpha);

    public static ImageData Decode(byte[] dib)
    {
        ArgumentNullException.ThrowIfNull(dib);
        return Decode(dib, Parse(dib, null));
    }

    internal static ImageData DecodeBitmapFile(byte[] file) => Decode(file.AsSpan(14), ParseBitmapFile(file));

    internal static (int Width, int Height) InspectBitmapFile(byte[] file)
    {
        Layout layout = ParseBitmapFile(file);
        return (layout.Width, layout.Height);
    }

    private static Layout ParseBitmapFile(byte[] file)
    {
        ArgumentNullException.ThrowIfNull(file);
        ImageLimits.ValidatePayload(file.LongLength);
        if (file.Length < 54 || file[0] != (byte)'B' || file[1] != (byte)'M')
            throw new InvalidDataException("Invalid BMP signature or file header.");
        uint declaredSize = U32(file, 2), offset = U32(file, 10);
        if (declaredSize != file.Length || U32(file, 6) != 0 || offset < 14 || offset > file.Length)
            throw new InvalidDataException("Invalid BMP size, reserved fields or pixel offset.");
        return Parse(file.AsSpan(14), checked((int)offset - 14));
    }

    private static ImageData Decode(ReadOnlySpan<byte> dib, Layout layout)
    {
        byte[] bgra = new byte[ImageLimits.ValidateDimensions(layout.Width, layout.Height)];
        for (int y = 0; y < layout.Height; y++)
        {
            int sourceY = layout.TopDown ? y : layout.Height - 1 - y;
            int source = checked(layout.Offset + sourceY * layout.Stride);
            int target = checked(y * layout.Width * 4);
            for (int x = 0; x < layout.Width; x++)
            {
                bgra[target++] = dib[source++];
                bgra[target++] = dib[source++];
                bgra[target++] = dib[source++];
                bgra[target++] = layout.Bits == 32 ? (layout.Alpha ? dib[source++] : SkipOpaque(ref source)) : (byte)255;
            }
        }
        return new ImageData(layout.Width, layout.Height, bgra);
    }

    private static byte SkipOpaque(ref int source) { source++; return 255; }

    private static Layout Parse(ReadOnlySpan<byte> dib, int? suppliedOffset)
    {
        if (dib.Length > ImageLimits.MaxBufferBytes + 124L) throw new InvalidDataException("Excessive DIB payload.");
        if (dib.Length < 40) throw new InvalidDataException("Truncated DIB header.");
        uint header = U32(dib, 0);
        if (header is not (40 or 108 or 124) || header > dib.Length)
            throw new NotSupportedException("Only BITMAPINFOHEADER/V4/V5 DIB headers are supported.");
        int width = I32(dib, 4), signedHeight = I32(dib, 8);
        if (signedHeight == int.MinValue) throw new InvalidDataException("Invalid DIB height.");
        int height = Math.Abs(signedHeight);
        ImageLimits.ValidateDimensions(width, height);
        if (U16(dib, 12) != 1) throw new InvalidDataException("DIB planes must be one.");
        int bits = U16(dib, 14);
        uint compression = U32(dib, 16);
        if (bits is not (24 or 32) || (compression != 0 && !(bits == 32 && compression == 3)))
            throw new NotSupportedException("Only 24/32-bit RGB or standard 32-bit bitfields are supported.");
        if (U32(dib, 32) != 0 || U32(dib, 36) != 0)
            throw new NotSupportedException("DIB color tables are not supported.");
        int offset = checked((int)header);
        bool alpha = false;
        if (compression == 3)
        {
            if (header == 40) offset = checked(offset + 12);
            if (dib.Length < offset) throw new InvalidDataException("Truncated DIB masks.");
            if (U32(dib, 40) != 0x00ff0000 || U32(dib, 44) != 0x0000ff00 || U32(dib, 48) != 0x000000ff)
                throw new NotSupportedException("Only standard byte-aligned RGB masks are supported.");
            if (header >= 108)
            {
                uint mask = U32(dib, 52);
                if (mask != 0 && mask != 0xff000000) throw new NotSupportedException("Unsupported DIB alpha mask.");
                alpha = mask == 0xff000000;
            }
        }
        if (header >= 108)
        {
            if (U32(dib, 56) != Srgb)
                throw new NotSupportedException("Only explicit sRGB V4/V5 DIBs are supported; custom profiles are rejected.");
            if (header == 124 && (U32(dib, 112) != 0 || U32(dib, 116) != 0 || U32(dib, 120) != 0))
                throw new NotSupportedException("DIB profile data and reserved extensions are unsupported.");
        }
        if (suppliedOffset.HasValue)
        {
            if (suppliedOffset.Value < offset) throw new InvalidDataException("BMP pixels overlap its header.");
            offset = suppliedOffset.Value;
        }
        long stride = ((checked((long)width * bits) + 31) / 32) * 4;
        long pixelBytes = checked(stride * height);
        if (pixelBytes > ImageLimits.MaxBufferBytes || checked((long)offset + pixelBytes) != dib.Length)
            throw new InvalidDataException("Truncated, excessive or ambiguous DIB pixel buffer.");
        uint imageSize = U32(dib, 20);
        if (imageSize != 0 && imageSize != pixelBytes)
            throw new InvalidDataException("DIB image length does not match its stride and dimensions.");
        return new Layout(width, height, signedHeight < 0, bits, checked((int)stride), offset, alpha);
    }

    public static byte[] EncodeV5(ImageData image)
    {
        ArgumentNullException.ThrowIfNull(image);
        image.Validate();
        int length = checked(124 + image.Bgra.Length);
        if (length > ImageLimits.MaxBufferBytes + 124L) throw new InvalidDataException("Excessive DIB payload.");
        byte[] result = new byte[length];
        W32(result, 0, 124);
        W32(result, 4, checked((uint)image.Width));
        BinaryPrimitives.WriteInt32LittleEndian(result.AsSpan(8, 4), -image.Height);
        BinaryPrimitives.WriteUInt16LittleEndian(result.AsSpan(12, 2), 1);
        BinaryPrimitives.WriteUInt16LittleEndian(result.AsSpan(14, 2), 32);
        W32(result, 16, 3); // BI_BITFIELDS; straight alpha, never premultiplied.
        W32(result, 20, checked((uint)image.Bgra.Length));
        W32(result, 40, 0x00ff0000);
        W32(result, 44, 0x0000ff00);
        W32(result, 48, 0x000000ff);
        W32(result, 52, 0xff000000);
        W32(result, 56, Srgb);
        W32(result, 108, 4); // LCS_GM_IMAGES
        image.Bgra.CopyTo(result, 124);
        return result;
    }

    private static ushort U16(ReadOnlySpan<byte> bytes, int offset) => BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(offset, 2));
    private static uint U32(ReadOnlySpan<byte> bytes, int offset) => BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(offset, 4));
    private static int I32(ReadOnlySpan<byte> bytes, int offset) => BinaryPrimitives.ReadInt32LittleEndian(bytes.Slice(offset, 4));
    private static void W32(byte[] bytes, int offset, uint value) => BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(offset, 4), value);
}
