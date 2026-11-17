Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Write-Json($Value, [string]$Path) {
    # Readers observe either the complete old document or the complete new one.
    $text=$Value | ConvertTo-Json -Depth 30
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($text)
    $pending=$Path+'.'+[guid]::NewGuid().ToString('N')+'.pending'
    $stream=$null
    try {
        $stream=[IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true); $stream.Dispose(); $stream=$null
        if([IO.File]::Exists($Path)) { [IO.File]::Replace($pending,$Path,[Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($pending,$Path) }
    } finally { if($null -ne $stream) { $stream.Dispose() }; if([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) } }
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
function Assert-NotCancelled([string]$RunDirectory,[string]$CancellationPath='') {
    if([IO.File]::Exists((Join-Path $RunDirectory 'cancel')) -or ($CancellationPath -and [IO.File]::Exists($CancellationPath))) { throw 'Cancelled' }
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
function Get-FormulaSignature([object]$Value) {
    # Load only in processes that compute workbook signatures. The controller
    # and batch preflight do not pay for a C# compilation they do not use.
    if(-not ('ExcelPasswordSafe.FormulaSignatureV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
public static class EpsWindow
{
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
namespace ExcelPasswordSafe
{
    public static class FormulaSignatureV1
    {
        public static string Compute(object value)
        {
            using (var hash = SHA256.Create())
            using (var crypto = new CryptoStream(Stream.Null, hash, CryptoStreamMode.Write))
            using (var buffer = new BufferedStream(crypto, 65536))
            using (var writer = new BinaryWriter(buffer, Encoding.UTF8, true))
            {
                WriteText(writer, "EPS-FORMULA-SHA256-V1");
                WriteValue(writer, value, 0);
                writer.Flush(); buffer.Flush(); crypto.FlushFinalBlock();
                return BitConverter.ToString(hash.Hash).Replace("-", "");
            }
        }
        static void WriteText(BinaryWriter writer, string value)
        {
            // Length followed by UTF-16 code units is unambiguous and retains
            // even an unmatched surrogate without replacement or normalization.
            writer.Write(value.Length);
            for (int i = 0; i < value.Length; i++) writer.Write((ushort)value[i]);
        }
        static bool SupportedElementType(Type type)
        {
            if (type == typeof(object) || type == typeof(DBNull) || type == typeof(ErrorWrapper)) return true;
            if (type.IsArray) return SupportedElementType(type.GetElementType());
            return !type.IsEnum && Type.GetTypeCode(type) != TypeCode.Object;
        }
        static void WriteValue(BinaryWriter writer, object value, int depth)
        {
            if (depth > 64) throw new InvalidOperationException("UnsupportedFormulaValueDepth");
            if (value == null) { writer.Write((byte)0); return; }
            if (value == DBNull.Value) { writer.Write((byte)1); return; }
            Type type = value.GetType();
            var array = value as Array;
            if (array != null)
            {
                Type elementType = type.GetElementType();
                if (!SupportedElementType(elementType)) throw new InvalidOperationException("UnsupportedFormulaArrayType");
                writer.Write((byte)18); WriteText(writer, elementType.FullName);
                writer.Write(array.Rank);
                for (int dimension = 0; dimension < array.Rank; dimension++)
                {
                    writer.Write(array.GetLowerBound(dimension)); writer.Write(array.GetLength(dimension));
                }
                foreach (object item in array) WriteValue(writer, item, depth + 1);
                return;
            }
            var error = value as ErrorWrapper;
            if (error != null) { writer.Write((byte)17); writer.Write(error.ErrorCode); return; }
            if (type.IsEnum) throw new InvalidOperationException("UnsupportedFormulaValueType");
            switch (Type.GetTypeCode(type))
            {
                case TypeCode.String: writer.Write((byte)2); WriteText(writer, (string)value); return;
                case TypeCode.Boolean: writer.Write((byte)3); writer.Write((bool)value); return;
                case TypeCode.SByte: writer.Write((byte)4); writer.Write((sbyte)value); return;
                case TypeCode.Byte: writer.Write((byte)5); writer.Write((byte)value); return;
                case TypeCode.Int16: writer.Write((byte)6); writer.Write((short)value); return;
                case TypeCode.UInt16: writer.Write((byte)7); writer.Write((ushort)value); return;
                case TypeCode.Int32: writer.Write((byte)8); writer.Write((int)value); return;
                case TypeCode.UInt32: writer.Write((byte)9); writer.Write((uint)value); return;
                case TypeCode.Int64: writer.Write((byte)10); writer.Write((long)value); return;
                case TypeCode.UInt64: writer.Write((byte)11); writer.Write((ulong)value); return;
                case TypeCode.Single: writer.Write((byte)12); writer.Write((float)value); return;
                case TypeCode.Double: writer.Write((byte)13); writer.Write((double)value); return;
                case TypeCode.Decimal: writer.Write((byte)14); writer.Write((decimal)value); return;
                case TypeCode.DateTime:
                    var date = (DateTime)value;
                    writer.Write((byte)15); writer.Write(date.Ticks); writer.Write((byte)date.Kind); return;
                case TypeCode.Char: writer.Write((byte)16); writer.Write((ushort)(char)value); return;
                default: throw new InvalidOperationException("UnsupportedFormulaValueType");
            }
        }
    }
}
'@
    }
    [ExcelPasswordSafe.FormulaSignatureV1]::Compute($Value)
}
# Formula/constant values, sheet identity, visibility, shape and OLE inventory.
# This is a semantic guard, NOT proof of byte-identical object payloads or rendering.
function Get-WorkbookSignature($Book) {
    $sheets=$null; $records=New-Object 'System.Collections.Generic.List[object]'
    try {
        $sheets=$Book.Sheets
        $sheetCount=[int]$sheets.Count
        for($i=1;$i -le $sheetCount;$i++) {
            $sheet=$null; $range=$null; $rows=$null; $columns=$null; $shapes=$null
            try {
                $sheet=$sheets.Item($i)
                $row=[ordered]@{name=[string]$sheet.Name;type=[int]$sheet.Type;visible=[int]$sheet.Visible;shapes=@()}
                if($row.type -in @(3,4)) { throw 'Excel4MacroSheetNotSupported' }
                if($row.type -eq -4167) {
                    $range=$sheet.UsedRange
                    # One bulk COM read; hash the typed values without creating
                    # a complete CLI XML string and another UTF-8 byte array.
                    $row.formulaSha=Get-FormulaSignature $range.Formula
                    $rows=$range.Rows; $columns=$range.Columns
                    $row.bounds=@([int]$range.Row,[int]$range.Column,[int]$rows.Count,[int]$columns.Count)
                }
                $shapes=$sheet.Shapes; $inventory=@()
                $shapeCount=[int]$shapes.Count
                for($j=1;$j -le $shapeCount;$j++) {
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

function Test-ProcessIdentity([int]$ProcessId,[string]$StartTicks) {
    $process=$null
    try {
        $process=[Diagnostics.Process]::GetProcessById($ProcessId)
        return -not $process.HasExited -and $process.StartTime.ToUniversalTime().Ticks.ToString() -ceq $StartTicks
    } catch { return $false }
    finally { if($null -ne $process) { $process.Dispose() } }
}

function Invoke-GuardedReplace([string]$Source,[string]$Temp,[string]$Backup,[string]$Recovery,[string]$SourceHash,[string]$TempHash,$HeldStream) {
    if((Get-Sha $Temp) -ne $TempHash) { throw 'TempChanged' }
    if((Get-Sha $Source) -ne $SourceHash -or (Get-StreamSha $HeldStream) -ne $SourceHash) { throw 'SourceChanged' }
    if((Get-Sha $Backup) -ne $SourceHash) { throw 'BackupChanged' }
    [IO.File]::Replace($Temp,$Source,$Recovery,$false)
    $verifiedHash=Get-Sha $Source
    if($verifiedHash -ne $TempHash -or (Get-Sha $Recovery) -ne $SourceHash) { throw 'PostReplaceHashMismatch' }
    $verifiedHash
}
