[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$session = (Get-Process -Id $PID).SessionId
$explorer = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Where-Object SessionId -eq $session)
$owners = @($explorer | ForEach-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid).Sid })
$registry = [ordered]@{}
foreach ($hive in @('HKCU','HKLM')) {
    foreach ($branch in @('Software/Microsoft/Office/16.0/Excel/Options','Software/Microsoft/Office/16.0/Excel/Add-in Manager','Software/Microsoft/Office/Excel/Addins','Software/Microsoft/Office/16.0/Excel/Security','Software/Policies/Microsoft/Office/16.0/Excel','Software/Microsoft/PowerShell/1/ShellIds/Microsoft.PowerShell','Software/Policies/Microsoft/Windows/PowerShell')) {
        $path = $hive + ':/' + $branch
        $entries = @()
        if (Test-Path -LiteralPath $path) {
            $keys = @((Get-Item -LiteralPath $path)) + @(Get-ChildItem -LiteralPath $path -Recurse)
            foreach ($key in $keys) {
                foreach ($name in $key.GetValueNames()) {
                    $entries += [ordered]@{key=$key.Name; name=$name; kind=[string]$key.GetValueKind($name); value=$key.GetValue($name)}
                }
            }
        }
        $registry[$path] = $entries
    }
}
$productDir = Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
$files = @()
if (Test-Path -LiteralPath $productDir) {
    $files = @(Get-ChildItem -LiteralPath $productDir -File | ForEach-Object { [ordered]@{name=$_.Name; length=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
}
$excelPathKey = Get-Item -LiteralPath 'HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/App Paths/excel.exe' -ErrorAction SilentlyContinue
$excelPath = if ($excelPathKey) { [string]$excelPathKey.GetValue('') } else { $null }
$machine = $null
if ($excelPath -and (Test-Path -LiteralPath $excelPath)) {
    $stream = [IO.File]::OpenRead($excelPath)
    $reader = New-Object IO.BinaryReader($stream)
    try { $stream.Position=0x3c; $offset=$reader.ReadInt32(); $stream.Position=$offset+4; $machine=('0x{0:X4}' -f $reader.ReadUInt16()) } finally { $reader.Dispose(); $stream.Dispose() }
}
$os = Get-CimInstance Win32_OperatingSystem
$data = [ordered]@{
    timestamp=(Get-Date).ToString('o'); platform=$env:OS; osVersion=$os.Version; osCaption=$os.Caption
    powershell=[string]$PSVersionTable.PSVersion; processPath=(Get-Process -Id $PID).Path
    identity=$identity.Name; sid=$identity.User.Value; profile=$env:USERPROFILE; localAppData=$env:LOCALAPPDATA
    sessionId=$session; explorerSids=$owners; sameDesktopAccount=($owners -contains $identity.User.Value)
    elevated=([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    executionPolicy=@(Get-ExecutionPolicy -List | Select-Object Scope,ExecutionPolicy)
    excelExecutable=$excelPath; excelPEMachine=$machine; excelFileVersion=if($excelPath){(Get-Item -LiteralPath $excelPath).VersionInfo.FileVersion}else{$null}
    excelProcesses=@(Get-Process EXCEL -ErrorAction SilentlyContinue | Select-Object Id,SessionId,StartTime,Path)
    productDirectoryExists=(Test-Path -LiteralPath $productDir); productFiles=$files; registry=$registry
}
$parent = Split-Path -Parent $OutputPath
[void](New-Item -ItemType Directory -Path $parent -Force)
$data | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
[pscustomobject]$data | Select-Object timestamp,platform,osVersion,powershell,sameDesktopAccount,elevated,excelPEMachine,excelFileVersion,productDirectoryExists | Format-List
