# Developer-only isolated build/runtime helper. It never installs or unregisters a product.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$ApprovedTemporaryVbaAccess,
    [switch]$ProbeOnly,
    [switch]$BuildOnly,
    [ValidateSet('0.2.0-rc.10','0.2.0-rc.11','0.2.0-rc.12')][string]$ExpectedReleaseVersion='0.2.0-rc.11'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($ProbeOnly -and $BuildOnly){throw 'Choose ProbeOnly or BuildOnly, not both.'}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$toolRoot=Split-Path -Parent $PSScriptRoot
$artifacts=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith(($artifacts.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be below repository artifacts.'}
if(Test-Path -LiteralPath $output){throw 'Output directory already exists; choose a fresh directory.'}
$ancestor=$output
while($ancestor -and $ancestor.Length -ge $artifacts.Length){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Output may not pass through reparse points.'}
    $ancestor=Split-Path -Parent $ancestor
}
[void][IO.Directory]::CreateDirectory($output)
$evidence=Join-Path $output 'build.private';[void][IO.Directory]::CreateDirectory($evidence)
$sourceSnapshot=Join-Path $evidence 'source';[void][IO.Directory]::CreateDirectory($sourceSnapshot)
$utf8=New-Object Text.UTF8Encoding($false)
$audit=[ordered]@{
    schemaVersion=1;mode=$(if($ProbeOnly){'Probe'}elseif($BuildOnly){'BuildOnly'}else{'BuildAndTest'});status='NOT_RUN';phase='preflight'
    runtimeTests=$(if($BuildOnly){'NOT_RUN: user-requested wording-only release'}else{'NOT_RUN'})
    startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null;failure=$null;cleanupErrors=@()
    releaseVersion=$null;expectedSha256=$null;actualSha256=$null;finalSha256=$null;candidatePath=$null
    tests=@();owner=$null;existingExcelBefore=@();existingExcelPreserved=$null;excelExited=$null
    officeVersion=$null;excelVersion=$null;probe='NOT_RUN';sourceAudit=@();sourceStage=$null;inputHashes=@()
    inMemoryImportAudit='NOT_RUN';serializedSourceAudit='NOT_RUN';candidateSaved=$false
    approvedTemporaryVbaAccess=[bool]$ApprovedTemporaryVbaAccess;securityChanged=$false;accessBefore=$null
    accessAfter=$null;accessRestored=$null;externalSecurityChangeDetected=$false
    installedBaseline=$null;installedPreserved=$null;installedTests='NOT_RUN';nativeInputTests='NOT_RUN';releaseApproved=$false
}
$excel=$null;$process=$null;$bootstrap=$null;$bootstrapBook=$null;$candidateBook=$null;$probeBook=$null;$harnessBook=$null
$installedPath=$null;$installedManifest=$null;$installedSnapshot=$null;$securityPath=$null
$accessSnapshotTaken=$false;$securityWritten=$false;$unknownBooks=$false;$ownedBooks=New-Object Collections.ArrayList
$mutex=$null;$locked=$false;$exitCode=1
function Save-Audit {
    $destination=Join-Path $output 'usability.private.json';$temporary=Join-Path $output 'usability.private.writing'
    [IO.File]::WriteAllText($temporary,($audit | ConvertTo-Json -Depth 18),$utf8)
    if([IO.File]::Exists($destination)){[IO.File]::Replace($temporary,$destination,[NullString]::Value)}else{[IO.File]::Move($temporary,$destination)}
}
function Set-Phase([string]$Name){
    $audit.phase=$Name;$audit.lastPhaseUtc=[DateTime]::UtcNow.ToString('o');Save-Audit
}
function Load-HelperFunctions([string]$Path,[string[]]$Names){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('Cannot parse helper source: '+$Path)}
    foreach($name in $Names){
        $found=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$false))
        if($found.Count -ne 1){throw ('Expected exactly one helper: '+$name)}
        # Define in script scope; never execute either script's top-level dispatcher.
        $definition=$found[0].Extent.Text -replace ('^function\s+'+[regex]::Escape($name)+'\b'),('function script:'+$name)
        . ([scriptblock]::Create($definition))
    }
}
Load-HelperFunctions (Join-Path $toolRoot 'Setup.ps1') @('Release-Com','New-SessionBootstrap','Bytes-Sha256','Read-ZipText','Write-ZipText','Write-PackageMetadata')
Load-HelperFunctions (Join-Path $PSScriptRoot 'Build-ExcelCandidate.ps1') @('Candidate-Failure','Read-AccessValue','Same-AccessValue','Assert-VbaPolicy','Normalize-Vba','Record-SourceAudit')
function Hash-File([string]$Path){
    # Loaded add-ins may hold a write-capable handle; read without taking an exclusive share.
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
    finally{$hasher.Dispose();$stream.Dispose()}
}
function Process-Snapshot {
    return @(Get-Process EXCEL -ErrorAction SilentlyContinue | ForEach-Object {
        try{[ordered]@{pid=$_.Id;startTimeUtcTicks=$_.StartTime.ToUniversalTime().Ticks}}finally{$_.Dispose()}
    })
}
function Read-KeyValues([string]$Path,[string]$NamePattern='.*'){
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    try{
        if($null -eq $key){return [ordered]@{present=$false;values=@()}}
        $values=@(foreach($name in @($key.GetValueNames() | Where-Object {$_ -match $NamePattern} | Sort-Object)){
            [ordered]@{name=$name;kind=[string]$key.GetValueKind($name);value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
        })
        return [ordered]@{present=$true;values=$values}
    }finally{if($null -ne $key){$key.Close()}}
}
function Installation-Snapshot {
    $files=@()
    if($null -ne $installedManifest){
        foreach($name in @('install.json','ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md')){
            $path=Join-Path ([IO.Path]::GetDirectoryName($installedPath)) $name
            $files+=@([ordered]@{name=$name;present=(Test-Path -LiteralPath $path -PathType Leaf);sha256=$(if(Test-Path -LiteralPath $path -PathType Leaf){Hash-File $path}else{$null})})
        }
    }
    $prefix='Software\Microsoft\Office\'+$audit.officeVersion+'\Excel\'
    $trust=$null
    if($null -ne $installedManifest -and $null -ne $installedManifest.PSObject.Properties['trustedLocation']){
        $trust=Read-KeyValues ($prefix+'Security\Trusted Locations\'+[string]$installedManifest.trustedLocation.keyName)
    }
    return [ordered]@{files=$files;options=(Read-KeyValues ($prefix+'Options') '^OPEN\d*$');manager=(Read-KeyValues ($prefix+'Add-in Manager') 'ExcelSmartListCompare');trust=$trust}
}
function Assert-OwnedApplication {
    if($null -eq $excel -or $null -eq $audit.owner){throw 'Owned Excel connection is unavailable.'}
    [uint32]$actual=0
    Set-Phase 'before-application-hwnd'
    $appHwnd=[IntPtr]$excel.Hwnd
    Set-Phase 'after-application-hwnd'
    [void][SlcIsolatedBinding]::GetWindowThreadProcessId($appHwnd,[ref]$actual)
    if($actual -ne $audit.owner.pid){throw 'Application does not belong to the launched PID.'}
    $check=Get-Process -Id $actual -ErrorAction Stop
    try{if($check.StartTime.ToUniversalTime().Ticks -ne $audit.owner.startTimeUtcTicks){throw 'Excel PID identity changed.'}}finally{$check.Dispose()}
}
function Assert-OwnedWorkspace {
    Assert-OwnedApplication
    Set-Phase 'before-protected-view-count'
    $protectedCount=[int]$excel.ProtectedViewWindows.Count
    Set-Phase 'after-protected-view-count'
    if($protectedCount -gt 0){$script:unknownBooks=$true;throw 'Unexpected Protected View document; preserve it and refuse Quit.'}
    Set-Phase 'before-workbooks-count'
    $workbookCount=[int]$excel.Workbooks.Count
    Set-Phase 'after-workbooks-count'
    for($index=1;$index -le $workbookCount;$index++){
        Set-Phase ('before-workbook-item-'+$index)
        $observed=$excel.Workbooks.Item($index);$allowed=$false
        Set-Phase ('after-workbook-item-'+$index)
        foreach($owned in $ownedBooks){if([object]::ReferenceEquals($observed,$owned)){$allowed=$true;break}}
        if(-not $allowed -and $installedPath){
            Set-Phase ('before-workbook-identity-'+$index)
            $observedPath=[string]$observed.FullName;$observedAddin=[bool]$observed.IsAddin
            Set-Phase ('after-workbook-identity-'+$index)
            if($observedPath -ieq $installedPath -and $observedAddin){$allowed=$true}
        }
        if(-not $allowed){$script:unknownBooks=$true;throw 'Unexpected workbook in owned Excel; it is preserved and Quit is refused.'}
        $observed=$null;$owned=$null
    }
}
function Close-OwnedBook($Book){
    if($null -eq $Book){return}
    Assert-OwnedApplication
    if(-not $ownedBooks.Contains($Book)){throw 'Refusing to close an unowned workbook.'}
    Set-Phase 'before-owned-book-close'
    $Book.Close($false)
    Set-Phase 'after-owned-book-close'
    [void]$ownedBooks.Remove($Book);Release-Com $Book
}
function Assert-SerializedSource($Book){
    $project=$null;$components=$null;$component=$null;$codeModule=$null
    try{
        $project=$Book.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$Book,$null)
        $components=$project.VBComponents
        foreach($name in $imports){
            $component=$components.Item([IO.Path]::GetFileNameWithoutExtension($name));$codeModule=$component.CodeModule
            Record-SourceAudit ([string]$component.Name) ([IO.File]::ReadAllText((Join-Path $sourceSnapshot $name),[Text.Encoding]::ASCII)) ([string]$codeModule.Lines(1,$codeModule.CountOfLines))
            Release-Com $codeModule;$codeModule=$null;Release-Com $component;$component=$null
        }
        $component=$components.Item([string]$Book.CodeName);$codeModule=$component.CodeModule
        Record-SourceAudit 'ThisWorkbook' ([IO.File]::ReadAllText((Join-Path $sourceSnapshot 'ThisWorkbook_events.txt'),[Text.Encoding]::ASCII)) ([string]$codeModule.Lines(1,$codeModule.CountOfLines))
    }finally{Release-Com $codeModule;Release-Com $component;Release-Com $components;Release-Com $project}
}
try{
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Use Windows PowerShell 5.1.'}
    $mutex=New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-Setup')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw (Candidate-Failure 'Another product operation is running.' 'BLOCKED_ENV' 4)}
    $audit.existingExcelBefore=@(Process-Snapshot)
    $curVer=[Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('Excel.Application\CurVer')
    try{$progId=if($curVer){[string]$curVer.GetValue('')}else{''}}finally{if($curVer){$curVer.Close()}}
    if($progId -notmatch '^Excel\.Application\.(\d+)$'){throw 'Cannot determine installed Excel version.'}
    $audit.officeVersion=$Matches[1]+'.0'
    Assert-VbaPolicy $audit.officeVersion
    $local=[Environment]::GetFolderPath('LocalApplicationData')
    $installedDirectory=Join-Path $local 'ExcelSmartListCompare';$manifestPath=Join-Path $installedDirectory 'install.json'
    if(Test-Path -LiteralPath $installedDirectory){
        if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'Existing product folder has no recognized manifest.'}
        $installedManifest=[IO.File]::ReadAllText($manifestPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if([string]$installedManifest.productId -cne 'SLC-68A45C44-2026' -or [IO.Path]::GetFullPath([string]$installedManifest.installDirectory) -ine $installedDirectory){throw 'Existing product manifest identity mismatch.'}
        $installedPath=Join-Path $installedDirectory 'ExcelSmartListCompare.xlam'
        if((Hash-File $installedPath) -ine [string]$installedManifest.sha256){throw 'Existing product hash mismatch; preserve and stop.'}
    }
    $installedSnapshot=Installation-Snapshot;$audit.installedBaseline=$installedSnapshot
    $securityPath='Software\Microsoft\Office\'+$audit.officeVersion+'\Excel\Security'
    $audit.accessBefore=Read-AccessValue $securityPath;$accessSnapshotTaken=$true
    $alreadyEnabled=$audit.accessBefore.present -and $audit.accessBefore.kind -ceq 'DWord' -and $audit.accessBefore.value -eq 1
    if(-not $alreadyEnabled -and -not $ApprovedTemporaryVbaAccess){throw (Candidate-Failure 'Temporary VBA project access requires explicit approval.' 'BLOCKED_POLICY' 5)}
    if(-not $audit.accessBefore.keyPresent){throw (Candidate-Failure 'Excel security key is absent; this helper does not create it.' 'BLOCKED_POLICY' 5)}
    $imports=@('CSLCList.cls','CSLCAppEvents.cls','modSLCNormalize.bas','modSLCMain.bas','modSLCReport.bas')
    foreach($name in ($imports+@('ThisWorkbook_events.txt','customUI14.xml'))){
        Copy-Item -LiteralPath (Join-Path $toolRoot ('src/'+$name)) -Destination (Join-Path $sourceSnapshot $name)
        $audit.inputHashes+=@([ordered]@{name=$name;sha256=(Hash-File (Join-Path $sourceSnapshot $name))})
    }
    foreach($name in ($imports+@('ThisWorkbook_events.txt'))){if(@([IO.File]::ReadAllBytes((Join-Path $sourceSnapshot $name)) | Where-Object {$_ -gt 127}).Count){throw 'VBA imports must be ASCII exports.'}}
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class SlcIsolatedBinding {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lparam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool IsWow64Process(IntPtr process, out bool wow64);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr data);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out object obj);
    public static IntPtr[] NativeWindows(uint pid) {
        var found=new List<IntPtr>();
        EnumProc children=(h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid){var name=new StringBuilder(64);GetClassName(h,name,64);if(name.ToString()=="EXCEL7")found.Add(h);}return true;};
        EnumProc top=(h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid)EnumChildWindows(h,children,IntPtr.Zero);return true;};
        EnumWindows(top,IntPtr.Zero);return found.ToArray();
    }
}
'@
    Assert-VbaPolicy $audit.officeVersion
    if(-not (Same-AccessValue $audit.accessBefore (Read-AccessValue $securityPath))){throw 'VBA access preference changed externally before write.'}
    if(-not $alreadyEnabled){
        $prior=[ordered]@{keyPath=$securityPath;valueName='AccessVBOM';snapshot=$audit.accessBefore;temporaryValue=1;temporaryKind='DWord';approvedTemporaryVbaAccess=$true}
        $stream=[IO.File]::Open((Join-Path $evidence 'access-before.private.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        $writer=New-Object IO.StreamWriter($stream,$utf8)
        try{$writer.Write(($prior | ConvertTo-Json -Depth 8));$writer.Flush();$stream.Flush($true)}finally{$writer.Dispose()}
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($securityPath,$true)
        try{
            if($null -eq $key -or -not (Same-AccessValue $audit.accessBefore (Read-AccessValue $securityPath))){throw 'VBA preference changed before temporary write.'}
            $securityWritten=$true;$audit.securityChanged=$true;$audit.phase='before-temporary-access';Save-Audit
            $key.SetValue('AccessVBOM',1,[Microsoft.Win32.RegistryValueKind]::DWord);$key.Flush()
        }finally{if($key){$key.Close()}}
    }
    $pathKey=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe')
    if($null -eq $pathKey){$pathKey=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe')}
    try{if($null -eq $pathKey){throw 'Excel executable registration missing.'};$excelPath=[string]$pathKey.GetValue('')}finally{if($pathKey){$pathKey.Close()}}
    $bootstrap=New-SessionBootstrap
    $audit.phase='launching';Save-Audit
    $process=Start-Process -FilePath $excelPath -ArgumentList @('/x',('"'+$bootstrap+'"')) -WindowStyle Hidden -PassThru
    $audit.owner=[ordered]@{pid=$process.Id;startTimeUtcTicks=$process.StartTime.ToUniversalTime().Ticks}
    if(@($audit.existingExcelBefore | Where-Object {$_.pid -eq $audit.owner.pid}).Count){throw 'Launch returned a pre-existing Excel PID.'}
    Save-Audit
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while($null -eq $excel -and $timer.Elapsed.TotalSeconds -lt 30 -and -not $process.HasExited){
        Set-Phase 'before-native-window-enumeration'
        $nativeWindows=[SlcIsolatedBinding]::NativeWindows([uint32]$audit.owner.pid)
        Set-Phase 'after-native-window-enumeration'
        foreach($window in $nativeWindows){
            $native=$null;$dispatch=[Guid]'00020400-0000-0000-C000-000000000046'
            Set-Phase 'before-accessible-object'
            $hr=[SlcIsolatedBinding]::AccessibleObjectFromWindow($window,[uint32]4294967280,[ref]$dispatch,[ref]$native)
            Set-Phase 'after-accessible-object'
            if($hr -eq 0 -and $null -ne $native){
                try{
                    Set-Phase 'before-native-application'
                    $excel=$native.Application
                    Set-Phase 'after-native-application'
                }finally{Release-Com $native;$native=$null}
                if($null -ne $excel){break}
            }
        }
        if($null -eq $excel){Start-Sleep -Milliseconds 200}
    }
    if($null -eq $excel){throw 'Could not bind the launched PID through EXCEL7; no existing Excel was queried.'}
    Assert-OwnedApplication
    # Establish the bootstrap and every already-open document before changing
    # application state or closing anything in this new normal-start instance.
    Set-Phase 'before-bootstrap-item'
    $bootstrapBook=$excel.Workbooks.Item([IO.Path]::GetFileName($bootstrap))
    Set-Phase 'after-bootstrap-item'
    Set-Phase 'before-bootstrap-fullname'
    $bootstrapFullName=[IO.Path]::GetFullPath([string]$bootstrapBook.FullName)
    Set-Phase 'after-bootstrap-fullname'
    if($bootstrapFullName -ine $bootstrap){$unknownBooks=$true;throw 'Bootstrap workbook path mismatch.'}
    [void]$ownedBooks.Add($bootstrapBook)
    Assert-OwnedWorkspace
    $audit.startupWorkspaceVerified=$true;Set-Phase 'startup-workspace-verified'
    Set-Phase 'before-automation-security'
    $excel.AutomationSecurity=2
    Set-Phase 'after-automation-security'
    Set-Phase 'before-visible'
    $excel.Visible=$false
    Set-Phase 'after-visible'
    Set-Phase 'before-user-control'
    $excel.UserControl=$false
    Set-Phase 'after-user-control'
    Set-Phase 'before-disable-events'
    $excel.EnableEvents=$false
    Set-Phase 'after-disable-events'
    Set-Phase 'before-excel-version'
    $audit.excelVersion=[string]$excel.Version
    $excelBuild=[string]$excel.Build
    Set-Phase 'after-excel-version'
    $wow64=$false;$processBits=$null;$bitnessError=$null
    if([SlcIsolatedBinding]::IsWow64Process($process.Handle,[ref]$wow64)){
        $processBits=if([Environment]::Is64BitOperatingSystem -and -not $wow64){64}else{32}
    }else{$bitnessError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
    $audit.environment=[ordered]@{osVersion=[Environment]::OSVersion.VersionString;powerShellVersion=$PSVersionTable.PSVersion.ToString();excelVersion=$audit.excelVersion;excelBuild=$excelBuild;excelProcessBitness=$processBits;bitnessProbe='IsWow64Process';bitnessError=$bitnessError}
    Close-OwnedBook $bootstrapBook;$bootstrapBook=$null
    Set-Phase 'before-probe-book-add'
    $probeBook=$excel.Workbooks.Add(-4167);[void]$ownedBooks.Add($probeBook)
    Set-Phase 'after-probe-book-add'
    Assert-OwnedWorkspace
    $project=$null;$probeComponents=$null
    try{
        Set-Phase 'before-probe-vbproject'
        $project=$probeBook.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$probeBook,$null)
        Set-Phase 'after-probe-vbproject'
        Set-Phase 'before-probe-components'
        $probeComponents=$project.VBComponents;$null=$probeComponents.Count
        Set-Phase 'after-probe-components'
    }finally{Release-Com $probeComponents;$probeComponents=$null;Release-Com $project;$project=$null}
    $audit.probe='PASS';$audit.phase='probe-complete';Save-Audit
    if($ProbeOnly){Close-OwnedBook $probeBook;$probeBook=$null;$audit.status='PASS';$exitCode=0}
    else{
        $candidateBook=$probeBook;$probeBook=$null
        $project=$null;$components=$null;$component=$null;$codeModule=$null
        try{
            $project=$candidateBook.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$candidateBook,$null)
            $components=$project.VBComponents;$audit.sourceStage='in-memory'
            foreach($name in $imports){
                $component=$components.Import((Join-Path $sourceSnapshot $name));$codeModule=$component.CodeModule
                Record-SourceAudit ([string]$component.Name) ([IO.File]::ReadAllText((Join-Path $sourceSnapshot $name),[Text.Encoding]::ASCII)) ([string]$codeModule.Lines(1,$codeModule.CountOfLines))
                Release-Com $codeModule;$codeModule=$null;Release-Com $component;$component=$null
            }
            $component=$components.Item([string]$candidateBook.CodeName);$codeModule=$component.CodeModule
            if($codeModule.CountOfLines -gt 0){$codeModule.DeleteLines(1,$codeModule.CountOfLines)}
            $events=[IO.File]::ReadAllText((Join-Path $sourceSnapshot 'ThisWorkbook_events.txt'),[Text.Encoding]::ASCII)
            $codeModule.AddFromString($events);Record-SourceAudit 'ThisWorkbook' $events ([string]$codeModule.Lines(1,$codeModule.CountOfLines))
            $project.Name='SLC2026';$audit.inMemoryImportAudit='PASS'
        }finally{Release-Com $codeModule;Release-Com $component;Release-Com $components;Release-Com $project}
        $candidate=Join-Path $output ('ExcelSmartListCompare-'+$ExpectedReleaseVersion+'-'+[Guid]::NewGuid().ToString('N')+'.xlam')
        $candidateBook.IsAddin=$true;$candidateBook.SaveAs($candidate,55)
        Close-OwnedBook $candidateBook;$candidateBook=$null
        Write-PackageMetadata $candidate (Join-Path $sourceSnapshot 'customUI14.xml')
        $audit.candidatePath=$candidate;$audit.candidateSaved=$true
        $audit.expectedSha256=Hash-File $candidate;$audit.actualSha256=$audit.expectedSha256
        $audit.phase='candidate-saved';Save-Audit
        Assert-OwnedWorkspace
        if($BuildOnly){
            # Building does not require macro execution or reopening an untrusted
            # add-in. Audit serialized source separately with audit_candidate.py.
            $mainSource=[IO.File]::ReadAllText((Join-Path $sourceSnapshot 'modSLCMain.bas'),[Text.Encoding]::ASCII)
            $versionMatch=[regex]::Match($mainSource,'(?m)^\s*SLC_ReleaseVersion\s*=\s*"([^"]+)"\s*$')
            if(-not $versionMatch.Success -or $versionMatch.Groups[1].Value -cne $ExpectedReleaseVersion){throw 'Imported release version mismatch.'}
            $audit.releaseVersion=$versionMatch.Groups[1].Value
            $audit.releaseVersionSource='imported-source'
            $audit.serializedSourceAudit='NOT_RUN: use external read-only source audit'
        }else{
        Set-Phase 'before-saved-candidate-reopen'
        $candidateBook=$excel.Workbooks.Open($candidate,0,$true);[void]$ownedBooks.Add($candidateBook)
        Set-Phase 'after-saved-candidate-reopen'
        if([IO.Path]::GetFullPath([string]$candidateBook.FullName) -ine $candidate -or -not [bool]$candidateBook.IsAddin){throw 'Exact saved candidate was not reopened.'}
        $audit.sourceStage='serialized';Assert-SerializedSource $candidateBook;$audit.serializedSourceAudit='PASS'
        $q="'"+([string]$candidateBook.Name).Replace("'","''")+"'!"
        $audit.releaseVersion=[string]$excel.Run($q+'SLC_ReleaseVersion')
        if($audit.releaseVersion -cne $ExpectedReleaseVersion){throw 'Saved candidate release version mismatch.'}
        # A normal workbook provides the same active-window context as use of
        # the add-in. Keep ownership explicit and close it with the other books.
        $harnessBook=$excel.Workbooks.Add(-4167);[void]$ownedBooks.Add($harnessBook)
        $audit.harnessWorkbookName=[string]$harnessBook.Name;Save-Audit
        foreach($name in @('SLC_UiProbe','SLC_TestAll','SLC_UsabilityTests')){
            Assert-OwnedWorkspace
            $audit.phase=$name;Save-Audit
            $watch=[Diagnostics.Stopwatch]::StartNew();$result=[string]$excel.Run($q+$name);$watch.Stop()
            $passed=$result.StartsWith('PASS:',[StringComparison]::Ordinal)
            $audit.tests+=@([ordered]@{name=$name;status=$(if($passed){'PASS'}else{'FAIL'});result=$result;elapsedSeconds=$watch.Elapsed.TotalSeconds})
            Save-Audit;Assert-OwnedWorkspace
            if(-not $passed){throw ('Candidate test failed: '+$name)}
        }
        $audit.phase='detach-candidate-ui';Save-Audit
        [void]$excel.Run($q+'SLC_DetachUI')
        $audit.runtimeTests='PASS'
        Close-OwnedBook $candidateBook;$candidateBook=$null
        }
        $audit.finalSha256=Hash-File $candidate
        if($audit.finalSha256 -cne $audit.expectedSha256){throw 'Candidate bytes changed during read-only testing.'}
        $audit.status='PASS';$exitCode=0
    }
}catch{
    $audit.status='FAIL';$audit.failure=$_.Exception.Message;$audit.failureStack=$_.ScriptStackTrace
    if($_.Exception.Data.Contains('CandidateStatus')){$audit.status=[string]$_.Exception.Data['CandidateStatus']}
    if($_.Exception.Data.Contains('ExitCode')){$exitCode=[int]$_.Exception.Data['ExitCode']}
}finally{
    if($null -ne $excel){
        try{Assert-OwnedWorkspace}catch{$unknownBooks=$true;$audit.cleanupErrors+=@($_.Exception.Message)}
        for($i=$ownedBooks.Count-1;$i -ge 0;$i--){try{Close-OwnedBook $ownedBooks[$i]}catch{$audit.cleanupErrors+=@($_.Exception.Message)}}
        if(-not $unknownBooks){try{Assert-OwnedApplication;Set-Phase 'before-owned-excel-quit';$excel.Quit();Set-Phase 'after-owned-excel-quit'}catch{$audit.cleanupErrors+=@($_.Exception.Message)}}
        Release-Com $excel;$excel=$null
    }
    $candidateBook=$null;$probeBook=$null;$bootstrapBook=$null;$harnessBook=$null
    $project=$null;$components=$null;$component=$null;$codeModule=$null;$native=$null
    $observed=$null;$owned=$null
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();[GC]::WaitForPendingFinalizers()
    if($null -ne $process){
        try{$audit.excelExited=$process.WaitForExit(15000)}catch{$audit.excelExited=$false;$audit.cleanupErrors+=@($_.Exception.Message)}
        $process.Dispose();$process=$null
        if(-not $audit.excelExited){$audit.cleanupErrors+=@('Owned Excel did not exit; no process was killed.')}
    }
    if($accessSnapshotTaken){
        try{
            $now=Read-AccessValue $securityPath
            if($securityWritten -and -not (Same-AccessValue $audit.accessBefore $now)){
                if($now.keyPresent -and $now.present -and $now.kind -ceq 'DWord' -and $now.value -eq 1){
                    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($securityPath,$true)
                    try{if($audit.accessBefore.present){$key.SetValue('AccessVBOM',$audit.accessBefore.value,[Microsoft.Win32.RegistryValueKind]$audit.accessBefore.kind)}else{$key.DeleteValue('AccessVBOM',$false)};$key.Flush()}finally{if($key){$key.Close()}}
                }else{$audit.externalSecurityChangeDetected=$true}
            }
            $audit.accessAfter=Read-AccessValue $securityPath;$audit.accessRestored=Same-AccessValue $audit.accessBefore $audit.accessAfter
        }catch{$audit.accessRestored=$false;$audit.cleanupErrors+=@($_.Exception.Message)}
    }
    if($null -ne $installedSnapshot){
        try{$audit.installedPreserved=((ConvertTo-Json -InputObject $installedSnapshot -Depth 16 -Compress) -ceq (ConvertTo-Json -InputObject (Installation-Snapshot) -Depth 16 -Compress))}catch{$audit.installedPreserved=$false;$audit.cleanupErrors+=@($_.Exception.Message)}
    }
    $after=@(Process-Snapshot);$audit.existingExcelPreserved=$true
    foreach($before in $audit.existingExcelBefore){if(@($after | Where-Object {$_.pid -eq $before.pid -and $_.startTimeUtcTicks -eq $before.startTimeUtcTicks}).Count -ne 1){$audit.existingExcelPreserved=$false}}
    if($bootstrap -and $audit.excelExited -eq $true -and (Test-Path -LiteralPath $bootstrap)){Remove-Item -LiteralPath $bootstrap -Force}
    if($audit.cleanupErrors.Count -gt 0 -or ($accessSnapshotTaken -and -not $audit.accessRestored) -or ($null -ne $installedSnapshot -and -not $audit.installedPreserved) -or -not $audit.existingExcelPreserved){$audit.status='FAIL';$exitCode=1}
    $audit.finishedUtc=[DateTime]::UtcNow.ToString('o');$audit.phase='finished'
    try{Save-Audit}finally{if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
}
Write-Output ($audit.status+': '+$(if($audit.failure){$audit.failure}else{'See usability.private.json'}))
exit $exitCode
