using System.Buffers.Binary;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ImageCopySave.Engine;

namespace ImageCopySave.Tests;

// Product-process cases share only the already verified private-station harness.
// No case substitutes a test publisher for the actual product copy/save command.
public static partial class ClipboardTests
{
    private static partial class HelperProcessTests
    {
        private static string HelperExe => Environment.GetEnvironmentVariable("IMAGE_COPY_SAVE_TEST_HELPER")
            ?? Path.Combine(AppContext.BaseDirectory, "helper", "ImageCopySave.Helper.exe");

        public static void EnsureAvailable()
        {
            if (!Path.IsPathFullyQualified(HelperExe) || !File.Exists(HelperExe))
                throw new TestUnavailableException("Product helper executable unavailable; supply --helper with an absolute ImageCopySave.Helper.exe path.");
        }

        public static void Run(string scenario)
        {
            VerifyPrivateStation(ActiveStation);
            EnsureAvailable();
            string sources = OwnedDirectory("product-source");
            string saves = OwnedDirectory("product-save");
            switch (scenario)
            {
                case "product-copy-save-alpha": CopySaveAlpha(sources, saves); break;
                case "product-jpeg-copy": JpegCopy(sources, saves); break;
                case "product-invalid-preserves": InvalidPreserves(sources); break;
                case "product-empty-save": EmptySave(saves); break;
                case "product-parallel-save": ParallelSave(saves); break;
                case "product-save-current": SaveCurrent(saves); break;
                case "product-worker-cancel": WorkerCancel(saves); break;
                case "product-watchdog": Watchdog(saves); break;
                case "product-snapshot-other-copy": SnapshotOtherCopy(sources, saves); break;
                case "product-corrupt-clipboard": CorruptClipboard(saves); break;
                case "product-copy-preparation-race": CopyPreparationRace(sources); break;
                case "product-worker-inflight-cancel": WorkerInflightCancel(sources, saves); break;
                case "product-shell-roundtrip": ShellRoundTrip(sources, saves); break;
                case "product-shell-invoke-guard": ShellInvokeGuard(sources, saves); break;
                default: throw new InvalidOperationException("Unknown product helper scenario.");
            }
        }

        private static NativeChild Product(params string[] arguments) => new(HelperExe, arguments, ActiveStation, OwnedDirectory("product-log"));

        private static void ShellRoundTrip(string sources, string saves)
        {
            byte[] bytes = ImageCodec.EncodePng(Fixture());
            string source = Path.Combine(sources, "셸 호출 그림 (시험).png");
            File.WriteAllBytes(source, bytes);
            RunProduct(0, "--shell", "copy", source, ClipboardEngine.CaptureSequence().ToString(CultureInfo.InvariantCulture), "0");
            CheckImage(Fixture(), ClipboardEngine.Capture(), "shell GUI helper exits with durable copy");
            uint sequence = ClipboardEngine.CaptureSequence();
            RunProduct(0, "--shell", "save", saves, sequence.ToString(CultureInfo.InvariantCulture), "0");
            CheckImage(Fixture(), ImageCodec.Decode(File.ReadAllBytes(ExactlyOneSaved(saves)), ".png"), "shell GUI save");
            Check.That(ClipboardEngine.CaptureSequence() == sequence, "Shell save changed clipboard.");
            AssertSourceUnchanged(source, bytes);
        }

        private static void ShellInvokeGuard(string sources, string saves)
        {
            byte[] bytes = ImageCodec.EncodePng(Fixture());
            string source = Path.Combine(sources, "stale-invoke.png");
            File.WriteAllBytes(source, bytes);
            SetText("old-shell-invoke");
            uint old = ClipboardEngine.CaptureSequence();
            ClipboardEngine.Copy(Fixture(), old);
            uint current = ClipboardEngine.CaptureSequence();
            Check.That(old != current);
            // Explicitly simulate the shell-to-helper launch gap, before any worker starts.
            RunProduct(1, "--shell", "copy", source, old.ToString(CultureInfo.InvariantCulture), "0");
            RunProduct(1, "--shell", "save", saves, old.ToString(CultureInfo.InvariantCulture), "0");
            AssertNoFiles(saves, "stale shell save");
            Check.That(ClipboardEngine.CaptureSequence() == current, "A stale shell invocation changed the newer clipboard.");
            CheckImage(Fixture(), ClipboardEngine.Capture(), "newer clipboard after stale shell invocation");
            AssertSourceUnchanged(source, bytes);
        }

