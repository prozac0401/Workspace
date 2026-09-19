# Pure synthetic regression. Never starts Excel or changes the installation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'windows-rc10-flow.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Flow source must parse.'}
foreach($name in @('Get-ToolbarProbeHResult','Read-ToolbarNames','Test-ToolbarAbsenceControls','Find-Toolbar')){
    $definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$false))
    if($definition.Count -ne 1){throw ('Expected unique function: '+$name)}
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public sealed class ProbeBar { public string Name {get;set;} public ProbeBar(string name){Name=name;} }
public sealed class ProbeBars {
    public string Scenario {get;set;}
    public int NumericCalls {get;private set;}
    public int NamedCalls {get;private set;}
    public int Count {get{return Scenario=="empty"?0:1;}}
    public ProbeBars(string scenario){Scenario=scenario;}
    public ProbeBar Item(object key){
        if(!(key is string)){
            NumericCalls++;
            if(Scenario=="enumeration-error")throw new COMException("Synthetic RPC",unchecked((int)0x80010001));
            if(Scenario=="enumerated-target")return new ProbeBar("SLC_68A45C44_Toolbar");
            if(Scenario=="churn" && NumericCalls>1)return new ProbeBar("Changed");
            return new ProbeBar("BuiltIn");
        }
        NamedCalls++;
        if((string)key=="BuiltIn"){
            if(Scenario=="positive-error")throw new COMException("Synthetic RPC",unchecked((int)0x80010001));
            if(Scenario=="positive-wrong")return new ProbeBar("Wrong");
            return new ProbeBar("BuiltIn");
        }
        if(Scenario=="negative-found")return new ProbeBar((string)key);
        int hr=Scenario=="negative-rpc"?unchecked((int)0x80010001):unchecked((int)0x80070057);
        throw new COMException("Synthetic missing or failure",hr);
    }
}
'@
function Release-Com($Value){}
function Assert([bool]$Passed,[string]$Message){if(-not $Passed){throw $Message}}
foreach($scenario in @('stable','positive-error','positive-wrong','negative-rpc','negative-found','enumerated-target','empty','enumeration-error','churn')){
    $bars=New-Object ProbeBars($scenario)
    $e=Test-ToolbarAbsenceControls $bars 'SLC_68A45C44_Toolbar' '80070057'
    $expected=$scenario -ceq 'stable'
    Assert ($e.absenceEstablished -eq $expected) ('Incorrect absence result: '+$scenario)
    if($expected){Assert ($e.status -ceq 'ABSENCE_CORROBORATED' -and $e.stableEnumeration -and $e.positiveStatus -ceq 'FOUND' -and $e.negativeHResult -ceq '80070057') 'Both controls and stable complete enumeration are required.'}
    else{Assert ($e.status -ceq 'LOOKUP_FAILED' -and $null -ne $e.failure) ('Failed control must preserve failure: '+$scenario)}
}
$bars=New-Object ProbeBars('stable')
$e=Test-ToolbarAbsenceControls $bars 'SLC_68A45C44_Toolbar' '80010001'
Assert (-not $e.absenceEstablished -and $bars.NamedCalls -eq 0 -and $bars.NumericCalls -eq 0) 'RPC target failures must not run controls or become absence.'
$script:Excel=[pscustomobject]@{CommandBars=(New-Object ProbeBars('stable'))}
$audit=[ordered]@{toolbarLookup=$null}
$found=Find-Toolbar
Assert ($null -eq $found -and $audit.toolbarLookup.status -ceq 'MISSING_CORROBORATED' -and $audit.toolbarLookup.absenceControls.absenceEstablished) 'Integrated lookup may return absent only after successful controls.'
$script:Excel=[pscustomobject]@{CommandBars=(New-Object ProbeBars('positive-error'))}
$failed=$false
try{$null=Find-Toolbar}catch{$failed=$true}
Assert ($failed -and $audit.toolbarLookup.status -ceq 'LOOKUP_FAILED' -and -not $audit.toolbarLookup.absenceControls.absenceEstablished) 'Integrated positive-control failure must still stop acceptance.'
Write-Output 'PASS: 10 synthetic control scenarios and 2 integrated lookup cases; no actual Excel observations.'
