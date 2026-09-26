namespace ImageCopySave.Engine;

// The contract is straight BGRA, not premultiplied. Callers own the buffer.
public sealed record ImageData(int Width, int Height, byte[] Bgra)
{
    public void Validate()
    {
        ArgumentNullException.ThrowIfNull(Bgra);
        if (Bgra.Length != ImageLimits.ValidateDimensions(Width, Height))
            throw new InvalidDataException("Pixel buffer length does not match dimensions.");
    }
}

public static class ImageLimits
{
    public const int MaxDimension = 16_384;
    public const long MaxPixels = 50_000_000;
    public const int MaxPayloadBytes = 128 * 1024 * 1024;
    public const int MaxBufferBytes = 256 * 1024 * 1024;
    public static int ValidateDimensions(int width, int height)
    {
        if (width <= 0 || height <= 0 || width > MaxDimension || height > MaxDimension)
            throw new InvalidDataException("Image dimension limit exceeded.");
        long pixels = checked((long)width * height);
        long bytes = checked(pixels * 4);
        if (pixels > MaxPixels || bytes > MaxBufferBytes)
            throw new InvalidDataException("Image buffer limit exceeded.");
        return checked((int)bytes);
    }
    public static void ValidatePayload(long length)
    {
        if (length <= 0 || length > MaxPayloadBytes)
            throw new InvalidDataException("Image payload limit exceeded.");
    }
}
