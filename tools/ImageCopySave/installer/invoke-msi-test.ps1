[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [Parameter(Mandatory=$true)][ValidateSet('Install','Repair','Remove','Rollback','Upgrade')][string]$Action,
    [string]$PreviousMetadata = '',
    [switch]$DamageOwnedFile
)
# A normal ShellExecute runas launch. The Windows consent prompt remains the OS's.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
function Owned-Input([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    if (-not $full.StartsWith(($root + '\artifacts\image-copy-save\msi\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Expected this worktree product MSI artifact.' }
    $current=$full
    while ($current -ne $root) { if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse inputs are not accepted.' }; $current=[IO.Path]::GetDirectoryName($current) }
    return $full
}
$MsiPath = Owned-Input $MsiPath
if ($PreviousMetadata) { $PreviousMetadata = Owned-Input $PreviousMetadata }
$output = Join-Path $root ('artifacts/image-copy-save/msi-test-launch/' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$report = [ordered]@{ status='REQUESTING_UAC'; requestedUtc=[DateTime]::UtcNow.ToString('o'); action=$Action; msi=$MsiPath; scriptSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'test-msi-lifecycle.ps1') -Algorithm SHA256).Hash; processId=$null; exitCode=$null }
$reportPath = Join-Path $output 'launch.json'
function Write-Report { [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false))) }
Write-Report
$arguments = @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'test-msi-lifecycle.ps1'),'-MsiPath',$MsiPath,'-Action',$Action)
if ($PreviousMetadata) { $arguments += @('-PreviousMetadata',$PreviousMetadata) }
if ($DamageOwnedFile) { $arguments += '-DamageOwnedFile' }
$quoted = @($arguments | ForEach-Object { if ($_.Contains('"') -or $_ -match '[\r\n]' -or $_.EndsWith('\')) { throw 'Ambiguous elevation argument.' }; '"' + $_ + '"' }) -join ' '
try {
    $process = Start-Process -FilePath (Join-Path $env:windir 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $quoted -Verb RunAs -WindowStyle Hidden -PassThru
    $report.status='RUNNING'; $report.processId=$process.Id; Write-Report
    $process.WaitForExit(); $report.exitCode=$process.ExitCode
    $report.status=$(if ($process.ExitCode -eq 0) { 'COMPLETED' } else { 'CHILD_FAILED_OR_BLOCKED' })
} catch { $report.status='ELEVATION_NOT_STARTED'; $report.error=$_.Exception.Message; throw }
finally { $report.finishedUtc=[DateTime]::UtcNow.ToString('o'); Write-Report; if ($null -ne $process) { $process.Dispose() }; Write-Output "Launch result: $reportPath" }
