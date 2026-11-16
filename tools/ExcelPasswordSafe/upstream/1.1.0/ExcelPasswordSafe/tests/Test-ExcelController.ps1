#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [Parameter(Mandatory=$true)][string]$FixtureDirectory
)

$packageRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $packageRoot 'Common.ps1')
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell 5.1 with desktop Excel.'
}
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) {
    throw 'Close Excel normally before starting the controller test.'
}
$fixtureRoot = [IO.Path]::GetFullPath($FixtureDirectory).TrimEnd('\')
$evidenceRoot = [IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\')
if((Split-Path -Parent $evidenceRoot) -ine $fixtureRoot -or (Test-Path -LiteralPath $evidenceRoot)) {
    throw 'EvidenceDirectory must be a new direct child of FixtureDirectory.'
}
Assert-NoReparse $fixtureRoot
$marker = Join-Path $fixtureRoot 'excel-password-safe.synthetic'
Assert-NoReparse $marker
if((Get-Content -LiteralPath $marker -Raw).Trim() -cne 'ExcelPasswordSafe synthetic fixtures') {
    throw 'Use the fixture directory created by Test-ExcelSynthetic.ps1.'
}

$controller = Join-Path $packageRoot 'ExcelPassword.ps1'
$target = Join-Path $evidenceRoot 'target'
$nested = Join-Path $target 'subfolder'
New-Item -ItemType Directory -Path $evidenceRoot | Out-Null
[void][IO.Directory]::CreateDirectory($nested)
foreach($name in @('fixture-56.xls','fixture-51.xlsx','fixture-52.xlsm','fixture-50.xlsb','fixture-61.xlsx','picture_biff8.xls','picture_vba.xlsm')) {
    $source = Join-Path $fixtureRoot $name
    if($name -in @('fixture-61.xlsx','picture_biff8.xls','picture_vba.xlsm') -and -not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    Assert-NoReparse $source
    [IO.File]::Copy($source,(Join-Path $nested $name),$false)
}
$lockedFile = Join-Path $target '01-잠금 [test] & sample.xlsx'
$readOnlyFile = Join-Path $target '02-read-only.xlsx'
[IO.File]::Copy((Join-Path $nested 'fixture-51.xlsx'),$lockedFile,$false)
[IO.File]::Copy((Join-Path $nested 'fixture-51.xlsx'),$readOnlyFile,$false)
$reportPath = Join-Path $evidenceRoot 'controller-results.csv'

function Assert-Controller($Condition,[string]$Message) {
    if(-not $Condition) { throw $Message }
}

function Get-SyntheticHashes {
    $hashes = @{}
    foreach($path in Get-Candidates $target) { $hashes[$path] = Get-Sha $path }
    return $hashes
}

function Assert-SyntheticHashes($Expected) {
    $actual = Get-SyntheticHashes
    Assert-Controller ($actual.Count -eq $Expected.Count) 'Synthetic file list changed.'
    foreach($path in $Expected.Keys) {
        Assert-Controller ($actual[$path] -eq $Expected[$path]) ('File changed unexpectedly: '+$path)
    }
}

function Invoke-SyntheticController {
    param(
        [string]$Phase,
        [string]$Mode = 'Encrypt',
        [switch]$Execute,
        [switch]$Cancel,
        [switch]$HoldLock,
        [string]$RetryLog,
        [int]$ExpectedExit = 0
    )

    $backupRoot = Join-Path $evidenceRoot ('backups-'+$Phase)
    # Only this call scope shadows Read-Host. The production script and worker stay unchanged.
    $epsSyntheticGate = @{Approved=$false; Lock=$null}
    function Read-Host {
        param([string]$Prompt,[switch]$AsSecureString)
        if(-not $AsSecureString -and $Prompt -match '^Review ALL targets and backups above\. Type (APPLY-[0-9]{8}-[0-9]{6}-[0-9a-f]{8}) to permit overwrite$') {
            if($Cancel) { return 'synthetic cancel' }
            $epsSyntheticGate.Approved = $true
            if($HoldLock) { $epsSyntheticGate.Lock = [IO.File]::Open($lockedFile,'Open','Read','None') }
            return $Matches[1]
        }
        if(-not $AsSecureString -or -not $epsSyntheticGate.Approved) { throw 'Unexpected controller prompt.' }
        switch -Wildcard ($Prompt) {
            'Existing opening password*' {
                if($Mode -eq 'Encrypt') { return (New-Object Security.SecureString) }
                return (ConvertTo-SecureString 'EpsTest-42!' -AsPlainText -Force)
            }
            'New opening password*' { return (ConvertTo-SecureString 'EpsTest-42!' -AsPlainText -Force) }
            'Repeat new password' { return (ConvertTo-SecureString 'EpsTest-42!' -AsPlainText -Force) }
            default { throw 'Unexpected password prompt.' }
        }
    }
    try {
        & $controller -Mode $Mode -Root $target -BackupRoot $backupRoot -Execute:$Execute -RetryLog $RetryLog -MaxAttempts 1 | Out-Host
        $exitCode = $LASTEXITCODE
    } finally {
        if($null -ne $epsSyntheticGate.Lock) { $epsSyntheticGate.Lock.Dispose() }
    }
    Assert-Controller ($exitCode -eq $ExpectedExit) ("$Phase exit code $exitCode, expected $ExpectedExit.")
    $runs = @(Get-ChildItem -LiteralPath $backupRoot -Directory)
    Assert-Controller ($runs.Count -eq 1) ('Expected one run directory for '+$Phase)
    return $runs[0].FullName
}

function Assert-CommitRows {
    param([string]$RunDirectory,$Rows,$Before,[string]$Mode)
    $states = @{}
    foreach($stateFile in Get-ChildItem -LiteralPath $RunDirectory -Filter '*.state.json' -File) {
        $state = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
        $states[$state.path] = $state
    }
    $workers = @{}
    foreach($resultFile in Get-ChildItem -LiteralPath $RunDirectory -Filter '*.result.json' -File) {
        $result = Get-Content -LiteralPath $resultFile.FullName -Raw | ConvertFrom-Json
        if($result.status -eq 'Validated') { $workers[$result.tempHash] = $result }
    }
    foreach($row in $Rows) {
        $path = $row.path
        Assert-Controller ($row.status -eq 'Success' -and $row.category -eq 'ReplacedAndVerified') ('Expected commit: '+$path)
        $state = $states[$path]
        Assert-Controller ($null -ne $state -and $state.state -eq 'Committed') ('Missing commit state: '+$path)
        Assert-Controller ($row.mode -eq $Mode -and $row.sourceHash -eq $Before[$path] -and $state.sourceHash -eq $Before[$path]) ('Incorrect input evidence: '+$path)
        Assert-Controller ((Get-Sha $row.backup) -eq $Before[$path]) ('Backup does not match input: '+$path)
        Assert-Controller ((Get-Sha $state.recovery) -eq $Before[$path]) ('Recovery does not match input: '+$path)
        Assert-Controller ($row.resultHash -eq $state.resultHash -and (Get-Sha $path) -eq $row.resultHash -and $row.resultHash -ne $Before[$path]) ('Incorrect output evidence: '+$path)
        $worker = $workers[$row.resultHash]
        Assert-Controller ($null -ne $worker -and $worker.encryptedBefore -eq ($Mode -eq 'Decrypt')) ('Missing real Excel verification: '+$path)
    }
}

$original = Get-SyntheticHashes
$phase = 'preview'
try {
    $run = Invoke-SyntheticController -Phase $phase
    Assert-Controller ((@(Import-Csv -LiteralPath (Join-Path $run 'plan.csv'))).Count -eq $original.Count) 'Preview did not list every synthetic file.'
    Assert-Controller (-not (Test-Path -LiteralPath (Join-Path $run 'originals'))) 'Preview wrote backups.'
    Assert-SyntheticHashes $original
    [pscustomobject]@{phase=$phase;status='Passed';detail='Plan listed all files; workbook hashes unchanged.'} | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8

    $phase = 'cancel'
    $run = Invoke-SyntheticController -Phase $phase -Execute -Cancel -ExpectedExit 2
    Assert-Controller (-not (Test-Path -LiteralPath (Join-Path $run 'originals'))) 'Cancelled run wrote backups.'
    Assert-SyntheticHashes $original
    [pscustomobject]@{phase=$phase;status='Passed';detail='Cancelled approval; workbook hashes unchanged.'} | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -Append

    $phase = 'encrypt'
    $attributes = [IO.File]::GetAttributes($readOnlyFile)
    [IO.File]::SetAttributes($readOnlyFile,($attributes -bor [IO.FileAttributes]::ReadOnly))
    try { $run = Invoke-SyntheticController -Phase $phase -Execute -HoldLock -ExpectedExit 1 }
    finally { [IO.File]::SetAttributes($readOnlyFile,$attributes) }
    $encryptLog = Join-Path $run 'results.csv'
    $rows = @(Import-Csv -LiteralPath $encryptLog)
    $blocked = @($rows | Where-Object { $_.path -in @($lockedFile,$readOnlyFile) })
    $success = @($rows | Where-Object { $_.path -notin @($lockedFile,$readOnlyFile) })
    Assert-Controller ($rows.Count -eq $original.Count -and $blocked.Count -eq 2) 'Missing encryption results.'
    foreach($row in $blocked) {
        $expectedCategory = if($row.path -eq $lockedFile) { 'FileInUse' } else { 'ReadOnlyAttribute' }
        Assert-Controller ($row.status -eq 'Failed' -and $row.category -eq $expectedCategory) ('Incorrect blocked-file result: '+$row.path+' '+$row.category)
        Assert-Controller ((Get-Sha $row.path) -eq $original[$row.path]) ('Blocked file changed: '+$row.path)
    }
    Assert-CommitRows -RunDirectory $run -Rows $success -Before $original -Mode Encrypt
    [pscustomobject]@{phase=$phase;status='Passed';detail="$($success.Count) committed; file lock and read-only file kept intact."} | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -Append

    $phase = 'retry'
    $beforeRetry = Get-SyntheticHashes
    $run = Invoke-SyntheticController -Phase $phase -Execute -RetryLog $encryptLog
    $rows = @(Import-Csv -LiteralPath (Join-Path $run 'results.csv'))
    Assert-Controller ($rows.Count -eq 2 -and @($rows | Where-Object { $_.path -notin @($lockedFile,$readOnlyFile) }).Count -eq 0) 'Retry selected unexpected files.'
    Assert-CommitRows -RunDirectory $run -Rows $rows -Before $beforeRetry -Mode Encrypt
    foreach($row in $success) {
        Assert-Controller ((Get-Sha $row.path) -eq $beforeRetry[$row.path]) ('Retry changed prior success: '+$row.path)
    }
    [pscustomobject]@{phase=$phase;status='Passed';detail='Retried only the two failed files; prior successes unchanged.'} | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -Append

    $phase = 'decrypt'
    $encrypted = Get-SyntheticHashes
    $run = Invoke-SyntheticController -Phase $phase -Mode Decrypt -Execute
    $rows = @(Import-Csv -LiteralPath (Join-Path $run 'results.csv'))
    Assert-Controller ($rows.Count -eq $original.Count) 'Missing decryption results.'
    Assert-CommitRows -RunDirectory $run -Rows $rows -Before $encrypted -Mode Decrypt
    [pscustomobject]@{phase=$phase;status='Passed';detail="$($rows.Count) Excel decryption and commit results verified."} | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -Append
    Write-Host "PASS: Windows controller roundtrip. Evidence: $reportPath"
} catch {
    [pscustomobject]@{phase=$phase;status='Failed';detail=$_.Exception.Message} | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -Append
    throw
}
