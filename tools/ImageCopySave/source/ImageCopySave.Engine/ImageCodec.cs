using System.Buffers.Binary;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ImageCopySave.Engine;

/// <summary>Explicit Windows PNG/JPEG/BMP decoders, bounded before decoding. Output is 8-bit straight BGRA.</summary>
public static class ImageCodec
{
    private sealed record Header(int Width, int Height, int Orientation = 1);
    private static readonly byte[] PngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
    private static readonly uint[] CrcTable = CreateCrcTable();

    public static ImageData Decode(byte[] bytes, string extension)
    {
        ArgumentNullException.ThrowIfNull(bytes);
        ArgumentNullException.ThrowIfNull(extension);
        ImageLimits.ValidatePayload(bytes.LongLength);
        string kind = extension.ToLowerInvariant();
        Header header = kind switch
        {
            ".png" => InspectPng(bytes),
            ".jpg" or ".jpeg" => InspectJpeg(bytes),
            ".bmp" => BmpHeader(bytes),
            _ => throw new NotSupportedException("Only PNG, JPG/JPEG and BMP file inputs are supported.")
        };
        using var input = new MemoryStream(bytes, writable: false);
        const BitmapCreateOptions options = BitmapCreateOptions.PreservePixelFormat | BitmapCreateOptions.IgnoreColorProfile;
        // Explicit codec classes do not discover formats through installed third-party codecs.
        BitmapDecoder decoder = kind switch
        {
            ".png" => new PngBitmapDecoder(input, options, BitmapCacheOption.OnLoad),
            ".jpg" or ".jpeg" => new JpegBitmapDecoder(input, options, BitmapCacheOption.OnLoad),
            ".bmp" => new BmpBitmapDecoder(input, options, BitmapCacheOption.OnLoad),
            _ => throw new InvalidOperationException()
        };
        if (decoder.Frames.Count != 1) throw new NotSupportedException("Only one still image is supported.");
        BitmapFrame frame = decoder.Frames[0];
        if (frame.PixelWidth != header.Width || frame.PixelHeight != header.Height)
            throw new InvalidDataException("Decoded dimensions disagree with the validated header.");
        // DIB's declared masks are authoritative. Reading straight bytes also preserves RGB under alpha zero.
        if (kind == ".bmp") return DibCodec.DecodeBitmapFile(bytes);
        PixelFormat format = frame.Format;
        if (format == PixelFormats.Pbgra32 || format == PixelFormats.Prgba64 || format == PixelFormats.Prgba128Float ||
            format == PixelFormats.Cmyk32 || format.BitsPerPixel > 32)
            throw new NotSupportedException("Premultiplied, high-bit-depth and CMYK decoding are unsupported.");
        BitmapSource source = format == PixelFormats.Bgra32 ? frame :
            new FormatConvertedBitmap(frame, PixelFormats.Bgra32, null, 0);
        byte[] pixels = new byte[ImageLimits.ValidateDimensions(header.Width, header.Height)];
        source.CopyPixels(pixels, checked(header.Width * 4), 0);
        return Orient(new ImageData(header.Width, header.Height, pixels), header.Orientation);
    }

    public static byte[] EncodePng(ImageData image)
    {
        ArgumentNullException.ThrowIfNull(image);
        image.Validate();
        BitmapSource source = BitmapSource.Create(image.Width, image.Height, 96, 96,
            PixelFormats.Bgra32, null, image.Bgra, checked(image.Width * 4));
        source.Freeze();
        var encoder = new PngBitmapEncoder();
        // A new pixel-only frame intentionally omits source EXIF/GPS/author/profile metadata.
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var output = new MemoryStream();
        encoder.Save(output);
        ImageLimits.ValidatePayload(output.Length);
        return output.ToArray();
    }

    private static Header BmpHeader(byte[] bytes)
    {
        var dimensions = DibCodec.InspectBitmapFile(bytes);
        return new Header(dimensions.Width, dimensions.Height);
    }

