[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$CertificateThumbprint,
    [string]$SignTool
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'package-common.ps1')
$package = Get-ImageCopySavePackage $PackagePath ''
if ($package.SignaturePresent) { throw 'Input must be the unsigned evaluation package. Existing signatures are not overwritten.' }
$certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint) -ErrorAction Stop
if ($certificate.Subject -cne $package.Publisher) { throw 'Certificate subject must exactly match the package Publisher. Rebuild with -Publisher set to the authorized certificate subject.' }
if (-not $certificate.HasPrivateKey -or $certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date)) { throw 'An unexpired code-signing certificate with its private key is required.' }
if (@($certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' }).Count -ne 1) { throw 'Certificate does not explicitly permit code signing.' }
$destination = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($destination) -ine '.msix' -or (Test-Path -LiteralPath $destination)) { throw 'Output must be a new .msix path; existing files are never replaced.' }
if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($destination)) -PathType Container)) { throw 'Create the intended output directory first.' }
$executable = Resolve-ImageCopySaveSdkTool 'SignTool.exe' $SignTool
if ($PSCmdlet.ShouldProcess($destination, 'Create and sign a copy using the explicitly selected existing certificate')) {
    [IO.File]::Copy($package.Path, $destination, $false)
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $package.Sha256) { throw 'Input package changed before the signing copy was prepared. Nothing was signed.' }
    & $executable sign /fd SHA256 /s My /sha1 $CertificateThumbprint $destination | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Signing failed. The original unsigned input was preserved; inspect the incomplete output at $destination." }
    $signed = Get-ImageCopySavePackage $destination $package.Publisher
    Assert-ImageCopySaveTrustedSignature $signed $executable
    Write-Warning 'Evaluation package signed without an external timestamp. Certificate validity still limits future installs. Installation and Explorer G0 remain NOT RUN.'
    $signed
}
