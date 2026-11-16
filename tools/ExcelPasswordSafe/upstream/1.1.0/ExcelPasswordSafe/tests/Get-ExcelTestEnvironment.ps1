#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath, [object]$ExcelApplication)

function Get-EpsRegistryValues {
    param(
        [Microsoft.Win32.RegistryHive]$Hive,
        [Microsoft.Win32.RegistryView]$View,
        [string]$Key,
        [string[]]$Names
    )

    $values = @{}
    $base = $null
    $subkey = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
        $subkey = $base.OpenSubKey($Key, $false)
        if ($null -ne $subkey) {
            foreach ($name in $Names) { $values[$name] = $subkey.GetValue($name) }
        }
    } catch [System.Security.SecurityException] {
        # Evidence is optional when registry read access is restricted.
    } catch [System.UnauthorizedAccessException] {
    } finally {
        if ($null -ne $subkey) { $subkey.Dispose() }
        if ($null -ne $base) { $base.Dispose() }
    }
    return $values
}

function Get-EpsRegisteredExcel {
    param([Microsoft.Win32.RegistryView[]]$Views)

    foreach ($view in $Views) {
        $class = Get-EpsRegistryValues ClassesRoot $view 'Excel.Application\CLSID' @('')
        if (-not $class['']) { continue }
        $server = Get-EpsRegistryValues ClassesRoot $view ('CLSID\' + $class[''] + '\LocalServer32') @('')
        # The registration can quote the path and include a switch such as /automation.
        if ([string]$server[''] -match '^\s*"?([^"]+?\\EXCEL\.EXE)"?(?:\s|$)') {
            $candidate = $Matches[1]
            if ([IO.File]::Exists($candidate)) {
                return [pscustomobject]@{ path = $candidate; source = 'RegisteredCom' }
            }
        }
    }
    foreach ($view in $Views) {
        $entry = Get-EpsRegistryValues LocalMachine $view 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' @('')
        $candidate = ([string]$entry['']).Trim('"')
        if ([IO.File]::Exists($candidate)) {
            return [pscustomobject]@{ path = $candidate; source = 'AppPaths' }
        }
    }
}

function Get-EpsPeArchitecture {
    param([Parameter(Mandatory=$true)][string]$Path)

    $stream = [IO.File]::Open($Path, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $reader = [IO.BinaryReader]::new($stream)
        try {
            if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
                throw [IO.InvalidDataException]::new('Missing DOS executable header.')
            }
            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 6)) {
                throw [IO.InvalidDataException]::new('Invalid PE header offset.')
            }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                throw [IO.InvalidDataException]::new('Missing PE signature.')
            }
            $machine = $reader.ReadUInt16()
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }

    $architecture = switch ($machine) {
        0x014c { 'x86' }
        0x8664 { 'x64' }
        0x01c4 { 'Arm32' }
        0xaa64 { 'Arm64' }
        0xa641 { 'Arm64EC' }
        0xa64e { 'Arm64X' }
        default { 'Unknown' }
    }
    $bitness = switch ($architecture) {
        { $_ -in @('x86', 'Arm32') } { 32 }
        { $_ -in @('x64', 'Arm64', 'Arm64EC', 'Arm64X') } { 64 }
    }
    [pscustomobject]@{ architecture = $architecture; bitness = $bitness; peMachine = ('0x{0:X4}' -f $machine) }
}

function Get-EpsChannelId {
    param([string]$Value)

    # Save the channel GUID only. Tenant URLs and their other components are not needed.
    if ($Value -match '(?i)(?:^|/)([0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})(?:/|$)') {
        return $Matches[1].ToLowerInvariant()
    }
}

