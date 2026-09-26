using ImageCopySave.Engine;
namespace ImageCopySave.Tests;

internal static class SafetyTests
{
    private static readonly ImageData Pixel = new(1, 1, [3, 5, 7, 128]);
    public static void Register(Action<string, Action> test)
    {
        test("path/ancestry-cannot-rename-while-pinned", () => WithFolder(folder =>
        {
            string parent = Path.Combine(folder, "parent");
            string child = Path.Combine(parent, "child");
            Directory.CreateDirectory(child);
            using (LocalPaths.Acquire(child, true))
            {
                Check.Throws<IOException>(() => Directory.Move(child, child + "-moved"));
                Check.Throws<IOException>(() => Directory.Move(parent, parent + "-moved"));
            }
            Directory.Move(child, child + "-moved");
            Check.That(Directory.Exists(child + "-moved"), "Pins were not released");
        }));
        test("path/source-cannot-replace-while-pinned", () => WithFolder(folder =>
        {
            string source = Path.Combine(folder, "source.png");
            byte[] original = ImageCodec.EncodePng(Pixel); File.WriteAllBytes(source, original);
            using (LocalPaths.Acquire(source, false))
            {
                Check.Throws<IOException>(() => File.Move(source, source + ".moved"));
                Check.Throws<IOException>(() => File.WriteAllText(source, "replacement"));
                Check.That(File.ReadAllBytes(source).SequenceEqual(original));
            }
            File.Move(source, source + ".moved");
        }));
        test("save/directory-pinned-through-commit", () => WithFolder(folder =>
        {
            string target = Path.Combine(folder, "target"); Directory.CreateDirectory(target);
            string result = AtomicPngWriter.SaveCore(Pixel, target, DateTime.Now, default, stage =>
            {
                if (stage == SaveStage.BeforeCommit)
                    Check.Throws<IOException>(() => Directory.Move(target, target + "-moved"));
            });
            Check.That(File.Exists(result) && Path.GetDirectoryName(result) == target);
            Check.That(ImageCodec.Decode(File.ReadAllBytes(result), ".png").Bgra.SequenceEqual(Pixel.Bgra));
        }));
        test("save/owned-temp-replacement-blocked", () => WithFolder(folder =>
        {
            Check.Throws<IOException>(() => AtomicPngWriter.SaveCore(Pixel, folder, DateTime.Now, default, stage =>
            {
                if (stage != SaveStage.Created) return;
                string temporary = Directory.GetFiles(folder, ".ImageCopySave-*.tmp").Single();
                Check.Throws<IOException>(() => File.Move(temporary, temporary + ".moved"));
                throw new IOException("Injected operation failure after replacement attempt");
            }));
            Check.That(Directory.GetFiles(folder).Length == 0, "Owned temporary was not cleaned");
        }));
        test("save/cleanup-native-failure-reported", () => WithFolder(folder =>
        {
            string? temporary = null;
            try
            {
                var error = Check.Throws<OwnedTemporaryCleanupException>(() => AtomicPngWriter.SaveCore(Pixel, folder, DateTime.Now, default, stage =>
                {
                    if (stage != SaveStage.Created) return;
                    temporary = Directory.GetFiles(folder, ".ImageCopySave-*.tmp").Single();
                    File.SetAttributes(temporary, FileAttributes.ReadOnly);
                    throw new IOException("Injected operation failure");
                }));
                Check.That(error.NativeErrorCode != 0 && (error.HResult & 0xffff) == error.NativeErrorCode);
                Check.That(error.InnerException is IOException && temporary != null && File.Exists(temporary));
                Check.That(Directory.GetFiles(folder, "*.png").Length == 0);
            }
            finally
            {
                if (temporary != null && File.Exists(temporary))
                { File.SetAttributes(temporary, FileAttributes.Normal); File.Delete(temporary); }
            }
        }));
        test("save/read-only-name-collision-preserved", () => WithFolder(folder =>
        {
            DateTime instant = new(2026, 9, 24, 18, 30, 0);
            string existing = Path.Combine(folder, "그림_20260924_183000.png");
            File.WriteAllText(existing, "read-only sentinel"); File.SetAttributes(existing, FileAttributes.ReadOnly);
            try
            {
                string result = AtomicPngWriter.SaveCore(Pixel, folder, instant, default, null);
                Check.That(Path.GetFileName(result) == "그림_20260924_183000_2.png");
                Check.That(File.ReadAllText(existing) == "read-only sentinel");
            }
            finally { File.SetAttributes(existing, FileAttributes.Normal); }
        }));
    }
    private static void WithFolder(Action<string> action)
    {
        string parent = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string root = Path.Combine(parent, "ImageCopySave-safety-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try { action(root); }
        finally
        {
            string resolved = Path.GetFullPath(root);
            if (!resolved.StartsWith(parent, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(resolved).StartsWith("ImageCopySave-safety-", StringComparison.Ordinal))
                throw new IOException("Unsafe safety-test cleanup path");
            Directory.Delete(resolved, true);
        }
    }
}
