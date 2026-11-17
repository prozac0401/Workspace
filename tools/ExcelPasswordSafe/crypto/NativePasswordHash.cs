using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;

namespace ExcelPasswordSafe.Crypto {
    // Windows' SHA implementation only. The Office Agile input order and spin
    // count are identical to the pinned codec's legacy loop. No state survives
    // this derivation. Its caller owns and clears the returned digest.
    internal static class NativePasswordHash {
        private const uint ReusableHash = 0x20;

        internal static byte[] Derive(byte[] initialInput, int spinCount,
            string hashName, CancellationToken cancellationToken) {
            byte[]? digest = null, iterationInput = null, result = null;
            NativeAlgorithmHandle? algorithm = null;
            NativeHashHandle? hash = null;
            IntPtr objectBuffer = IntPtr.Zero;
            int objectLength = 0;
            try {
                if (initialInput == null) throw new ArgumentNullException(nameof(initialInput));
                if (spinCount < 0) throw new ArgumentOutOfRangeException(nameof(spinCount));
                cancellationToken.ThrowIfCancellationRequested();
                string name = (hashName ?? "").Replace("-", "").ToUpperInvariant();
                int digestLength;
                switch (name) {
                    case "SHA1": digestLength = 20; break;
                    case "SHA256": digestLength = 32; break;
                    case "SHA384": digestLength = 48; break;
                    case "SHA512": digestLength = 64; break;
                    default: throw new NotSupportedException("Unsupported password hash algorithm.");
                }

                // Allocate the managed owner before the native call succeeds;
                // no allocating constructor can strand a returned native handle.
                algorithm = new NativeAlgorithmHandle();
                IntPtr algorithmPointer;
                int status = NativeHashApi.OpenAlgorithm(out algorithmPointer, name,
                    "Microsoft Primitive Provider", ReusableHash);
                algorithm.SetNativeHandle(algorithmPointer);
                Check(status);
                if (algorithm == null || algorithm.IsInvalid) throw new CryptographicException("Invalid hash provider handle.");
                int returned, actualDigestLength;
                Check(NativeHashApi.GetProperty(algorithm.DangerousGetHandle(), "ObjectLength",
                    out objectLength, sizeof(int), out returned, 0));
                if (returned != sizeof(int) || objectLength <= 0 || objectLength > 1024 * 1024)
                    throw new CryptographicException("Invalid hash object length.");
                Check(NativeHashApi.GetProperty(algorithm.DangerousGetHandle(), "HashDigestLength",
                    out actualDigestLength, sizeof(int), out returned, 0));
                if (returned != sizeof(int) || actualDigestLength != digestLength)
                    throw new CryptographicException("Invalid password hash length.");

                // BCrypt retains this address until DestroyHash. It is unmanaged
                // storage, never a temporary marshalled address of a movable array.
                objectBuffer = Marshal.AllocHGlobal(objectLength);
                ZeroNative(objectBuffer, objectLength);
                hash = new NativeHashHandle(objectBuffer, objectLength);
                objectBuffer = IntPtr.Zero;
                IntPtr hashPointer;
                status = NativeHashApi.CreateHash(algorithm.DangerousGetHandle(), out hashPointer,
                    hash.ObjectBuffer, objectLength, IntPtr.Zero, 0, ReusableHash);
                hash.SetNativeHandle(hashPointer);
                Check(status);
                if (!hash.HasNativeHash) throw new CryptographicException("Invalid hash handle.");

                digest = new byte[digestLength];
                iterationInput = new byte[sizeof(uint) + digestLength];
                HashInto(hash, initialInput, digest);
                for (uint iteration = 0; iteration < spinCount; iteration++) {
                    if ((iteration & 1023U) == 0U) cancellationToken.ThrowIfCancellationRequested();
                    iterationInput[0] = (byte)iteration;
                    iterationInput[1] = (byte)(iteration >> 8);
                    iterationInput[2] = (byte)(iteration >> 16);
                    iterationInput[3] = (byte)(iteration >> 24);
                    Buffer.BlockCopy(digest, 0, iterationInput, sizeof(uint), digest.Length);
                    HashInto(hash, iterationInput, digest);
                }
                cancellationToken.ThrowIfCancellationRequested();
                result = digest;
                digest = null;
            } finally {
                // initialInput is an operation-local copy made by the pinned
                // caller. Consume it here; the caller also clears it in finally.
                Clear(initialInput); Clear(digest); Clear(iterationInput);
                Exception? cleanupFailure = null;
                try {
                    if (hash != null) hash.CloseChecked();
                    else if (objectBuffer != IntPtr.Zero) {
                        ZeroNative(objectBuffer, objectLength);
                        Marshal.FreeHGlobal(objectBuffer);
                    }
                } catch (Exception error) { cleanupFailure = error; }
                try { if (algorithm != null) algorithm.CloseChecked(); }
                catch (Exception error) { if (cleanupFailure == null) cleanupFailure = error; }
                if (cleanupFailure != null) {
                    Clear(result);
                    throw new CryptographicException("Password hash cleanup failed.", cleanupFailure);
                }
            }
            return result ?? throw new CryptographicException("Password hash produced no result.");
        }

