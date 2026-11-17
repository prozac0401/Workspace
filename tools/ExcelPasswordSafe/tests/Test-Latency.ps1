#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [Parameter(Mandatory=$true)][string]$BaselineRuntime,
    [Parameter(Mandatory=$true)][string]$RuntimeDirectory,
    [ValidateRange(1,10)][int]$Repetitions=3
)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Excel is running; do not touch it.' }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory); Set-PrivateDirectory $EvidenceDirectory
$checks=New-Object 'System.Collections.Generic.List[object]'
$measurements=New-Object 'System.Collections.Generic.List[object]'
$runtimes=New-Object 'System.Collections.Generic.List[object]'
function Check([bool]$Condition,[string]$Name) {
    $checks.Add(@{name=$Name;passed=$Condition})
    if(-not $Condition) { throw ('Latency validation failed: '+$Name) }
}
function Protect-Test([string]$Text) {
    if(-not $Text) { return '' }
    $secure=ConvertTo-SecureString $Text -AsPlainText -Force
    try { ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
}
function Copy-Fixture([string]$Source,[string]$Destination) {
    [IO.File]::Copy($Source,$Destination)
    [IO.File]::SetAttributes($Destination,[IO.FileAttributes]::Normal)
}
function Run-Measured([string]$Label,[string]$Mode,[int]$Round) {
    Check (@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count -eq 0) 'no unrelated Excel before operation'
    $working=Join-Path $EvidenceDirectory ($Round.ToString()+'-'+$Mode+'-'+$Label)
    [void][IO.Directory]::CreateDirectory($working)
    $file=Join-Path $working 'sample.xlsx'
    $source=if($Mode -eq 'Encrypt'){$plain}else{$encrypted}
    Copy-Fixture $source $file
    $before=Get-Sha $file
    Check ($before -eq (Get-Sha $source)) 'same immutable input bytes'
    $old=if($Mode -eq 'Encrypt'){''}else{'Latency-A42!'}
    $new=if($Mode -eq 'Decrypt'){''}elseif($Mode -eq 'ChangePassword'){'Latency-B42!'}else{'Latency-A42!'}
    $run=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run); Set-PrivateDirectory $run
    $request=Join-Path $run 'request.json'
    Write-Json @{schemaVersion=1;path=$file;mode=$Mode;expectedHash=$before;oldSecret=(Protect-Test $old);newSecret=(Protect-Test $new)} $request
    $script=Join-Path (Join-Path $EvidenceDirectory ($Label+'-runtime')) 'Engine.ps1'
    $launchArgs='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -RequestPath "'+$request+'"'
    $record=[ordered]@{runtime=$Label;mode=$Mode;round=$Round;inputSha256=$before;inputBytes=(Get-Item -LiteralPath $file).Length;milliseconds=0;exitCode=$null;status='NotCompleted';runDirectory=$run}
    $measurements.Add($record)
    $watch=[Diagnostics.Stopwatch]::StartNew();$process=$null
    try {
        $process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $launchArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $run 'stdout.log') -RedirectStandardError (Join-Path $run 'stderr.log')
        [void]$process.Handle
        while(-not $process.WaitForExit(250)) {
            if($watch.Elapsed.TotalSeconds -gt 180) {
                [IO.File]::WriteAllText((Join-Path $run 'cancel'),'cancel')
                throw 'Controller timeout; cancellation requested, inspect evidence without killing Excel.'
            }
        }
        $record.exitCode=$process.ExitCode
    } finally { $watch.Stop();$record.milliseconds=[Math]::Round($watch.Elapsed.TotalMilliseconds,2);if($process){$process.Dispose()} }
    $result=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $record.status=[string]$result.status
    Check ($record.exitCode -eq 0 -and $result.status -eq 'Success' -and $result.backend -eq 'DirectOoxml') 'direct operation succeeded'
    Check ((Get-Sha $result.backup) -eq $before) 'byte-identical original backup'
    Check ((Get-Sha $file) -eq $result.resultHash -and $result.recoveryRemoved) 'verified atomic replacement'
    foreach($path in @($request,(Join-Path $run 'worker-job.json'),$result.temp,$result.inputCopy,$result.recovery)) {
        if($path) { Check (-not [IO.File]::Exists($path)) 'owned intermediate and secret request removed' }
    }
    Check (@(Get-ChildItem -LiteralPath $working -File -Filter '.eps-*').Count -eq 0) 'no source-folder leftovers'
    Check (@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count -eq 0) 'direct operation creates no Excel process'
    # Independently read output with the unmodified baseline codec, outside timing.
    if($Mode -eq 'Decrypt') { Check ((Get-Sha $file) -eq $plainHash) 'exact plaintext restored' }
    else {
        $verify=Join-Path $working 'verified.xlsx'
        $verification=[ExcelPasswordSafe.Crypto.DirectCrypto]::Operate($file,$verify,'.xlsx','Decrypt',$new,'')
        Check ($verification.Status -eq 'Validated' -and (Get-Sha $verify) -eq $plainHash) 'baseline codec reads exact original plaintext'
    }
    Check ((Get-Sha $plain) -eq $plainHash -and (Get-Sha $encrypted) -eq $encryptedHash) 'immutable fixtures unchanged'
    Write-Json $measurements.ToArray() (Join-Path $EvidenceDirectory 'timings.json')
    Write-Output ($Label+' '+$Mode+' #'+$Round+': '+$record.milliseconds+' ms')
}
try {
    foreach($pair in @(@('baseline',$BaselineRuntime),@('current',$RuntimeDirectory))) {
        $target=Join-Path $EvidenceDirectory ($pair[0]+'-runtime');[void][IO.Directory]::CreateDirectory($target)
        $hashes=@{}
        foreach($name in @('Common.ps1','Engine.ps1','BatchEngine.ps1','ExcelPassword.Worker.ps1','ExcelPasswordSafe.Crypto.dll')) {
            [IO.File]::Copy((Join-Path $pair[1] $name),(Join-Path $target $name))
            $hashes[$name]=Get-Sha (Join-Path $target $name)
        }
        $runtimes.Add(@{label=$pair[0];source=[IO.Path]::GetFullPath($pair[1]);files=$hashes})
    }
    $plain=Join-Path $EvidenceDirectory 'plaintext-fixture.xlsx'
    Copy-Fixture (Join-Path $toolRoot 'upstream/1.1.0/ExcelPasswordSafe/tests/fixtures/picture_ooxml.xlsx') $plain
    $plainHash=Get-Sha $plain
    Add-Type -Path (Join-Path $EvidenceDirectory 'baseline-runtime/ExcelPasswordSafe.Crypto.dll')
    Check ((Get-Sha ([ExcelPasswordSafe.Crypto.DirectCrypto].Assembly.Location)) -eq $runtimes[0].files['ExcelPasswordSafe.Crypto.dll']) 'independent verifier is exact baseline assembly'
    $encrypted=Join-Path $EvidenceDirectory 'encrypted-fixture.xlsx'
    $setup=[ExcelPasswordSafe.Crypto.DirectCrypto]::Operate($plain,$encrypted,'.xlsx','Encrypt','','Latency-A42!')
    Check ($setup.Status -eq 'Validated') 'baseline-generated encrypted fixture'
    $encryptedHash=Get-Sha $encrypted
    [IO.File]::SetAttributes($plain,[IO.FileAttributes]::ReadOnly)
    [IO.File]::SetAttributes($encrypted,[IO.FileAttributes]::ReadOnly)
    for($round=1;$round -le $Repetitions;$round++) {
        $order=if(($round%2) -eq 1){@('baseline','current')}else{@('current','baseline')}
        foreach($mode in @('Encrypt','Decrypt','ChangePassword')) {
            foreach($label in $order) { Run-Measured $label $mode $round }
        }
    }
    $summary=@()
    foreach($label in @('baseline','current')) {
        foreach($mode in @('Encrypt','Decrypt','ChangePassword')) {
            $values=@($measurements|Where-Object{$_.runtime -eq $label -and $_.mode -eq $mode}|ForEach-Object{$_.milliseconds}|Sort-Object)
            $median=if(($values.Count%2) -eq 1){$values[[int][Math]::Floor($values.Count/2)]}else{($values[$values.Count/2-1]+$values[$values.Count/2])/2}
            $summary+=@{runtime=$label;mode=$mode;count=$values.Count;medianMs=$median;minMs=$values[0];maxMs=$values[-1]}
        }
    }
    Write-Json @{status='PASS';checks=$checks.ToArray();runtimes=$runtimes.ToArray();measurements=$measurements.ToArray();summary=$summary;plaintextSha256=$plainHash;encryptedSha256=$encryptedHash;timingScope='immediately before Start-Process through observed controller exit, including launch, backup/verification/commit/cleanup; excludes fixture setup and independent harness verification';order='paired per mode, baseline first on odd rounds and current first on even rounds';limitation='Three repetitions by default on one machine; no general latency guarantee.'} (Join-Path $EvidenceDirectory 'latency-results.json')
    Write-Output ('PASS: '+$checks.Count+' checks; '+$EvidenceDirectory)
} catch {
    Write-Json @{status='FAIL';checks=$checks.ToArray();runtimes=$runtimes.ToArray();measurements=$measurements.ToArray()} (Join-Path $EvidenceDirectory 'latency-results.json')
    throw
}
