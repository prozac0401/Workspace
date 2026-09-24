[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ZipPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$resolved = (Resolve-Path -LiteralPath $ZipPath).Path
$archive = [IO.Compression.ZipFile]::OpenRead($resolved)
try {
    $names = @($archive.Entries | ForEach-Object FullName)
    if (($names | Select-Object -Unique).Count -ne $names.Count) { throw 'Duplicate archive entry.' }
    $allowed = @('Install.cmd','Uninstall.cmd','VisibleCellsPaste.Setup.exe','version.txt','README.md','CHANGELOG.md','build-manifest.json','SHA256SUMS.txt','x86/VisibleCellsPaste.AddIn.dll','x64/VisibleCellsPaste.AddIn.dll','docs/architecture.md','docs/clipboard-compatibility.md','docs/undo-safety.md','docs/install-security.md','docs/test-report.md','docs/release-checklist.md','docs/native-format-research.md')
    if (@(Compare-Object ($allowed | Sort-Object) ($names | Sort-Object)).Count -ne 0) { throw 'Archive inventory differs from the explicit approved files.' }
    $hashEntry = $archive.GetEntry('SHA256SUMS.txt')
    $reader = New-Object IO.StreamReader($hashEntry.Open())
    try { $hashText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $checked = @()
    foreach ($line in ($hashText -split '\r?\n' | Where-Object { $_ -ne '' })) {
        if ($line -notmatch '^([a-f0-9]{64})  (.+)$') { throw 'Invalid SHA256SUMS line.' }
        $expected = $Matches[1]; $name = $Matches[2]
        $entry = $archive.GetEntry($name)
        if ($null -eq $entry) { throw "Hash entry missing from ZIP: $name" }
        $entryStream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-','').ToLowerInvariant() }
        finally { $sha.Dispose(); $entryStream.Dispose() }
        if ($expected -ne $actual) { throw "Hash mismatch: $name" }
        $checked += $name
    }
    if (@(Compare-Object (($names | Where-Object { $_ -ne 'SHA256SUMS.txt' }) | Sort-Object) ($checked | Sort-Object)).Count -ne 0) { throw 'Hash inventory incomplete.' }
    foreach ($arch in @('x86','x64')) {
        $entry = $archive.GetEntry("$arch/VisibleCellsPaste.AddIn.dll")
        $stream = $entry.Open(); $memory = New-Object IO.MemoryStream
        try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
        $memory.Position = 0; $binary = New-Object IO.BinaryReader($memory)
        try {
            if ($binary.ReadUInt16() -ne 0x5a4d) { throw "Invalid DOS header: $arch" }
            $memory.Position=0x3c; $offset=$binary.ReadInt32(); $memory.Position=$offset
            if ($binary.ReadUInt32() -ne 0x4550) { throw "Invalid PE header: $arch" }
            $machine=$binary.ReadUInt16()
            if (($arch -eq 'x86' -and $machine -ne 0x14c) -or ($arch -eq 'x64' -and $machine -ne 0x8664)) { throw "Wrong PE architecture: $arch" }
            # CLR reflection-only cannot load two architecture images with the same
            # identity into one AppDomain. Inspect each in an isolated PowerShell process.
            $inspectionDll=Join-Path ([IO.Path]::GetDirectoryName($resolved)) ('metadata-'+$arch+'-'+[Guid]::NewGuid().ToString('N')+'.dll')
            [IO.File]::WriteAllBytes($inspectionDll,$memory.ToArray())
            try {
                $process=New-Object Diagnostics.Process
                $info=New-Object Diagnostics.ProcessStartInfo
                $info.FileName=Join-Path $PSHOME 'powershell.exe'
                $arguments=@('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'verify-assembly.ps1'),'-AssemblyPath',$inspectionDll)
                $info.Arguments=[string]::Join(' ',@($arguments|ForEach-Object{'"'+($_ -replace '"','\"')+'"'}))
                $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
                $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$process.StartInfo=$info
                try {
                    if(-not $process.Start()){throw 'Metadata verifier did not start.'}
                    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$process.WaitForExit()
                    $result=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
                    if($process.ExitCode -ne 0){throw "Metadata verifier failed: $result"}
                    Write-Output $result.TrimEnd()
                }finally{$process.Dispose()}
            }finally{if([IO.File]::Exists($inspectionDll)){[IO.File]::Delete($inspectionDll)}}
        } finally { $binary.Dispose(); $memory.Dispose() }
    }
    Write-Output "PASS package inventory, 16 file hashes, x86/x64 PE architecture, COM identities/dual interfaces, Ribbon callbacks/IDs/tags, no fault injection fields: $resolved"
    Write-Output 'Actual Excel loading and signed/approved distribution status must be recorded separately.'
} finally { $archive.Dispose() }
