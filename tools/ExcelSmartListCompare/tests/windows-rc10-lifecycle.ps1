[CmdletBinding()]
param(
    [ValidateSet('Plan','Execute')][string]$Mode = 'Plan',
    [ValidateSet('EXE','Engine')][string]$InstallChannel = 'EXE',
    [ValidateSet('Full','InstallationOnly')][string]$VerificationScope = 'Full',
    [Parameter(Mandatory=$true)][string]$InstallerPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedInstallerSha256,
    [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
    [string]$ExpectedSetupSha256 = '',
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedXlamSha256,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$PreviousXlamSha256,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$FlowScript = '',
    [switch]$NativeUiCheckpoint,
    [switch]$NativeUiFirst,
    [switch]$AllowOwnedEmptyCleanup,
    [ValidateRange(30,1800)][int]$NativeUiTimeoutSeconds = 1800
)
# This is a local, non-native acceptance harness, not a release approval gate.
# Plan makes a real private backup but never changes product/registry/Excel state.
# Execute changes only the recognised RC9 product and returns it to its baseline.
# Engine exercises the pinned payload directly and never establishes EXE acceptance.
# Do not run this script from an elevated shell or while any Excel is running.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($NativeUiFirst -and -not $NativeUiCheckpoint) { throw 'NativeUiFirst requires NativeUiCheckpoint.' }
$InstallChannel=if($InstallChannel -ieq 'Engine'){'Engine'}else{'EXE'}
$VerificationScope=if($VerificationScope -ieq 'InstallationOnly'){'InstallationOnly'}else{'Full'}
if (-not $FlowScript) { $FlowScript = Join-Path $PSScriptRoot 'windows-rc10-flow.ps1' }
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [Environment]::GetFolderPath('LocalApplicationData') }
if (-not $env:APPDATA) { $env:APPDATA = [Environment]::GetFolderPath('ApplicationData') }
if (-not $env:SystemRoot) { $env:SystemRoot = [Environment]::GetFolderPath('Windows') }
if (-not $env:OS) { $env:OS = 'Windows_NT' }
if (-not $env:COMSPEC) { $env:COMSPEC = Join-Path $env:SystemRoot 'System32\cmd.exe' }
if (-not $env:PSModulePath) { $env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules' }
$productId = 'SLC-68A45C44-2026'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$product = Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
$manager = Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare.Setup'
$target = Join-Path $product 'ExcelSmartListCompare.xlam'
$appKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\ExcelSmartListCompare.OneFile_is1'
$productNames = @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json')
$managerNames = @('manager.id','unins000.exe','unins000.dat','unins000.msg','Engine\Setup.ps1','Engine\Uninstall.cmd')
$checks = New-Object Collections.Generic.List[object]
$openSlots = New-Object Collections.Generic.List[string]
$trustPaths = New-Object Collections.Generic.List[string]
$script:lastState = $null
$script:mutationStarted = $false
$script:journalNumber = 0
$script:restoreStatus = 'NOT_NEEDED'
$script:postRestoreStatus = 'NOT_RUN'
$script:failure = $null
$script:hadExitFailure = $false
$harnessMutex = $null
$harnessHeld = $false

function Json($Value) { return ConvertTo-Json -InputObject $Value -Depth 40 -Compress }
function Assert-PhysicalPathMatch([string]$Expected,[string]$Actual) {
    if($Actual.StartsWith('\\?\UNC\')){$Actual='\\'+$Actual.Substring(8)}
    elseif($Actual.StartsWith('\\?\')){$Actual=$Actual.Substring(4)}
    if([string]::IsNullOrEmpty($Actual) -or $Actual -ine [IO.Path]::GetFullPath($Expected)) {
        throw 'Physical file location differs from its intended path; installation/restoration is not verified.'
    }
}
function Assert-InstalledPhysicalPaths {
    if(-not ('SlcLifecyclePhysicalPath' -as [type])) {
        Add-Type @'
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class SlcLifecyclePhysicalPath {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 public static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint capacity, uint flags);
}
'@
    }
    foreach($pair in @(@($product,$productNames),@($manager,$managerNames))) {
        foreach($name in $pair[1]) {
            $path=Join-Path $pair[0] $name
            if(-not [IO.File]::Exists($path)){continue}
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            try {
                $buffer=New-Object Text.StringBuilder 32768
                $length=[SlcLifecyclePhysicalPath]::GetFinalPathNameByHandle($stream.SafeFileHandle,$buffer,32768,0)
                if($length -eq 0 -or $length -ge 32768){throw 'Physical file location could not be established.'}
                Assert-PhysicalPathMatch $path $buffer.ToString()
            } finally {$stream.Dispose()}
        }
    }
}
function Canonical($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [Collections.IDictionary]) {
        $sorted=[ordered]@{}; foreach($key in @($Value.Keys | Sort-Object)) { $sorted[$key]=Canonical $Value[$key] }; return $sorted
    }
    if ($Value -is [pscustomobject]) {
        $sorted=[ordered]@{}; foreach($p in @($Value.PSObject.Properties | Sort-Object Name)) { $sorted[$p.Name]=Canonical $p.Value }; return $sorted
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $items=@(); foreach($item in $Value) { $items += ,(Canonical $item) }; return ,$items
    }
    return $Value
}
function Same($A,$B) { return (Json (Canonical $A)) -ceq (Json (Canonical $B)) }
function Write-Json([string]$Name,$Value) {
    $path = Join-Path $output $Name
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $Value -Depth 40), [Text.UTF8Encoding]::new($false))
}
function Check([string]$Name,[bool]$Pass) {
    $checks.Add([ordered]@{name=$Name;status=$(if($Pass){'PASS'}else{'FAIL'})})
    if (-not $Pass) { throw $Name }
}
function Assert-NoExcel {
    if (@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'An Excel process is open; no user process will be closed or killed.' }
}
function Assert-NoReparse([string]$Path) {
    $p = [IO.Path]::GetFullPath($Path)
    $leaf=$true
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            $entry=Get-Item -LiteralPath $p -Force
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('Reparse point refused: '+$p) }
            if (-not $leaf -and -not $entry.PSIsContainer) { throw ('Path parent is not a directory: '+$p) }
        }
        $parent = [IO.Directory]::GetParent($p)
        $p = if ($null -eq $parent) { $null } else { $parent.FullName }
        $leaf=$false
    }
}
function File-Hash([string]$Path) {
    Assert-NoReparse $Path
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('Known file path is not a file: '+$Path) }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function File-Metadata([string]$Path) {
    Assert-NoReparse $Path
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('Known file path is not a file: '+$Path) }
    $i=Get-Item -LiteralPath $Path -Force
    return [ordered]@{attributes=[int]$i.Attributes;lastWriteUtc=$i.LastWriteTimeUtc.ToString('o')}
}
function Metadata-State {
    $result=[ordered]@{}
    foreach($pair in @(@('product',$product,$productNames),@('manager',$manager,$managerNames))) {
        foreach($name in $pair[2]) { $result[$pair[0]+'/'+$name]=File-Metadata (Join-Path $pair[1] $name) }
    }
    return $result
}
function File-State {
    $result = [ordered]@{}
    foreach ($pair in @(@('product',$product,$productNames),@('manager',$manager,$managerNames))) {
        foreach ($name in $pair[2]) { $result[($pair[0]+'/'+$name)] = File-Hash (Join-Path $pair[1] $name) }
    }
    return $result
}
function Extra-State {
    # Inventory names only. Never open, copy or delete unrelated files.
    $result = @()
    foreach ($pair in @(@('product',$product,$productNames),@('manager',$manager,$managerNames))) {
        if (-not (Test-Path -LiteralPath $pair[1])) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $pair[1] -Force | Sort-Object Name)) {
            if ($pair[0] -eq 'manager' -and $item.Name -eq 'Engine' -and $item.PSIsContainer) {
                Assert-NoReparse $item.FullName
                foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force | Sort-Object Name)) {
                    if (('Engine\'+$child.Name) -notin $managerNames) { $result += ($pair[0]+'/Engine/'+$child.Name) }
                }
            } elseif ($item.Name -notin $pair[2]) { $result += ($pair[0]+'/'+$item.Name) }
        }
    }
    return @($result)
}
function Registry-Value($Key,[string]$Name) {
    if ($null -eq $Key -or $Name -notin $Key.GetValueNames()) { return $null }
    $kind = [string]$Key.GetValueKind($Name)
    $value = $Key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if ($kind -eq 'Binary') { $value = [Convert]::ToBase64String($value) }
    return [ordered]@{name=$Name;kind=$kind;value=$value}
}
function Registry-Tree([string]$Path,[string]$Hive='HKCU') {
    $root = if ($Hive -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
    $key = $root.OpenSubKey($Path)
    if ($null -eq $key) { return [ordered]@{exists=$false;values=@();children=[ordered]@{}} }
    try {
        $values = @(); foreach ($name in @($key.GetValueNames() | Sort-Object)) { $values += Registry-Value $key $name }
        $children = [ordered]@{}; foreach ($name in @($key.GetSubKeyNames() | Sort-Object)) { $children[$name] = Registry-Tree ($Path+'\'+$name) $Hive }
        return [ordered]@{exists=$true;values=@($values);children=$children}
    } finally { $key.Dispose() }
}
function Owned-Registry {
    $options = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($excelRoot+'\Options')
    $opens = [ordered]@{}
    try {
        if ($null -ne $options) {
            foreach ($name in $options.GetValueNames()) {
                $v = [string]$options.GetValue($name)
                if ($name -match '^OPEN\d*$' -and ($v -ieq $target -or $v -ieq ('"'+$target+'"'))) {
                    if (-not $openSlots.Contains($name)) { $openSlots.Add($name) }
                }
            }
        }
        foreach ($name in @($openSlots | Sort-Object)) { $opens[$name] = Registry-Value $options $name }
    } finally { if ($null -ne $options) { $options.Dispose() } }
    $addins = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($excelRoot+'\Add-in Manager')
    try { $addin = Registry-Value $addins $target } finally { if ($null -ne $addins) { $addins.Dispose() } }
    $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($trustRoot)
    try {
        if ($null -ne $root) {
            foreach ($name in $root.GetSubKeyNames()) {
                $k = $root.OpenSubKey($name)
                try {
                    if ([string]$k.GetValue('SLCProductId','') -ceq $productId -and ([string]$k.GetValue('Path','')).TrimEnd('\') -ieq $product) {
                        $p = $trustRoot+'\'+$name
                        if (-not $trustPaths.Contains($p)) { $trustPaths.Add($p) }
                    }
                } finally { $k.Dispose() }
            }
        }
    } finally { if ($null -ne $root) { $root.Dispose() } }
    $trust = [ordered]@{}; foreach ($p in @($trustPaths | Sort-Object)) { $trust[$p] = Registry-Tree $p }
    return [ordered]@{opens=$opens;addin=$addin;trust=$trust;app=(Registry-Tree $appKey)}
}
function State { return [ordered]@{files=(File-State);metadata=(Metadata-State);registry=(Owned-Registry);extras=@(Extra-State)} }
function Protected-State {
    # Read-only comparison of other add-ins/security/policy. No bulk restore.
    $result = [ordered]@{}
    foreach ($hive in @('HKCU','HKLM')) {
        foreach ($p in @(($excelRoot+'\Options'),($excelRoot+'\Add-in Manager'),($excelRoot+'\Security'),'Software\Microsoft\Office\Excel\Addins','Software\Policies\Microsoft\Office','Software\Policies\Microsoft\Windows\PowerShell','Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell')) {
            $tree = Registry-Tree $p $hive
            if ($p -eq ($excelRoot+'\Options')) {
                $tree.values=@($tree.values | Where-Object { $_.name -match '^OPEN\d*$' -and ($hive -ne 'HKCU' -or $_.name -notin $openSlots) })
                $tree.children=[ordered]@{}
            }
            if ($hive -eq 'HKCU') {
                if ($p -eq ($excelRoot+'\Add-in Manager')) { $tree.values=@($tree.values | Where-Object { $_.name -ine $target }) }
                if ($p -eq ($excelRoot+'\Security') -and $tree.children.Contains('Trusted Locations')) {
                    $locations = $tree.children['Trusted Locations']
                    foreach ($owned in $trustPaths) { $locations.children.Remove(($owned -split '\\')[-1]) }
                    if (-not $locations.values.Count -and -not $locations.children.Count) { $tree.children.Remove('Trusted Locations') }
                }
            }
            # Empty parent keys created/removed by the product are not other settings.
            if (-not $tree.values.Count -and -not $tree.children.Count) { $tree.exists=$false }
            $result[$hive+'/'+$p] = $tree
        }
    }
    return $result
}
function Journal([string]$Label,$Snapshot) {
    $script:journalNumber++
    Write-Json ('journal-{0:D2}-{1}.private.json' -f $script:journalNumber,$Label) $Snapshot
    $script:lastState = $Snapshot
}
function Assert-Unchanged {
    Assert-NoExcel
    Check 'Product state still matches the last recorded state' (Same (State) $script:lastState)
    Check 'Other add-ins and policy values remain unchanged' (Same (Protected-State) $protectedBaseline)
}
function Backup-Files($Snapshot) {
    $meta = [ordered]@{}
    foreach ($pair in @(@('product',$product,$productNames),@('manager',$manager,$managerNames))) {
        foreach ($name in $pair[2]) {
            $id = $pair[0]+'/'+$name
            if ($null -eq $Snapshot.files[$id]) { continue }
            $source = Join-Path $pair[1] $name
            $dest = Join-Path (Join-Path $backup $pair[0]) $name
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
            [IO.File]::Copy($source,$dest,$false)
            Check ('Backup verified: '+$id) ((File-Hash $dest) -ceq $Snapshot.files[$id])
            $info = Get-Item -LiteralPath $source -Force
            $meta[$id] = [ordered]@{attributes=[int]$info.Attributes;lastWriteUtc=$info.LastWriteTimeUtc.ToString('o')}
        }
    }
    return $meta
}
function Child-SearchPath([string]$CurrentPath,[string]$WindowsRoot) {
    $paths=New-Object Collections.Generic.List[string]
    foreach($path in @((Join-Path $WindowsRoot 'System32'),$WindowsRoot,(Join-Path $WindowsRoot 'System32\Wbem'),(Join-Path $WindowsRoot 'System32\WindowsPowerShell\v1.0'))+@($CurrentPath -split ';')) {
        if([string]::IsNullOrWhiteSpace($path)) { continue }
        $value=$path.Trim().TrimEnd('\')
        if(@($paths | Where-Object { $_ -ieq $value }).Count -eq 0) { $paths.Add($value) }
    }
    return ($paths -join ';')
}
function Start-LifecycleChild([string]$File,[object]$Arguments,[string]$Stdout='', [string]$Stderr='') {
    # Windows PowerShell 5 has no Start-Process -Environment argument. Change
    # only this harness process while creating its child, then restore it
    # immediately. No user/machine environment registry is written.
    $oldPath=$env:PATH
    $oldPathExt=$env:PATHEXT
    try {
        $env:PATH=Child-SearchPath $oldPath $env:SystemRoot
        $pathExtDefaulted=[string]::IsNullOrWhiteSpace($env:PATHEXT)
        if($pathExtDefaulted) { $env:PATHEXT='.COM;.EXE;.BAT;.CMD' }
        Write-Json 'child-environment.private.json' ([ordered]@{status='PROCESS_ONLY';reason='Prepend missing standard Windows command directories and default PATHEXT only if missing for child processes; preserve other entries; no persistent environment changes.';pathExtDefaulted=$pathExtDefaulted;standardDirectories=@((Join-Path $env:SystemRoot 'System32'),$env:SystemRoot,(Join-Path $env:SystemRoot 'System32\Wbem'),(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0'))})
        $start=@{FilePath=$File;ArgumentList=$Arguments;WorkingDirectory=$repo;WindowStyle='Hidden';PassThru=$true}
        if($Stdout) { $start.RedirectStandardOutput=$Stdout }
        if($Stderr) { $start.RedirectStandardError=$Stderr }
        return Start-Process @start
    } finally { $env:PATH=$oldPath; $env:PATHEXT=$oldPathExt }
}
function Run-Installer([string]$Exe,[string]$Label,[switch]$Uninstall) {
    Assert-Unchanged
    if (-not $Uninstall) { Check 'Installer pin still matches' ((File-Hash $Exe) -ieq $ExpectedInstallerSha256) }
    else { Check 'Remover bytes match recorded manager' ((File-Hash $Exe) -ceq $script:lastState.files['manager/unins000.exe']) }
    $priorMutation=$script:mutationStarted
    $beforeDirectories=@(Test-Path -LiteralPath $product -PathType Container; Test-Path -LiteralPath $manager -PathType Container; Test-Path -LiteralPath (Join-Path $manager 'Engine') -PathType Container)
    $script:mutationStarted = $true
    $log = Join-Path $output ($Label+'.inno.private.log')
    $p = Start-LifecycleChild $Exe @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG="'+$log+'"'))
    try {
        [void]$p.Handle
        if (-not $p.WaitForExit(120000)) { throw ('Installer did not exit; no process killed. Inspect PID '+$p.Id) }
        $exitCode = $p.ExitCode
        if($null -eq $exitCode) { throw 'Installer exit code is unavailable; success is not assumed.' }
    } finally { $p.Dispose() }
    if ($exitCode -ne 0) {
        if(-not $priorMutation -and $Label -ceq 'upgrade' -and -not $Uninstall) {
            $afterDirectories=@(Test-Path -LiteralPath $product -PathType Container; Test-Path -LiteralPath $manager -PathType Container; Test-Path -LiteralPath (Join-Path $manager 'Engine') -PathType Container)
            $unchanged=(Same (State) $script:lastState) -and (Same (Protected-State) $protectedBaseline) -and (Same $beforeDirectories $afterDirectories)
            Write-Json 'failed-initial-upgrade-state.private.json' ([ordered]@{exitCode=$exitCode;stateUnchanged=$unchanged;priorMutation=$priorMutation;observedUtc=[DateTime]::UtcNow.ToString('o')})
            if($unchanged) { $script:mutationStarted=$false; $script:restoreStatus='NOT_NEEDED_UNCHANGED' }
        }
        throw ($Label+' exited '+$exitCode+'. See the preserved installer log and state evidence.')
    }
    if ($Uninstall) {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt 20 -and ((Test-Path -LiteralPath $Exe) -or -not (Test-Path -LiteralPath $log) -or [IO.File]::ReadAllText($log) -notmatch 'Log closed\.')) { Start-Sleep -Milliseconds 200 }
        Check 'Registered remover completed its log' ((Test-Path -LiteralPath $log) -and [IO.File]::ReadAllText($log) -match 'Uninstallation process succeeded\.' -and [IO.File]::ReadAllText($log) -match 'Log closed\.')
    }
    $next = State
    if ($Uninstall) { Assert-Removed $next } else { Assert-Candidate $next }
    Journal $Label $next
    Check ($Label+' leaves other add-ins and policies unchanged') (Same (Protected-State) $protectedBaseline)
}
function Assert-Candidate($Snapshot) {
    foreach ($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md')) { Check ('Installed exact payload: '+$name) ($Snapshot.files['product/'+$name] -ceq $payloadHashes[$name]) }
    $m = Get-Content -LiteralPath (Join-Path $product 'install.json') -Raw | ConvertFrom-Json
    Check 'RC10 manifest identity and pin' ($m.productId -ceq $productId -and $m.installDirectory -ieq $product -and $m.installerVersion -ceq '0.2.0-rc.10' -and $m.sha256 -ieq $ExpectedXlamSha256)
    if($InstallChannel -ceq 'EXE') {
        Check 'Manager recovery Setup matches payload' ($Snapshot.files['manager/Engine\Setup.ps1'] -ceq $payloadHashes['Setup.ps1'])
        Check 'Manager recovery launcher matches payload' ($Snapshot.files['manager/Engine\Uninstall.cmd'] -ceq $payloadHashes['Uninstall.cmd'])
        Check 'Owned manager and remover exist' (([IO.File]::ReadAllText((Join-Path $manager 'manager.id')).Trim() -ceq 'SLC-68A45C44-2026-OneFile-1') -and $null -ne $Snapshot.files['manager/unins000.exe'] -and $Snapshot.registry.app.exists)
    } else {
        Check 'Direct engine creates no EXE manager or Apps registration' (-not (Test-Path -LiteralPath $manager) -and -not $Snapshot.registry.app.exists)
    }
    $active = @($Snapshot.registry.opens.Values | Where-Object { $null -ne $_ })
    Check 'Exactly one product autoload value exists' ($active.Count -eq 1 -and ($active[0].value -ieq $target -or $active[0].value -ieq ('"'+$target+'"')))
}
function Assert-Removed($Snapshot) {
    Check 'Product files and manager files removed' (@($Snapshot.files.Values | Where-Object { $null -ne $_ }).Count -eq 0)
    Check 'Product OPEN and Add-in Manager entries removed' (@($Snapshot.registry.opens.Values | Where-Object { $null -ne $_ }).Count -eq 0 -and $null -eq $Snapshot.registry.addin)
    Check 'Owned trust and Apps registration removed' (@($Snapshot.registry.trust.Values | Where-Object exists).Count -eq 0 -and -not $Snapshot.registry.app.exists)
    Check 'Unrelated file names preserved' (Same $Snapshot.extras $baseline.extras)
}
function Flow-ChildEligible($Flow) {
    try {
        if ($Flow.status -notin @('PASS','PENDING_HOST_RELEASE') -or $null -ne $Flow.failure -or @($Flow.cleanupErrors).Count -ne 0 -or $Flow.quitSent -ne $true -or $Flow.normalStartup -cne 'PASS') { return $false }
        if ($null -eq $Flow.owner -or [int]$Flow.owner.pid -le 0 -or [string]$Flow.owner.startTimeUtcTicksText -notmatch '^\d+$') { return $false }
        if ($Flow.status -ceq 'PASS') { return ($Flow.excelExited -eq $true -and $Flow.exitConfirmation -ceq 'PASS') }
        return ($Flow.excelExited -eq $false -and $Flow.exitConfirmation -ceq 'PENDING_HOST_RELEASE')
    } catch { return $false }
}
function Flow-ExitObservation($Owner,$Processes) {
    $matches=@($Processes | Where-Object { $_.pid -eq $Owner.pid -and $_.startTimeUtcTicksText -ceq $Owner.startTimeUtcTicksText })
    return [ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');ownedIdentityExited=($matches.Count -eq 0);globalExcelCount=@($Processes).Count;processes=@($Processes)}
}
function Get-FreshExcelIdentities {
    $current=@()
    foreach($process in @(Get-Process EXCEL -ErrorAction SilentlyContinue)) {
        try {
            $processId=$process.Id
            try { $ticks=$process.StartTime.ToUniversalTime().Ticks.ToString() }
            catch {
                $again=Get-Process -Id $processId -ErrorAction SilentlyContinue
                if($null -eq $again) { continue }
                $again.Dispose(); throw
            }
            $current+=([ordered]@{pid=$processId;startTimeUtcTicksText=$ticks})
        } finally { $process.Dispose() }
    }
    return ,$current
}
function Release-LifecycleCom($Value) {
    if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value) }
}
function Stop-ProvenOwnedEmptyExcel($Owner,$Record) {
    # This opt-in recovery is not a normal-exit pass. Never close a workbook,
    # use a process-name kill, or act on a process with incomplete proof.
    $excel=$null; $books=$null; $views=$null; $ownedProcess=$null
    $proof=[ordered]@{pid=$Owner.pid;startTimeUtcTicksText=$Owner.startTimeUtcTicksText;processName=$null;comHwnd=$null;comPid=$null;workbooks=$null;protectedViews=$null;mainWindowHandle=$null;verified=$false}
    $Record['ownedEmptyProof']=$proof
    try {
        $identities=Get-FreshExcelIdentities
        if($identities.Count -eq 0) { $Record['lateExitWithoutForce']=$true; return }
        if($identities.Count -ne 1 -or $identities[0].pid -ne $Owner.pid -or $identities[0].startTimeUtcTicksText -cne $Owner.startTimeUtcTicksText) { throw 'Empty cleanup requires exactly the original owned Excel process; every other process is preserved.' }
        $ownedProcess=Get-Process -Id $Owner.pid -ErrorAction Stop
        $proof.processName=$ownedProcess.ProcessName
        if($proof.processName -ine 'EXCEL' -or $ownedProcess.StartTime.ToUniversalTime().Ticks.ToString() -cne $Owner.startTimeUtcTicksText) { throw 'Owned process identity changed; no process was terminated.' }
        if(-not ('SlcLifecycleOwner' -as [type])) {
            Add-Type 'using System; using System.Runtime.InteropServices; public static class SlcLifecycleOwner { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid); }'
        }
        $excel=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application')
        $proof.comHwnd=[long]$excel.Hwnd
        [uint32]$comPid=0
        [void][SlcLifecycleOwner]::GetWindowThreadProcessId([IntPtr]$proof.comHwnd,[ref]$comPid)
        $proof.comPid=$comPid
        if($proof.comHwnd -eq 0 -or $comPid -ne $Owner.pid) { throw 'Fresh COM HWND does not belong to the owned session; no process was terminated.' }
        $books=$excel.Workbooks; $views=$excel.ProtectedViewWindows
        $proof.workbooks=[int]$books.Count; $proof.protectedViews=[int]$views.Count
        $ownedProcess.Refresh(); $proof.mainWindowHandle=[long]$ownedProcess.MainWindowHandle
        if($proof.workbooks -ne 0 -or $proof.protectedViews -ne 0 -or $proof.mainWindowHandle -ne 0) { throw 'The owned process is not provably empty and hidden; all workbooks/processes were preserved.' }
        # Re-read every gate immediately before targeting this single Process object.
        $identities=Get-FreshExcelIdentities
        $ownedProcess.Refresh()
        [uint32]$lastComPid=0; $lastHwnd=[long]$excel.Hwnd
        [void][SlcLifecycleOwner]::GetWindowThreadProcessId([IntPtr]$lastHwnd,[ref]$lastComPid)
        if($identities.Count -ne 1 -or $identities[0].pid -ne $Owner.pid -or $identities[0].startTimeUtcTicksText -cne $Owner.startTimeUtcTicksText -or $ownedProcess.ProcessName -ine 'EXCEL' -or $ownedProcess.StartTime.ToUniversalTime().Ticks.ToString() -cne $Owner.startTimeUtcTicksText -or [long]$ownedProcess.MainWindowHandle -ne 0 -or $lastComPid -ne $Owner.pid -or $lastHwnd -eq 0 -or $lastHwnd -ne $proof.comHwnd -or [int]$books.Count -ne 0 -or [int]$views.Count -ne 0) { throw 'Empty-process proof changed immediately before cleanup; no process was terminated.' }
        $proof.verified=$true
        Stop-Process -InputObject $ownedProcess -Force -ErrorAction Stop
        $Record.forcedOwnedEmptyCleanup=$true; $Record.processesKilled=1
    } finally {
        Release-LifecycleCom $views; Release-LifecycleCom $books; Release-LifecycleCom $excel
        if($null -ne $ownedProcess) { $ownedProcess.Dispose() }
    }
}
function Confirm-FlowExit($Flow,[string]$Folder) {
    # Called only after the child PowerShell process has exited. Its raw result
    # remains unchanged; this parent records its independent exit observation.
    $raw=Join-Path $Folder 'flow.private.json'
    $record=[ordered]@{schemaVersion=1;status='FAIL';normalExit='NOT_CONFIRMED';forcedOwnedEmptyCleanup=$false;allowOwnedEmptyCleanup=[bool]$AllowOwnedEmptyCleanup;childStatus=$Flow.status;childEvidence='flow.private.json';childEvidenceSha256=(File-Hash $raw);owner=$Flow.owner;timeoutSeconds=30;startedUtc=[DateTime]::UtcNow.ToString('o');lastObservation=$null;failure=$null;processesKilled=0}
    try {
        if(-not (Flow-ChildEligible $Flow)) { throw 'Child has an actual failure or lacks safe Quit/ownership evidence; pending status is not accepted.' }
        $timer=[Diagnostics.Stopwatch]::StartNew()
        do {
            $current=Get-FreshExcelIdentities
            $record.lastObservation=Flow-ExitObservation $Flow.owner $current
            if($record.lastObservation.ownedIdentityExited -and $record.lastObservation.globalExcelCount -eq 0) {
                if((File-Hash $raw) -cne $record.childEvidenceSha256) { throw 'The raw child evidence changed during supervision.' }
                $record.normalExit='PASS'; $record.status='PASS'; break
            }
            Start-Sleep -Milliseconds 250
        } while($timer.Elapsed.TotalSeconds -lt 30)
        if($record.status -cne 'PASS') {
            $record.normalExit='FAIL'; $script:hadExitFailure=$true
            if(-not $AllowOwnedEmptyCleanup -or $Flow.status -cne 'PENDING_HOST_RELEASE') { throw 'Fresh parent observations still show Excel after 30 seconds. No process was closed or killed.' }
            Stop-ProvenOwnedEmptyExcel $Flow.owner $record
            $cleanupTimer=[Diagnostics.Stopwatch]::StartNew()
            do {
                $record.lastObservation=Flow-ExitObservation $Flow.owner (Get-FreshExcelIdentities)
                if($record.lastObservation.ownedIdentityExited -and $record.lastObservation.globalExcelCount -eq 0) { break }
                Start-Sleep -Milliseconds 250
            } while($cleanupTimer.Elapsed.TotalSeconds -lt 30)
            if(-not $record.lastObservation.ownedIdentityExited -or $record.lastObservation.globalExcelCount -ne 0) { throw 'Excel remains after the bounded owned-empty cleanup; installation testing cannot continue.' }
            if((File-Hash $raw) -cne $record.childEvidenceSha256) { throw 'The raw child evidence changed during supervision.' }
            $record.status='PARTIAL'
        }
    } catch { $record.failure=$_.Exception.Message; throw }
    finally {
        $record['finishedUtc']=[DateTime]::UtcNow.ToString('o')
        [IO.File]::WriteAllText((Join-Path $Folder 'supervisor.private.json'),(ConvertTo-Json -InputObject $record -Depth 20),[Text.UTF8Encoding]::new($false))
    }
}
function Quote-NativeArgument([string]$Value) {
    # All callers pass file paths or fixed switches/values. Embedded double
    # quotes/newlines are refused, not interpreted as another command.
    if($Value -match '["\r\n]') { throw 'Unsupported quote or newline in a child argument.' }
    $tail=[regex]::Match($Value,'\\+$').Value
    return ('"'+$Value+$tail+'"')
}
function Run-PowerShellChild([string[]]$Arguments,[string]$Label,[int]$TimeoutSeconds=600) {
    $stdout=Join-Path $output ($Label+'.stdout.private.log')
    $stderr=Join-Path $output ($Label+'.stderr.private.log')
    $record=[ordered]@{status='STARTING';pid=$null;startTimeUtcTicksText=$null;startedUtc=[DateTime]::UtcNow.ToString('o');exitCode=$null;hostExited=$false;stdout=[IO.Path]::GetFileName($stdout);stderr=[IO.Path]::GetFileName($stderr);failure=$null}
    $process=$null
    try {
        $commandLine=(@($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
        $process=Start-LifecycleChild $psExe $commandLine $stdout $stderr
        # Start-Process may otherwise discard the exit status on this host.
        # Acquire and retain the exact process handle before it exits.
        [void]$process.Handle
        $record.pid=$process.Id; $record.startTimeUtcTicksText=$process.StartTime.ToUniversalTime().Ticks.ToString()
        Write-Json ($Label+'.child.private.json') $record
        if(-not $process.WaitForExit($TimeoutSeconds*1000)) { throw ('Child PowerShell timed out. Its process and any Excel session were preserved; inspect PID '+$process.Id) }
        $process.WaitForExit()
        $process.Refresh()
        $rawExit=$process.ExitCode
        if($null -eq $rawExit) { throw 'Child exited but its exit code is unavailable; success is not assumed.' }
        $record.hostExited=$true; $record.exitCode=[int]$rawExit
        $record.status=if($record.exitCode -eq 0){'EXITED_ZERO'}else{'EXITED_NONZERO'}
        return $record.exitCode
    } catch { $record.status='FAIL'; $record.failure=$_.Exception.Message; throw }
    finally {
        $record['finishedUtc']=[DateTime]::UtcNow.ToString('o')
        Write-Json ($Label+'.child.private.json') $record
        if($null -ne $process) { $process.Dispose() }
    }
}
function Run-Engine([string]$Action,[string]$Label) {
    Assert-Unchanged
    Check 'Direct engine bytes match the explicit package pin' ((File-Hash (Join-Path $ReleaseDirectory 'Setup.ps1')) -ieq $ExpectedSetupSha256)
    foreach($name in $payloadHashes.Keys) { Check ('Direct-engine payload remains pinned: '+$name) ((File-Hash (Join-Path $ReleaseDirectory $name)) -ceq $payloadHashes[$name]) }
    $priorMutation=$script:mutationStarted
    $beforeDirectories=@(Test-Path -LiteralPath $product -PathType Container; Test-Path -LiteralPath $manager -PathType Container; Test-Path -LiteralPath (Join-Path $manager 'Engine') -PathType Container)
    $script:mutationStarted=$true
    $engineExit=Run-PowerShellChild @('-NoProfile','-File',(Join-Path $ReleaseDirectory 'Setup.ps1'),'-Action',$Action,'-ConfirmProduct',$productId) ($Label+'-engine')
    if($engineExit -ne 0) {
        if(-not $priorMutation -and $Label -ceq 'upgrade' -and $Action -ceq 'Install') {
            $afterDirectories=@(Test-Path -LiteralPath $product -PathType Container; Test-Path -LiteralPath $manager -PathType Container; Test-Path -LiteralPath (Join-Path $manager 'Engine') -PathType Container)
            $unchanged=(Same (State) $script:lastState) -and (Same (Protected-State) $protectedBaseline) -and (Same $beforeDirectories $afterDirectories)
            Write-Json 'failed-initial-engine-state.private.json' ([ordered]@{exitCode=$engineExit;stateUnchanged=$unchanged;priorMutation=$priorMutation;observedUtc=[DateTime]::UtcNow.ToString('o')})
            if($unchanged) { $script:mutationStarted=$false; $script:restoreStatus='NOT_NEEDED_UNCHANGED' }
        }
        throw ($Label+' direct engine exited '+$engineExit+'. This is not an EXE acceptance result.')
    }
    $next=State
    if($Action -ceq 'Uninstall') { Assert-Removed $next } else { Assert-Candidate $next }
    Journal ($Label+'-engine') $next
    Check ($Label+' direct engine preserves other add-ins and policies') (Same (Protected-State) $protectedBaseline)
}
function Run-PackageInstall([string]$Label) {
    if($InstallChannel -ceq 'Engine') { Run-Engine 'Install' $Label }
    else { Run-Installer $InstallerPath $Label }
}
function Run-PackageUninstall {
    if($InstallChannel -ceq 'Engine') { Run-Engine 'Uninstall' 'uninstall' }
    else { Run-Installer (Join-Path $manager 'unins000.exe') 'uninstall' -Uninstall }
}
function Lifecycle-SuccessStatus([string]$Channel,[bool]$Partial) {
    if($Channel -ceq 'Engine') { if($Partial){return 'INSTALL_ENGINE_STEPS_PARTIAL'}else{return 'INSTALL_ENGINE_STEPS_PASS'} }
    if($Partial){return 'AUTOMATED_STEPS_PARTIAL'}else{return 'AUTOMATED_STEPS_PASS'}
}
function Run-Flow([string]$FlowMode,[string]$Label,[string]$Version='0.2.0-rc.10',[string]$Hash=$ExpectedXlamSha256) {
    Assert-Unchanged
    Check 'Flow verifier has not changed during this run' ((File-Hash $FlowScript) -ceq $flowScriptHash)
    $folder = Join-Path $output $Label
    $arguments=@('-NoProfile','-STA','-File',$FlowScript,'-Mode',$FlowMode,'-ExpectedSha256',$Hash,'-InstalledAddinPath',$target,'-ExpectedReleaseVersion',$Version,'-OutputDirectory',$folder)
    if ($Label -eq 'upgraded-functional' -and $InstallChannel -ceq 'EXE') { $arguments += @('-GuardInstallerPath',$InstallerPath,'-ExpectedInstallerSha256',$ExpectedInstallerSha256,'-GuardUninstallerPath',(Join-Path $manager 'unins000.exe')) }
    $childExit=Run-PowerShellChild $arguments $Label
    Check ($Label+' process exits successfully') ($childExit -eq 0)
    $flow=Get-Content -LiteralPath (Join-Path $folder 'flow.private.json') -Raw | ConvertFrom-Json
    Check ($Label+' identifies the requested flow and candidate') ($flow.mode -ceq $FlowMode -and $flow.expectedSha256 -ieq $Hash -and $flow.expectedReleaseVersion -ceq $Version)
    Confirm-FlowExit $flow $folder
    Check ($Label+' parent independently confirms Excel exit') $true
    if($FlowMode -eq 'Functional') { Check ($Label+' completed functional assertions') ($flow.functional -ceq 'PASS') }
    Assert-NoExcel
    Check ($Label+' does not change installation') (Same (State) $script:lastState)
    Check ($Label+' preserves other add-ins/policies') (Same (Protected-State) $protectedBaseline)
}
function Run-InstalledVerification([string]$Label) {
    if($VerificationScope -ceq 'InstallationOnly') {
        $checks.Add([ordered]@{name=($Label+' functional assertions');status='NOT_RUN';reason='InstallationOnly observes normal startup only. Existing functional failures are not reevaluated or superseded.'})
        $result.functionalChecksSkipped++
        Run-Flow 'NormalStart' ($Label.Replace('-functional','-installation-startup'))
    } else {
        $result.functionalChecks='RUNNING';$result.functionalChecksExecuted++
        try { Run-Flow 'Functional' $Label; $result.functionalChecks='PASS' }
        catch { $result.functionalChecks='FAIL'; throw }
        if($Label -ceq 'upgraded-functional' -and $InstallChannel -ceq 'EXE') { $result.openExcelGuards='PASS' }
    }
}
function Set-RegistryValue($Key,$Value) {
    $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$Value.kind)
    $data = $Value.value
    if ($Value.kind -eq 'Binary') { $data = [Convert]::FromBase64String([string]$data) }
    if ($Value.kind -eq 'MultiString') { $data = [string[]]$data }
    if ($Value.kind -eq 'DWord') { $data = [int]$data }
    if ($Value.kind -eq 'QWord') { $data = [long]$data }
    $Key.SetValue([string]$Value.name,$data,$kind)
}
function Write-Tree([string]$Path,$Tree,$Expected) {
    Check ('Immediate registry tree comparison: '+$Path) (Same (Registry-Tree $Path) $Expected)
    if (-not $Tree.exists -and -not $Expected.exists) { return }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
    try {
        $wanted=@{}; if($Tree.exists) { foreach($value in $Tree.values) { $wanted[$value.name]=$value } }
        $prior=@{}; foreach($value in $Expected.values) { $prior[$value.name]=$value }
        foreach($name in @((@($prior.Keys)+@($wanted.Keys)) | Sort-Object -Unique)) {
            Check ('Immediate registry value comparison: '+$Path+' / '+$name) (Same (Registry-Value $key $name) $prior[$name])
            if($wanted.ContainsKey($name)) { Set-RegistryValue $key $wanted[$name] } else { $key.DeleteValue($name,$false) }
        }
        $childNames=@($Expected.children.Keys); if($Tree.exists) { $childNames+=@($Tree.children.Keys) }
        foreach($name in @($childNames | Sort-Object -Unique)) {
            $empty=[ordered]@{exists=$false;values=@();children=[ordered]@{}}
            $want=if($Tree.exists -and $Tree.children.Contains($name)){$Tree.children[$name]}else{$empty}
            $was=if($Expected.children.Contains($name)){$Expected.children[$name]}else{$empty}
            Write-Tree ($Path+'\'+$name) $want $was
        }
        $key.Flush()
    } finally { $key.Dispose() }
    if (-not $Tree.exists) {
        $now=Registry-Tree $Path
        Check ('Owned registry key is still empty before deletion: '+$Path) (-not $now.values.Count -and -not $now.children.Count)
        $parent=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey((Split-Path -Parent $Path),$true)
        if($null -ne $parent) { try{$parent.DeleteSubKey((Split-Path -Leaf $Path),$false)}finally{$parent.Dispose()} }
    }
}
function Restore-Baseline {
    $script:restoreStatus = 'RESTORE_INCOMPLETE'
    Assert-NoExcel
    $locks = @(); $held = @()
    try {
        foreach ($name in @('Local\ExcelSmartListCompare-Setup','Local\ExcelSmartListCompare.OneFile')) {
            $m = New-Object Threading.Mutex($false,$name); $locks += $m
            if (-not $m.WaitOne(0)) { throw 'A product installer is running; restoration did not change it.' }
            $held += $m
        }
        # All-or-nothing eligibility check: external changes are never adopted.
        Check 'Restoration sees exactly the recorded product state' (Same (State) $script:lastState)
        Check 'Restoration sees unchanged protected values' (Same (Protected-State) $protectedBaseline)
        foreach ($id in $baseline.files.Keys) {
            if ($null -ne $baseline.files[$id]) { Check ('Restoration backup pin: '+$id) ((File-Hash (Join-Path $backup $id)) -ceq $baseline.files[$id]) }
        }
        Write-Json 'restore-start.private.json' (State)
        # Remove only the product autoload values, then restore files before trust.
        $options = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($excelRoot+'\Options',$true)
        if ($null -ne $options) { try { foreach ($name in $openSlots) { Check ('Immediate OPEN comparison: '+$name) (Same (Registry-Value $options $name) $script:lastState.registry.opens[$name]); $options.DeleteValue($name,$false) }; $options.Flush() } finally { $options.Dispose() } }
        foreach ($pair in @(@('product',$product,$productNames),@('manager',$manager,$managerNames))) {
            foreach ($name in $pair[2]) {
                Assert-NoExcel
                $id = $pair[0]+'/'+$name; $path = Join-Path $pair[1] $name
                Assert-NoReparse $path
                Check ('Immediate file content comparison: '+$id) ((File-Hash $path) -ceq $script:lastState.files[$id])
                Check ('Immediate file metadata comparison: '+$id) (Same (File-Metadata $path) $script:lastState.metadata[$id])
                if ($null -eq $baseline.files[$id]) {
                    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
                } else {
                    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
                    if (Test-Path -LiteralPath $path) { [IO.File]::SetAttributes($path,[IO.FileAttributes]::Normal) }
                    [IO.File]::Copy((Join-Path $backup $id),$path,$true)
                    [IO.File]::SetLastWriteTimeUtc($path,[DateTime]::Parse($fileMetadata[$id].lastWriteUtc))
                    [IO.File]::SetAttributes($path,[IO.FileAttributes]$fileMetadata[$id].attributes)
                }
            }
        }
        foreach ($p in $trustPaths) {
            $old = if ($baseline.registry.trust.Contains($p)) { $baseline.registry.trust[$p] } else { [ordered]@{exists=$false;values=@();children=[ordered]@{}} }
            Write-Tree $p $old $script:lastState.registry.trust[$p]
        }
        $options = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($excelRoot+'\Options')
        try { foreach ($value in $baseline.registry.opens.Values) { if ($null -ne $value) { Check ('OPEN slot still absent: '+$value.name) ($null -eq (Registry-Value $options $value.name)); Set-RegistryValue $options $value } }; $options.Flush() } finally { $options.Dispose() }
        $addins = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($excelRoot+'\Add-in Manager')
        try { Check 'Immediate Add-in Manager comparison' (Same (Registry-Value $addins $target) $script:lastState.registry.addin); if ($null -eq $baseline.registry.addin) { $addins.DeleteValue($target,$false) } else { Set-RegistryValue $addins $baseline.registry.addin }; $addins.Flush() } finally { $addins.Dispose() }
        Write-Tree $appKey $baseline.registry.app $script:lastState.registry.app
        # Remove only newly created empty directories; never recurse over extras.
        if (-not $baselineManagerExists) {
            foreach ($p in @((Join-Path $manager 'Engine'),$manager)) {
                Assert-NoReparse $p
                if ((Test-Path -LiteralPath $p) -and @(Get-ChildItem -LiteralPath $p -Force).Count -eq 0) { [IO.Directory]::Delete($p,$false) }
            }
        }
        $restored = State
        # New slots/locations can remain tracked as explicit absence. Compare against an expanded baseline.
        foreach ($name in $openSlots) { if (-not $baseline.registry.opens.Contains($name)) { $baseline.registry.opens[$name]=$null } }
        foreach ($p in $trustPaths) { if (-not $baseline.registry.trust.Contains($p)) { $baseline.registry.trust[$p]=[ordered]@{exists=$false;values=@();children=[ordered]@{}} } }
        Check 'Original RC9 files and product values restored exactly' (Same $restored $baseline)
        Check 'No unrelated add-in or policy was changed by restoration' (Same (Protected-State) $protectedBaseline)
        Assert-InstalledPhysicalPaths
        Journal 'restored-rc9' $restored
        $script:restoreStatus = 'PASS'
    } finally {
        foreach ($m in $held) { $m.ReleaseMutex() }
        foreach ($m in $locks) { $m.Dispose() }
    }
}

$output = [IO.Path]::GetFullPath($OutputDirectory)
$artifacts = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts')).TrimEnd('\')+'\'
if (-not $output.StartsWith($artifacts,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) { throw 'Use a fresh directory strictly below this repository artifacts directory.' }
foreach ($p in @($output,$product,$manager,$InstallerPath,$ReleaseDirectory)) { Assert-NoReparse $p }
Assert-InstalledPhysicalPaths
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$ReleaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
$psExe = Join-Path $PSHOME 'powershell.exe'
if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as the ordinary desktop user, not elevated.' }
$manifest = Get-Content -LiteralPath (Join-Path $product 'install.json') -Raw | ConvertFrom-Json
if ($manifest.productId -cne $productId -or $manifest.installDirectory -ine $product -or $manifest.installerVersion -cne '0.2.0-rc.9' -or $manifest.excelVersion -notmatch '^\d+\.0$' -or -not $manifest.trustedLocation.owned) { throw 'Requires an existing recognised RC9 installation with an owned trust location.' }
$excelRoot = 'Software\Microsoft\Office\'+$manifest.excelVersion+'\Excel'
$trustRoot = $excelRoot+'\Security\Trusted Locations'
if ($manifest.trustedLocation.keyName -notmatch '^Location\d+$' -or $manifest.trustedLocation.token -notmatch '^[a-f0-9]{32}$') { throw 'Invalid baseline trust ownership.' }
$trustPaths.Add($trustRoot+'\'+$manifest.trustedLocation.keyName)
$baselineManagerExists = Test-Path -LiteralPath $manager
if ($baselineManagerExists) {
    if (-not (Test-Path -LiteralPath (Join-Path $manager 'manager.id')) -or [IO.File]::ReadAllText((Join-Path $manager 'manager.id')).Trim() -cne 'SLC-68A45C44-2026-OneFile-1') { throw 'Unrecognised manager is preserved.' }
    if (-not (Registry-Tree $appKey).exists) { throw 'Manager without matching Apps entry is preserved.' }
} elseif ((Registry-Tree $appKey).exists) { throw 'Apps entry without a manager is preserved.' }
if($InstallChannel -ceq 'Engine') {
    if($baselineManagerExists -or (Registry-Tree $appKey).exists) { throw 'The direct-engine channel requires an original baseline without an EXE manager or Apps entry.' }
    if($ExpectedSetupSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Engine channel requires an explicit ExpectedSetupSha256 for the published package engine.' }
}
if ($Mode -eq 'Execute') {
    Assert-NoExcel
    if (-not (Test-Path -LiteralPath $FlowScript -PathType Leaf)) { throw 'RC10 flow verifier is required before execution.' }
    $flowTokens=$null; $flowErrors=$null
    $flowAst=[Management.Automation.Language.Parser]::ParseFile($FlowScript,[ref]$flowTokens,[ref]$flowErrors)
    if($flowErrors.Count) { throw 'The flow verifier has parser errors.' }
    $flowParameters=@($flowAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $requiredFlowParameters=@('Mode','ExpectedSha256','InstalledAddinPath','OutputDirectory','ExpectedReleaseVersion')
    if($InstallChannel -ceq 'EXE') { $requiredFlowParameters+=@('GuardInstallerPath','ExpectedInstallerSha256','GuardUninstallerPath') }
    foreach($required in $requiredFlowParameters) {
        if($required -notin $flowParameters) { throw ('Flow verifier contract is incomplete: '+$required) }
    }
    $flowScriptHash=File-Hash $FlowScript
}
[void][IO.Directory]::CreateDirectory($output)
$backup = Join-Path $output 'baseline-backup'; [void][IO.Directory]::CreateDirectory($backup)
$payloadHashes = [ordered]@{}
$result = [ordered]@{schemaVersion=1;mode=$Mode;installChannel=$InstallChannel;verificationScope=$VerificationScope;functionalChecks='NOT_RUN';functionalChecksExecuted=0;functionalChecksSkipped=0;priorFunctionalEvidenceSuperseded=$false;openExcelGuards='NOT_RUN';exeLifecycleAcceptance=$(if($InstallChannel -ceq 'Engine'){'NOT_EVALUATED_BY_ENGINE_CHANNEL'}else{'See EXE step evidence'});status='STARTED';productMutations=0;restoration='NOT_NEEDED';restoreFilesAndRegistration='NOT_NEEDED';postRestoreVerification='NOT_RUN';nativeUi='NOT_RUN';nativeCancellation='NOT_RUN';releaseApproved=$false;fullAcceptancePassed=$false;checks=$checks;failure=$null}
try {
    $harnessMutex = New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-RC10-Lifecycle')
    $harnessHeld = $harnessMutex.WaitOne(0)
    if (-not $harnessHeld) { throw 'Another lifecycle harness is active.' }
    Check 'Pinned RC10 installer' ((File-Hash $InstallerPath) -ieq $ExpectedInstallerSha256)
    Check 'Pinned RC10 XLAM' ((File-Hash (Join-Path $ReleaseDirectory 'ExcelSmartListCompare.xlam')) -ieq $ExpectedXlamSha256)
    Check 'Pinned baseline RC9 XLAM' ((File-Hash $target) -ieq $PreviousXlamSha256 -and $manifest.sha256 -ieq $PreviousXlamSha256)
    foreach ($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md')) { $payloadHashes[$name]=File-Hash (Join-Path $ReleaseDirectory $name); Check ('Payload exists: '+$name) ($null -ne $payloadHashes[$name]) }
    if($InstallChannel -ceq 'Engine') { Check 'Direct-engine package pin' ($payloadHashes['Setup.ps1'] -ieq $ExpectedSetupSha256) }
    $baseline = State
    Write-Json 'baseline.private.json' $baseline
    $baselineOpenCount=@($baseline.registry.opens.Values | Where-Object { $null -ne $_ }).Count
    Check 'All five baseline product files present' (@($productNames | Where-Object { $null -eq $baseline.files['product/'+$_] }).Count -eq 0)
    $baselineTrust = $baseline.registry.trust[$trustPaths[0]]
    $baselineTrustExists=[bool]$baselineTrust.exists
    if($baselineTrustExists) {
        Check 'Existing baseline trust remains exactly product-owned' (@($baselineTrust.values | Where-Object { $_.name -ceq 'SLCOwnerToken' -and $_.kind -ceq 'String' -and $_.value -ceq $manifest.trustedLocation.token }).Count -eq 1 -and @($baselineTrust.values | Where-Object { $_.name -ceq 'SLCProductId' -and $_.kind -ceq 'String' -and $_.value -ceq $productId }).Count -eq 1 -and @($baselineTrust.values | Where-Object { $_.name -ceq 'Path' -and $_.kind -ceq 'String' -and ([string]$_.value).TrimEnd('\') -ieq $product }).Count -eq 1 -and $baselineTrust.values.Count -eq 5 -and $baselineTrust.children.Count -eq 0)
    } else {
        $checks.Add([ordered]@{name='Baseline trust location is absent';status='OBSERVED';reason='Preserve absence on restoration; the manifest does not authorize recreating a pre-existing missing key.'})
    }
    $protectedBaseline = Protected-State
    $fileMetadata = Backup-Files $baseline
    Write-Json 'baseline.private.json' $baseline
    Write-Json 'baseline-file-metadata.private.json' $fileMetadata
    Write-Json 'protected-baseline.private.json' $protectedBaseline
    Check 'Baseline unchanged during read-only backup' (Same (State) $baseline)
    Check 'Protected values unchanged during backup' (Same (Protected-State) $protectedBaseline)
    Journal 'baseline' $baseline
    $installedCheck=if($VerificationScope -ceq 'Full'){'Functional autoload'}else{'NormalStart only; functional assertions NOT_RUN'}
    Write-Json 'plan.private.json' ([ordered]@{baselineVersion='0.2.0-rc.9';baselineManager=$(if($baselineManagerExists){'EXE'}else{'CMD'});installChannel=$InstallChannel;verificationScope=$VerificationScope;functionalScopeNote='InstallationOnly does not reevaluate or supersede prior functional failures.';engineSha256=$ExpectedSetupSha256;steps=@(($InstallChannel+' upgrade'),$installedCheck,'NormalStart restart',($InstallChannel+' same-version repair'),$installedCheck,($InstallChannel+' removal'),'NoAddin normal start','repeat engine uninstall',($InstallChannel+' clean install when baseline contains no extra files'),$installedCheck,'conditional exact baseline restoration','RC9 baseline startup behavior');installerSha256=$ExpectedInstallerSha256;xlamSha256=$ExpectedXlamSha256;previousXlamSha256=$PreviousXlamSha256;nativeUi='NOT_RUN';nativeCancellation='NOT_RUN';exeAcceptance=$(if($InstallChannel -ceq 'Engine'){'NOT_EVALUATED_BY_ENGINE_CHANNEL'}else{'Only actual EXE evidence can establish acceptance'})})
    if($VerificationScope -ceq 'InstallationOnly') { $checks.Add([ordered]@{name='Installer/remover refusal while Excel is open';status='NOT_RUN';reason='This scope uses NormalStart, which does not execute Functional-mode installer guards.'}) }
    if ($Mode -eq 'Plan') { $result.status='PLAN_READY'; return }
    Run-PackageInstall 'upgrade'
    if($baselineTrustExists) { Check 'Upgrade keeps original trust token' ((Get-Content -LiteralPath (Join-Path $product 'install.json') -Raw | ConvertFrom-Json).trustedLocation.token -ceq $manifest.trustedLocation.token) }
    if (-not $NativeUiFirst) { Run-InstalledVerification 'upgraded-functional' }
    if ($NativeUiCheckpoint) {
        $checkpoint=Join-Path $output 'native-ui.complete.json'
        Write-Json 'native-ui-ready.private.json' ([ordered]@{status='READY';verifiedSha256=$ExpectedXlamSha256;completionFile=$checkpoint;timeoutSeconds=$NativeUiTimeoutSeconds})
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $checkpoint) -and $timer.Elapsed.TotalSeconds -lt $NativeUiTimeoutSeconds) { Start-Sleep -Milliseconds 500 }
        if(-not (Test-Path -LiteralPath $checkpoint)) { throw 'Native UI checkpoint timed out; restoration will be attempted without closing unknown Excel.' }
        $native=Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json
        Check 'Native UI checkpoint identifies this candidate and exited Excel' ($native.status -ceq 'PASS' -and $native.verifiedSha256 -ieq $ExpectedXlamSha256 -and $native.excelExited -eq $true)
        Assert-Unchanged
        $result.nativeUi='PASS'; $result['nativeUiEvidence']='native-ui.complete.json'
    }
    if ($NativeUiFirst) { Run-InstalledVerification 'upgraded-functional' }
    Run-Flow 'NormalStart' 'upgraded-restart'
    Run-PackageInstall 'repair'
    Run-InstalledVerification 'repaired-functional'
    Run-PackageUninstall
    Run-Flow 'NoAddin' 'removed-normal-start'
    Assert-Unchanged
    Check 'Repeated-uninstall engine bytes remain pinned' ((File-Hash (Join-Path $ReleaseDirectory 'Setup.ps1')) -ceq $payloadHashes['Setup.ps1'])
    $repeatExit=Run-PowerShellChild @('-NoProfile','-File',(Join-Path $ReleaseDirectory 'Setup.ps1'),'-Action','Uninstall','-ConfirmProduct',$productId) 'repeat-uninstall'
    Check 'Repeat engine uninstall succeeds without a manifest' ($repeatExit -eq 0)
    Check 'Repeat uninstall leaves absent state unchanged' (Same (State) $script:lastState)
    if (@($baseline.extras | Where-Object { $_ -like 'product/*' }).Count) {
        $checks.Add([ordered]@{name='Clean install';status='NOT_RUN';reason='Original unrelated product files are preserved; fresh trust must not enable them.'})
    } else {
        Run-PackageInstall 'clean-install'
        Run-InstalledVerification 'clean-functional'
    }
    $result.status=Lifecycle-SuccessStatus $InstallChannel $script:hadExitFailure
} catch {
    $script:failure=$_.Exception.Message
    $result.status='FAIL'
} finally {
    if ($script:mutationStarted) {
        $result.productMutations=1
        try {
            Restore-Baseline
        } catch {
            $script:restoreStatus='RESTORE_INCOMPLETE'; $result.status='FAIL'; $script:failure=([string]$script:failure+' Restoration: '+$_.Exception.Message).Trim()
            try { Write-Json 'restore-incomplete.private.json' (State) } catch { Write-Json 'restore-inspection-error.private.json' ([ordered]@{error=$_.Exception.Message}) }
        }
        if($script:restoreStatus -ceq 'PASS') {
            try {
                if($baselineOpenCount -eq 0) { Run-Flow 'NoAddin' 'restored-original-no-autoload' '0.2.0-rc.9' $PreviousXlamSha256; $script:postRestoreStatus='PASS' }
                elseif($baselineTrustExists) { Run-Flow 'NormalStart' 'restored-rc9-normal-start' '0.2.0-rc.9' $PreviousXlamSha256; $script:postRestoreStatus='PASS' }
                else { $checks.Add([ordered]@{name='Restored RC9 normal startup';status='NOT_RUN';reason='Baseline owned trust location was already absent; exact restoration preserves it.'}) }
            } catch {
                $script:postRestoreStatus='FAIL'; $result.status='FAIL'; $script:failure=([string]$script:failure+' Post-restoration verification: '+$_.Exception.Message).Trim()
                try { Write-Json 'post-restore-verification-state.private.json' (State) } catch { Write-Json 'post-restore-inspection-error.private.json' ([ordered]@{error=$_.Exception.Message}) }
            }
        }
    }
    $result.restoration=$script:restoreStatus
    $result.restoreFilesAndRegistration=$script:restoreStatus
    $result.postRestoreVerification=$script:postRestoreStatus
    if($script:hadExitFailure -and $result.status -in @('AUTOMATED_STEPS_PASS','INSTALL_ENGINE_STEPS_PASS')) { $result.status=Lifecycle-SuccessStatus $InstallChannel $true }
    $result['normalExcelExit']=if($script:hadExitFailure){'FAIL'}else{'See per-flow supervisor records'}
    $result.failure=$script:failure
    Write-Json 'lifecycle.private.json' $result
    if ($harnessHeld) { $harnessMutex.ReleaseMutex() }
    if ($null -ne $harnessMutex) { $harnessMutex.Dispose() }
}
if ($result.status -eq 'FAIL') { throw $result.failure }
