using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using ImageCopySave.Engine;

namespace ImageCopySave.Tests;

public static class FileSystemIntegrationTests
{
    private static readonly List<object> observations = [];
    public static IReadOnlyList<object> Evidence => observations;
    private static readonly ImageData Pixel = new(2, 1, [9, 8, 7, 0, 6, 5, 4, 128]);

    public static void Register(Action<string, Action> test)
    {
        test("filesystem/actual-source-read-ACL-denial", ReadDenied);
        test("filesystem/actual-destination-write-ACL-denial", WriteDenied);
        test("filesystem/owned-VHD-real-disk-full", DiskFull);
    }

    private static void ReadDenied()
    {
        using var scope = new IntegrationFolder("acl-read");
        RequireNtfs(scope.Root);
        string path = Path.Combine(scope.Root, "source.png");
        byte[] original = ImageCodec.EncodePng(Pixel);
        File.WriteAllBytes(path, original);
        int? code;
        using (new DenyOwnAccess(path, false, FileSystemRights.ReadData))
        {
            // Confirm an actual OS denial, not a mock/injected exception or read-only attribute.
            Exception denied = Failure(() => { using var stream = File.OpenRead(path); });
            Check.That(IsAccessDenied(denied), "The test file ACL did not deny ordinary file reading.");
            Exception result = Failure(() => LocalPaths.ReadImage(path));
            Check.That(IsAccessDenied(result), "Engine did not reject the actual source ACL denial.");
            code = NativeCode(result);
            observations.Add(new { test = "actual-source-read-ACL-denial", phase = "denial-observed", ordinaryNativeCode = NativeCode(denied), engineNativeCode = code });
        }
        Check.That(File.ReadAllBytes(path).SequenceEqual(original), "Denied source changed.");
        Check.That(Directory.GetFileSystemEntries(scope.Root).Length == 1, "Source rejection created another file.");
        observations.Add(new { test = "actual-source-read-ACL-denial", nativeCode = code, aclRestored = true, sourceBytesUnchanged = true, clipboardAccess = false });
    }

    private static void WriteDenied()
    {
        using var scope = new IntegrationFolder("acl-write");
        RequireNtfs(scope.Root);
        string target = Path.Combine(scope.Root, "target"); Directory.CreateDirectory(target);
        string sentinel = Path.Combine(target, "existing.txt"); File.WriteAllText(sentinel, "owned sentinel");
        int? code;
        using (new DenyOwnAccess(target, true, FileSystemRights.CreateFiles | FileSystemRights.CreateDirectories))
        {
            string probe = Path.Combine(target, "denial-probe.tmp");
            Exception denied = Failure(() => { using var stream = new FileStream(probe, FileMode.CreateNew, FileAccess.Write); });
            Check.That(IsAccessDenied(denied), "The test directory ACL did not deny ordinary file creation.");
            Exception result = Failure(() => AtomicPngWriter.Save(Pixel, target));
            Check.That(IsAccessDenied(result), "Save did not reject the actual destination ACL denial.");
            code = NativeCode(result);
            observations.Add(new { test = "actual-destination-write-ACL-denial", phase = "denial-observed", ordinaryNativeCode = NativeCode(denied), engineNativeCode = code });
        }
        Check.That(File.ReadAllText(sentinel) == "owned sentinel", "Existing file changed during denied save.");
        Check.That(Directory.GetFiles(target).Length == 1 && Directory.GetDirectories(target).Length == 0,
            "Denied save left an incomplete final or temporary file.");
        observations.Add(new { test = "actual-destination-write-ACL-denial", nativeCode = code, aclRestored = true, existingFileUnchanged = true, incompleteFiles = 0, clipboardAccess = false });
    }

