[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string]$Version = '0.1.0-rc.10',
    [string]$InnoCompiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output = Join-Path $repo ('artifacts\selection-export\activation-failure-' + [Guid]::NewGuid().ToString('N'))
$installed = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Workspace\ExcelSelectionExport'
$classPath = 'Software\Classes\CLSID\{2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1}'
if (-not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) { throw 'Supply the installed Inno compiler with -InnoCompiler.' }
$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', [Microsoft.Win32.RegistryView]::Registry64)
try {
    $key = $base.OpenSubKey($classPath)
    try { if ($key -or (Test-Path -LiteralPath $installed)) { throw 'Preserve existing installation; this failure test requires no SelectionExport installation.' } }
    finally { if ($key) { $key.Dispose() } }
} finally { $base.Dispose() }
if (@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Save work and close Excel before this serial failure test.' }
$payload = Join-Path $output 'fault-payload'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
foreach ($name in @('SetupProbe.exe','README.md','CHANGELOG.md','product.id')) {
    Copy-Item -LiteralPath (Join-Path $PackageDirectory "x64\$name") -Destination (Join-Path $payload $name)
}
# Only the isolated test package is damaged. Never alter an existing installed DLL.
[IO.File]::WriteAllText((Join-Path $payload 'ExcelSelectionExport.AddIn.dll'), 'TEST ONLY - intentionally invalid assembly')
$checks = New-Object 'System.Collections.Generic.List[object]'
function Check([bool]$Ok, [string]$Name) {
    $checks.Add([ordered]@{ name = $Name; passed = $Ok })
    if (-not $Ok) { throw "FAIL: $Name" }
    Write-Output "PASS: $Name"
}
function Run([string]$File, [string[]]$Arguments, [string]$Label) {
    $quoted = @($Arguments | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' })
    $process = Start-Process -FilePath $File -ArgumentList $quoted -WindowStyle Hidden -PassThru
    try {
        if (-not $process.WaitForExit(120000)) { throw "$Label did not finish; left running for inspection, no forced termination." }
        return $process.ExitCode
    } finally { $process.Dispose() }
}
function Install([string]$File, [string]$Label) {
    return Run $File @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG=' + (Join-Path $output "$Label.log"))) $Label
}
try {
    & (Join-Path $PSScriptRoot 'Test-Package.ps1') -Action Snapshot -OutputDirectory (Join-Path $output 'before')
    $source = Join-Path $PSScriptRoot '..\installer\SelectionExport.iss'
    $compile = Run $InnoCompiler @('/Q',("/DPayloadDir=$payload"),("/DProductVersion=$Version"),'/DArch=x64',("/O$output"),'/FTEST-ONLY-invalid-payload', $source) 'compile fault package'
    Check ($compile -eq 0) 'Isolated invalid-payload test installer compiled'
    $failure = Install (Join-Path $output 'TEST-ONLY-invalid-payload.exe') 'activation-failure'
    Check ($failure -eq 30) 'Post-install activation failure reports exit 30, never success'
    Check ((Get-Content -LiteralPath (Join-Path $output 'activation-failure.log') -Raw) -match 'INSTALL VALIDATION FAILED') 'Failure log identifies installed but unvalidated state'
    Check (Test-Path -LiteralPath (Join-Path $installed 'unins000.exe')) 'Failed activation leaves an explicit uninstall recovery path'
    $valid = Join-Path $PackageDirectory "ExcelSelectionExport-$Version-x64-Setup.exe"
    Check ((Install $valid 'repair-valid-payload') -eq 0) 'Valid installer repairs the failed activation state'
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $PackageDirectory 'x64\ExcelSelectionExport.AddIn.dll')).Hash
    Check ((Get-FileHash -LiteralPath (Join-Path $installed "versions\$Version\x64\ExcelSelectionExport.AddIn.dll")).Hash -eq $sourceHash) 'Repair restores exact product DLL bytes'
    Check ((Install (Join-Path $installed 'unins000.exe') 'remove') -eq 0) 'Repaired test installation uninstalls normally'
    # The uninstall launcher can return before its temporary helper removes the
    # launcher directory. Observe bounded completion; never delete it ourselves.
    $wait = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-Path -LiteralPath $installed) -and $wait.ElapsedMilliseconds -lt 10000) { Start-Sleep -Milliseconds 100 }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $base.OpenSubKey($classPath)
        try { Check (-not $key -and -not (Test-Path -LiteralPath $installed)) 'Final product registration and directory absent' }
        finally { if ($key) { $key.Dispose() } }
    } finally { $base.Dispose() }
    & (Join-Path $PSScriptRoot 'Test-Package.ps1') -Action Compare -Baseline (Join-Path $output 'before\safety-snapshot.json') -OutputDirectory (Join-Path $output 'after')
    Check $true 'Security and other add-in registrations preserved across activation failure and repair'
} finally {
    [ordered]@{ version = $Version; checks = $checks.ToArray(); limitations = @('Intentional invalid assembly exercises COM activation failure, not registry ACL denial.', 'Hard interruption and power failure are not exercised.', 'No real user documents or security settings are changed.') } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding UTF8
}
Write-Output "Activation failure evidence: $output"
