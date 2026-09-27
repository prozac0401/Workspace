[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ServicedReport,[string]$WrapperPath='')
# Pure evidence/path tests: no MSI actions, registry writes, or product changes.
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
if(-not $WrapperPath){$WrapperPath=Join-Path $PSScriptRoot '../invoke-msi-preservation-recovery.ps1'}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($WrapperPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Recovery wrapper did not parse.'}
foreach($name in @('Assert-ServicedEvidence','Normalize-PendingPath','Assert-PendingTargets')){
 $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
 if($nodes.Count -ne 1){throw 'Expected unique pure recovery helper.'};Invoke-Expression $nodes[0].Extent.Text
}
$evidence=Get-Content -LiteralPath $ServicedReport -Raw -Encoding UTF8|ConvertFrom-Json
$log=Get-Content -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($ServicedReport)) 'service-exact-failed-fixture.msiexec.log') -Raw
$FailedReport=$evidence.failedReport;$failureHash=$evidence.failedReportSha256;$PreviousMetadata=$evidence.previousMetadata;$fixtureFolder=$evidence.fixtureFolder
$installed=[pscustomobject]@{path=$evidence.installedMsi;sha256=$evidence.installedMsiSha256;packageCode=$evidence.steps[0].inspection.cachedPackageCode}
$recoveryPackage=[pscustomobject]@{path=$evidence.recoveryMsi;sha256=$evidence.recoveryMsiSha256;packageCode=$evidence.recoveryPackageCode}
$product=[pscustomobject]@{path=$evidence.msi;sha256=$evidence.msiSha256};$rollback=[pscustomobject]@{path=$evidence.rollbackMsi}
$results=New-Object 'System.Collections.Generic.List[object]'
function Test-Case([string]$Label,[scriptblock]$Body){& $Body;$results.Add([ordered]@{name=$Label;status='PASS'})}
function Must-Reject([scriptblock]$Body){$rejected=$false;try{& $Body}catch{$rejected=$true};if(-not $rejected){throw 'Expected unsafe evidence/target rejection.'}}
function Evidence-Copy {return ($evidence|ConvertTo-Json -Depth 30|ConvertFrom-Json)}
Test-Case 'actual reviewed 3010 with both guards and finalization' {Assert-ServicedEvidence $evidence $log}
foreach($name in @('failedReport','installedMsi','recoveryMsi','msi','rollbackMsi','previousMetadata')){
 Test-Case ('reject changed recovery input '+$name) {$copy=Evidence-Copy;$copy.$name='C:\different-input';Must-Reject {Assert-ServicedEvidence $copy $log}}
}
Test-Case 'reject changed original failure hash' {$copy=Evidence-Copy;$copy.failedReportSha256='0'*64;Must-Reject {Assert-ServicedEvidence $copy $log}}
Test-Case 'reject ordinary MSI failure' {$copy=Evidence-Copy;$copy.steps[0].exitCode=1603;Must-Reject {Assert-ServicedEvidence $copy $log}}
Test-Case 'reject later or additional step' {$copy=Evidence-Copy;$copy.steps+=($copy.steps[0]);Must-Reject {Assert-ServicedEvidence $copy $log}}
Test-Case 'reject already attempted final install' {$copy=Evidence-Copy;$copy.finalInstallAttempted=$true;Must-Reject {Assert-ServicedEvidence $copy $log}}
Test-Case 'reject different serviced package' {$copy=Evidence-Copy;$copy.steps[0].packageCode='{00000000-0000-0000-0000-000000000000}';Must-Reject {Assert-ServicedEvidence $copy $log}}
Test-Case 'reject wrong original cached package' {$copy=Evidence-Copy;$copy.steps[0].inspection.cachedPackageCode=$recoveryPackage.packageCode;Must-Reject {Assert-ServicedEvidence $copy $log}}
Test-Case 'reject absent immediate guard proof' {Must-Reject {Assert-ServicedEvidence $evidence ($log.Replace('PASS (preflight)','MISSING'))}}
Test-Case 'reject absent deferred guard proof' {Must-Reject {Assert-ServicedEvidence $evidence ($log.Replace('PASS (deferred recheck)','MISSING'))}}
Test-Case 'reject a guard block in successful-looking log' {Must-Reject {Assert-ServicedEvidence $evidence ($log+[Environment]::NewLine+'ImageCopySave ownership guard: BLOCKED: test')}}
Test-Case 'reject absent transaction completion' {Must-Reject {Assert-ServicedEvidence $evidence ($log.Replace('InstallFinalize.','NO_FINALIZE.'))}}
$cache='C:\Windows\Installer\current.msi';$folder='D:\fixture\installed-product';$old='C:\Windows\Installer\old.msi'
Test-Case 'allow obsolete cache deletion and unrelated operations unchanged' {
 $pairs=@([pscustomobject]@{source='*1\??\C:\Windows\Installer\old.msi';destination=''},[pscustomobject]@{source='\??\C:\unrelated\old.tmp';destination='!\??\C:\unrelated\new.tmp'})
 $before=$pairs|ConvertTo-Json -Compress;$result=Assert-PendingTargets $pairs $cache $folder $old
 if($result.totalPendingPairs -ne 2 -or $result.obsoleteCacheDeletionPairs -ne 1 -or $result.unrelatedPendingPairs -ne 1 -or ($pairs|ConvertTo-Json -Compress) -ne $before){throw 'Unrelated queue evidence changed.'}
}
Test-Case 'allow empty queue' {$result=Assert-PendingTargets @() $cache $folder $old;if($result.totalPendingPairs -ne 0){throw 'Empty queue count differs.'}}
$blocked=@(
 [pscustomobject]@{name='source owned file with NT prefix';source='*1\??\d:\fixture\installed-product\Engine.dll';destination=''},
 [pscustomobject]@{name='destination current cache';source='C:\other.tmp';destination='!\??\c:\windows\installer\current.msi'},
 [pscustomobject]@{name='source fixture directory';source=$folder;destination=''},
 [pscustomobject]@{name='destination normalized dot segments';source='C:\other.tmp';destination='D:\fixture\unused\..\installed-product\Engine.dll'},
 [pscustomobject]@{name='source ancestor of product';source='D:\fixture';destination=''},
 [pscustomobject]@{name='destination ancestor of cache';source='C:\other.tmp';destination='C:\Windows\Installer'},
 [pscustomobject]@{name='current cache named stream';source=($cache+':stream');destination=''},
 [pscustomobject]@{name='unresolvable relative target';source='relative.tmp';destination=''}
)
foreach($case in $blocked){Test-Case ('reject pending '+$case.name) {Must-Reject {Assert-PendingTargets @($case) $cache $folder $old}}}
[ordered]@{status='PASS';checkedAtUtc=[DateTime]::UtcNow.ToString('o');wrapperSha256=(Get-FileHash -LiteralPath $WrapperPath -Algorithm SHA256).Hash;servicedReportSha256=(Get-FileHash -LiteralPath $ServicedReport -Algorithm SHA256).Hash;testCount=$results.Count;tests=@($results.ToArray());msiActionsRun=0;registryWrites=0}|ConvertTo-Json -Depth 8
