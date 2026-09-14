# Windows PowerShell 5.1 / Windows desktop Excel.
# No policy bypass, elevation, trust-location changes, network calls, or process killing.
[CmdletBinding()]
param(
    [ValidateSet('Install','Build','Uninstall','Test')]
    [string]$Action = 'Install',
    # Explicit approval of this product only; never suppresses an Office security prompt.
    [ValidateSet('SLC-68A45C44-2026')]
    [string]$ConfirmProduct
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProductId = 'SLC-68A45C44-2026'
$Version = '0.2.0'
$Root = $PSScriptRoot
$InstallDir = Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
$Target = Join-Path $InstallDir 'ExcelSmartListCompare.xlam'
$Manifest = Join-Path $InstallDir 'install.json'
$script:Excel = $null
$script:ExcelVersion = $null
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
function Start-OwnExcel {
    # All Excel windows must already be closed by the user. Never close or kill their process.
    $active = @(Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId })
    if ($active.Count -gt 0) {
        throw (Setup-Failure '작업을 저장한 뒤 모든 Excel 창을 닫고 다시 실행해 주세요. 설치기가 Excel을 강제로 종료하지는 않습니다.' 3)
    }
    $script:Excel = New-Object -ComObject Excel.Application
    $script:Excel.Visible = $false
    # Explicitly respect the user's macro security; COM defaults must not weaken it.
    $script:Excel.AutomationSecurity = 2 # msoAutomationSecurityByUI
    $script:ExcelVersion = [string]$script:Excel.Version
}
function Stop-OwnExcel {
    if ($null -ne $script:Excel) {
        try { $script:Excel.Quit() } finally {
            Release-Com $script:Excel
            $script:Excel = $null
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
        }
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
            $project = $book.VBProject
            $null = $project.VBComponents.Count
        } catch {
            throw (Setup-Failure ('Source build needs Excel VBA project access permitted by your organization. ' +
                'Setup does not enable it or modify Trust Center. Ask an authorized developer to run Build_Release.cmd ' +
                'and provide the Release folder containing the XLAM. End-user installation of that release does not need VBA project access.') 5)
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
        $book.BuiltinDocumentProperties.Item('Title').Value = 'Excel Smart List Compare'
        $book.BuiltinDocumentProperties.Item('Comments').Value = 'Product SLC-68A45C44-2026; version 0.2.0'
        $book.IsAddin = $true
        $book.SaveAs($temporary, 55) # xlOpenXMLAddIn
        # Run entry points to make Excel compile the modules, then run integration tests.
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
        $book.Save()
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
function Install-Addin {
    $oldManifest = Read-OwnManifest
    if ((Test-Path -LiteralPath $Target) -and $null -eq $oldManifest) {
        throw 'An unrecognized file already exists at the install path. It was not overwritten.'
    }
    if (-not (Confirm-Action ('현재 Windows 사용자에게 명단 비교 기능을 설치할까요?' + "`r`n`r`n" +
        'Excel을 모두 닫아 주세요. 관리자 권한 요청, 전역 단축키 등록, 보안 설정 변경은 하지 않습니다.' + "`r`n" +
        '소스만 있는 패키지는 허용된 Excel 환경에서 최초 1회 빌드가 필요합니다.'))) { return }
    $payload = Join-Path $Root 'ExcelSmartListCompare.xlam'
    if (-not (Test-Path -LiteralPath $payload)) { $payload = Join-Path $Root 'dist\ExcelSmartListCompare.xlam' }
    if (-not (Test-Path -LiteralPath $payload)) {
        Start-OwnExcel
        try { $payload = Build-Addin } finally { Stop-OwnExcel }
    }
    [void](New-Item -ItemType Directory -Path $InstallDir -Force)
    $backup = $null
    if (Test-Path -LiteralPath $Target) {
        $backup = Join-Path $InstallDir ('slc-backup-' + [Guid]::NewGuid().ToString('N') + '.xlam')
        Copy-Item -LiteralPath $Target -Destination $backup
    }
    $ai = $null
    $installed = $false
    try {
        Copy-Item -LiteralPath $payload -Destination $Target -Force
        Start-OwnExcel
        $ai = Find-OwnAddin
        if ($null -eq $ai) { $ai = $script:Excel.AddIns.Add($Target, $false) }
        $ai.Installed = $true
        $q = "'ExcelSmartListCompare.xlam'!"
        $reported = [string]$script:Excel.Run($q + 'SLC_Version')
        if ($reported -ne $Version) { throw 'The registered add-in failed its version check.' }
        $null = $script:Excel.Run($q + 'SLC_AttachUI')
        if (-not [bool]$script:Excel.Run($q + 'SLC_UiReady')) { throw 'Excel could not register the comparison menu.' }
        Release-Com $ai
        $ai = $null
        Stop-OwnExcel
        foreach ($file in @('Setup.ps1','Uninstall.cmd','README.md')) {
            $source = Join-Path $Root $file
            $destination = Join-Path $InstallDir $file
            if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($destination)) {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
        [ordered]@{
            productId = $ProductId; version = $Version; installDirectory = $InstallDir
            installedAt = (Get-Date).ToString('o'); excelVersion = $script:ExcelVersion
            sha256 = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
            ownedFiles = @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json')
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Manifest -Encoding UTF8
        $installed = $true
        Write-Host '설치했습니다. Excel에서 추가 기능 탭의 명단 비교 버튼 또는 셀 우클릭 메뉴를 사용하세요.'
        Write-Host ('Uninstall: ' + (Join-Path $InstallDir 'Uninstall.cmd'))
    } catch {
        # Best effort registration rollback, with truthful reporting on upgrades.
        if ($null -ne $script:Excel) {
            if ($null -eq $ai) { $ai = Find-OwnAddin }
            if ($null -ne $ai) { try { $ai.Installed = $false } catch {} }
        }
        Release-Com $ai
        $ai = $null
        Stop-OwnExcel
        if ($null -ne $backup -and (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $backup -Destination $Target -Force
            Write-Warning 'Previous XLAM restored. If needed, re-enable it in Excel Add-ins after resolving the installation error.'
        } elseif (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Force }
        throw
    } finally {
        Release-Com $ai
        Stop-OwnExcel
        if ($null -ne $backup -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Force }
    }
}
function Uninstall-Addin {
    $data = Read-OwnManifest
    if ($null -eq $data) {
        Write-Host 'No owned installation found. No files or other add-ins were changed.'
        return
    }
    if (-not (Confirm-Action ('Excel 명단 비교 기능만 삭제할까요?' + "`r`n`r`n" +
        '기존 통합문서와 다른 추가 기능은 삭제하지 않습니다.'))) { return }
    $ai = $null
    try {
        Start-OwnExcel
        $ai = Find-OwnAddin
        if ($null -ne $ai) { $ai.Installed = $false }
        Release-Com $ai
        $ai = $null
    } finally { Release-Com $ai; Stop-OwnExcel }
    # Excel owns OPEN registration. Remove only our exact, disabled list entry, not the key or other values.
    if ($null -ne $script:ExcelVersion) {
        $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            ('Software\Microsoft\Office\' + $script:ExcelVersion + '\Excel\Add-in Manager'), $true)
        if ($null -ne $reg) {
            try {
                foreach ($name in $reg.GetValueNames()) {
                    if ($name -ieq $Target) { $reg.DeleteValue($name, $false) }
                }
            } finally { $reg.Close() }
        }
    }
    # Fixed allow-list: never recursively delete the installation directory.
    foreach ($file in @('ExcelSmartListCompare.xlam','README.md','Uninstall.cmd','Setup.ps1','install.json')) {
        $path = Join-Path $InstallDir $file
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Get-ChildItem -LiteralPath $InstallDir -Force | Measure-Object).Count -eq 0) {
        Remove-Item -LiteralPath $InstallDir -Force
    } else { Write-Host 'Additional files were left untouched in the installation directory.' }
    Write-Host '삭제했습니다. 통합문서와 다른 추가 기능은 변경하지 않았습니다.'
}
function Test-Addin {
    $file = $Target
    if (-not (Test-Path -LiteralPath $file)) { $file = Join-Path $Root 'dist\ExcelSmartListCompare.xlam' }
    if (-not (Test-Path -LiteralPath $file)) { $file = Join-Path $Root 'ExcelSmartListCompare.xlam' }
    if (-not (Test-Path -LiteralPath $file)) { throw 'Build or install the add-in before running Excel tests.' }
    $book = $null
    try {
        Start-OwnExcel
        foreach ($b in $script:Excel.Workbooks) {
            if ([string]$b.FullName -ieq $file) { $book = $b; break }
            Release-Com $b
        }
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
            Start-OwnExcel
            $built = Build-Addin
            Write-Host ('Built: ' + $built)
            Write-Host 'Distribute the Release folder; end users run Install.cmd once.'
        }
        'Install' { Install-Addin }
        'Uninstall' { Uninstall-Addin }
        'Test' { Test-Addin }
    }
} catch {
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
