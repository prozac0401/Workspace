[CmdletBinding()]
param()
# Local synthetic-file regression only. Does not run MSI or change registration.
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'test-msi-lifecycle.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Assert-PlainPath','Restore-RepairFixture')) {
    $definition=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if ($definition.Count -ne 1) { throw 'Expected one recovery function definition.' }
    . ([ScriptBlock]::Create($definition[0].Extent.Text))
}
$output=Join-Path $root ('artifacts/image-copy-save/msi-recovery-tests/'+[Guid]::NewGuid().ToString('N'))
$installFolder=Join-Path $output 'synthetic-install'
[IO.Directory]::CreateDirectory($installFolder) | Out-Null
$checks=New-Object 'System.Collections.Generic.List[string]'
function Expect-Rejected([scriptblock]$Operation,[string]$Label) {
    $rejected=$false
    try { & $Operation | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw "Expected rejection: $Label" }
    $checks.Add($Label)
}
$target=Join-Path $installFolder 'owned.dll'
$backup=Join-Path $output 'owned.dll.backup'
[IO.File]::WriteAllText($backup,'synthetic-original-bytes')
$hash=(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
if ((Assert-PlainPath $target $installFolder) -ne $target) { throw 'Missing ordinary path was rejected.' }
$checks.Add('missing ordinary target accepted')
Expect-Rejected { Assert-PlainPath (Join-Path $output 'outside.dll') $installFolder } 'outside boundary rejected'
if ((Restore-RepairFixture $target $backup $hash) -ne 'RESTORED_VERIFIED_BACKUP' -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash) { throw 'Missing target was not restored.' }
$checks.Add('missing target restored with original hash')
[IO.File]::WriteAllText($target,'synthetic-new-file')
$newHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
if ((Restore-RepairFixture $target $backup $hash) -ne 'PRESERVED_EXISTING_TARGET' -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $newHash) { throw 'Existing target was overwritten.' }
$checks.Add('existing target preserved')
$otherTarget=Join-Path $installFolder 'missing.dll'
[IO.File]::WriteAllText($backup,'synthetic-changed-backup')
Expect-Rejected { Restore-RepairFixture $otherTarget $backup $hash } 'changed backup rejected'
if (Test-Path -LiteralPath $otherTarget) { throw 'Changed backup created a target.' }
$junction=Join-Path $root '.tools'
$reparse='NOT RUN: no existing local tools junction'
if (([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint)) {
    Expect-Rejected { Assert-PlainPath (Join-Path $junction 'synthetic-missing-child') $root } 'ancestor junction rejected'
    $reparse='PASS'
}
[ordered]@{ status='PASS'; passed=$checks.Count; checks=@($checks.ToArray()); existingAncestorJunction=$reparse; installed=$false; registryModified=$false; fixtures=$output } | ConvertTo-Json -Depth 5
