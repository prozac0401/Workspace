[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [string]$MetadataPath='',
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedMsiSha256,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$ReferenceBaseline=''
)
# Build-time audit only. Never invoke this exporter from an MSI custom action.
# It opens the explicitly identified MSI read-only; it never installs a product,
# queries installed component paths, or reads/writes the product registry.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Guid-Text([string]$Value){return $Value -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'}
function Relative-Path([string]$Value){
    if(-not $Value -or $Value.Length -gt 255 -or $Value -match '(^[/\\]|[:*?"<>|]|(^|[/\\])\.\.?([/\\]|$)|[\x00-\x1f])'){throw 'Invalid relative ownership path.'}
    return $Value.Replace('\','/')
}
function Leaf-Name([string]$Value){
    $target=($Value -split ':',2)[0]
    $name=($target -split '\|')[-1]
    if(-not $name -or $name -eq '.' -or $name -eq '..' -or $name -match '[/\\:*?"<>|\x00-\x1f]'){throw 'Unsupported MSI target file/directory name.'}
    return $name
}
function Output-Path([string]$Value){
    $full=[IO.Path]::GetFullPath($Value)
    $allowed=$false
    foreach($boundary in @((Join-Path $root 'artifacts'),(Join-Path $PSScriptRoot 'baselines'))){
        if($full.StartsWith(($boundary.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){$allowed=$true}
    }
    if(-not $allowed -or [IO.Path]::GetExtension($full) -ne '.json'){throw 'Baseline output must be a JSON file under this repository artifacts or installer/baselines.'}
    $part=$full
    while($part){
        if(Test-Path -LiteralPath $part){if(([IO.File]::GetAttributes($part) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Baseline output cannot traverse a reparse point.'}}
        $part=[IO.Path]::GetDirectoryName($part)
    }
    return $full
}
$MsiPath=(Resolve-Path -LiteralPath $MsiPath).Path
if(-not $MetadataPath){$MetadataPath=Join-Path ([IO.Path]::GetDirectoryName($MsiPath)) 'build-metadata.json'}
$MetadataPath=(Resolve-Path -LiteralPath $MetadataPath).Path
$OutputPath=Output-Path $OutputPath
$metadataHash=Hash $MetadataPath
$metadata=Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8|ConvertFrom-Json
$msiHash=Hash $MsiPath
if($msiHash -ne $ExpectedMsiSha256 -or $msiHash -ne $metadata.msiSha256 -or $metadata.status -ne 'PASS' -or $metadata.rollbackTest){throw 'Expected audited non-rollback MSI and PASS build metadata must match exactly.'}
if(@($metadata.files).Count -ne 404){throw 'This audited schema requires exactly 404 payload files.'}
$inventory=@{}
foreach($file in $metadata.files){
    $relative=Relative-Path ([string]$file.path)
    if($relative -cne $file.path -or $inventory.ContainsKey($relative) -or $file.sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or [long]$file.bytes -lt 0){throw 'Duplicate or invalid build inventory entry.'}
    $inventory[$relative]=$file
}
$installer=$null;$database=$null;$summary=$null
function Query([string]$Sql,[int]$Columns){
    $view=$database.OpenView($Sql)
    try{
        [void]$view.Execute();$rows=New-Object 'System.Collections.Generic.List[object]'
        while($record=$view.Fetch()){
            try{$row=@();for($i=1;$i -le $Columns;$i++){$row += [string]$record.StringData($i)};$rows.Add($row)}
            finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)}
        }
        return ,($rows.ToArray())
    }finally{[void]$view.Close();[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)}
}
try{
    $installer=New-Object -ComObject WindowsInstaller.Installer
    $database=$installer.OpenDatabase($MsiPath,0)
    $properties=@{}
    foreach($row in (Query 'SELECT `Property`, `Value` FROM `Property`' 2)){$properties[$row[0]]=$row[1]}
    $summary=$database.SummaryInformation(0)
    $packageCode=[string]$summary.Property(9)
    if($properties.ProductName -ne 'ImageCopySave' -or $properties.ProductCode -ne $metadata.productCode -or $properties.ProductVersion -ne $metadata.version -or $properties.UpgradeCode -ne $metadata.upgradeCode -or $properties.UpgradeCode -ne '{78C90F77-8CC3-4B10-BA9A-00E84ADAF375}' -or $properties.ALLUSERS -ne '1' -or -not (Guid-Text $packageCode) -or -not (Guid-Text $properties.ProductCode)){throw 'MSI product/package identity differs from the audited build.'}
    $tables=@{};foreach($row in (Query 'SELECT `Name` FROM `_Tables`' 1)){$tables[$row[0]]=$true}
    foreach($table in @('RemoveFile','RemoveRegistry')){
        if($tables.ContainsKey($table)){$sql='SELECT * FROM `'+$table+'`';if((Query $sql 1).Count){throw 'Explicit file/registry removal rows are outside this ownership schema.'}}
    }
    $directories=@{}
    foreach($row in (Query 'SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`' 3)){
        if($directories.ContainsKey($row[0])){throw 'Duplicate MSI directory identifier.'}
        $directories[$row[0]]=@{parent=$row[1];name=$row[2]}
    }
    if(-not $directories.ContainsKey('INSTALLFOLDER')){throw 'The MSI has no INSTALLFOLDER anchor.'}
    function Relative-Directory([string]$Id){
        $seen=@{};$parts=New-Object 'System.Collections.Generic.List[string]'
        while($Id -ne 'INSTALLFOLDER'){
            if(-not $Id -or -not $directories.ContainsKey($Id) -or $seen.ContainsKey($Id)){throw 'File directory is not a finite descendant of INSTALLFOLDER.'}
            $seen[$Id]=$true;$parts.Insert(0,(Leaf-Name $directories[$Id].name));$Id=$directories[$Id].parent
        }
        return [string]::Join('/',$parts.ToArray())
    }
    $components=@{};$componentGuids=@{}
    foreach($row in (Query 'SELECT `Component`, `ComponentId`, `Directory_`, `Attributes`, `KeyPath` FROM `Component`' 5)){
        if($components.ContainsKey($row[0]) -or -not (Guid-Text $row[1]) -or $componentGuids.ContainsKey($row[1]) -or ([int]$row[3] -band 256) -eq 0){throw 'Components must have unique GUIDs and use the x64 view.'}
        $components[$row[0]]=@{guid=$row[1].ToUpperInvariant();directory=$row[2];attributes=[int]$row[3];keyPath=$row[4]};$componentGuids[$row[1]]=$true
    }
    $featureComponents=@{}
    foreach($row in (Query 'SELECT `Feature_`, `Component_` FROM `FeatureComponents`' 2)){
        if($row[0] -ne 'Product' -or -not $components.ContainsKey($row[1]) -or $featureComponents.ContainsKey($row[1])){throw 'Unexpected or duplicate feature/component tree relationship.'}
        $featureComponents[$row[1]]=$true
    }
    if($featureComponents.Count -ne $components.Count){throw 'Orphan MSI component.'}
    $files=New-Object 'System.Collections.Generic.List[object]';$fileComponents=@{};$fileKeys=@{};$seenPaths=@{}
    foreach($row in (Query 'SELECT `File`, `Component_`, `FileName`, `FileSize` FROM `File`' 4)){
        if(-not $components.ContainsKey($row[1]) -or $fileComponents.ContainsKey($row[1]) -or $fileKeys.ContainsKey($row[0])){throw 'Each payload file must have its own unique component and File key.'}
        $component=$components[$row[1]]
        if($component.keyPath -ne $row[0] -or ($component.attributes -band 4) -ne 0){throw 'Each payload component must use its sole file as key path.'}
        $directory=Relative-Directory $component.directory;$name=Leaf-Name $row[2]
        $relative=Relative-Path $(if($directory){$directory+'/'+$name}else{$name})
        if($seenPaths.ContainsKey($relative) -or -not $inventory.ContainsKey($relative) -or [long]$inventory[$relative].bytes -ne [long]$row[3]){throw 'Derived MSI path/size differs from the verified payload inventory.'}
        $entry=$inventory[$relative]
        if($entry.PSObject.Properties['componentId'] -and $entry.componentId -ne $component.guid){throw 'Component GUID differs from the build inventory.'}
        $files.Add([ordered]@{path=$relative;sha256=$entry.sha256.ToUpperInvariant();bytes=[long]$entry.bytes;componentId=$component.guid})
        $fileComponents[$row[1]]=$true;$fileKeys[$row[0]]=$true;$seenPaths[$relative]=$true
    }
    if($files.Count -ne 404 -or $seenPaths.Count -ne $inventory.Count){throw 'MSI does not contain exactly the verified 404 file key paths.'}
    $expectedRegistry=@{}
    function Expect-Registry([string]$Key,[string]$Name,[string]$Value){$expectedRegistry[$Key+'|'+$Name]=$Value}
    $save='{9C030D44-BBFA-48B7-BD63-53470C112830}';$copy='{B481F5D0-A2B3-47D7-A139-B6C2F60B36DE}'
    foreach($clsid in @($save,$copy)){$key='Software\Classes\CLSID\'+$clsid+'\InprocServer32';Expect-Registry $key '' '[INSTALLFOLDER]ImageCopySave.Shell.dll';Expect-Registry $key 'ThreadingModel' 'Apartment'}
    $key='Software\Classes\Directory\Background\shell\Workspace.ImageCopySave.Save'
    Expect-Registry $key 'ExplorerCommandHandler' $save;Expect-Registry $key 'MUIVerb' '복사한 그림 저장';Expect-Registry $key 'NeverDefault' ''
    foreach($extension in @('png','jpg','jpeg','bmp')){$key='Software\Classes\SystemFileAssociations\.'+$extension+'\shell\Workspace.ImageCopySave.Copy';Expect-Registry $key 'ExplorerCommandHandler' $copy;Expect-Registry $key 'MUIVerb' '그림으로 복사';Expect-Registry $key 'MultiSelectModel' 'Single';Expect-Registry $key 'NeverDefault' ''}
    $registry=New-Object 'System.Collections.Generic.List[object]';$registryKeys=@{};$seenRegistry=@{};$registryComponents=@{}
    foreach($row in (Query 'SELECT `Registry`, `Root`, `Key`, `Name`, `Value`, `Component_` FROM `Registry`' 6)){
        $identity=$row[2]+'|'+$row[3]
        if($row[1] -ne '2' -or $row[3] -in @('*','-','+') -or $row[4].StartsWith('#') -or $row[4].Contains('[~]') -or -not $expectedRegistry.ContainsKey($identity) -or $seenRegistry.ContainsKey($identity) -or $row[4] -cne $expectedRegistry[$identity] -or $registryKeys.ContainsKey($row[0])){throw 'Only the exact 23 audited HKLM REG_SZ values are supported; broad removal/type changes are forbidden.'}
        if(-not $components.ContainsKey($row[5]) -or $fileComponents.ContainsKey($row[5]) -or ($components[$row[5]].attributes -band 4) -eq 0){throw 'Registry resources must belong to x64 registry-key-path components.'}
        $registry.Add([ordered]@{root=2;key=$row[2];name=$row[3];value=$row[4]})
        $registryKeys[$row[0]]=$row[5];$registryComponents[$row[5]]=$true;$seenRegistry[$identity]=$true
    }
    if($registry.Count -ne 23 -or $seenRegistry.Count -ne $expectedRegistry.Count){throw 'Incomplete audited registry inventory.'}
    foreach($componentId in $registryComponents.Keys){if(-not $registryKeys.ContainsKey($components[$componentId].keyPath) -or $registryKeys[$components[$componentId].keyPath] -ne $componentId){throw 'Registry component key path is not an owned registry row.'}}
    if($fileComponents.Count+$registryComponents.Count -ne $components.Count){throw 'MSI has a component outside the audited files and registry.'}
    $result=[ordered]@{schema=2;version=$properties.ProductVersion;productCode=$properties.ProductCode.ToUpperInvariant();packageCode=$packageCode.ToUpperInvariant();msiSha256=$msiHash;files=@($files.ToArray()|Sort-Object path);registry=@($registry.ToArray()|Sort-Object key,name)}
    if($ReferenceBaseline){
        $reference=Get-Content -LiteralPath (Resolve-Path -LiteralPath $ReferenceBaseline).Path -Raw -Encoding UTF8|ConvertFrom-Json
        if($reference.schema -ne 2 -or @($reference.files).Count -ne 404 -or @($reference.registry).Count -ne 23){throw 'Reference baseline must use audited schema 2.'}
        $referenceFiles=@{};foreach($file in $reference.files){if($referenceFiles.ContainsKey($file.path)){throw 'Duplicate reference file.'};$referenceFiles[$file.path]=$file.componentId}
        foreach($file in $result.files){if(-not $referenceFiles.ContainsKey($file.path) -or $referenceFiles[$file.path] -ne $file.componentId){throw 'File/component GUID tree differs from the reference baseline.'};$referenceFiles.Remove($file.path)}
        $referenceRegistry=@{};foreach($value in $reference.registry){$id=[string]$value.root+'|'+$value.key+'|'+$value.name;if($referenceRegistry.ContainsKey($id)){throw 'Duplicate reference registry value.'};$referenceRegistry[$id]=[string]$value.value}
        foreach($value in $result.registry){$id=[string]$value.root+'|'+$value.key+'|'+$value.name;if(-not $referenceRegistry.ContainsKey($id) -or $referenceRegistry[$id] -cne $value.value){throw 'Registry ownership differs from the reference baseline.'};$referenceRegistry.Remove($id)}
        if($referenceFiles.Count -or $referenceRegistry.Count){throw 'Incomplete reference baseline comparison.'}
    }
    if((Hash $MsiPath) -ne $msiHash -or (Hash $MetadataPath) -ne $metadataHash){throw 'Audit input changed during export.'}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($OutputPath))
    [IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Depth 8)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    [ordered]@{status='PASS';schema=2;productCode=$result.productCode;packageCode=$result.packageCode;msiSha256=$msiHash;files=$files.Count;registry=$registry.Count;referenceTreeVerified=[bool]$ReferenceBaseline;baselineSha256=(Hash $OutputPath);output=$OutputPath;installed=$false;registryModified=$false}|ConvertTo-Json -Depth 3
}finally{
    foreach($com in @($summary,$database,$installer)){if($null -ne $com){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com)}}
}
