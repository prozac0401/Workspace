[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$path=(Resolve-Path -LiteralPath $MsiPath).Path
$metadata=Get-Content -Encoding UTF8 -LiteralPath ($path+'.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $metadata.sha256) { throw 'MSI hash differs from build metadata.' }
$installer=New-Object -ComObject WindowsInstaller.Installer
$database=$installer.OpenDatabase($path,0)
function Rows([string]$Sql,[int]$Count) {
    $view=$database.OpenView($Sql);[void]$view.Execute()
    $items=New-Object 'System.Collections.Generic.List[object]'
    try { while($record=$view.Fetch()) { try { $row=@();for($i=1;$i -le $Count;$i++){$row+=$record.StringData($i)};$items.Add($row) }finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)} } }
    finally{[void]$view.Close();[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)}
    return ,$items
}
function Assert([bool]$Condition,[string]$Reason){if(!$Condition){throw "MSI verification failed: $Reason"}}
try {
    $properties=@{};foreach($row in (Rows 'SELECT `Property`,`Value` FROM `Property`' 2)){$properties[$row[0]]=$row[1]}
    Assert ($properties['ProductCode'] -eq $metadata.productCode) 'ProductCode'
    Assert ($properties['ProductVersion'] -eq $metadata.productVersion) 'ProductVersion'
    Assert ($properties['UpgradeCode'] -eq $metadata.upgradeCode) 'UpgradeCode'
    Assert (!$properties.ContainsKey('ALLUSERS')) 'current-user installation scope'
    Assert ($properties['MSIRESTARTMANAGERCONTROL'] -eq 'Disable') 'no automatic Excel shutdown'
    Assert ($properties['REBOOT'] -eq 'ReallySuppress') 'no automatic reboot'
    $summary=$database.SummaryInformation(0)
    try {
        $template=$summary.Property(7);$flags=[int]$summary.Property(15)
        Assert ($template -eq $(if($metadata.architecture -eq 'x64'){'x64;1042'}else{'Intel;1042'})) 'platform/language'
        Assert (($flags -band 8) -ne 0) 'non-elevated package flag'
    }finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary)}
    $media=Rows 'SELECT `Cabinet` FROM `Media`' 1
    Assert ($media.Count -eq 1 -and $media[0][0].StartsWith('#')) 'single embedded cabinet'
    $files=Rows 'SELECT `File`,`FileName`,`FileSize`,`Component_` FROM `File`' 4
    Assert ($files.Count -eq $metadata.files.Count) 'explicit payload file count'
    $components=Rows 'SELECT `Component`,`Attributes`,`KeyPath` FROM `Component`' 3
    Assert ($components.Count -eq ($files.Count+1)) 'one owned component per payload plus registration'
    foreach($component in $components){
        Assert (([int]$component[1] -band 4) -ne 0) 'HKCU registry keypaths for per-user components'
        Assert ((([int]$component[1] -band 256) -ne 0) -eq ($metadata.architecture -eq 'x64')) 'registry/file component architecture'
    }
    foreach($file in $metadata.files){
        $name=[IO.Path]::GetFileName($file.Name)
        $match=@($files|Where-Object{($_[1] -split '\|')[-1] -eq $name})
        Assert ($match.Count -eq 1) "payload filename $name"
        Assert ([long]$match[0][2] -eq (Get-Item -LiteralPath $file.Source).Length) "payload size $name"
        Assert ((Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash -eq $file.Sha256) "payload source hash $name"
    }
    $regs=Rows 'SELECT `Root`,`Key`,`Name`,`Value` FROM `Registry`' 4
    Assert ($regs.Count -eq ($metadata.registrations.Count+$metadata.files.Count)) 'bounded named registry values'
    foreach($reg in $regs){Assert ($reg[0] -eq '1') 'HKCU-only registration';Assert ($reg[2] -ne '-' -and $reg[2] -ne '*') 'no wildcard registry deletion'}
    foreach($expected in $metadata.registrations){
        $match=@($regs|Where-Object{$_[1] -eq $expected.Key -and $_[2] -eq $expected.Name})
        Assert ($match.Count -eq 1) "registration $($expected.Key)/$($expected.Name)"
        $value=if($expected.Type -eq 'integer'){'#'+$expected.Value}else{$expected.Value}
        Assert ($match[0][3] -ceq $value) "registry value $($expected.Name)"
    }
    $assembly=[Reflection.AssemblyName]::GetAssemblyName($metadata.files[0].Source)
    Assert ($assembly.FullName -eq $metadata.assemblyIdentity -and $assembly.Version.ToString() -eq $metadata.assemblyVersion) 'payload assembly identity matches package metadata'
    $assemblyRegs=@($regs|Where-Object{$_[2] -eq 'Assembly'})
    Assert ($assemblyRegs.Count -eq 2) 'both CLR registration identities present'
    foreach($reg in $assemblyRegs){Assert ($reg[3] -ceq $assembly.FullName) 'CLR registration matches actual add-in assembly'}
    Assert (@($regs|Where-Object{$_[1].EndsWith('\InprocServer32\'+$assembly.Version.ToString())}).Count -eq 4) 'version-specific CLR registration matches actual add-in'
    $actions=Rows 'SELECT `Action`,`Type`,`Source`,`Target` FROM `CustomAction`' 4
    $pre=@($actions|Where-Object{$_[0] -eq 'VcpPreflight'});$deferred=@($actions|Where-Object{$_[0] -eq 'VcpDeferred'})
    Assert ($pre.Count -eq 1 -and [int]$pre[0][1] -eq 1 -and $pre[0][2] -eq 'VcpGuard' -and $pre[0][3] -eq 'VcpPreflight') 'native read-only preflight entry'
    Assert ($deferred.Count -eq 1 -and (([int]$deferred[0][1] -band 1024) -ne 0) -and (([int]$deferred[0][1] -band 2048) -eq 0) -and $deferred[0][2] -eq 'VcpGuard' -and $deferred[0][3] -eq 'VcpDeferred') 'deferred guard uses user impersonation'
    foreach($action in $actions){Assert (([int]$action[1] -band 63) -in @(1,19,51)) 'no executable/script installation custom actions'}
    Assert ((@($actions|Where-Object{$_[0] -eq 'FailRollbackTest'}).Count -eq 1) -eq [bool]$metadata.rollbackTest) 'test failure is excluded from release MSI'
    $sequence=@{};foreach($row in (Rows 'SELECT `Action`,`Sequence` FROM `InstallExecuteSequence`' 2)){$sequence[$row[0]]=[int]$row[1]}
    Assert ($sequence.VcpPreflight -lt $sequence.InstallInitialize -and $sequence.VcpDeferred -gt $sequence.InstallInitialize -and $sequence.VcpDeferred -lt $sequence.ProcessComponents) 'guards execute before standard mutation actions'
    Assert (!$sequence.ContainsKey('RemoveExistingProducts')) 'first MSI release does not perform unaudited upgrades'
    $removeFiles=Rows 'SELECT `FileName` FROM `RemoveFile`' 1
    foreach($row in $removeFiles){Assert ([string]::IsNullOrEmpty($row[0])) 'only empty owned directories are removed'}
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    Assert ($signature.Status -eq 'NotSigned') 'unsigned classification matches artifact'
    Write-Output "PASS MSI structure: $([IO.Path]::GetFileName($path)); $($files.Count) payload files; HKCU; $($metadata.guardTests.passed) guard tests; no installation performed."
}finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database);[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)}