        private static void HashInto(NativeHashHandle hash, byte[] input, byte[] output) {
            Check(NativeHashApi.HashData(hash.DangerousGetHandle(), input, input.Length, 0));
            Check(NativeHashApi.FinishHash(hash.DangerousGetHandle(), output, output.Length, 0));
            GC.KeepAlive(hash);
        }
        private static void Clear(byte[]? bytes) { if (bytes != null) Array.Clear(bytes, 0, bytes.Length); }
        private static void Check(int status) {
            if (status < 0) throw new CryptographicException("Windows password hash failed (" + status.ToString("X8") + ").");
        }
        private static void ZeroNative(IntPtr pointer, int length) {
            // No secret managed copy or unpinned native object is introduced.
            for (int offset = 0; offset < length; offset++) Marshal.WriteByte(pointer, offset, 0);
        }

        private sealed class NativeAlgorithmHandle : SafeHandleZeroOrMinusOneIsInvalid {
            private int releaseStatus;
            internal NativeAlgorithmHandle() : base(true) { }
            internal void SetNativeHandle(IntPtr value) { SetHandle(value); }
            protected override bool ReleaseHandle() {
                try { releaseStatus = NativeHashApi.CloseAlgorithm(handle, 0); }
                catch { releaseStatus = unchecked((int)0xC0000001); }
                return releaseStatus >= 0;
            }
            internal void CloseChecked() { Dispose(); Check(releaseStatus); }
        }
        private sealed class NativeHashHandle : SafeHandle {
            private IntPtr objectBuffer;
            private readonly int objectLength;
            private int releaseStatus;
            internal NativeHashHandle(IntPtr buffer, int length) : base(IntPtr.Zero, true) {
                objectBuffer = buffer; objectLength = length;
            }
            internal IntPtr ObjectBuffer { get { return objectBuffer; } }
            internal bool HasNativeHash { get { return handle != IntPtr.Zero && handle != new IntPtr(-1); } }
            // Before CreateHash succeeds the owner still owns its native buffer,
            // so SafeHandle must invoke ReleaseHandle even without a hash handle.
            public override bool IsInvalid { get { return !HasNativeHash && objectBuffer == IntPtr.Zero; } }
            internal void SetNativeHandle(IntPtr value) { SetHandle(value); }
            protected override bool ReleaseHandle() {
                try { if (HasNativeHash) releaseStatus = NativeHashApi.DestroyHash(handle); }
                catch { releaseStatus = unchecked((int)0xC0000001); }
                if (objectBuffer != IntPtr.Zero) {
                    ZeroNative(objectBuffer, objectLength);
                    // A failed DestroyHash leaves ownership uncertain. Retain
                    // the zeroed allocation until process exit rather than free
                    // memory still referenced by a native handle. CloseChecked
                    // fails the operation; no verified output can be returned.
                    if (releaseStatus >= 0) Marshal.FreeHGlobal(objectBuffer);
                    objectBuffer = IntPtr.Zero;
                }
                return releaseStatus >= 0;
            }
            internal void CloseChecked() { Dispose(); Check(releaseStatus); }
        }
    }
}
