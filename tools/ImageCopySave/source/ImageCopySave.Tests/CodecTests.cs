using System.Buffers.Binary;
using System.Text;
using System.IO.Compression;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ImageCopySave.Engine;

namespace ImageCopySave.Tests;

public static class CodecTests
{
    public static void Register(Action<string, Action> test)
    {
        test("codec/PNG exact RGBA including transparent RGB", () => Equal(Fixture(), ImageCodec.Decode(ImageCodec.EncodePng(Fixture()), ".png")));
        test("codec/indexed PNG palette transparency exact", () =>
        {
            ImageData image = Fixture();
            byte[] palette = new byte[18], alpha = new byte[6];
            for (int i = 0; i < 6; i++)
            {
                palette[i * 3] = image.Bgra[i * 4 + 2]; palette[i * 3 + 1] = image.Bgra[i * 4 + 1]; palette[i * 3 + 2] = image.Bgra[i * 4]; alpha[i] = image.Bgra[i * 4 + 3];
            }
            Equal(image, ImageCodec.Decode(RawPng(3, [0,0,1,2,0,3,4,5], palette, alpha), ".png"));
        });
        test("codec/grayscale PNG converted without tone changes", () =>
        {
            byte[] gray = [0,17,127,128,254,255], expected = new byte[24];
            for (int i = 0; i < 6; i++) { expected[i * 4] = expected[i * 4 + 1] = expected[i * 4 + 2] = gray[i]; expected[i * 4 + 3] = 255; }
            Equal(new ImageData(3, 2, expected), ImageCodec.Decode(RawPng(0, [0,0,17,127,0,128,254,255]), ".png"));
        });
        test("codec/DIB standard INFO bitfields and V4 alpha", () =>
        {
            ImageData image = Fixture(); byte[] v5 = DibCodec.EncodeV5(image);
            byte[] v4 = [..v5.AsSpan(0, 108), ..image.Bgra]; Put32(v4, 0, 108);
            Equal(image, DibCodec.Decode(v4));
            byte[] info = [..v5.AsSpan(0, 52), ..image.Bgra]; Put32(info, 0, 40);
            Equal(OpaqueFixture(), DibCodec.Decode(info));
            // An undocumented fourth external mask cannot be confused with the first pixel.
            byte[] ambiguous = [..v5.AsSpan(0, 56), ..image.Bgra]; Put32(ambiguous, 0, 40);
            Reject(() => DibCodec.Decode(ambiguous));
        });
        test("codec/repeated PNG DIBV5 alpha roundtrip", () =>
        {
            ImageData image = Fixture();
            for (int i = 0; i < 12; i++) image = ImageCodec.Decode(ImageCodec.EncodePng(DibCodec.Decode(DibCodec.EncodeV5(image))), ".png");
            Equal(Fixture(), image);
        });
        test("codec/DIBV5 straight alpha exact", () => Equal(Fixture(), DibCodec.Decode(DibCodec.EncodeV5(Fixture()))));
        test("codec/DIBV5 bottom-up row order", () =>
        {
            ImageData image = Fixture();
            byte[] dib = DibCodec.EncodeV5(image);
            Put32(dib, 8, (uint)image.Height);
            for (int y = 0; y < image.Height; y++)
                image.Bgra.AsSpan((image.Height - 1 - y) * image.Width * 4, image.Width * 4).CopyTo(dib.AsSpan(124 + y * image.Width * 4));
            Equal(image, DibCodec.Decode(dib));
        });
        test("codec/DIB24 padded rows bottom-up", () => Equal(OpaqueFixture(), DibCodec.Decode(Dib24(false))));
        test("codec/DIB24 padded rows top-down", () => Equal(OpaqueFixture(), DibCodec.Decode(Dib24(true))));
        test("codec/DIB32 BI_RGB reserved byte is opaque", () =>
        {
            byte[] dib = new byte[40 + Fixture().Bgra.Length];
            Put32(dib, 0, 40); Put32(dib, 4, 3); Put32(dib, 8, unchecked((uint)-2)); Put16(dib, 12, 1); Put16(dib, 14, 32);
            Fixture().Bgra.CopyTo(dib, 40);
            Equal(OpaqueFixture(), DibCodec.Decode(dib));
        });
        test("codec/BMP24 and V5 file inputs", () =>
        {
            Equal(OpaqueFixture(), ImageCodec.Decode(BmpFile(Dib24(false)), ".BMP"));
            Equal(Fixture(), ImageCodec.Decode(BmpFile(DibCodec.EncodeV5(Fixture())), ".bmp"));
        });
        test("codec/signature extension mismatch", () =>
        {
            byte[] png = ImageCodec.EncodePng(Fixture());
            Reject(() => ImageCodec.Decode(png, ".jpg")); Reject(() => ImageCodec.Decode(png, ".bmp"));
            Reject(() => ImageCodec.Decode(png, ".gif"));
        });
        test("codec/PNG CRC truncation and trailing data", () =>
        {
            byte[] png = ImageCodec.EncodePng(Fixture());
            byte[] corrupt = (byte[])png.Clone(); corrupt[29] ^= 1;
            Reject(() => ImageCodec.Decode(corrupt, ".png"));
            Reject(() => ImageCodec.Decode(png[..^1], ".png"));
            Reject(() => ImageCodec.Decode([..png, 0], ".png"));
        });
        test("codec/PNG APNG and high-bit-depth rejected", () =>
        {
            byte[] png = ImageCodec.EncodePng(Fixture());
            Reject(() => ImageCodec.Decode(AddChunk(png, "acTL", [0,0,0,1,0,0,0,0]), ".png"));
            byte[] high = (byte[])png.Clone(); high[24] = 16; FixIhdr(high);
            Reject(() => ImageCodec.Decode(high, ".png"));
        });
        test("codec/PNG profile and HDR rejected", () =>
        {
            byte[] png = ImageCodec.EncodePng(Fixture());
            foreach (string type in new[] { "iCCP", "cICP", "mDCV", "cLLI" })
                Reject(() => ImageCodec.Decode(AddChunk(png, type, [1]), ".png"));
            Reject(() => ImageCodec.Decode(AddChunk(png, "gAMA", [0,0,0,1]), ".png"));
        });
        test("codec/PNG oversized dimensions rejected before decode", () =>
        {
            byte[] png = ImageCodec.EncodePng(Fixture());
            foreach ((uint w, uint h) in new[] { (16385u, 1u), (10000u, 5001u), (uint.MaxValue, uint.MaxValue), (0u, 2u) })
            {
                byte[] bad = (byte[])png.Clone();
                BinaryPrimitives.WriteUInt32BigEndian(bad.AsSpan(16, 4), w); BinaryPrimitives.WriteUInt32BigEndian(bad.AsSpan(20, 4), h); FixIhdr(bad);
                Reject(() => ImageCodec.Decode(bad, ".png"));
            }
        });
        test("codec/PNG EXIF orientations 1-8 both byte orders", () =>
        {
            byte[] png = ImageCodec.EncodePng(Fixture());
            for (int orientation = 1; orientation <= 8; orientation++)
            foreach (bool little in new[] { true, false })
                Equal(ExpectedOrientation(Fixture(), orientation), ImageCodec.Decode(AddChunk(png, "eXIf", Exif(orientation, little)), ".png"));
        });
        test("codec/JPEG EXIF orientations 1-8", () =>
        {
            byte[] jpeg = Jpeg();
            ImageData reference = ImageCodec.Decode(jpeg, ".jpeg");
            for (int orientation = 1; orientation <= 8; orientation++)
                Equal(ExpectedOrientation(reference, orientation), ImageCodec.Decode(AddJpegSegment(jpeg, 225, [.."Exif\0\0"u8.ToArray(), ..Exif(orientation, orientation % 2 == 0)]), ".jpg"));
        });
        test("codec/JPEG ICC MPO high-bit CMYK and malformed rejected", () =>
        {
            byte[] jpeg = Jpeg();
            Reject(() => ImageCodec.Decode(AddJpegSegment(jpeg, 226, "ICC_PROFILE\0"u8.ToArray()), ".jpg"));
            Reject(() => ImageCodec.Decode(AddJpegSegment(jpeg, 226, "MPF\0"u8.ToArray()), ".jpg"));
            Reject(() => ImageCodec.Decode(jpeg[..^2], ".jpg"));
            Reject(() => ImageCodec.Decode([..jpeg, ..jpeg], ".jpg"));
            int sof = FindSof(jpeg);
            byte[] high = (byte[])jpeg.Clone(); high[sof + 4] = 12;
            byte[] cmyk = (byte[])jpeg.Clone(); cmyk[sof + 9] = 4;
            Reject(() => ImageCodec.Decode(high, ".jpg")); Reject(() => ImageCodec.Decode(cmyk, ".jpg"));
        });
        test("codec/EXIF malicious offsets and invalid orientation", () =>
        {
            byte[] png = ImageCodec.EncodePng(Fixture());
            byte[] exif = Exif(1, true); Put32(exif, 4, uint.MaxValue);
            Reject(() => ImageCodec.Decode(AddChunk(png, "eXIf", exif), ".png"));
            Reject(() => ImageCodec.Decode(AddChunk(png, "eXIf", Exif(9, true)), ".png"));
            Reject(() => ImageCodec.Decode(AddChunk(png, "eXIf", [1,2,3]), ".png"));
        });
        test("codec/output metadata stripped after orientation", () =>
        {
            byte[] tagged = AddChunk(AddChunk(ImageCodec.EncodePng(Fixture()), "tEXt", Encoding.ASCII.GetBytes("Author\0private-fixture")), "eXIf", Exif(6, true));
            byte[] output = ImageCodec.EncodePng(ImageCodec.Decode(tagged, ".png"));
            Check.That(!Chunks(output).Any(x => x is "eXIf" or "tEXt" or "iTXt" or "zTXt" or "iCCP"), "Source metadata copied to PNG.");
            Equal(ExpectedOrientation(Fixture(), 6), ImageCodec.Decode(output, ".png"));
        });
        test("codec/DIB malformed stride dimensions masks profile lengths", () =>
        {
            byte[] valid = DibCodec.EncodeV5(Fixture());
            foreach ((int offset, uint value) in new[] { (0, 125u), (4, uint.MaxValue), (8, 0x80000000u), (8, 0u), (16, 1u), (20, uint.MaxValue), (32, 1u), (40, 0x0000ff00u), (52, 0x0f000000u), (56, 0u), (112, 124u), (116, 4u), (120, 1u) })
            {
                byte[] bad = (byte[])valid.Clone(); Put32(bad, offset, value); Reject(() => DibCodec.Decode(bad));
            }
            Reject(() => DibCodec.Decode(valid[..^1]));
            Reject(() => DibCodec.Decode(valid[..39]));
            byte[] huge = (byte[])valid.Clone(); Put32(huge, 4, 16384); Put32(huge, 8, 16384); Reject(() => DibCodec.Decode(huge));
        });
        test("codec/BMP unsafe offsets and declared lengths", () =>
        {
            byte[] bmp = BmpFile(Dib24(false));
            foreach ((int offset, uint value) in new[] { (2, uint.MaxValue), (6, 1u), (10, 15u), (10, uint.MaxValue) })
            {
                byte[] bad = (byte[])bmp.Clone(); Put32(bad, offset, value); Reject(() => ImageCodec.Decode(bad, ".bmp"));
            }
        });
    }