    private static Header InspectPng(byte[] bytes)
    {
        if (bytes.Length < 45 || !bytes.AsSpan(0, 8).SequenceEqual(PngSignature))
            throw new InvalidDataException("Invalid PNG signature or truncated image.");
        Header? header = null;
        bool idat = false, end = false, exif = false;
        int offset = 8, orientation = 1;
        while (offset < bytes.Length)
        {
            if (bytes.Length - offset < 12) throw new InvalidDataException("Truncated PNG chunk.");
            uint length = Be32(bytes, offset);
            if (length > int.MaxValue || checked((long)offset + 12 + length) > bytes.Length)
                throw new InvalidDataException("PNG chunk length exceeds input.");
            int size = checked((int)length);
            ReadOnlySpan<byte> type = bytes.AsSpan(offset + 4, 4);
            ReadOnlySpan<byte> data = bytes.AsSpan(offset + 8, size);
            foreach (byte b in type)
                if (b is not (>= 65 and <= 90) and not (>= 97 and <= 122)) throw new InvalidDataException("Invalid PNG chunk type.");
            if (Crc(bytes.AsSpan(offset + 4, size + 4)) != Be32(bytes, offset + 8 + size))
                throw new InvalidDataException("PNG chunk CRC mismatch.");
            if (header == null && !type.SequenceEqual("IHDR"u8)) throw new InvalidDataException("PNG must begin with IHDR.");
            if (type.SequenceEqual("IHDR"u8))
            {
                if (header != null || size != 13) throw new InvalidDataException("Invalid PNG IHDR.");
                uint width = BinaryPrimitives.ReadUInt32BigEndian(data), height = BinaryPrimitives.ReadUInt32BigEndian(data[4..]);
                if (width > int.MaxValue || height > int.MaxValue) throw new InvalidDataException("Excessive PNG dimensions.");
                ImageLimits.ValidateDimensions((int)width, (int)height);
                int depth = data[8], color = data[9];
                bool supported = color switch { 0 or 3 => depth is 1 or 2 or 4 or 8, 2 or 4 or 6 => depth == 8, _ => false };
                if (!supported) throw new NotSupportedException("Only up-to-8-bit screen PNG formats are supported.");
                if (data[10] != 0 || data[11] != 0 || data[12] > 1) throw new NotSupportedException("Unsupported PNG coding method.");
                header = new Header((int)width, (int)height);
            }
            else if (type.SequenceEqual("acTL"u8) || type.SequenceEqual("fcTL"u8) || type.SequenceEqual("fdAT"u8))
                throw new NotSupportedException("Animated PNG is unsupported.");
            else if (type.SequenceEqual("iCCP"u8) || type.SequenceEqual("cICP"u8) || type.SequenceEqual("mDCV"u8) || type.SequenceEqual("cLLI"u8))
                throw new NotSupportedException("ICC/HDR/custom color profiles are unsupported.");
            else if (type.SequenceEqual("gAMA"u8))
            {
                if (size != 4 || BinaryPrimitives.ReadUInt32BigEndian(data) != 45455)
                    throw new NotSupportedException("Only standard sRGB gamma is supported.");
            }
            else if (type.SequenceEqual("cHRM"u8))
            {
                uint[] srgb = [31270, 32900, 64000, 33000, 30000, 60000, 15000, 6000];
                if (size != 32) throw new InvalidDataException("Invalid PNG chromaticities.");
                for (int n = 0; n < srgb.Length; n++)
                    if (BinaryPrimitives.ReadUInt32BigEndian(data[(n * 4)..]) != srgb[n])
                        throw new NotSupportedException("Only standard sRGB chromaticities are supported.");
            }
            else if (type.SequenceEqual("sRGB"u8))
            {
                if (size != 1 || data[0] > 3) throw new InvalidDataException("Invalid sRGB rendering intent.");
            }
            else if (type.SequenceEqual("eXIf"u8))
            {
                if (exif) throw new InvalidDataException("Multiple PNG EXIF chunks.");
                orientation = ReadOrientation(data);
                exif = true;
            }
            else if (type.SequenceEqual("IDAT"u8)) idat = true;
            else if (type.SequenceEqual("IEND"u8))
            {
                if (size != 0 || !idat || offset + 12 != bytes.Length) throw new InvalidDataException("Invalid PNG end or trailing image.");
                end = true;
            }
            else if (type[0] < 97 && !type.SequenceEqual("PLTE"u8))
                throw new NotSupportedException("Unknown critical PNG chunk.");
            offset = checked(offset + size + 12);
        }
        if (header == null || !end) throw new InvalidDataException("PNG has no complete image.");
        return header with { Orientation = orientation };
    }

