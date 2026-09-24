using System;
using System.IO;
using System.Collections.Generic;
internal static class SetupProbeTests
{
    static int Main()
    {
        string directory = Path.Combine(Path.GetTempPath(), "SelectionExport-ProbeTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        int count = 0;
        try
        {
            Check(directory, "x86", Pe(0x014c, 64), "x86", ref count);
            Check(directory, "x64", Pe(0x8664, 64), "x64", ref count);
            Check(directory, "unsupported-machine", Pe(0xAA64, 64), "unknown", ref count);
            Check(directory, "short", new byte[63], "unknown", ref count);
            byte[] invalidMagic = Pe(0x8664, 64); invalidMagic[0] = 0;
            Check(directory, "invalid-mz", invalidMagic, "unknown", ref count);
            byte[] invalidSignature = Pe(0x8664, 64); invalidSignature[64] = 0;
            Check(directory, "invalid-pe", invalidSignature, "unknown", ref count);
            Check(directory, "negative-offset", Pe(0x8664, -1), "unknown", ref count);
            Check(directory, "past-end", Pe(0x8664, Int32.MaxValue), "unknown", ref count);
            Check(directory, "overlaps-header", Pe(0x8664, 20), "unknown", ref count);
            Assert(SetupProbe.OfficeRegistryVersion(16) == "16.0", "Excel 16 selects Office 16", ref count);
            Assert(SetupProbe.OfficeRegistryVersion(15) == "15.0", "Excel 15 selects Office 15", ref count);
            // Simulate stale policy entries with in-memory paths, never real registry writes.
            var stale15 = new HashSet<string>(SetupProbe.OfficePolicyRoots(15), StringComparer.OrdinalIgnoreCase);
            var stale16 = new HashSet<string>(SetupProbe.OfficePolicyRoots(16), StringComparer.OrdinalIgnoreCase);
            Assert(!AnyPolicySelected(16, stale15), "Excel 16 permitted despite stale Office 15 blocks", ref count);
            Assert(!AnyPolicySelected(15, stale16), "Excel 15 permitted despite stale Office 16 blocks", ref count);
            Assert(AnyPolicySelected(16, stale16), "Current Office 16 blocks remain selected", ref count);
            Assert(AnyPolicySelected(15, stale15), "Current Office 15 blocks remain selected", ref count);
            Assert(SetupProbe.DisabledItemsPath(16).IndexOf(@"\16.0\", StringComparison.Ordinal) >= 0 &&
                SetupProbe.DisabledItemsPath(16).IndexOf(@"\15.0\", StringComparison.Ordinal) < 0,
                "Excel 16 ignores Office 15 disabled-item residue", ref count);
            Assert(SetupProbe.DisabledItemsPath(15).IndexOf(@"\15.0\", StringComparison.Ordinal) >= 0 &&
                SetupProbe.DisabledItemsPath(15).IndexOf(@"\16.0\", StringComparison.Ordinal) < 0,
                "Excel 15 ignores Office 16 disabled-item residue", ref count);
            foreach (int unsupported in new[] { 0, 14, 17, Int32.MaxValue })
                RejectUnknownMajor(unsupported, ref count);
            Console.WriteLine("PASS: " + count + " deployment architecture/policy-scope tests");
            return 0;
        }
        finally
        {
            // Only names created by this test are removed, with no recursive deletion.
            foreach (string file in Directory.GetFiles(directory, "*.bin")) File.Delete(file);
            Directory.Delete(directory);
        }
    }
    static bool AnyPolicySelected(int major, HashSet<string> simulatedBlockedRoots)
    {
        foreach (string root in SetupProbe.OfficePolicyRoots(major))
            if (simulatedBlockedRoots.Contains(root)) return true;
        return false;
    }
    static void RejectUnknownMajor(int major, ref int count)
    {
        try { SetupProbe.OfficeRegistryVersion(major); }
        catch (InvalidOperationException ex)
        {
            Assert(ex.Message.IndexOf(major.ToString(), StringComparison.Ordinal) >= 0,
                "Unknown Excel major rejected with explicit diagnostic: " + major, ref count);
            return;
        }
        throw new Exception("Unknown Excel major was accepted: " + major);
    }
    static void Assert(bool condition, string name, ref int count)
    {
        if (!condition) throw new Exception(name);
        count++;
        Console.WriteLine("PASS " + name);
    }
    static byte[] Pe(ushort machine, int offset)
    {
        byte[] bytes = new byte[128];
        bytes[0] = 0x4D; bytes[1] = 0x5A;
        Array.Copy(BitConverter.GetBytes(offset), 0, bytes, 0x3C, 4);
        bytes[64] = 0x50; bytes[65] = 0x45;
        Array.Copy(BitConverter.GetBytes(machine), 0, bytes, 68, 2);
        return bytes;
    }
    static void Check(string directory, string name, byte[] bytes, string expected, ref int count)
    {
        string path = Path.Combine(directory, name + ".bin");
        File.WriteAllBytes(path, bytes);
        string actual = SetupProbe.ReadPeArchitecture(path);
        if (actual != expected) throw new Exception(name + ": expected " + expected + ", got " + actual);
        count++;
    }
}