        private static void RunProduct(uint expectedCode, params string[] arguments)
            => RunProductChecked(expectedCode, arguments, [], []);

        private static void RunProductChecked(uint expectedCode, string[] arguments, string[] forbiddenText, params byte[][] forbiddenBytes)
        {
            using var child = Product(arguments);
            uint code = child.WaitForExit(10000);
            // Inspect the raw bounded streams before any redacted summary is produced.
            if (forbiddenText.Length != 0 || forbiddenBytes.Length != 0)
                child.AssertDiagnosticsExclude(forbiddenText, forbiddenBytes);
            Check.That(code == expectedCode, $"Product helper {arguments[0]}: expected exit {expectedCode}, actual {code}. " + child.DiagnosticSummary());
            child.AssertNoSurvivingChildren();
        }

        private static void CopySaveAlpha(string sources, string saves)
        {
            byte[] bytes = ImageCodec.EncodePng(Fixture());
            string original = Path.Combine(sources, "alpha original.png");
            File.WriteAllBytes(original, bytes);
            RunProduct(0, "copy", original); // Wait includes supervisor exit and no surviving worker.
            AssertSourceUnchanged(original, bytes);
            string moved = Path.Combine(sources, "alpha moved.png");
            File.Move(original, moved);
            File.Delete(moved);
            Check.That(!File.Exists(original) && !File.Exists(moved), "Source removal after helper exit did not complete.");
            uint sequence = ClipboardEngine.CaptureSequence();
            CheckImage(Fixture(), ClipboardEngine.Capture(), "actual helper exit and source deletion");
            RunProduct(0, "save", saves);
            string saved = ExactlyOneSaved(saves);
            CheckImage(Fixture(), ImageCodec.Decode(File.ReadAllBytes(saved), ".png"), "actual helper PNG exact alpha and transparent RGB");
            Check.That(ClipboardEngine.CaptureSequence() == sequence, "Actual helper save changed clipboard sequence.");
        }

        private static void JpegCopy(string sources, string saves)
        {
            (byte[] jpeg, ImageData expected) = OrientationSixJpeg();
            string original = Path.Combine(sources, "orientation6.jpg");
            File.WriteAllBytes(original, jpeg);
            RunProduct(0, "copy", original);
            AssertSourceUnchanged(original, jpeg);
            File.Delete(original);
            CheckImage(expected, ClipboardEngine.Capture(), "actual helper JPEG EXIF6 axes and pixels");
            RunProduct(0, "save", saves);
            CheckImage(expected, ImageCodec.Decode(File.ReadAllBytes(ExactlyOneSaved(saves)), ".png"),
                "actual helper JPEG EXIF6 to PNG");
        }

        private static void InvalidPreserves(string sources)
        {
            byte[] bytes = Encoding.UTF8.GetBytes("ImageCopySave-Invalid-Fixture-8273");
            string invalid = Path.Combine(sources, "invalid.png");
            File.WriteAllBytes(invalid, bytes);
            SetText("product-invalid-preserve");
            uint sequence = ClipboardEngine.CaptureSequence();
            RunProductChecked(1, ["copy", invalid],
                [invalid, Path.GetFileName(invalid), "product-invalid-preserve", Encoding.UTF8.GetString(bytes),
                    Convert.ToHexString(bytes), Convert.ToBase64String(bytes)], bytes);
            AssertSourceUnchanged(invalid, bytes);
            Check.That(ClipboardEngine.CaptureSequence() == sequence && ReadText() == "product-invalid-preserve",
                "Invalid actual helper copy changed the previous clipboard.");
            byte[] validBytes = ImageCodec.EncodePng(Fixture());
            string valid = Path.Combine(sources, "context-guard.png");
            File.WriteAllBytes(valid, validBytes);
            string cancelName = "Local\\ImageCopySave-Cancel-" + Guid.NewGuid().ToString("N");
            using var cancellation = new EventWaitHandle(false, EventResetMode.ManualReset, cancelName);
            // A valid operation would succeed and overwrite the sentinel if the internal
            // context guard were ignored. No stderr-stage claim is made by this assertion.
            RunProductChecked(1, ["--worker", "copy", valid, cancelName, sequence.ToString(CultureInfo.InvariantCulture),
                ActiveStation + "-deliberate-mismatch", "Test"],
                [valid, Path.GetFileName(valid), "product-invalid-preserve", Convert.ToHexString(validBytes), Convert.ToBase64String(validBytes)], validBytes);
            AssertSourceUnchanged(valid, validBytes);
            Check.That(ClipboardEngine.CaptureSequence() == sequence && ReadText() == "product-invalid-preserve",
                "Mismatched internal worker context did not preserve the previous clipboard.");
        }

