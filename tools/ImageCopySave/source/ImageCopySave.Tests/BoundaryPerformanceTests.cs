using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using ImageCopySave.Engine;

namespace ImageCopySave.Tests;

public static class BoundaryPerformanceTests
{
    private const string BoundaryName = "limits/actual-pixel-boundaries-roundtrip";
    private const string PerformanceName = "performance/4k-engine-save-read-p50-p95";
    private const long MinimumAvailableBytes = 3L * 1024 * 1024 * 1024;
    private const int PerformanceBudgetSeconds = 90;
    private const string FixtureKind = "deterministic 8-bit straight BGRA horizontal/vertical gradient with wrapped red/alpha, including transparent and opaque pixels";
    private static readonly List<object> observations = [];
    public static IReadOnlyList<object> Evidence => observations;

    public static void Register(Action<string, Action> test)
    {
        test(BoundaryName, ActualPixelBoundaries);
        test(PerformanceName, Measure4K);
    }

    private static void ActualPixelBoundaries()
    {
        CollectReleasedFixtures();
        MemoryAvailability initial = RequireMemory(BoundaryName);
        using var folder = new IntegrationFolder("actual-pixel-boundaries");
        var completed = new List<BoundaryObservation>();
        // Deliberately allocate real BGRA data even for the two over-limit inputs.
        // No PNG payload-size or 256 MiB buffer-limit boundary is claimed by this matrix.
        (int Width, int Height, bool Accepted)[] cases =
        [
            (16_383, 1, true), (16_384, 1, true), (16_385, 1, false),
            (9_999, 5_000, true), (10_000, 5_000, true), (10_000, 5_001, false)
        ];
        try
        {
            foreach (var item in cases)
            {
                CollectReleasedFixtures();
                RequireMemory(BoundaryName);
                completed.Add(RunBoundary(folder.Root, item.Width, item.Height, item.Accepted));
            }
            AssertEmpty(folder.Root, "Boundary matrix");
            observations.Add(new
            {
                test = BoundaryName, status = "PASS", fixtureKind = FixtureKind,
                scope = "actual dimension and pixel-count boundaries; engine PNG save/read only; not all 128 MiB payload or 256 MiB guard boundaries",
                minimumAvailableBytes = MinimumAvailableBytes, initialMemory = initial,
                sequentialFixtures = true, collectionBetweenFixtures = true, cases = completed.ToArray()
            });
        }
        catch (TestUnavailableException)
        {
            observations.Add(new { test = BoundaryName, status = "NOT RUN", completedCasesOnly = completed.ToArray(), wholeMatrixCompleted = false });
            throw;
        }
        finally { CollectReleasedFixtures(); }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static BoundaryObservation RunBoundary(string folder, int width, int height, bool accepted)
    {
        AssertEmpty(folder, "Before boundary fixture");
        ImageData expected = CreateFixture(width, height);
        if (!accepted)
        {
            Check.Throws<InvalidDataException>(() => AtomicPngWriter.Save(expected, folder));
            AssertEmpty(folder, "Over-limit rejection");
            return new(width, height, (long)width * height, expected.Bgra.LongLength, false,
                "rejected before output", 0, false, false);
        }

        string? output = null;
        try
        {
            output = AtomicPngWriter.Save(expected, folder);
            ImageData actual = LocalPaths.ReadImage(output);
            AssertPixels(expected, actual);
            AssertOnePng(folder, output);
            return new(width, height, (long)width * height, expected.Bgra.LongLength, true,
                "saved and read exactly", new FileInfo(output).Length, true, true);
        }
        finally
        {
            if (output != null) File.Delete(output);
            AssertEmpty(folder, "After boundary fixture");
        }
    }

    private static void Measure4K()
    {
        CollectReleasedFixtures();
        MemoryAvailability initial = RequireMemory(PerformanceName);
        using var folder = new IntegrationFolder("4k-performance");
        using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(PerformanceBudgetSeconds));
        var elapsed = Stopwatch.StartNew();
        ImageData fixture = CreateFixture(3_840, 2_160);
        const int warmups = 2, count = 10;
        var samples = new List<RoundTripSample>(count);
        try
        {
            for (int iteration = 0; iteration < warmups + count; iteration++)
            {
                // Keep native WIC and decoded managed buffers from accumulating. Collection,
                // fixture generation, pixel verification and file deletion are not timed samples.
                CollectReleasedFixtures();
                CheckBudget(elapsed, budget.Token);
                RoundTripSample sample = RunTimedRoundTrip(fixture, folder.Root, budget.Token);
                CheckBudget(elapsed, budget.Token);
                if (iteration >= warmups) samples.Add(sample);
            }
            Check.That(samples.Count == count, "The complete ten-sample performance series was not collected.");
            AssertEmpty(folder.Root, "4K performance series");
            observations.Add(new
            {
                test = PerformanceName, status = "PASS", width = fixture.Width, height = fixture.Height,
                pixels = (long)fixture.Width * fixture.Height, bgraBytes = fixture.Bgra.LongLength,
                fixtureKind = FixtureKind, warmupCount = warmups, measuredCount = samples.Count,
                allWarmupsAndSamplesValidatedExactly = true, noResize = true,
                scope = "engine codec/files only; not helper/menu/end-user 2 second target",
                timedScope = "Save includes encoding and file flush/commit; Read includes local file read and decoding; validation, cleanup and GC excluded",
                budgetSeconds = PerformanceBudgetSeconds, budgetKind = "cooperative cancellation and between-call checks; synchronous WIC calls are not forcibly interrupted",
                elapsedMilliseconds = elapsed.Elapsed.TotalMilliseconds,
                minimumAvailableBytes = MinimumAvailableBytes, initialMemory = initial,
                collectionBetweenIterations = true, percentileMethod = "nearest rank: sorted[ceil(p * n) - 1]",
                saveMilliseconds = Percentiles(samples.Select(s => s.SaveMilliseconds)),
                readMilliseconds = Percentiles(samples.Select(s => s.ReadMilliseconds)),
                roundTripMilliseconds = Percentiles(samples.Select(s => s.RoundTripMilliseconds)),
                encodedPngBytes = samples.Select(s => s.EncodedPngBytes).ToArray(), samples = samples.ToArray()
            });
        }
        catch (OperationCanceledException) when (budget.IsCancellationRequested)
        { throw new TimeoutException("The 4K engine measurement exceeded its 90-second cooperative test budget; no complete performance result is claimed."); }
        finally { CollectReleasedFixtures(); }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static RoundTripSample RunTimedRoundTrip(ImageData expected, string folder, CancellationToken cancellation)
    {
        AssertEmpty(folder, "Before 4K sample");
        string? output = null;
        try
        {
            long start = Stopwatch.GetTimestamp();
            output = AtomicPngWriter.Save(expected, folder, cancellation);
            long saved = Stopwatch.GetTimestamp();
            ImageData actual = LocalPaths.ReadImage(output, cancellation);
            long read = Stopwatch.GetTimestamp();
            AssertPixels(expected, actual);
            AssertOnePng(folder, output);
            return new(Stopwatch.GetElapsedTime(start, saved).TotalMilliseconds,
                Stopwatch.GetElapsedTime(saved, read).TotalMilliseconds,
                Stopwatch.GetElapsedTime(start, read).TotalMilliseconds, new FileInfo(output).Length);
        }
        finally
        {
            if (output != null) File.Delete(output);
            AssertEmpty(folder, "After 4K sample");
        }
    }

    private static ImageData CreateFixture(int width, int height)
    {
        // Do not call ImageLimits here: rejected cases must still contain the full actual buffer.
        byte[] pixels = new byte[checked(width * height * 4)];
        int horizontal = Math.Max(1, width - 1), vertical = Math.Max(1, height - 1);
        for (int y = 0; y < height; y++)
        {
            byte green = (byte)(y * 255 / vertical);
            int offset = checked(y * width * 4);
            for (int x = 0; x < width; x++)
            {
                pixels[offset++] = (byte)(x * 255 / horizontal);
                pixels[offset++] = green;
                pixels[offset++] = (byte)((x + y) & 255);
                pixels[offset++] = (byte)((x + 3 * y) & 255);
            }
        }
        return new(width, height, pixels);
    }

    private static void AssertPixels(ImageData expected, ImageData actual)
        => Check.That(actual.Width == expected.Width && actual.Height == expected.Height &&
            actual.Bgra.AsSpan().SequenceEqual(expected.Bgra), "Dimensions or full straight BGRA pixels changed; resizing/alpha changes are not accepted.");

    private static void AssertOnePng(string folder, string expected)
    {
        string[] entries = Directory.GetFileSystemEntries(folder);
        Check.That(entries.Length == 1 && string.Equals(entries[0], expected, StringComparison.OrdinalIgnoreCase) &&
            Path.GetExtension(expected).Equals(".png", StringComparison.OrdinalIgnoreCase), "Save left an unexpected file or directory.");
    }

    private static void AssertEmpty(string folder, string operation)
        => Check.That(!Directory.EnumerateFileSystemEntries(folder).Any(), operation + " left an output or temporary file.");

    private static object Percentiles(IEnumerable<double> values)
    {
        double[] ordered = values.Order().ToArray();
        Check.That(ordered.Length == 10, "Percentiles require all ten measured samples.");
        return new { p50 = ordered[(int)Math.Ceiling(0.50 * ordered.Length) - 1], p95 = ordered[(int)Math.Ceiling(0.95 * ordered.Length) - 1] };
    }

    private static void CheckBudget(Stopwatch elapsed, CancellationToken cancellation)
    {
        if (elapsed.Elapsed >= TimeSpan.FromSeconds(PerformanceBudgetSeconds) || cancellation.IsCancellationRequested)
            throw new TimeoutException("The 4K engine measurement exceeded its 90-second cooperative test budget; no complete performance result is claimed.");
    }

    private static void CollectReleasedFixtures()
    {
        GC.Collect(GC.MaxGeneration, GCCollectionMode.Forced, blocking: true, compacting: false);
        GC.WaitForPendingFinalizers();
        GC.Collect(GC.MaxGeneration, GCCollectionMode.Forced, blocking: true, compacting: false);
    }

    private static MemoryAvailability RequireMemory(string test)
    {
        if (!OperatingSystem.IsWindows() || RuntimeInformation.ProcessArchitecture != Architecture.X64)
            throw new TestUnavailableException("Actual boundary/performance fixtures require a Windows x64 process.");
        var native = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        if (!GlobalMemoryStatusEx(ref native))
            throw new TestUnavailableException("Available-memory preflight failed; native=" + Marshal.GetLastWin32Error() + ". No large fixture was allocated.");
        long gcLimit = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
        long live = GC.GetTotalMemory(false);
        var available = new MemoryAvailability(native.AvailablePhysical, native.AvailablePageFile, gcLimit, live);
        if (native.AvailablePhysical < (ulong)MinimumAvailableBytes || native.AvailablePageFile < (ulong)MinimumAvailableBytes ||
            gcLimit <= 0 || gcLimit - live < MinimumAvailableBytes)
        {
            observations.Add(new { test, status = "NOT RUN", minimumAvailableBytes = MinimumAvailableBytes, memory = available });
            throw new TestUnavailableException("Actual boundary/performance fixtures require 3 GiB available physical RAM, commit headroom and remaining GC memory budget. Prerequisite unavailable; not a passing test.");
        }
        return available;
    }

    private sealed record BoundaryObservation(int Width, int Height, long Pixels, long BgraBytes, bool ExpectedAccepted,
        string Outcome, long EncodedPngBytes, bool FullPixelsValidated, bool NoResize);
    private sealed record RoundTripSample(double SaveMilliseconds, double ReadMilliseconds, double RoundTripMilliseconds, long EncodedPngBytes);
    private sealed record MemoryAvailability(ulong AvailablePhysicalBytes, ulong AvailableCommitBytes, long GcReportedLimitBytes, long ManagedLiveBytes);

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatus
    {
        public uint Length, MemoryLoad;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
}
