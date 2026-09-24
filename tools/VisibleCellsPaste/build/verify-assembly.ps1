[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$arch=[IO.Path]::GetFileName($AssemblyPath)
$assembly=[Reflection.Assembly]::ReflectionOnlyLoadFrom((Resolve-Path -LiteralPath $AssemblyPath).Path)
            foreach($reference in $assembly.GetReferencedAssemblies()) { [Reflection.Assembly]::ReflectionOnlyLoad($reference.FullName) | Out-Null }
            $addin=$assembly.GetType('VisibleCellsPaste.AddIn',$true)
            $guid=@($addin.GetCustomAttributesData() | Where-Object { $_.AttributeType.FullName -eq 'System.Runtime.InteropServices.GuidAttribute' })
            $progId=@($addin.GetCustomAttributesData() | Where-Object { $_.AttributeType.FullName -eq 'System.Runtime.InteropServices.ProgIdAttribute' })
            if($guid.Count -ne 1 -or [string]$guid[0].ConstructorArguments[0].Value -ne '856B2219-6225-42ED-8FF1-2D06E5913AC8'){throw "Wrong add-in CLSID: $arch"}
            if($progId.Count -ne 1 -or [string]$progId[0].ConstructorArguments[0].Value -ne 'Workspace.VisibleCellsPaste'){throw "Wrong add-in ProgID: $arch"}
            foreach($interfaceName in @('IDTExtensibility2','IRibbonExtensibility','ICallbacks')) {
                $interface=$assembly.GetType(('VisibleCellsPaste.'+$interfaceName),$true)
                $kind=@($interface.GetCustomAttributesData() | Where-Object { $_.AttributeType.FullName -eq 'System.Runtime.InteropServices.InterfaceTypeAttribute' })
                if(-not $interface.IsInterface -or $kind.Count -ne 1 -or [int]$kind[0].ConstructorArguments[0].Value -ne 0){throw "COM interface is not dual: $interfaceName / $arch"}
            }
            # GetCustomUI intentionally returns one literal. Resolve its ldstr metadata
            # rather than creating the COM class or executing any add-in/Excel code.
            $method=$addin.GetMethod('GetCustomUI')
            $il=$method.GetMethodBody().GetILAsByteArray()
            if($il.Length -ne 6 -or $il[0] -ne 0x72 -or $il[5] -ne 0x2a){throw 'GetCustomUI is no longer a single literal; review static extraction before packaging.'}
            $ribbon=$method.Module.ResolveString([BitConverter]::ToInt32($il,1))
            $xml=New-Object Xml.XmlDocument
            $xml.XmlResolver=$null
            $xml.LoadXml($ribbon)
            $buttons=@($xml.SelectNodes("//*[local-name()='button']"))
            $ids=@($buttons | ForEach-Object { $_.GetAttribute('id') })
            if($buttons.Count -ne 4 -or ($ids | Select-Object -Unique).Count -ne 4){throw 'Ribbon IDs must be four unique product-owned buttons.'}
            foreach($button in $buttons) {
                $id=$button.GetAttribute('id');$tag=$button.GetAttribute('tag');$callback=$button.GetAttribute('onAction')
                if(-not $id.StartsWith('VCPVisibleCellsPaste',[StringComparison]::Ordinal)){throw "Foreign Ribbon ID: $id"}
                if($callback -notin @('Paste','Undo') -or $tag -ne ('VCP.VisibleCellsPaste.'+$callback+'.v1')){throw "Ribbon tag/callback mismatch: $id"}
                $action=$addin.GetMethod($callback)
                $callbackInterface=$assembly.GetType('VisibleCellsPaste.ICallbacks',$true).GetMethod($callback)
                if($null -eq $action -or $action.GetParameters().Count -ne 1 -or $null -eq $callbackInterface){throw "Missing COM-visible Ribbon callback: $callback"}
            }
            $engine=$assembly.GetType('VisibleCellsPaste.ExcelEngine',$true)
            foreach($faultField in @('FailAfterWrites','FailRecoveryAt','CancelAfterWrite')) {
                if ($null -ne $engine.GetField($faultField,[Reflection.BindingFlags]'Public,NonPublic,Instance,Static')) { throw "Fault injection field leaked into release $arch : $faultField" }
            }
Write-Output "PASS static COM/Ribbon/fault-exclusion metadata: $arch"
