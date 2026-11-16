#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$file = (Resolve-Path -LiteralPath $MsiPath).Path
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($file,0)
function Query([string]$Sql,[int]$Columns) {
    $view=$database.OpenView($Sql)
    try {
        [void]$view.Execute(); $rows=@()
        while ($row=$view.Fetch()) {
            $values=@(); for($i=1;$i -le $Columns;$i++) { $values += $row.StringData($i) }
            $rows += ,$values
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($row)
        }
        return ,$rows
    } finally { [void]$view.Close(); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) }
}
try {
    $properties=@{}
    foreach($row in (Query 'SELECT `Property`, `Value` FROM `Property`' 2)) { $properties[$row[0]]=$row[1] }
    if($properties['ALLUSERS']) { throw 'The package is not per-user.' }
    if($properties['ProductName'] -ne 'ExcelPasswordSafe') { throw 'Unexpected product name.' }
    if($properties['UpgradeCode'] -ne '{0E60B57C-21DA-41A5-8FAC-6CCDF41EB62C}') { throw 'Unexpected upgrade identity.' }
    $registry=Query 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`' 4
    foreach($row in $registry) {
        if($row[0] -ne '1') { throw 'Non-HKCU registry write found.' }
        if($row[1] -notmatch '^Software\\(Workspace\\ExcelPasswordSafe($|\\)|Classes\\SystemFileAssociations\\\.(xls|xlsx|xlsm|xlsb)\\shell\\Workspace\.ExcelPasswordSafe($|\\command$))') { throw ('Unexpected registry ownership scope: '+$row[1]) }
    }
    $commands=@($registry | Where-Object { $_[1] -match '\\command$' })
    if($commands.Count -ne 4) { throw 'Expected exactly four extension-specific commands.' }
    foreach($row in $commands) { if($row[3] -cne '"[INSTALLFOLDER]ExcelPasswordSafe.exe" --file "%1"') { throw 'Unexpected or unquoted shell command.' } }
    foreach($extension in @('.xls','.xlsx','.xlsm','.xlsb')) {
        $key='Software\Classes\SystemFileAssociations\'+$extension+'\shell\Workspace.ExcelPasswordSafe'
        if(@($registry | Where-Object { $_[1] -eq $key -and $_[2] -eq 'MultiSelectModel' -and $_[3] -eq 'Single' }).Count -ne 1) { throw ('Single-file menu model missing: '+$extension) }
    }
    $files=Query 'SELECT `FileName` FROM `File`' 1
    $names=@($files | ForEach-Object { ($_[0] -split '\|')[-1] } | Sort-Object)
    $expected=@('Common.ps1','Engine.ps1','ExcelPassword.Worker.ps1','ExcelPasswordSafe.exe','ExcelPasswordSafe.exe.config','README.md') | Sort-Object
    if(($names -join '|') -cne ($expected -join '|')) { throw ('Unexpected MSI payload: '+($names -join ', ')) }
    $tables=Query 'SELECT `Name` FROM `_Tables`' 1
    if(@($tables | Where-Object { $_[0] -eq 'CustomAction' }).Count) {
        $actions=Query 'SELECT `Action`, `Type`, `Source`, `Target` FROM `CustomAction`' 4
        foreach($action in $actions) {
            # WiX emits only SetProperty for remembering an existing installation.
            if($action[0] -ne 'SetINSTALLFOLDER' -or $action[2] -ne 'INSTALLFOLDER' -or $action[3] -ne '[SAVEDINSTALLFOLDER]' -or $action[1] -ne '51') { throw ('Unexpected executable/custom action: '+$action[0]) }
        }
    }
    $summary=$database.SummaryInformation(0)
    try { $template=$summary.Property(7); $wordCount=[int]$summary.Property(15) } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary) }
    if($template -notmatch '^x64;') { throw 'Expected x64 MSI template.' }
    if(($wordCount -band 8) -ne 8) { throw 'Package is not marked for limited-user installation.' }
    [ordered]@{status='Pass';product=$properties['ProductName'];version=$properties['ProductVersion'];productCode=$properties['ProductCode'];upgradeCode=$properties['UpgradeCode'];fileCount=$files.Count;commands=$commands.Count;perUser=$true;registry='HKCU only';template=$template;limitedUser=$true;signature=(Get-AuthenticodeSignature -LiteralPath $file).Status.ToString();sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash;productionRelease=$false} | ConvertTo-Json
} finally {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
}
