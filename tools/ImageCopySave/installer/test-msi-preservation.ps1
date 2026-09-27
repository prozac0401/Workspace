[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [ValidateSet('Inspect','Suite')][string]$Action = 'Inspect',
    [string]$PreviousMsiPath = '',
    [string]$RollbackMsiPath = '',
    [switch]$RequestElevation
)
# Targeted DEP-06 regression. The default is read-only. Suite never adopts an
# existing installation: it owns a unique artifacts directory and exact fixture
# registry values, and preserves the report and all business-folder fixtures.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$utf8 = New-Object Text.UTF8Encoding($false)
$script:preservationHarnessDirectory=$PSScriptRoot
function Assert-PlainPath([string]$Path, [string]$Boundary) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $bound = [IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    if ($full -ne $bound -and -not $full.StartsWith(($bound + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped the test boundary.' }
    $scan = $full
    while ($scan) {
        $attributes = $null
        try { $attributes = [IO.File]::GetAttributes($scan) } catch [IO.FileNotFoundException] { } catch [IO.DirectoryNotFoundException] { }
        if ($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse paths are not accepted.' }
        $scan = [IO.Path]::GetDirectoryName($scan)
    }
    return $full
}
function Read-Package([string]$Path, [bool]$IsRollback) {
    $path = (Resolve-Path -LiteralPath $Path).Path
    [void](Assert-PlainPath $path (Join-Path $root 'artifacts/image-copy-save/msi'))
    $metadataPath = Join-Path ([IO.Path]::GetDirectoryName($path)) 'build-metadata.json'
    $meta = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($meta.status -ne 'PASS' -or [bool]$meta.rollbackTest -ne $IsRollback) { throw 'Package metadata does not describe the requested verified artifact kind.' }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $meta.msiSha256) { throw 'MSI hash differs from its build metadata.' }
    if ($meta.upgradeCode -ne '{78C90F77-8CC3-4B10-BA9A-00E84ADAF375}') { throw 'Unexpected product family.' }
    if (-not $IsRollback -and $Path -eq $MsiPath) { & (Join-Path $PSScriptRoot 'verify-msi.ps1') -MsiPath $path | Out-Null }
    return [pscustomobject]@{ Path=$path; MetadataPath=$metadataPath; Metadata=$meta }
}
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
$package = Read-Package $MsiPath $false
$previous = $null; $rollback = $null
if ($PreviousMsiPath) { $previous=Read-Package $PreviousMsiPath $false; if ([Version]$previous.Metadata.version -ge [Version]$package.Metadata.version) { throw 'PreviousMsiPath must be an earlier verified version.' } }
if ($RollbackMsiPath) { $rollback=Read-Package $RollbackMsiPath $true; if ([Version]$rollback.Metadata.version -le [Version]$package.Metadata.version) { throw 'RollbackMsiPath must use a higher version for upgrade rollback coverage.' } }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Action -eq 'Suite' -and -not $admin) {
    if (-not $RequestElevation) { throw 'Suite needs normal administrator approval; use -RequestElevation. No security policy or UAC setting is changed.' }
    $arguments = @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-MsiPath',$MsiPath,'-Action','Suite')
    if ($PreviousMsiPath) { $arguments+=@('-PreviousMsiPath',$previous.Path) }
    if ($RollbackMsiPath) { $arguments+=@('-RollbackMsiPath',$rollback.Path) }
    $quoted = @($arguments | ForEach-Object { if ($_.Contains('"') -or $_ -match '[\r\n]' -or $_.EndsWith('\')) { throw 'Ambiguous elevation argument.' }; '"' + $_ + '"' }) -join ' '
    $child = Start-Process -FilePath (Join-Path $env:windir 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $quoted -Verb RunAs -WindowStyle Hidden -PassThru
    try { $child.WaitForExit(); if ($child.ExitCode -ne 0) { throw "Preservation suite failed or was blocked: $($child.ExitCode). Inspect its result.json." } } finally { $child.Dispose() }
    return
}
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N')
$output = Assert-PlainPath (Join-Path $root ('artifacts/image-copy-save/msi-preservation/' + $runId)) (Join-Path $root 'artifacts/image-copy-save/msi-preservation')
[IO.Directory]::CreateDirectory($output) | Out-Null
$installFolder = Assert-PlainPath (Join-Path $output 'installed-product') $output
$businessFolder = Assert-PlainPath (Join-Path $output 'preserved-business-fixture') $output
$resultPath = Join-Path $output 'result.json'
$machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$user = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
$save = '{9C030D44-BBFA-48B7-BD63-53470C112830}'; $copy = '{B481F5D0-A2B3-47D7-A139-B6C2F60B36DE}'
$ownedKeys = @("Software\Classes\CLSID\$save\InprocServer32", "Software\Classes\CLSID\$copy\InprocServer32", 'Software\Classes\Directory\Background\shell\Workspace.ImageCopySave.Save') + @('png','jpg','jpeg','bmp' | ForEach-Object { 'Software\Classes\SystemFileAssociations\.' + $_ + '\shell\Workspace.ImageCopySave.Copy' })
$collisionRoots = @("Software\Classes\CLSID\$save", "Software\Classes\CLSID\$copy") + @($ownedKeys[2..6])
$fixtureName = 'ImageCopySavePreservationTest_' + [Guid]::NewGuid().ToString('N')
$fixtureText = 'Synthetic preservation fixture ' + $runId
$rows = New-Object Collections.Generic.List[object]
$activeFileFixture=$null; $activeRegistryFixture=$null; $activeStreamFixture=$null
$result = [ordered]@{ status='RUNNING'; action=$Action; startedUtc=[DateTime]::UtcNow.ToString('o'); elevated=$admin; initiatingUserSid=$identity.User.Value; msi=$package.Path; msiSha256=$package.Metadata.msiSha256; previousMsi=$(if ($previous) {$previous.Path} else {$null}); rollbackMsi=$(if ($rollback) {$rollback.Path} else {$null}); installFolder=$installFolder; reports=$output; tests=$rows; explorerRestarted=$false; businessFixturesDeleted=$false; rebootRequired=$false; cleanup='NOT_STARTED' }
function Write-Result { [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 15), $utf8) }
function Add-Result([string]$Name, [string]$Status, [object]$Detail) { $rows.Add([ordered]@{ test=$Name; status=$Status; detail=$Detail; utc=[DateTime]::UtcNow.ToString('o') }); Write-Result }
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-RegistrySnapshot([Microsoft.Win32.RegistryKey]$Base, [string]$Path) {
    $key = $Base.OpenSubKey($Path)
    if ($null -eq $key) { return '<absent>' }
    try {
        $values = @($key.GetValueNames() | Sort-Object | ForEach-Object { $name=$_; $value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); [ordered]@{ name=$name; kind=[string]$key.GetValueKind($name); value=$value } })
        $subkeys = @($key.GetSubKeyNames() | Sort-Object)
        return ([ordered]@{ values=$values; subkeys=$subkeys } | ConvertTo-Json -Depth 8 -Compress)
    } finally { $key.Dispose() }
}
function Get-Associations {
    $entries = @()
    foreach ($base in @($machine,$user)) { foreach ($ext in @('png','jpg','jpeg','bmp')) { foreach ($path in @("Software\Classes\.$ext", "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.$ext\UserChoice")) { $entries += (Get-RegistrySnapshot $base $path) } } }
    return ($entries | ConvertTo-Json -Depth 10 -Compress)
}
function Get-ExistingProducts {
    $found = @()
    foreach ($base in @($machine,$user)) {
        $uninstall = $base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall')
        if ($null -eq $uninstall) { continue }
        try { foreach ($name in $uninstall.GetSubKeyNames()) { $key=$uninstall.OpenSubKey($name); if ($null -eq $key) {continue}; try { if ($key.GetValue('DisplayName') -eq 'ImageCopySave') { $found += [ordered]@{ key=$name; version=$key.GetValue('DisplayVersion'); location=$key.GetValue('InstallLocation') } } } finally { $key.Dispose() } } } finally { $uninstall.Dispose() }
    }
    return ,$found
}
function Is-Installed([object]$Expected) {
    $key = $machine.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $Expected.productCode)
    if ($null -eq $key) { return $false }
    try { if ($key.GetValue('DisplayName') -ne 'ImageCopySave') { throw 'Unexpected product identity.' }; return $true } finally { $key.Dispose() }
}
function Assert-Payload([object]$Expected) {
    if (-not (Is-Installed $Expected)) { throw 'Expected product is not installed.' }
    foreach ($entry in $Expected.files) { $path=Assert-PlainPath (Join-Path $installFolder $entry.path) $installFolder; if (-not [IO.File]::Exists($path) -or (Get-Hash $path) -ne $entry.sha256) { throw "Installed payload differs: $($entry.path)" } }
    foreach ($path in $ownedKeys) { if ((Get-RegistrySnapshot $machine $path) -eq '<absent>') { throw 'Owned registration is missing.' } }
    foreach ($path in $ownedKeys[0..1]) { $key=$machine.OpenSubKey($path); try { if ($key.GetValue('') -ne (Join-Path $installFolder 'ImageCopySave.Shell.dll')) { throw 'COM registration does not point at the fixture installation.' } } finally { $key.Dispose() } }
}
function Assert-NoProduct([object]$Expected) {
    if (Is-Installed $Expected) { throw 'Product remains installed.' }
    foreach ($entry in $Expected.files) { if (Test-Path -LiteralPath (Assert-PlainPath (Join-Path $installFolder $entry.path) $installFolder)) { throw "Owned file remains: $($entry.path)" } }
}
function Run-Msi([object]$Package, [ValidateSet('Install','Repair','Remove')][string]$Operation, [string]$Name, [bool]$ExpectBlock=$false, [bool]$ExpectRollback=$false) {
    $log = Join-Path $output ($Name + '.msiexec.log')
    $switch = $(if ($Operation -eq 'Remove') {'/x'} elseif ($Operation -eq 'Repair') {'/fa'} else {'/i'})
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:windir 'System32/msiexec.exe'; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.Arguments = $switch + ' "' + $Package.Path + '" /qn /norestart REBOOT=ReallySuppress MSIRESTARTMANAGERCONTROL=Disable INSTALLFOLDER="' + $installFolder + '" /l*v "' + $log + '"'
    $process = [Diagnostics.Process]::Start($info)
    try { $process.WaitForExit(); $code=$process.ExitCode } finally { $process.Dispose() }
    if ($code -eq 3010) { $result.rebootRequired=$true; throw 'MSI requested a reboot. The suite stops rather than treating pending removal as PASS.' }
    $text=Get-Content -LiteralPath $log -Raw
    if ($ExpectBlock) {
        if ($code -ne 1603 -or $text -notmatch 'ImageCopySave ownership guard:' -or $text -notmatch '(?m)^[^\r\n]*: ImageGuard(?:Preflight|Deferred)\. [^\r\n]* 3\.\r?$') { throw "Expected ownership guard rejection was not demonstrated: $Name, exit $code" }
    } elseif ($ExpectRollback) {
        if ($code -ne 1603 -or $text -notmatch '(?m)^[^\r\n]*: FailRollbackTest\. [^\r\n]* 3\.\r?$') { throw "Deliberate rollback failure was not demonstrated: $Name, exit $code" }
    } elseif ($code -ne 0) { throw "MSI operation failed: $Name, exit $code" }
    if ($ExpectBlock) {
        if ($script:activeFileFixture -and (Get-Hash $script:activeFileFixture.path) -ne $script:activeFileFixture.hash) { throw 'Blocked MSI changed the externally modified owned file.' }
        if ($script:activeStreamFixture) {
            $f=$script:activeStreamFixture
            if ((Get-NamedStreamHash $f.path) -ne $f.hash -or (Get-Hash $f.basePath) -ne $f.baseHash) {throw 'Blocked MSI changed the named stream or its base file.'}
        }
        if ($script:activeRegistryFixture) {
            $f=$script:activeRegistryFixture; $key=$machine.OpenSubKey($f.path)
            if ($null -eq $key) {throw 'Blocked MSI removed the external registry fixture.'}
            try {if ($key.GetValueNames() -notcontains $f.name -or $key.GetValueKind($f.name) -ne $f.kind -or $key.GetValue($f.name) -ne $f.value) {throw 'Blocked MSI changed the external registry fixture.'}} finally {$key.Dispose()}
        }
    }
    return [ordered]@{ exitCode=$code; log=[IO.Path]::GetFileName($log); expectedBlock=$ExpectBlock; expectedRollback=$ExpectRollback }
}
function Assert-Associations { if ((Get-Associations) -ne $script:associationsBefore) { throw 'Existing image association values changed. They were not automatically overwritten by recovery.' } }
function New-ExactFile([string]$Path, [byte[]]$Bytes) {
    [void](Assert-PlainPath $Path $output)
    $stream = New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Remove-ExactFile([string]$Path, [string]$ExpectedHash) {
    [void](Assert-PlainPath $Path $output)
    if (-not [IO.File]::Exists($Path)) { return }
    if ((Get-Hash $Path) -ne $ExpectedHash -or @(Get-Item -LiteralPath $Path -Stream * | Where-Object {$_.Stream -ne ':$DATA'}).Count -ne 0) { throw 'Synthetic file bytes or named streams changed externally; cleanup preserved it.' }
    # The fixture is under a unique test-owned directory. Recheck immediately.
    [void](Assert-PlainPath $Path $output)
    if ((Get-Hash $Path) -ne $ExpectedHash -or @(Get-Item -LiteralPath $Path -Stream * | Where-Object {$_.Stream -ne ':$DATA'}).Count -ne 0) { throw 'Synthetic file bytes or named streams changed before cleanup; preserved.' }
    Remove-Item -LiteralPath $Path
}
function Replace-ExactFile([string]$Path, [string]$ExpectedHash, [byte[]]$Bytes) {
    [void](Assert-PlainPath $Path $installFolder)
    # Hold an exclusive file handle throughout compare and replacement, so an
    # external writer cannot race recovery after the expected-byte comparison.
    $stream = New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-',''); if ($actual -ne $ExpectedHash) { throw 'File changed externally; fixture restore preserved it.' }; $stream.Position=0; $stream.SetLength(0); $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true) } finally { $sha.Dispose(); $stream.Dispose() }
}
function Remove-ExactRegistryValue([Microsoft.Win32.RegistryKey]$Base, [string]$Path, [string]$Name, [string]$Expected) {
    $key=$Base.OpenSubKey($Path,$true)
    if ($null -eq $key) { return }
    try { if ($key.GetValueNames() -notcontains $Name) {return}; if ($key.GetValueKind($Name) -ne [Microsoft.Win32.RegistryValueKind]::String -or $key.GetValue($Name) -ne $Expected) { throw 'Registry fixture changed externally; cleanup preserved it.' }; $key.DeleteValue($Name,$false) } finally { $key.Dispose() }
}
function Remove-EmptyKey([Microsoft.Win32.RegistryKey]$Base, [string]$Path) {
    $key=$Base.OpenSubKey($Path)
    if ($null -eq $key) {return}
    try { $empty=$key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0 } finally { $key.Dispose() }
    if ($empty) { $Base.DeleteSubKey($Path,$false) }
}
function Invoke-FreshRegistryFixture([Microsoft.Win32.RegistryKey]$Base,[string]$BaseName,[string]$Path,[scriptblock]$Body) {
    if ((Get-RegistrySnapshot $Base $Path) -ne '<absent>') {throw 'Registration appeared after preflight; collision fixture was not applied.'}
    # Journal the exact prospective ownership before creation. Any failure after
    # CreateSubKey/SetValue (including diagnostic read-back) enters the same
    # conditional cleanup; externally changed values and other values remain.
    $result.activeFixture=[ordered]@{hive=$BaseName;key=$Path;valueName=$fixtureName;value=$fixtureText;valueKind='String';phase='PREPARED';snapshot=$null}
    Write-Result
    try {
        $key=$Base.CreateSubKey($Path)
        try {
            if ($key.ValueCount -ne 0 -or $key.SubKeyCount -ne 0) {throw 'Registration changed during fixture creation; existing values were preserved.'}
            $key.SetValue($fixtureName,$fixtureText,[Microsoft.Win32.RegistryValueKind]::String)
        } finally {$key.Dispose()}
        $result.activeFixture.phase='CREATED'
        Write-Result
        $before=Get-RegistrySnapshot $Base $Path
        if ($before -eq '<absent>') {throw 'Fresh registry collision fixture was not created; MSI was not invoked.'}
        $check=$Base.OpenSubKey($Path)
        try {if ($check.GetValueNames() -notcontains $fixtureName -or $check.GetValueKind($fixtureName) -ne [Microsoft.Win32.RegistryValueKind]::String -or $check.GetValue($fixtureName) -ne $fixtureText) {throw 'Fresh collision fixture value is not exact; MSI was not invoked.'}} finally {$check.Dispose()}
        if ($BaseName -eq 'HKCU') {
            $users=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users,[Microsoft.Win32.RegistryView]::Registry64)
            try {
                $classesPath=$identity.User.Value + '_Classes\' + $Path.Substring('Software\Classes\'.Length)
                if ((Get-RegistrySnapshot $users $classesPath) -ne $before) {throw 'HKCU fixture differs from initiating-user Classes hive; MSI was not invoked.'}
            } finally {$users.Dispose()}
        }
        $result.activeFixture.phase='CREATED_AND_VERIFIED';$result.activeFixture.snapshot=$before
        Write-Result
        & $Body $before
    } finally {
        try {
            Remove-ExactRegistryValue $Base $Path $fixtureName $fixtureText
            Remove-EmptyKey $Base $Path
            $result.activeFixture.phase='EXACT_FIXTURE_CLEANED'
        } catch {
            $result.activeFixture.phase='PRESERVED_FOR_REVIEW'
            $result.activeFixture.cleanupError=$_.Exception.Message
            throw
        } finally {Write-Result}
    }
}
function With-ChangedFile([object]$Expected, [scriptblock]$Body) {
    $entry=@($Expected.files | Where-Object {$_.path -eq 'ImageCopySave.Engine.dll'})
    if ($entry.Count -ne 1) { throw 'Expected one owned engine fixture.' }
    $target=Assert-PlainPath (Join-Path $installFolder $entry[0].path) $installFolder
    $original=[IO.File]::ReadAllBytes($target)
    $backup=Join-Path $output ('owned-file-backup-' + [Guid]::NewGuid().ToString('N') + '.bin')
    New-ExactFile $backup $original
    if ((Get-Hash $backup) -ne $entry[0].sha256) {throw 'Backup differs from the verified payload.'}
    $modified=$utf8.GetBytes($fixtureText + ' externally modified owned file')
    Replace-ExactFile $target $entry[0].sha256 $modified
    $modifiedHash=Get-Hash $target
    $script:activeFileFixture=@{path=$target;hash=$modifiedHash}
    try { & $Body; if ((Get-Hash $target) -ne $modifiedHash) { throw 'MSI overwrote or deleted the external file fixture.' } }
    finally { try {Replace-ExactFile $target $modifiedHash $original} finally {$script:activeFileFixture=$null} }
}
function Initialize-NamedStreamApi {
    if (-not ('ImageCopySave.PreservationTests.NativeStream' -as [type])) {Add-Type -Path (Join-Path $script:preservationHarnessDirectory 'preservation-tests/NativeStream.cs')}
}
function Get-NamedStreamHash([string]$Path) {
    Initialize-NamedStreamApi
    $stream = [ImageCopySave.PreservationTests.NativeStream]::Open($Path,$false)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $sha.Dispose(); $stream.Dispose() }
}
function With-AddedStream([object]$Expected, [scriptblock]$Body) {
    $entry=@($Expected.files | Where-Object {$_.path -eq 'ImageCopySave.Engine.dll'})
    if ($entry.Count -ne 1) {throw 'Expected one owned engine file for the named-stream fixture.'}
    $target=Assert-PlainPath (Join-Path $installFolder $entry[0].path) $installFolder
    if ((Get-Hash $target) -ne $entry[0].sha256 -or @(Get-Item -LiteralPath $target -Stream * | Where-Object {$_.Stream -ne ':$DATA'}).Count -ne 0) {throw 'Named-stream fixture base is not the original product file or already has an external stream.'}
    $streamName=$fixtureName + '_' + [Guid]::NewGuid().ToString('N')
    $streamPath=$target + ':' + $streamName
    Initialize-NamedStreamApi
    $stream=[ImageCopySave.PreservationTests.NativeStream]::Open($streamPath,$true)
    $bytes=$utf8.GetBytes($fixtureText + ' externally added named stream')
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    $streamHash=Get-NamedStreamHash $streamPath
    $script:activeStreamFixture=@{basePath=$target;baseHash=$entry[0].sha256;path=$streamPath;hash=$streamHash}
    try {
        & $Body
        if ((Get-NamedStreamHash $streamPath) -ne $streamHash -or (Get-Hash $target) -ne $entry[0].sha256) {throw 'MSI changed the external named stream or its base file.'}
    } finally {
        try {
            [void](Assert-PlainPath $target $installFolder)
            if ((Get-Hash $target) -ne $entry[0].sha256 -or (Get-NamedStreamHash $streamPath) -ne $streamHash) {throw 'Named-stream fixture changed externally; cleanup preserved it.'}
            # -Stream removes only this unique synthetic stream, never the file
            # or another stream. The original file hash must remain unchanged.
            Remove-Item -LiteralPath $target -Stream $streamName
            if ((Get-Hash $target) -ne $entry[0].sha256) {throw 'Base file differs after named-stream cleanup.'}
        } finally {$script:activeStreamFixture=$null}
    }
}
function With-ChangedRegistration([scriptblock]$Body, [Microsoft.Win32.RegistryValueKind]$FixtureKind=[Microsoft.Win32.RegistryValueKind]::String) {
    $path=$ownedKeys[2]; $name='MUIVerb'; $key=$machine.OpenSubKey($path,$true)
    $fixtureValue=$(if ($FixtureKind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { 7391 } else { $fixtureText })
    try {
        $kind=$key.GetValueKind($name); $original=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $expectedLabel=([char[]]@(0xBCF5,0xC0AC,0xD55C,0x20,0xADF8,0xB9BC,0x20,0xC800,0xC7A5)) -join ''
        if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -or $original -ne $expectedLabel) {throw 'Registry fixture was not the original product value; no mutation was applied.'}
        $key.SetValue($name,$fixtureValue,$FixtureKind)
    } finally { $key.Dispose() }
    $script:activeRegistryFixture=@{path=$path;name=$name;kind=$FixtureKind;value=$fixtureValue}
    try { & $Body; $key=$machine.OpenSubKey($path); try { if ($key.GetValue($name) -ne $fixtureValue -or $key.GetValueKind($name) -ne $FixtureKind) { throw 'MSI overwrote or deleted the external registration fixture.' } } finally { if ($key) {$key.Dispose()} } }
    finally {
        try {
            $key=$machine.OpenSubKey($path,$true)
            if ($null -eq $key) { throw 'External registration fixture was removed; cannot restore safely.' }
            try { if ($key.GetValue($name) -ne $fixtureValue -or $key.GetValueKind($name) -ne $FixtureKind) { throw 'Registry value changed externally; recovery preserved it.' }; $key.SetValue($name,$original,$kind) } finally { $key.Dispose() }
        } finally { $script:activeRegistryFixture=$null }
    }
}
$unknownFile=$null; $unknownHash=$null; $siblingPath='Software\Classes\Directory\Background\shell\' + $fixtureName
function Add-UnknownFixtures {
    $script:unknownFile=Assert-PlainPath (Join-Path $installFolder ($fixtureName + '.txt')) $installFolder
    New-ExactFile $script:unknownFile ($utf8.GetBytes($fixtureText)); $script:unknownHash=Get-Hash $script:unknownFile
    foreach ($path in @($ownedKeys[2],$siblingPath)) { $key=$machine.CreateSubKey($path); try { if ($key.GetValueNames() -contains $fixtureName) { throw 'Unknown fixture name already exists.' }; $key.SetValue($fixtureName,$fixtureText,[Microsoft.Win32.RegistryValueKind]::String) } finally {$key.Dispose()} }
}
function Assert-UnknownFixtures {
    if (-not [IO.File]::Exists($script:unknownFile) -or (Get-Hash $script:unknownFile) -ne $script:unknownHash) { throw 'Unknown installation file was changed or removed.' }
    foreach ($path in @($ownedKeys[2],$siblingPath)) { $key=$machine.OpenSubKey($path); if ($null -eq $key) {throw 'Unknown registry fixture was removed.'}; try { if ($key.GetValueNames() -notcontains $fixtureName -or $key.GetValue($fixtureName) -ne $fixtureText -or $key.GetValueKind($fixtureName) -ne [Microsoft.Win32.RegistryValueKind]::String) {throw 'Unknown registry fixture changed.'} } finally {$key.Dispose()} }
    Assert-Associations
}
Write-Result
try {
    $existing=Get-ExistingProducts
    $collisions=@()
    foreach ($baseName in @('HKLM','HKCU')) { $base=$(if($baseName -eq 'HKLM'){$machine}else{$user}); foreach ($path in $collisionRoots) { if ((Get-RegistrySnapshot $base $path) -ne '<absent>') { $collisions += $baseName + '\' + $path } } }
    $defaultFolder=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Workspace/ImageCopySave'
    $canRun=$existing.Count -eq 0 -and $collisions.Count -eq 0 -and -not (Test-Path -LiteralPath $defaultFolder)
    $result.preflight=[ordered]@{ canRunSuite=$canRun; existingProducts=$existing; registryCollisions=$collisions; defaultInstallDirectoryExists=(Test-Path -LiteralPath $defaultFolder); fixtureDirectoryExists=(Test-Path -LiteralPath $installFolder) }
    if ($Action -eq 'Inspect') { $result.status='PASS'; $result.note='Read-only preflight; no install, registry edit, or product-file mutation was performed.'; return }
    if (-not $canRun) { $result.status='BLOCKED'; throw 'Existing ImageCopySave installation, registration, or default directory found. No fixture was applied. Coordinate migration/removal separately; this suite never adopts it.' }
    $script:associationsBefore=Get-Associations
    [IO.Directory]::CreateDirectory($businessFolder) | Out-Null
    $businessPng=Join-Path $businessFolder 'preserve-user-image.png'
    New-ExactFile $businessPng ([Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='))
    $businessHash=Get-Hash $businessPng
    foreach ($baseName in @('HKLM','HKCU')) {
        $base=$(if($baseName -eq 'HKLM'){$machine}else{$user})
        for ($i=0; $i -lt $collisionRoots.Count; $i++) {
            $path=$collisionRoots[$i]
            Invoke-FreshRegistryFixture $base $baseName $path {
                param($before)
                $detail=Run-Msi $package Install ('fresh-' + $baseName + '-root-' + $i) $true
                if ((Get-RegistrySnapshot $base $path) -ne $before) {throw 'Existing collision registration changed.'}
                Assert-NoProduct $package.Metadata
                if (Test-Path -LiteralPath $installFolder) {throw 'Blocked fresh install created its target directory.'}
                Add-Result ('fresh-' + $baseName + '-root-' + $i) 'PASS' $detail
            }
        }
    }
    foreach ($kind in @('empty-directory','existing-file')) {
        [IO.Directory]::CreateDirectory($installFolder) | Out-Null
        $collisionFile=Join-Path $installFolder 'ImageCopySave.Engine.dll'; $collisionHash=$null
        if ($kind -eq 'existing-file') {New-ExactFile $collisionFile ($utf8.GetBytes($fixtureText)); $collisionHash=Get-Hash $collisionFile}
        try { $detail=Run-Msi $package Install ('fresh-' + $kind) $true; if (-not [IO.Directory]::Exists($installFolder)) {throw 'Collision directory removed.'}; if ($collisionHash -and (Get-Hash $collisionFile) -ne $collisionHash) {throw 'Collision file changed.'}; if (Is-Installed $package.Metadata) {throw 'Blocked collision install registered a product.'}; Add-Result ('fresh-' + $kind) 'PASS' $detail }
        finally { if ($collisionHash) {Remove-ExactFile $collisionFile $collisionHash}; [void](Assert-PlainPath $installFolder $output); if (@([IO.Directory]::EnumerateFileSystemEntries($installFolder)).Count -eq 0) {[IO.Directory]::Delete($installFolder,$false)} }
    }
    if ($rollback) { $detail=Run-Msi $rollback Install 'fresh-rollback' $false $true; Assert-NoProduct $rollback.Metadata; foreach($path in $collisionRoots){if((Get-RegistrySnapshot $machine $path) -ne '<absent>'){throw 'Fresh rollback left product registration root.'}}; if(Test-Path -LiteralPath $installFolder){throw 'Fresh rollback left its installation directory.'}; Add-Result 'fresh-rollback' 'PASS' $detail } else {Add-Result 'fresh-rollback' 'NOT RUN' 'No deliberately failing rollback MSI supplied.'}
    $starting=$(if($previous){$previous}else{$package})
    $detail=Run-Msi $starting Install 'fixture-install'; Assert-Payload $starting.Metadata; Add-Result 'fixture-install' 'PASS' $detail
    Add-UnknownFixtures
    if ($previous) {
        With-ChangedFile $previous.Metadata { $detail=Run-Msi $package Install 'upgrade-block-modified-file' $true; if(-not(Is-Installed $previous.Metadata) -or (Is-Installed $package.Metadata)){throw 'Blocked upgrade changed product registration.'}; Add-Result 'upgrade-block-modified-file' 'PASS' $detail }
        With-ChangedRegistration { $detail=Run-Msi $package Install 'upgrade-block-modified-registration' $true; if(-not(Is-Installed $previous.Metadata) -or (Is-Installed $package.Metadata)){throw 'Blocked upgrade changed product registration.'}; Add-Result 'upgrade-block-modified-registration' 'PASS' $detail }
        Assert-Payload $previous.Metadata; Assert-UnknownFixtures
        $detail=Run-Msi $package Install 'upgrade-preserve-unknown'; Assert-Payload $package.Metadata; if(Is-Installed $previous.Metadata){throw 'Old product remains registered after upgrade.'}; Assert-UnknownFixtures; Add-Result 'upgrade-preserve-unknown' 'PASS' $detail
    } else { Add-Result 'upgrade-preservation' 'NOT RUN' 'No previous verified MSI supplied.' }
    if ($rollback) { $detail=Run-Msi $rollback Install 'upgrade-rollback' $false $true; Assert-Payload $package.Metadata; if(Is-Installed $rollback.Metadata){throw 'Rollback product remains registered.'}; Assert-UnknownFixtures; Add-Result 'upgrade-rollback' 'PASS' $detail } else {Add-Result 'upgrade-rollback' 'NOT RUN' 'No higher-version deliberately failing MSI supplied.'}
    foreach ($operation in @('Repair','Remove')) {
        With-AddedStream $package.Metadata { $detail=Run-Msi $package $operation ($operation.ToLowerInvariant() + '-block-named-stream') $true; if(-not(Is-Installed $package.Metadata)){throw 'Blocked operation removed product registration.'}; Assert-UnknownFixtures; Add-Result ($operation.ToLowerInvariant() + '-block-named-stream') 'PASS' $detail }
        Assert-Payload $package.Metadata
        With-ChangedFile $package.Metadata { $detail=Run-Msi $package $operation ($operation.ToLowerInvariant() + '-block-modified-file') $true; if(-not(Is-Installed $package.Metadata)){throw 'Blocked operation removed product registration.'}; Assert-UnknownFixtures; Add-Result ($operation.ToLowerInvariant() + '-block-modified-file') 'PASS' $detail }
        Assert-Payload $package.Metadata
        With-ChangedRegistration { $detail=Run-Msi $package $operation ($operation.ToLowerInvariant() + '-block-modified-registration') $true; if(-not(Is-Installed $package.Metadata)){throw 'Blocked operation removed product registration.'}; Assert-UnknownFixtures; Add-Result ($operation.ToLowerInvariant() + '-block-modified-registration') 'PASS' $detail }
        Assert-Payload $package.Metadata
        With-ChangedRegistration { $detail=Run-Msi $package $operation ($operation.ToLowerInvariant() + '-block-registry-type') $true; if(-not(Is-Installed $package.Metadata)){throw 'Blocked operation removed product registration.'}; Assert-UnknownFixtures; Add-Result ($operation.ToLowerInvariant() + '-block-registry-type') 'PASS' $detail } ([Microsoft.Win32.RegistryValueKind]::DWord)
        Assert-Payload $package.Metadata
    }
    $engineEntry=@($package.Metadata.files | Where-Object {$_.path -eq 'ImageCopySave.Engine.dll'})[0]
    $enginePath=Assert-PlainPath (Join-Path $installFolder $engineEntry.path) $installFolder
    $engineBackup=Join-Path $output 'missing-file-repair-backup.bin'
    [IO.File]::Copy($enginePath,$engineBackup,$false)
    if((Get-Hash $engineBackup) -ne $engineEntry.sha256){throw 'Missing-file repair backup differs.'}
    Remove-ExactFile $enginePath $engineEntry.sha256
    try { $detail=Run-Msi $package Repair 'repair-missing-file'; Assert-Payload $package.Metadata; Assert-UnknownFixtures; Add-Result 'repair-missing-file' 'PASS' $detail }
    finally { if(-not(Test-Path -LiteralPath $enginePath)){[void](Assert-PlainPath $enginePath $installFolder); [IO.File]::Copy($engineBackup,$enginePath,$false)} }
    $detail=Run-Msi $package Remove 'remove-preserve-unknown'; Assert-NoProduct $package.Metadata; Assert-UnknownFixtures
    foreach($path in $ownedKeys) { $key=$machine.OpenSubKey($path); if($key){try{foreach($name in @('','ThreadingModel','ExplorerCommandHandler','MUIVerb','MultiSelectModel','NeverDefault')){if($key.GetValueNames() -contains $name){throw 'Owned registration value remains after uninstall.'}}}finally{$key.Dispose()}} }
    if((Get-Hash $businessPng) -ne $businessHash){throw 'Business PNG fixture changed.'}
    Add-Result 'remove-preserve-unknown' 'PASS' $detail
    # Cleanup only our exact synthetic unknown fixtures after preservation has
    # been asserted. No recursive directory or registry deletion is used.
    Remove-ExactFile $unknownFile $unknownHash
    foreach($path in @($ownedKeys[2],$siblingPath)){Remove-ExactRegistryValue $machine $path $fixtureName $fixtureText; Remove-EmptyKey $machine $path}
    [void](Assert-PlainPath $installFolder $output)
    if([IO.Directory]::Exists($installFolder) -and @([IO.Directory]::EnumerateFileSystemEntries($installFolder)).Count -eq 0){[IO.Directory]::Delete($installFolder,$false)}
    Assert-Associations
    $result.cleanup='EXACT_SYNTHETIC_FIXTURES_REMOVED_BUSINESS_FIXTURE_PRESERVED'
    $result.status=$(if(@($rows | Where-Object {$_.status -eq 'NOT RUN'}).Count -gt 0){'PASS_WITH_NOT_RUN'}else{'PASS'})
    $result.businessFixtureSha256=$businessHash
    $result.note='MSI scope only. Does not establish Explorer menu, external-application, reboot, hostile concurrent administrator mutation, or power-loss behavior.'
} catch {
    if($result.status -ne 'BLOCKED'){$result.status='FAIL'}
    $result.error=$_.Exception.Message
    $result.cleanup='STOPPED_FOR_REVIEW_NO_AUTOMATIC_PRODUCT_REMOVAL'
    throw
} finally {
    $result.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $result.installedProductsAfter=Get-ExistingProducts
    Write-Result
    $machine.Dispose(); $user.Dispose()
    Write-Output "Preservation result: $resultPath"
}
