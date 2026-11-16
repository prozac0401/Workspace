#requires -Version 5.1
#requires -PSEdition Desktop
# Internal worker: it can ONLY write a temporary workbook, never replace a source.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$JobPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$job=Get-Content -LiteralPath $JobPath -Raw | ConvertFrom-Json
$app=$null; $books=$null; $book=$null; $owned=$false; $stage='ComStart'
$result=[ordered]@{status='Failed';category='WorkerFailed';stage=$stage;hresults='';message='';excelPid=0;encryptedBefore=$null}
$old=''; $new=''; $sentinel=[guid]::NewGuid().ToString('N').Substring(0,15)
try {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class EpsWindow { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid); }
'@
    $prior=@(Get-Process EXCEL -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if($prior.Count) { throw 'ExistingExcel: close Excel normally before retry.' }
    $app=New-Object -ComObject Excel.Application
    [uint32]$excelProcessId=0
    [void][EpsWindow]::GetWindowThreadProcessId([IntPtr]$app.Hwnd,[ref]$excelProcessId)
    if(-not $excelProcessId -or $excelProcessId -in $prior) { throw 'ExcelOwnershipNotProven' }
    $owned=$true; $result.excelPid=$excelProcessId
    $app.Visible=$false; $app.DisplayAlerts=$false; $app.EnableEvents=$false
    $app.AskToUpdateLinks=$false; $app.AutomationSecurity=3
    $old=Unprotect-Text $job.oldSecret; $new=Unprotect-Text $job.newSecret
    if(-not $old) { $old=$sentinel }
    $missing=[Type]::Missing
    $books=$app.Workbooks
    $stage='Open'
    # Explicit password and write-password avoid missing-argument password prompts.
    $book=$books.Open($job.input,0,$true,$missing,$old,$sentinel,$true,$missing,$missing,$false,$false,$missing,$false,$false,0)
    if($null -eq $book) { throw 'WorkbookOpenReturnedNull' }
    $hasPassword=[bool]$book.HasPassword; $result.encryptedBefore=$hasPassword
    $signatureSet=$null
    try { $signatureSet=$book.Signatures; $signed=$signatureSet.Count -gt 0 } finally { Release-Com $signatureSet }
    if($signed -or $book.VBASigned) { $result.category='SignedWorkbookUnsupported'; $result.status='Skipped' }
    elseif($book.MultiUserEditing) { $result.category='SharedWorkbookUnsupported'; $result.status='Skipped' }
    elseif($book.WriteReserved) { $result.category='WriteReservedUnsupported'; $result.status='Skipped' }
    elseif($job.mode -eq 'Encrypt' -and $hasPassword) { $result.category='AlreadyEncrypted'; $result.status='Skipped' }
    elseif($job.mode -eq 'Decrypt' -and -not $hasPassword) { $result.category='AlreadyUnencrypted'; $result.status='Skipped' }
    else {
        $format=[int]$book.FileFormat
        if($format -notin @(Get-AllowedFormats ([IO.Path]::GetExtension($job.backup)))) { throw 'ExtensionAndFileFormatMismatchOrLegacyFormat' }
        $stage='Verify'; $before=Get-WorkbookSignature $book
        $stage='SaveAs'; $outPassword=if($job.mode -eq 'Encrypt'){$new}else{''}
        # Positional COM arguments: FileName, FileFormat, Password, WriteResPassword...
        $book.SaveAs($job.temp,$format,$outPassword,'',$false,$false,1,2,$false,$missing,$missing,$false)
        $book.Close($false); Release-Com $book; $book=$null
        $stage='Verify'
        if(-not (Test-Path -LiteralPath $job.temp) -or (Get-Item -LiteralPath $job.temp).Length -eq 0) { throw 'EmptyTemporaryFile' }
        $verifyPassword=if($outPassword){$outPassword}else{$sentinel}
        $book=$books.Open($job.temp,0,$true,$missing,$verifyPassword,$sentinel,$true,$missing,$missing,$false,$false,$missing,$false,$false,0)
        if($null -eq $book) { throw 'VerificationOpenReturnedNull' }
        if([bool]$book.HasPassword -ne ($job.mode -eq 'Encrypt')) { throw 'PasswordStateMismatch' }
        if((Get-WorkbookSignature $book) -cne $before) { throw 'WorkbookSignatureMismatch' }
        $book.Close($false); Release-Com $book; $book=$null
        if($job.mode -eq 'Encrypt') {
            # Negative test: a deliberately different password MUST fail to open.
            $wrong=if($new -ceq $sentinel){'Wrong-'+$sentinel.Substring(0,8)}else{$sentinel}
            $unexpected=$null; $rejected=$false
            try { $unexpected=$books.Open($job.temp,0,$true,$missing,$wrong,$sentinel,$true,$missing,$missing,$false,$false,$missing,$false,$false,0) }
            catch {
                # Only Excel's normal 1004 qualifies; RPC/library failures are not proof.
                if((Get-HResults $_) -notmatch '0x800A03EC') { throw }
                $rejected=$true
            }
            finally { if($null -ne $unexpected) { $unexpected.Close($false); Release-Com $unexpected } }
            if(-not $rejected) { throw 'WrongPasswordWasNotRejected' }
        }
        $result.status='Validated'; $result.category='Validated'; $result.tempHash=Get-Sha $job.temp
    }
} catch {
    $result.category=Get-Category $_ $stage; $result.hresults=Get-HResults $_
    $message=$_.Exception.Message
    foreach($secret in @($old,$new,$sentinel)) { if($secret) { $message=$message.Replace($secret,'[REDACTED]') } }
    $result.message=$message
    if($message -match 'ExtensionAndFileFormatMismatchOrLegacyFormat') { $result.category='UnsupportedOrMismatchedFormat' }
    elseif($message -match 'Excel4MacroSheetNotSupported') { $result.category='Excel4MacroSheetUnsupported' }
    elseif($message -match 'ExistingExcel|ExcelOwnershipNotProven') { $result.category='ExcelOwnershipOrExistingProcess' }
} finally {
    $result.stage=$stage
    try { if($null -ne $book) { $book.Close($false) } } catch { $result.status='Failed'; $result.category='ComCleanupFailed' }
    Release-Com $book; Release-Com $books
    if($owned -and $null -ne $app) {
        try { $app.Quit() } catch { $result.status='Failed'; $result.category='ComCleanupFailed' }
    }
    Release-Com $app; $old=''; $new=''; $outPassword=''
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    Write-Json $result $job.result
}
