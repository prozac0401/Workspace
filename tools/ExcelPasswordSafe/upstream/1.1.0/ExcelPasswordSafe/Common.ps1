Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Write-Json($Value, [string]$Path) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
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
function Get-Candidates([string]$Root) {
    $queue=New-Object 'System.Collections.Generic.Queue[string]'; $queue.Enqueue($Root)
    while($queue.Count) {
        $dir=$queue.Dequeue()
        foreach($item in Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if($item.PSIsContainer) { $queue.Enqueue($item.FullName); continue }
            if($item.Name.StartsWith('~$') -or $item.Name.StartsWith('.eps-')) { continue }
            if($item.Extension.ToLowerInvariant() -in @('.xls','.xlsx','.xlsm','.xlsb')) { $item.FullName }
        }
    }
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
