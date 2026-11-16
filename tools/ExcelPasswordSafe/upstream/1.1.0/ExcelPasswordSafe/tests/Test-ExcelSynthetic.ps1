#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [switch]$Run
)

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common.ps1')
. (Join-Path $PSScriptRoot 'Get-ExcelTestEnvironment.ps1')

if($env:OS -ne 'Windows_NT') { throw 'Windows desktop Excel is required.' }
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Start Windows PowerShell with -STA.' }
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Close Excel normally first.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
Assert-NoReparse (Split-Path -Parent $EvidenceDirectory)
Write-Host "Synthetic fixtures and test output: $EvidenceDirectory"
if(-not $Run -and (Read-Host 'Type SYNTHETIC to start the test') -cne 'SYNTHETIC') { exit 2 }
New-Item -ItemType Directory -Path $EvidenceDirectory | Out-Null

$testsRoot=$PSScriptRoot
$packageRoot=Split-Path -Parent $PSScriptRoot
$fixtureDirectory=Join-Path $testsRoot 'fixtures'
$picture=Join-Path $fixtureDirectory 'synthetic-picture.png'
$resultsPath=Join-Path $EvidenceDirectory 'synthetic-results.csv'
$fixturePath=Join-Path $EvidenceDirectory 'fixture-results.csv'
$shaPath=Join-Path $EvidenceDirectory 'interop-files.csv'
$timeoutSeconds=180
$results=New-Object 'System.Collections.Generic.List[object]'
$fixtures=New-Object 'System.Collections.Generic.List[object]'

function Save-FixtureRecord([string]$Name,[int]$Format,[string]$Case,[string]$Status,[string]$Detail='') {
    [pscustomobject]@{name=$Name;format=$Format;case=$Case;status=$Status;detail=$Detail} |
        Export-Csv -LiteralPath $fixturePath -Append -NoTypeInformation -Encoding UTF8
}

function Wait-ExcelExit {
    for($i=0;$i -lt 20 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count;$i++) {
        Start-Sleep -Milliseconds 500
    }
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) {
        throw 'Excel remains running. Inspect and close it normally before resuming.'
    }
}

function New-PictureFixture($Books,[int]$Format,[string]$Path) {
    $book=$null; $sheets=$null; $sheet=$null; $cell=$null
    $shapes=$null; $shape=$null; $ole=$null; $embedded=$null
    try {
        $book=$Books.Add()
        $sheets=$book.Worksheets
        $sheet=$sheets.Item(1)
        $sheet.Name='한글_그림'
        $cell=$sheet.Range('A1'); $cell.Value2='Synthetic picture fixture'; Release-Com $cell; $cell=$null
        $cell=$sheet.Range('A2'); $cell.Value2=42; Release-Com $cell; $cell=$null
        $cell=$sheet.Range('B2'); $cell.Formula='=A2*2'; Release-Com $cell; $cell=$null
        $shapes=$sheet.Shapes
        $shape=$shapes.AddPicture($picture,0,-1,20,80,64,40)
        $shape.Name='TestPicture'; Release-Com $shape; $shape=$null
        $shape=$shapes.AddShape(1,100,80,80,40)
        $shape.Name='TestRectangle'; Release-Com $shape; $shape=$null
        if($Format -eq 56) {
            try {
                $payload=Join-Path $EvidenceDirectory 'ole-payload.txt'
                [IO.File]::WriteAllText($payload,'ExcelPasswordSafe synthetic embedded file.')
                $ole=$sheet.OLEObjects()
                $embedded=$ole.Add([Type]::Missing,$payload,$false,$true)
                $embedded.Name='TestEmbeddedFile'
                $shape=$shapes.Item('TestEmbeddedFile')
                if([int]$shape.Type -ne 7) { throw 'Fixture is not an embedded OLE shape.' }
                Save-FixtureRecord ([IO.Path]::GetFileName($Path)) $Format 'EmbeddedOle' 'Created'
            } catch {
                Save-FixtureRecord ([IO.Path]::GetFileName($Path)) $Format 'EmbeddedOle' 'NotCovered' $_.Exception.Message
            } finally {
                Release-Com $shape; $shape=$null
                Release-Com $embedded; $embedded=$null
                Release-Com $ole; $ole=$null
            }
        }
        $book.SaveAs($Path,$Format)
        if([int]$book.FileFormat -ne $Format) { throw 'Fixture format after SaveAs differs from requested format.' }
    } finally {
        Release-Com $shape; Release-Com $shapes; Release-Com $cell
        Release-Com $sheet; Release-Com $sheets
        if($null -ne $book) { try { $book.Close($false) } finally { Release-Com $book } }
    }
}

