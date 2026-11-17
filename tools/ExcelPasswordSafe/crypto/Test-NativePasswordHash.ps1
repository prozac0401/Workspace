#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][string]$EvidenceDirectory,[Parameter(Mandatory=$true)][string]$Dotnet)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $EvidenceDirectory){throw 'Use a new evidence directory.'}
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory);[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$AssemblyPath=(Resolve-Path -LiteralPath $AssemblyPath).Path;$Dotnet=(Resolve-Path -LiteralPath $Dotnet).Path
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
Add-Type -Path (Join-Path $PSScriptRoot 'tests/NativeKdfTests.cs') -ReferencedAssemblies (Join-Path $framework 'System.Core.dll')
$record=@{status='FAIL';assemblySha256=(Get-FileHash -LiteralPath $AssemblyPath).Hash;scope='Native KDF only; synthetic bytes/passwords and isolated fault API, no Excel';utc=[DateTime]::UtcNow.ToString('o')}
try{
 [NativeKdfTests]::Run($AssemblyPath)
 $record.nativeChecks=@([NativeKdfTests]::Checks)
 $lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'compiler-lock.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $compiler=Join-Path (Split-Path -Parent $Dotnet) ('sdk/'+$lock.sdkVersion+'/Roslyn/bincore/csc.dll')
 if((Get-FileHash -LiteralPath $compiler).Hash -ne $lock.cscSha256){throw 'Unexpected test compiler.'}
 $sourcePath=Join-Path $PSScriptRoot 'NativePasswordHash.cs';$source=[IO.File]::ReadAllText($sourcePath)
 $alloc='Marshal.AllocHGlobal';$free='Marshal.FreeHGlobal'
 if(([regex]::Matches($source,[regex]::Escape($alloc))).Count -ne 1 -or ([regex]::Matches($source,[regex]::Escape($free))).Count -ne 2){throw 'Unexpected native allocation anchors.'}
 $testSource=$source.Replace($alloc,'TestMemory.AllocHGlobal').Replace($free,'TestMemory.FreeHGlobal')
 $testSourcePath=Join-Path $EvidenceDirectory 'NativePasswordHash.test.cs';[IO.File]::WriteAllText($testSourcePath,$testSource,(New-Object Text.UTF8Encoding($false)))
 $testExe=Join-Path $EvidenceDirectory 'NativeKdfFaults.exe'
 $arguments=@($compiler,'/nologo','/target:exe','/optimize+','/debug-','/warnaserror+','/nullable:enable','/langversion:latest','/nostdlib+',('/out:'+$testExe))
 $arguments+=@('mscorlib.dll','System.dll','System.Core.dll'|ForEach-Object {'/reference:'+(Join-Path $framework $_)})
 $arguments+=@((Join-Path $PSScriptRoot 'Globals.cs'),$testSourcePath,(Join-Path $PSScriptRoot 'tests/NativeKdfFaults.cs'))
 & $Dotnet @arguments | Out-File -LiteralPath (Join-Path $EvidenceDirectory 'fault-compile.log') -Encoding UTF8
 if($LASTEXITCODE -ne 0){throw 'Native fault test compile failed.'}
 $output=& $testExe 2>&1;$exitCode=$LASTEXITCODE
 [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'fault-results.txt'),($output|Out-String),(New-Object Text.UTF8Encoding($false)))
 if($exitCode -ne 0 -or ($output|Out-String) -notmatch '^PASS (\d+)'){throw 'Native fault tests failed.'}
 $record.faultAssertions=[int]$Matches[1];$record.faultExitCode=$exitCode
 $record.sourceSha256=(Get-FileHash -LiteralPath $sourcePath).Hash
 $record.isolatedTestSourceSha256=(Get-FileHash -LiteralPath $testSourcePath).Hash
 $record.status='PASS'
}catch{$record.error=$_.Exception.Message;throw}
finally{
 $record.nativeChecks=@([NativeKdfTests]::Checks)
 [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'native-kdf-results.json'),($record|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
}
Write-Host ('PASS: '+$record.nativeChecks.Count+' native KDF checks and '+$record.faultAssertions+' isolated fault assertions')
