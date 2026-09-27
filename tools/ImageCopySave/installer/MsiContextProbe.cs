// Local feasibility probe; never used by the released helper or Explorer DLL.
using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Security.Principal;
using Windows.Management.Deployment;
using Windows.Foundation;

internal static class MsiContextProbe
{
    const string Name = "ImageCopySave.UnsignedSparseProbe";
    const string FullName = "ImageCopySave.UnsignedSparseProbe_0.1.1.0_x64__bys59z1khays2";
    const string Family = "ImageCopySave.UnsignedSparseProbe_bys59z1khays2";
    const string Publisher = "CN=ImageCopySave.UnsignedSparseProbe, OID.2.25.311729368913984317654407730594956997722=1";
    static DeploymentResult Wait(IAsyncOperationWithProgress<DeploymentResult, DeploymentProgress> operation)
    {
        try
        {
            while (operation.Status == AsyncStatus.Started) System.Threading.Thread.Sleep(50);
            if (operation.Status == AsyncStatus.Error) throw operation.ErrorCode;
            if (operation.Status == AsyncStatus.Canceled) throw new OperationCanceledException();
            return operation.GetResults();
        }
        finally { operation.Close(); }
    }
    static void Check(DeploymentResult result)
    {
        if (result.ExtendedErrorCode != null && result.ExtendedErrorCode.HResult != 0)
            throw new InvalidOperationException(result.ErrorText, result.ExtendedErrorCode);
    }
    static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--register-user")
        {
            using (var log = new StreamWriter(args[1], false, new System.Text.UTF8Encoding(false)))
            {
                try
                {
                    var identity = WindowsIdentity.GetCurrent();
                    bool elevated = new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
                    log.WriteLine("ELEVATED=" + elevated);
                    if (elevated || identity.IsSystem) throw new InvalidOperationException("Ordinary-user verification required.");
                    var deployment = new PackageManager();
                    Check(Wait(deployment.RegisterPackageByFamilyNameAsync(Family, new string[0], DeploymentOptions.None, null, new string[0])));
                    if (!deployment.FindPackagesForUser(identity.User.Value).Any(p => p.Id.FullName == FullName))
                        throw new InvalidOperationException("Expected current-user registration missing.");
                    log.WriteLine("REGISTER_USER=PASS");
                    return 0;
                }
                catch (Exception e) { log.WriteLine("REGISTER_USER=FAIL\n" + e); return 1; }
            }
        }
        if (args.Length != 4 && !(args.Length == 5 && args[4] == "wait")) return 64;
        bool attempted = false, passed = false, cleanup = false;
        var manager = new PackageManager();
        using (var log = new StreamWriter(args[3], false, new System.Text.UTF8Encoding(false)))
        {
            log.AutoFlush = true;
            log.WriteLine("START " + DateTime.UtcNow.ToString("o"));
            try
            {
                bool system = WindowsIdentity.GetCurrent().IsSystem;
                log.WriteLine("SYSTEM=" + system);
                if (!system) throw new InvalidOperationException("Deferred non-impersonating MSI context required.");
                using (var sha = SHA256.Create())
                using (var input = File.OpenRead(args[0]))
                    if (BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "") != args[2].ToUpperInvariant())
                        throw new InvalidOperationException("Package digest differs.");
                if (!File.Exists(Path.Combine(args[1], "ImageCopySave.Shell.dll"))) throw new InvalidOperationException("Missing payload.");
                if (manager.FindPackages().Any(p => p.Id.Name.StartsWith("ImageCopySave", StringComparison.OrdinalIgnoreCase)) ||
                    manager.FindProvisionedPackages().Any(p => p.Id.Name.StartsWith("ImageCopySave", StringComparison.OrdinalIgnoreCase)))
                    throw new InvalidOperationException("Existing ImageCopySave registration must be preserved.");
                var options = new StagePackageOptions { AllowUnsigned = true, ExternalLocationUri = new Uri(Path.GetFullPath(args[1]).TrimEnd('\\') + "\\") };
                attempted = true;
                log.WriteLine("STAGING");
                Check(Wait(manager.StagePackageByUriAsync(new Uri(Path.GetFullPath(args[0])), options)));
                log.WriteLine("STAGING=PASS");
                Check(Wait(manager.ProvisionPackageForAllUsersAsync(Family)));
                if (manager.FindProvisionedPackages().Count(p => p.Id.FullName == FullName) != 1)
                    throw new InvalidOperationException("Expected provisioning missing.");
                log.WriteLine("PROVISIONING=PASS");
                foreach (var user in manager.FindUsers(FullName)) log.WriteLine("USER_STATE=" + user.InstallState);
                if (args.Length == 5)
                {
                    log.WriteLine("AWAITING_ORDINARY_USER");
                    var deadline = DateTime.UtcNow.AddSeconds(120);
                    while (DateTime.UtcNow < deadline && !File.Exists(args[3] + ".complete")) System.Threading.Thread.Sleep(200);
                    foreach (var user in manager.FindUsers(FullName)) log.WriteLine("AFTER_USER_STATE=" + user.InstallState);
                }
                passed = true;
            }
            catch (Exception e) { log.WriteLine("ERROR=" + e); }
            finally
            {
                if (attempted)
                {
                    try
                    {
                        if (manager.FindProvisionedPackages().Any(p => p.Id.FullName == FullName))
                            Check(Wait(manager.DeprovisionPackageForAllUsersAsync(Family)));
                        if (manager.FindPackages().Any(p => p.Id.FullName == FullName && p.Id.Publisher == Publisher))
                            Check(Wait(manager.RemovePackageAsync(FullName, RemovalOptions.RemoveForAllUsers)));
                        if (manager.FindPackages().Any(p => p.Id.Name == Name) || manager.FindProvisionedPackages().Any(p => p.Id.Name == Name))
                            throw new InvalidOperationException("Probe registration remains.");
                        cleanup = true;
                        log.WriteLine("CLEANUP=PASS");
                    }
                    catch (Exception e) { log.WriteLine("CLEANUP_ERROR=" + e); }
                }
                log.WriteLine("STATUS=" + (passed && cleanup ? "PASS" : "FAIL"));
                log.WriteLine("FINISH " + DateTime.UtcNow.ToString("o"));
            }
        }
        return passed && cleanup ? 0 : 1;
    }
}
