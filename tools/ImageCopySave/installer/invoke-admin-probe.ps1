[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExternalLocation,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$MakeAppx,
    [ValidateRange(0, 900)][int]$ExplorerWindowSeconds = 0
)
# Request elevation through the normal Windows UAC prompt; never bypass it.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$external = (Resolve-Path -LiteralPath $ExternalLocation).Path
$make = (Resolve-Path -LiteralPath $MakeAppx).Path
$probe = Join-Path $PSScriptRoot 'probe-unsigned-identity.ps1'
$powershell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
if (-not $external.StartsWith((Join-Path $repo 'artifacts') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'ExternalLocation must be under this worktree artifacts.' }
foreach ($value in @($external, $make, $probe, $powershell)) {
    if ($value.IndexOfAny([char[]]@('"', "`r", "`n")) -ge 0) { throw 'Unsafe command argument.' }
}
$output = Join-Path $repo ('artifacts/image-copy-save/admin-probe-launch/' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$report = [ordered]@{
    startedUtc = [DateTime]::UtcNow.ToString('o'); status = 'REQUESTING_UAC'
    probe = $probe; probeSha256 = (Get-FileHash -LiteralPath $probe).Hash
    externalLocation = $external; makeAppx = $make; elevationMethod = 'Windows Shell runas'
    securitySettingsChanged = $false; childPid = $null; childExitCode = $null
}
$reportFile = Join-Path $output 'launch.json'
function Write-LaunchReport { $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportFile -Encoding UTF8 }
Write-LaunchReport
$process = $null
try {
    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $probe,
        '-ExternalLocation', $external, '-MakeAppx', $make, '-RegistrationContext', 'Administrator', '-ExplorerWindowSeconds', [string]$ExplorerWindowSeconds)
    $quoted = @($arguments | ForEach-Object { '"' + $_ + '"' })
    $process = Start-Process -FilePath $powershell -ArgumentList $quoted -Verb RunAs -WindowStyle Hidden -PassThru
    $report.status = 'RUNNING'; $report.childPid = $process.Id
    Write-LaunchReport
    $process.WaitForExit()
    $report.childExitCode = $process.ExitCode
    $report.status = if ($process.ExitCode -eq 0) { 'COMPLETED' } else { 'CHILD_FAILED_OR_BLOCKED' }
} catch {
    $report.status = 'ELEVATION_NOT_STARTED'
    $report.error = $_.Exception.Message
    if ($_.Exception.InnerException -is [ComponentModel.Win32Exception]) { $report.nativeError = $_.Exception.InnerException.NativeErrorCode }
} finally {
    if ($null -ne $process) { $process.Dispose() }
    $report.finishedUtc = [DateTime]::UtcNow.ToString('o')
    Write-LaunchReport
    Write-Output ('Admin probe launch evidence: ' + $reportFile)
}
if ($report.status -ne 'COMPLETED') { exit 1 }