    private static Header InspectJpeg(byte[] bytes)
    {
        if (bytes.Length < 4 || bytes[0] != 255 || bytes[1] != 216) throw new InvalidDataException("Invalid JPEG signature.");
        Header? header = null;
        bool exif = false, scan = false;
        int orientation = 1, position = 2;
        while (position < bytes.Length)
        {
            if (bytes[position++] != 255) throw new InvalidDataException("Invalid JPEG marker.");
            while (position < bytes.Length && bytes[position] == 255) position++;
            if (position >= bytes.Length) throw new InvalidDataException("Truncated JPEG marker.");
            byte marker = bytes[position++];
            if (marker == 217)
            {
                if (header == null || !scan || position != bytes.Length) throw new InvalidDataException("Incomplete JPEG or trailing image.");
                return header with { Orientation = orientation };
            }
            if (marker is 0 or 216 or (>= 208 and <= 215) or 1) throw new InvalidDataException("Unexpected JPEG marker.");
            if (bytes.Length - position < 2) throw new InvalidDataException("Truncated JPEG segment.");
            int length = BinaryPrimitives.ReadUInt16BigEndian(bytes.AsSpan(position, 2));
            if (length < 2 || (long)position + length > bytes.Length) throw new InvalidDataException("Invalid JPEG segment length.");
            ReadOnlySpan<byte> data = bytes.AsSpan(position + 2, length - 2);
            if (marker is >= 192 and <= 207 && marker is not (196 or 200 or 204))
            {
                if (marker is not (192 or 193 or 194) || header != null || data.Length < 6)
                    throw new NotSupportedException("Unsupported JPEG coding or multiple images.");
                int components = data[5];
                if (data[0] != 8 || components is not (1 or 3)) throw new NotSupportedException("High-bit-depth or CMYK JPEG is unsupported.");
                if (data.Length != 6 + components * 3) throw new InvalidDataException("Invalid JPEG component table.");
                int height = BinaryPrimitives.ReadUInt16BigEndian(data[1..]), width = BinaryPrimitives.ReadUInt16BigEndian(data[3..]);
                ImageLimits.ValidateDimensions(width, height);
                header = new Header(width, height);
            }
            else if (marker == 225 && data.StartsWith("Exif\0\0"u8))
            {
                if (exif) throw new InvalidDataException("Multiple EXIF segments are unsupported.");
                orientation = ReadOrientation(data[6..]);
                exif = true;
            }
            else if (marker == 226 && (data.StartsWith("ICC_PROFILE\0"u8) || data.StartsWith("MPF\0"u8)))
                throw new NotSupportedException("ICC profiles and multi-picture JPEG are unsupported.");
            position = checked(position + length);
            if (marker == 218)
            {
                if (header == null) throw new InvalidDataException("JPEG scan has no image header.");
                scan = true;
                bool next = false;
                while (position < bytes.Length)
                {
                    if (bytes[position] != 255) { position++; continue; }
                    int markerStart = position++;
                    while (position < bytes.Length && bytes[position] == 255) position++;
                    if (position >= bytes.Length) break;
                    byte nextMarker = bytes[position];
                    if (nextMarker == 0 || nextMarker is >= 208 and <= 215) { position++; continue; }
                    position = markerStart;
                    next = true;
                    break;
                }
                if (!next) throw new InvalidDataException("Truncated JPEG entropy data.");
            }
        }
        throw new InvalidDataException("JPEG end marker missing.");
    }