    private static void DiskFull()
    {
        RequireDisposableHostedRunner();
        using var host = new IntegrationFolder("vhd");
        var hostDrive = new DriveInfo(Path.GetPathRoot(host.Root)!);
        if (hostDrive.AvailableFreeSpace < 1024L * 1024 * 1024)
            throw new TestUnavailableException("Owned-VHD preflight requires at least 1 GiB free on its host volume.");
        using var disk = OwnedVhd.Create(host);
        disk.VerifyIdentity();
        string area = Path.Combine(disk.Root, "ImageCopySave-" + Guid.NewGuid().ToString("N"));
        string target = Path.Combine(area, "save-target"); Directory.CreateDirectory(target);
        string sentinel = Path.Combine(target, "existing.txt"); File.WriteAllText(sentinel, "owned disk-full sentinel");
        string filler = Path.Combine(area, "owned-filler.bin");
        try
        {
            disk.VerifyIdentity();
            // All allocation is confined to the verified owned volume and capped at its 128 MiB disk size.
            long filled = 0; int? fillCode = null; byte[] block = new byte[64 * 1024];
            new Random(1977).NextBytes(block);
            using (var output = new FileStream(filler, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1, FileOptions.WriteThrough))
            {
                for (int attempt = 0; attempt < 32768 && filled < 128L * 1024 * 1024; attempt++)
                {
                    try { output.Write(block); filled += block.Length; }
                    catch (IOException ex) when (IsDiskFull(ex))
                    {
                        fillCode = NativeCode(ex);
                        if (block.Length > 4096) { block = new byte[4096]; continue; }
                        break;
                    }
                }
                // Writes above are actual allocated data, not a sparse SetLength reservation.
            }
            Check.That(fillCode is 112 or 39, "Filler did not reach a real filesystem disk-full error within its 128 MiB cap.");
            disk.VerifyIdentity();
            long freeBeforeSave = new DriveInfo(disk.Root).AvailableFreeSpace;
            Check.That(freeBeforeSave < 1024 * 1024, "The isolated volume is not sufficiently full to exercise the save.");
            byte[] pixels = new byte[1024 * 1024 * 4]; new Random(331).NextBytes(pixels);
            var image = new ImageData(1024, 1024, pixels);
            int encodedPngBytes = ImageCodec.EncodePng(image).Length;
            Check.That(encodedPngBytes > 1024 * 1024, "Disk-full fixture must exceed NTFS resident-file capacity and remaining space.");
            Exception failure = Failure(() => AtomicPngWriter.Save(image, target));
            Check.That(IsDiskFull(failure), "Save failed for a reason other than actual disk exhaustion; native=" + NativeCode(failure));
            Check.That(File.ReadAllText(sentinel) == "owned disk-full sentinel", "Existing file changed on full volume.");
            Check.That(Directory.GetFiles(target).Length == 1, "Full-volume save left a temporary or incomplete final PNG.");
            observations.Add(new { test = "owned-VHD-real-disk-full", volumeBytes = disk.VolumeBytes, diskBytes = 128L * 1024 * 1024,
                fillCode, saveNativeCode = NativeCode(failure), filledBytes = filled, freeBeforeSave, encodedPngBytes,
                ownImageIdentityVerified = true, systemVolume = false, incompleteFiles = 0, clipboardAccess = false });
        }
        finally
        {
            // Recheck the mount before pathname cleanup; detach still runs if this identity check fails.
            disk.VerifyIdentity();
            // Free our filler before deleting our test directory; no other volume content is touched.
            File.Delete(filler);
            string resolved = Path.GetFullPath(area);
            if (!resolved.StartsWith(disk.Root, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(resolved).StartsWith("ImageCopySave-", StringComparison.Ordinal))
                throw new IOException("Unsafe owned-volume cleanup path.");
            Directory.Delete(resolved, true);
        }
    }

    private static void RequireDisposableHostedRunner()
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("IMAGE_COPY_SAVE_TEST_ISOLATED_FS") != "1" ||
            !string.Equals(Environment.GetEnvironmentVariable("GITHUB_ACTIONS"), "true", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT"), "github-hosted", StringComparison.OrdinalIgnoreCase))
            throw new TestUnavailableException("Real disk-full test requires explicit opt-in on a disposable GitHub-hosted Windows runner; no local/system volume is used.");
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
            throw new TestUnavailableException("Creating and mounting the test-owned VHD requires an administrator in the disposable runner.");
    }

    private static void RequireNtfs(string path)
    {
        if (!OperatingSystem.IsWindows() || !new DriveInfo(Path.GetPathRoot(path)!).DriveFormat.Equals("NTFS", StringComparison.OrdinalIgnoreCase))
            throw new TestUnavailableException("Actual ACL denial test requires a test-owned directory on Windows NTFS.");
    }
    private static Exception Failure(Action action)
    {
        try { action(); }
        catch (Exception exception) { return exception; }
        throw new Exception("The operation unexpectedly succeeded; no denial was observed.");
    }
    private static bool IsAccessDenied(Exception error) => error is UnauthorizedAccessException || NativeCode(error) == 5;
    private static bool IsDiskFull(Exception error) => NativeCode(error) is 112 or 39;
    private static int? NativeCode(Exception error)
    {
        for (Exception? current = error; current != null; current = current.InnerException)
        {
            if (current is Win32Exception native) return native.NativeErrorCode;
            if ((unchecked((uint)current.HResult) & 0xffff0000u) == 0x80070000u) return current.HResult & 0xffff;
        }
        return null;
    }

    private sealed class DenyOwnAccess : IDisposable
    {
        private readonly FileSystemInfo target;
        private readonly FileSystemSecurity original;
        private readonly byte[] originalDescriptor;
        private readonly string originalSddl;
        private readonly SecurityIdentifier user;
        private readonly int denialMask;
        private byte[]? appliedDescriptor;
        private bool changed;
        public DenyOwnAccess(string path, bool directory, FileSystemRights rights)
        {
            target = directory ? new DirectoryInfo(path) : new FileInfo(path);
            original = ReadAcl();
            originalDescriptor = original.GetSecurityDescriptorBinaryForm();
            originalSddl = original.GetSecurityDescriptorSddlForm(AccessControlSections.Access);
            denialMask = (int)rights;
            FileSystemSecurity denied = directory ? new DirectorySecurity() : new FileSecurity();
            denied.SetSecurityDescriptorBinaryForm(originalDescriptor, AccessControlSections.Access);
            using var identity = WindowsIdentity.GetCurrent();
            user = identity.User ?? throw new TestUnavailableException("Current user SID is unavailable for a test-owned ACL.");
            denied.AddAccessRule(new FileSystemAccessRule(user, rights, InheritanceFlags.None, PropagationFlags.None, AccessControlType.Deny));
            try
            {
                Apply(denied); changed = true;
            }
            catch (UnauthorizedAccessException) { throw new TestUnavailableException("The runner cannot change an ACL on its own new test fixture."); }
            catch (PlatformNotSupportedException) { throw new TestUnavailableException("The filesystem does not expose ACL support for its new test fixture."); }
            try { appliedDescriptor = ReadAcl().GetSecurityDescriptorBinaryForm(); }
            catch
            {
                // An inspection failure must not strand the temporary deny during construction.
                Restore();
                throw;
            }
        }
        private FileSystemSecurity ReadAcl() => target is DirectoryInfo directory
            ? directory.GetAccessControl(AccessControlSections.Access)
            : ((FileInfo)target).GetAccessControl(AccessControlSections.Access);
        private void Apply(FileSystemSecurity security)
        {
            if (target is DirectoryInfo directory) directory.SetAccessControl((DirectorySecurity)security);
            else ((FileInfo)target).SetAccessControl((FileSecurity)security);
        }
        private void Restore()
        {
            // SetAccessControl persists only changed sections. Restore the untouched snapshot
            // explicitly as a changed DACL; never change owner, group, or auditing sections.
            original.SetSecurityDescriptorBinaryForm(originalDescriptor, AccessControlSections.Access);
            Apply(original); changed = false;
        }
        public void Dispose()
        {
            if (!changed) return;
            Restore();
            FileSystemSecurity restored = ReadAcl();
            var before = new RawSecurityDescriptor(originalDescriptor, 0);
            var applied = new RawSecurityDescriptor(appliedDescriptor!, 0);
            var after = new RawSecurityDescriptor(restored.GetSecurityDescriptorBinaryForm(), 0);
            byte[][] beforeAces = AceBytes(before.DiscretionaryAcl), afterAces = AceBytes(after.DiscretionaryAcl);
            bool sequenceEqual = beforeAces.Length == afterAces.Length && beforeAces.Zip(afterAces).All(pair => pair.First.SequenceEqual(pair.Second));
            bool multisetEqual = beforeAces.Select(Convert.ToHexString).Order(StringComparer.Ordinal)
                .SequenceEqual(afterAces.Select(Convert.ToHexString).Order(StringComparer.Ordinal));
            bool exactSddl = restored.GetSecurityDescriptorSddlForm(AccessControlSections.Access) == originalSddl;
            bool nullStateEqual = (before.DiscretionaryAcl == null) == (after.DiscretionaryAcl == null);
            bool aclRevisionEqual = before.DiscretionaryAcl?.Revision == after.DiscretionaryAcl?.Revision;
            const ControlFlags automaticInheritance = ControlFlags.DiscretionaryAclAutoInherited;
            bool automaticInheritanceAdded = (before.ControlFlags & automaticInheritance) == 0 &&
                after.ControlFlags == (before.ControlFlags | automaticInheritance);
            bool controlFlagsAllowed = before.ControlFlags == after.ControlFlags || automaticInheritanceAdded;
            bool ownDenyRestored = OwnDenyCount(before.DiscretionaryAcl) == OwnDenyCount(after.DiscretionaryAcl);
            var probe = ProbeRestoredAccess();
            var identities = new Dictionary<SecurityIdentifier, int>();
            observations.Add(new
            {
                test = target is DirectoryInfo ? "actual-destination-write-ACL-denial" : "actual-source-read-ACL-denial",
                phase = "restoration-diagnostic", exactSddlEqual = exactSddl,
                aceSequenceEqual = sequenceEqual, aceMultisetEqual = multisetEqual,
                aclNullStateEqual = nullStateEqual, aclRevisionEqual, controlFlagsAllowed, automaticInheritanceAdded,
                restorationCriterion = "ordered ACE bytes and ACL null/revision exact; flags exact or AUTO_INHERITED 0-to-1 only; own deny and effective access restored",
                controlFlagsDelta = (int)(before.ControlFlags ^ after.ControlFlags),
                original = AclShape(before, identities), denied = AclShape(applied, identities), restored = AclShape(after, identities),
                originalOwnExplicitDenyCount = OwnDenyCount(before.DiscretionaryAcl),
                appliedOwnExplicitDenyCount = OwnDenyCount(applied.DiscretionaryAcl),
                restoredOwnExplicitDenyCount = OwnDenyCount(after.DiscretionaryAcl),
                ownAddedDenyAbsent = ownDenyRestored,
                effectiveAccessRestored = probe.Success, effectiveAccessNativeCode = probe.NativeCode,
                effectiveAccessProbe = target is DirectoryInfo ? "create-write-flush-delete-owned-file" : "open-read-owned-source",
                sidValuesIncluded = false, pathsIncluded = false
            });
            // SetSecurityInfo can add AUTO_INHERITED when converting to the current inheritance
            // model. Keep exactSddlEqual visible and allow only that documented 0-to-1 change.
            // https://learn.microsoft.com/en-us/windows/win32/secauthz/automatic-propagation-of-inheritable-aces
            Check.That(sequenceEqual, "Original test ACE bytes or ordering were not restored.");
            Check.That(nullStateEqual && aclRevisionEqual, "Original test ACL null state or revision changed.");
            Check.That(controlFlagsAllowed, "Unexpected ACL control flag change after restoration.");
            Check.That(ownDenyRestored, "Temporary test deny remains after restoration.");
            Check.That(probe.Success, "Actual access did not recover after restoring the test ACL.");
        }
        private (bool Success, int? NativeCode) ProbeRestoredAccess()
        {
            string? probe = null; bool created = false;
            try
            {
                if (target is DirectoryInfo)
                {
                    probe = Path.Combine(target.FullName, ".acl-restored-" + Guid.NewGuid().ToString("N") + ".tmp");
                    using var output = new FileStream(probe, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                    created = true; output.WriteByte(0x51); output.Flush(true);
                }
                else
                {
                    using var input = File.OpenRead(target.FullName);
                    Check.That(input.ReadByte() >= 0, "Owned source became empty during ACL restoration.");
                }
                return (true, null);
            }
            catch (Exception error) { return (false, FileSystemIntegrationTests.NativeCode(error)); }
            finally { if (created) File.Delete(probe!); }
        }
        private int OwnDenyCount(RawAcl? acl) => acl == null ? 0 : acl.Cast<GenericAce>().Count(ace =>
            ace is KnownAce known && ace.AceType == AceType.AccessDenied &&
            (ace.AceFlags & AceFlags.Inherited) == 0 && known.SecurityIdentifier.Equals(user) && (known.AccessMask & denialMask) != 0);
        private static byte[][] AceBytes(RawAcl? acl) => acl == null ? [] : acl.Cast<GenericAce>().Select(ace =>
        {
            byte[] bytes = new byte[ace.BinaryLength]; ace.GetBinaryForm(bytes, 0); return bytes;
        }).ToArray();
        private object AclShape(RawSecurityDescriptor descriptor, Dictionary<SecurityIdentifier, int> identities)
        {
            RawAcl? acl = descriptor.DiscretionaryAcl;
            var entries = new List<object>();
            if (acl != null)
            {
                foreach (GenericAce ace in acl.Cast<GenericAce>().Take(64))
                {
                    int? sidOrdinal = null, accessMask = null; bool currentUser = false;
                    if (ace is KnownAce known)
                    {
                        if (!identities.TryGetValue(known.SecurityIdentifier, out int ordinal))
                        { ordinal = identities.Count; identities.Add(known.SecurityIdentifier, ordinal); }
                        sidOrdinal = ordinal; accessMask = known.AccessMask; currentUser = known.SecurityIdentifier.Equals(user);
                    }
                    entries.Add(new { type = (int)ace.AceType, flags = (int)ace.AceFlags, accessMask, sidOrdinal, currentUser });
                }
            }
            return new { controlFlags = (int)descriptor.ControlFlags, controlFlagNames = descriptor.ControlFlags.ToString(),
                daclPresent = (descriptor.ControlFlags & ControlFlags.DiscretionaryAclPresent) != 0,
                protectedDacl = (descriptor.ControlFlags & ControlFlags.DiscretionaryAclProtected) != 0,
                aclIsNull = acl == null, aclRevision = acl?.Revision, aceCount = acl?.Count ?? 0, entriesTruncated = acl != null && acl.Count > 64, entries };
        }
    }

    private sealed class OwnedVhd : IDisposable
    {
        private readonly IntegrationFolder host;
        private readonly string image, label, detachScript;
        private readonly string volumeIdentity;
        private bool attached = true;
        public string Root { get; }
        public long VolumeBytes { get; }
        private OwnedVhd(IntegrationFolder host, string image, string label, string detachScript, string root, string identity, long bytes)
        { this.host = host; this.image = image; this.label = label; this.detachScript = detachScript; Root = root; volumeIdentity = identity; VolumeBytes = bytes; }

        public static OwnedVhd Create(IntegrationFolder host)
        {
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            string diskpart = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "diskpart.exe");
            if (!File.Exists(powershell) || !File.Exists(diskpart)) throw new TestUnavailableException("Windows Storage tools are unavailable for the owned-VHD preflight.");
            string image = Path.Combine(host.Root, "owned-" + Guid.NewGuid().ToString("N") + ".vhd");
            if (image.Any(c => c > 127 || c is '"' or '\r' or '\n')) throw new TestUnavailableException("DiskPart test-image path is not safely representable in its bounded ASCII input script.");
            string probe = Path.Combine(host.Root, "preflight.ps1");
            File.WriteAllText(probe, "$ErrorActionPreference='Stop'; foreach($name in @('Mount-DiskImage','Get-DiskImage','Get-Disk','Initialize-Disk','New-Partition','Format-Volume','Get-Volume','Dismount-DiskImage')) { $null=Get-Command $name -ErrorAction Stop }; 'READY'");
            var capability = Run(powershell, ["-NoProfile", "-NonInteractive", "-File", probe], 30000);
            if (capability.Code != 0 || !capability.Output.Contains("READY", StringComparison.Ordinal))
                throw new TestUnavailableException("Storage cmdlet capability preflight failed; no disk was created or mounted.");
            string createScript = Path.Combine(host.Root, "create-vhd.txt");
            File.WriteAllText(createScript, "create vdisk file=\"" + image + "\" maximum=128 type=fixed\r\nexit\r\n", Encoding.ASCII);
            string mountScript = Path.Combine(host.Root, "mount-owned-vhd.ps1"); File.WriteAllText(mountScript, MountScript);
            string detachScript = Path.Combine(host.Root, "detach-owned-vhd.ps1"); File.WriteAllText(detachScript, DetachScript);
            string label = "ICS" + Guid.NewGuid().ToString("N")[..16];
            try
            {
                var created = Run(diskpart, ["/s", createScript], 60000);
                if (created.Code != 0 || !File.Exists(image) || new FileInfo(image).Length > 129L * 1024 * 1024)
                    throw new TestUnavailableException("The bounded 128 MiB VHD could not be created by the runner.");
                var mounted = Run(powershell, ["-NoProfile", "-NonInteractive", "-File", mountScript, "-ImagePath", image, "-Label", label], 60000);
                if (mounted.Code != 0)
                {
                    string stage = mounted.Output.Trim();
                    string[] knownStages = ["UNAVAILABLE:mount-owned-image", "UNAVAILABLE:verify-owned-disk", "UNAVAILABLE:initialize-owned-disk", "UNAVAILABLE:partition-owned-disk", "UNAVAILABLE:format-owned-volume", "UNAVAILABLE:verify-owned-volume"];
                    string detail = knownStages.Contains(stage) ? stage : "UNAVAILABLE:owned-image-setup";
                    throw new TestUnavailableException("Owned-VHD preflight " + detail + "; cleanup targets only its own image.");
                }
                using JsonDocument json = JsonDocument.Parse(mounted.Output.Trim());
                string root = json.RootElement.GetProperty("root").GetString()!;
                string identity = json.RootElement.GetProperty("identity").GetString()!;
                long bytes = json.RootElement.GetProperty("bytes").GetInt64();
                var disk = new OwnedVhd(host, image, label, detachScript, root, identity, bytes);
                disk.VerifyIdentity();
                return disk;
            }
            catch
            {
                if (File.Exists(image)) Detach(host, powershell, detachScript, image);
                throw;
            }
        }

        public void VerifyIdentity()
        {
            Check.That(Root.Length == 3 && char.IsAsciiLetter(Root[0]) && Root[1] == ':' && Root[2] == '\\', "Unexpected owned volume root.");
            Check.That(!Root.Equals(Path.GetPathRoot(host.Root), StringComparison.OrdinalIgnoreCase) &&
                !Root.Equals(Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)), StringComparison.OrdinalIgnoreCase), "Owned volume unexpectedly aliases a host/system drive.");
            var name = new StringBuilder(128);
            Check.That(GetVolumeNameForVolumeMountPoint(Root, name, name.Capacity) && name.ToString().Equals(volumeIdentity, StringComparison.OrdinalIgnoreCase), "Owned VHD mount-point identity changed.");
            var drive = new DriveInfo(Root);
            Check.That(drive.IsReady && drive.DriveType == DriveType.Fixed && drive.DriveFormat == "NTFS" && drive.VolumeLabel == label &&
                drive.TotalSize == VolumeBytes && VolumeBytes > 0 && VolumeBytes <= 128L * 1024 * 1024, "Owned VHD size/filesystem/label does not match its verified creation.");
        }
        public void Dispose()
        {
            if (!attached) return;
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            Detach(host, powershell, detachScript, image); attached = false;
            observations.Add(new { test = "owned-VHD-cleanup", detached = true, ownedImageOnly = true });
        }
        private static void Detach(IntegrationFolder host, string powershell, string script, string image)
        {
            try
            {
                var result = Run(powershell, ["-NoProfile", "-NonInteractive", "-File", script, "-ImagePath", image], 30000);
                if (result.Code != 0 || !result.Output.Contains("DETACHED", StringComparison.Ordinal))
                    throw new IOException("Detachment of the owned test VHD could not be verified; its image was preserved.");
            }
            catch { host.Preserve = true; throw; }
        }
        private static (int Code, string Output) Run(string executable, string[] arguments, int timeout)
        {
            var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (string argument in arguments) start.ArgumentList.Add(argument);
            using Process process = Process.Start(start) ?? throw new IOException("Unable to start owned-volume capability operation.");
            Task<string> output = process.StandardOutput.ReadToEndAsync(), error = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(timeout))
            {
                process.Kill(entireProcessTree: true);
                if (!process.WaitForExit(5000)) throw new IOException("Owned-volume tool could not be stopped.");
                throw new TestUnavailableException("Owned-volume capability operation exceeded its deadline.");
            }
            Task.WhenAll(output, error).GetAwaiter().GetResult();
            // Scripts/tool diagnostics stay out of test JSON: they may include generated local paths.
            return (process.ExitCode, output.Result);
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetVolumeNameForVolumeMountPoint(string root, StringBuilder name, int length);