function Get-EpsClickToRun {
    param([string]$Executable, [Microsoft.Win32.RegistryView[]]$Views)

    foreach ($view in $Views) {
        $config = Get-EpsRegistryValues LocalMachine $view 'SOFTWARE\Microsoft\Office\ClickToRun\Configuration' @(
            'InstallationPath', 'ProductReleaseIds', 'Platform', 'VersionToReport', 'UpdateChannel', 'CDNBaseUrl'
        )
        $installPath = ([string]$config['InstallationPath']).TrimEnd('\', '/')
        if (-not $installPath) { continue }
        # Match the C2R root so an unrelated installation on the same PC isn't attributed to this Excel.
        if ([IO.Path]::GetFileName($installPath) -ine 'root') {
            $installPath = Join-Path $installPath 'root'
        }
        if (-not $Executable.StartsWith($installPath + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }

        $products = @(([string]$config['ProductReleaseIds'] -split '[,;\s]+') |
            Where-Object { $_ -match '^[A-Za-z][A-Za-z0-9]{1,80}$' } | Sort-Object -Unique)
        return [pscustomobject]@{
            productReleaseIds = $products
            platform = [string]$config['Platform']
            versionToReport = [string]$config['VersionToReport']
            updateChannelId = Get-EpsChannelId $config['UpdateChannel']
            cdnChannelId = Get-EpsChannelId $config['CDNBaseUrl']
        }
    }
}

function Get-ExcelTestEnvironment {
    [CmdletBinding()]
    param([string]$OutputPath, [object]$ExcelApplication)

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Windows is required to collect Excel installation evidence.'
    }

    $views = if ([Environment]::Is64BitOperatingSystem) {
        if ([Environment]::Is64BitProcess) { @('Registry64', 'Registry32') }
        else { @('Registry32', 'Registry64') }
    } else { @('Registry32') }

    $os = Get-EpsRegistryValues LocalMachine $views[0] 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' @(
        'CurrentMajorVersionNumber', 'CurrentMinorVersionNumber', 'CurrentVersion', 'CurrentBuildNumber', 'UBR', 'DisplayVersion', 'EditionID'
    )
    $osVersion = [string]$os['CurrentVersion']
    if ($null -ne $os['CurrentMajorVersionNumber'] -and $null -ne $os['CurrentMinorVersionNumber']) {
        $osVersion = '{0}.{1}' -f $os['CurrentMajorVersionNumber'], $os['CurrentMinorVersionNumber']
    }
    $nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $excel = [ordered]@{
        discovery = 'Unavailable'
        version = $null
        build = $null
        fileVersion = $null
        productVersion = $null
        architecture = $null
        bitness = $null
        peMachine = $null
        clickToRun = $null
    }

    $executable = $null
    if ($null -ne $ExcelApplication) {
        $excel.discovery = 'ComApplication'
        try { $excel.version = [string]$ExcelApplication.Version } catch {}
        try { $excel.build = [string]$ExcelApplication.Build } catch {}
        try { $executable = Join-Path ([string]$ExcelApplication.Path) 'EXCEL.EXE' } catch {}
    } else {
        $registered = Get-EpsRegisteredExcel $views
        if ($null -ne $registered) {
            $excel.discovery = $registered.source
            $executable = $registered.path
        }
    }
    if ($executable -and [IO.File]::Exists($executable)) {
        try {
            $file = [Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
            $excel.fileVersion = $file.FileVersion
            $excel.productVersion = $file.ProductVersion
        } catch {}
        try {
            $pe = Get-EpsPeArchitecture $executable
            $excel.architecture = $pe.architecture
            $excel.bitness = $pe.bitness
            $excel.peMachine = $pe.peMachine
        } catch {}
        $excel.clickToRun = Get-EpsClickToRun $executable $views
    }

    $report = [pscustomobject][ordered]@{
        schemaVersion = 1
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        os = [pscustomobject]@{
            version = $osVersion
            build = [string]$os['CurrentBuildNumber']
            buildRevision = $os['UBR']
            displayVersion = [string]$os['DisplayVersion']
            edition = [string]$os['EditionID']
            architecture = $nativeArchitecture
            is64Bit = [Environment]::Is64BitOperatingSystem
        }
        powerShell = [pscustomobject]@{
            version = $PSVersionTable.PSVersion.ToString()
            edition = $PSVersionTable.PSEdition
            architecture = $env:PROCESSOR_ARCHITECTURE
            is64Bit = [Environment]::Is64BitProcess
            apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState().ToString()
        }
        excel = [pscustomobject]$excel
    }
    if ($OutputPath) {
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -ErrorAction Stop
    }
    return $report
}

if ($MyInvocation.InvocationName -ne '.') {
    Get-ExcelTestEnvironment @PSBoundParameters
}
