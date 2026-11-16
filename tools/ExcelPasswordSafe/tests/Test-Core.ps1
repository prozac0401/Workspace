#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Core tests include engine preflight checks; wait until the separate Excel suite has finished and all Excel windows are closed normally.' }
if(-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $toolRoot)) 'artifacts/excel-password-safe/core') ([guid]::NewGuid().ToString('N')) }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
$checks=New-Object 'System.Collections.Generic.List[object]'
function Assert($Condition,[string]$Name) {
    $checks.Add([pscustomobject]@{name=$Name;passed=[bool]$Condition})
    if(-not $Condition) { throw ('ASSERT: '+$Name) }
}
function Assert-Throws([scriptblock]$Action,[string]$Name) {
    $threw=$false
    try { & $Action | Out-Null } catch { $threw=$true }
    Assert $threw $Name
}
function Protect-Test([string]$Text) {
    if(-not $Text) { return '' }
    $secure=ConvertTo-SecureString $Text -AsPlainText -Force
    try { ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
}
function New-TestRequest([string]$Path,[string]$Mode='Encrypt',[string]$Old='',[string]$New='Test-A42!') {
    $dir=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir); Set-PrivateDirectory $dir
    $request=[ordered]@{schemaVersion=1;path=$Path;mode=$Mode;oldSecret=Protect-Test $Old;newSecret=Protect-Test $New;expectedHash=Get-Sha $Path}
    Write-Json $request (Join-Path $dir 'request.json')
    return $dir
}
function Invoke-TestEngine([string]$RunDir,[string]$Expected) {
    $script=Join-Path $toolRoot 'runtime/Engine.ps1'
    $request=Join-Path $RunDir 'request.json'
    $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -RequestPath "'+$request+'"') -PassThru -WindowStyle Hidden
    try {
        if(-not $p.WaitForExit(15000)) { $p.Kill(); throw 'Preflight test unexpectedly timed out.' }
    } finally { $p.Dispose() }
    $r=Get-Content -LiteralPath (Join-Path $RunDir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($r.category -eq $Expected) ('engine category '+$Expected+' actual='+$r.category)
    Assert (-not [IO.File]::Exists($request)) ('secret request removed '+$Expected)
    Assert (-not [IO.File]::Exists((Join-Path $RunDir 'worker-job.json'))) ('no retained worker secret '+$Expected)
    return $r
}
try {
    foreach($name in @('Common.ps1','Engine.ps1','ExcelPassword.Worker.ps1')) {
        $tokens=$null; $errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $toolRoot ('runtime/'+$name)),[ref]$tokens,[ref]$errors)
        Assert (@($errors).Count -eq 0) ('PowerShell 5.1 parse '+$name)
    }
    foreach($pair in @(@('.xls',56),@('.xlsx',51),@('.xlsx',61),@('.xlsm',52),@('.xlsb',50))) { Assert ($pair[1] -in @(Get-AllowedFormats $pair[0])) ('format '+$pair[1]) }
    Assert (39 -notin @(Get-AllowedFormats '.xls')) 'Excel95 unsupported'
    $secret='한글 Test42!'
    Assert ((Unprotect-Text (Protect-Test $secret)) -ceq $secret) 'DPAPI Unicode roundtrip'
    $request=[pscustomobject]@{schemaVersion=1;path='C:\sample.xlsx';mode='ChangePassword';oldSecret=Protect-Test 'Before-42!';newSecret=Protect-Test 'After-99!';expectedHash=('A'*64)}
    Assert-Request $request; Assert $true 'change request accepted'
    $request.newSecret=$request.oldSecret
    Assert-Throws { Assert-Request $request } 'same old and new rejected'
    $request.newSecret=Protect-Test 'before-42!'
    Assert-Request $request; Assert $true 'password comparison case-sensitive'
    $request.oldSecret=''
    Assert-Throws { Assert-Request $request } 'change requires current password'
    $request.mode='Decrypt'
    Assert-Throws { Assert-Request $request } 'decrypt requires current password'
    $request.mode='Encrypt'; $request.newSecret=Protect-Test ('a'*16)
    Assert-Throws { Assert-Request $request } 'new password maximum enforced'
    $request.newSecret=''
    Assert-Throws { Assert-Request $request } 'new password minimum enforced'
    $request.newSecret=Protect-Test 'Valid'; $request.schemaVersion=2
    Assert-Throws { Assert-Request $request } 'unknown request schema rejected'

    $json=Join-Path $EvidenceDirectory 'atomic.json'
    Write-Json @{state='BackedUp';value=1} $json
    $prior=Get-Sha $json
    $jsonLock=[IO.File]::Open($json,'Open','Read','Read')
    try { Assert-Throws { Write-Json @{state='CommitIntent'} $json } 'interrupted journal replacement fails closed' }
    finally { $jsonLock.Dispose() }
    Assert ((Get-Sha $json) -eq $prior) 'previous complete journal retained on replacement failure'
    Assert ((Get-Content -LiteralPath $json -Raw | ConvertFrom-Json).state -eq 'BackedUp') 'retained journal remains readable'
    Write-Json @{state='CommitIntent';value=2} $json
    Assert ((Get-Content -LiteralPath $json -Raw | ConvertFrom-Json).state -eq 'CommitIntent') 'journal atomic replacement succeeds'

    $source=Join-Path $EvidenceDirectory '한글 [a] & $test.xlsx'
    $temp=Join-Path $EvidenceDirectory 'temp.xlsx'; $backup=Join-Path $EvidenceDirectory 'backup.xlsx'; $recovery=Join-Path $EvidenceDirectory 'recovery'
    [IO.File]::WriteAllText($source,'original test bytes'); [IO.File]::Copy($source,$backup); [IO.File]::WriteAllText($temp,'validated test bytes')
    $sourceHash=Get-Sha $source; $tempHash=Get-Sha $temp
    $hold=[IO.File]::Open($source,'Open','Read',([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
    try {
        Assert-Throws { [IO.File]::WriteAllText($source,'concurrent writer') } 'held source denies concurrent writes'
        Assert ((Get-StreamSha $hold) -eq $sourceHash) 'held source hash'
        foreach($which in @('temp','backup')) {
            $file=if($which -eq 'temp'){$temp}else{$backup}; $bytes=[IO.File]::ReadAllBytes($file)
            [IO.File]::WriteAllText($file,'external modification')
            Assert-Throws { Invoke-GuardedReplace $source $temp $backup $recovery $sourceHash $tempHash $hold } ($which+' tamper rejected')
            Assert ((Get-Sha $source) -eq $sourceHash) ($which+' tamper original retained')
            [IO.File]::WriteAllBytes($file,$bytes)
        }
        Assert-Throws { Invoke-GuardedReplace $source $temp $backup $recovery ('0'*64) $tempHash $hold } 'stale approval rejected'
        $tempLock=[IO.File]::Open($temp,'Open','Read','Read')
        try { Assert-Throws { Invoke-GuardedReplace $source $temp $backup $recovery $sourceHash $tempHash $hold } 'locked output rejects commit without fallback' }
        finally { $tempLock.Dispose() }
        Assert ((Get-Sha $source) -eq $sourceHash -and (Get-Sha $backup) -eq $sourceHash) 'failed commit preserves original and backup'
        $actual=Invoke-GuardedReplace $source $temp $backup $recovery $sourceHash $tempHash $hold
        Assert ($actual -eq $tempHash -and (Get-Sha $source) -eq $tempHash) 'actual NTFS atomic replace'
        Assert ((Get-Sha $backup) -eq $sourceHash -and (Get-Sha $recovery) -eq $sourceHash) 'recoverable exact prior bytes retained'
    } finally { $hold.Dispose() }
    # Manual recovery is explicit and retains the result being rolled back.
    $restore=Join-Path $EvidenceDirectory 'restore.xlsx'; $rolledBack=Join-Path $EvidenceDirectory 'rolled-back-result.xlsx'
    [IO.File]::Copy($backup,$restore)
    [IO.File]::Replace($restore,$source,$rolledBack)
    Assert ((Get-Sha $source) -eq $sourceHash -and (Get-Sha $rolledBack) -eq $tempHash) 'manual rollback preserves both versions'

    $other=Join-Path $EvidenceDirectory 'unselected.txt'; [IO.File]::WriteAllText($other,'unselected business fixture'); $otherHash=Get-Sha $other
    $run=New-TestRequest $source
    [IO.File]::WriteAllText((Join-Path $run 'cancel'),'cancel')
    $r=Invoke-TestEngine $run 'Cancelled'
    Assert ($r.status -eq 'Cancelled' -and -not [IO.File]::Exists((Join-Path $run 'original.xlsx'))) 'cancellation before backup preserves original'
    $run=New-TestRequest $source
    $mutex=New-Object Threading.Mutex($false,(Get-EngineMutexName)); $owned=$mutex.WaitOne(0)
    if(-not $owned) { $mutex.Dispose(); throw 'Another real operation is running; stop core tests.' }
    try { $null=Invoke-TestEngine $run 'AnotherOperationRunning' } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
    $run=New-TestRequest $source
    [IO.File]::WriteAllText($source,'changed after confirmation')
    $null=Invoke-TestEngine $run 'SourceChanged'
    Assert ([IO.File]::ReadAllText($source) -eq 'changed after confirmation') 'external newer source preserved'
    $run=New-TestRequest $source
    $attrs=[IO.File]::GetAttributes($source); [IO.File]::SetAttributes($source,($attrs -bor [IO.FileAttributes]::ReadOnly))
    try { $null=Invoke-TestEngine $run 'ReadOnlyAttribute' } finally { [IO.File]::SetAttributes($source,$attrs) }
    $run=New-TestRequest $source
    $lock=[IO.File]::Open($source,'Open','Read','None')
    try { $null=Invoke-TestEngine $run 'FileInUse' } finally { $lock.Dispose() }
    $run=New-TestRequest $source -Mode ChangePassword -Old 'same' -New 'same'
    $null=Invoke-TestEngine $run 'PasswordUnchanged'
    Assert ((Get-Sha $other) -eq $otherHash) 'unselected files untouched'
    foreach($path in @('C:relative.xlsx','\\server\share\a.xlsx','C:\file.xlsx:stream')) { Assert-Throws { Assert-LocalWorkbook $path } ('unsafe path rejected '+$path) }
    Write-Json @{status='PASS';count=$checks.Count;checks=$checks.ToArray();powershell=$PSVersionTable.PSVersion.ToString();excelCom='NOT RUN';timestamp=[DateTime]::UtcNow.ToString('o')} (Join-Path $EvidenceDirectory 'core-results.json')
    Write-Output "PASS: $($checks.Count) assertions; $EvidenceDirectory"
} catch {
    Write-Json @{status='FAIL';count=$checks.Count;checks=$checks.ToArray();error=$_.Exception.Message} (Join-Path $EvidenceDirectory 'core-results.json')
    throw
}
