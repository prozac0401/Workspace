param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$files=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')+@(Get-Item -LiteralPath (Join-Path $root 'Setup.ps1'))
$checks=@(foreach($file in $files){
    $errors=$null;$tokens=$null
    $null=[System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    [pscustomobject]@{file=$file.Name;parserVersion=[string]$PSVersionTable.PSVersion;errors=@($errors | ForEach-Object Message);status=if($errors.Count){'FAIL'}else{'PASS'}}
})
$checks | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$checks | Format-Table file,status
if(@($checks | Where-Object status -eq 'FAIL').Count){exit 1}
