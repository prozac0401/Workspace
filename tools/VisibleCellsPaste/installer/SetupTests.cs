using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Xml.Linq;
using VisibleCellsPaste.Installation;

internal static class SetupTests
{
    private static int count;
    private static void Check(bool pass, string name) { if (!pass) throw new Exception(name); count++; Console.WriteLine("PASS " + name); }
    private static void Reject(Action action, string name) { try { action(); } catch { Check(true, name); return; } throw new Exception("Expected rejection: " + name); }
    private static object Private(string name, params object[] args) { return typeof(Setup).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Static).Invoke(null, args); }
    private static void CheckClrCodeBase(string basePath, string folder)
    {
        string directory = Setup.SafePath(basePath, folder);
        Directory.CreateDirectory(directory);
        string fileName = "fixture%20#한글's.dll";
        string file = Setup.SafePath(directory, fileName);
        var name = new AssemblyName("VcpCodeBaseFixture" + Guid.NewGuid().ToString("N"));
        var assembly = AppDomain.CurrentDomain.DefineDynamicAssembly(name, System.Reflection.Emit.AssemblyBuilderAccess.Save, directory);
        var module = assembly.DefineDynamicModule(name.Name, fileName);
        var type = module.DefineType("VcpPathMarker", TypeAttributes.Public);
        var method = type.DefineMethod("Value", MethodAttributes.Public | MethodAttributes.Static, typeof(int), Type.EmptyTypes);
        var il = method.GetILGenerator(); il.Emit(System.Reflection.Emit.OpCodes.Ldc_I4, 137); il.Emit(System.Reflection.Emit.OpCodes.Ret);
        type.CreateType(); assembly.Save(fileName);
        AppDomain isolated = null;
        try
        {
            isolated = AppDomain.CreateDomain("VcpPathLoad-" + Guid.NewGuid().ToString("N"));
            var probe = (SetupCodeBaseProbe)isolated.CreateInstanceAndUnwrap(typeof(SetupCodeBaseProbe).Assembly.FullName, typeof(SetupCodeBaseProbe).FullName);
            string codeBase = Setup.ClrCodeBase(file);
            string[] result = probe.Load(codeBase);
            Check(Setup.SamePath(result[0], file) && result[2] == "137", "CLR loads actual fixture at " + folder);
            Check(result[1] == codeBase, "CodeBase matches CLR canonical form at " + folder);
        }
        finally
        {
            if (isolated != null) AppDomain.Unload(isolated);
            if (File.Exists(file)) File.Delete(file);
            if (!Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
        }
    }
    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        string basePath = Path.GetFullPath(args.Length == 0 ? Path.Combine(Path.GetTempPath(), "VisibleCellsPaste-SetupTests-" + Guid.NewGuid().ToString("N")) : args[0]);
        Directory.CreateDirectory(basePath);
        try
        {
            Check(Setup.Identity != "Workspace.ExcelSelectionExport", "independent identity");
            Check(Setup.SafePath(basePath, @"한글 폴더\O'Brien\파일.dll").StartsWith(basePath + "\\", StringComparison.OrdinalIgnoreCase), "Korean spaces apostrophe paths");
            Reject(() => Setup.SafePath(basePath, @"..\outside.dll"), "relative traversal");
            Reject(() => Setup.SafePath(basePath, @"C:\outside.dll"), "absolute path");
            Reject(() => Setup.SafePath(basePath, "."), "root file target");
            Reject(() => Setup.ValidateRoot(Path.GetPathRoot(basePath)), "drive root");
            Check(Setup.SamePath(basePath.ToUpperInvariant(), basePath), "case insensitive Windows comparison");
            string sample = Path.Combine(basePath, "hash.txt"); File.WriteAllText(sample, "abc", new UTF8Encoding(false));
            Check(Setup.Hash(sample) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA256 known vector");
            Check(Private("LoadManifest", basePath) == null, "missing manifest");
            var manifest = new XDocument(new XElement("installation", new XAttribute("schema", "1"), new XAttribute("identity", Setup.Identity), new XAttribute("root", basePath), new XAttribute("architecture", "x64"), new XElement("files"), new XElement("registry")));
            string manifestFile = Path.Combine(basePath, Setup.ManifestName); manifest.Save(manifestFile);
            Check(Private("LoadManifest", basePath) != null, "valid minimal owned manifest");
            manifest.Root.SetAttributeValue("identity", "another product"); manifest.Save(manifestFile); Reject(() => Private("LoadManifest", basePath), "foreign manifest owner");
            manifest.Root.SetAttributeValue("identity", Setup.Identity); manifest.Root.SetAttributeValue("schema", "2"); manifest.Save(manifestFile); Reject(() => Private("LoadManifest", basePath), "unknown manifest schema");
            manifest.Root.SetAttributeValue("schema", "1"); manifest.Root.SetAttributeValue("architecture", "arm64"); manifest.Save(manifestFile); Reject(() => Private("LoadManifest", basePath), "unknown manifest architecture");
            manifest.Root.SetAttributeValue("architecture", "x64"); manifest.Root.Element("files").Add(new XElement("file", new XAttribute("path", "../business.txt"))); manifest.Save(manifestFile); Reject(() => Private("LoadManifest", basePath), "manifest file traversal");
            manifest.Root.Element("files").RemoveNodes(); manifest.Root.Element("registry").Add(new XElement("value", new XAttribute("key", @"Software\Microsoft\Office\16.0\Excel\Security"), new XAttribute("name", "VBAWarnings"), new XAttribute("kind", "DWord"), new XAttribute("data", "1"))); manifest.Save(manifestFile); Reject(() => Private("LoadManifest", basePath), "foreign registry entry");
            manifest.Root.Element("registry").RemoveNodes();
            string ownComRoot = @"Software\Classes\CLSID\" + Setup.Clsid + @"\InprocServer32\";
            foreach (string assemblyVersion in new[] { "0.1.0.0", Setup.AssemblyVersion })
            {
                manifest.Root.Element("registry").RemoveNodes();
                manifest.Root.Element("registry").Add(new XElement("value", new XAttribute("key", ownComRoot + assemblyVersion), new XAttribute("name", "Assembly"), new XAttribute("kind", "String"), new XAttribute("data", "VisibleCellsPaste.AddIn, Version=" + assemblyVersion + ", Culture=neutral, PublicKeyToken=null")));
                manifest.Save(manifestFile);
                Check(Private("LoadManifest", basePath) != null, "owned assembly manifest accepted " + assemblyVersion);
            }
            manifest.Root.Element("registry").Element("value").SetAttributeValue("key", ownComRoot + "0.1.2.0");
            manifest.Save(manifestFile); Reject(() => Private("LoadManifest", basePath), "unknown future assembly registry path");
            manifest.Root.Element("registry").Element("value").SetAttributeValue("key", @"Software\Classes\CLSID\{00000000-0000-0000-0000-000000000000}\InprocServer32\0.1.0.0");
            manifest.Save(manifestFile); Reject(() => Private("LoadManifest", basePath), "foreign previous-version COM registry path");
            object currentRegs = Private("Registration", basePath, Path.Combine(basePath, "new.dll"), "0.1.1");
            object priorRegs = Private("Registration", basePath, Path.Combine(basePath, "old.dll"), "0.1.0");
            foreach (object record in (System.Collections.IEnumerable)priorRegs)
            {
                var key = record.GetType().GetField("Key", BindingFlags.Instance | BindingFlags.NonPublic);
                var data = record.GetType().GetField("Value", BindingFlags.Instance | BindingFlags.NonPublic);
                key.SetValue(record, ((string)key.GetValue(record)).Replace(@"\InprocServer32\" + Setup.AssemblyVersion, @"\InprocServer32\0.1.0.0"));
                data.SetValue(record, ((string)data.GetValue(record)).Replace("Version=" + Setup.AssemblyVersion, "Version=0.1.0.0"));
            }
            var retained = ((System.Collections.Generic.IEnumerable<XElement>)Private("RegistryManifest", currentRegs, priorRegs)).ToArray();
            var priorVersion = retained.Where(x => ((string)x.Attribute("key")) == ownComRoot + "0.1.0.0").ToArray();
            Check(priorVersion.Length == 4 && (string)priorVersion.Single(x => (string)x.Attribute("name") == "Assembly").Attribute("data") == "VisibleCellsPaste.AddIn, Version=0.1.0.0, Culture=neutral, PublicKeyToken=null"
                && retained.Where(x => ((string)x.Attribute("key")) == ownComRoot + Setup.AssemblyVersion).Count() == 4
                && retained.Select(x => (string)x.Attribute("key") + "|" + (string)x.Attribute("name")).Distinct().Count() == retained.Length, "upgrade retains exact old version ownership without duplicate current records");
            manifest.Root.Element("registry").RemoveNodes();manifest.Root.Element("registry").Add(retained);manifest.Save(manifestFile);
            Check(Private("LoadManifest", basePath) != null, "merged upgrade manifest remains valid for removal");
            File.WriteAllText(manifestFile, "<!DOCTYPE x [<!ENTITY xxe SYSTEM 'file:///C:/Windows/win.ini'>]><installation>&xxe;</installation>"); Reject(() => Private("LoadManifest", basePath), "DTD external entity");
            foreach (string folder in new[] { "한글 경로's", "percent%20 space #한글's", "literal%2Fname", "literal#name" }) CheckClrCodeBase(basePath, folder);
            Console.WriteLine("PASS total=" + count); return 0;
        }
        catch (Exception e) { Console.WriteLine("FAIL " + e); return 1; }
        finally
        {
            // Delete only this test's two explicitly owned files; preserve unknown files.
            foreach (string name in new[] { "hash.txt", Setup.ManifestName }) { string file = Setup.SafePath(basePath, name); if (File.Exists(file)) File.Delete(file); }
            if (!Directory.EnumerateFileSystemEntries(basePath).Any()) Directory.Delete(basePath);
        }
    }
}

public sealed class SetupCodeBaseProbe : MarshalByRefObject
{
    public string[] Load(string codeBase)
    {
        Assembly assembly = Assembly.LoadFrom(codeBase);
        return new[] { assembly.Location, assembly.CodeBase, assembly.GetType("VcpPathMarker").GetMethod("Value").Invoke(null, null).ToString() };
    }
}
