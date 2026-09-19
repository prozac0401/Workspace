[CmdletBinding()]
param([ValidateRange(0,255)][int]$ExitCode,[string]$Message,[switch]$ShowPathExt)
# Synthetic child-process fixture. No Excel, installation or registry calls.
Write-Output $Message
if($ShowPathExt) { Write-Output ('PATHEXT='+$env:PATHEXT) }
[Console]::Error.WriteLine('synthetic stderr '+$ExitCode)
exit $ExitCode
