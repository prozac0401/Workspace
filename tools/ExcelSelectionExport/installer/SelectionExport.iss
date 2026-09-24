#ifndef PayloadDir
  #error PayloadDir is required; run scripts/build.ps1.
#endif
#ifndef ProductVersion
  #define ProductVersion "0.1.0-rc.9"
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#define ProductId "Workspace.ExcelSelectionExport"
#define ProductClsid "{2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1}"
#define ProductAssembly "ExcelSelectionExport.AddIn, Version=0.1.0.0, Culture=neutral, PublicKeyToken=null"
#define ClassKey "Software\Classes\CLSID\{" + ProductClsid
#define ProgKey "Software\Classes\" + ProductId
#define AddinKey "Software\Microsoft\Office\Excel\Addins\" + ProductId

[Setup]
AppId={#ProductId}
AppName=선택범위 내보내기
AppVersion={#ProductVersion}
AppVerName=선택범위 내보내기 {#ProductVersion} (서명되지 않은 평가판)
AppPublisher=Workspace
DefaultDirName={localappdata}\Workspace\ExcelSelectionExport
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
#if Arch == "x64"
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0.22000
WizardStyle=modern
SetupLogging=yes
CloseApplications=no
RestartApplications=no
AlwaysRestart=no
UninstallDisplayName=선택범위 내보내기
UninstallDisplayIcon={uninstallexe}
OutputBaseFilename=ExcelSelectionExport-{#ProductVersion}-{#Arch}-Setup
Compression=lzma2
SolidCompression=yes
VersionInfoVersion=0.1.0.0
VersionInfoDescription=선택범위 내보내기 평가판 설치 프로그램
VersionInfoProductName=선택범위 내보내기
AppMutex=Local\Workspace.ExcelSelectionExport.Setup

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Messages]
SetupWindowTitle=선택범위 내보내기 설치
ReadyLabel1=선택범위 내보내기 평가판을 설치할 준비가 되었습니다.
FinishedHeadingLabel=선택범위 내보내기 설치 완료
FinishedLabelNoIcons=새로 시작한 Excel에서 셀을 선택하고 우클릭 → 선택범위 내보내기 → 새 Excel로를 누르세요.%n%n열려 있던 Excel에는 바로 나타나지 않을 수 있습니다. 작업을 저장하고 Excel 창을 모두 닫았다가 다시 열어 주세요.%n%n이 파일은 서명되지 않은 평가판입니다. 조직의 추가 기능 승인 정책이 적용됩니다.
ConfirmUninstall=선택범위 내보내기를 제거할까요?%n%nExcel에서 작업을 저장하고 모든 Excel 창을 닫아 주세요.
UninstalledAll=선택범위 내보내기를 제거했습니다.

[Files]
Source: "{#PayloadDir}\ExcelSelectionExport.AddIn.dll"; DestDir: "{app}\versions\{#ProductVersion}\{#Arch}"; Flags: ignoreversion
Source: "{#PayloadDir}\SetupProbe.exe"; DestDir: "{app}\versions\{#ProductVersion}\{#Arch}"; Flags: ignoreversion
Source: "{#PayloadDir}\SetupProbe.exe"; Flags: dontcopy
Source: "{#PayloadDir}\README.md"; DestDir: "{app}\versions\{#ProductVersion}\{#Arch}"; Flags: ignoreversion
Source: "{#PayloadDir}\CHANGELOG.md"; DestDir: "{app}\versions\{#ProductVersion}\{#Arch}"; Flags: ignoreversion
Source: "{#PayloadDir}\product.id"; DestDir: "{app}"; Flags: ignoreversion

; Only product-owned values are removed. Unknown values/keys survive uninstall.
; The initial LoadBehavior is installed once; repair/update never resets it.
[Registry]
Root: HKCU; Subkey: "{#ClassKey}"; ValueType: string; ValueData: "ExcelSelectionExport.AddIn"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ClassKey}\ProgId"; ValueType: string; ValueData: "{#ProductId}"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32"; ValueType: string; ValueData: "mscoree.dll"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32"; ValueType: string; ValueName: "ThreadingModel"; ValueData: "Both"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32"; ValueType: string; ValueName: "Class"; ValueData: "ExcelSelectionExport.AddIn"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32"; ValueType: string; ValueName: "Assembly"; ValueData: "{#ProductAssembly}"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32"; ValueType: string; ValueName: "RuntimeVersion"; ValueData: "v4.0.30319"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32"; ValueType: string; ValueName: "CodeBase"; ValueData: "{code:AssemblyCodeBase}"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32\0.1.0.0"; ValueType: string; ValueName: "Class"; ValueData: "ExcelSelectionExport.AddIn"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32\0.1.0.0"; ValueType: string; ValueName: "Assembly"; ValueData: "{#ProductAssembly}"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32\0.1.0.0"; ValueType: string; ValueName: "RuntimeVersion"; ValueData: "v4.0.30319"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\InprocServer32\0.1.0.0"; ValueType: string; ValueName: "CodeBase"; ValueData: "{code:AssemblyCodeBase}"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#ClassKey}\Implemented Categories"; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ClassKey}\Implemented Categories\{{62C8FE65-4EBB-45E7-B440-6E39B2CDBF29}"; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ProgKey}"; ValueType: string; ValueData: "ExcelSelectionExport.AddIn"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ProgKey}\CLSID"; ValueType: string; ValueData: "{{#ProductClsid}"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#AddinKey}"; ValueType: string; ValueName: "FriendlyName"; ValueData: "선택범위 내보내기"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#AddinKey}"; ValueType: string; ValueName: "Description"; ValueData: "보이는 선택범위를 저장 전 새 통합문서로 만듭니다."; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#AddinKey}"; ValueType: dword; ValueName: "LoadBehavior"; ValueData: "3"; Flags: createvalueifdoesntexist uninsdeletevalue
Root: HKCU; Subkey: "Software\Workspace\ExcelSelectionExport"; ValueType: string; ValueName: "Owner"; ValueData: "{{#ProductClsid}"; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Workspace\ExcelSelectionExport"; ValueType: string; ValueName: "Architecture"; ValueData: "{#Arch}"; Flags: uninsdeletevalue

[Code]
const
  Identity = 'Workspace.ExcelSelectionExport.2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1';
var
  SetupMutex: THandle;
  IsUpgrade: Boolean;
  PostInstallFailure: String;

function CreateMutexW(Attributes: Integer; InitialOwner: Boolean; Name: String): THandle;
  external 'CreateMutexW@kernel32.dll stdcall';
function GetLastError: LongWord;
  external 'GetLastError@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function UrlCreateFromPathW(Path: String; Url: String; var Size: LongWord; Reserved: LongWord): Integer;
  external 'UrlCreateFromPathW@shlwapi.dll stdcall';

function ProductDirectory: String;
begin
  Result := ExpandConstant('{localappdata}\Workspace\ExcelSelectionExport');
end;

function PayloadDirectory: String;
begin
  Result := ProductDirectory + '\versions\{#ProductVersion}\{#Arch}';
end;

function AssemblyCodeBase(Param: String): String;
var Size: LongWord; Code: Integer;
begin
  Size := 32768;
  SetLength(Result, Size);
  Code := UrlCreateFromPathW(PayloadDirectory + '\ExcelSelectionExport.AddIn.dll', Result, Size, 0);
  if Code <> 0 then RaiseException('COM 등록에 필요한 파일 주소를 만들지 못했습니다.');
  SetLength(Result, Size);
end;

function AcquireLock: Boolean;
var ErrorCode: LongWord;
begin
  SetupMutex := CreateMutexW(0, False, 'Local\Workspace.ExcelSelectionExport.Setup.Transaction');
  ErrorCode := GetLastError;
  Result := (SetupMutex <> 0) and (ErrorCode <> 183);
  if not Result then begin
    if SetupMutex <> 0 then CloseHandle(SetupMutex);
    SetupMutex := 0;
    SuppressibleMsgBox('선택범위 내보내기의 설치 또는 제거가 진행 중입니다. 끝난 뒤 다시 실행해 주세요.', mbError, MB_OK, IDOK);
  end;
end;
procedure ReleaseLock;
begin
  if SetupMutex <> 0 then CloseHandle(SetupMutex);
  SetupMutex := 0;
end;
function OwnDirectory: Boolean;
var Stored: AnsiString;
begin
  Result := LoadStringFromFile(ProductDirectory + '\product.id', Stored);
  if Result then Result := Trim(String(Stored)) = Identity;
end;
function RuntimeReady: Boolean;
var Release: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM32, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', Release);
  if Result then Result := Release >= 528040;
end;
function InitializeSetup: Boolean;
var Owner, ExistingClass, ExistingClsid, ExistingArch: String;
begin
  Result := AcquireLock;
  if not Result then exit;
  if not RuntimeReady then begin
    SuppressibleMsgBox('[E11] .NET Framework 4.8 이상이 필요합니다. 회사에서 승인한 Windows 구성 절차로 준비해 주세요.', mbError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  IsUpgrade := OwnDirectory;
  if DirExists(ProductDirectory) and not IsUpgrade then begin
    SuppressibleMsgBox('기존 폴더가 선택범위 내보내기 소유인지 확인할 수 없어 설치를 중단했습니다.', mbError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  if RegQueryStringValue(HKCU, 'Software\Workspace\ExcelSelectionExport', 'Architecture', ExistingArch) and
     (ExistingArch <> '{#Arch}') then begin
    SuppressibleMsgBox('[E13] 다른 비트수의 선택범위 내보내기가 설치되어 있습니다. Excel 작업을 저장하고 기존 제품을 제거한 뒤 설치해 주세요.', mbError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  if (RegKeyExists(HKCU, 'Software\Classes\CLSID\{2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1}') or RegKeyExists(HKCU, '{#ProgKey}') or RegKeyExists(HKCU, '{#AddinKey}')) and not IsUpgrade then begin
    SuppressibleMsgBox('이 제품의 기존 등록이 있지만 설치 소유권을 확인할 수 없어 중단했습니다. 기존 등록은 그대로 두었습니다.', mbError, MB_OK, IDOK);
    Result := False;
  end;
end;
procedure DeinitializeSetup;
begin
  ReleaseLock;
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
var ExitCode: Integer; ReportFile, Arguments: String;
begin
  Result := '';
  if CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), ProductDirectory) <> 0 then begin
    Result := '이 제품의 설치 폴더는 바꿀 수 없습니다. 기본 설치 위치를 사용해 주세요.';
    exit;
  end;
  ExtractTemporaryFile('SetupProbe.exe');
  ReportFile := ExpandConstant('{tmp}\SelectionExport-probe.ini');
  Arguments := 'preflight {#Arch} "' + ReportFile + '"';
  { Existing Excel can retain an earlier version. Only replacement of an already
    installed payload requires every Excel process to be closed. }
  if DirExists(PayloadDirectory) then begin
    Arguments := Arguments + ' upgrade';
    Log('SelectionExport payload already exists; replacement requires all Excel processes closed.');
  end else
    Log('SelectionExport new version directory; existing Excel processes retain the previous assembly until restarted.');
  if not Exec(ExpandConstant('{tmp}\SetupProbe.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then begin
    Result := '[E31] 설치 검사 프로그램을 실행하지 못했습니다. 보안 차단 또는 필수 런타임을 확인해 주세요.';
    exit;
  end;
  Log('SelectionExport preflight exit=' + IntToStr(ExitCode));
  if ExitCode <> 0 then
    Result := '[E' + IntToStr(ExitCode) + '] ' + GetIniString('Probe', 'Message', '설치 검사를 완료하지 못했습니다.', ReportFile);
end;
procedure CurStepChanged(CurStep: TSetupStep);
var ExitCode: Integer; ReportFile: String;
begin
  if CurStep <> ssPostInstall then exit;
  ReportFile := ExpandConstant('{tmp}\SelectionExport-activation.ini');
  if not Exec(PayloadDirectory + '\SetupProbe.exe', 'diagnose "' + ReportFile + '"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    PostInstallFailure := '[E31] 설치 후 COM 로드 검사 프로그램을 실행하지 못했습니다.'
  else if ExitCode <> 0 then
    PostInstallFailure := '[E' + IntToStr(ExitCode) + '] ' + GetIniString('Probe', 'Message', 'COM 로드 검사를 마치지 못했습니다.', ReportFile);
  if PostInstallFailure <> '' then Log('SelectionExport INSTALL VALIDATION FAILED: ' + PostInstallFailure)
  else Log('SelectionExport COM activation passed. Actual Excel startup/menu validation remains separate.');
end;
procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and (PostInstallFailure <> '') then begin
    WizardForm.FinishedHeadingLabel.Caption := '추가 기능 로드 확인 실패';
    WizardForm.FinishedLabel.Caption := PostInstallFailure + #13#10#13#10 +
      '제품 파일과 등록은 설치되었지만 정상 설치로 확인되지 않았습니다. 기능을 사용할 수 없는 상태일 수 있습니다.' + #13#10 +
      '이 설치는 자동으로 되돌리지 않았습니다. IT 담당자에게 오류 코드를 전달하거나 Windows 설정에서 선택범위 내보내기를 제거해 주세요.';
  end;
end;
function GetCustomSetupExitCode: Integer;
begin
  if PostInstallFailure <> '' then Result := 30 else Result := 0;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := '지금 로그인한 Windows 계정에 선택범위 내보내기를 설치합니다.' + NewLine + NewLine +
    'Excel을 시작하면 메뉴만 자동으로 준비합니다. 내보내기는 메뉴를 눌렀을 때 시작합니다.' + NewLine +
    '설치된 Excel 비트수: {#Arch}용 패키지' + NewLine +
    '새 버전은 별도 폴더에 설치합니다. 열려 있던 Excel은 이전 버전을 계속 사용하므로 저장 후 다시 시작해 주세요.' + NewLine +
    '이 파일은 서명되지 않은 평가판이며 회사의 추가 기능 정책이 적용됩니다.' + NewLine + NewLine + ProductDirectory;
end;
function InitializeUninstall: Boolean;
var ExitCode: Integer; ReportFile: String;
begin
  Result := AcquireLock;
  if not Result then exit;
  if not OwnDirectory then begin
    SuppressibleMsgBox('설치 소유권을 확인할 수 없어 제거를 중단했습니다.', mbError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  ReportFile := ExpandConstant('{tmp}\SelectionExport-uninstall.ini');
  if not Exec(PayloadDirectory + '\SetupProbe.exe', 'uninstall "' + ReportFile + '"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then begin
    SuppressibleMsgBox('제거 검사를 실행하지 못했습니다. 설치 파일과 보안 차단 상태를 확인해 주세요.', mbError, MB_OK, IDOK);
    Result := False;
    exit;
  end;
  Result := ExitCode = 0;
  if not Result then SuppressibleMsgBox('[E' + IntToStr(ExitCode) + '] ' +
    GetIniString('Probe', 'Message', '제거 검사를 완료하지 못했습니다.', ReportFile), mbError, MB_OK, IDOK);
end;
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var ExitCode: Integer; ReportFile: String;
begin
  if CurUninstallStep <> usUninstall then exit;
  { Recheck after the confirmation dialog, before Inno changes owned files/keys. }
  ReportFile := ExpandConstant('{tmp}\SelectionExport-uninstall-final.ini');
  if not Exec(PayloadDirectory + '\SetupProbe.exe', 'uninstall "' + ReportFile + '"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    RaiseException('제거 직전 검사를 실행하지 못했습니다. 설치 파일은 그대로 두었습니다.');
  if ExitCode <> 0 then RaiseException('[E' + IntToStr(ExitCode) + '] ' +
    GetIniString('Probe', 'Message', '제거 직전 검사를 마치지 못했습니다.', ReportFile));
end;
procedure DeinitializeUninstall;
begin
  ReleaseLock;
end;
