[CmdletBinding()]
param([ValidateSet('Inspect','EnableModern','Restore')][string]$Action = 'Inspect')
# Developer UI acceptance only. Never invoked by the product installer.
# RegRenameKey preserves the existing key instead of copying and deleting it.
# No ACL setters, Explorer termination, clipboard or product registration.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
function Initialize-NativeRename {
    if (-not ('ImageCopySave.Tests.NativeRegistryRename' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace ImageCopySave.Tests {
    public static class NativeRegistryRename {
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
        public static extern int RegRenameKey(SafeRegistryHandle key, string subKey, string newName);
    }
}
'@
    }
}
function Get-OverrideSnapshot([string]$ParentRelative,[string]$Name) {
    if ($Name -match '[\\/]' -or -not $Name) { throw 'Expected one registry key name.' }
    $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key=$hive.OpenSubKey($ParentRelative+'\'+$Name,$false)
        if ($null -eq $key) { return $null }
        try {
            if ($key.GetValueNames().Count -ne 0 -or $key.GetSubKeyNames().Count -ne 1 -or $key.GetSubKeyNames()[0] -cne 'InprocServer32') { throw 'Unknown customization in override; preserve it.' }
            $child=$key.OpenSubKey('InprocServer32',$false)
            try {
                if ($child.GetSubKeyNames().Count -ne 0 -or $child.GetValueNames().Count -ne 1 -or $child.GetValueNames()[0] -cne '' -or $child.GetValueKind('') -ne [Microsoft.Win32.RegistryValueKind]::String -or $child.GetValue('') -cne '') { throw 'Unexpected override content; preserve it.' }
                $sections=[Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access
                return [pscustomobject][ordered]@{ securitySections='Owner,Group,DACL'; rootSecurity=$key.GetAccessControl($sections).GetSecurityDescriptorSddlForm($sections); childSecurity=$child.GetAccessControl($sections).GetSecurityDescriptorSddlForm($sections); childName='InprocServer32'; defaultValue=''; defaultKind='String' }
            } finally { $child.Dispose() }
        } finally { $key.Dispose() }
    } finally { $hive.Dispose() }
}
function Assert-SameSnapshot([object]$Actual,[object]$Expected) {
    if ($null -eq $Actual -or $null -eq $Expected) { throw 'Expected override snapshot is missing.' }
    foreach ($property in @('securitySections','rootSecurity','childSecurity','childName','defaultValue','defaultKind')) {
        if ([string]$Actual.$property -cne [string]$Expected.$property) { throw 'Override content or security descriptor changed externally; preserve it.' }
    }
}
function Rename-ExactOverride([string]$ParentRelative,[string]$From,[string]$To,[object]$Expected) {
    if (-not $From -or -not $To -or $From -eq $To -or $From -match '[\\/]' -or $To -match '[\\/]') { throw 'Expected distinct immediate registry key names.' }
    Initialize-NativeRename
    Assert-SameSnapshot (Get-OverrideSnapshot $ParentRelative $From) $Expected
    $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
    try {
        $parentKey=$hive.OpenSubKey($ParentRelative,$true)
        if ($null -eq $parentKey) { throw 'Expected registry parent is missing.' }
        try {
            $collision=$parentKey.OpenSubKey($To,$false)
            if ($null -ne $collision) { $collision.Dispose(); throw 'Destination exists; neither registry key was overwritten.' }
            $code=[ImageCopySave.Tests.NativeRegistryRename]::RegRenameKey($parentKey.Handle,$From,$To)
            if ($code -ne 0) { throw (New-Object ComponentModel.Win32Exception($code)) }
        } finally { $parentKey.Dispose() }
    } finally { $hive.Dispose() }
    Assert-SameSnapshot (Get-OverrideSnapshot $ParentRelative $To) $Expected
    if ($null -ne (Get-OverrideSnapshot $ParentRelative $From)) { throw 'Source key was recreated externally; both keys were preserved.' }
}
function Key-Exists([string]$ParentRelative,[string]$Name) {
    $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
    try { $key=$hive.OpenSubKey($ParentRelative+'\'+$Name,$false); if ($null -eq $key) { return $false }; $key.Dispose(); return $true } finally { $hive.Dispose() }
}
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$output=[IO.Path]::GetFullPath((Join-Path $root 'artifacts/classic-validation-20260927'))
if (-not $output.StartsWith(($root+'\artifacts\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Report directory escaped the worktree artifacts.' }
$ancestor=$output
while ($ancestor -ne $root) {
    $item=Get-Item -LiteralPath $ancestor -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Report directories may not traverse reparse points.' }
    $ancestor=[IO.Path]::GetDirectoryName($ancestor)
}
[IO.Directory]::CreateDirectory($output) | Out-Null
$parent='Software\Classes\CLSID'
$name='{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$saved=$name+'.ImageCopySaveTestBackup'
$journalPath=Join-Path $output 'menu-mode-restore-state.json'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$encoding=New-Object Text.UTF8Encoding($false)
$record=[ordered]@{ action=$Action; status='RUNNING'; startedUtc=[DateTime]::UtcNow.ToString('o'); originalPresent=(Key-Exists $parent $name); backupPresent=(Key-Exists $parent $saved); changed=$false; renameApi='RegRenameKey'; renameSecurityComparisonScope='Owner,Group,DACL'; securityModified=$false }
$journal=$null
try {
    if ($Action -eq 'EnableModern') {
        if ($record.backupPresent) { throw 'A previous backup exists; do not change either key.' }
        if ($record.originalPresent) {
            if (Test-Path -LiteralPath $journalPath) {
                $previous=Get-Content -LiteralPath $journalPath -Encoding UTF8 -Raw | ConvertFrom-Json
                if ($previous.status -ne 'RESTORED') { throw 'A previous incomplete restore journal exists; inspect it before another test.' }
            }
            $snapshot=Get-OverrideSnapshot $parent $name
            $journal=[ordered]@{ schemaVersion=1; sid=$sid; parent=$parent; original=$name; backup=$saved; status='PREPARED'; snapshot=$snapshot; preparedUtc=[DateTime]::UtcNow.ToString('o') }
            [IO.File]::WriteAllText($journalPath,($journal|ConvertTo-Json -Depth 6),$encoding)
            Rename-ExactOverride $parent $name $saved $snapshot
            $journal.status='MOVED'; $journal.movedUtc=[DateTime]::UtcNow.ToString('o')
            [IO.File]::WriteAllText($journalPath,($journal|ConvertTo-Json -Depth 6),$encoding)
            $record.changed=$true; $record.securityPreserved=$true
        }
    } elseif ($Action -eq 'Restore') {
        if ($record.backupPresent) {
            if ($record.originalPresent) { throw 'Original key was recreated externally; preserve both keys.' }
            if (-not (Test-Path -LiteralPath $journalPath)) { throw 'Restore ownership/security journal is missing; preserve the backup.' }
            $journal=Get-Content -LiteralPath $journalPath -Encoding UTF8 -Raw | ConvertFrom-Json
            if ($journal.schemaVersion -ne 1 -or $journal.sid -ne $sid -or $journal.parent -cne $parent -or $journal.original -cne $name -or $journal.backup -cne $saved -or $journal.status -notin @('PREPARED','MOVED')) { throw 'Restore journal does not describe this exact user and key.' }
            Rename-ExactOverride $parent $saved $name $journal.snapshot
            $journal.status='RESTORED'
            [IO.File]::WriteAllText($journalPath,($journal|ConvertTo-Json -Depth 6),$encoding)
            $record.changed=$true; $record.securityPreserved=$true
        } elseif (Test-Path -LiteralPath $journalPath) {
            $previous=Get-Content -LiteralPath $journalPath -Encoding UTF8 -Raw | ConvertFrom-Json
            if ($previous.status -eq 'MOVED') { throw 'The recorded backup is missing; restoration was not claimed.' }
        }
    }
    $record.status='PASS'
} catch { $record.status='FAIL'; $record.error=$_.Exception.Message; throw }
finally {
    $record.originalPresentAfter=Key-Exists $parent $name
    $record.backupPresentAfter=Key-Exists $parent $saved
    $record.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $path=Join-Path $output ('menu-mode-'+$Action+'-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.json')
    [IO.File]::WriteAllText($path,($record|ConvertTo-Json -Depth 6),$encoding)
    $record | ConvertTo-Json -Depth 6
}
