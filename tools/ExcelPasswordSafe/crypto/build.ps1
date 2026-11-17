#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='4.0.0',
    [string]$Dotnet
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
$repoRoot=[IO.Path]::GetFullPath((Join-Path $toolRoot '..\..'))
if(-not $Dotnet) { $Dotnet=Join-Path $repoRoot '.tools\dotnet\dotnet.exe' }
$Dotnet=(Resolve-Path -LiteralPath $Dotnet).Path
$compilerLock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'compiler-lock.json') -Raw | ConvertFrom-Json
$compiler=Join-Path (Split-Path -Parent $Dotnet) ('sdk\'+$compilerLock.sdkVersion+'\Roslyn\bincore\csc.dll')
if(-not (Test-Path -LiteralPath $compiler) -or (Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash -ine $compilerLock.cscSha256) { throw 'The pinned Roslyn compiler is missing or changed. Supply the approved private .NET SDK through -Dotnet.' }
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$upstream=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'upstream-manifest.json') -Raw | ConvertFrom-Json
if($upstream.schemaVersion -ne 1 -or -not $upstream.files.Count) { throw 'The upstream source hash manifest is missing or invalid.' }
$vendorRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'vendor'))+[IO.Path]::DirectorySeparatorChar
$vendorPaths=@()
foreach($entry in $upstream.files) {
    $path=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $entry.path))
    if(-not $path.StartsWith($vendorRoot,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path)) { throw 'The upstream source manifest contains an invalid vendor file path.' }
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256 -or (Get-Item -LiteralPath $path).Length -ne $entry.bytes) { throw ('Vendored source changed from the pinned upstream bytes: '+$entry.path) }
    $vendorPaths+=$path
}
foreach($file in (Get-ChildItem -LiteralPath $vendorRoot -Recurse -File)) { if($vendorPaths -notcontains $file.FullName) { throw ('Unpinned vendored file: '+$file.Name) } }
$referenceNames=@('mscorlib.dll','System.dll','System.Core.dll','System.Security.dll','System.Xml.dll','System.Xml.Linq.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll')
$referencePaths=@($referenceNames | ForEach-Object { Join-Path $framework $_ })
foreach($reference in $referencePaths) { if(-not (Test-Path -LiteralPath $reference)) { throw ('Required .NET Framework 4.8 assembly is missing: '+$reference) } }
$sources=@(@(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.cs')+@(Get-ChildItem -LiteralPath $vendorRoot -Recurse -File -Filter '*.cs') | Sort-Object FullName)
if(-not $sources.Count) { throw 'Crypto source files are not present.' }
$output=[IO.Path]::GetFullPath($OutputDirectory)
if($output.Equals($PSScriptRoot,[StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($PSScriptRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Generated files must be outside the crypto source directory.' }
if(Test-Path -LiteralPath $output) { throw 'Choose a new crypto build output directory; existing build evidence is immutable.' }
New-Item -ItemType Directory -Path $output | Out-Null
$dll=Join-Path $output 'ExcelPasswordSafe.Crypto.dll'
$assembly=Join-Path $output 'AssemblyInfo.cs'
$utf8=New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($assembly,('using System.Reflection; using System.Runtime.Versioning; [assembly: AssemblyTitle("ExcelPasswordSafe.Crypto")] [assembly: AssemblyProduct("ExcelPasswordSafe '+([version]$Version).Major+'")] [assembly: AssemblyVersion("'+$Version+'.0")] [assembly: AssemblyFileVersion("'+$Version+'.0")] [assembly: TargetFramework(".NETFramework,Version=v4.8")]'),$utf8)
$arguments=@($compiler,'/nologo','/target:library','/platform:anycpu','/optimize+','/deterministic+','/debug-','/warn:4','/warnaserror+','/nullable:enable','/langversion:latest','/define:NETFRAMEWORK,NET48','/nostdlib+','/utf8output',('/out:'+$dll),('/pathmap:'+$PSScriptRoot+'=/_/crypto,'+$output+'=/_/generated'))
$arguments+=@($referencePaths | ForEach-Object { '/reference:'+$_ })
$arguments+=@($sources.FullName)+@($assembly)
$before=@($sources | ForEach-Object { @{path=$_.FullName.Substring($PSScriptRoot.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
$record=[ordered]@{status='Failed';version=$Version;targetFramework='.NETFramework,Version=v4.8';runtimeDependencies='Windows .NET Framework BCL only';compiler=$compilerLock;upstreamCommit=$upstream.commit;upstreamFilesVerified=$vendorPaths.Count;frameworkReferences=@($referencePaths | ForEach-Object { @{name=[IO.Path]::GetFileName($_);sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} });sources=$before;dll=$dll}
try {
    $savedPreference=$ErrorActionPreference
    try { $ErrorActionPreference='Continue'; $lines=& $Dotnet @arguments 2>&1; $code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$savedPreference }
    $lines | Out-File -LiteralPath (Join-Path $output 'compile.log') -Encoding utf8
    if($code -ne 0) { throw ('Crypto compile failed ('+$code+'). See '+(Join-Path $output 'compile.log')) }
    for($i=0;$i -lt $sources.Count;$i++) { if((Get-FileHash -LiteralPath $sources[$i].FullName -Algorithm SHA256).Hash -cne $before[$i].sha256) { throw 'Crypto sources changed during compilation.' } }
    $metadata=[Reflection.Assembly]::ReflectionOnlyLoadFrom($dll)
    $dependencies=@($metadata.GetReferencedAssemblies() | ForEach-Object { $_.Name })
    $allowed=@($referenceNames | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
    foreach($dependency in $dependencies) { if($allowed -notcontains $dependency) { throw ('Unexpected non-BCL runtime dependency: '+$dependency) } }
    $record.references=$dependencies
    $record.sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    $record.bytes=(Get-Item -LiteralPath $dll).Length
    $record.status='Pass'
} catch { $record.failure=$_.Exception.Message; throw }
finally { $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'crypto-build.json') -Encoding utf8 }
Write-Output $dll
