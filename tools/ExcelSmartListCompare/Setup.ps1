# Windows PowerShell 5.1 / Windows desktop Excel.
# Trusts only this product's local install directory, without subfolders.
# No policy bypass, elevation, network calls, or process killing.
[CmdletBinding()]
param(
    [ValidateSet('Install','Build','Uninstall','Test')]
    [string]$Action = 'Install',
    # Approval includes this product directory's narrowly scoped Trusted Location.
    [ValidateSet('SLC-68A45C44-2026')]
    [string]$ConfirmProduct
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProductId = 'SLC-68A45C44-2026'
$Version = '0.2.0'
$InstallerVersion = '0.2.0-rc.2'
$Root = $PSScriptRoot
$InstallDir = Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
$Target = Join-Path $InstallDir 'ExcelSmartListCompare.xlam'
$Manifest = Join-Path $InstallDir 'install.json'
$script:Excel = $null
$script:ExcelVersion = $null
$script:ExcelProcess = $null
$script:ExcelBootstrap = $null
$script:ExcelSessionBook = $null
$mutex = $null
$acquired = $false
$script:ExitCode = 0

function Setup-Failure([string]$Message, [int]$Code = 1) {
    $failure = New-Object System.InvalidOperationException($Message)
    $failure.Data['ExitCode'] = $Code
    return $failure
}

function Release-Com([object]$Value) {
    if ($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}
function New-SessionBootstrap {
    # A new macro-free workbook gives a normal Excel process a document to open.
    # No user workbook or template is read to create it.
    Add-Type -AssemblyName System.IO.Compression
    $path = Join-Path ([IO.Path]::GetTempPath()) ('slc-session-' + [Guid]::NewGuid().ToString('N') + '.xlsx')
    $parts = [ordered]@{
        '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
        '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        'xl/workbook.xml' = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="BuildSession" sheetId="1" r:id="rId1"/></sheets></workbook>'
        'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
        'xl/worksheets/sheet1.xml' = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>'
    }
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew)
    $archive = $null
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        foreach ($name in $parts.Keys) {
            $writer = [IO.StreamWriter]::new($archive.CreateEntry($name).Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write($parts[$name]) } finally { $writer.Dispose() }
        }
    } finally { if ($null -ne $archive) { $archive.Dispose() }; $stream.Dispose() }
    return $path
}
function File-Sha256([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-', '') }
    finally { $hash.Dispose(); $stream.Dispose() }
}
function Bytes-Sha256([byte[]]$Bytes) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '') }
    finally { $hash.Dispose() }
}
function Write-PackageMetadata([string]$Path) {
    # Write product metadata without Office's default personal author identity.
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = $null
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Update, $false)
        $entry = $archive.GetEntry('docProps/core.xml')
        if ($null -ne $entry) { $entry.Delete() }
        $writer = [IO.StreamWriter]::new($archive.CreateEntry('docProps/core.xml').Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Excel Smart List Compare</dc:title><dc:creator>Excel Smart List Compare</dc:creator><cp:lastModifiedBy>Excel Smart List Compare</cp:lastModifiedBy><dc:description>Product SLC-68A45C44-2026; version 0.2.0</dc:description></cp:coreProperties>') }
        finally { $writer.Dispose() }
    } finally { if ($null -ne $archive) { $archive.Dispose() }; $stream.Dispose() }
}
function Start-OwnExcel([switch]$NormalStart) {
    # All Excel windows must already be closed by the user. Never close or kill their process.
    $active = @(Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId })
    if ($active.Count -gt 0) {
        throw (Setup-Failure '작업을 저장한 뒤 모든 Excel 창을 닫고 다시 실행해 주세요. 설치기가 Excel을 강제로 종료하지는 않습니다.' 3)
    }
    if ($NormalStart) {
        # On the tested Office build, /automation -Embedding rejects VBProject
        # even when developer access is allowed. Use normal startup and verify
        # the newly created process before any build or registration operation.
        if (-not ('SlcSetupWindowOwner' -as [type])) {
            Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SlcSetupWindowOwner {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
        }
        $pathKey = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' -ErrorAction SilentlyContinue
        if ($null -eq $pathKey) { $pathKey = Get-Item -LiteralPath 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' -ErrorAction SilentlyContinue }
        if ($null -eq $pathKey) { throw 'Excel executable registration was not found.' }
        $excelPath = [string]$pathKey.GetValue('')
        if (-not (Test-Path -LiteralPath $excelPath -PathType Leaf)) { throw 'Registered Excel executable was not found.' }
        $script:ExcelBootstrap = New-SessionBootstrap
        $script:ExcelProcess = Start-Process -FilePath $excelPath -ArgumentList @('/x', ('"' + $script:ExcelBootstrap + '"')) -WindowStyle Hidden -PassThru
        Write-Host ('Started dedicated Excel PID ' + $script:ExcelProcess.Id)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        do {
            try { $script:Excel = [Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application') }
            catch { Start-Sleep -Milliseconds 200 }
        } while ($null -eq $script:Excel -and $timer.Elapsed.TotalSeconds -lt 30 -and -not $script:ExcelProcess.HasExited)
        if ($null -eq $script:Excel) { throw ('Could not attach to the new build Excel within 30 seconds. Inspect owned PID ' + $script:ExcelProcess.Id + '. No process was killed.') }
        [uint32]$actualPid = 0
        [void][SlcSetupWindowOwner]::GetWindowThreadProcessId([IntPtr]$script:Excel.Hwnd, [ref]$actualPid)
        if ($actualPid -ne $script:ExcelProcess.Id) {
            Release-Com $script:Excel
            $script:Excel = $null
            throw 'Excel automation resolved to another process. It was not changed or closed.'
        }
        $bootstrapBook = $script:Excel.Workbooks.Item([IO.Path]::GetFileName($script:ExcelBootstrap))
        try { $bootstrapBook.Close($false) } finally { Release-Com $bootstrapBook }
    } else { $script:Excel = New-Object -ComObject Excel.Application }
    $script:Excel.Visible = $false
    $script:Excel.UserControl = $false
    # Explicitly respect the user's macro security; COM defaults must not weaken it.
    $script:Excel.AutomationSecurity = 2 # msoAutomationSecurityByUI
    $script:ExcelVersion = [string]$script:Excel.Version
}
function Stop-OwnExcel {
    if ($null -ne $script:Excel) {
        if ($null -ne $script:ExcelSessionBook) {
            try { $script:ExcelSessionBook.Close($false) } finally {
                Release-Com $script:ExcelSessionBook
                $script:ExcelSessionBook = $null
            }
        }
        try { $script:Excel.Quit() } finally {
            Release-Com $script:Excel
            $script:Excel = $null
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
        }
    }
    if ($null -ne $script:ExcelProcess) {
        if (-not $script:ExcelProcess.WaitForExit(5000)) { Write-Warning ('Owned build Excel PID ' + $script:ExcelProcess.Id + ' remains after normal Quit; no process was killed.') }
        $script:ExcelProcess.Dispose()
        $script:ExcelProcess = $null
    }
    if ($null -ne $script:ExcelBootstrap -and (Test-Path -LiteralPath $script:ExcelBootstrap)) {
        Remove-Item -LiteralPath $script:ExcelBootstrap -Force
        $script:ExcelBootstrap = $null
    }
}
function Read-OwnManifest {
    if (-not (Test-Path -LiteralPath $Manifest)) { return $null }
    $data = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.productId -ne $ProductId -or $data.installDirectory -ne $InstallDir) {
        throw 'The installation marker is not owned by this product. No files were changed.'
    }
    return $data
}
function Confirm-Action([string]$Message) {
    if ($ConfirmProduct -eq $ProductId) { return $true }
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show($Message, 'Excel Smart List Compare',
        [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question,
        [Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { $script:ExitCode = 2; return $false }
    return $true
}
function Build-Addin {
    $src = Join-Path $Root 'src'
    if (-not (Test-Path -LiteralPath (Join-Path $src 'modSLCMain.bas'))) {
        throw 'No prebuilt XLAM or source files were found. Obtain the built release package.'
    }
    $dist = Join-Path $Root 'dist'
    [void](New-Item -ItemType Directory -Path $dist -Force)
    $output = Join-Path $dist 'ExcelSmartListCompare.xlam'
    $temporary = Join-Path $dist ('slc-build-' + [Guid]::NewGuid().ToString('N') + '.xlam')
    $book = $null
    $project = $null
    $component = $null
    try {
        $book = $script:Excel.Workbooks.Add(-4167) # xlWBATWorksheet
        try {
            # PowerShell's COM property adapter can turn Excel's access-denied
            # exception into null. Invoke explicitly to preserve the real cause.
            $project = $book.GetType().InvokeMember('VBProject', [Reflection.BindingFlags]::GetProperty, $null, $book, $null)
            $null = $project.VBComponents.Count
        } catch {
            $cause = $_.Exception
            while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
            $detail = $cause.Message.Trim() + (' (HRESULT 0x{0:X8})' -f $cause.HResult)
            throw (Setup-Failure ('Source build needs Excel VBA project access permitted by your organization. ' +
                'Setup does not enable it or modify Trust Center. Ask an authorized developer to run Build_Release.cmd ' +
                'and provide the Release folder containing the XLAM. End-user installation of that release does not need VBA project access. Excel detail: ' + $detail) 5)
        }
        foreach ($file in @('CSLCList.cls','modSLCNormalize.bas','modSLCMain.bas')) {
            $component = $project.VBComponents.Import((Join-Path $src $file))
            Release-Com $component
            $component = $null
        }
        $component = $project.VBComponents.Item($book.CodeName)
        # Only the newly created workbook is edited; avoid duplicate Option Explicit.
        if ($component.CodeModule.CountOfLines -gt 0) {
            $component.CodeModule.DeleteLines(1, $component.CodeModule.CountOfLines)
        }
        $component.CodeModule.AddFromString((Get-Content -LiteralPath (Join-Path $src 'ThisWorkbook_events.txt') -Raw -Encoding ASCII))
        Release-Com $component
        $component = $null
        $project.Name = 'SLC2026'
        Release-Com $project
        $project = $null
        # Ownership and version are verified through the manifest and VBA entry
        # point. Optional Office document properties are not needed for either.
        $book.IsAddin = $true
        $book.SaveAs($temporary, 55) # xlOpenXMLAddIn
        # Saving as an add-in can leave the source workbook in its original
        # format. Close it without another Save, then test the serialized XLAM.
        $book.Close($false)
        Release-Com $book
        $book = $null
        Write-PackageMetadata $temporary
        $book = $script:Excel.Workbooks.Open($temporary, 0, $true)
        Write-Host ('Testing saved XLAM: ' + $book.Name + '; format ' + $book.FileFormat)
        # Run entry points to make Excel compile the saved modules and test them.
        $q = "'" + ([string]$book.Name).Replace("'", "''") + "'!"
        $reported = [string]$script:Excel.Run($q + 'SLC_Version')
        if ($reported -ne $Version) { throw 'The built add-in reported an unexpected version.' }
        $testResult = [string]$script:Excel.Run($q + 'SLC_TestAll')
        if (-not $testResult.StartsWith('PASS:')) { throw ('Excel tests failed: ' + $testResult) }
        Write-Host $testResult
        # Validate the UI entry point as well. Runtime shutdown removes only our own controls.
        $null = $script:Excel.Run($q + 'SLC_AttachUI')
        if (-not [bool]$script:Excel.Run($q + 'SLC_UiReady')) { throw 'Excel could not register the comparison menu.' }
        $null = $script:Excel.Run($q + 'SLC_DetachUI')
        $book.Close($false)
        Release-Com $book
        $book = $null
        Move-Item -LiteralPath $temporary -Destination $output -Force
        $release = Join-Path $Root 'Release'
        [void](New-Item -ItemType Directory -Path $release -Force)
        Copy-Item -LiteralPath $output -Destination (Join-Path $release 'ExcelSmartListCompare.xlam') -Force
        foreach ($file in @('Setup.ps1','Install.cmd','Uninstall.cmd','Test_Excel.cmd','README.md')) {
            Copy-Item -LiteralPath (Join-Path $Root $file) -Destination (Join-Path $release $file) -Force
        }
        $userReadme = Join-Path $Root 'docs\RELEASE_README.md'
        if (Test-Path -LiteralPath $userReadme) { Copy-Item -LiteralPath $userReadme -Destination (Join-Path $release 'README.md') -Force }
        ($testResult + "`r`nBuilt with Excel " + $script:ExcelVersion + "`r`n" + (Get-Date).ToString('o')) |
            Set-Content -LiteralPath (Join-Path $release 'EXCEL_TEST_RESULT.txt') -Encoding UTF8
        # This generated marker is obsolete only after the real build/tests succeeded.
        $blockedMarker = Join-Path $release 'BUILD_BLOCKED.txt'
        if (Test-Path -LiteralPath $blockedMarker) { Remove-Item -LiteralPath $blockedMarker -Force }
        return $output
    } finally {
        if ($null -ne $book) { try { $book.Close($false) } catch {}; Release-Com $book }
        Release-Com $component
        Release-Com $project
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
function Find-OwnAddin {
    $addins = $script:Excel.AddIns
    try {
        for ($i = 1; $i -le $addins.Count; $i++) {
            $item = $addins.Item($i)
            if ([string]$item.FullName -ieq $Target) { return $item }
            Release-Com $item
        }
    } finally { Release-Com $addins }
    return $null
}
function Excel-RegistrationVersion {
    $key = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' -ErrorAction SilentlyContinue
    if ($null -eq $key) { $key = Get-Item -LiteralPath 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' -ErrorAction SilentlyContinue }
    if ($null -eq $key) { throw 'Windows desktop Excel was not found.' }
    $path = [string]$key.GetValue('')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Registered Excel executable is missing.' }
    return ([Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileMajorPart.ToString() + '.0')
}
function Own-OpenEntries($Key) {
    $entries = @{}
    foreach ($name in $Key.GetValueNames()) {
        if ($name -match '^OPEN\d*$') {
            $value = [string]$Key.GetValue($name)
            if ($value -ieq ('"' + $Target + '"') -or $value -ieq $Target) { $entries[$name] = $value }
        }
    }
    return $entries
}
function Excel-UserPath([string]$OfficeVersion) {
    return ('Software\Microsoft\Office\' + $OfficeVersion + '\Excel')
}
function Trust-RootPath([string]$OfficeVersion) {
    return ((Excel-UserPath $OfficeVersion) + '\Security\Trusted Locations')
}
function Test-TrustPolicyBlocked($Key) {
    return ($Key.GetValue('alllocationsdisabled',0) -eq 1 -or $Key.GetValue('allow user locations',1) -eq 0)
}
function Assert-TrustPolicy([string]$OfficeVersion) {
    # Office ADMX: alllocationsdisabled (Excel), allow user locations (Common).
    # Read preferences, Group Policy and Cloud Policy; never write policy values.
    foreach ($hive in @([Microsoft.Win32.Registry]::CurrentUser,[Microsoft.Win32.Registry]::LocalMachine)) {
        foreach ($prefix in @('Software\Microsoft\Office\','Software\Policies\Microsoft\Office\','Software\Policies\Microsoft\Cloud\Office\')) {
            foreach ($app in @('Excel','Common')) {
                $key = $hive.OpenSubKey(($prefix+$OfficeVersion+'\'+$app+'\Security\Trusted Locations'))
                if ($null -eq $key) { continue }
                try {
                    if (Test-TrustPolicyBlocked $key) {
                        throw (Setup-Failure 'Excel 설정 또는 조직 정책에서 사용자 신뢰 위치를 차단했습니다. 정책은 변경하지 않았습니다. IT 담당자에게 이 제품 폴더의 승인된 배포를 요청하세요.' 6)
                    }
                } finally { $key.Close() }
            }
        }
    }
}
function Trust-Values($Record) {
    return [ordered]@{SLCProductId=$ProductId;SLCOwnerToken=[string]$Record.token;Description='Excel Smart List Compare';AllowSubfolders=0;Path=($InstallDir.TrimEnd('\')+'\')}
}
function Test-OwnTrustKey($Key, $Record, [switch]$Partial) {
    if ($null -eq $Key -or $Key.SubKeyCount -ne 0) { return $false }
    $values = Trust-Values $Record
    $names = @($Key.GetValueNames())
    if (-not $Partial -and $names.Count -ne $values.Count) { return $false }
    # The owner token is written before Path, including interrupted activation.
    if ([string]$Key.GetValue('SLCOwnerToken','') -cne [string]$Record.token) { return $false }
    foreach ($name in $names) {
        if (-not $values.Contains($name)) { return $false }
        $kind = if ($name -eq 'AllowSubfolders') { 'DWord' } else { 'String' }
        if ([string]$Key.GetValueKind($name) -ne $kind -or [string]$Key.GetValue($name) -cne [string]$values[$name]) { return $false }
    }
    return $true
}
function Plan-TrustedLocation([string]$OfficeVersion, $OldManifest) {
    Assert-TrustPolicy $OfficeVersion
    if ($InstallDir.StartsWith('\\') -or ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($InstallDir))).DriveType -ne 'Fixed') { throw 'Automatic trust requires a local fixed disk.' }
    if ((Test-Path -LiteralPath $InstallDir) -and ((Get-Item -LiteralPath $InstallDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'A redirected product directory cannot be automatically trusted.' }
    $path = Trust-RootPath $OfficeVersion
    $parent = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
    try {
        if ($null -ne $OldManifest -and $null -ne $OldManifest.PSObject.Properties['trustedLocation'] -and $null -ne $OldManifest.trustedLocation -and $OldManifest.trustedLocation.owned) {
            $record = $OldManifest.trustedLocation
            if ($OldManifest.excelVersion -ne $OfficeVersion -or [string]$record.keyName -notmatch '^Location\d+$' -or [string]$record.token -notmatch '^[a-f0-9]{32}$') { throw 'Invalid or different Office Trusted Location ownership record; remove the previous installation first.' }
            $key = if ($null -ne $parent) { $parent.OpenSubKey([string]$record.keyName) } else { $null }
            if ($null -ne $key) {
                try { if (-not (Test-OwnTrustKey $key $record)) { throw 'The product Trusted Location was externally changed. It was preserved. Remove the product and review that location before reinstalling.' } }
                finally { $key.Close() }
                return [pscustomobject]@{record=$record;create=$false}
            }
        }
        if ($null -ne $parent) {
            foreach ($name in $parent.GetSubKeyNames()) {
                $key = $parent.OpenSubKey($name)
                try {
                    $existing = [Environment]::ExpandEnvironmentVariables([string]$key.GetValue('Path','')).TrimEnd('\')
                    if ($existing -ieq $InstallDir.TrimEnd('\')) {
                        return [pscustomobject]@{record=[pscustomobject]@{owned=$false;keyName=$name};create=$false}
                    }
                } finally { $key.Close() }
            }
        }
        # New trust must not silently enable unrelated files already in this folder.
        if (Test-Path -LiteralPath $InstallDir) {
            $other = @(Get-ChildItem -LiteralPath $InstallDir -Force | Where-Object { $_.PSIsContainer -or $_.Name -notin @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json') })
            if ($other.Count) { throw 'The product directory contains additional files. Move those files yourself before automatically trusting this directory.' }
        }
        $index = 0
        $names = if ($null -ne $parent) { @($parent.GetSubKeyNames()) } else { @() }
        do { $name = 'Location'+$index; $index++ } while ($names -contains $name)
        $security = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(((Excel-UserPath $OfficeVersion)+'\Security'))
        $securityCreated = $null -eq $security
        if ($null -ne $security) { $security.Close() }
        return [pscustomobject]@{record=[pscustomobject]@{owned=$true;keyName=$name;token=[Guid]::NewGuid().ToString('N');rootCreated=($null -eq $parent);securityCreated=$securityCreated};create=$true}
    } finally { if ($null -ne $parent) { $parent.Close() } }
}
function New-ExclusiveRegistryKey($Parent, [string]$Name) {
    # RegCreateKeyEx disposition prevents taking ownership of a concurrently added key.
    if (-not ('SlcRegistryCreate' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class SlcRegistryCreate {
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode)]
    public static extern int RegCreateKeyEx(SafeRegistryHandle parent, string name, int reserved,
        string cls, int options, int access, IntPtr security, out SafeRegistryHandle key, out int disposition);
}
'@
    }
    $handle = $null; [int]$disposition = 0
    $errorCode = [SlcRegistryCreate]::RegCreateKeyEx($Parent.Handle,$Name,0,$null,0,0x2001f,[IntPtr]::Zero,[ref]$handle,[ref]$disposition)
    if ($errorCode -ne 0) { throw ([ComponentModel.Win32Exception]::new($errorCode)) }
    if ($disposition -ne 1) { $handle.Dispose(); throw 'Trusted Location key appeared concurrently. The external key was preserved; retry installation.' }
    return [Microsoft.Win32.RegistryKey]::FromHandle($handle,$Parent.View)
}
function Enable-TrustedLocation([string]$OfficeVersion, $Plan) {
    Assert-TrustPolicy $OfficeVersion
    if (-not $Plan.create) {
        $existing = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(((Trust-RootPath $OfficeVersion)+'\'+$Plan.record.keyName))
        try {
            if ($null -eq $existing) { throw 'Trusted Location disappeared during installation.' }
            if ($Plan.record.owned) { if (-not (Test-OwnTrustKey $existing $Plan.record)) { throw 'Trusted Location changed during installation; the external change was preserved.' } }
            elseif ([Environment]::ExpandEnvironmentVariables([string]$existing.GetValue('Path','')).TrimEnd('\') -ine $InstallDir.TrimEnd('\')) { throw 'Existing Trusted Location changed during installation.' }
        } finally { if ($null -ne $existing) { $existing.Close() } }
        return
    }
    $parent = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey((Trust-RootPath $OfficeVersion))
    $key = $null
    try {
        $key = New-ExclusiveRegistryKey $parent ([string]$Plan.record.keyName)
        $Plan | Add-Member -NotePropertyName created -NotePropertyValue $true -Force
        # Manifest is already committed. Write the identity first and Path last.
        $key.SetValue('SLCOwnerToken',[string]$Plan.record.token,[Microsoft.Win32.RegistryValueKind]::String)
        $values = Trust-Values $Plan.record
        foreach ($name in $values.Keys) {
            $kind = if ($name -eq 'AllowSubfolders') { [Microsoft.Win32.RegistryValueKind]::DWord } else { [Microsoft.Win32.RegistryValueKind]::String }
            $key.SetValue($name,$values[$name],$kind)
        }
        $key.Flush()
        if (-not (Test-OwnTrustKey $key $Plan.record)) { throw 'Trusted Location verification failed.' }
    } finally { if ($null -ne $key) { $key.Close() }; $parent.Close() }
}
function Remove-OwnedTrustedLocation([string]$OfficeVersion, $Record) {
    if ($null -eq $Record -or -not $Record.owned) { return }
    if ([string]$Record.keyName -notmatch '^Location\d+$' -or [string]$Record.token -notmatch '^[a-f0-9]{32}$') { throw 'Invalid Trusted Location ownership record.' }
    $path = Trust-RootPath $OfficeVersion
    $parent = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path,$true)
    if ($null -eq $parent) { return }
    try {
        $key = $parent.OpenSubKey([string]$Record.keyName)
        if ($null -ne $key) {
            try { $owned = Test-OwnTrustKey $key $Record -Partial } finally { $key.Close() }
            if ($owned) { $parent.DeleteSubKey([string]$Record.keyName,$false) }
            else { Write-Warning 'Externally changed Trusted Location preserved; review it in Excel Trust Center.' }
        }
        $empty = $parent.ValueCount -eq 0 -and $parent.SubKeyCount -eq 0
    } finally { $parent.Close() }
    if ($Record.rootCreated -and $empty) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($path,$false) }
    if ($Record.securityCreated) {
        $securityPath = (Excel-UserPath $OfficeVersion)+'\Security'
        $security = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($securityPath)
        if ($null -ne $security) {
            try { $empty = $security.ValueCount -eq 0 -and $security.SubKeyCount -eq 0 } finally { $security.Close() }
            if ($empty) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($securityPath,$false) }
        }
    }
}
function Install-Addin {
    $oldManifest = Read-OwnManifest
    $ownedFiles = @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json')
    if ($null -eq $oldManifest) {
        foreach ($name in $ownedFiles) {
            if (Test-Path -LiteralPath (Join-Path $InstallDir $name)) { throw 'An unrecognized file already exists at the install path. It was not overwritten.' }
        }
    }
    if (-not (Confirm-Action ('현재 Windows 사용자에게 명단 비교 기능을 설치할까요?' + "`r`n`r`n" +
        '제품 파일과 자동 로드를 등록하고 아래 폴더만 Excel 신뢰 위치로 추가합니다(하위 폴더 제외).' + "`r`n" + $InstallDir + "`r`n" +
        '이 폴더 안의 파일은 매크로 알림 없이 실행될 수 있습니다. 제품 파일만 보관하세요.'))) { return }
    $payload = Join-Path $Root 'ExcelSmartListCompare.xlam'
    if (-not (Test-Path -LiteralPath $payload)) { $payload = Join-Path $Root 'dist\ExcelSmartListCompare.xlam' }
    if (-not (Test-Path -LiteralPath $payload)) { throw 'Install requires the built Release folder. Build_Release.cmd is for authorized developers.' }
    $payloadHash = File-Sha256 $payload
    $officeVersion = Excel-RegistrationVersion
    $trustPlan = Plan-TrustedLocation $officeVersion $oldManifest
    $optionPath = (Excel-UserPath $officeVersion) + '\Options'
    $options = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($optionPath)
    $before = Own-OpenEntries $options
    $backup = @{}
    $written = @{}
    foreach ($name in $ownedFiles) {
        $file = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $file -PathType Leaf) { $backup[$name] = [IO.File]::ReadAllBytes($file) }
    }
    $temporary = $null
    try {
        [void](New-Item -ItemType Directory -Path $InstallDir -Force)
        Copy-Item -LiteralPath $payload -Destination $Target -Force
        $written['ExcelSmartListCompare.xlam'] = $payloadHash
        foreach ($name in @('Setup.ps1','Uninstall.cmd','README.md')) {
            $source = Join-Path $Root $name
            $destination = Join-Path $InstallDir $name
            if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($destination)) { Copy-Item -LiteralPath $source -Destination $destination -Force; $written[$name] = File-Sha256 $destination }
        }
        if ((File-Sha256 $Target) -ne $payloadHash) { throw 'Copied XLAM hash mismatch.' }
        $names = @($before.Keys | Sort-Object)
        if ($names.Count) { $openName = $names[0] }
        else {
            $index = 0
            do { $openName = if ($index -eq 0) { 'OPEN' } else { 'OPEN' + $index }; $index++ } while ($options.GetValueNames() -contains $openName)
        }
        # Commit ownership before registration so an interrupted install is removable.
        $data = [ordered]@{productId=$ProductId;version=$Version;installerVersion=$InstallerVersion;installDirectory=$InstallDir;installedAt=(Get-Date).ToString('o');excelVersion=$officeVersion;sha256=$payloadHash;openValueName=$openName;ownedFiles=$ownedFiles;trustedLocation=$trustPlan.record}
        $temporary = Join-Path $InstallDir ('slc-install-' + [Guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($temporary, ($data | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($true))
        if (Test-Path -LiteralPath $Manifest) { [IO.File]::Replace($temporary,$Manifest,[NullString]::Value) } else { [IO.File]::Move($temporary,$Manifest) }
        $temporary = $null
        $written['install.json'] = File-Sha256 $Manifest
        Enable-TrustedLocation $officeVersion $trustPlan
        $current = $options.GetValue($openName,$null)
        if ($null -ne $current -and [string]$current -ine ('"'+$Target+'"') -and [string]$current -ine $Target) { throw 'Excel registration changed concurrently; the external value was preserved.' }
        $options.SetValue($openName,('"'+$Target+'"'),[Microsoft.Win32.RegistryValueKind]::String)
        foreach ($duplicate in $names) { if ($duplicate -ne $openName -and (Own-OpenEntries $options).ContainsKey($duplicate)) { $options.DeleteValue($duplicate,$false) } }
        $options.Flush()
        if ([string]$options.GetValue($openName) -cne ('"'+$Target+'"')) { throw 'Excel registration verification failed.' }
        Write-Host '설치했습니다. Excel을 열어 추가 기능 탭 또는 셀 우클릭의 명단 비교를 사용하세요.'
        Write-Host ('Excel 신뢰 위치: ' + $InstallDir + ' (기존 항목은 보존합니다.)')
        Write-Host ('Uninstall: ' + (Join-Path $InstallDir 'Uninstall.cmd'))
    } catch {
        if ($null -ne $trustPlan.PSObject.Properties['created'] -and $trustPlan.created) { Remove-OwnedTrustedLocation $officeVersion $trustPlan.record }
        # Roll back only this exact product path; preserve unrelated OPEN values.
        foreach ($name in @((Own-OpenEntries $options).Keys)) { $options.DeleteValue($name,$false) }
        foreach ($name in $before.Keys) {
            if ($null -eq $options.GetValue($name,$null)) { $options.SetValue($name,$before[$name],[Microsoft.Win32.RegistryValueKind]::String) }
        }
        foreach ($name in $ownedFiles) {
            $file = Join-Path $InstallDir $name
            $currentHash = if (Test-Path -LiteralPath $file -PathType Leaf) { File-Sha256 $file } else { $null }
            if ($backup.ContainsKey($name)) {
                if ($currentHash -eq (Bytes-Sha256 $backup[$name])) { continue }
                if ($null -ne $currentHash -and (-not $written.ContainsKey($name) -or $currentHash -ne $written[$name])) { Write-Warning ('Externally changed file preserved during rollback: '+$name); continue }
                [IO.File]::WriteAllBytes($file,$backup[$name])
            } elseif ($null -ne $currentHash -and $written.ContainsKey($name) -and $currentHash -eq $written[$name]) { Remove-Item -LiteralPath $file -Force }
        }
        throw
    } finally {
        $options.Close()
        if ($null -ne $temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force }
    }
}
function Uninstall-Addin {
    $data = Read-OwnManifest
    if ($null -eq $data) { Write-Host 'No owned installation found. No files or other add-ins were changed.'; return }
    if (-not (Confirm-Action ('Excel 명단 비교 기능만 삭제할까요?' + "`r`n`r`n" + '기존 통합문서와 다른 추가 기능은 삭제하지 않습니다.'))) { return }
    $version = [string]$data.excelVersion
    if ($version -notmatch '^\d+\.0$') { throw 'Invalid owned Excel registration version.' }
    if ($null -ne $data.PSObject.Properties['trustedLocation']) { Remove-OwnedTrustedLocation $version $data.trustedLocation }
    $options = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(((Excel-UserPath $version)+'\Options'),$true)
    if ($null -ne $options) {
        try { foreach ($name in @((Own-OpenEntries $options).Keys)) { $options.DeleteValue($name,$false) }; $options.Flush() }
        finally { $options.Close() }
    }
    $manager = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(((Excel-UserPath $version)+'\Add-in Manager'),$true)
    if ($null -ne $manager) { try { foreach ($name in $manager.GetValueNames()) { if ($name -ieq $Target) { $manager.DeleteValue($name,$false) } } } finally { $manager.Close() } }
    foreach ($name in @('ExcelSmartListCompare.xlam','README.md','Uninstall.cmd','Setup.ps1','install.json')) {
        $file = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
    }
    if ((Get-ChildItem -LiteralPath $InstallDir -Force | Measure-Object).Count -eq 0) { Remove-Item -LiteralPath $InstallDir -Force }
    else { Write-Host 'Additional files were left untouched in the installation directory.' }
    Write-Host '삭제했습니다. 통합문서와 다른 추가 기능은 변경하지 않았습니다.'
}

function Test-Addin {
    $file = $Target
    if (-not (Test-Path -LiteralPath $file)) { $file = Join-Path $Root 'dist\ExcelSmartListCompare.xlam' }
    if (-not (Test-Path -LiteralPath $file)) { $file = Join-Path $Root 'ExcelSmartListCompare.xlam' }
    if (-not (Test-Path -LiteralPath $file)) { throw 'Build or install the add-in before running Excel tests.' }
    $book = $null
    try {
        Start-OwnExcel -NormalStart
        # Loaded add-ins need not appear in Workbooks enumeration.
        # Resolve the exact name and verify its path before opening it again.
        try { $book = $script:Excel.Workbooks.Item([IO.Path]::GetFileName($file)) } catch {}
        if ($null -ne $book -and [string]$book.FullName -ine $file) { Release-Com $book; $book = $null }
        if ($null -eq $book) { $book = $script:Excel.Workbooks.Open($file, 0, $true) }
        $q = "'" + ([string]$book.Name).Replace("'", "''") + "'!"
        $result = [string]$script:Excel.Run($q + 'SLC_TestAll')
        if (-not $result.StartsWith('PASS:')) { throw $result }
        Write-Host $result
    } finally { Release-Com $book; Stop-OwnExcel }
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows desktop Excel is required.' }
    $mutex = New-Object Threading.Mutex($false, 'Local\ExcelSmartListCompare-Setup')
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { throw (Setup-Failure 'Another setup or removal is already running.' 4) }
    $active = @(Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId })
    if ($active.Count -gt 0) { throw (Setup-Failure '작업을 저장한 뒤 모든 Excel 창을 닫고 다시 실행해 주세요. 다른 프로그램은 종료하지 않습니다.' 3) }
    switch ($Action) {
        'Build' {
            Start-OwnExcel -NormalStart
            $built = Build-Addin
            Write-Host ('Built: ' + $built)
            Write-Host 'Distribute the Release folder; end users run Install.cmd once.'
        }
        'Install' { Install-Addin }
        'Uninstall' { Uninstall-Addin }
        'Test' { Test-Addin }
    }
} catch {
    Write-Host ('Setup failure location: ' + $_.ScriptStackTrace)
    Write-Error $_ -ErrorAction Continue
    Write-Host 'No security policy was bypassed. If macros or PowerShell are blocked, use your approved IT distribution process.'
    $script:ExitCode = 1
    if ($_.Exception.Data.Contains('ExitCode')) { $script:ExitCode = [int]$_.Exception.Data['ExitCode'] }
} finally {
    Stop-OwnExcel
    if ($acquired -and $null -ne $mutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $script:ExitCode
