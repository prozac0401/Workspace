# Pure mock regression for an enumerable toolbar. Never opens Excel.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'windows-rc10-flow.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Flow source must parse.'}
$definitions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Find-Toolbar'},$false))
if($definitions.Count -ne 1){throw 'Expected one Find-Toolbar.'}
. ([scriptblock]::Create($definitions[0].Extent.Text))
foreach($name in @('Get-ToolbarProbeHResult','Read-ToolbarNames','Test-ToolbarAbsenceControls')){
    $helper=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$false))
    if($helper.Count -ne 1){throw ('Expected one '+$name)}
    . ([scriptblock]::Create($helper[0].Extent.Text))
}
Add-Type @'
using System;
using System.Collections;
public sealed class SlcMockEnumerableToolbar : IEnumerable {
    public string Name { get; set; }
    public object[] Controls { get; private set; }
    public SlcMockEnumerableToolbar() { Name = "SLC_68A45C44_Toolbar"; Controls = new object[] { "button-one", "button-two" }; }
    public IEnumerator GetEnumerator() { return Controls.GetEnumerator(); }
}
public sealed class SlcMockToolbarCollection {
    public SlcMockEnumerableToolbar Toolbar { get; private set; }
    private SlcMockEnumerableToolbar Other;
    public bool HideFromEnumeration { get; set; }
    public bool Missing { get; set; }
    public int NamedError { get; set; }
    public int Count { get { return 1; } }
    public SlcMockToolbarCollection() { Toolbar = new SlcMockEnumerableToolbar(); Other = new SlcMockEnumerableToolbar(); Other.Name="Unrelated toolbar"; }
    public SlcMockEnumerableToolbar Item(object index) {
        if(index is string) {
            if(NamedError != 0) throw new System.Runtime.InteropServices.COMException("Synthetic lookup failure",NamedError);
            if(!Missing && (string)index == Toolbar.Name) return Toolbar;
            throw new System.Runtime.InteropServices.COMException("Synthetic bad index",unchecked((int)0x8002000B));
        }
        if(Convert.ToInt32(index) != 1) throw new IndexOutOfRangeException();
        return HideFromEnumeration ? Other : Toolbar;
    }
}
'@
$script:releases=New-Object Collections.Generic.List[object]
function Release-Com($Value){if($null -ne $Value){$script:releases.Add($Value)}}
function Assert([bool]$Pass,[string]$Message){if(-not $Pass){throw $Message}}
$audit=[ordered]@{toolbarLookup=$null}
$bars=New-Object SlcMockToolbarCollection
$script:Excel=[pscustomobject]@{CommandBars=$bars}
$found=Find-Toolbar
Assert ([object]::ReferenceEquals($found,$bars.Toolbar)) 'Enumerable toolbar must remain the exact object, not unroll to its buttons.'
Assert ($found.Controls.Count -eq 2 -and $found -isnot [Array]) 'Returned object must retain Controls.'
Assert ($audit.toolbarLookup.status -eq 'FOUND' -and $audit.toolbarLookup.controlsCount -eq 2 -and -not $audit.toolbarLookup.isArray) 'Scalar toolbar diagnostics must describe the actual object.'
Assert ($script:releases.Count -eq 3) 'Enumeration reference, controls and bars collections must be released.'
$bars.HideFromEnumeration=$true
$namedOnly=Find-Toolbar
Assert ([object]::ReferenceEquals($namedOnly,$bars.Toolbar) -and -not $audit.toolbarLookup.enumerationMatched -and $audit.toolbarLookup.namedLookup -eq 'FOUND') 'Named lookup must find a toolbar absent from numeric enumeration.'
Assert ($script:releases.Count -eq 6) 'Named-only success must also release the observed references.'
$bars.Missing=$true
$missing=Find-Toolbar
Assert ($null -eq $missing -and $audit.toolbarLookup.status -eq 'MISSING' -and $audit.toolbarLookup.namedLookup -eq 'MISSING') 'Missing toolbar must produce explicit scalar MISSING evidence.'
Assert ($script:releases.Count -eq 8 -and $Error.Count -eq 0) 'Missing lookup must release references and clear expected COM errors.'
$bars.NamedError=-2147024809
$failed=$false
try{$null=Find-Toolbar}catch{$failed=$true}
Assert ($failed -and $audit.toolbarLookup.status -eq 'LOOKUP_FAILED' -and $audit.toolbarLookup.errorHresult -eq '80070057') 'E_INVALIDARG alone must not establish toolbar absence.'
Assert ($audit.toolbarLookup.enumerationCompleted -and -not $audit.toolbarLookup.enumerationMatched) 'Completed negative enumeration must remain separate evidence from named lookup failure.'
Assert ($definitions[0].Extent.Text -notmatch '\.Add\s*\(|\.Run\s*\(') 'Toolbar observation must not repair or create UI.'
foreach($name in @('Check','Check-Toolbar')){
    $definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$false))
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
function Save-Audit {}
$audit=[ordered]@{tests=@();uiDiagnosticFailures=@()};$Mode='UiFixture';$AllowUiDiagnostics=$true
Check-Toolbar $false 'Synthetic missing toolbar'
Assert ($audit.tests[0].status -eq 'FAIL' -and $audit.uiDiagnosticFailures.Count -eq 1) 'Diagnostic UI continuation must latch failure, never convert it to PASS.'
$Mode='Functional';$blocked=$false
try{Check-Toolbar $false 'Synthetic functional failure'}catch{$blocked=$true}
Assert $blocked 'Functional mode must still stop on a toolbar failure.'
Write-Output 'PASS: enumerable and named-only toolbar identity; missing diagnostic; cleanup; UI diagnostic failure latch; strict Functional gate.'