        private static void EmptySave(string saves)
        {
            SetRaw();
            uint sequence = ClipboardEngine.CaptureSequence();
            RunProduct(1, "save", saves);
            AssertNoFiles(saves, "empty clipboard save");
            Check.That(ClipboardEngine.CaptureSequence() == sequence, "Empty actual helper save changed clipboard.");
            SetText("product-text-save-preserve");
            sequence = ClipboardEngine.CaptureSequence();
            RunProduct(1, "save", saves);
            AssertNoFiles(saves, "text clipboard save");
            Check.That(ClipboardEngine.CaptureSequence() == sequence && ReadText() == "product-text-save-preserve",
                "Text-only actual helper save changed clipboard.");
        }

        private static void ParallelSave(string saves)
        {
            ClipboardEngine.Copy(Fixture(), ClipboardEngine.CaptureSequence());
            uint sequence = ClipboardEngine.CaptureSequence();
            // Increase exposure to intermittent concurrent-save failures while keeping
            // the acceptance case count stable: exercise 32 real helper saves.
            for (int batch = 1; batch <= 8; batch++)
            {
                try { ParallelSaveRound(saves, sequence, batch); }
                catch (Exception error)
                {
                    throw new InvalidOperationException($"Parallel actual helper batch {batch}/8: " + error.Message, error);
                }
            }
        }

        private static void ParallelSaveRound(string saves, uint sequence, int batch)
        {
            AssertNoFiles(saves, $"before parallel batch {batch}/8");
            // Reserve every base name for this batch's fresh bounded launch interval.
            // This deterministically exercises collisions without modifying the product clock.
            var sentinels = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
            DateTime first = DateTime.Now.AddSeconds(-1);
            for (int seconds = 0; seconds <= 31; seconds++)
            {
                string name = "그림_" + first.AddSeconds(seconds).ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture) + ".png";
                string path = Path.Combine(saves, name);
                byte[] marker = Encoding.UTF8.GetBytes($"owned-sentinel-batch-{batch}-{seconds}");
                File.WriteAllBytes(path, marker); sentinels.Add(path, marker);
            }
            var children = new List<NativeChild>();
            string[] created = [];
            try
            {
                var timer = Stopwatch.StartNew();
                for (int i = 0; i < 4; i++) children.Add(Product("save", saves));
                for (int i = 0; i < children.Count; i++)
                {
                    NativeChild child = children[i];
                    uint remaining = checked((uint)Math.Max(1, 14000 - timer.ElapsedMilliseconds));
                    uint code = child.WaitForExit(remaining);
                    Check.That(code == 0, $"Child {i + 1}/4 failed with exit {code}. " + child.DiagnosticSummary());
                    child.AssertNoSurvivingChildren();
                }
                foreach (var sentinel in sentinels) AssertSourceUnchanged(sentinel.Key, sentinel.Value);
                created = Directory.GetFiles(saves).Where(path => !sentinels.ContainsKey(path)).ToArray();
                Check.That(created.Length == 4 && created.Distinct(StringComparer.OrdinalIgnoreCase).Count() == 4,
                    "Four parallel helpers did not create four distinct files, or left a temporary file.");
                foreach (string path in created)
                {
                    string name = Path.GetFileName(path);
                    Check.That(name.EndsWith(".png", StringComparison.OrdinalIgnoreCase), "Parallel helper left a non-PNG output.");
                    string stem = Path.GetFileNameWithoutExtension(path);
                    int suffixPosition = stem.LastIndexOf('_');
                    Check.That(suffixPosition > 0 && int.TryParse(stem[(suffixPosition + 1)..], out int suffix) && suffix >= 2,
                        "Parallel collision fixture did not exercise a numbered no-replace destination.");
                    string basePath = Path.Combine(saves, stem[..suffixPosition] + ".png");
                    Check.That(sentinels.ContainsKey(basePath), "Parallel save escaped the collision fixture's reserved interval.");
                    CheckImage(Fixture(), ImageCodec.Decode(File.ReadAllBytes(path), ".png"), $"parallel batch {batch}/8 actual helper PNG");
                }
                Check.That(!Directory.EnumerateDirectories(saves).Any(), "Parallel save created an unexpected directory.");
                Check.That(ClipboardEngine.CaptureSequence() == sequence, "Parallel actual helper saves changed clipboard.");
            }
            finally { foreach (NativeChild child in children) child.Dispose(); }

