#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$file = (Resolve-Path -LiteralPath $MsiPath).Path
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($file,0)
function Query([string]$Sql,[int]$Columns) {
    $view=$database.OpenView($Sql)
    try {
        [void]$view.Execute(); $rows=@()
        while ($row=$view.Fetch()) {
            $values=@(); for($i=1;$i -le $Columns;$i++) { $values += $row.StringData($i) }
            $rows += ,$values
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($row)
        }
        return ,$rows
    } finally { [void]$view.Close(); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) }
}
try {
    $properties=@{}
    foreach($row in (Query 'SELECT `Property`, `Value` FROM `Property`' 2)) { $properties[$row[0]]=$row[1] }
    if($properties['ALLUSERS']) { throw 'The package is not per-user.' }
    $supportsBackground=[version]$properties['ProductVersion'] -ge [version]'2.0.0'
    $expectedProductName=if($supportsBackground) {'ExcelPasswordSafe '+([version]$properties['ProductVersion']).Major} else {'ExcelPasswordSafe'}
    if($properties['ProductName'] -ne $expectedProductName) { throw 'Unexpected product name.' }
    if($properties['UpgradeCode'] -ne '{0E60B57C-21DA-41A5-8FAC-6CCDF41EB62C}') { throw 'Unexpected upgrade identity.' }
    $supportsFolder=[version]$properties['ProductVersion'] -ge [version]'1.4.0'
    $fileKeyPattern='^Software\\Classes\\SystemFileAssociations\\\.(xls|xlsx|xlsm|xlsb)\\shell\\Workspace\.ExcelPasswordSafe($|\\command$)'
    if($supportsBackground) { $fileKeyPattern='^Software\\Classes\\SystemFileAssociations\\\.(xls|xlsx|xlsm|xlsb)\\shell\\Workspace\.ExcelPasswordSafe($|\\shell\\(01Encrypt|02Decrypt|03ChangePassword)($|\\command$))' }
    $folderKeyPattern='^Software\\Classes\\Directory\\shell\\Workspace\.ExcelPasswordSafe($|\\shell\\(01Encrypt|02Decrypt|03ChangePassword)($|\\command$))'
    $backgroundKeyPattern='^Software\\Classes\\Directory\\Background\\shell\\Workspace\.ExcelPasswordSafe($|\\shell\\(01Encrypt|02Decrypt|03ChangePassword)($|\\command$))'
    $registry=Query 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`' 4
    foreach($row in $registry) {
        if($row[0] -ne '1') { throw 'Non-HKCU registry write found.' }
        $owned=($row[1] -match '^Software\\Workspace\\ExcelPasswordSafe($|\\)') -or ($row[1] -match $fileKeyPattern) -or ($supportsFolder -and $row[1] -match $folderKeyPattern) -or ($supportsBackground -and $row[1] -match $backgroundKeyPattern)
        if(-not $owned) { throw ('Unexpected registry ownership scope: '+$row[1]) }
    }
    $commands=@($registry | Where-Object { $_[1] -match '\\command$' })
    $fileCommands=@($commands | Where-Object { $_[1] -match $fileKeyPattern })
    $folderCommands=@($commands | Where-Object { $_[1] -match $folderKeyPattern })
    $backgroundCommands=@($commands | Where-Object { $_[1] -match $backgroundKeyPattern })
    $expectedBackgroundCommands=if($supportsBackground) {3} else {0}
    $expectedFolderCommands=if($supportsFolder) {3} else {0}
    $expectedFileCommands=if($supportsBackground) {12} else {4}
    if($fileCommands.Count -ne $expectedFileCommands -or $folderCommands.Count -ne $expectedFolderCommands -or $backgroundCommands.Count -ne $expectedBackgroundCommands -or $commands.Count -ne ($expectedFileCommands+$expectedFolderCommands+$expectedBackgroundCommands)) { throw 'Unexpected file/folder command count.' }
    if(-not $supportsBackground) { foreach($row in $fileCommands) { if($row[3] -cne '"[INSTALLFOLDER]ExcelPasswordSafe.exe" --file "%1"') { throw 'Unexpected or unquoted file command.' } } }
    foreach($extension in @('.xls','.xlsx','.xlsm','.xlsb')) {
        $key='Software\Classes\SystemFileAssociations\'+$extension+'\shell\Workspace.ExcelPasswordSafe'
        if(@($registry | Where-Object { $_[1] -eq $key -and $_[2] -eq 'MultiSelectModel' -and $_[3] -eq 'Single' }).Count -ne 1) { throw ('Single-file menu model missing: '+$extension) }
    }
    $menus=@()
    if($supportsBackground) {
        foreach($extension in @('.xls','.xlsx','.xlsm','.xlsb')) {
            $key='Software\Classes\SystemFileAssociations\'+$extension+'\shell\Workspace.ExcelPasswordSafe'
            if(@($registry | Where-Object { $_[1] -ceq ($key+'\command') }).Count) { throw 'Obsolete single-file root command must not be authored.' }
            $menus+=@{key=$key;argument='%1';commands=$fileCommands;kind='file'}
        }
    }
    if($supportsFolder) { $menus+=@{key='Software\Classes\Directory\shell\Workspace.ExcelPasswordSafe';argument='%1';commands=$folderCommands;kind='folder'} }
    if($supportsBackground) { $menus+=@{key='Software\Classes\Directory\Background\shell\Workspace.ExcelPasswordSafe';argument='%V\.';commands=$backgroundCommands;kind='folder'} }
    foreach($menu in $menus) {
        $folderKey=$menu.key
        if(@($registry | Where-Object { $_[1] -ceq $folderKey -and $_[2] -eq 'Icon' -and $_[3] -ceq '"[INSTALLFOLDER]ExcelPasswordSafe.exe",0' }).Count -ne 1) { throw 'Cascade padlock icon reference missing.' }
        foreach($pair in @(@('MUIVerb','Excel 암호 관리'),@('SubCommands',''),@('MultiSelectModel','Single'))) {
            if(@($registry | Where-Object { $_[1] -ceq $folderKey -and $_[2] -ceq $pair[0] -and $_[3] -ceq $pair[1] }).Count -ne 1) { throw ('Folder cascade value missing or incorrect: '+$pair[0]) }
        }
        $verbs=@(@{id='01Encrypt';mode='Encrypt';label='암호 설정'},@{id='02Decrypt';mode='Decrypt';label='암호 해제'},@{id='03ChangePassword';mode='ChangePassword';label='암호 변경'})
        foreach($verb in $verbs) {
            $key=$folderKey+'\shell\'+$verb.id
            $expectedCommand='"[INSTALLFOLDER]ExcelPasswordSafe.exe" --'+$menu.kind+' "'+$menu.argument+'" --mode '+$verb.mode
            if(@($menu.commands | Where-Object { $_[1] -ceq ($key+'\command') -and $_[3] -ceq $expectedCommand }).Count -ne 1) { throw ('Unexpected or unquoted folder command: '+$verb.mode) }
            if(@($registry | Where-Object { $_[1] -ceq $key -and $_[2] -ceq 'MUIVerb' -and $_[3] -ceq $verb.label }).Count -ne 1) { throw ('Folder action label missing: '+$verb.mode) }
            if(@($registry | Where-Object { $_[1] -ceq $key -and $_[2] -ceq 'MultiSelectModel' -and $_[3] -ceq 'Single' }).Count -ne 1) { throw ('Folder action selection model missing: '+$verb.mode) }
        }
    }
    $files=Query 'SELECT `FileName` FROM `File`' 1
    $names=@($files | ForEach-Object { ($_[0] -split '\|')[-1] } | Sort-Object)
    $expected=@('Common.ps1','Engine.ps1','ExcelPassword.Worker.ps1','ExcelPasswordSafe.exe','ExcelPasswordSafe.exe.config','README.md')
    if($supportsFolder) { $expected+='BatchEngine.ps1' }
    if([version]$properties['ProductVersion'] -ge [version]'4.0.0') { $expected+=@('ExcelPasswordSafe.Crypto.dll','THIRD-PARTY-NOTICES.txt') }
    $expected=@($expected | Sort-Object)
    if(($names -join '|') -cne ($expected -join '|')) { throw ('Unexpected MSI payload: '+($names -join ', ')) }
    if([version]$properties['ProductVersion'] -ge [version]'4.0.0') {
        $componentDirectories=@{}
        foreach($row in (Query 'SELECT `Component`, `Directory_` FROM `Component`' 2)) { $componentDirectories[$row[0]]=$row[1] }
        foreach($row in (Query 'SELECT `FileName`, `Component_` FROM `File`' 2)) {
            $name=($row[0] -split '\|')[-1]
            $expectedDirectory=if($name -eq 'ExcelPasswordSafe.Crypto.dll' -or $name -like '*.ps1') { 'RUNTIMEDIR' } else { 'INSTALLFOLDER' }
            if($componentDirectories[$row[1]] -cne $expectedDirectory) { throw ('Unexpected installed payload directory: '+$name) }
        }
    }
    $tables=Query 'SELECT `Name` FROM `_Tables`' 1
    if(@($tables | Where-Object { $_[0] -eq 'RemoveRegistry' }).Count) {
        $removals=Query 'SELECT `Root`, `Key`, `Name` FROM `RemoveRegistry`' 3
        if($removals.Count) { throw 'Unexpected explicit registry deletion. Uninstall must remove only authored values.' }
    }
    if(@($tables | Where-Object { $_[0] -eq 'CustomAction' }).Count) {
        $actions=Query 'SELECT `Action`, `Type`, `Source`, `Target` FROM `CustomAction`' 4
        foreach($action in $actions) {
            # WiX emits only SetProperty for remembering an existing installation.
            $known=($action[0] -eq 'SetINSTALLFOLDER' -and $action[2] -eq 'INSTALLFOLDER' -and $action[3] -eq '[SAVEDINSTALLFOLDER]' -and $action[1] -eq '51')
            if($supportsBackground) { $known=$known -or ($action[0] -eq 'SetARPINSTALLLOCATION' -and $action[2] -eq 'ARPINSTALLLOCATION' -and $action[3] -eq '[INSTALLFOLDER]' -and $action[1] -eq '51') }
            if(-not $known) { throw ('Unexpected executable/custom action: '+$action[0]) }
        }
    }
    if($supportsBackground) {
        if($properties['ARPPRODUCTICON'] -ne 'ExcelPasswordSafe.ico') { throw 'ARP icon missing.' }
        $icons=Query 'SELECT `Name` FROM `Icon`' 1
        if(@($icons | Where-Object { $_[0] -eq 'ExcelPasswordSafe.ico' }).Count -ne 1) { throw 'Padlock Icon table resource missing.' }
        $shortcuts=Query 'SELECT `Icon_`, `IconIndex` FROM `Shortcut`' 2
        if(@($shortcuts | Where-Object { $_[0] -eq 'ExcelPasswordSafe.ico' -and $_[1] -eq '0' }).Count -ne 1) { throw 'Shortcut icon missing.' }
        $controls=Query 'SELECT `Dialog_`, `Control`, `Type`, `Property`, `Text` FROM `Control`' 5
        if(@($controls | Where-Object { $_[0] -eq 'Welcome' -and $_[1] -eq 'FolderPath' -and $_[2] -eq 'PathEdit' -and $_[3] -eq 'INSTALLFOLDER' }).Count -ne 1) { throw 'Installation path input missing.' }
        if(@($controls | Where-Object { $_[0] -eq 'BrowseFolder' -and $_[2] -eq 'DirectoryList' -and $_[3] -eq 'INSTALLFOLDER' }).Count -ne 1) { throw 'Native folder browser missing.' }
        if(@($controls | Where-Object { $_[4] -match '평가|미서명|서명되지|ProductVersion|2\.0\.0' }).Count) { throw 'Technical/evaluation version text leaked into installer UI.' }
        $events=Query 'SELECT `Dialog_`, `Control_`, `Event`, `Argument`, `Condition`, `Ordering` FROM `ControlEvent`' 6
        foreach($pair in @(@('Welcome','Install'),@('BrowseFolder','UseFolder'))) {
            $ordered=@($events | Where-Object { $_[0] -eq $pair[0] -and $_[1] -eq $pair[1] })
            $validation=@($ordered | Where-Object { $_[2] -eq 'SetTargetPath' -and $_[3] -eq 'INSTALLFOLDER' -and $_[5] -eq '1' })
            $proceed=@($ordered | Where-Object { $_[2] -eq 'EndDialog' -and $_[3] -eq 'Return' -and $_[5] -eq '2' })
            if($validation.Count -ne 1 -or $proceed.Count -ne 1) { throw 'Native write-path validation must precede continuation.' }
        }
        if($properties['ErrorDialog'] -ne 'InstallerError') { throw 'Friendly MSI error dialog missing.' }
        $dialogs=Query 'SELECT `Dialog`, `Control_First` FROM `Dialog`' 2
        if(@($dialogs | Where-Object { $_[0] -eq 'InstallerError' -and $_[1] -eq 'ErrorText' }).Count -ne 1) { throw 'Installer ErrorText must be the first control.' }
        $errors=Query 'SELECT `Error`, `Message` FROM `Error`' 2
        if(@($errors | Where-Object { $_[0] -eq '1315' -and $_[1] -match '쓸 수' }).Count -ne 1) { throw 'Writable-folder error guidance missing.' }
        $conditions=Query 'SELECT `Dialog_`, `Control_`, `Action`, `Condition` FROM `ControlCondition`' 4
        foreach($control in @('FolderPath','Browse')) {
            if(@($conditions | Where-Object { $_[0] -eq 'Welcome' -and $_[1] -eq $control -and $_[2] -eq 'Disable' -and $_[3] -eq 'SAVEDINSTALLFOLDER' }).Count -ne 1) { throw 'Existing installation location must stay fixed.' }
        }
        foreach($sequence in @('InstallUISequence','InstallExecuteSequence')) {
            $saved=Query ('SELECT `Condition` FROM `'+$sequence+'` WHERE `Action`=''SetINSTALLFOLDER''') 1
            if($saved.Count -ne 1 -or $saved[0][0] -ne 'SAVEDINSTALLFOLDER') { throw 'Remembered path must override location changes during maintenance/upgrade.' }
        }
    }
    $summary=$database.SummaryInformation(0)
    try { $template=$summary.Property(7); $wordCount=[int]$summary.Property(15) } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary) }
    if($template -notmatch '^x64;') { throw 'Expected x64 MSI template.' }
    if(($wordCount -band 8) -ne 8) { throw 'Package is not marked for limited-user installation.' }
    [ordered]@{status='Pass';product=$properties['ProductName'];version=$properties['ProductVersion'];productCode=$properties['ProductCode'];upgradeCode=$properties['UpgradeCode'];fileCount=$files.Count;commands=$commands.Count;fileCommands=$fileCommands.Count;folderCommands=$folderCommands.Count;backgroundCommands=$backgroundCommands.Count;menuRoots=(4+[int]$supportsFolder+[int]$supportsBackground);folderCascade=$supportsFolder;fileCascade=$supportsBackground;backgroundCascade=$supportsBackground;customInstallLocation=$supportsBackground;perUser=$true;registry='HKCU only';template=$template;limitedUser=$true;signature=(Get-AuthenticodeSignature -LiteralPath $file).Status.ToString();sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash;productionRelease=$false} | ConvertTo-Json
} finally {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
}
