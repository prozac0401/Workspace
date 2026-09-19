# Pure mock regression: no Excel, installation, registry or product mutation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'windows-rc10-flow.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Flow source must parse.'}
$definitions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Find-LoadedBook'},$false))
if($definitions.Count -ne 1){throw 'Expected one Find-LoadedBook.'}
. ([scriptblock]::Create($definitions[0].Extent.Text))
$script:releaseCount=0
function Release-Com($Value){if($null -ne $Value){$script:releaseCount++}}
function Assert([bool]$Passed,[string]$Message){if(-not $Passed){throw $Message}}
$audit=[ordered]@{addinLookup=$null}
$hidden=[pscustomobject]@{Name='ExcelSmartListCompare.xlam';IsAddin=$true;FullName='C:\Synthetic\ExcelSmartListCompare.xlam'}
$books=[pscustomobject]@{Count=0;Hidden=$hidden;Requests=(New-Object Collections.Generic.List[string])}
$books|Add-Member ScriptMethod Item {
    param($Name)
    $this.Requests.Add([string]$Name)
    if($Name -is [string] -and $Name -ceq $this.Hidden.Name){return $this.Hidden}
    throw [Runtime.InteropServices.COMException]::new('Synthetic bad index',-2147352565)
}
$script:Excel=[pscustomobject]@{Workbooks=$books}
$found=Find-LoadedBook 'ExcelSmartListCompare.xlam'
Assert ([object]::ReferenceEquals($found,$hidden)) 'Count zero must not hide a named loaded add-in.'
Assert ($books.Requests.Count -eq 1 -and $books.Requests[0] -ceq 'ExcelSmartListCompare.xlam') 'The exact filename must be queried without numeric enumeration.'
Assert ($script:releaseCount -eq 1 -and $audit.addinLookup.status -eq 'FOUND') 'Successful observation must release its collection and record FOUND.'
$absent=Find-LoadedBook 'Absent.xlam'
Assert ($null -eq $absent -and $audit.addinLookup.status -eq 'MISSING') 'Bad index must preserve NoAddin missing behavior.'
Assert ($audit.addinLookup.errorHresult -eq '8002000B' -and $script:releaseCount -eq 2) 'Missing observation must record only scalar diagnostics and release its collection.'
Assert ($Error.Count -eq 0) 'Expected COM lookup errors must not retain error-ring references.'
$books|Add-Member ScriptMethod Item {param($Name)throw [Runtime.InteropServices.COMException]::new('Synthetic RPC rejection',-2147418111)} -Force
$unexpected=$false
try{$null=Find-LoadedBook 'ExcelSmartListCompare.xlam'}catch{$unexpected=$true}
Assert ($unexpected -and $audit.addinLookup.status -eq 'LOOKUP_FAILED') 'RPC rejection must not be classified as an absent add-in.'
Assert ($script:releaseCount -eq 3) 'Unexpected failure must also release its collection.'
Assert ($definitions[0].Extent.Text -notmatch '\.Open\s*\(|\.Run\s*\(') 'Observation helper must never load or activate the add-in.'
Write-Output 'PASS: named hidden-addin lookup; missing lookup; unexpected COM failure; observation-only and collection cleanup.'
