# Windows PowerShell 5.1. Installed-product API checks and a separate native-UI fixture.
[CmdletBinding()]
param(
    [ValidateSet('Functional','NormalStart','NoAddin','UiFixture')][string]$Mode='Functional',
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][string]$InstalledAddinPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$ExpectedReleaseVersion='0.2.0-rc.10',
    [string]$GuardInstallerPath='',
    [ValidatePattern('^$|^[0-9a-fA-F]{64}$')][string]$ExpectedInstallerSha256='',
    [string]$GuardUninstallerPath='',
    [switch]$AllowUiDiagnostics,
    [ValidateRange(60,14400)][int]$UiTimeoutSeconds=3600
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifacts=[IO.Path]::GetFullPath((Join-Path $repo 'artifacts'))
$output=[IO.Path]::GetFullPath($OutputDirectory)
$addin=[IO.Path]::GetFullPath($InstalledAddinPath)
if(-not $output.StartsWith(($artifacts.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'OutputDirectory must be below repository artifacts.'}
if(Test-Path -LiteralPath $output){throw 'OutputDirectory must be fresh; previous evidence is preserved.'}
$ancestor=$output
while($ancestor -and $ancestor.Length -ge $artifacts.Length){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Output path must not contain a reparse point.'}
    $ancestor=Split-Path -Parent $ancestor
}
[void][IO.Directory]::CreateDirectory($output)
$utf8=New-Object Text.UTF8Encoding($false)
$audit=[ordered]@{
    schemaVersion=1; mode=$Mode; status='NOT_RUN'; phase='preflight'; startedUtc=[DateTime]::UtcNow.ToString('o'); finishedUtc=$null
    installedAddinPath=$addin; expectedSha256=$ExpectedSha256.ToLowerInvariant(); actualSha256=$null; finalSha256=$null
    expectedReleaseVersion=$ExpectedReleaseVersion; releaseVersion=$null; normalStartup='NOT_RUN'; functional='NOT_RUN'
    nativeInputTests='NOT_RUN'; nativeUi='NOT_RUN'; releaseApproved=$false; owner=$null; tests=@(); fixtures=@(); results=@()
    failure=$null; cleanupErrors=@(); excelExited=$null; securityChanged=$false; uiCompletion=$null
    installerGuards=@(); quitSent=$false; exitConfirmation='NOT_RUN'; warnings=@(); addinLookup=$null
    toolbarLookup=$null; startupWorkbook=$null; uiReady=$null; ribbonReady=$null; uiDiagnosticFailures=@()
    observationContext=$null; rawStatusObservations=@()
}
$script:Excel=$null; $script:ExcelProcess=$null; $script:ExcelVersion=$null; $script:ExcelBootstrap=$null; $script:ExcelSessionBook=$null
$script:owned=New-Object 'System.Collections.Generic.List[object]'
$script:unknown=$false; $script:loaded=$null; $script:q=$null; $script:initialState=$null
$functionsLoaded=$false; $mutex=$null; $locked=$false; $exitCode=1
function Save-Audit {
    [IO.File]::WriteAllText((Join-Path $output 'flow.private.json'),($audit|ConvertTo-Json -Depth 12),$utf8)
}
function Phase([string]$Name){$audit.phase=$Name;Save-Audit}
function Check([bool]$Passed,[string]$Name,$Detail=$null){
    $audit.tests+=@([ordered]@{name=$Name;status=$(if($Passed){'PASS'}else{'FAIL'});detail=$Detail})
    Save-Audit
    if(-not $Passed){throw ('Check failed: '+$Name)}
}
function Check-Toolbar([bool]$Passed,[string]$Name,$Detail=$null){
    if(-not $Passed -and $Mode -eq 'UiFixture' -and $AllowUiDiagnostics){
        $audit.tests+=@([ordered]@{name=$Name;status='FAIL';detail=$Detail})
        $audit.uiDiagnosticFailures+=@($Name)
        Save-Audit
        return
    }
    Check $Passed $Name $Detail
}
function Hash-File([string]$Path){
    $s=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash($s))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose();$s.Dispose()}
}
function Guard-FileState {
    $state=[ordered]@{}
    foreach($path in @($addin,$GuardInstallerPath,$GuardUninstallerPath)){$state[$path]=Hash-File $path}
    return $state
}
function Read-GuardLog([string]$Path){
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=New-Object IO.StreamReader($stream,$true)
    try{return $reader.ReadToEnd()}finally{$reader.Dispose();$stream.Dispose()}
}
function Invoke-OpenExcelGuard([string]$Action,[string]$Exe,[string]$PinnedHash){
    Assert-KnownBooks
    if((Hash-File $Exe) -cne $PinnedHash){throw ('Guard executable changed before launch: '+$Action)}
    $before=Guard-FileState
    $log=Join-Path $output ('open-excel-'+$Action.ToLowerInvariant()+'.inno.private.log')
    $record=[ordered]@{action=$Action;executable=$Exe;sha256=$PinnedHash;status='STARTED';mutexReleased=$false;processId=$null;exitCode=$null;engineExitCodes=@();ownedExcelAlive=$false;filesUnchanged=$false;before=$before;after=$null;log=$log;failure=$null}
    $audit.installerGuards+=@($record)
    $child=$null;$finished=$false;$logClosed=$false
    Phase ('open-excel-guard-'+$Action.ToLowerInvariant())
    try{
        # Do not let the harness mutex cause code 4 and mask the Excel-open guard.
        if(-not $script:locked){throw 'Product mutex is not held before guard test.'}
        $mutex.ReleaseMutex();$script:locked=$false;$record.mutexReleased=$true;Save-Audit
        $child=Start-Process -FilePath $Exe -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG="'+$log+'"')) -WindowStyle Hidden -PassThru
        $record.processId=$child.Id;$null=$child.Handle;Save-Audit
        $finished=$child.WaitForExit(30000)
        if(-not $finished){$script:unknown=$true;throw 'Installer guard process did not exit; preserve Excel and do not kill any process.'}
        $record.exitCode=$child.ExitCode
        # The registered remover can delegate to its temporary copy. Require its
        # completed engine log, not merely termination of the initial launcher.
        $timer=[Diagnostics.Stopwatch]::StartNew();$logText=''
        do{
            $logText=Read-GuardLog $log
            $logClosed=$logText -match 'Log closed\.'
            if(-not $logClosed){Start-Sleep -Milliseconds 200}
        }while(-not $logClosed -and $timer.Elapsed.TotalSeconds -lt 15)
        if(-not $logClosed){$script:unknown=$true;throw 'Installer log did not close; preserve Excel until the installer is inspected.'}
        $record.engineExitCodes=@([regex]::Matches($logText,'SLC_ENGINE_EXIT_CODE=(-?\d+)')|ForEach-Object{[int]$_.Groups[1].Value})
        Assert-Owner;$record.ownedExcelAlive=$true
        $record.after=Guard-FileState
        $record.filesUnchanged=($before|ConvertTo-Json -Compress) -ceq ($record.after|ConvertTo-Json -Compress)
        $passed=$record.exitCode -ne 0 -and $record.engineExitCodes.Count -eq 1 -and $record.engineExitCodes[0] -eq 3 -and $logText.Contains('SLC_ENGINE_ACTION='+$Action) -and $record.ownedExcelAlive -and $record.filesUnchanged
        $record.status=if($passed){'PASS'}else{'FAIL'}
        Check $passed ('Open Excel refuses '+$Action+' with engine code 3 and preserves files/process') $record
    }catch{
        $record.status='FAIL';$record.failure=$_.Exception.Message
        # Evidence collection never retries the installer or repairs its output.
        try{$record.after=Guard-FileState;$record.filesUnchanged=($before|ConvertTo-Json -Compress) -ceq ($record.after|ConvertTo-Json -Compress)}catch{}
        try{Assert-Owner;$record.ownedExcelAlive=$true}catch{}
        throw
    }finally{
        if($null -ne $child){$child.Dispose()}
        if($record.mutexReleased -and ($null -eq $record.processId -or ($finished -and $logClosed))){
            try{$script:locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$script:locked=$true}
            if(-not $script:locked){$script:unknown=$true;$audit.cleanupErrors+=@('Product mutex could not be reacquired after guard; session preserved.')}
        }
        Save-Audit
    }
    if(-not $script:locked){throw 'Product mutex unavailable after installer guard.'}
}
function Assert-Owner {
    if($null -eq $script:ExcelProcess -or $script:ExcelProcess.HasExited){throw 'Owned Excel has exited.'}
    if($script:ExcelProcess.StartTime.ToUniversalTime().Ticks.ToString() -cne $audit.owner.startTimeUtcTicksText){throw 'Owned process identity changed.'}
    [uint32]$actual=0
    [void][SlcSetupWindowOwner]::GetWindowThreadProcessId([IntPtr]$script:Excel.Hwnd,[ref]$actual)
    if($actual -ne $audit.owner.pid){throw 'Excel HWND no longer belongs to the owned process.'}
}
function Same-Com($A,$B){
    if($null -eq $A -or $null -eq $B){return $false}
    $pa=[IntPtr]::Zero;$pb=[IntPtr]::Zero
    try{$pa=[Runtime.InteropServices.Marshal]::GetIUnknownForObject($A);$pb=[Runtime.InteropServices.Marshal]::GetIUnknownForObject($B);return $pa -eq $pb}
    finally{if($pa -ne [IntPtr]::Zero){[void][Runtime.InteropServices.Marshal]::Release($pa)};if($pb -ne [IntPtr]::Zero){[void][Runtime.InteropServices.Marshal]::Release($pb)}}
}
function Is-Known($Book){
    if(Same-Com $Book $script:loaded){return $true}
    foreach($entry in $script:owned){if(Same-Com $Book $entry.book){return $true}}
    return $false
}
function Find-LoadedBook([string]$Name){
    $books=$script:Excel.Workbooks
    try{
        # Open add-ins are omitted from Workbooks enumeration but are available
        # through Item(filename). This only observes; never Open or AttachUI.
        # https://learn.microsoft.com/office/vba/api/excel.application.workbooks
        try{
            $candidate=$books.Item($Name)
            $audit.addinLookup=[ordered]@{method='Workbooks.Item(filename)';name=$Name;status='FOUND';errorHresult=$null;errorType=$null}
            return ,$candidate
        }catch{
            $cause=$_.Exception
            while($null -ne $cause.InnerException){$cause=$cause.InnerException}
            $code=('{0:X8}' -f ($cause.HResult -band 0xffffffffL))
            $audit.addinLookup=[ordered]@{method='Workbooks.Item(filename)';name=$Name;status='LOOKUP_FAILED';errorHresult=$code;errorType=$cause.GetType().FullName}
            # Excel can report an absent named workbook as bad index or 1004.
            # Other failures (busy/disconnected COM, etc.) must not prove absence.
            $missing=$code -in @('8002000B','800A03EC')
            $cause=$null
            $Error.Clear()
            if(-not $missing){throw ('Named add-in lookup failed with HRESULT 0x'+$code+'; absence was not established.')}
            $audit.addinLookup.status='MISSING'
            return $null
        }
    }finally{Release-Com $books}
}
function Get-ToolbarProbeHResult($ErrorRecord){
    $cause=$ErrorRecord.Exception
    while($null -ne $cause.InnerException){$cause=$cause.InnerException}
    return ('{0:X8}' -f ($cause.HResult -band 0xffffffffL))
}
function Read-ToolbarNames($Bars){
    $names=New-Object 'System.Collections.Generic.List[string]'
    $count=[int]$Bars.Count
    for($i=1;$i -le $count;$i++){
        $item=$null
        try{$item=$Bars.Item($i);$names.Add([string]$item.Name)}finally{Release-Com $item}
    }
    if([int]$Bars.Count -ne $count){throw 'Toolbar collection count changed during enumeration.'}
    return ,($names.ToArray())
}
function Test-ToolbarAbsenceControls($Bars,[string]$TargetName,[string]$TargetHResult){
    $e=[ordered]@{status='LOOKUP_FAILED';absenceEstablished=$false;targetName=$TargetName;targetHResult=$TargetHResult;enumerationCompleted=$false;enumerationCount=$null;targetMatches=$null;positiveName=$null;positiveStatus='NOT_RUN';positiveHResult=$null;negativeName=$null;negativeStatus='NOT_RUN';negativeHResult=$null;stableEnumeration=$false;failure=$null}
    # E_INVALIDARG is not an absence contract. Corroborate only this uncertain
    # HRESULT with same-collection controls; other failures remain errors.
    if($TargetHResult -cne '80070057'){$e.failure='Target HRESULT is not eligible for this corroboration.';return $e}
    $positive=$null;$negative=$null
    try{
        $before=Read-ToolbarNames $Bars
        $e.enumerationCompleted=$true;$e.enumerationCount=$before.Count
        $e.targetMatches=@($before|Where-Object{[string]::Equals($_,$TargetName,[StringComparison]::OrdinalIgnoreCase)}).Count
        if($e.targetMatches -ne 0){throw 'Target exists in numeric enumeration; named failure cannot prove absence.'}
        $eligible=@($before|Where-Object{-not [string]::IsNullOrEmpty($_)})
        if($eligible.Count -eq 0){throw 'No enumerated toolbar is available for a positive control.'}
        $e.positiveName=$eligible[0]
        try{
            $positive=$Bars.Item($e.positiveName)
            if($null -eq $positive -or [string]$positive.Name -cne $e.positiveName){throw 'Positive lookup did not return the enumerated name.'}
            $e.positiveStatus='FOUND'
        }catch{
            $e.positiveStatus='LOOKUP_FAILED';$e.positiveHResult=Get-ToolbarProbeHResult $_
            $Error.Clear();throw 'Positive named control failed.'
        }finally{Release-Com $positive;$positive=$null}
        do{$e.negativeName='SLC_Absent_Control_'+[Guid]::NewGuid().ToString('N')}while($before -contains $e.negativeName)
        try{$negative=$Bars.Item($e.negativeName);$e.negativeStatus='UNEXPECTED_FOUND'}
        catch{$e.negativeStatus='LOOKUP_FAILED';$e.negativeHResult=Get-ToolbarProbeHResult $_;$Error.Clear()}
        finally{Release-Com $negative;$negative=$null}
        if($e.negativeStatus -cne 'LOOKUP_FAILED' -or $e.negativeHResult -cne $TargetHResult){throw 'Negative named control did not reproduce the target HRESULT.'}
        $after=Read-ToolbarNames $Bars
        $e.stableEnumeration=($before|ConvertTo-Json -Compress) -ceq ($after|ConvertTo-Json -Compress)
        if(-not $e.stableEnumeration -or $after -contains $e.negativeName){throw 'Toolbar collection changed while controls were observed.'}
        $e.status='ABSENCE_CORROBORATED';$e.absenceEstablished=$true
    }catch{$e.failure=$_.Exception.Message;$Error.Clear()}
    return $e
}
function Find-Toolbar {
    $bars=$script:Excel.CommandBars
    $audit.toolbarLookup=[ordered]@{status='OBSERVING';collectionCount=[int]$bars.Count;enumerationCompleted=$false;enumerationMatched=$false;namedLookup='NOT_RUN';matchedName=$null;objectType=$null;isArray=$null;controlsCount=$null;errorHresult=$null;absenceControls=$null}
    try{
        for($i=1;$i -le [int]$bars.Count;$i++){
            $candidate=$bars.Item($i)
            if([string]$candidate.Name -ceq 'SLC_68A45C44_Toolbar'){$audit.toolbarLookup.enumerationMatched=$true}
            Release-Com $candidate;$candidate=$null
        }
        $audit.toolbarLookup.enumerationCompleted=$true
        # Compare enumeration with a direct name lookup without creating UI.
        try{$candidate=$bars.Item('SLC_68A45C44_Toolbar')}
        catch{
            $cause=$_.Exception;while($null -ne $cause.InnerException){$cause=$cause.InnerException}
            $code=('{0:X8}' -f ($cause.HResult -band 0xffffffffL));$cause=$null
            $audit.toolbarLookup.errorHresult=$code;$Error.Clear()
            if($code -ceq '80070057'){
                $audit.toolbarLookup.absenceControls=Test-ToolbarAbsenceControls $bars 'SLC_68A45C44_Toolbar' $code
                if(-not $audit.toolbarLookup.enumerationMatched -and $audit.toolbarLookup.absenceControls.absenceEstablished){
                    $audit.toolbarLookup.status='MISSING_CORROBORATED';$audit.toolbarLookup.namedLookup='E_INVALIDARG_CORROBORATED';return $null
                }
            }
            if($code -notin @('8002000B','800A03EC')){$audit.toolbarLookup.status='LOOKUP_FAILED';$audit.toolbarLookup.namedLookup='LOOKUP_FAILED';throw ('Named toolbar lookup failed with HRESULT 0x'+$code+'; absence was not established.')}
            $audit.toolbarLookup.status='MISSING';$audit.toolbarLookup.namedLookup='MISSING';return $null
        }
        $audit.toolbarLookup.status='FOUND';$audit.toolbarLookup.namedLookup='FOUND'
        $audit.toolbarLookup.matchedName=[string]$candidate.Name
        $audit.toolbarLookup.objectType=$candidate.GetType().FullName
        $audit.toolbarLookup.isArray=$candidate -is [Array]
        $controls=$null
        try{$controls=$candidate.Controls;$audit.toolbarLookup.controlsCount=[int]$controls.Count}finally{Release-Com $controls}
        return ,$candidate
    }finally{Release-Com $bars}
}
function Assert-KnownBooks {
    Assert-Owner
    $protected=$script:Excel.ProtectedViewWindows
    try{if([int]$protected.Count -ne 0){$script:unknown=$true;throw 'Unexpected Protected View document; preserve the session.'}}finally{Release-Com $protected}
    $books=$script:Excel.Workbooks
    try{
        for($i=1;$i -le [int]$books.Count;$i++){
            $observed=$books.Item($i)
            $known=Is-Known $observed
            if(-not $known){$script:unknown=$true;Release-Com $observed;$observed=$null;throw 'Unexpected workbook; preserve the session and refuse Quit.'}
            # Do not release an RCW alias still held in the ownership list.
            $observed=$null
        }
    }finally{Release-Com $books}
}
function Set-VisibleObservationContext {
    # All menu acceptance modes observe the same visible document context as
    # the native UI check. This does not create or repair any product controls.
    Assert-KnownBooks
    $script:Excel.Visible=$true
    $script:Excel.UserControl=$true
    $audit.observationContext=[ordered]@{mode=$Mode;visible=[bool]$script:Excel.Visible;userControl=[bool]$script:Excel.UserControl;startupWorkbook=[string]$audit.startupWorkbook.name}
    if(-not $audit.observationContext.visible -or -not $audit.observationContext.userControl){throw 'Visible owned-document observation context was not established.'}
}
function Record-RawStatus([string]$Stage){
    $raw=$script:Excel.StatusBar
    $type=if($null -eq $raw){$null}else{$raw.GetType().FullName}
    $audit.rawStatusObservations+=@([ordered]@{stage=$Stage;type=$type;value=$raw})
    Save-Audit
}
function App-State {
    $status=$script:Excel.StatusBar
    return [ordered]@{screenUpdating=[bool]$script:Excel.ScreenUpdating;enableEvents=[bool]$script:Excel.EnableEvents;displayAlerts=[bool]$script:Excel.DisplayAlerts;enableCancelKey=[int]$script:Excel.EnableCancelKey;calculation=[int]$script:Excel.Calculation;statusType=$status.GetType().FullName;statusValue=$status}
}
function Invoke-Product([string]$Name){
    Assert-KnownBooks
    $before=App-State
    Phase ('macro-'+$Name)
    $null=$script:Excel.Run($script:q+$Name)
    $after=App-State
    Check (($before|ConvertTo-Json -Compress) -ceq ($after|ConvertTo-Json -Compress)) ($Name+' restores application settings/status') $after
}
function Current-State{return [string]$script:Excel.Run($script:q+'SLC_CurrentState')}
function Select-Fixture($Book,[string]$Address){
    Assert-KnownBooks
    $Book.Activate();$sheet=$Book.Worksheets.Item(1);$range=$null
    try{$sheet.Activate();$range=$sheet.Range($Address);$range.Select()}finally{Release-Com $range;Release-Com $sheet}
}
function Capture-Result([string]$Macro,[string[]]$ExpectedSheets){
    Invoke-Product $Macro
    $new=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le [int]$script:Excel.Workbooks.Count;$i++){
        $observed=$script:Excel.Workbooks.Item($i)
        if(-not (Is-Known $observed)){$new.Add($observed)}else{$observed=$null}
    }
    if($new.Count -ne 1){$script:unknown=$true;throw 'Expected one new result; unproven workbook ownership is preserved.'}
    $result=$new[0]
    if([string]$result.Path -ne '' -or [bool]$result.IsAddin -or [int]$result.Worksheets.Count -ne $ExpectedSheets.Count){$script:unknown=$true;throw 'New workbook does not match the result contract; preserved.'}
    $names=@();$formulaFree=$true
    for($i=1;$i -le $ExpectedSheets.Count;$i++){
        $sheet=$result.Worksheets.Item($i);$used=$null
        try{$names+=@([string]$sheet.Name);$used=$sheet.UsedRange;if($used.HasFormula -ne $false){$formulaFree=$false}}finally{Release-Com $used;Release-Com $sheet}
    }
    if(($names -join '|') -cne ($ExpectedSheets -join '|')){$script:unknown=$true;throw 'Result sheet names are unexpected; preserved.'}
    $script:owned.Add([pscustomobject]@{book=$result;kind='result';path=$null})
    $audit.results+=@([ordered]@{name=[string]$result.Name;sheets=$names;macro=$Macro;formulaFree=$formulaFree})
    Check $formulaFree ($Macro+' writes text, not formulas')
    Assert-KnownBooks
    return ,$result
}
function Summary-Value($Book,[string]$Label,[int]$Column){
    $sheet=$Book.Worksheets.Item(1);$used=$null;$cell=$null
    try{
        $used=$sheet.UsedRange
        for($r=2;$r -le [int]$used.Rows.Count;$r++){
            $cell=$sheet.Cells.Item($r,1);$text=[string]$cell.Value2;Release-Com $cell;$cell=$null
            if($text -ceq $Label){$cell=$sheet.Cells.Item($r,$Column);return $cell.Value2}
        }
        throw ('Missing summary label: '+$Label)
    }finally{Release-Com $cell;Release-Com $used;Release-Com $sheet}
}
function Assert-Summary($Book,[int]$A,[int]$B,[int]$Matched,[int]$LeftA,[int]$LeftB){
    foreach($item in @(@('비교 대상 항목',2,$A),@('비교 대상 항목',3,$B),@('짝지어진 항목',2,$Matched),@('남은 항목',2,$LeftA),@('남은 항목',3,$LeftB))){
        $actual=Summary-Value $Book $item[0] $item[1]
        Check ([double]$actual -eq [double]$item[2]) ([string]$Book.Name+': '+$item[0]+' column '+$item[1]) $actual
    }
}
function Write-Xlsx([string]$Path,[string]$SheetName,[string]$Rows){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew)
    $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    $parts=[ordered]@{
        '[Content_Types].xml'='<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
        '_rels/.rels'='<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        'xl/workbook.xml'=('<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="'+$SheetName+'" sheetId="1" r:id="rId1"/></sheets></workbook>')
        'xl/_rels/workbook.xml.rels'='<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
        'xl/worksheets/sheet1.xml'=('<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="2" width="30" customWidth="1"/></cols><sheetData>'+$Rows+'</sheetData></worksheet>')
    }
    try{foreach($key in $parts.Keys){$entry=$zip.CreateEntry($key);$writer=New-Object IO.StreamWriter($entry.Open(),$utf8);try{$writer.Write([string]$parts[$key])}finally{$writer.Dispose()}}}finally{$zip.Dispose();$stream.Dispose()}
}
function Text-Cell([string]$Address,[string]$Value){return ('<c r="'+$Address+'" t="inlineStr"><is><t xml:space="preserve">'+[Security.SecurityElement]::Escape($Value)+'</t></is></c>')}
function Create-Fixtures {
    Add-Type -AssemblyName System.IO.Compression
    $suffix=[Guid]::NewGuid().ToString('N').Substring(0,8)
    $first=Join-Path $output ('SLC-UI-A-'+$suffix+'.xlsx');$second=Join-Path $output ('SLC-UI-B-'+$suffix+'.xlsx')
    $a=@('Kim@a.invalid','00123','123.0','dup','dup','','#N/A','=1+1','ＣＡＳＥ')
    $b=@('kim@b.invalid','00123','1.23e2','DUP','dup','','#DIV/0!','=1+1','case')
    for($which=0;$which -lt 2;$which++){
        $values=if($which -eq 0){$a}else{$b};$rows='<row r="1">'+(Text-Cell 'A1' 'Synthetic selection: A2:A10')+(Text-Cell 'B1' 'Difference selection: B2:B4')+'</row>'
        for($i=0;$i -lt $values.Count;$i++){
            $r=$i+2;$cells=''
            if($i -eq 6){$cells='<c r="A'+$r+'" t="e"><v>'+$values[$i]+'</v></c>'}elseif($i -ne 5){$cells=Text-Cell ('A'+$r) $values[$i]}
            if($which -eq 1 -and $i -lt 3){$cells+=Text-Cell ('B'+$r) (@('different','extra','00123')[$i])}
            $rows+='<row r="'+$r+'">'+$cells+'</row>'
        }
        $path=if($which -eq 0){$first}else{$second};Write-Xlsx $path ('Synthetic'+$(if($which -eq 0){'A'}else{'B'})) $rows
        $audit.fixtures+=@([ordered]@{path=$path;sha256=(Hash-File $path);selection='A2:A10';expectedTotal=7;expectedBlank=1;expectedError=1})
    }
}
try{
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Use Windows PowerShell 5.1.'}
    if($Mode -in @('Functional','UiFixture') -and $ExpectedReleaseVersion -cne '0.2.0-rc.10'){throw 'Functional and UiFixture modes require RC10.'}
    if($AllowUiDiagnostics -and $Mode -ne 'UiFixture'){throw 'AllowUiDiagnostics is restricted to UiFixture mode.'}
    $guardRequested=$GuardInstallerPath -ne '' -or $ExpectedInstallerSha256 -ne '' -or $GuardUninstallerPath -ne ''
    if($guardRequested){
        if($Mode -ne 'Functional' -or -not $GuardInstallerPath -or -not $ExpectedInstallerSha256 -or -not $GuardUninstallerPath){throw 'Installer guards require Functional mode and all three guard parameters.'}
        $GuardInstallerPath=[IO.Path]::GetFullPath($GuardInstallerPath);$GuardUninstallerPath=[IO.Path]::GetFullPath($GuardUninstallerPath)
        foreach($guardPath in @($GuardInstallerPath,$GuardUninstallerPath)){
            if([IO.Path]::GetExtension($guardPath) -ine '.exe' -or -not (Test-Path -LiteralPath $guardPath -PathType Leaf)){throw 'Guard paths must identify existing EXE files.'}
            $parent=$guardPath
            while($parent){if((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Guard executable path contains a reparse point.'};$parent=Split-Path -Parent $parent}
        }
        Check ((Hash-File $GuardInstallerPath) -ceq $ExpectedInstallerSha256.ToLowerInvariant()) 'Pinned installer for Excel-open guard'
        $guardUninstallerHash=Hash-File $GuardUninstallerPath
    }
    $mutex=New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-Setup')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Another product operation is running.'}
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){$audit.status='BLOCKED_ENV';throw 'Existing Excel detected. No Excel process or workbook was touched.'}
    if($Mode -ne 'NoAddin'){
        if([IO.Path]::GetExtension($addin) -ine '.xlam' -or -not (Test-Path -LiteralPath $addin -PathType Leaf)){throw 'InstalledAddinPath must identify the installed XLAM.'}
        $audit.actualSha256=Hash-File $addin
        Check ($audit.actualSha256 -ceq $audit.expectedSha256) 'Installed file hash before startup'
    }
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Setup.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Setup helper source has parse errors.'}
    foreach($name in @('Setup-Failure','Release-Com','New-SessionBootstrap','Start-OwnExcel','Stop-OwnExcel')){
        $found=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$false))
        if($found.Count -ne 1){throw ('Missing unique helper '+$name)}
        . ([scriptblock]::Create($found[0].Extent.Text))
    }
    $functionsLoaded=$true
    if($Mode -in @('Functional','UiFixture')){Create-Fixtures}
    Phase 'normal-start'
    Start-OwnExcel -NormalStart
    $audit.owner=[ordered]@{pid=$script:ExcelProcess.Id;startTimeUtcTicksText=$script:ExcelProcess.StartTime.ToUniversalTime().Ticks.ToString();hwnd=[long]$script:Excel.Hwnd}
    $audit.excelVersion=[string]$script:Excel.Version;$audit.excelBuild=[string]$script:Excel.Build
    $script:initialState=App-State
    # Observation only: never open XLAM or call SLC_AttachUI to repair auto-loading.
    Phase 'observe-auto-load'
    $script:loaded=Find-LoadedBook ([IO.Path]::GetFileName($addin))
    Assert-KnownBooks
    # Start-OwnExcel closes its temporary bootstrap. Observe legacy SDI UI in
    # the meaningful user context of an open, macro-free owned document.
    # Creating this document never loads XLAM or calls SLC_AttachUI.
    $contextBooks=$script:Excel.Workbooks
    try{$contextBook=$contextBooks.Add(-4167)}finally{Release-Com $contextBooks}
    $script:owned.Add([pscustomobject]@{book=$contextBook;kind='startup';path=$null})
    $audit.startupWorkbook=[ordered]@{name=[string]$contextBook.Name;kind='startup';savedToDisk=$false}
    $contextBook=$null
    Assert-KnownBooks
    Set-VisibleObservationContext
    if($Mode -eq 'NoAddin'){
        Check ($null -eq $script:loaded) 'Product workbook absent after normal startup'
        $toolbar=Find-Toolbar
        Check ($null -eq $toolbar) 'Product toolbar absent after normal startup'
        Release-Com $toolbar;$toolbar=$null
    }else{
        Check ($null -ne $script:loaded) 'Product automatically loaded after normal startup'
        Check ([IO.Path]::GetFullPath([string]$script:loaded.FullName) -ieq $addin -and [bool]$script:loaded.IsAddin) 'Exact installed add-in automatically loaded'
        $script:q="'"+([string]$script:loaded.Name).Replace("'","''")+"'!"
        $audit.releaseVersion=[string]$script:Excel.Run($script:q+'SLC_ReleaseVersion')
        Check ($audit.releaseVersion -ceq $ExpectedReleaseVersion) 'Loaded release version' $audit.releaseVersion
        $audit.uiReady=[bool]$script:Excel.Run($script:q+'SLC_UiReady')
        $audit.ribbonReady=[bool]$script:Excel.Run($script:q+'SLC_RibbonReady')
        if($ExpectedReleaseVersion -ceq '0.2.0-rc.9'){
            $toolbar=Find-Toolbar
            Check ($null -ne $toolbar) 'RC9 toolbar exists with an owned workbook open' $audit.toolbarLookup
            try{Check ([int]$toolbar.Controls.Count -eq 5) 'RC9 toolbar exposes five controls (API observation)'}finally{Release-Com $toolbar;$toolbar=$null}
        }
        if($ExpectedReleaseVersion -ceq '0.2.0-rc.10'){
            $toolbar=Find-Toolbar
            Check-Toolbar ($null -ne $toolbar) 'RC10 toolbar exists with an owned workbook open' $audit.toolbarLookup
            if($null -ne $toolbar){try{
                Check-Toolbar ([int]$toolbar.Controls.Count -eq 8) 'RC10 toolbar exposes eight controls (API observation)'
                $tags=@();for($i=1;$i -le [int]$toolbar.Controls.Count;$i++){$control=$toolbar.Controls.Item($i);try{$tags+=@([string]$control.Tag)}finally{Release-Com $control}}
                $expectedTags=@('run','pending','preview','cancel','progress','clear','replace','about')|ForEach-Object{'SLC_68A45C44_2026.'+$_}
                Check-Toolbar (($tags -join '|') -ceq ($expectedTags -join '|')) 'RC10 toolbar control identities' $tags
            }finally{Release-Com $toolbar;$toolbar=$null}}
            Add-Type -AssemblyName System.IO.Compression
            $file=[IO.File]::Open($addin,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $zip=New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Read,$false)
            try{$entry=$zip.GetEntry('customUI/customUI14.xml');Check ($null -ne $entry) 'Ribbon XML exists (package observation)';$reader=New-Object IO.StreamReader($entry.Open());try{[xml]$xml=$reader.ReadToEnd()}finally{$reader.Dispose()};Check ($null -ne $xml.DocumentElement) 'Ribbon XML is well formed'}finally{$zip.Dispose();$file.Dispose()}
        }
    }
    Assert-KnownBooks
    $audit.normalStartup=if($audit.uiDiagnosticFailures.Count){'PARTIAL_UI_DIAGNOSTIC'}else{'PASS'}
    if($guardRequested){
        Invoke-OpenExcelGuard 'Install' $GuardInstallerPath $ExpectedInstallerSha256.ToLowerInvariant()
        Invoke-OpenExcelGuard 'Uninstall' $GuardUninstallerPath $guardUninstallerHash
    }
    if($Mode -in @('Functional','UiFixture')){
        foreach($fixture in $audit.fixtures){
            $book=$script:Excel.Workbooks.Open($fixture.path,0,$false)
            if([string]$book.FullName -ine $fixture.path){$script:unknown=$true;throw 'Excel opened an unexpected fixture.'}
            $script:owned.Add([pscustomobject]@{book=$book;kind='fixture';path=$fixture.path});$book=$null
        }
        $fixtureBooks=@($script:owned|Where-Object{$_.kind -eq 'fixture'})
        if($fixtureBooks.Count -ne 2){throw 'Expected exactly two owned fixture workbooks.'}
        $firstBook=$fixtureBooks[0].book;$secondBook=$fixtureBooks[1].book
        Select-Fixture $firstBook 'A2:A10'
        if($Mode -eq 'UiFixture'){
            $token=[Guid]::NewGuid().ToString('N')
            $session=[ordered]@{schemaVersion=1;owner=$audit.owner;token=$token;completionFile=(Join-Path $output 'completion.command.json');startupWorkbook=$audit.startupWorkbook;fixtures=$audit.fixtures;installedAddinPath=$addin;sha256=$audit.actualSha256;nativeUi='NOT_RUN';instructions=@('Use the actual toolbar/context menu to capture A2:A10 in A.','Preview must create three sheets. Close that result without saving.','Select A2:A10 in B and compare: four sheets, seven matched, blank/error exclusions one each.','Close that result. Compare B2:B4 again: first count seven, second three, matched one, remaining six/two.','Close every UI-created result before completion. Leave the owned blank startup workbook and both fixture workbooks open.','Write completion.command.json with the exact token and action complete or preserve. Native UI evidence is recorded separately.')}
            [IO.File]::WriteAllText((Join-Path $output 'ui-session.private.json'),($session|ConvertTo-Json -Depth 10),$utf8)
            Phase 'ui-fixture-ready'
            $timer=[Diagnostics.Stopwatch]::StartNew();$done=$false
            # No COM polling/input while a human/Sky owns UI interaction.
            while(-not $done -and $timer.Elapsed.TotalSeconds -lt $UiTimeoutSeconds){
                if(Test-Path -LiteralPath $session.completionFile){
                    $command=Get-Content -LiteralPath $session.completionFile -Raw -Encoding UTF8|ConvertFrom-Json
                    if([string]$command.token -cne $token -or [string]$command.action -notin @('complete','preserve')){throw 'Invalid UI completion token/action; preserve the session.'}
                    $audit.uiCompletion=[string]$command.action;$done=$true
                    if($command.action -eq 'preserve'){$script:unknown=$true;throw 'UI operator requested preserving the session.'}
                }else{Start-Sleep -Milliseconds 500}
            }
            if(-not $done){$script:unknown=$true;throw 'UI fixture wait expired; session preserved.'}
            Assert-KnownBooks
            $audit.uiObservedState=Current-State
            $audit.uiObservedCellMenu=[string]$script:Excel.Run($script:q+'SLC_MenuXml','Cell')
            $audit.functional='NOT_RUN';$audit.nativeUi='EXTERNAL_EVIDENCE_REQUIRED'
        }else{
            Invoke-Product 'SLC_Clear'
            Select-Fixture $firstBook 'A2:A10'
            Record-RawStatus 'before-capture'
            Invoke-Product 'SLC_Capture'
            Record-RawStatus 'after-capture'
            $pending=Current-State;Check ($pending.Contains('7') -and $pending.Contains([string]$firstBook.Name)) 'First snapshot records count and source' $pending
            $preview=Capture-Result 'SLC_Preview' @('요약','제외·발생위치','규칙으로 같아진 값')
            Record-RawStatus 'after-preview'
            Check ([double](Summary-Value $preview '비교 대상 항목' 2) -eq 7) 'Preview retains seven captured items'
            Select-Fixture $secondBook 'A2:A10'
            $equal=Capture-Result 'SLC_Compare' @('요약','차이·중복','제외·발생위치','규칙으로 같아진 값')
            Assert-Summary $equal 7 7 7 0 0
            Check ([string](Summary-Value $equal '확인 결과' 2) -ceq '비교 대상 값·개수 일치') 'Equality still produces a result workbook'
            Check ([double](Summary-Value $equal '제외: 빈칸·공백·빈문자' 2) -eq 1 -and [double](Summary-Value $equal '제외: 오류' 2) -eq 1) 'Blank/error exclusions remain explicit'
            Select-Fixture $secondBook 'B2:B4'
            $different=Capture-Result 'SLC_Compare' @('요약','차이·중복','제외·발생위치','규칙으로 같아진 값')
            Assert-Summary $different 7 3 1 6 2
            Check ((Current-State).Contains([string]$firstBook.Name)) 'Repeated comparison retains first source' (Current-State)
            # Alter only an in-memory synthetic fixture; its disk file is never saved.
            $sheet=$firstBook.Worksheets.Item(1);$cell=$sheet.Range('A2');try{$cell.Value2='edited-after-capture'}finally{Release-Com $cell;Release-Com $sheet}
            Select-Fixture $secondBook 'A2:A10'
            $snapshot=Capture-Result 'SLC_Compare' @('요약','차이·중복','제외·발생위치','규칙으로 같아진 값')
            Assert-Summary $snapshot 7 7 7 0 0
            Assert-Summary $equal 7 7 7 0 0
            Invoke-Product 'SLC_Clear'
            $audit.functional='PASS'
        }
    }
    if($audit.uiDiagnosticFailures.Count){$audit.status='FAIL';$audit.failure='Toolbar checks failed; UI fixture was exposed for diagnosis only.';$exitCode=1}
    else{$audit.status='PASS';$exitCode=0}
}catch{
    if($audit.status -ne 'BLOCKED_ENV'){$audit.status='FAIL'}
    $audit.failure=$_.Exception.Message
}finally{
    Phase 'cleanup'
    if($functionsLoaded -and $null -ne $script:Excel){
        try{Assert-KnownBooks}catch{$script:unknown=$true;$audit.cleanupErrors+=@($_.Exception.Message)}
        if(-not $script:unknown){
            for($i=$script:owned.Count-1;$i -ge 0;$i--){
                try{$script:owned[$i].book.Close($false)}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
                Release-Com $script:owned[$i].book
            }
            $script:owned.Clear();$firstBook=$null;$secondBook=$null;$preview=$null;$equal=$null;$different=$null;$snapshot=$null
            try{
                if($null -ne $script:initialState){
                    $script:Excel.ScreenUpdating=$script:initialState.screenUpdating;$script:Excel.EnableEvents=$script:initialState.enableEvents
                    $script:Excel.DisplayAlerts=$script:initialState.displayAlerts;$script:Excel.EnableCancelKey=$script:initialState.enableCancelKey
                    $script:Excel.StatusBar=$script:initialState.statusValue
                }
                # A workbook Close event can open another document. Revalidate
                # after closing our fixtures/results and immediately before Quit.
                Assert-KnownBooks
                Release-Com $script:loaded;$script:loaded=$null
                # Expected startup COM errors may retain RCWs in PowerShell's
                # error ring. All useful failure text is already in the audit.
                $Error.Clear()
                Stop-OwnExcel
                $audit.quitSent=$true
            }catch{$audit.cleanupErrors+=@($_.Exception.Message)}
        }else{
            # Unknown or operator-preserved documents are never closed, saved, or killed.
            foreach($entry in $script:owned){Release-Com $entry.book};$script:owned.Clear()
            Release-Com $script:loaded;$script:loaded=$null;Release-Com $script:Excel;$script:Excel=$null
        }
    }
    foreach($fixture in $audit.fixtures){
        try{Check ((Hash-File $fixture.path) -ceq $fixture.sha256) ('Synthetic source file preserved: '+[IO.Path]::GetFileName($fixture.path))}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
    }
    if($Mode -ne 'NoAddin' -and $null -ne $audit.actualSha256){
        try{$audit.finalSha256=Hash-File $addin;if($audit.finalSha256 -cne $audit.actualSha256){throw 'Installed add-in changed during testing.'}}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
    }
    if($null -ne $audit.owner){
        [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();[GC]::WaitForPendingFinalizers()
        $exitTimer=[Diagnostics.Stopwatch]::StartNew();$same=$false
        do{
            $p=Get-Process -Id $audit.owner.pid -ErrorAction SilentlyContinue;$same=$false
            if($null -ne $p){try{$same=$p.StartTime.ToUniversalTime().Ticks.ToString() -ceq $audit.owner.startTimeUtcTicksText}finally{$p.Dispose()}}
            if($same -and -not $script:unknown){Start-Sleep -Milliseconds 250}
        }while($same -and -not $script:unknown -and $exitTimer.Elapsed.TotalSeconds -lt 15)
        $audit.excelExited=(-not $same)
        if($same){
            if($audit.quitSent -and -not $script:unknown -and $audit.status -eq 'PASS' -and $audit.cleanupErrors.Count -eq 0){
                # Some PowerShell COM references are released only as this host
                # exits. A separate parent must confirm PID/start disappearance.
                # The child deliberately does not classify this as PASS.
                $audit.status='PENDING_HOST_RELEASE';$exitCode=0
                $audit.exitConfirmation='PENDING_HOST_RELEASE'
                $audit.warnings+=@('Quit returned successfully; owned Excel still exists in this host. Parent must verify the exact PID/start identity exits after this process terminates. No process was killed.')
            }else{
                $audit.exitConfirmation='FAIL'
                $audit.cleanupErrors+=@('Owned Excel remains open; no process was killed.')
            }
        }else{$audit.exitConfirmation='PASS'}
    }
    if($audit.cleanupErrors.Count -gt 0){$audit.status='FAIL';$exitCode=1}
    if($locked -and $null -ne $mutex){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}
    $audit.phase='finished';$audit.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-Audit
}
Write-Output ($audit.status+': '+$(if($audit.failure){$audit.failure}else{'See flow.private.json; native UI evidence is separate.'}))
exit $exitCode
