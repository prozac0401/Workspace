# Windows PowerShell 5.1. Synthetic Excel runtime tests; never installs a product.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AddinPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifacts=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith(($artifacts.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
    throw 'OutputDirectory must be a new directory below repository artifacts.'
}
if(Test-Path -LiteralPath $output){throw 'Choose a fresh evidence directory; earlier results are preserved.'}
$ancestor=$output
while($ancestor -and $ancestor.Length -ge $artifacts.Length){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'OutputDirectory must not pass through a reparse point.'
    }
    $ancestor=Split-Path -Parent $ancestor
}
[void][IO.Directory]::CreateDirectory($output)
$utf8=New-Object Text.UTF8Encoding($false)
$addin=[IO.Path]::GetFullPath($AddinPath)
$audit=[ordered]@{
    schemaVersion=1; status='NOT_RUN'; startedUtc=[DateTime]::UtcNow.ToString('o'); finishedUtc=$null
    addinPath=$addin; expectedSha256=$ExpectedSha256.ToLowerInvariant(); actualSha256=$null; finalSha256=$null
    releaseVersion=$null; owner=$null; tests=@(); failure=$null; cleanupErrors=@(); excelExited=$null
    securityChanged=$false; installedTests='NOT_RUN'; nativeInputTests='NOT_RUN'; releaseApproved=$false
}
$script:Excel=$null; $script:ExcelVersion=$null; $script:ExcelProcess=$null
$script:ExcelBootstrap=$null; $script:ExcelSessionBook=$null
$functionsLoaded=$false; $book=$null; $bookOwned=$false; $unknownBooks=$false
$mutex=$null; $locked=$false; $exitCode=1
function Save-Audit {
    [IO.File]::WriteAllText((Join-Path $output 'usability.private.json'),($audit | ConvertTo-Json -Depth 10),$utf8)
}
function Test-Failure([string]$Message,[string]$Status='FAIL',[int]$Code=1){
    $failure=New-Object InvalidOperationException($Message)
    $failure.Data['Status']=$Status; $failure.Data['ExitCode']=$Code
    return $failure
}
function Assert-OnlyCandidate {
    for($i=1;$i -le [int]$script:Excel.Workbooks.Count;$i++){
        $observed=$null
        try{
            $observed=$script:Excel.Workbooks.Item($i)
            if(-not $bookOwned -or [string]$observed.FullName -ine $addin){
                $script:unknownBooks=$true
                throw (Test-Failure 'An unexpected workbook is open. It is preserved; testing and application shutdown are refused.' 'BLOCKED_ENV' 3)
            }
        }finally{
            # Avoid releasing a shared RCW alias for the owned candidate.
            if($null -ne $observed -and -not [object]::ReferenceEquals($observed,$book)){Release-Com $observed}
        }
    }
}
try{
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -ne 5){
        throw (Test-Failure 'Use native Windows PowerShell 5.1.' 'BLOCKED_ENV' 3)
    }
    $mutex=New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-Setup')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw (Test-Failure 'Another product build/install/remove/test operation is running.' 'BLOCKED_ENV' 4)}
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){
        throw (Test-Failure 'Excel is already running. Existing Excel processes and workbooks were not touched.' 'BLOCKED_ENV' 3)
    }
    if(-not (Test-Path -LiteralPath $addin -PathType Leaf) -or [IO.Path]::GetExtension($addin) -ine '.xlam'){
        throw (Test-Failure 'An explicit existing XLAM candidate is required.' 'BLOCKED_ENV' 3)
    }
    $audit.actualSha256=(Get-FileHash -LiteralPath $addin -Algorithm SHA256).Hash.ToLowerInvariant()
    if($audit.actualSha256 -cne $audit.expectedSha256){throw 'The requested candidate hash does not match; no Excel was started.'}
    # Read function definitions only. Never execute Setup.ps1's action dispatcher.
    $tokens=$null; $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Setup.ps1'),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Setup helper source has parse errors.'}
    foreach($name in @('Setup-Failure','Release-Com','New-SessionBootstrap','Start-OwnExcel','Stop-OwnExcel')){
        $found=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$false))
        if($found.Count -ne 1){throw ('Expected exactly one helper: '+$name)}
        . ([scriptblock]::Create($found[0].Extent.Text))
    }
    $functionsLoaded=$true
    Start-OwnExcel -NormalStart
    $audit.owner=[ordered]@{pid=$script:ExcelProcess.Id;startTimeUtcTicks=$script:ExcelProcess.StartTime.ToUniversalTime().Ticks}
    $audit.excelVersion=$script:ExcelVersion
    # A normal launch may auto-load an existing add-in with the same name.
    # Never invoke or unload that installed add-in as though it were this candidate.
    $existing=$null
    try{$existing=$script:Excel.Workbooks.Item([IO.Path]::GetFileName($addin))}catch{}
    if($null -ne $existing){
        $unknownBooks=$true
        Release-Com $existing
        throw (Test-Failure 'An add-in with the candidate name is already loaded. No macro was run or add-in unloaded.' 'BLOCKED_ENV' 3)
    }
    Assert-OnlyCandidate
    $book=$script:Excel.Workbooks.Open($addin,0,$true)
    $bookOwned=$true
    if([IO.Path]::GetFullPath([string]$book.FullName) -ine $addin -or -not [bool]$book.IsAddin){throw 'Excel did not open the exact candidate as an add-in.'}
    Assert-OnlyCandidate
    $q="'"+([string]$book.Name).Replace("'","''")+"'!"
    $audit.releaseVersion=[string]$script:Excel.Run($q+'SLC_ReleaseVersion')
    if($audit.releaseVersion -notin @('0.2.0-rc.10','0.2.0-rc.11')){throw 'This usability harness expects an RC10 or R11 candidate.'}
    foreach($name in @('SLC_TestAll','SLC_UsabilityTests')){
        Assert-OnlyCandidate
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $result=[string]$script:Excel.Run($q+$name)
        $timer.Stop()
        $passed=$result.StartsWith('PASS:',[StringComparison]::Ordinal)
        $audit.tests+=@([ordered]@{name=$name;status=$(if($passed){'PASS'}else{'FAIL'});result=$result;elapsedSeconds=$timer.Elapsed.TotalSeconds})
        Save-Audit
        Assert-OnlyCandidate
        if(-not $passed){throw ('Runtime self-test failed: '+$name+' '+$result)}
    }
    $audit.finalSha256=(Get-FileHash -LiteralPath $addin -Algorithm SHA256).Hash.ToLowerInvariant()
    if($audit.finalSha256 -cne $audit.actualSha256){throw 'The candidate changed during read-only runtime testing.'}
    $audit.status='PASS'; $exitCode=0
}catch{
    $audit.status='FAIL'; $audit.failure=$_.Exception.Message
    if($_.Exception.Data.Contains('Status')){$audit.status=[string]$_.Exception.Data['Status']}
    if($_.Exception.Data.Contains('ExitCode')){$exitCode=[int]$_.Exception.Data['ExitCode']}
}finally{
    if($functionsLoaded -and $null -ne $script:Excel){
        try{Assert-OnlyCandidate}catch{$unknownBooks=$true;$audit.cleanupErrors+=@($_.Exception.Message)}
        if($bookOwned -and $null -ne $book){
            try{$book.Close($false)}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
            Release-Com $book; $book=$null; $bookOwned=$false
        }
        if(-not $unknownBooks){
            try{Stop-OwnExcel}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
        }else{
            # Preserve unknown documents; release our reference without Quit or kill.
            Release-Com $script:Excel; $script:Excel=$null
        }
    }
    if($null -ne $audit.owner){
        [GC]::Collect();[GC]::WaitForPendingFinalizers()
        $remaining=Get-Process -Id $audit.owner.pid -ErrorAction SilentlyContinue
        $same=$false
        if($null -ne $remaining){
            try{$same=$remaining.StartTime.ToUniversalTime().Ticks -eq $audit.owner.startTimeUtcTicks}finally{$remaining.Dispose()}
        }
        $audit.excelExited=(-not $same)
        if($same){$audit.cleanupErrors+=@('Owned Excel remains open; no process was killed.')}
    }
    if($audit.cleanupErrors.Count -gt 0 -and $audit.status -eq 'PASS'){$audit.status='FAIL';$exitCode=1}
    if($locked -and $null -ne $mutex){$mutex.ReleaseMutex()}
    if($null -ne $mutex){$mutex.Dispose()}
    $audit.finishedUtc=[DateTime]::UtcNow.ToString('o')
    Save-Audit
}
Write-Output ($audit.status+': '+$(if($audit.failure){$audit.failure}else{'See usability.private.json for exact test and cleanup results.'}))
exit $exitCode
