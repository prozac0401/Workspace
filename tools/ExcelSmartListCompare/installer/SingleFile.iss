; ADR-0009: the published RC7 engine owns Excel files and registration.
; Inno Setup owns only the separate manager directory and Apps entry.
#ifndef PayloadDir
  #error PayloadDir is required; use scripts/build-excel-onefile.py.
#endif
#ifndef ManagerFolder
  #define ManagerFolder "ExcelSmartListCompare.Setup"
#endif
#ifndef ProductFolder
  #define ProductFolder "ExcelSmartListCompare"
#endif
#ifndef ManagerId
  #define ManagerId "ExcelSmartListCompare.OneFile"
#endif
#include AddBackslash(PayloadDir) + "PayloadHashes.iss"

[Setup]
AppId={#ManagerId}
AppName=Excel 명단 비교
AppVersion=0.2.0-rc.7
AppVerName=Excel 명단 비교 0.2.0 RC7
AppPublisher=Workspace
AppPublisherURL=https://github.com/prozac0401/Workspace
AppSupportURL=https://github.com/prozac0401/Workspace/releases
DefaultDirName={localappdata}\{#ManagerFolder}
UsePreviousAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
SetupLogging=yes
CloseApplications=no
RestartApplications=no
AlwaysRestart=no
UninstallDisplayName=Excel 명단 비교
UninstallDisplayIcon={uninstallexe}
OutputBaseFilename=ExcelSmartListCompare-0.2.0-rc.7-Setup
Compression=lzma2
SolidCompression=yes
VersionInfoVersion=0.2.0.7001
VersionInfoDescription=Excel 명단 비교 단일 설치 프로그램
VersionInfoProductName=Excel Smart List Compare

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Messages]
ReadyLabel1=Excel 명단 비교를 설치할 준비가 되었습니다.
ReadyLabel2a=Excel 업무를 저장하고 모든 Excel 창을 닫은 다음 [설치]를 누르세요.
FinishedHeadingLabel=Excel 명단 비교 설치 완료
FinishedLabelNoIcons=Excel을 열고 첫 번째 목록을 선택한 다음 [첫 번째 목록 담기]를 누르세요.%n다음 목록에서 [두 번째 목록 담아 비교]를 실행하면 됩니다.%n%n제거: Windows 설정 → 앱 → 설치된 앱 → Excel 명단 비교
ConfirmUninstall=Excel 명단 비교를 제거할까요?%n%n모든 Excel 창을 먼저 닫아 주세요. 기존 통합문서와 다른 추가 기능은 유지됩니다.

[Files]
Source: "{#PayloadDir}\Install.cmd"; Flags: dontcopy
Source: "{#PayloadDir}\Uninstall.cmd"; Flags: dontcopy
Source: "{#PayloadDir}\Setup.ps1"; Flags: dontcopy
Source: "{#PayloadDir}\README.md"; Flags: dontcopy
Source: "{#PayloadDir}\ExcelSmartListCompare.xlam"; Flags: dontcopy
Source: "{#PayloadDir}\Setup.ps1"; DestDir: "{app}\Engine"; Flags: ignoreversion
Source: "{#PayloadDir}\Uninstall.cmd"; DestDir: "{app}\Engine"; Flags: ignoreversion
Source: "{#PayloadDir}\manager.id"; DestDir: "{app}"; Flags: ignoreversion

[Code]
const
  ManagerIdentity = 'SLC-68A45C44-2026-OneFile-1';
var
  ManagerLock: THandle;
  EngineComplete: Boolean;
  EngineRunning: Boolean;

function CreateMutexW(Attributes: Integer; InitialOwner: Boolean; Name: String): THandle;
  external 'CreateMutexW@kernel32.dll stdcall';
function LastWindowsError: LongWord;
  external 'GetLastError@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function SetEnvironmentVariable(Name, Value: String): Boolean;
  external 'SetEnvironmentVariableW@kernel32.dll stdcall';

function ManagerDirectory: String;
begin
  Result := ExpandConstant('{localappdata}\{#ManagerFolder}');
end;

function ProductDirectory: String;
begin
  Result := ExpandConstant('{localappdata}\{#ProductFolder}');
end;

function OwnManager: Boolean;
var Identity: AnsiString;
begin
  Result := LoadStringFromFile(ManagerDirectory + '\manager.id', Identity);
  if Result then Result := Trim(String(Identity)) = ManagerIdentity;
end;

function AcquireManagerLock: Boolean;
var LastError: LongWord;
begin
  ManagerLock := CreateMutexW(0, False, 'Local\{#ManagerId}');
  LastError := LastWindowsError;
  Result := (ManagerLock <> 0) and (LastError <> 183);
  if not Result then begin
    if ManagerLock <> 0 then CloseHandle(ManagerLock);
    ManagerLock := 0;
    SuppressibleMsgBox('다른 설치 또는 제거가 진행 중입니다. 완료 후 다시 실행하세요.', mbError, MB_OK, IDOK);
  end;
end;

procedure ReleaseManagerLock;
begin
  if ManagerLock <> 0 then CloseHandle(ManagerLock);
  ManagerLock := 0;
end;

function InitializeSetup: Boolean;
begin
  Result := AcquireManagerLock;
  if not Result then exit;
  if (DirExists(ManagerDirectory) or RegKeyExists(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#ManagerId}_is1')) and not OwnManager then begin
    SuppressibleMsgBox('설치 관리 폴더에 확인할 수 없는 파일이 있습니다. 기존 폴더를 보존하고 중단합니다.', mbError, MB_OK, IDOK);
    Result := False;
  end;
end;

procedure DeinitializeSetup;
begin
  ReleaseManagerLock;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := '현재 Windows 사용자에게 설치합니다.' + NewLine + NewLine +
    '• 이전 버전은 자동으로 교체하고, 같은 버전은 다시 설치합니다.' + NewLine +
    '• 설치 후 Excel에서 명단 비교 기능을 사용할 수 있습니다.' + NewLine +
    '• 아래 제품 폴더만 Excel 신뢰 위치로 등록합니다(하위 폴더 제외).' + NewLine +
    '  이 폴더의 매크로는 알림 없이 실행될 수 있으므로 제품 파일만 보관하세요.' + NewLine + NewLine +
    ProductDirectory;
end;

procedure CaptureEngineOutput(const S: String; const Error, FirstLine: Boolean);
begin
  Log('Engine: ' + S);
end;

function EngineError(Code: Integer): String;
begin
  case Code of
    2: Result := '설치 또는 제거를 취소했습니다.';
    3: Result := 'Excel 업무를 저장하고 모든 Excel 창을 닫은 뒤 다시 실행하세요.';
    4: Result := '다른 설치 또는 제거가 진행 중입니다. 완료 후 다시 실행하세요.';
    6: Result := '제품 설치 경로 또는 조직의 Excel 신뢰 위치 정책을 확인해 주세요.';
  else
    Result := '설치를 완료하지 못했습니다. 실행 정책, 기존 설치 상태 또는 파일 접근 권한을 확인해 주세요.';
  end;
  Result := Result + #13#10 + '설치 엔진 종료 코드: ' + IntToStr(Code) + #13#10 +
    '자세한 내용은 로컬 설치 로그를 확인하세요.';
end;

function RunEngine(Directory, Action: String): Integer;
var PreviousNoPause: String; Started: Boolean;
begin
  PreviousNoPause := GetEnv('SLC_SETUP_NO_PAUSE');
  if not SetEnvironmentVariable('SLC_SETUP_NO_PAUSE', '1') then
    RaiseException('설치 실행 환경을 준비하지 못했습니다.');
  try
    { No path is interpolated into shell code. The fixed launcher is resolved in
      the explicit working directory, including paths with shell metacharacters. }
    Started := ExecAndLogOutput(ExpandConstant('{cmd}'),
      '/D /V:OFF /C "chcp 65001>nul & ' + Action + '.cmd -ConfirmProduct SLC-68A45C44-2026"',
      Directory, SW_HIDE, ewWaitUntilTerminated, Result, @CaptureEngineOutput);
    if not Started then begin
      Log('Engine process could not be started: ' + IntToStr(Result));
      Result := 1;
    end;
    Log('SLC_ENGINE_EXIT_CODE=' + IntToStr(Result));
  finally
    SetEnvironmentVariable('SLC_SETUP_NO_PAUSE', PreviousNoPause);
  end;
end;

procedure ExtractChecked(Name, ExpectedHash: String);
begin
  ExtractTemporaryFile(Name);
  if CompareText(GetSHA256OfFile(ExpandConstant('{tmp}\') + Name), ExpectedHash) <> 0 then
    RaiseException('설치 파일의 무결성 확인에 실패했습니다: ' + Name);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code: Integer;
begin
  Result := '';
  if EngineComplete then exit;
  if CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), ManagerDirectory) <> 0 then begin
    Result := '이 설치기는 현재 사용자의 고정 제품 경로만 지원합니다.';
    exit;
  end;
  EngineRunning := True;
  try
    ExtractChecked('Install.cmd', '{#InstallHash}');
    ExtractChecked('Uninstall.cmd', '{#UninstallHash}');
    ExtractChecked('Setup.ps1', '{#SetupHash}');
    ExtractChecked('README.md', '{#ReadmeHash}');
    ExtractChecked('ExcelSmartListCompare.xlam', '{#XlamHash}');
    Code := RunEngine(ExpandConstant('{tmp}'), 'Install');
    if Code <> 0 then Result := EngineError(Code)
    else EngineComplete := True;
  finally
    EngineRunning := False;
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if EngineRunning or (EngineComplete and (CurPageID <> wpFinished)) then Cancel := False;
end;

function InitializeUninstall: Boolean;
begin
  Result := AcquireManagerLock;
  if not Result then exit;
  Result := OwnManager;
  if not Result then
    SuppressibleMsgBox('설치 관리 폴더의 제품 기록을 확인할 수 없어 제거를 중단합니다.', mbError, MB_OK, IDOK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Code: Integer; EngineDirectory, StagedDirectory: String;
begin
  if CurUninstallStep <> usUninstall then exit;
  { usUninstall occurs AFTER Inno's consent dialog and BEFORE it removes files.
    An exception here is fatal, preserving the manager and its Apps entry. }
  EngineDirectory := ProductDirectory;
  if not FileExists(EngineDirectory + '\Setup.ps1') or
     not FileExists(EngineDirectory + '\Uninstall.cmd') then
    EngineDirectory := ManagerDirectory + '\Engine';
  if not FileExists(EngineDirectory + '\Setup.ps1') or
     not FileExists(EngineDirectory + '\Uninstall.cmd') then
    RaiseException('제거 파일이 없습니다. 단일 설치 프로그램을 다시 실행한 후 제거하세요.');
  { Run copies from the private temporary directory. Running a batch file inside
    the product would lock its working directory and delete the active batch. }
  StagedDirectory := ExpandConstant('{tmp}');
  if not FileCopy(EngineDirectory + '\Setup.ps1', StagedDirectory + '\Setup.ps1', False) or
     not FileCopy(EngineDirectory + '\Uninstall.cmd', StagedDirectory + '\Uninstall.cmd', False) then
    RaiseException('제거 파일을 준비하지 못했습니다. 기존 설치는 유지됩니다.');
  Code := RunEngine(StagedDirectory, 'Uninstall');
  if Code <> 0 then RaiseException(EngineError(Code));
end;

procedure DeinitializeUninstall;
begin
  ReleaseManagerLock;
end;
