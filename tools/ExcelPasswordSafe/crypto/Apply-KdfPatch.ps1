#requires -Version 5.1
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SourcePath,
 [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'kdf-patch.json') -Raw -Encoding UTF8|ConvertFrom-Json
$SourcePath=(Resolve-Path -LiteralPath $SourcePath).Path
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if($SourcePath -ne (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $manifest.sourcePath)).Path){throw 'Unexpected KDF patch input path.'}
if([IO.File]::Exists($OutputPath) -or [IO.Directory]::Exists($OutputPath)){throw 'KDF patch output must be new.'}
function Hash-Bytes([byte[]]$Bytes){$algorithm=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-','')}finally{$algorithm.Dispose()}}
$sourceBytes=[IO.File]::ReadAllBytes($SourcePath)
if((Hash-Bytes $sourceBytes) -ne $manifest.sourceSha256){throw 'Pinned KDF source hash mismatch.'}
$beforeBytes=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $manifest.beforePath))
$afterBytes=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $manifest.afterPath))
if((Hash-Bytes $beforeBytes) -ne $manifest.beforeSha256 -or (Hash-Bytes $afterBytes) -ne $manifest.afterSha256){throw 'KDF patch anchor hash mismatch.'}
$utf8=New-Object Text.UTF8Encoding($false,$true)
$source=$utf8.GetString($sourceBytes);$before=$utf8.GetString($beforeBytes);$after=$utf8.GetString($afterBytes)
$index=$source.IndexOf($before,[StringComparison]::Ordinal)
if($index -lt 0 -or $index -ne $source.LastIndexOf($before,[StringComparison]::Ordinal)){throw 'KDF dispatch anchor is not unique.'}
$patched=$source.Substring(0,$index)+$after+$source.Substring($index+$before.Length)
$patchedBytes=$utf8.GetBytes($patched);$patchedHash=Hash-Bytes $patchedBytes
if($patchedHash -ne $manifest.patchedSha256){throw 'Generated KDF source hash mismatch.'}
$stream=New-Object IO.FileStream($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$stream.Write($patchedBytes,0,$patchedBytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
[pscustomobject]@{schemaVersion=1;name=$manifest.name;upstreamCommit=$manifest.upstreamCommit;sourcePath=$manifest.sourcePath;sourceSha256=$manifest.sourceSha256;beforeSha256=$manifest.beforeSha256;afterSha256=$manifest.afterSha256;patchedSha256=$patchedHash;outputPath=$OutputPath;scope=$manifest.scope}
