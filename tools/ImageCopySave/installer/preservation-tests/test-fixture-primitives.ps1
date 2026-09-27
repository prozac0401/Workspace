[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
$harness=Join-Path $PSScriptRoot '../test-msi-preservation.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $harness).Path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Harness must parse before testing its fixture primitives.'}
$script:preservationHarnessDirectory=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$names=@('Initialize-NamedStreamApi','Assert-PlainPath','Get-Hash','Get-NamedStreamHash','With-AddedStream','Replace-ExactFile','Remove-ExactFile')
$functions=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)
foreach($name in $names){$match=@($functions | Where-Object {$_.Name -eq $name});if($match.Count -ne 1){throw 'Expected exactly one fixture helper.'}; . ([ScriptBlock]::Create($match[0].Extent.Text))}
# Only selected file-fixture helpers are loaded. No MSI or registry helper is
# invoked, and all test material remains beneath this unique artifacts path.
$output=Join-Path $root ('artifacts/image-copy-save/msi-preservation-primitives/' + [Guid]::NewGuid().ToString('N'))
[void](Assert-PlainPath $output (Join-Path $root 'artifacts/image-copy-save/msi-preservation-primitives'))
[IO.Directory]::CreateDirectory($output)|Out-Null
$installFolder=$output
$fixtureName='PreservationPrimitive_' + [Guid]::NewGuid().ToString('N')
$fixtureText='Synthetic fixture primitive test'
$utf8=New-Object Text.UTF8Encoding($false)
$target=Join-Path $output 'ImageCopySave.Engine.dll'
$bytes=$utf8.GetBytes('Synthetic file; not an actual DLL.')
[IO.File]::WriteAllBytes($target,$bytes)
$hash=Get-Hash $target
$expected=[pscustomobject]@{files=@([pscustomobject]@{path='ImageCopySave.Engine.dll';sha256=$hash})}
$activeStreamFixture=$null
$cases=New-Object Collections.Generic.List[object]
With-AddedStream $expected {
    if(-not $script:activeStreamFixture){throw 'Named stream fixture was not initialized.'}
    if((Get-NamedStreamHash $script:activeStreamFixture.path) -ne $script:activeStreamFixture.hash){throw 'Named stream hash differs.'}
    if((Get-Hash $target) -ne $hash){throw 'Named stream changed main file bytes.'}
}
if(@(Get-Item -LiteralPath $target -Stream * | Where-Object {$_.Stream -ne ':$DATA'}).Count -ne 0){throw 'Normal named stream cleanup left a stream.'}
$cases.Add('named stream created and hashed; only its stream removed; base preserved')
$rejected=$false
try{Replace-ExactFile $target ('0'*64) ($utf8.GetBytes('wrong replacement'))}catch{$rejected=$true}
if(-not $rejected -or (Get-Hash $target) -ne $hash){throw 'Compare-before-replace did not preserve mismatched file.'}
$cases.Add('mismatched file hash rejects replacement and preserves bytes')
$changed=$utf8.GetBytes('Owned test replacement')
Replace-ExactFile $target $hash $changed
$changedHash=Get-Hash $target
Replace-ExactFile $target $changedHash $bytes
if((Get-Hash $target) -ne $hash){throw 'Verified fixture replacement/restore differs.'}
$cases.Add('matched file replacement and verified restore preserve original hash')
$rejected=$false
try{[void](Assert-PlainPath (Join-Path $output '../escaped-file') $output)}catch{$rejected=$true}
if(-not $rejected){throw 'Boundary escape was accepted.'}
$cases.Add('artifact boundary escape rejected')
$preservedStream=$null
$rejected=$false
try{
    With-AddedStream $expected {
        $script:preservedStream=$script:activeStreamFixture.path
        Set-Content -LiteralPath $target -Stream ($script:preservedStream.Substring($target.Length+1)) -Value 'External test modification: preserve this stream' -Encoding UTF8 -NoNewline
    }
}catch{$rejected=$true}
if(-not $rejected -or -not $preservedStream -or (Get-Content -LiteralPath $target -Stream ($preservedStream.Substring($target.Length+1)) -Raw -Encoding UTF8) -ne 'External test modification: preserve this stream' -or (Get-Hash $target) -ne $hash){throw 'Modified named stream was not preserved by failed cleanup.'}
$cases.Add('externally changed named stream blocks cleanup and remains intact')
$rejected=$false
try{Remove-ExactFile $target $hash}catch{$rejected=$true}
if(-not $rejected -or -not [IO.File]::Exists($target) -or (Get-Hash $target) -ne $hash){throw 'File cleanup did not preserve a named stream added externally.'}
$cases.Add('whole-file cleanup rejects an external named stream even when base bytes match')
[ordered]@{status='PASS';tests=$cases;count=$cases.Count;artifacts=$output;msiInvoked=$false;registryChanged=$false}|ConvertTo-Json -Depth 5