    private static int ReadOrientation(ReadOnlySpan<byte> tiff)
    {
        if (tiff.Length < 8) throw new InvalidDataException("Truncated EXIF TIFF header.");
        bool little = tiff[0] == 'I' && tiff[1] == 'I';
        if (!little && !(tiff[0] == 'M' && tiff[1] == 'M')) throw new InvalidDataException("Invalid EXIF byte order.");
        if (T16(tiff, 2, little) != 42) throw new InvalidDataException("Invalid EXIF TIFF signature.");
        uint offset = T32(tiff, 4, little);
        if (offset == 0) return 1;
        if (offset < 8 || (long)offset + 2 > tiff.Length) throw new InvalidDataException("Invalid EXIF IFD offset.");
        int start = checked((int)offset);
        int count = T16(tiff, start, little);
        if (checked((long)start + 2 + count * 12L + 4) > tiff.Length) throw new InvalidDataException("Truncated EXIF IFD.");
        int orientation = 1;
        bool found = false;
        for (int i = 0; i < count; i++)
        {
            int entry = checked(start + 2 + i * 12);
            if (T16(tiff, entry, little) != 0x0112) continue;
            if (found || T16(tiff, entry + 2, little) != 3 || T32(tiff, entry + 4, little) != 1)
                throw new InvalidDataException("Invalid EXIF orientation entry.");
            orientation = T16(tiff, entry + 8, little);
            if (orientation is < 1 or > 8) throw new InvalidDataException("Invalid EXIF orientation value.");
            found = true;
        }
        return orientation;
    }

    private static ImageData Orient(ImageData source, int orientation)
    {
        if (orientation == 1) return source;
        int width = orientation >= 5 ? source.Height : source.Width;
        int height = orientation >= 5 ? source.Width : source.Height;
        byte[] target = new byte[ImageLimits.ValidateDimensions(width, height)];
        for (int y = 0; y < source.Height; y++)
        for (int x = 0; x < source.Width; x++)
        {
            (int dx, int dy) = orientation switch
            {
                2 => (source.Width - 1 - x, y),
                3 => (source.Width - 1 - x, source.Height - 1 - y),
                4 => (x, source.Height - 1 - y),
                5 => (y, x),
                6 => (source.Height - 1 - y, x),
                7 => (source.Height - 1 - y, source.Width - 1 - x),
                8 => (y, source.Width - 1 - x),
                _ => throw new InvalidDataException("Unsupported orientation.")
            };
            source.Bgra.AsSpan(checked((y * source.Width + x) * 4), 4)
                .CopyTo(target.AsSpan(checked((dy * width + dx) * 4), 4));
        }
        return new ImageData(width, height, target);
    }

    private static ushort T16(ReadOnlySpan<byte> data, int offset, bool little) => little ?
        BinaryPrimitives.ReadUInt16LittleEndian(data.Slice(offset, 2)) : BinaryPrimitives.ReadUInt16BigEndian(data.Slice(offset, 2));
    private static uint T32(ReadOnlySpan<byte> data, int offset, bool little) => little ?
        BinaryPrimitives.ReadUInt32LittleEndian(data.Slice(offset, 4)) : BinaryPrimitives.ReadUInt32BigEndian(data.Slice(offset, 4));
    private static uint Be32(byte[] bytes, int offset) => BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(offset, 4));
    private static uint Crc(ReadOnlySpan<byte> bytes)
    {
        uint crc = uint.MaxValue;
        foreach (byte value in bytes) crc = CrcTable[(crc ^ value) & 255] ^ (crc >> 8);
        return ~crc;
    }
    private static uint[] CreateCrcTable()
    {
        uint[] table = new uint[256];
        for (uint i = 0; i < table.Length; i++)
        {
            uint value = i;
            for (int bit = 0; bit < 8; bit++) value = (value & 1) != 0 ? 0xedb88320 ^ (value >> 1) : value >> 1;
            table[i] = value;
        }
        return table;
    }
}