function Get-VbaPayloadHash([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    $stream=$null; $sha=$null
    try {
        $entry=$zip.GetEntry('xl/vbaProject.bin')
        if($null -eq $entry) { throw 'VBA payload missing from XLSM.' }
        $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
        [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')
    } finally {
        if($sha) { $sha.Dispose() }
        if($stream) { $stream.Dispose() }
        $zip.Dispose()
    }
}

$app=$null; $books=$null; $fixtureFailure=$false
try {
    $app=New-Object -ComObject Excel.Application
    $app.Visible=$false; $app.DisplayAlerts=$false; $app.AutomationSecurity=3; $app.EnableEvents=$false
    $identity=Get-ExcelTestEnvironment -ExcelApplication $app -OutputPath (Join-Path $EvidenceDirectory 'environment.json')
    $major=([version]$identity.excel.version).Major
    $books=$app.Workbooks
    foreach($pair in @(@('.xls',56),@('.xlsx',51),@('.xlsm',52),@('.xlsb',50),@('.xlsx',61))) {
        $format=[int]$pair[1]
        $name='fixture-'+$format+$pair[0]
        if($format -eq 61 -and $major -lt 15) {
            Save-FixtureRecord $name $format 'PictureAndShape' 'NotApplicable' 'Strict SaveAs requires Excel 2013 or later.'
            continue
        }
        $path=Join-Path $EvidenceDirectory $name
        try {
            New-PictureFixture $books $format $path
            $fixtures.Add([pscustomobject]@{name=$name;path=$path;format=$format;vba=$false})
            Save-FixtureRecord $name $format 'PictureAndShape' 'Created'
        } catch {
            $fixtureFailure=$true
            Save-FixtureRecord $name $format 'PictureAndShape' 'Failed' $_.Exception.Message
        }
    }
} finally {
    Release-Com $books
    if($null -ne $app) { try { $app.Quit() } finally { Release-Com $app } }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
Wait-ExcelExit

foreach($sample in @(@('picture_biff8.xls',56,$false),@('picture_vba.xlsm',52,$true))) {
    $path=Join-Path $EvidenceDirectory $sample[0]
    [IO.File]::Copy((Join-Path $fixtureDirectory $sample[0]),$path)
    $fixtures.Add([pscustomobject]@{name=$sample[0];path=$path;format=$sample[1];vba=$sample[2]})
    Save-FixtureRecord $sample[0] $sample[1] 'BundledSample' 'Copied'
}
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'excel-password-safe.synthetic'),'ExcelPasswordSafe synthetic fixtures')

$plainSecret=ConvertTo-SecureString 'EpsTest-42!' -AsPlainText -Force
$wrongSecret=ConvertTo-SecureString 'EpsWrong-91!' -AsPlainText -Force
try {
    $cipher=ConvertFrom-SecureString $plainSecret
    $wrongCipher=ConvertFrom-SecureString $wrongSecret
} finally {
    $plainSecret.Dispose(); $wrongSecret.Dispose()
}

$workerFailure=$false
foreach($fixture in $fixtures) {
    $stem=[IO.Path]::GetFileNameWithoutExtension($fixture.name)
    $ext=[IO.Path]::GetExtension($fixture.name)
    $encrypted=Join-Path $EvidenceDirectory ($stem+'-encrypted'+$ext)
    $decrypted=Join-Path $EvidenceDirectory ($stem+'-decrypted'+$ext)
    $cases=@(
        @{name='Encrypt';mode='Encrypt';input=$fixture.path;output=$encrypted;old='';status='Validated';category='Validated'},
        @{name='EncryptAlready';mode='Encrypt';input=$encrypted;output=$null;old=$cipher;status='Skipped';category='AlreadyEncrypted'},
        @{name='DecryptWrong';mode='Decrypt';input=$encrypted;output=$null;old=$wrongCipher;status='Failed';category='OpenFailedPossiblePasswordOrCorruption'},
        @{name='Decrypt';mode='Decrypt';input=$encrypted;output=$decrypted;old=$cipher;status='Validated';category='Validated'},
        @{name='DecryptAlready';mode='Decrypt';input=$decrypted;output=$null;old='';status='Skipped';category='AlreadyUnencrypted'}
    )
    foreach($case in $cases) {
        Wait-ExcelExit
        $id=[guid]::NewGuid().ToString('N').Substring(0,12)
        $job=Join-Path $EvidenceDirectory ($id+'.job.json')
        $report=Join-Path $EvidenceDirectory ($id+'.result.json')
        $temp=if($case.output) { $case.output } else { Join-Path $EvidenceDirectory ($id+$ext) }
        $inputHash=Get-Sha $case.input
        Write-Json @{mode=$case.mode;input=$case.input;backup=$case.input;temp=$temp;result=$report;oldSecret=$case.old;newSecret=$(if($case.mode -eq 'Encrypt'){$cipher}else{''})} $job
        $record=[ordered]@{fixture=$fixture.name;format=$fixture.format;case=$case.name;passed=$false;status='Failed';category='WorkerFailed';hresults='';detail=''}
        $timedOut=$false
        try {
            $script=Join-Path $packageRoot 'ExcelPassword.Worker.ps1'
            $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$script+'" -JobPath "'+$job+'"'
            $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru
            try {
                if(-not $p.WaitForExit($timeoutSeconds*1000)) {
                    $timedOut=$true
                    $record.category='WorkerTimeout'
                    $p.Kill()
                    $p.WaitForExit()
                    throw 'Test PowerShell worker timed out. Excel may still be running.'
                }
            } finally { $p.Dispose() }
            $r=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
            $record.status=$r.status; $record.category=$r.category; $record.hresults=$r.hresults; $record.detail=$r.message
            $record.passed=$r.status -eq $case.status -and $r.category -eq $case.category -and (Get-Sha $case.input) -eq $inputHash
            if($record.passed -and $case.output) { $record.passed=(Get-Sha $temp) -eq $r.tempHash }
            if($record.passed -and -not $case.output) { $record.passed=-not (Test-Path -LiteralPath $temp) }
            if($record.passed -and $fixture.vba -and $case.name -eq 'Decrypt') {
                $before=Get-VbaPayloadHash $fixture.path
                $after=Get-VbaPayloadHash $decrypted
                $record.detail="VBA payload present after decrypt. Byte hash unchanged: $($before -eq $after). Before=$before After=$after"
            }
            if($record.passed -and $case.name -eq 'Encrypt') {
                [pscustomobject]@{name=[IO.Path]::GetFileName($encrypted);format=$fixture.format;sha256=$r.tempHash;producerVersion=$identity.excel.fileVersion;producerArchitecture=$identity.excel.architecture} |
                    Export-Csv -LiteralPath $shaPath -Append -NoTypeInformation -Encoding UTF8
            }
        } catch {
            $record.passed=$false
            $record.detail=$_.Exception.Message
        } finally {
            Remove-Item -LiteralPath $job -Force -ErrorAction SilentlyContinue
            $results.Add([pscustomobject]$record)
            [pscustomobject]$record | Export-Csv -LiteralPath $resultsPath -Append -NoTypeInformation -Encoding UTF8
            Write-Host "$($fixture.name) / $($case.name) / $($record.category) / passed=$($record.passed)"
        }
        if($timedOut) { throw 'Synthetic suite stopped after worker timeout.' }
        if(-not $record.passed) {
            $workerFailure=$true
            break
        }
    }
}
Wait-ExcelExit
if($fixtureFailure -or $workerFailure) { throw "Synthetic fixture/worker failures. See $fixturePath and $resultsPath." }
Write-Host "PASS: $($results.Count) real Excel worker cases."
& (Join-Path $PSScriptRoot 'Test-ExcelController.ps1') -EvidenceDirectory (Join-Path $EvidenceDirectory 'controller') -FixtureDirectory $EvidenceDirectory
exit 0
