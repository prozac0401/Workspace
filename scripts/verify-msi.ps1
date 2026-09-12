[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath)
$ErrorActionPreference = 'Stop'
$file = (Resolve-Path -LiteralPath $MsiPath).Path
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($file,0)
function Query([string]$sql,[int]$columns) {
    $view=$database.OpenView($sql); [void]$view.Execute(); $rows=@()
    while ($record=$view.Fetch()) { $row=@(); for($i=1;$i -le $columns;$i++) { $row += $record.StringData($i) }; $rows += ,$row }
    [void]$view.Close(); return ,$rows
}
$properties = @{}
foreach($row in (Query 'SELECT `Property`, `Value` FROM `Property`' 2)) { $properties[$row[0]]=$row[1] }
if ($properties['ALLUSERS']) { throw 'Package is not strictly per-user.' }
if ($properties['ProductName'] -ne 'FolderState') { throw 'Wrong product.' }
$registry=Query 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`' 4
$commands=@($registry | Where-Object { $_[1] -like '*\Workspace.FolderState\shell\*\command' })
if ($commands.Count -ne 6) { throw "Expected six commands, found $($commands.Count)" }
foreach($row in $registry) { if ($row[0] -ne '1') { throw 'Non-HKCU registry entry found.' } }
foreach($row in $commands) { if ($row[3] -notmatch '^"\[INSTALLFOLDER\]FolderState.exe" (set (todo|doing|done|issue)|reset|repair) "%1"$') { throw 'Unquoted or unexpected command.' } }
$files=Query 'SELECT `FileName` FROM `File`' 1
if (@($files | Where-Object { $_[0] -like '*FolderState.exe*' }).Count -ne 1) { throw 'GUI missing from MSI.' }
if (@($files | Where-Object { $_[0] -like '*FolderState.Cli.exe*' }).Count -ne 1) { throw 'CLI missing from MSI.' }
@{product=$properties['ProductName'];version=$properties['ProductVersion'];productCode=$properties['ProductCode'];fileCount=$files.Count;commands=$commands.Count;perUser=$true;registry='HKCU only';signature=(Get-AuthenticodeSignature -LiteralPath $file).Status.ToString()} | ConvertTo-Json
