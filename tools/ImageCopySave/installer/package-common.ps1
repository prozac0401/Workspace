Set-StrictMode -Version 2.0

function Resolve-ImageCopySaveSdkTool([string]$Name, [string]$ExplicitPath) {
    if ($ExplicitPath) { return (Get-Command $ExplicitPath -CommandType Application -ErrorAction Stop).Source }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $sdkBins = @((Join-Path $PSScriptRoot '../../../.tools/image-copy-save-native/sdk/bin'), (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits/10/bin'))
    foreach ($sdkBin in $sdkBins) {
        if (Test-Path -LiteralPath $sdkBin) {
            foreach ($version in Get-ChildItem -LiteralPath $sdkBin -Directory | Sort-Object Name -Descending) {
                $candidate = Join-Path $version.FullName ('x64/' + $Name)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
            }
        }
    }
    throw "$Name was not found. Pass its existing Windows SDK x64 path explicitly. No tools or certificates were installed."
}

function Get-ImageCopySavePackage([string]$Path, [string]$ExpectedPublisher) {
    $fullPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if ([IO.Path]::GetExtension($fullPath) -ine '.msix') { throw 'Expected one .msix package.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($fullPath)
    try {
        $entries = @($zip.Entries | Where-Object { $_.FullName -ceq 'AppxManifest.xml' })
        if ($entries.Count -ne 1 -or $entries[0].Length -gt 1048576) { throw 'Expected one bounded package manifest.' }
        $stream = $entries[0].Open()
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($stream, $settings)
        try { $manifest = New-Object Xml.XmlDocument; $manifest.XmlResolver = $null; $manifest.Load($reader) }
        finally { $reader.Dispose(); $stream.Dispose() }
        $ns = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
        $ns.AddNamespace('f', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
        $identity = $manifest.SelectSingleNode('/f:Package/f:Identity', $ns)
        if ($null -eq $identity -or $identity.Name -cne 'ImageCopySave.Evaluation' -or $identity.ProcessorArchitecture -cne 'x64') { throw 'This is not the expected ImageCopySave x64 evaluation package.' }
        if ($ExpectedPublisher -and $identity.Publisher -cne $ExpectedPublisher) { throw 'Package publisher differs from the explicitly expected publisher.' }
        $signatureCount = @($zip.Entries | Where-Object { $_.FullName -ceq 'AppxSignature.p7x' }).Count
        if ($signatureCount -gt 1) { throw 'Duplicate package signatures are not accepted.' }
        return [pscustomobject]@{
            Path = $fullPath; Name = [string]$identity.Name; Publisher = [string]$identity.Publisher
            Version = [string]$identity.Version; Architecture = [string]$identity.ProcessorArchitecture
            SignaturePresent = ($signatureCount -eq 1); Sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
            ProductionRelease = $false
        }
    } finally { $zip.Dispose() }
}

function Assert-ImageCopySaveTrustedSignature($Package, [string]$SignTool) {
    if (-not $Package.SignaturePresent) { throw 'The package is unsigned. Signing with an already trusted code-signing certificate is required before installation.' }
    $executable = Resolve-ImageCopySaveSdkTool 'SignTool.exe' $SignTool
    & $executable verify /pa /all /v $Package.Path | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Package signature verification failed. Certificate trust and installation policy must be resolved by the responsible PC administrator; no bypass was attempted.' }
    if ((Get-FileHash -LiteralPath $Package.Path -Algorithm SHA256).Hash -ne $Package.Sha256) { throw 'Package changed during signature verification.' }
}
