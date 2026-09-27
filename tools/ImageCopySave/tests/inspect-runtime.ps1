[CmdletBinding()]
param(
    [ValidateRange(0, 30)]
    [int]$WaitForHelperSeconds = 0
)

# Read-only, current-session runtime evidence. Do not publish the JSON as user logs.
# No command lines, clipboard access, privilege changes, UI automation or process control.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runtimeSession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
$runtimeRecords = @()
$runtimeStatus = 'Success'
$runtimeHelperSeen = $false

try {
    if (-not ('ImageCopySave.RuntimeReadOnlyProbe' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace ImageCopySave
{
    public sealed class RuntimeReadOnlyResult
    {
        public string ExecutablePath = "Unknown";
        public object Elevated = "Unknown";
        public bool ScopeMatched = true;
    }

    public static class RuntimeReadOnlyProbe
    {
        public static RuntimeReadOnlyResult Read(uint processId, uint expectedSession, string expectedName)
        {
            var result = new RuntimeReadOnlyResult();
            IntPtr process = IntPtr.Zero, token = IntPtr.Zero;
            try
            {
                // No terminate, suspend, VM read/write, duplicate or adjustment permissions.
                process = OpenProcess(0x1000 /* PROCESS_QUERY_LIMITED_INFORMATION */, false, processId);
                if (process == IntPtr.Zero) return result;
                uint session;
                if (!ProcessIdToSessionId(processId, out session)) return result;
                if (session != expectedSession) { result.ScopeMatched = false; return result; }

                var image = new StringBuilder(32768);
                uint size = (uint)image.Capacity;
                if (!QueryFullProcessImageName(process, 0, image, ref size)) return result;
                string actualName = Path.GetFileName(image.ToString());
                // A process may have exited between the CIM snapshot and OpenProcess.
                // Check the opened process before reading its token or reporting its path.
                if (!String.Equals(actualName, expectedName, StringComparison.OrdinalIgnoreCase) ||
                    !(String.Equals(actualName, "explorer.exe", StringComparison.OrdinalIgnoreCase) ||
                      String.Equals(actualName, "ImageCopySave.Helper.exe", StringComparison.OrdinalIgnoreCase)))
                { result.ScopeMatched = false; return result; }
                result.ExecutablePath = image.ToString();

                if (!OpenProcessToken(process, 0x0008 /* TOKEN_QUERY */, out token)) return result;
                uint elevated, returned;
                if (GetTokenInformation(token, 20 /* TokenElevation */, out elevated, sizeof(uint), out returned)
                    && returned == sizeof(uint))
                    result.Elevated = elevated != 0;
                return result;
            }
            catch { return result; }
            finally
            {
                if (token != IntPtr.Zero) CloseHandle(token);
                if (process != IntPtr.Zero) CloseHandle(process);
            }
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint processId);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ProcessIdToSessionId(uint processId, out uint sessionId);
        [DllImport("kernel32.dll", EntryPoint = "QueryFullProcessImageNameW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref uint size);
        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(IntPtr token, int informationClass, out uint information,
            uint length, out uint returned);
        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }
}
'@ -ErrorAction Stop
    }

    # The CIM provider receives the names/session filter and requested properties.
    # CommandLine and other applications are never requested.
    $runtimeFilter = "(Name = 'explorer.exe' OR Name = 'ImageCopySave.Helper.exe') AND SessionId = $runtimeSession"
    $runtimeWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $runtimeAttempts = 0
    do {
        # This test-only observation loop is bounded to the requested 0..30 seconds.
        # Each local CIM request also has a one-second operation timeout.
        if ($WaitForHelperSeconds -gt 0 -and $runtimeAttempts -gt 0 -and
            $runtimeWatch.ElapsedMilliseconds -ge ($WaitForHelperSeconds * 1000)) { break }
        $runtimeAttempts++
        $runtimeRecords = @()
        $runtimeStatus = 'Success'
        $runtimeProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter $runtimeFilter -Property ProcessId, SessionId, Name -OperationTimeoutSec 1 -ErrorAction Stop | Sort-Object ProcessId)
        foreach ($runtimeProcess in $runtimeProcesses) {
            $runtimeInfo = [ImageCopySave.RuntimeReadOnlyProbe]::Read(
                [uint32]$runtimeProcess.ProcessId, [uint32]$runtimeSession, [string]$runtimeProcess.Name)
            if (-not $runtimeInfo.ScopeMatched) {
                $runtimeStatus = 'Unknown'
                continue
            }
            if ($runtimeProcess.Name -ieq 'ImageCopySave.Helper.exe') { $runtimeHelperSeen = $true }
            if ($runtimeInfo.ExecutablePath -eq 'Unknown' -or $runtimeInfo.Elevated -is [string]) {
                $runtimeStatus = 'Unknown'
            }
            $runtimeRecords += [pscustomobject][ordered]@{
                pid = [uint32]$runtimeProcess.ProcessId
                sessionId = [uint32]$runtimeProcess.SessionId
                executablePath = $runtimeInfo.ExecutablePath
                elevated = $runtimeInfo.Elevated
            }
        }
        if ($WaitForHelperSeconds -eq 0 -or $runtimeHelperSeen) { break }
        $runtimeRemaining = $WaitForHelperSeconds * 1000 - $runtimeWatch.ElapsedMilliseconds
        if ($runtimeRemaining -le 0) { break }
        Start-Sleep -Milliseconds ([int][Math]::Min(250, $runtimeRemaining))
    } while ($runtimeWatch.ElapsedMilliseconds -lt ($WaitForHelperSeconds * 1000))

    if ($WaitForHelperSeconds -gt 0 -and -not $runtimeHelperSeen) {
        $runtimeStatus = 'NOT_FOUND'
    }

} catch {
    # A failed query is not evidence that no matching processes exist.
    # Do not emit free-form exception messages that may contain unrelated data.
    $runtimeStatus = 'Unknown'
}

$runtimeOutput = [ordered]@{
    sessionId = $runtimeSession
    queryStatus = $runtimeStatus
    processes = @($runtimeRecords)
}
if ($WaitForHelperSeconds -gt 0) {
    $runtimeOutput['waitForHelperSeconds'] = $WaitForHelperSeconds
    $runtimeOutput['helperObservation'] = if ($runtimeHelperSeen) { 'FOUND' } elseif ($runtimeStatus -eq 'NOT_FOUND') { 'NOT_FOUND' } else { 'Unknown' }
}
$runtimeOutput | ConvertTo-Json -Depth 4
if ($runtimeStatus -ne 'Success') { exit 2 }
exit 0