        private const string MountScript = """
param([Parameter(Mandatory=$true)][string]$ImagePath,[Parameter(Mandatory=$true)][string]$Label)
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
$stage='mount-owned-image'
try {
    $resolved=(Resolve-Path -LiteralPath $ImagePath).ProviderPath
    $image=Mount-DiskImage -ImagePath $resolved -StorageType VHD -Access ReadWrite -NoDriveLetter -PassThru
    $stage='verify-owned-disk'
    $disk=@($image | Get-Disk)
    if($disk.Count -ne 1 -or $disk[0].IsBoot -or $disk[0].IsSystem -or $disk[0].Size -ne 128MB -or $disk[0].PartitionStyle -ne 'RAW') { throw 'Owned-image disk identity was not safe to initialize' }
    $number=$disk[0].Number
    $again=@(Get-DiskImage -ImagePath $resolved | Get-Disk)
    if($again.Count -ne 1 -or $again[0].Number -ne $number) { throw 'Image-to-disk identity changed' }
    $stage='initialize-owned-disk'
    Initialize-Disk -Number $number -PartitionStyle GPT | Out-Null
    $stage='partition-owned-disk'
    $partition=New-Partition -DiskNumber $number -UseMaximumSize -AssignDriveLetter
    $stage='format-owned-volume'
    $partition | Format-Volume -FileSystem NTFS -NewFileSystemLabel $Label -Confirm:$false -Force | Out-Null
    $stage='verify-owned-volume'
    $volume=$partition | Get-Volume
    $drive=[string]$volume.DriveLetter
    if($drive.Length -ne 1 -or $volume.Size -gt 128MB -or $volume.FileSystemLabel -ne $Label -or $drive -eq $env:SystemDrive.Substring(0,1)) { throw 'Owned-volume mount identity was not safe' }
    @{root=($drive+':\');identity=$volume.Path;bytes=[long]$volume.Size} | ConvertTo-Json -Compress
} catch { Write-Output ('UNAVAILABLE:'+$stage); exit 71 }
""";
        private const string DetachScript = """
param([Parameter(Mandatory=$true)][string]$ImagePath)
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
try {
    $image=Get-DiskImage -ImagePath $ImagePath
    if($image.Attached) { Dismount-DiskImage -ImagePath $ImagePath }
    if((Get-DiskImage -ImagePath $ImagePath).Attached) { throw 'Owned image remains attached' }
    'DETACHED'
} catch { exit 72 }
""";
    }
}

internal sealed class IntegrationFolder : IDisposable
{
    private readonly string allowed = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
    public string Root { get; }
    public bool Preserve { get; set; }
    public IntegrationFolder(string purpose)
    {
        Root = Path.Combine(allowed, "ImageCopySave-integration-" + purpose + "-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Root);
    }
    public void Dispose()
    {
        if (Preserve) return;
        string resolved = Path.GetFullPath(Root);
        if (!resolved.StartsWith(allowed, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(resolved).StartsWith("ImageCopySave-integration-", StringComparison.Ordinal) ||
            File.GetAttributes(resolved).HasFlag(FileAttributes.ReparsePoint))
            throw new IOException("Unsafe owned integration fixture cleanup path.");
        Directory.Delete(resolved, true);
    }
}
