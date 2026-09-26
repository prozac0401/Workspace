[CmdletBinding()]
param(
    [ValidateSet('Snapshot', 'Compare', 'Lifecycle')]
    [string]$Action = 'Snapshot',
    [string]$Version = '0.1.0-rc.9',
    [string]$PackageDirectory,
    [string]$PreviousVersion,
    [string]$PreviousPackageDirectory,
    [switch]$TestLockedRepair,
    [string]$OutputDirectory,
    [string]$Baseline
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not $PackageDirectory) { $PackageDirectory = Join-Path $repoRoot "artifacts\selection-export\$Version" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot ('artifacts\selection-export\package-tests\' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$outputBoundary = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\selection-export')) + [IO.Path]::DirectorySeparatorChar
if (-not $OutputDirectory.StartsWith($outputBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package test evidence must stay inside artifacts/selection-export.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$productId = 'Workspace.ExcelSelectionExport'
$clsid = '{2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1}'
$localApplicationData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([String]::IsNullOrWhiteSpace($localApplicationData)) { throw 'Windows LocalApplicationData known folder could not be resolved.' }
$productDirectory = Join-Path $localApplicationData 'Workspace\ExcelSelectionExport'
$installedPayload = Join-Path $productDirectory ("versions\$Version\x64")
$views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)
$checks = New-Object 'System.Collections.Generic.List[object]'

function Hash-Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Read-RegistryTree($Key, [string]$Relative, $Lines, [string]$ExcludedChild) {
    $Lines.Add('KEY|' + $Relative)
    foreach ($name in @($Key.GetValueNames() | Sort-Object)) {
        $value = $Key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($value -is [byte[]]) { $text = [Convert]::ToBase64String($value) }
        elseif ($value -is [string[]]) { $text = ConvertTo-Json -InputObject $value -Compress }
        else { $text = [Convert]::ToString($value, [Globalization.CultureInfo]::InvariantCulture) }
        $Lines.Add(($Relative + '|' + $name + '|' + $Key.GetValueKind($name) + '|' + $text))
    }
    foreach ($child in @($Key.GetSubKeyNames() | Sort-Object)) {
        if ($Relative -eq '' -and $ExcludedChild -and $child -eq $ExcludedChild) { continue }
        $opened = $Key.OpenSubKey($child, $false)
        if ($null -eq $opened) { throw 'A registry key disappeared during the safety snapshot.' }
        try { Read-RegistryTree $opened ($Relative + '\' + $child) $Lines '' }
        finally { $opened.Dispose() }
    }
}
function Registry-Fingerprint($Hive, $View, [string]$Path, [string]$ExcludedChild = '') {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
    try {
        $key = $base.OpenSubKey($Path, $false)
        if ($null -eq $key) { if ($ExcludedChild) { return 'NO_OTHER_ENTRIES' } else { return 'ABSENT' } }
        try {
            $lines = New-Object 'System.Collections.Generic.List[string]'
            Read-RegistryTree $key '' $lines $ExcludedChild
            if ($ExcludedChild -and $lines.Count -eq 1) { return 'NO_OTHER_ENTRIES' }
            return Hash-Text ([string]::Join([Environment]::NewLine, $lines.ToArray()))
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}
function Capture-Safety {
    $fingerprints = [ordered]@{}
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in $views) {
            foreach ($key in @('Software\Policies\Microsoft\Office', 'Software\Microsoft\Office\16.0\Excel\Security', 'Software\Microsoft\Office\16.0\Common\Security', 'Software\Microsoft\Office\16.0\Excel\Resiliency', 'Software\Microsoft\Office\16.0\Excel\Options')) {
                $fingerprints["$hive/$view/$key"] = Registry-Fingerprint $hive $view $key
            }
            $fingerprints["$hive/$view/OtherOfficeAddins"] = Registry-Fingerprint $hive $view 'Software\Microsoft\Office\Excel\Addins' $productId
            $fingerprints["$hive/$view/OtherWorkspaceTools"] = Registry-Fingerprint $hive $view 'Software\Workspace' 'ExcelSelectionExport'
        }
    }
    # Only fixed, known software payloads are hashed. No workbook or business directory is scanned.
    foreach ($relative in @('ExcelSmartListCompare\ExcelSmartListCompare.xlam', 'ExcelSmartListCompare\Setup.ps1', 'ExcelSmartListCompare\Install.cmd', 'ExcelSmartListCompare\Uninstall.cmd', 'ExcelSmartListCompare.Setup\manager.id')) {
        $path = Join-Path $localApplicationData $relative
        $fingerprints['OtherProductFile/' + $relative] = if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'ABSENT' }
    }
    return [ordered]@{ Utc = [DateTime]::UtcNow.ToString('o'); Fingerprints = $fingerprints }
}
function Save-Json($Object, [string]$Path) { $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Check([bool]$Condition, [string]$Name) {
    $checks.Add([ordered]@{ name = $Name; passed = $Condition })
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Output "PASS: $Name"
}
function Assert-Safety($Before, $After, [string]$Name) {
    # Compare fingerprint values by key, independent of dictionary/JSON ordering.
    # Print only changed scope names, never registry values or business contents.
    $beforeMap = $Before.Fingerprints | ConvertTo-Json -Compress -Depth 10 | ConvertFrom-Json
    $afterMap = $After.Fingerprints | ConvertTo-Json -Compress -Depth 10 | ConvertFrom-Json
    $scopeNames = @(@($beforeMap.PSObject.Properties.Name) + @($afterMap.PSObject.Properties.Name) | Sort-Object -Unique)
    $different = New-Object 'System.Collections.Generic.List[string]'
    foreach ($scopeName in $scopeNames) {
        $beforeProperty = $beforeMap.PSObject.Properties[$scopeName]
        $afterProperty = $afterMap.PSObject.Properties[$scopeName]
        if ($null -eq $beforeProperty -or $null -eq $afterProperty -or $beforeProperty.Value -cne $afterProperty.Value) {
            $different.Add($scopeName)
            Write-Output ('Changed fingerprint scope: ' + $scopeName)
        }
    }
    Check ($different.Count -eq 0) $Name
}
function Product-Registered {
    foreach ($view in $views) {
        foreach ($key in @("Software\Classes\CLSID\$clsid", "Software\Classes\$productId", "Software\Microsoft\Office\Excel\Addins\$productId", "Software\Microsoft\Windows\CurrentVersion\Uninstall\$($productId)_is1")) {
            if ((Registry-Fingerprint ([Microsoft.Win32.RegistryHive]::CurrentUser) $view $key) -ne 'ABSENT') { return $true }
        }
    }
    return $false
}
function Run-Package([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing package: $Path" }
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ('/LOG=' + (Join-Path $OutputDirectory ($Label + '.log'))))
    $quoted = @($arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' })
    $process = Start-Process -FilePath $Path -ArgumentList $quoted -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(120000)) { throw 'Installer did not finish within 120 seconds. It was not forcibly terminated; inspect its state before continuing.' }
    return $process.ExitCode
}

if ($Action -eq 'Snapshot') {
    $snapshot = Capture-Safety
    $snapshotPath = Join-Path $OutputDirectory 'safety-snapshot.json'
    Save-Json $snapshot $snapshotPath
    Write-Output "Read-only safety snapshot: $snapshotPath"
    return
}
if ($Action -eq 'Compare') {
    if (-not $Baseline) { throw '-Baseline is required for Compare.' }
    $before = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json
    $after = Capture-Safety
    Save-Json $after (Join-Path $OutputDirectory 'safety-after.json')
    try { Assert-Safety $before $after 'Office security, policy, other add-in registrations and known other-product payloads unchanged' }
    finally { Save-Json $checks.ToArray() (Join-Path $OutputDirectory 'checks.json') }
    return
}

# Lifecycle intentionally refuses existing installations and live Excel processes.
# It never closes Excel, changes Office/Trust Center policy or reenables COM add-ins.
if (@(Get-Process -Name EXCEL -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Close Excel after saving work before package lifecycle tests.' }
if ((Test-Path -LiteralPath $productDirectory) -or (Product-Registered)) { throw 'An existing SelectionExport installation or folder was found. Preserve it; use Snapshot/Compare or a clean test profile.' }
$x64Package = Join-Path $PackageDirectory "ExcelSelectionExport-$Version-x64-Setup.exe"
$x86Package = Join-Path $PackageDirectory "ExcelSelectionExport-$Version-x86-Setup.exe"
if ([bool]$PreviousVersion -ne [bool]$PreviousPackageDirectory) { throw 'Specify both PreviousVersion and PreviousPackageDirectory for cross-version upgrade.' }
if ($PreviousVersion -eq $Version) { throw 'Cross-version upgrade requires different versions.' }
$previousPackage = if ($PreviousVersion) { Join-Path $PreviousPackageDirectory "ExcelSelectionExport-$PreviousVersion-x64-Setup.exe" } else { $null }
if ($previousPackage -and -not (Test-Path -LiteralPath $previousPackage -PathType Leaf)) { throw 'The previous x64 installer is missing.' }
$probe = Join-Path $PackageDirectory 'x64\SetupProbe.exe'
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw 'Build the x64 setup probe first.' }
$probeReport = Join-Path $OutputDirectory 'preflight.ini'
$probeProcess = Start-Process -FilePath $probe -ArgumentList @('preflight', 'x64', ('"' + $probeReport + '"')) -WindowStyle Hidden -Wait -PassThru
if ($probeProcess.ExitCode -ne 0) { throw 'This lifecycle test requires supported x64 Excel and an allowed test environment. The preflight report distinguishes its blocker.' }
$baselineState = Capture-Safety
Save-Json $baselineState (Join-Path $OutputDirectory 'safety-before.json')
$sentinel = Join-Path $OutputDirectory 'outside-product-sentinel.txt'
$sentinelText = 'SelectionExport package test owned sentinel ' + [Guid]::NewGuid().ToString('D')
[IO.File]::WriteAllText($sentinel, $sentinelText, [Text.Encoding]::UTF8)
try {
    $mismatchExit = Run-Package $x86Package '01-x86-mismatch'
    Check ($mismatchExit -ne 0) 'x86 package rejects installed x64 Excel'
    Check (-not (Product-Registered) -and -not (Test-Path -LiteralPath $productDirectory)) 'Architecture mismatch creates no product installation or registration'
    $mismatchLog = Get-Content -LiteralPath (Join-Path $OutputDirectory '01-x86-mismatch.log') -Raw
    Check ($mismatchLog -match 'preflight exit=13|\[E13\]') 'Architecture mismatch has distinct E13 diagnostic'
    Assert-Safety $baselineState (Capture-Safety) 'Mismatch leaves security and other tools unchanged'
    if ($previousPackage) {
        Check ((Run-Package $previousPackage '01b-previous-install') -eq 0) 'Previous-version installation succeeds'
        $previousDll = Join-Path $productDirectory "versions\$PreviousVersion\x64\ExcelSelectionExport.AddIn.dll"
        Check (Test-Path -LiteralPath $previousDll -PathType Leaf) 'Previous-version payload exists'
        $previousHash = (Get-FileHash -LiteralPath $previousDll -Algorithm SHA256).Hash
        Assert-Safety $baselineState (Capture-Safety) 'Previous-version installation leaves security and other tools unchanged'
    }
    Check ((Run-Package $x64Package '02-install') -eq 0) 'x64 initial installation and COM activation succeed'
    Check ((Test-Path -LiteralPath (Join-Path $installedPayload 'ExcelSelectionExport.AddIn.dll')) -and (Product-Registered)) 'Owned payload and registration exist'
    if ($previousPackage) {
        Check ((Get-FileHash -LiteralPath $previousDll -Algorithm SHA256).Hash -eq $previousHash) 'Upgrade preserves the previous version payload bytes'
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $key = $base.OpenSubKey("Software\Classes\CLSID\$clsid\InprocServer32")
            try {
                $registeredUri = [Uri]$key.GetValue('CodeBase')
                Check ($registeredUri.IsFile -and $registeredUri.LocalPath -eq (Join-Path $installedPayload 'ExcelSelectionExport.AddIn.dll')) 'Cross-version upgrade selects the new DLL in COM registration'
            } finally { if ($key) { $key.Dispose() } }
        } finally { $base.Dispose() }
    }
    Assert-Safety $baselineState (Capture-Safety) 'Install leaves security and other tools unchanged'
    if ($TestLockedRepair) {
        $dll = Join-Path $installedPayload 'ExcelSelectionExport.AddIn.dll'
        $hashBefore = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
        $registrationBefore = Registry-Fingerprint ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Registry64) "Software\Classes\CLSID\$clsid"
        $locked = [IO.File]::Open($dll, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try { $lockedExit = Run-Package $x64Package '02b-locked-repair' }
        finally { $locked.Dispose() }
        Check ($lockedExit -ne 0) 'Locked payload replacement reports a failed installation'
        Check ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -eq $hashBefore) 'Locked replacement failure preserves the installed DLL'
        Check ((Registry-Fingerprint ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Registry64) "Software\Classes\CLSID\$clsid") -eq $registrationBefore) 'Locked replacement failure preserves COM registration'
        Assert-Safety $baselineState (Capture-Safety) 'Locked replacement failure leaves security and other tools unchanged'
    }
    Check ((Run-Package $x64Package '03-repair') -eq 0) 'Same-version repair or upgrade succeeds with Excel closed'
    Assert-Safety $baselineState (Capture-Safety) 'Repair leaves security and other tools unchanged'
    $uninstaller = Join-Path $productDirectory 'unins000.exe'
    Check ((Run-Package $uninstaller '04-uninstall') -eq 0) 'Independent product uninstall succeeds'
    Check (-not (Product-Registered)) 'Owned COM, Office and Apps registration removed'
    Check (-not (Test-Path -LiteralPath (Join-Path $installedPayload 'ExcelSelectionExport.AddIn.dll'))) 'Owned add-in DLL removed'
    if ($previousPackage) { Check (-not (Test-Path -LiteralPath $previousDll)) 'Uninstall also removes the previous owned payload' }
    Check (([IO.File]::ReadAllText($sentinel, [Text.Encoding]::UTF8)) -ceq $sentinelText) 'Sentinel outside the product survives install, repair and uninstall'
    Assert-Safety $baselineState (Capture-Safety) 'Uninstall leaves security and other tools unchanged'
    Check ((Run-Package $x64Package '05-reinstall') -eq 0) 'Reinstall after removal succeeds'
    Check ((Run-Package (Join-Path $productDirectory 'unins000.exe') '06-final-uninstall') -eq 0) 'Final removal restores absent initial product state'
    Check (-not (Product-Registered)) 'Final product registration absent'
    Assert-Safety $baselineState (Capture-Safety) 'Reinstall/removal leaves security and other tools unchanged'
} finally {
    Save-Json (Capture-Safety) (Join-Path $OutputDirectory 'safety-after.json')
    Save-Json ([ordered]@{ checks = $checks.ToArray(); previousVersion = $PreviousVersion; version = $Version; limitations = @('Actual Excel menu coexistence and automatic load are separate UI tests.', 'Cross-version upgrade is covered only when PreviousVersion and PreviousPackageDirectory are supplied.', 'No policy or user-disabled setting is modified for testing.', 'x86 Excel runtime loading is not tested on this x64 Excel machine.') }) (Join-Path $OutputDirectory 'package-test-results.json')
}
Write-Output "Package lifecycle evidence: $OutputDirectory"
