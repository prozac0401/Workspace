[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath, [string]$UpgradeMsiPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$package = (Resolve-Path -LiteralPath $MsiPath).Path
$menuKey = 'HKCU:\Software\Classes\Directory\shell\Workspace.FolderState'
if (Test-Path -LiteralPath $menuKey) { throw 'An existing FolderState menu is present. Use a clean test profile.' }
$testRoot = Join-Path $repoRoot ('artifacts/msi-smoke-' + [guid]::NewGuid().ToString('N'))
$resolved = [IO.Path]::GetFullPath($testRoot)
$allowed = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Test path outside artifacts.' }
$install = Join-Path $testRoot 'installed'
$business = Join-Path $testRoot 'business'
New-Item -ItemType Directory -Path $testRoot,$business -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $business 'keep.txt'),'UNCHANGED')
$results = [Collections.Generic.List[object]]::new()
$installedPackage = $null
$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function Msi-Run([string]$name,[string[]]$arguments,[int[]]$expected=@(0,3010)) {
    $log = Join-Path $testRoot "$name.log"
    $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/msiexec.exe') -ArgumentList ($arguments + @('/qn','/norestart','/l*v',('"'+$log+'"'))) -Wait -PassThru -WindowStyle Hidden
    $results.Add(@{name=$name;exitCode=$process.ExitCode;passed=($expected -contains $process.ExitCode)})
    if ($expected -notcontains $process.ExitCode) { throw "$name failed with $($process.ExitCode). Log: $log" }
}
function Check([string]$name,[bool]$condition) { $results.Add(@{name=$name;passed=$condition}); if (-not $condition) { throw "Check failed: $name" } }
try {
    Msi-Run 'install' @('/i',('"'+$package+'"'),('INSTALLFOLDER="'+$install+'"'))
    $installedPackage = $package
    Check 'HKCU Explorer menu' (Test-Path -LiteralPath $menuKey)
    $cli = Join-Path $install 'FolderState.Cli.exe'
    Check 'self-contained CLI present' (Test-Path -LiteralPath $cli)
    $output = & $cli set done $business --json
    Check 'installed CLI works' ($LASTEXITCODE -eq 0)
    $parsed = $output | ConvertFrom-Json
    Check 'state recorded' ($parsed.Success -eq $true)
    $statePath = Join-Path $business '.folderstate.ini'
    $before = [IO.File]::ReadAllBytes($statePath)
    $icon = Join-Path $install 'icons/done.ico'
    Remove-Item -LiteralPath $icon -Force
    Msi-Run 'repair' @('/fa',('"'+$package+'"'))
    Check 'missing icon repaired' (Test-Path -LiteralPath $icon)
    if ($UpgradeMsiPath) {
        $upgrade = (Resolve-Path -LiteralPath $UpgradeMsiPath).Path
        Msi-Run 'upgrade' @('/i',('"'+$upgrade+'"'),('INSTALLFOLDER="'+$install+'"'))
        $installedPackage = $upgrade
        Msi-Run 'downgrade-blocked' @('/i',('"'+$package+'"'),('INSTALLFOLDER="'+$install+'"')) @(1638,1603)
        $downgradeLog = Get-Content -LiteralPath (Join-Path $testRoot 'downgrade-blocked.log') -Raw
        Check 'downgrade rejected for version reason' (($results[$results.Count-1].exitCode -eq 1638) -or ($downgradeLog -match '더 최신 버전의 FolderState'))
        Check 'CLI retained after upgrade' (Test-Path -LiteralPath $cli)
        & $cli status $business --json | Out-Null
        Check 'saved state readable after upgrade' ($LASTEXITCODE -eq 0)
    }
    Msi-Run 'uninstall' @('/x',('"'+$installedPackage+'"'))
    $installedPackage = $null
    Check 'menu removed' (-not (Test-Path -LiteralPath $menuKey))
    Check 'program removed' (-not (Test-Path -LiteralPath $cli))
    Check 'business file untouched' ([IO.File]::ReadAllText((Join-Path $business 'keep.txt')) -eq 'UNCHANGED')
    Check 'folder metadata survives uninstall' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath)) -eq [Convert]::ToBase64String($before))
}
finally {
    if ($installedPackage) { Msi-Run 'cleanup-uninstall' @('/x',('"'+$installedPackage+'"')) }
    $record = @{timestamp=[DateTimeOffset]::Now.ToString('O');os=[Environment]::OSVersion.VersionString;elevated=$isElevated;results=$results.ToArray();fixture=$testRoot}
    $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $repoRoot 'artifacts/installer-test-results.json') -Encoding UTF8
}
Write-Host "Installer smoke passed. Evidence: $testRoot"
