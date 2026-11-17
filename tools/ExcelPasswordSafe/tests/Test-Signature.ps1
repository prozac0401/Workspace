#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$EvidenceDirectory)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $PSScriptRoot ('..\..\..\artifacts\excel-password-safe\signature-'+[guid]::NewGuid().ToString('N'))}
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[IO.Directory]::CreateDirectory($EvidenceDirectory)|Out-Null
. (Join-Path $PSScriptRoot '..\runtime\Common.ps1')
$checks=[Collections.Generic.List[object]]::new()
$benchmarks=[Collections.Generic.List[object]]::new()
$status='FAIL';$errorMessage=$null
function Assert([bool]$Value,[string]$Name){$checks.Add([ordered]@{name=$Name;passed=$Value});if(-not $Value){throw $Name}}
function Different([object]$Left,[object]$Right,[string]$Name){Assert ((Get-FormulaSignature -Value $Left) -cne (Get-FormulaSignature -Value $Right)) $Name}
function Rejected([object]$Value,[string]$Name){
    $rejected=$false
    try{$null=Get-FormulaSignature -Value $Value}catch{$rejected=$_.Exception.ToString().Contains('UnsupportedFormula')}
    Assert $rejected $Name
}
function Measure-Signature([Array]$Value,[string]$Algorithm){
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    $heapBefore=[GC]::GetTotalMemory($false)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $xml=$null;$bytes=$null;$materializedBytes=0L
    if($Algorithm -eq 'PSSerializer'){
        $xml=[Management.Automation.PSSerializer]::Serialize($Value,100)
        $bytes=[Text.Encoding]::UTF8.GetBytes($xml)
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$signature=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','')}finally{$hash.Dispose()}
        $materializedBytes=2L*$xml.Length+$bytes.Length
    }else{$signature=Get-FormulaSignature -Value $Value}
    $watch.Stop()
    $heapAfter=[GC]::GetTotalMemory($false)
    [ordered]@{algorithm=$Algorithm;cells=$Value.Length;milliseconds=[Math]::Round($watch.Elapsed.TotalMilliseconds,3);managedHeapDeltaBytes=($heapAfter-$heapBefore);xmlAndUtf8PayloadBytes=$materializedBytes;signatureLength=$signature.Length}
}
try{
    $cold=[Diagnostics.Stopwatch]::StartNew();$first=Get-FormulaSignature -Value 'warm-up';$cold.Stop()
    Assert ($first -match '^[0-9A-F]{64}$' -and $first -ceq (Get-FormulaSignature -Value 'warm-up')) 'Hash is deterministic SHA-256'
    Different $null '' 'Null and empty string stay distinct'
    Different ([DBNull]::Value) $null 'DBNull and null stay distinct'
    Different ([double]1) '1' 'Numeric constant and text stay distinct'
    Different $true 'True' 'Boolean and text stay distinct'
    Different $false ([int]0) 'Boolean and numeric zero stay distinct'
    $numeric=@([sbyte]1,[byte]1,[int16]1,[uint16]1,[int32]1,[uint32]1,[int64]1,[uint64]1,[single]1,[double]1,[decimal]1)
    $numericHashes=@($numeric|ForEach-Object{Get-FormulaSignature -Value $_}|Sort-Object -Unique)
    Assert ($numericHashes.Count -eq $numeric.Count) 'All supported numeric types keep separate tags'
    Different ([double]1) ([double]1.000000000000001) 'Double precision is not rounded by string formatting'
    Different ([double]0) ([BitConverter]::Int64BitsToDouble([long]::MinValue)) 'IEEE positive and negative zero remain distinct'
    Different 'Case' 'case' 'Text comparison remains case sensitive'
    Different '한글🔒' '한글🔑' 'Unicode UTF-16 code units are preserved'
    Different "line`r`nend" "line`nend" 'Line endings are not normalized'
    Different ([string][char]0xd800) ([string][char]0xfffd) 'Unpaired surrogate does not collapse to a replacement character'
    Different ([char]'A') 'A' 'Character and string types remain distinct'
    Different '=SUM(A1:B2)' ([double]3) 'Formula text does not become its calculated constant'
    Different ([Runtime.InteropServices.ErrorWrapper]::new(2042)) ([int]2042) 'Excel error wrapper differs from a numeric constant'
    Different ([Runtime.InteropServices.ErrorWrapper]::new(2042)) ([Runtime.InteropServices.ErrorWrapper]::new(2015)) 'Excel error codes remain distinct'
    $date=[DateTime]::new(2026,1,2,3,4,5,[DateTimeKind]::Utc)
    Different $date ([DateTime]::SpecifyKind($date,[DateTimeKind]::Unspecified)) 'Date ticks and kind are both represented'
    Different $date ($date.AddTicks(1)) 'Date precision is retained'
    Different ([object[]]@('ab','c')) ([object[]]@('a','bc')) 'Element lengths prevent ambiguous concatenation'
    $matrix=[Array]::CreateInstance([object],[int[]]@(2,2),[int[]]@(1,1))
    $matrix.SetValue('A',1,1);$matrix.SetValue([double]2,1,2);$matrix.SetValue($true,2,1);$matrix.SetValue($null,2,2)
    Assert ((Get-FormulaSignature -Value $matrix) -ceq (Get-FormulaSignature -Value $matrix.Clone())) 'Equal COM-style 1-based matrices match'
    $changed=$matrix.Clone();$changed.SetValue('changed',2,2)
    Different $matrix $changed 'Changing one cell changes the matrix signature'
    Different $matrix ([object[]]@('A',[double]2,$true,$null)) 'Array rank differs from a flattened vector'
    $zeroBased=[Array]::CreateInstance([object],[int[]]@(2,2),[int[]]@(0,0))
    $zeroBased.SetValue('A',0,0);$zeroBased.SetValue([double]2,0,1);$zeroBased.SetValue($true,1,0);$zeroBased.SetValue($null,1,1)
    Different $matrix $zeroBased 'Array lower bounds remain part of the signature'
    Different ([Array]::CreateInstance([object],[int[]]@(2,3))) ([Array]::CreateInstance([object],[int[]]@(3,2))) 'Array dimensions are not inferred only from element count'
    Different ([object[]]@([double]1)) ([double[]]@(1)) 'Declared array element type is retained'
    Different ([object[]]@('one')) 'one' 'Single-cell array and scalar do not collapse'
    $originalCulture=[Threading.Thread]::CurrentThread.CurrentCulture
    try{
        $before=Get-FormulaSignature -Value $matrix
        [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('tr-TR')
        Assert ($before -ceq (Get-FormulaSignature -Value $matrix)) 'Hash encoding is independent of current culture'
    }finally{[Threading.Thread]::CurrentThread.CurrentCulture=$originalCulture}
    Rejected ([Uri]::new('https://example.invalid')) 'Unsupported object types fail closed'
    Rejected ([DayOfWeek]::Monday) 'Enum values are not silently treated as integers'
    Rejected ([Uri[]]@()) 'Even an empty array of unsupported object types fails closed'
    $cycle=New-Object object[] 1;$cycle.SetValue($cycle,0)
    Rejected $cycle 'Cyclic nested arrays stop at a bounded depth'

    # Generate synthetic values in managed code so construction cost is outside
    # the timed comparison. This never creates or opens an Excel document.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EpsSignatureTestData
{
    public static Array Create(int cells)
    {
        var values = Array.CreateInstance(typeof(object), new[] { cells / 10, 10 }, new[] { 1, 1 });
        for (int i = 0; i < cells; i++)
        {
            object value;
            switch (i % 10)
            {
                case 0: value = "text-" + i; break;
                case 1: value = i / 10.0; break;
                case 2: value = "=SUM(A1:B2)"; break;
                case 3: value = true; break;
                case 4: value = null; break;
                case 5: value = new DateTime(2026, 1, 2, 3, 4, 5); break;
                case 6: value = new ErrorWrapper(2042); break;
                case 7: value = ""; break;
                case 8: value = i; break;
                default: value = "line\r\ntext"; break;
            }
            values.SetValue(value, i / 10 + 1, i % 10 + 1);
        }
        return values;
    }
}
'@
    $warm=[EpsSignatureTestData]::Create(100)
    $null=Measure-Signature $warm 'PSSerializer';$null=Measure-Signature $warm 'TypedStream'
    foreach($size in @(100000,400000)){
        $values=[EpsSignatureTestData]::Create($size)
        $benchmarks.Add((Measure-Signature $values 'PSSerializer'))
        $benchmarks.Add((Measure-Signature $values 'TypedStream'))
        Assert ((Get-FormulaSignature -Value $values) -ceq (Get-FormulaSignature -Value $values)) ('Stable repeated hash for '+$size+' synthetic cells')
        $values=$null
    }
    $status='PASS'
}catch{$errorMessage=$_.Exception.Message}
finally{
    $record=[ordered]@{status=$status;assertions=$checks.Count;checks=$checks.ToArray();benchmarks=$benchmarks.ToArray();error=$errorMessage;scope='Synthetic managed values only; no Excel, UI, workbook file or business data access';memoryMetric='Managed heap immediately after hashing, not peak allocation. Legacy XML/UTF8 buffers remain live for measurement; shared input array is excluded by the before snapshot.';coldHelperMilliseconds=$(if($null -ne (Get-Variable cold -ErrorAction SilentlyContinue)){[Math]::Round($cold.Elapsed.TotalMilliseconds,3)}else{$null});timestamp=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'signature-results.json'),($record|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
}
$record|ConvertTo-Json -Depth 10
if($status -ne 'PASS'){throw 'Signature checks failed; see signature-results.json'}