            // All products have exited and passed validation. Remove only the exact
            // output/sentinel lists from this owned batch before starting the next one.
            foreach (string path in created) File.Delete(path);
            foreach (string path in sentinels.Keys) File.Delete(path);
            AssertNoFiles(saves, $"after parallel batch {batch}/8 cleanup");
        }

        private static void SaveCurrent(string saves)
        {
            ClipboardEngine.Copy(Fixture(), ClipboardEngine.CaptureSequence());
            uint earlier = ClipboardEngine.CaptureSequence();
            var current = new ImageData(1, 2, [29, 47, 73, 255, 199, 41, 11, 63]);
            ClipboardEngine.Copy(current, earlier);
            uint sequence = ClipboardEngine.CaptureSequence();
            Check.That(sequence != earlier, "Current-image fixture did not change the clipboard.");
            RunProduct(0, "save", saves);
            CheckImage(current, ImageCodec.Decode(File.ReadAllBytes(ExactlyOneSaved(saves)), ".png"), "actual helper uses current image B");
            Check.That(ClipboardEngine.CaptureSequence() == sequence, "Saving current image changed its clipboard sequence.");
            CheckImage(current, ClipboardEngine.Capture(), "current clipboard B preserved after actual save");
        }

        private static void WorkerCancel(string saves)
        {
            SetText("product-worker-cancel-preserve");
            uint sequence = ClipboardEngine.CaptureSequence();
            using var locker = Child("--clipboard-lock");
            WaitForFile("ready.txt", 5000);
            try
            {
                string cancelName = "Local\\ImageCopySave-Cancel-" + Guid.NewGuid().ToString("N");
                // This is the internal worker's already-requested cancellation contract,
                // with a real lock holder. It is not a UI Ctrl+C or mid-commit cancellation test.
                using var cancellation = new EventWaitHandle(true, EventResetMode.ManualReset, cancelName);
                RunProduct(3, "--worker", "save", saves, cancelName, "0", ActiveStation, "Test");
                AssertNoFiles(saves, "canceled internal product worker");
            }
            finally { File.WriteAllText(Path.Combine(WorkerDirectory, "stop.txt"), "stop"); }
            locker.Wait(5000);
            Check.That(ClipboardEngine.CaptureSequence() == sequence && ReadText() == "product-worker-cancel-preserve",
                "Canceled internal product worker changed the locked clipboard.");
        }

        private static void Watchdog(string saves)
        {
            using var provider = Child("--clipboard-hang");
            WaitForFile("ready.txt", 5000);
            Check.That(ClipboardEngine.HasSupportedImage(), "Hang fixture did not advertise delayed PNG.");
            Check.That(!File.Exists(Path.Combine(WorkerDirectory, "rendered.txt")), "Metadata query invoked the hang fixture.");
            var elapsed = Stopwatch.StartNew();
            using var helper = Product("save", saves);
            WaitForFile("rendered.txt", 5000);
            // The marker proves actual GetClipboardData reached the blocked WM_RENDERFORMAT,
            // rather than merely exercising an unrelated launch/clipboard-access error.
            uint code = helper.WaitForExit(18000);
            long milliseconds = elapsed.ElapsedMilliseconds;
            Check.That(code == 3, $"Product watchdog expected exit 3, actual {code}; elapsed {milliseconds} ms. " + helper.DiagnosticSummary());
            // Product policy is 15 s plus 1 s cancellation grace; allow explicit startup/
            // scheduling margin in this integration test rather than claiming precision.
            Check.That(milliseconds >= 14000 && milliseconds < 19000,
                $"Product watchdog elapsed {milliseconds} ms outside the 14–19 s integration bound.");
            helper.AssertNoSurvivingChildren(); // Check before job disposal can hide a leaked worker.
            AssertNoFiles(saves, "watchdog-terminated actual helper");
            Check.That(provider.IsRunning, "Product watchdog unexpectedly terminated the independent clipboard provider.");
            // Provider is verified alive and intentionally still hung. Its separate owned job disposes it.
        }

        private static void AssertSourceUnchanged(string path, byte[] original)
        {
            byte[] actual = File.ReadAllBytes(path);
            Check.That(actual.AsSpan().SequenceEqual(original)
                && SHA256.HashData(actual).AsSpan().SequenceEqual(SHA256.HashData(original)),
                "An owned source/sentinel fixture changed bytes or SHA-256.");
        }

