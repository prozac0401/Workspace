# Pure mock regression. No Excel, installation, registry or native input.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'windows-rc10-flow.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Flow source must parse.'}
foreach($name in @('Set-VisibleObservationContext','Record-RawStatus')){
    $definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$false))
    if($definition.Count -ne 1){throw ('Expected unique function: '+$name)}
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
function Assert([bool]$Passed,[string]$Message){if(-not $Passed){throw $Message}}
function Assert-KnownBooks {if($script:guardBlocked){throw 'Synthetic unknown document.'}}
function Save-Audit {}
$script:guardBlocked=$false
foreach($Mode in @('Functional','NormalStart','NoAddin','UiFixture')){
    $script:Excel=[pscustomobject]@{Visible=$false;UserControl=$false;StatusBar=$false}
    $audit=[ordered]@{startupWorkbook=@{name='SyntheticOwned.xlsx'};observationContext=$null;rawStatusObservations=@()}
    Set-VisibleObservationContext
    Assert ($script:Excel.Visible -and $script:Excel.UserControl) ($Mode+' must use visible user context.')
    Assert ($audit.observationContext.mode -ceq $Mode -and $audit.observationContext.startupWorkbook -ceq 'SyntheticOwned.xlsx') 'Context evidence must identify the actual mode and owned document.'
}
$script:Excel=[pscustomobject]@{Visible=$false;UserControl=$false;StatusBar=$false}
$script:guardBlocked=$true;$blocked=$false
try{Set-VisibleObservationContext}catch{$blocked=$true}
Assert ($blocked -and -not $script:Excel.Visible -and -not $script:Excel.UserControl) 'Unknown-document guard must stop before visibility mutation.'
Record-RawStatus 'boolean'
$script:Excel.StatusBar='FALSE'
Record-RawStatus 'text'
Assert ($audit.rawStatusObservations[0].type -ceq 'System.Boolean' -and $audit.rawStatusObservations[0].value -is [bool]) 'Boolean false must retain its variant type.'
Assert ($audit.rawStatusObservations[1].type -ceq 'System.String' -and $audit.rawStatusObservations[1].value -ceq 'FALSE') 'Literal FALSE must remain distinct from Boolean false.'
Write-Output 'PASS: visible context in four modes; unknown-document guard; raw Boolean versus string StatusBar evidence.'
