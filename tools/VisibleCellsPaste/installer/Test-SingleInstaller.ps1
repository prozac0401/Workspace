[CmdletBinding()]
param([Parameter(Mandatory)][string]$Installer, [Parameter(Mandatory)][string]$ReleaseZip)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output = Join-Path $repo ('artifacts\visible-cells-paste\single-lifecycle-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $output "한글 test's 설치"
$default = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'VisibleCellsPaste'
$addin = 'Software\Microsoft\Office\Excel\Addins\Workspace.VisibleCellsPaste'
$class = 'Software\Classes\CLSID\{856B2219-6225-42ED-8FF1-2D06E5913AC8}'
$uninstall = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\Workspace.VisibleCellsPaste'
$reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', [Microsoft.Win32.RegistryView]::Registry64)
$checks = New-Object 'System.Collections.Generic.List[object]'
function Check([bool]$Ok, [string]$Name) {
    $checks.Add([ordered]@{ name = $Name; passed = $Ok })
    if (-not $Ok) { throw "FAIL: $Name" }
    Write-Output "PASS: $Name"
}
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Run([string]$Exe, [string[]]$Arguments, [string]$Report) {
    $all = @($Arguments) + @('--silent','--directory',$target,'--report',(Join-Path $output "$Report.txt"))
    $quoted = @($all | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' })
    $process = Start-Process -FilePath $Exe -ArgumentList $quoted -WindowStyle Hidden -PassThru
    try {
        if (-not $process.WaitForExit(120000)) { throw 'Installer remains running; inspect before proceeding. No forced termination.' }
        return $process.ExitCode
    } finally { $process.Dispose() }
}
function RegistryTree($Key, [string]$Path, $Lines) {
    foreach ($name in @($Key.GetValueNames() | Sort-Object)) {
        $value = $Key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $Lines.Add($Path + '|' + $name + '|' + $Key.GetValueKind($name) + '|' + (ConvertTo-Json -InputObject $value -Compress))
    }
    foreach ($name in @($Key.GetSubKeyNames() | Sort-Object)) {
        if ($Path -eq 'Addins' -and $name -eq 'Workspace.VisibleCellsPaste') { continue }
        $child = $Key.OpenSubKey($name)
        try { RegistryTree $child ($Path + '\' + $name) $Lines } finally { $child.Dispose() }
    }
}
function Safety {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($hive in @('CurrentUser','LocalMachine')) {
        foreach ($view in @('Registry64','Registry32')) {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
            try {
                foreach ($path in @('Software\Policies\Microsoft\Office','Software\Microsoft\Office\16.0\Excel\Security','Software\Microsoft\Office\16.0\Excel\Resiliency','Software\Microsoft\Office\16.0\Excel\Options','Software\Microsoft\Office\Excel\Addins')) {
                    $lines.Add("$hive|$view|$path")
                    $key = $base.OpenSubKey($path)
                    if ($key) { try { RegistryTree $key $(if ($path.EndsWith('\Addins')) { 'Addins' } else { $path }) $lines } finally { $key.Dispose() } }
                }
            } finally { $base.Dispose() }
        }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]::Join("`n",$lines.ToArray())))) } finally { $sha.Dispose() }
}
try {
    if (@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Excel must be closed before serial installer tests.' }
    if (Test-Path -LiteralPath $default) { throw 'Preserve the existing default product directory.' }
    foreach ($view in @('Registry64','Registry32')) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser',$view)
        try { foreach ($path in @($addin,$class,$uninstall,'Software\Classes\Workspace.VisibleCellsPaste','Software\VisibleCellsPaste')) {
            $key = $base.OpenSubKey($path)
            if ($key) { $key.Dispose(); throw 'Existing product registration must be preserved.' }
        }} finally { $base.Dispose() }
    }
    New-Item -ItemType Directory -Path $output | Out-Null
    $before = Safety
    & (Join-Path $PSScriptRoot '..\build\verify-package.ps1') -ZipPath $ReleaseZip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $legacy = Join-Path $output 'verified-release'
    [IO.Compression.ZipFile]::ExtractToDirectory($ReleaseZip, $legacy)
    Check ((Run (Join-Path $legacy 'VisibleCellsPaste.Setup.exe') @() '01-zip-install') -eq 0) 'Existing ZIP installer installs normally'
    $manifestPath = Join-Path $target 'installation.xml'
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
    Check ($manifest.installation.schema -eq '1' -and $manifest.installation.version -eq '0.1.1') 'Existing ownership manifest recognized'
    $dllEntry = @($manifest.installation.files.file | Where-Object { $_.path.EndsWith('VisibleCellsPaste.AddIn.dll') })[0]
    $dll = Join-Path $target $dllEntry.path
    $dllHash = Hash $dll
    $unknown = Join-Path $target 'user-canary.txt'; [IO.File]::WriteAllText($unknown,'preserve user file')
    Check ((Run $Installer @() '02-single-migration') -eq 0) 'Single EXE updates the ZIP installation'
    Check ((Hash $dll) -eq $dllHash) 'Migration preserves exact public add-in DLL bytes'
    Check ((Get-Content -LiteralPath $unknown -Raw) -ceq 'preserve user file') 'Migration preserves unknown user file'
    Check ((Safety) -eq $before) 'Migration preserves other add-ins and Office settings'
    $key = $reg.OpenSubKey($uninstall)
    try { Check ($key.GetValue('InstallLocation') -eq $target -and $key.GetValue('DisplayVersion') -eq '0.1.1') 'Single existing product uninstall registration retained' } finally { $key.Dispose() }
    $manifestHash = Hash $manifestPath
    $lock = [IO.File]::Open($dll,'Open','Read','Read')
    try { $failed = Run $Installer @() '03-locked-reinstall' } finally { $lock.Dispose() }
    Check ($failed -ne 0) 'Locked replacement reports failure'
    Check ((Hash $dll) -eq $dllHash -and (Hash $manifestPath) -eq $manifestHash) 'Locked failure preserves payload and manifest bytes'
    Check ((Run $Installer @() '04-repair') -eq 0) 'Reinstall recovers after releasing the lock'
    # These are exclusively this test's newly installed settings; no existing
    # user's disabled setting or Office security policy is modified.
    $key = $reg.OpenSubKey($addin,$true)
    try { $key.SetValue('LoadBehavior',0,[Microsoft.Win32.RegistryValueKind]::DWord); $key.SetValue('TestUnknownValue','preserve') } finally { $key.Dispose() }
    try {
        Check ((Run $Installer @() '05-disabled-preservation') -eq 0) 'Update accepts and preserves the test-owned disabled state'
        $key = $reg.OpenSubKey($addin)
        try { Check ($key.GetValue('LoadBehavior') -eq 0 -and $key.GetValue('TestUnknownValue') -eq 'preserve') 'Disabled state and unknown registry value remain unchanged' } finally { $key.Dispose() }
    } finally {
        $key = $reg.OpenSubKey($addin,$true)
        try { $key.SetValue('LoadBehavior',3,[Microsoft.Win32.RegistryValueKind]::DWord) } finally { $key.Dispose() }
    }
    Check ((Run $Installer @('--uninstall') '06-remove') -eq 0) 'Single EXE removes the migrated installation'
    Check (-not (Test-Path -LiteralPath $dll) -and -not (Test-Path -LiteralPath $manifestPath)) 'Owned DLL and ownership manifest removed'
    Check ((Get-Content -LiteralPath $unknown -Raw) -ceq 'preserve user file') 'Unknown file survives removal'
    $key = $reg.OpenSubKey($addin,$true)
    try {
        Check ($key.GetValue('TestUnknownValue') -eq 'preserve' -and $null -eq $key.GetValue('LoadBehavior')) 'Uninstall preserves unknown value and removes owned loader value'
        $key.DeleteValue('TestUnknownValue')
    } finally { $key.Dispose() }
    $reg.DeleteSubKey($addin)
    Check ((Run $Installer @('--uninstall') '07-repeat-remove') -eq 0) 'Repeated removal is idempotent'
    Check ((Safety) -eq $before) 'Other add-ins and Office settings match baseline after removal'
    Check (-not (Test-Path -LiteralPath $default)) 'Default product location was not touched by custom-path tests'
} finally {
    $reg.Dispose()
    if (Test-Path -LiteralPath $output) { [ordered]@{ checks = $checks.ToArray(); installerSha256 = Hash $Installer; releaseZipSha256 = Hash $ReleaseZip; limitations = @('Actual UI automatic load and paste/undo are separate tests.', 'Registry ACL and power failure injection not performed.', 'Only x64 Excel installed.') } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding UTF8 }
}
Write-Output "Single installer evidence: $output"