    private static ImageData Fixture() => new(3, 2, [19,31,47,0, 101,203,55,1, 51,81,211,127, 200,3,71,128, 17,213,99,254, 34,5,188,255]);
    private static ImageData OpaqueFixture()
    {
        ImageData image = Fixture();
        for (int i = 3; i < image.Bgra.Length; i += 4) image.Bgra[i] = 255;
        return image;
    }
    private static void Equal(ImageData expected, ImageData actual)
    {
        Check.That(expected.Width == actual.Width && expected.Height == actual.Height, "Image dimensions differ.");
        Check.That(expected.Bgra.SequenceEqual(actual.Bgra), "BGRA pixels differ, including alpha/transparent RGB.");
    }
    private static void Reject(Action action)
    {
        try { action(); }
        catch (Exception ex) when (ex is InvalidDataException or NotSupportedException or ArgumentException or OverflowException) { return; }
        throw new Exception("Malformed or unsupported image was not safely rejected.");
    }
    private static ImageData ExpectedOrientation(ImageData image, int orientation)
    {
        // Independently specified visual row order for the six labelled source pixels: A B C / D E F.
        int[][] order = [[0,1,2,3,4,5], [2,1,0,5,4,3], [5,4,3,2,1,0], [3,4,5,0,1,2], [0,3,1,4,2,5], [3,0,4,1,5,2], [5,2,4,1,3,0], [2,5,1,4,0,3]];
        byte[] result = new byte[24];
        for (int i = 0; i < 6; i++) image.Bgra.AsSpan(order[orientation - 1][i] * 4, 4).CopyTo(result.AsSpan(i * 4));
        return new ImageData(orientation <= 4 ? 3 : 2, orientation <= 4 ? 2 : 3, result);
    }
    private static byte[] Dib24(bool topDown)
    {
        ImageData image = OpaqueFixture();
        byte[] dib = new byte[40 + 24];
        Put32(dib, 0, 40); Put32(dib, 4, 3); Put32(dib, 8, unchecked((uint)(topDown ? -2 : 2))); Put16(dib, 12, 1); Put16(dib, 14, 24);
        Put32(dib, 20, 24);
        for (int y = 0; y < 2; y++)
        for (int x = 0; x < 3; x++)
            image.Bgra.AsSpan((y * 3 + x) * 4, 3).CopyTo(dib.AsSpan(40 + (topDown ? y : 1 - y) * 12 + x * 3, 3));
        return dib;
    }
    private static byte[] BmpFile(byte[] dib)
    {
        byte[] bmp = new byte[14 + dib.Length]; bmp[0] = (byte)'B'; bmp[1] = (byte)'M';
        Put32(bmp, 2, (uint)bmp.Length); Put32(bmp, 10, 14 + BinaryPrimitives.ReadUInt32LittleEndian(dib)); dib.CopyTo(bmp, 14);
        return bmp;
    }
    private static byte[] Exif(int orientation, bool little)
    {
        byte[] exif = new byte[26];
        exif[0] = exif[1] = (byte)(little ? 'I' : 'M');
        void W16(int offset, ushort value) { if (little) BinaryPrimitives.WriteUInt16LittleEndian(exif.AsSpan(offset, 2), value); else BinaryPrimitives.WriteUInt16BigEndian(exif.AsSpan(offset, 2), value); }
        void W32(int offset, uint value) { if (little) BinaryPrimitives.WriteUInt32LittleEndian(exif.AsSpan(offset, 4), value); else BinaryPrimitives.WriteUInt32BigEndian(exif.AsSpan(offset, 4), value); }
        W16(2, 42); W32(4, 8); W16(8, 1); W16(10, 0x0112); W16(12, 3); W32(14, 1); W16(18, (ushort)orientation);
        return exif;
    }
    private static byte[] Jpeg()
    {
        ImageData image = OpaqueFixture();
        var encoder = new JpegBitmapEncoder { QualityLevel = 95 };
        encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(3, 2, 96, 96, PixelFormats.Bgra32, null, image.Bgra, 12)));
        using var stream = new MemoryStream(); encoder.Save(stream); return stream.ToArray();
    }
    private static byte[] AddJpegSegment(byte[] jpeg, byte marker, byte[] payload)
    {
        byte[] segment = new byte[payload.Length + 4]; segment[0] = 255; segment[1] = marker;
        BinaryPrimitives.WriteUInt16BigEndian(segment.AsSpan(2, 2), checked((ushort)(payload.Length + 2))); payload.CopyTo(segment, 4);
        return [..jpeg.AsSpan(0, 2), ..segment, ..jpeg.AsSpan(2)];
    }
    private static int FindSof(byte[] jpeg)
    {
        for (int position = 2; position + 4 < jpeg.Length;)
        {
            if (jpeg[position] != 255) throw new Exception("Test JPEG invalid.");
            if (jpeg[position + 1] is 192 or 193 or 194) return position;
            position += 2 + BinaryPrimitives.ReadUInt16BigEndian(jpeg.AsSpan(position + 2, 2));
        }
        throw new Exception("Test JPEG SOF not found.");
    }
    private static byte[] RawPng(byte colorType, byte[] scanlines, byte[]? palette = null, byte[]? alpha = null)
    {
        byte[] ihdr = new byte[13]; BinaryPrimitives.WriteUInt32BigEndian(ihdr, 3); BinaryPrimitives.WriteUInt32BigEndian(ihdr.AsSpan(4), 2); ihdr[8] = 8; ihdr[9] = colorType;
        using var compressed = new MemoryStream();
        using (var zlib = new ZLibStream(compressed, CompressionLevel.SmallestSize, leaveOpen: true)) zlib.Write(scanlines);
        using var output = new MemoryStream(); output.Write([137,80,78,71,13,10,26,10]);
        void Chunk(string name, byte[] data)
        {
            byte[] chunk = new byte[data.Length + 12]; BinaryPrimitives.WriteUInt32BigEndian(chunk, (uint)data.Length);
            Encoding.ASCII.GetBytes(name).CopyTo(chunk, 4); data.CopyTo(chunk, 8);
            BinaryPrimitives.WriteUInt32BigEndian(chunk.AsSpan(chunk.Length - 4), Crc(chunk.AsSpan(4, chunk.Length - 8))); output.Write(chunk);
        }
        Chunk("IHDR", ihdr);
        if (palette != null) Chunk("PLTE", palette);
        if (alpha != null) Chunk("tRNS", alpha);
        Chunk("IDAT", compressed.ToArray()); Chunk("IEND", []);
        return output.ToArray();
    }
    private static byte[] AddChunk(byte[] png, string type, byte[] payload)
    {
        byte[] chunk = new byte[payload.Length + 12]; BinaryPrimitives.WriteUInt32BigEndian(chunk, (uint)payload.Length);
        Encoding.ASCII.GetBytes(type).CopyTo(chunk, 4); payload.CopyTo(chunk, 8);
        BinaryPrimitives.WriteUInt32BigEndian(chunk.AsSpan(chunk.Length - 4), Crc(chunk.AsSpan(4, chunk.Length - 8)));
        return [..png.AsSpan(0, 33), ..chunk, ..png.AsSpan(33)];
    }
    private static List<string> Chunks(byte[] png)
    {
        var result = new List<string>();
        for (int offset = 8; offset < png.Length; offset += checked(12 + (int)BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(offset))))
            result.Add(Encoding.ASCII.GetString(png, offset + 4, 4));
        return result;
    }
    private static void FixIhdr(byte[] png) => BinaryPrimitives.WriteUInt32BigEndian(png.AsSpan(29, 4), Crc(png.AsSpan(12, 17)));
    private static uint Crc(ReadOnlySpan<byte> data)
    {
        uint crc = uint.MaxValue;
        foreach (byte b in data)
        {
            crc ^= b;
            for (int bit = 0; bit < 8; bit++) crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
        }
        return ~crc;
    }
    private static void Put16(byte[] data, int offset, ushort value) => BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(offset, 2), value);
    private static void Put32(byte[] data, int offset, uint value) => BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(offset, 4), value);
}
