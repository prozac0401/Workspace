Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Write-Json($Value, [string]$Path) {
    # Readers observe either the complete old document or the complete new one.
    $text=$Value | ConvertTo-Json -Depth 30
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($text)
    $pending=$Path+'.'+[guid]::NewGuid().ToString('N')+'.pending'
    $stream=[IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    try {
        if([IO.File]::Exists($Path)) { [IO.File]::Replace($pending,$Path,[Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($pending,$Path) }
    } finally { if([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) } }
}
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-StreamSha($Stream) {
    $Stream.Position=0; $sha=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-','') }
    finally { $sha.Dispose(); $Stream.Position=0 }
}
function Assert-NoReparse([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force
    while($null -ne $item) {
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "ReparsePoint: $($item.FullName)" }
        $item=if($item -is [IO.FileInfo]){$item.Directory}else{$item.Parent}
    }
}
function Set-PrivateDirectory([string]$Path) {
    Assert-NoReparse $Path
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,(New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'))) {
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    [IO.Directory]::SetAccessControl($Path,$acl)
}
function Assert-LocalWorkbook([string]$Path) {
    if($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2).Contains(':')) { throw 'LocalPathRequired' }
    $full=[IO.Path]::GetFullPath($Path)
    if(-not [IO.File]::Exists($full)) { throw 'FileNotFound' }
    Assert-NoReparse $full
    $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($full))
    if($drive.DriveType -ne [IO.DriveType]::Fixed -or $drive.DriveFormat -ne 'NTFS') { throw 'LocalNtfsRequired' }
    if([IO.Path]::GetExtension($full).ToLowerInvariant() -notin @('.xls','.xlsx','.xlsm','.xlsb')) { throw 'UnsupportedExtension' }
    $name=[IO.Path]::GetFileName($full)
    if($name.StartsWith('~$') -or $name.StartsWith('.eps-')) { throw 'TemporaryFileNotSupported' }
    $attrs=[IO.File]::GetAttributes($full)
    if($attrs -band [IO.FileAttributes]::ReadOnly) { throw 'ReadOnlyAttribute' }
    if($attrs -band [IO.FileAttributes]::Offline) { throw 'OfflineFileUnsupported' }
    if(Test-Path -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($full)) ('~$'+$name))) { throw 'FileInUse' }
    return $full
}
function Assert-Request($Request) {
    foreach($property in @('schemaVersion','path','mode','oldSecret','newSecret','expectedHash')) {
        if($null -eq $Request.PSObject.Properties[$property]) { throw 'InvalidRequest' }
    }
    if($Request.schemaVersion -ne 1 -or $Request.mode -notin @('Encrypt','Decrypt','ChangePassword') -or $Request.expectedHash -notmatch '^[0-9a-fA-F]{64}$') { throw 'InvalidRequest' }
    $old=''; $new=''
    try {
        $old=Unprotect-Text $Request.oldSecret; $new=Unprotect-Text $Request.newSecret
        if($Request.mode -in @('Decrypt','ChangePassword') -and -not $old) { throw 'CurrentPasswordRequired' }
        if($Request.mode -in @('Encrypt','ChangePassword') -and ($new.Length -lt 1 -or $new.Length -gt 15)) { throw 'NewPasswordLength' }
        if($Request.mode -eq 'ChangePassword' -and $old -ceq $new) { throw 'PasswordUnchanged' }
    } finally { $old=''; $new='' }
}
function Assert-NotCancelled([string]$RunDirectory) {
    if([IO.File]::Exists((Join-Path $RunDirectory 'cancel'))) { throw 'Cancelled' }
}
function Get-EngineMutexName {
    'Global\ExcelPasswordSafe.Controller.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}
function Get-Category($ErrorRecord, [string]$Stage) {
    $ex=$ErrorRecord.Exception; $codes=New-Object 'System.Collections.Generic.List[string]'
    while($null -ne $ex) {
        $codes.Add(('0x{0:X8}' -f ($ex.HResult -band 0xffffffffL)))
        if($ex -is [UnauthorizedAccessException]) { return 'AccessDenied' }
        $ex=$ex.InnerException
    }
    if(@($codes | Where-Object { $_ -in @('0x8002801D','0x80029C4A','0x80040154') }).Count) { return 'ComRegistrationOrLibrary' }
    if(@($codes | Where-Object { $_ -in @('0x80010105','0x800706BA','0x80010108','0x80010001','0x8001010A') }).Count) { return 'ComServerError' }
    if($codes.Contains('0x80070005')) { return 'AccessDenied' }
    if(@($codes | Where-Object { $_ -in @('0x80070020','0x80070021') }).Count) { return 'FileInUse' }
    if($Stage -eq 'Open') { return 'OpenFailedPossiblePasswordOrCorruption' }
    if($Stage -eq 'Verify') { return 'ValidationFailed' }
    if($Stage -eq 'Commit') { return 'CommitFailed' }
    return ($Stage+'Failed')
}
function Get-HResults($ErrorRecord) {
    $ex=$ErrorRecord.Exception; $codes=@()
    while($null -ne $ex) { $codes+=('0x{0:X8}' -f ($ex.HResult -band 0xffffffffL)); $ex=$ex.InnerException }
    $codes -join ';'
}
function Get-AllowedFormats([string]$Extension) {
    switch($Extension.ToLowerInvariant()) { '.xls' {56} '.xlsx' {51;61} '.xlsm' {52} '.xlsb' {50} }
}
function Release-Com($Object) {
    if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)) {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Object)
    }
}
function Unprotect-Text([string]$Cipher) {
    if(-not $Cipher) { return '' }
    $sec=ConvertTo-SecureString $Cipher
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $sec.Dispose() }
}
# Formula/constant values, sheet identity, visibility, shape and OLE inventory.
# This is a semantic guard, NOT proof of byte-identical object payloads or rendering.
function Get-WorkbookSignature($Book) {
    $sheets=$null; $records=New-Object 'System.Collections.Generic.List[object]'
    try {
        $sheets=$Book.Sheets
        for($i=1;$i -le $sheets.Count;$i++) {
            $sheet=$null; $range=$null; $rows=$null; $columns=$null; $shapes=$null
            try {
                $sheet=$sheets.Item($i)
                $row=[ordered]@{name=[string]$sheet.Name;type=[int]$sheet.Type;visible=[int]$sheet.Visible;shapes=@()}
                if($sheet.Type -in @(3,4)) { throw 'Excel4MacroSheetNotSupported' }
                if($sheet.Type -eq -4167) {
                    $range=$sheet.UsedRange
                    # PSSerializer keeps types, array ranks and element values; no cell COM loop.
                    $xml=[Management.Automation.PSSerializer]::Serialize($range.Formula,100)
                    $sha=[Security.Cryptography.SHA256]::Create()
                    try { $row.formulaSha=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($xml))) }
                    finally { $sha.Dispose() }
                    $rows=$range.Rows; $columns=$range.Columns
                    $row.bounds=@([int]$range.Row,[int]$range.Column,[int]$rows.Count,[int]$columns.Count)
                }
                $shapes=$sheet.Shapes; $inventory=@()
                for($j=1;$j -le $shapes.Count;$j++) {
                    $shape=$null
                    try { $shape=$shapes.Item($j); $inventory+=[ordered]@{name=[string]$shape.Name;type=[int]$shape.Type} }
                    finally { Release-Com $shape }
                }
                $row.shapes=$inventory; $records.Add($row)
            } finally { Release-Com $shapes; Release-Com $columns; Release-Com $rows; Release-Com $range; Release-Com $sheet }
        }
        [ordered]@{format=[int]$Book.FileFormat;vba=[bool]$Book.HasVBProject;sheets=@($records.ToArray())} | ConvertTo-Json -Depth 20 -Compress
    } finally { Release-Com $sheets }
}

function Invoke-GuardedReplace([string]$Source,[string]$Temp,[string]$Backup,[string]$Recovery,[string]$SourceHash,[string]$TempHash,$HeldStream) {
    if((Get-Sha $Temp) -ne $TempHash) { throw 'TempChanged' }
    if((Get-Sha $Source) -ne $SourceHash -or (Get-StreamSha $HeldStream) -ne $SourceHash) { throw 'SourceChanged' }
    if((Get-Sha $Backup) -ne $SourceHash) { throw 'BackupChanged' }
    [IO.File]::Replace($Temp,$Source,$Recovery,$false)
    if((Get-Sha $Source) -ne $TempHash -or (Get-Sha $Recovery) -ne $SourceHash) { throw 'PostReplaceHashMismatch' }
    Get-Sha $Source
}
