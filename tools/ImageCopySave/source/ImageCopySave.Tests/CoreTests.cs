using ImageCopySave.Engine;
namespace ImageCopySave.Tests;
internal static class CoreTests
{
    private static readonly ImageData Pixel = new(2, 1, [1, 2, 3, 0, 4, 5, 6, 128]);
    public static void Register(Action<string, Action> test)
    {
        test("limits/dimension-boundary", () => { Check.That(ImageLimits.ValidateDimensions(16384, 1) == 65536); Check.Throws<InvalidDataException>(() => ImageLimits.ValidateDimensions(16385, 1)); });
        test("limits/pixel-boundary", () => { Check.That(ImageLimits.ValidateDimensions(10000, 5000) == 200000000); Check.Throws<InvalidDataException>(() => ImageLimits.ValidateDimensions(10000, 5001)); });
        test("limits/zero-negative-overflow", () => { foreach (int n in new[] { 0, -1, int.MaxValue, int.MinValue }) Check.Throws<InvalidDataException>(() => ImageLimits.ValidateDimensions(n, n)); });
        test("limits/payload-boundary", () => { ImageLimits.ValidatePayload(ImageLimits.MaxPayloadBytes); Check.Throws<InvalidDataException>(() => ImageLimits.ValidatePayload((long)ImageLimits.MaxPayloadBytes + 1)); Check.Throws<InvalidDataException>(() => ImageLimits.ValidatePayload(0)); });
        test("limits/exact-buffer", () => Check.Throws<InvalidDataException>(() => new ImageData(1, 1, [0]).Validate()));
        test("save/unicode-path-valid-png", () => WithFolder(folder => { var saved = AtomicPngWriter.Save(Pixel, folder); var result = ImageCodec.Decode(File.ReadAllBytes(saved), ".png"); Check.That(result.Bgra.SequenceEqual(Pixel.Bgra), "Straight-alpha pixels changed"); Check.That(!File.GetAttributes(saved).HasFlag(FileAttributes.Hidden)); Check.That(Directory.GetFiles(folder).Length == 1); }));
        test("save/same-second-existing-file-protected", () => WithFolder(folder => {
            DateTime now = new(2026, 9, 24, 18, 30, 0); string existing = Path.Combine(folder, "그림_20260924_183000.png"); File.WriteAllText(existing, "business sentinel");
            for (int n = 2; n <= 4; n++) { string saved = AtomicPngWriter.SaveCore(Pixel, folder, now, default, null); Check.That(Path.GetFileName(saved) == $"그림_20260924_183000_{n}.png", $"Expected suffix {n}, got {Path.GetFileName(saved)}; names: {string.Join(", ", Directory.GetFileSystemEntries(folder).Select(Path.GetFileName))}"); }
            Check.That(File.ReadAllText(existing) == "business sentinel", "Existing sentinel was modified");
        }));
        test("save/parallel-no-overwrite", () => WithFolder(folder => {
            var paths = new System.Collections.Concurrent.ConcurrentBag<string>();
            Parallel.For(0, 16, i => paths.Add(AtomicPngWriter.SaveCore(Pixel, folder, new DateTime(2026, 9, 24, 18, 30, 0), default, null)));
            Check.That(paths.Distinct().Count() == 16); Check.That(Directory.GetFiles(folder).Length == 16);
            foreach (string p in paths) Check.That(ImageCodec.Decode(File.ReadAllBytes(p), ".png").Bgra.SequenceEqual(Pixel.Bgra));
        }));
        foreach (SaveStage stage in Enum.GetValues<SaveStage>())
        {
            test("save/rollback-" + stage, () => WithFolder(folder => {
                Check.Throws<IOException>(() => AtomicPngWriter.SaveCore(Pixel, folder, DateTime.Now, default, observed => { if (observed == stage) throw new IOException("Injected write/flush/commit failure"); }));
                Check.That(Directory.GetFiles(folder).Length == 0, "Owned temporary leaked");
            }));
            test("save/cancel-" + stage, () => WithFolder(folder => {
                using var cts = new CancellationTokenSource();
                Check.Throws<OperationCanceledException>(() => AtomicPngWriter.SaveCore(Pixel, folder, DateTime.Now, cts.Token, observed => { if (observed == stage) cts.Cancel(); }));
                Check.That(Directory.GetFiles(folder).Length == 0);
            }));
        }
        test("save/cancel-before-create", () => WithFolder(folder => { Check.Throws<OperationCanceledException>(() => AtomicPngWriter.Save(Pixel, folder, new CancellationToken(true))); Check.That(Directory.GetFiles(folder).Length == 0); }));
        test("save/directory-name-collision", () => WithFolder(folder => {
            Directory.CreateDirectory(Path.Combine(folder,"그림_20260924_183000.png"));
            string output = AtomicPngWriter.SaveCore(Pixel, folder, new DateTime(2026,9,24,18,30,0), default, null);
            Check.That(Path.GetFileName(output).EndsWith("_2.png"));
        }));
        test("save/invalid-image-no-file", () => WithFolder(folder => { Check.Throws<InvalidDataException>(() => AtomicPngWriter.Save(new ImageData(1,1,[]),folder)); Check.That(Directory.GetFiles(folder).Length == 0); }));
        test("source/read-and-original-protection", () => WithFolder(folder => {
            string source = Path.Combine(folder,"원본 (é).png"); byte[] bytes = ImageCodec.EncodePng(Pixel); File.WriteAllBytes(source,bytes); File.SetAttributes(source,FileAttributes.ReadOnly);
            try { ImageData image = LocalPaths.ReadImage(source); Check.That(image.Bgra.SequenceEqual(Pixel.Bgra)); Check.That(File.ReadAllBytes(source).SequenceEqual(bytes)); }
            finally { File.SetAttributes(source,FileAttributes.Normal); }
        }));
        test("source/reject-path-and-unsupported", () => {
            foreach (string invalid in new[] { "relative.png", @"\\server\share\a.png", @"C:\a.png:stream", @"\\?\C:\a.png" }) Check.Throws<IOException>(() => LocalPaths.ReadImage(invalid));
            WithFolder(folder => { string unsupported = Path.Combine(folder,"a.gif"); File.WriteAllBytes(unsupported, ImageCodec.EncodePng(Pixel)); Check.Throws<InvalidDataException>(() => LocalPaths.ReadImage(unsupported)); });
        });
        test("source/reject-device-path-before-reading", () => WithFolder(folder => {
            string real = Path.Combine(folder,"real"); Directory.CreateDirectory(real); string link = Path.Combine(folder,"link");
            // Directory symlink privileges vary, so this test uses the already-supported
            // input rejection contract for noncanonical device paths independently.
            Check.Throws<IOException>(() => LocalPaths.Validate(@"\\?\" + real, true));
        }));
    }
    private static void WithFolder(Action<string> action)
    {
        string root = Path.Combine(Path.GetTempPath(), "ImageCopySave-tests-" + Guid.NewGuid().ToString("N"));
        string folder = Path.Combine(root, "한글 폴더 (é)"); Directory.CreateDirectory(folder);
        try { action(folder); }
        finally
        {
            string resolved = Path.GetFullPath(root); string allowed = Path.GetFullPath(Path.GetTempPath());
            if (!resolved.StartsWith(allowed, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(resolved).StartsWith("ImageCopySave-tests-",StringComparison.Ordinal)) throw new IOException("Unsafe cleanup path");
            Directory.Delete(resolved,true);
        }
    }
}
