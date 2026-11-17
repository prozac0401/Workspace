#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $EvidenceDirectory){throw 'Use a new evidence directory.'}
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory);[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$AssemblyPath=(Resolve-Path -LiteralPath $AssemblyPath).Path
$assembly=[Reflection.Assembly]::LoadFrom($AssemblyPath)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
Add-Type -Path (Join-Path $PSScriptRoot 'tests/CryptoFixtureTools.cs') -ReferencedAssemblies @((Join-Path $framework 'System.Core.dll'),(Join-Path $framework 'System.Xml.dll'),(Join-Path $framework 'System.Xml.Linq.dll'),(Join-Path $framework 'System.IO.Compression.dll'))
$checks=New-Object 'System.Collections.Generic.List[object]'
$timings=New-Object 'System.Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;passed=$Pass});if(-not $Pass){throw $Name}}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Run([string]$Source,[string]$Name,[string]$Extension,[string]$Mode,[string]$Old,[string]$New){
 $output=Join-Path $EvidenceDirectory ($Name+$Extension);$before=Sha $Source;$clock=[Diagnostics.Stopwatch]::StartNew()
 $result=[ExcelPasswordSafe.Crypto.DirectCrypto]::Operate($Source,$output,$Extension,$Mode,$Old,$New)
 $clock.Stop();$timings.Add([pscustomobject]@{name=$Name;mode=$Mode;milliseconds=[Math]::Round($clock.Elapsed.TotalMilliseconds,3);status=$result.Status;category=$result.Category})
 Check ($Name+' source unchanged') ((Sha $Source)-eq $before)
 if($result.Status -eq 'Validated'){Check ($Name+' exact persisted hash') ((Sha $output)-eq $result.TempHash)}
 else{Check ($Name+' no output') (-not [IO.File]::Exists($output))}
 [pscustomobject]@{result=$result;path=$output}
}
$status='FAIL';$failure=$null
try{
 $pass1='Test'+[char]0xd55c+[char]0xae00+'42!';$pass2='Next'+[char]0xc554+[char]0xd638+'99!'
 foreach($length in @(0,4080,4081,4096)){
  $original=Join-Path $EvidenceDirectory ('plain-'+$length+'.xlsx')
  [IO.File]::WriteAllBytes($original,[CryptoFixtureTools]::SmallPackage($length))
  if($length){Check ('fixture exact '+$length) ((Get-Item -LiteralPath $original).Length-eq $length)}
  $encrypted=Run $original ('encrypted-'+$length) '.xlsx' Encrypt '' $pass1
  Check ('encrypt '+$length) ($encrypted.result.Supported -and $encrypted.result.Status-eq 'Validated')
  $decrypted=Run $encrypted.path ('decrypted-'+$length) '.xlsx' Decrypt $pass1 ''
  Check ('decrypt '+$length) ($decrypted.result.Status-eq 'Validated' -and (Sha $decrypted.path)-eq (Sha $original))
  if($length-eq 0){$samplePlain=$original;$sampleEncrypted=$encrypted.path}
 }
 $changed=Run $sampleEncrypted 'changed' '.xlsx' ChangePassword $pass1 $pass2
 Check 'ChangePassword validated' ($changed.result.Status-eq 'Validated')
 $changedPlain=Run $changed.path 'changed-plain' '.xlsx' Decrypt $pass2 ''
 Check 'ChangePassword exact ZIP preservation' ((Sha $changedPlain.path)-eq (Sha $samplePlain))
 $oldRejected=Run $changed.path 'old-rejected' '.xlsx' Decrypt $pass1 ''
 Check 'Old password rejected' ($oldRejected.result.Supported -and $oldRejected.result.Status-eq 'Failed')
 $wrong=Run $sampleEncrypted 'wrong-password' '.xlsx' Decrypt 'not-the-password' ''
 Check 'Wrong password terminal' ($wrong.result.Supported -and $wrong.result.Category-eq 'OpenFailedPossiblePasswordOrCorruption')
 $plainSkip=Run $samplePlain 'plain-skip' '.xlsx' Decrypt '' ''
 Check 'Plain decrypt skipped after guard' ($plainSkip.result.Status-eq 'Skipped' -and $plainSkip.result.Category-eq 'AlreadyUnencrypted')
 $encryptedSkip=Run $sampleEncrypted 'encrypted-skip' '.xlsx' Encrypt '' 'New-42!'
 Check 'Encrypted Encrypt skipped without password' ($encryptedSkip.result.Status-eq 'Skipped' -and $encryptedSkip.result.Category-eq 'AlreadyEncrypted')
 $same=Run $sampleEncrypted 'same-password' '.xlsx' ChangePassword $pass1 $pass1
 Check 'Unchanged password rejected' ($same.result.Category-eq 'PasswordUnchanged')
 $fallbackMutations=@('standard','unsupported-algorithm','spin-limit','additional-certificate','multiple-password-keys','unknown-recipients-child','unknown-recipient-child','unknown-descriptor-child','unknown-outer-stream','outer-signature-stream','unknown-dataspace-stream')
 foreach($kind in ($fallbackMutations+@('missing-hmac','hmac-flip','payload-flip','payload-truncate','length-header','malformed-xml','invalid-hash-size'))){
  $mutant=Join-Path $EvidenceDirectory ($kind+'-source.xlsx')
  [IO.File]::WriteAllBytes($mutant,[CryptoFixtureTools]::Mutate($assembly,[IO.File]::ReadAllBytes($sampleEncrypted),$kind))
  $r=Run $mutant ($kind+'-result') '.xlsx' Decrypt $pass1 ''
  if($kind -in $fallbackMutations){
   Check ($kind+' COM fallback') (-not $r.result.Supported -and $r.result.Status-eq 'Unsupported')
   if($kind -eq 'additional-certificate'){
    $change=Run $mutant 'additional-certificate-change' '.xlsx' ChangePassword $pass1 $pass2
    Check 'Synthetic mixed recipient password change routes to COM' (-not $change.result.Supported -and $change.result.Status-eq 'Unsupported')
   }
  }else{
   Check ($kind+' terminal rejection') ($r.result.Supported -and $r.result.Status-eq 'Failed')
   if($kind -in @('hmac-flip','payload-flip')){Check ($kind+' HMAC rejection') ($r.result.Category-eq 'IntegrityCheckFailed')}
  }
 }
 $existing=Join-Path $EvidenceDirectory 'existing-temp.xlsx';[IO.File]::WriteAllText($existing,'retained bytes');$hash=Sha $existing
 $r=[ExcelPasswordSafe.Crypto.DirectCrypto]::Operate($samplePlain,$existing,'.xlsx','Encrypt','',$pass1)
 Check 'Existing destination never overwritten' ($r.Category-eq 'InvalidTemporaryPath' -and (Sha $existing)-eq $hash)
 $r=[ExcelPasswordSafe.Crypto.DirectCrypto]::Operate($samplePlain,$samplePlain,'.xlsx','Encrypt','',$pass1)
 Check 'Source cannot be output' ($r.Category-eq 'InvalidTemporaryPath')
 $unsupported=Run $samplePlain 'unsupported-format' '.xls' Encrypt '' $pass1
 Check 'Legacy format fallback' (-not $unsupported.result.Supported)
 $large=Join-Path $EvidenceDirectory 'size-limit.xlsx';$stream=[IO.File]::Create($large);try{$stream.SetLength(64MB+1)}finally{$stream.Dispose()}
 $limit=Run $large 'size-limit-result' '.xlsx' Encrypt '' $pass1
 Check 'Input size fallback' (-not $limit.result.Supported)
 $invalid=Join-Path $EvidenceDirectory 'invalid-plain.xlsx';[IO.File]::WriteAllText($invalid,'not a ZIP')
 $invalidResult=Run $invalid 'invalid-plain-result' '.xlsx' Decrypt '' ''
 Check 'Invalid plaintext never skipped or sent to COM' ($invalidResult.result.Supported -and $invalidResult.result.Status-eq 'Failed')
 $macro=Join-Path $PSScriptRoot '../upstream/1.1.0/ExcelPasswordSafe/tests/fixtures/picture_vba.xlsm'
 $macroEncrypted=Run $macro 'macro-encrypted' '.xlsm' Encrypt '' $pass1
 Check 'Macro package encryption' ($macroEncrypted.result.Status-eq 'Validated')
 $macroDecrypted=Run $macroEncrypted.path 'macro-decrypted' '.xlsm' Decrypt $pass1 ''
 Check 'Macro bytes preserved exactly' ($macroDecrypted.result.Status-eq 'Validated' -and (Sha $macro)-eq (Sha $macroDecrypted.path))
 $status='PASS'
}catch{$failure=$_.Exception.Message;throw}
finally{
 $record=@{status=$status;assertions=$checks.Count;checks=$checks.ToArray();timings=$timings.ToArray();assemblySha256=(Sha $AssemblyPath);error=$failure;scope='Synthetic ZIPs and upstream test fixtures; no Excel, UI, or business files';utc=[DateTime]::UtcNow.ToString('o')}
 [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'direct-crypto-results.json'),($record|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
}
Write-Host ('PASS: '+$checks.Count+' direct crypto assertions')

