#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [Parameter(Mandatory=$true)][string]$BaselineRuntime,
    [string]$RuntimeDirectory,
    [switch]$SmallOnly,
    [ValidateSet(1,5)][int]$FileCount=1
)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
if(-not $RuntimeDirectory) { $RuntimeDirectory=Join-Path $toolRoot 'runtime' }
$BaselineRuntime=[IO.Path]::GetFullPath($BaselineRuntime)
$RuntimeDirectory=[IO.Path]::GetFullPath($RuntimeDirectory)
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Close Excel normally and finish other Excel tests before this benchmark.' }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
foreach($directory in @($BaselineRuntime,$RuntimeDirectory)) {
    foreach($name in @('Common.ps1','Engine.ps1','BatchEngine.ps1','ExcelPassword.Worker.ps1')) {
        if(-not [IO.File]::Exists((Join-Path $directory $name))) { throw ('Runtime file missing: '+$name) }
    }
}
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
Set-PrivateDirectory $EvidenceDirectory
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$checks=New-Object 'System.Collections.Generic.List[object]'
$measurements=New-Object 'System.Collections.Generic.List[object]'
$runtimeRecords=New-Object 'System.Collections.Generic.List[object]'
$plainHash=''; $encryptedHashes=@(); $plainBytes=0; $encryptedBytes=@()
function Assert-Benchmark($Condition,[string]$Name) {
    $checks.Add(@{name=$Name;passed=[bool]$Condition})
    if(-not $Condition) { throw ('Benchmark validation failed: '+$Name) }
}
function Protect-Benchmark([string]$Text) {
    if(-not $Text) { return '' }
    $secure=ConvertTo-SecureString $Text -AsPlainText -Force
    try { ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
}
function Copy-WorkingFile([string]$Source,[string]$Destination,[bool]$Overwrite=$false) {
    [IO.File]::Copy($Source,$Destination,$Overwrite)
    [IO.File]::SetAttributes($Destination,[IO.FileAttributes]::Normal)
}
function Get-PackagePartHashes([string]$Path) {
    $hashes=@{}; $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach($entry in $zip.Entries) {
            $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
            try { $hashes[$entry.FullName]=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
            finally { $sha.Dispose(); $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    return $hashes
}
function New-LargeFixture([string]$Path) {
    # Change only sheet1.xml. Preserve its non-data nodes (including drawing)
    # and every other package part. Numeric, cached-formula and Unicode-string
    # cells exercise the signature path without any Excel generation step.
    $zip=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry=$zip.GetEntry('xl/worksheets/sheet1.xml')
        $xml=New-Object Xml.XmlDocument; $xml.PreserveWhitespace=$true; $xml.XmlResolver=$null
        $stream=$entry.Open()
        try { $xml.Load($stream) } finally { $stream.Dispose() }
        $entry.Delete()
        $entry=$zip.CreateEntry('xl/worksheets/sheet1.xml',[IO.Compression.CompressionLevel]::Optimal)
        $settings=New-Object Xml.XmlWriterSettings; $settings.Encoding=New-Object Text.UTF8Encoding($false); $settings.CloseOutput=$true
        $writer=[Xml.XmlWriter]::Create($entry.Open(),$settings)
        try {
            $ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
            $writer.WriteStartDocument(); $writer.WriteStartElement('worksheet',$ns)
            foreach($attribute in $xml.DocumentElement.Attributes) { $attribute.WriteTo($writer) }
            $columns=@(1..40 | ForEach-Object { if($_ -le 26){[string][char](64+$_)}else{'A'+[char](64+$_-26)} })
            $label=([string][char]0xD55C)+[char]0xAE00
            foreach($node in $xml.DocumentElement.ChildNodes) {
                if($node.LocalName -eq 'dimension') { $node.SetAttribute('ref','A1:AN10000'); $node.WriteTo($writer); continue }
                if($node.LocalName -ne 'sheetData') { $node.WriteTo($writer); continue }
                $writer.WriteStartElement('sheetData',$ns)
                for($row=1;$row -le 10000;$row++) {
                    $writer.WriteStartElement('row',$ns); $writer.WriteAttributeString('r',[string]$row)
                    for($column=1;$column -le 40;$column++) {
                        $writer.WriteStartElement('c',$ns); $writer.WriteAttributeString('r',($columns[$column-1]+$row))
                        if($column -eq 1) {
                            $writer.WriteAttributeString('t','inlineStr'); $writer.WriteStartElement('is',$ns)
                            $writer.WriteElementString('t',$ns,('sample-'+$label+'-'+$row)); $writer.WriteEndElement()
                        } elseif($column -eq 40) {
                            $writer.WriteElementString('f',$ns,('SUM(B'+$row+':AM'+$row+')'))
                            $writer.WriteElementString('v',$ns,([string](3800*$row+779)))
                        } else { $writer.WriteElementString('v',$ns,([string](100*$row+$column))) }
                        $writer.WriteEndElement()
                    }
                    $writer.WriteEndElement()
                }
                $writer.WriteEndElement()
            }
            $writer.WriteEndElement(); $writer.WriteEndDocument()
        } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
}
function Run-Operation([string]$Label,[string]$Runtime,[string]$WorkingDirectory,[string[]]$Files,[string]$Mode,[string]$Old,[string]$New) {
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Unexpected Excel process; benchmark stopped without closing it.' }
    $run=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run); Set-PrivateDirectory $run
    $hashes=@{}; $inputHashes=@(); $inputBytes=0L
    foreach($file in $Files) { $hashes[$file]=Get-Sha $file; $inputHashes+=@($hashes[$file]); $inputBytes+=(Get-Item -LiteralPath $file).Length }
    $request=Join-Path $run 'request.json'
    if($FileCount -eq 1) {
        Write-Json @{schemaVersion=1;path=$Files[0];mode=$Mode;expectedHash=$hashes[$Files[0]];oldSecret=(Protect-Benchmark $Old);newSecret=(Protect-Benchmark $New)} $request
        $script=Join-Path $Runtime 'Engine.ps1'
    } else {
        $owner=[Diagnostics.Process]::GetCurrentProcess()
        try { $ownerStart=$owner.StartTime.ToUniversalTime().Ticks.ToString() } finally { $owner.Dispose() }
        Write-Json @{schemaVersion=1;root=$WorkingDirectory;mode=$Mode;files=@($Files | ForEach-Object { @{path=$_;expectedHash=$hashes[$_]} });oldSecret=(Protect-Benchmark $Old);newSecret=(Protect-Benchmark $New);ownerPid=$PID;ownerStartTicks=$ownerStart} $request
        $script=Join-Path $Runtime 'BatchEngine.ps1'
    }
    $arguments='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -RequestPath "'+$request+'"'
    $measurement=[ordered]@{runtime=$Label;mode=$Mode;fileCount=$Files.Count;inputBytes=$inputBytes;inputSha256=$inputHashes;totalMilliseconds=0;status='NotCompleted';exitCode=$null;runDirectory=$run}
    $measurements.Add($measurement)
    $watch=[Diagnostics.Stopwatch]::StartNew(); $process=$null
    try {
        $process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $run 'controller.stdout.log') -RedirectStandardError (Join-Path $run 'controller.stderr.log')
        [void]$process.Handle
        while(-not $process.WaitForExit(250)) {
            if($watch.Elapsed.TotalSeconds -gt ($FileCount*600+120)) {
                [IO.File]::WriteAllText((Join-Path $run 'cancel'),'cancel')
                throw 'Benchmark controller timed out; cancellation requested, preserve evidence and inspect processes normally.'
            }
        }
        $measurement.exitCode=$process.ExitCode
    } finally { $watch.Stop(); $measurement.totalMilliseconds=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); if($null -ne $process) { $process.Dispose() } }
    $result=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $measurement.status=[string]$result.status
    Assert-Benchmark ($measurement.exitCode -eq 0 -and $result.status -eq 'Success') ($Label+' '+$Mode+' success')
    $records=@($result)
    if($FileCount -gt 1) {
        Assert-Benchmark ($result.succeededCount -eq $Files.Count -and @($result.items).Count -eq $Files.Count -and -not $result.reportPath) ($Label+' '+$Mode+' all batch files succeeded')
        $records=@($result.items | ForEach-Object { Get-Content -LiteralPath (Join-Path $_.runDirectory 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json })
    }
    foreach($record in $records) {
        Assert-Benchmark ($hashes.ContainsKey([string]$record.path) -and (Get-Sha $record.backup) -eq $hashes[[string]$record.path]) ($Label+' '+$Mode+' byte-identical original backup')
        Assert-Benchmark ((Get-Sha $record.path) -eq $record.resultHash) ($Label+' '+$Mode+' committed result hash')
        $clean=$true
        foreach($field in @('temp','inputCopy','recovery')) { if($record.$field -and [IO.File]::Exists([string]$record.$field)) { $clean=$false } }
        $attempt=[IO.Path]::GetDirectoryName([string]$record.backup)
        foreach($name in @('request.json','worker-job.json')) { if([IO.File]::Exists((Join-Path $attempt $name))) { $clean=$false } }
        Assert-Benchmark $clean ($Label+' '+$Mode+' owned intermediates and secret IPC removed')
    }
    Assert-Benchmark (-not [IO.File]::Exists($request) -and @(Get-ChildItem -LiteralPath $WorkingDirectory -File -Filter '.eps-*').Count -eq 0) ($Label+' '+$Mode+' no working leftovers')
    Assert-Benchmark (@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count -eq 0) ($Label+' '+$Mode+' Excel exited')
    Assert-Benchmark ((Get-Sha $plainFixture) -eq $plainHash) 'immutable plaintext fixture unchanged'
    Write-Json $measurements.ToArray() (Join-Path $EvidenceDirectory 'timings.json')
    Write-Output ($Label+' '+$Mode+': '+$measurement.totalMilliseconds+' ms, '+$result.status)
}
try {
    $fixture=Join-Path $toolRoot 'upstream/1.1.0/ExcelPasswordSafe/tests/fixtures/picture_ooxml.xlsx'
    $plainFixture=Join-Path $EvidenceDirectory 'plaintext-fixture.xlsx'
    [IO.File]::Copy($fixture,$plainFixture)
    if(-not $SmallOnly) { New-LargeFixture $plainFixture }
    $originalParts=Get-PackagePartHashes $fixture; $generatedParts=Get-PackagePartHashes $plainFixture
    $partsMatch=$originalParts.Count -eq $generatedParts.Count
    foreach($name in $originalParts.Keys) { if($name -ne 'xl/worksheets/sheet1.xml' -and $originalParts[$name] -cne $generatedParts[$name]) { $partsMatch=$false } }
    Assert-Benchmark $partsMatch 'all non-sheet package parts preserved'
    $plainHash=Get-Sha $plainFixture; $plainBytes=(Get-Item -LiteralPath $plainFixture).Length
    [IO.File]::SetAttributes($plainFixture,[IO.FileAttributes]::ReadOnly)
    $frozenEncrypted=Join-Path $EvidenceDirectory 'encrypted-fixtures'; [void][IO.Directory]::CreateDirectory($frozenEncrypted)
    foreach($pair in @(@('baseline',$BaselineRuntime),@('current',$RuntimeDirectory))) {
        $label=$pair[0]; $sourceRuntime=$pair[1]
        $runtime=Join-Path $EvidenceDirectory ($label+'-runtime'); [void][IO.Directory]::CreateDirectory($runtime)
        $hashes=@{}
        foreach($file in Get-ChildItem -LiteralPath $sourceRuntime -File | Where-Object { $_.Extension -in @('.ps1','.dll') }) { [IO.File]::Copy($file.FullName,(Join-Path $runtime $file.Name)); $hashes[$file.Name]=Get-Sha (Join-Path $runtime $file.Name) }
        $runtimeRecords.Add(@{label=$label;source=$sourceRuntime;files=$hashes})
    }
    # Freeze both runtime snapshots before any Excel operation. A single run is
    # baseline-first, not a statistical speed guarantee; no threshold is asserted.
    foreach($label in @('baseline','current')) {
        $runtime=Join-Path $EvidenceDirectory ($label+'-runtime')
        $working=Join-Path $EvidenceDirectory ($label+'-files'); [void][IO.Directory]::CreateDirectory($working)
        $files=@(1..$FileCount | ForEach-Object { $path=Join-Path $working ('sample-'+$_+'.xlsx'); Copy-WorkingFile $plainFixture $path; $path })
        Assert-Benchmark (@($files | Where-Object { (Get-Sha $_) -ne $plainHash }).Count -eq 0) ($label+' Encrypt identical starting bytes')
        Run-Operation $label $runtime $working $files 'Encrypt' '' 'Perf-A42!'
        for($index=0;$index -lt $FileCount;$index++) {
            $frozen=Join-Path $frozenEncrypted ('sample-'+($index+1)+'.xlsx')
            if($label -eq 'baseline') {
                [IO.File]::Copy($files[$index],$frozen)
                $encryptedHashes+=@(Get-Sha $frozen); $encryptedBytes+=@((Get-Item -LiteralPath $frozen).Length)
                [IO.File]::SetAttributes($frozen,[IO.FileAttributes]::ReadOnly)
            } else { Copy-WorkingFile $frozen $files[$index] $true }
            Assert-Benchmark ((Get-Sha $files[$index]) -eq $encryptedHashes[$index]) ($label+' Decrypt identical starting bytes')
        }
        Run-Operation $label $runtime $working $files 'Decrypt' 'Perf-A42!' ''
    }
    for($index=0;$index -lt $FileCount;$index++) { Assert-Benchmark ((Get-Sha (Join-Path $frozenEncrypted ('sample-'+($index+1)+'.xlsx'))) -eq $encryptedHashes[$index]) 'immutable encrypted fixture unchanged' }
    Write-Json @{status='PASS';fixture=$(if($SmallOnly){'small existing image fixture'}else{'10000 rows x 40 columns; 400000 cells'});plaintextSha256=$plainHash;plaintextBytes=$plainBytes;encryptedSha256=$encryptedHashes;encryptedBytes=$encryptedBytes;fileCount=$FileCount;runtimes=$runtimeRecords.ToArray();measurements=$measurements.ToArray();checks=$checks.ToArray();timingScope='controller start through exit; fixture generation and harness validation excluded';order='baseline Encrypt, baseline Decrypt, current Encrypt, current Decrypt';limitation='One sequential observation per mode/runtime; no speed threshold or general performance guarantee.'} (Join-Path $EvidenceDirectory 'performance-results.json')
    Write-Output ('PASS: benchmark validation; '+$EvidenceDirectory)
} catch {
    Write-Json @{status='FAIL';category='BenchmarkFailed';plaintextSha256=$plainHash;encryptedSha256=$encryptedHashes;fileCount=$FileCount;runtimes=$runtimeRecords.ToArray();measurements=$measurements.ToArray();checks=$checks.ToArray()} (Join-Path $EvidenceDirectory 'performance-results.json')
    throw
}
