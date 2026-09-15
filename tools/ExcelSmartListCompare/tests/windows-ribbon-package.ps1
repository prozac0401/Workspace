[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
# Exercise the actual build-time ZIP writer on a synthetic package. No Excel,
# registry changes, business workbooks or installed product are involved.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tool=Split-Path -Parent $PSScriptRoot
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a fresh evidence directory.'}
[void](New-Item -ItemType Directory -Path $output)
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'Setup.ps1'),[ref]$null,[ref]$null)
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($f.Extent.Text))}
Add-Type -AssemblyName System.IO.Compression
$checks=New-Object Collections.Generic.List[object]
function Check([string]$Name,[bool]$Pass){
    $checks.Add([pscustomobject]@{name=$Name;status=$(if($Pass){'PASS'}else{'FAIL'})})
    $checks|ConvertTo-Json -Depth 5|Set-Content (Join-Path $output 'ribbon-package.json') -Encoding UTF8
    if(-not $Pass){throw ('Failed: '+$Name)}
}
function Read-Parts([string]$Path){
    $file=[IO.File]::OpenRead($Path);$zip=[IO.Compression.ZipArchive]::new($file,[IO.Compression.ZipArchiveMode]::Read)
    try{
        $parts=@{}
        foreach($entry in $zip.Entries){
            if($parts.ContainsKey($entry.FullName)){throw ('Duplicate ZIP entry: '+$entry.FullName)}
            $parts[$entry.FullName]=Read-ZipText $zip $entry.FullName
        }
        return $parts
    }finally{$zip.Dispose();$file.Dispose()}
}
$package=Join-Path $output 'synthetic.xlam'
$file=[IO.File]::Open($package,[IO.FileMode]::CreateNew)
$zip=[IO.Compression.ZipArchive]::new($file,[IO.Compression.ZipArchiveMode]::Update)
try{
    Write-ZipText $zip '_rels/.rels' '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rIdOther" Type="urn:synthetic:preserve" Target="other.xml"/></Relationships>'
    Write-ZipText $zip '[Content_Types].xml' '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.ms-excel.addin.macroEnabled.main+xml"/><Override PartName="/other.xml" ContentType="application/xml"/></Types>'
    Write-ZipText $zip 'xl/workbook.xml' '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>'
    Write-ZipText $zip 'xl/vbaProject.bin' 'Synthetic VBA bytes that the writer must preserve.'
    Write-ZipText $zip 'other.xml' '<preserved>synthetic external part</preserved>'
    Write-ZipText $zip 'docProps/core.xml' '<old>synthetic previous author</old>'
}finally{$zip.Dispose();$file.Dispose()}
$before=Read-Parts $package
$ribbon=Join-Path $tool 'src/customUI14.xml'
Write-PackageMetadata $package $ribbon
$parts=Read-Parts $package
Check 'Source RibbonX is embedded exactly' ($parts['customUI/customUI14.xml'] -ceq [IO.File]::ReadAllText($ribbon,[Text.Encoding]::UTF8))
$relationships=[xml]$parts['_rels/.rels']
$ui=@($relationships.DocumentElement.ChildNodes|Where-Object {$_.GetAttribute('Type') -ceq 'http://schemas.microsoft.com/office/2007/relationships/ui/extensibility'})
Check 'One Office RibbonX package relationship' ($ui.Count -eq 1 -and $ui[0].GetAttribute('Target') -ceq 'customUI/customUI14.xml')
$types=[xml]$parts['[Content_Types].xml']
$uiTypes=@($types.DocumentElement.ChildNodes|Where-Object {$_.GetAttribute('PartName') -ceq '/customUI/customUI14.xml'})
Check 'One RibbonX content type override' ($uiTypes.Count -eq 1 -and $uiTypes[0].GetAttribute('ContentType') -ceq 'application/xml')
Check 'Existing package relationships preserved' (@($relationships.DocumentElement.ChildNodes|Where-Object {$_.GetAttribute('Id') -in @('rId1','rIdOther')}).Count -eq 2)
Check 'Existing content type overrides preserved' (@($types.DocumentElement.ChildNodes|Where-Object {$_.GetAttribute('PartName') -in @('/xl/workbook.xml','/other.xml')}).Count -eq 2)
foreach($name in @('xl/workbook.xml','xl/vbaProject.bin','other.xml')){Check ($name+' unchanged') ($parts[$name] -ceq $before[$name])}
Check 'Personal author metadata replaced by product identity' ($parts['docProps/core.xml'].Contains('<dc:creator>Excel Smart List Compare</dc:creator>') -and -not $parts['docProps/core.xml'].Contains('synthetic previous author'))
Write-PackageMetadata $package $ribbon
$again=Read-Parts $package
$identical=$again.Count -eq $parts.Count
foreach($name in $parts.Keys){$identical=$identical -and $again[$name] -ceq $parts[$name]}
Check 'Repeated metadata write has identical parts and no duplicates' $identical
$bad=Join-Path $output 'invalid-ribbon.xml'
[IO.File]::WriteAllText($bad,'<unexpected/>')
foreach($path in @($bad,(Join-Path $output 'missing-ribbon.xml'))){
    $hash=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash;$rejected=$false
    try{Write-PackageMetadata $package $path}catch{$rejected=$true}
    Check ('Invalid input preserves package: '+[IO.Path]::GetFileName($path)) ($rejected -and (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ceq $hash)
}
Write-Output ('PASS: '+$checks.Count+' RibbonX package checks.')