        private static string ExactlyOneSaved(string directory)
        {
            string[] files = Directory.GetFiles(directory);
            Check.That(files.Length == 1 && files[0].EndsWith(".png", StringComparison.OrdinalIgnoreCase)
                && !Directory.EnumerateDirectories(directory).Any(),
                "Actual helper did not produce exactly one PNG with no temporary files/directories.");
            return files[0];
        }

        private static void AssertNoFiles(string directory, string context)
            => Check.That(!Directory.EnumerateFileSystemEntries(directory).Any(), context + " left a file or directory.");

        private static string OwnedDirectory(string name)
        {
            string path = Path.GetFullPath(Path.Combine(WorkerDirectory, name));
            string expectedParent = Path.GetFullPath(WorkerDirectory);
            Check.That(string.Equals(Path.GetDirectoryName(path), expectedParent, StringComparison.OrdinalIgnoreCase),
                "Product fixture directory must be an immediate owned child.");
            Directory.CreateDirectory(path);
            return path;
        }

        public static void Cleanup(string workerDirectory)
        {
            // These exact children are created only in our fresh GUID test root.
            // Do not recurse or follow reparse points, even after a failed test.
            foreach (string name in new[] { "product-source", "product-save", "product-log" })
            {
                string parent = Path.GetFullPath(workerDirectory);
                string path = Path.GetFullPath(Path.Combine(parent, name));
                Check.That(string.Equals(Path.GetDirectoryName(path), parent, StringComparison.OrdinalIgnoreCase),
                    "Unsafe product fixture cleanup path.");
                if (!Directory.Exists(path)) continue;
                Check.That((File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0, "Refusing reparse-point fixture cleanup.");
                foreach (string file in Directory.EnumerateFiles(path, "*", SearchOption.TopDirectoryOnly)) File.Delete(file);
                Directory.Delete(path); // Unexpected subdirectories fail instead of being traversed.
            }
        }

        private static (byte[] Encoded, ImageData Expected) OrientationSixJpeg()
        {
            // Same six synthetic colors as CodecTests; source visual order is A B C / D E F.
            byte[] pixels = [19,31,47,255, 101,203,55,255, 51,81,211,255, 200,3,71,255, 17,213,99,255, 34,5,188,255];
            var encoder = new JpegBitmapEncoder { QualityLevel = 95 };
            encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(3, 2, 96, 96, PixelFormats.Bgra32, null, pixels, 12)));
            using var stream = new MemoryStream(); encoder.Save(stream);
            byte[] jpeg = stream.ToArray();
            ImageData decoded = ImageCodec.Decode(jpeg, ".jpg");
            // JPEG is lossy: golden pixels come from the untagged decode. The EXIF transform
            // is independently specified, without calling the product orientation method.
            int[] order = [3, 0, 4, 1, 5, 2]; // D A / E B / F C; clockwise 90 degrees, 2x3.
            byte[] expected = new byte[24];
            for (int i = 0; i < order.Length; i++) decoded.Bgra.AsSpan(order[i] * 4, 4).CopyTo(expected.AsSpan(i * 4));
            byte[] exif = new byte[26];
            exif[0] = exif[1] = (byte)'I';
            BinaryPrimitives.WriteUInt16LittleEndian(exif.AsSpan(2), 42);
            BinaryPrimitives.WriteUInt32LittleEndian(exif.AsSpan(4), 8);
            BinaryPrimitives.WriteUInt16LittleEndian(exif.AsSpan(8), 1);
            BinaryPrimitives.WriteUInt16LittleEndian(exif.AsSpan(10), 0x0112);
            BinaryPrimitives.WriteUInt16LittleEndian(exif.AsSpan(12), 3);
            BinaryPrimitives.WriteUInt32LittleEndian(exif.AsSpan(14), 1);
            BinaryPrimitives.WriteUInt16LittleEndian(exif.AsSpan(18), 6);
            byte[] payload = [.."Exif\0\0"u8.ToArray(), ..exif];
            byte[] segment = new byte[payload.Length + 4]; segment[0] = 255; segment[1] = 225;
            BinaryPrimitives.WriteUInt16BigEndian(segment.AsSpan(2), checked((ushort)(payload.Length + 2)));
            payload.CopyTo(segment, 4);
            return ([..jpeg.AsSpan(0, 2), ..segment, ..jpeg.AsSpan(2)], new ImageData(2, 3, expected));
        }
    }
}
