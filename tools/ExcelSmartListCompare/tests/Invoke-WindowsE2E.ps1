[CmdletBinding()]
param(
    [ValidateSet('Preflight','Build','Guards','Functional')][string]$Phase='Preflight',
    [string]$RunId=(Get-Date -Format 'yyyyMMdd-HHmmss')
)
# Run in native Windows PowerShell. No execution-policy override or elevation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Windows desktop Excel is required.'}
if($RunId -notmatch '^[A-Za-z0-9_-]+$'){throw 'RunId must be a simple directory name.'}
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root ('artifacts/windows-e2e/'+$RunId)
if(Test-Path -LiteralPath $out){throw 'Run directory already exists; choose a new RunId to preserve evidence.'}
[void](New-Item -ItemType Directory -Path $out)
$commands=New-Object System.Collections.Generic.List[object]
function Invoke-Step([string]$id,[string]$script,[string[]]$arguments){
    $stdout=Join-Path $out ($id+'.stdout.log');$stderr=Join-Path $out ($id+'.stderr.log')
    $args=@('-NoLogo','-NoProfile','-STA','-File',('"'+$script+'"'))+$arguments
    $started=Get-Date
    $process=Start-Process -FilePath powershell.exe -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null=$process.Handle
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while(-not $process.WaitForExit(1000)){
        if($timer.Elapsed.TotalSeconds -ge 120){
            $commands.Add([pscustomobject]@{id=$id;status='BLOCKED_ENV';reason='120 second harness deadline; process not killed';powershellPid=$process.Id;stdout=$stdout;stderr=$stderr})
            throw 'Deadline reached. Inspect the owned setup/Excel process and any Office dialog; this runner does not dismiss security warnings or kill Excel.'
        }
    }
    $process.Refresh()
    $code=$process.ExitCode
    $status=if($code -eq 0){'PASS'}elseif($code -eq 5){'BLOCKED_POLICY'}else{'FAIL'}
    $commands.Add([pscustomobject]@{id=$id;command=('powershell.exe '+($args -join ' '));started=$started.ToString('o');exitCode=$code;status=$status;durationMs=$timer.ElapsedMilliseconds;stdout=$stdout;stderr=$stderr})
    Write-Host "$id $status exit=$code"
    return $code
}
$exitCode=0
try{
    $null=Invoke-Step 'baseline-before' (Join-Path $PSScriptRoot 'windows-baseline.ps1') @('-OutputPath',('"'+(Join-Path $out 'baseline-before.json')+'"'))
    switch($Phase){
        'Preflight' {$exitCode=Invoke-Step 'excel-preflight' (Join-Path $PSScriptRoot 'windows-excel-preflight.ps1') @('-OutputPath',('"'+(Join-Path $out 'excel-preflight.json')+'"'))}
        'Build' {$exitCode=Invoke-Step 'build' (Join-Path $root 'Setup.ps1') @('-Action','Build')}
        'Guards' {$exitCode=Invoke-Step 'guards' (Join-Path $PSScriptRoot 'windows-setup-guards.ps1') @('-OutputDirectory',('"'+(Join-Path $out 'guards')+'"'))}
        'Functional' {$exitCode=Invoke-Step 'functional' (Join-Path $PSScriptRoot 'windows-functional.ps1') @('-AddinPath',('"'+(Join-Path $root 'Release/ExcelSmartListCompare.xlam')+'"'),'-OutputDirectory',('"'+(Join-Path $out 'functional')+'"'))}
    }
}finally{
    $null=Invoke-Step 'baseline-after' (Join-Path $PSScriptRoot 'windows-baseline.ps1') @('-OutputPath',('"'+(Join-Path $out 'baseline-after.json')+'"'))
    $commands | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'commands.json') -Encoding UTF8
}
exit $exitCode
