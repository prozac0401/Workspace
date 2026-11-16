# Cross-platform tests: no Excel, no business files, no Pester dependency.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common.ps1')
$count=0
function Assert($Condition,[string]$Message) {
    if(-not $Condition) { throw ('ASSERT: '+$Message) }
    $script:count++
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('eps-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    foreach($file in Get-ChildItem (Split-Path -Parent $PSScriptRoot) -Filter *.ps1 -Recurse) {
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert (@($errors).Count -eq 0) ('parse '+$file.Name)
        $newSyntax=$ast.FindAll({param($n) $n.GetType().Name -in @('PipelineChainAst','TernaryExpressionAst')},$true)
        Assert (@($newSyntax).Count -eq 0) ('PS5 syntax guard '+$file.Name)
    }
    foreach($pair in @(@('.xls',56),@('.xlsx',51),@('.xlsm',52),@('.xlsb',50))) {
        Assert ($pair[1] -in @(Get-AllowedFormats $pair[0])) ('format '+$pair[0])
    }
    Assert (61 -in @(Get-AllowedFormats '.xlsx')) 'strict xlsx preserved'
    Assert (39 -notin @(Get-AllowedFormats '.xls')) 'unsupported legacy format refused'
    $nested=Join-Path $root 'nested'; New-Item -ItemType Directory $nested | Out-Null
    foreach($name in @('a.xls','b.xlsx','c.xlsm','d.xlsb','~$lock.xlsx','.eps-temp.xls','plain.txt')) {
        [IO.File]::WriteAllText((Join-Path $nested $name),'fixture')
    }
    $files=@(Get-Candidates $root)
    Assert ($files.Count -eq 4) 'recursive selection excludes locks/temp/unrelated'
    Assert-NoReparse $files[0]; Assert $true 'file ancestor traversal'
    $source=Join-Path $root 'source.xlsx'; $temp=Join-Path $root 'temp.xlsx'
    $backup=Join-Path $root 'original.xlsx'; $recovery=Join-Path $root 'recovery'
    [IO.File]::WriteAllText($source,'original bytes')
    [IO.File]::Copy($source,$backup)
    [IO.File]::WriteAllText($temp,'validated bytes')
    $originalHash=Get-Sha $source; $outputHash=Get-Sha $temp
    $stream=[IO.File]::Open($source,'Open','Read',([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
    try {
        Assert ((Get-StreamSha $stream) -eq $originalHash) 'stream hashing'
        foreach($case in @('temp','backup')) {
            $target=if($case -eq 'temp'){$temp}else{$backup}
            $bytes=[IO.File]::ReadAllBytes($target)
            [IO.File]::WriteAllText($target,'tampered')
            $threw=$false
            try { Invoke-GuardedReplace $source $temp $backup $recovery $originalHash $outputHash $stream | Out-Null } catch { $threw=$true }
            Assert $threw ($case+' tamper rejected')
            Assert ((Get-Sha $source) -eq $originalHash) ($case+' tamper leaves source intact')
            [IO.File]::WriteAllBytes($target,$bytes)
        }
        $threw=$false
        try { Invoke-GuardedReplace $source $temp $backup $recovery ('0'*64) $outputHash $stream | Out-Null } catch { $threw=$true }
        Assert $threw 'stale source hash rejected'
        Assert ((Get-Sha $source) -eq $originalHash) 'stale source leaves original intact'
        $actual=Invoke-GuardedReplace $source $temp $backup $recovery $originalHash $outputHash $stream
        Assert ($actual -eq $outputHash) 'atomic replace output verified'
        Assert ((Get-Sha $recovery) -eq $originalHash) 'atomic recovery is original bytes'
        Assert ((Get-Sha $backup) -eq $originalHash) 'outside backup retained'
    } finally { $stream.Dispose() }
    foreach($fixture in Get-ChildItem (Join-Path $PSScriptRoot 'fixtures') -File | Where-Object { $_.Extension -in @('.xls','.xlsx') }) {
        $s=Join-Path $root ('actual'+$fixture.Extension); $t=$s+'.temp'; $b=$s+'.backup'; $r=$s+'.recovery'
        [IO.File]::Copy($fixture.FullName,$s); [IO.File]::Copy($s,$b); [IO.File]::Copy($s,$t)
        $hash=Get-Sha $s
        $held=[IO.File]::Open($s,'Open','Read',([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
        try { $outcome=Invoke-GuardedReplace $s $t $b $r $hash $hash $held }
        finally { $held.Dispose() }
        Assert ($outcome -eq $hash) ('synthetic '+$fixture.Extension+' byte transaction')
        Assert ((Get-Sha $b) -eq $hash -and (Get-Sha $r) -eq $hash) ('synthetic '+$fixture.Extension+' backup/recovery')
    }
    $csv=Join-Path $root 'log.csv'
    $weird=Join-Path $root '한글, [a] & quote".xls'
    [pscustomobject]@{path=$weird;status='Failed';category='FileInUse';message="line1`nline2"} | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $roundtrip=Import-Csv -LiteralPath $csv
    Assert ($roundtrip.path -ceq $weird) 'CSV special/Unicode paths round-trip'
    Assert ($roundtrip.message -ceq "line1`nline2") 'CSV multiline message round-trip'
    foreach($pair in @(@(-2147319779,'ComRegistrationOrLibrary'),@(-2147417851,'ComServerError'),@(-2147024864,'FileInUse'),@(-2147024891,'AccessDenied'))) {
        $exception=New-Object Runtime.InteropServices.COMException('synthetic',[int]$pair[0])
        $record=New-Object Management.Automation.ErrorRecord($exception,'synthetic',[Management.Automation.ErrorCategory]::NotSpecified,$null)
        Assert ((Get-Category $record 'Open') -eq $pair[1]) ('HRESULT '+$pair[1])
    }
    $ex=New-Object Exception 'ambiguous'
    $er=New-Object Management.Automation.ErrorRecord($ex,'x',[Management.Automation.ErrorCategory]::NotSpecified,$null)
    Assert ((Get-Category $er 'Open') -eq 'OpenFailedPossiblePasswordOrCorruption') 'ambiguous open is not called definite wrong password'
    $worker=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'ExcelPassword.Worker.ps1') -Raw
    Assert ($worker -notmatch '\[IO.File\]::Replace|Stop-Process|taskkill|GetActiveObject') 'worker cannot replace originals or kill Excel'
    $controller=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'ExcelPassword.ps1') -Raw
    Assert ($controller.IndexOf('Type $token') -lt $controller.IndexOf('$hold.CopyTo')) 'approval precedes any workbook copying'
    Write-Output "PASS: $count assertions (PowerShell $($PSVersionTable.PSVersion), $([Environment]::OSVersion.Platform)); Excel COM NOT tested."
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
