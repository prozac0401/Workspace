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
#ifndef EngineVersion
  #define EngineVersion "0.2.0-rc.7"
#endif
#include AddBackslash(PayloadDir) + "PayloadHashes.iss"

[Setup]
AppId={#ManagerId}
AppName=Excel 명단 비교
AppVersion={#EngineVersion}
AppVerName=Excel 명단 비교 {#EngineVersion}
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
OutputBaseFilename=ExcelSmartListCompare-{#EngineVersion}-Setup
Compression=lzma2
SolidCompression=yes
VersionInfoVersion=0.2.0.7001
VersionInfoDescription=Excel 명단 비교 설치 프로그램
VersionInfoProductName=Excel Smart List Compare

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Messages]
SetupWindowTitle=Excel 명단 비교 설치
SetupLdrStartupMessage=Excel 명단 비교를 설치할까요?
LdrCannotCreateTemp=설치에 필요한 임시 파일을 만들지 못해 설치를 중단했습니다.
LdrCannotExecTemp=임시 폴더에서 설치 파일을 실행하지 못해 설치를 중단했습니다.
SetupFileMissing=설치에 필요한 파일이 없습니다: %1%n%n설치 프로그램을 다시 받아 실행해 주세요.
SetupFileCorrupt=설치 파일이 손상되었습니다. 설치 프로그램을 다시 받아 실행해 주세요.
SetupFileCorruptOrWrongVer=설치 파일이 손상되었거나 버전이 맞지 않습니다. 설치 프로그램을 다시 받아 실행해 주세요.
InvalidParameter=설치 프로그램에 전달한 실행 옵션이 올바르지 않습니다:%n%n%1
SetupAlreadyRunning=설치가 이미 진행 중입니다. 끝난 뒤 다시 실행해 주세요.
WindowsVersionNotSupported=현재 Windows 버전에서는 Excel 명단 비교를 설치할 수 없습니다.
OnlyOnTheseArchitectures=이 PC에서는 설치할 수 없습니다. 다음 종류의 Windows가 필요합니다:%n%n%1
ErrorCreatingDir=설치에 필요한 폴더를 만들지 못했습니다:%n%1
ErrorTooManyFilesInDir=폴더에 파일이 너무 많아 새 파일을 만들지 못했습니다:%n%1
ExitSetupMessage=아직 설치가 끝나지 않았습니다. 지금 종료하면 나중에 설치 프로그램을 다시 실행해야 합니다.%n%n설치를 종료할까요?
ClickNext=계속하려면 [다음]을, 설치를 그만두려면 [취소]를 누르세요.
DiskSpaceWarning=설치에 필요한 공간은 %1 KB이지만, 남은 공간은 %2 KB입니다.%n%n그래도 계속할까요?
ReadyLabel1=Excel 명단 비교를 설치할 준비가 되었습니다.
ReadyLabel2a=Excel에서 작업 중인 내용을 저장하고 모든 Excel 창을 닫은 뒤 [설치]를 누르세요.
ReadyLabel2b=Excel에서 작업 중인 내용을 저장하고 모든 Excel 창을 닫은 뒤 [설치]를 누르세요.
PreparingDesc=Excel 명단 비교 설치를 준비하고 있습니다.
CannotContinue=설치를 계속할 수 없습니다. 위 안내를 확인하고 [취소]를 눌러 종료해 주세요.
InstallingLabel=Excel 명단 비교를 설치하고 있습니다. 잠시 기다려 주세요.
FinishedHeadingLabel=Excel 명단 비교 설치 완료
FinishedLabelNoIcons=Excel을 열고 첫 번째 목록의 셀을 선택한 뒤 [첫 번째 목록 담기]를 누르세요.%n이어서 두 번째 목록의 셀을 선택하고 [두 번째 목록 담아 비교]를 누르세요.%n%n제거하려면 Windows 설정 → 앱 → 설치된 앱에서 [Excel 명단 비교]를 찾아 [제거]를 누르세요.
ClickFinish=[마침]을 누르면 설치 창이 닫힙니다.
SetupAborted=설치를 마치지 못했습니다.%n%n위 안내에 따라 문제를 해결한 뒤 설치 프로그램을 다시 실행해 주세요.
AbortRetryIgnoreRetry=다시 시도(&T)
RetryCancelRetry=다시 시도(&T)
StatusCreateDirs=설치 폴더를 만들고 있습니다...
StatusExtractFiles=설치 파일의 압축을 풀고 있습니다...
StatusCreateRegistryEntries=Windows에 설치 정보를 등록하고 있습니다...
StatusSavingUninstall=제거에 필요한 정보를 저장하고 있습니다...
StatusRunProgram=설치를 마무리하고 있습니다...
StatusRollback=이번에 바꾼 내용을 되돌리고 있습니다...
ErrorExecutingProgram=파일을 실행하지 못했습니다:%n%1
ErrorRegOpenKey=Windows 설정을 읽지 못했습니다. 확인할 항목:%n%1\%2
ErrorRegCreateKey=Windows 설정에 새 항목을 만들지 못했습니다. 확인할 항목:%n%1\%2
ErrorRegWriteKey=Windows 설정을 저장하지 못했습니다. 확인할 항목:%n%1\%2
SourceDoesntExist=설치에 필요한 원본 파일이 없습니다: %1
SourceVerificationFailed=설치 파일이 원본과 같은지 확인하지 못했습니다: %1
ExistingFileReadOnly2=기존 파일이 읽기 전용으로 설정되어 있어 교체할 수 없습니다.
ExistingFileReadOnlyRetry=읽기 전용 설정을 해제하고 다시 시도(&R)
ErrorReadingExistingDest=기존 파일을 읽지 못했습니다:
FileExists2=같은 이름의 파일이 이미 있습니다.
FileExistsOverwriteOrKeepAll=이후 같은 상황에도 이 선택 적용(&D)
ExistingFileNewer2=이미 설치된 파일이 이번에 설치할 파일보다 새 버전입니다.
ExistingFileNewerOverwriteOrKeepAll=이후 같은 상황에도 이 선택 적용(&D)
ErrorChangingAttr=파일 속성을 바꾸지 못했습니다:
ErrorCreatingTemp=설치 폴더에 임시 파일을 만들지 못했습니다:
ErrorReadingSource=원본 파일을 읽지 못했습니다:
ErrorCopying=파일을 복사하지 못했습니다:
ErrorExtracting=파일의 압축을 풀지 못했습니다:
ErrorReplacingExistingFile=기존 파일을 교체하지 못했습니다:
ErrorRenamingTemp=임시 파일의 이름을 바꾸지 못했습니다:
ConfirmUninstall=Excel 명단 비교를 제거할까요?%n%nExcel에서 작업 중인 내용을 저장하고 모든 Excel 창을 닫아 주세요. 기존 Excel 파일과 다른 추가 기능은 그대로 둡니다.
UninstallNotFound=제거에 필요한 파일이 없습니다: %1%n%n같은 설치 프로그램을 다시 실행해 설치한 뒤 제거해 주세요.
UninstallOpenError=제거에 필요한 파일을 열지 못했습니다: %1
UninstallUnsupportedVer=제거 정보를 읽을 수 없어 제거를 중단했습니다. 확인할 파일: %1
UninstallUnknownEntry=제거 정보에 알 수 없는 항목이 있습니다: %1
UninstallStatusLabel=Excel 명단 비교를 제거하고 있습니다. 잠시 기다려 주세요.
UninstalledAll=Excel 명단 비교를 제거했습니다.
UninstalledMost=Excel 명단 비교를 제거했지만 일부 파일이나 설정이 남아 있습니다.
UninstallDataCorrupted=제거에 필요한 파일이 손상되어 제거를 중단했습니다: %1
WizardUninstalling=제거 중
StatusUninstalling=Excel 명단 비교를 제거하고 있습니다...
ShutdownBlockReasonInstallingApp=Excel 명단 비교를 설치하고 있습니다.
ShutdownBlockReasonUninstallingApp=Excel 명단 비교를 제거하고 있습니다.

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
    SuppressibleMsgBox('Excel 명단 비교를 설치하거나 제거하는 작업이 진행 중입니다. 끝난 뒤 다시 실행해 주세요.', mbError, MB_OK, IDOK);
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
    SuppressibleMsgBox('기존 설치 관리 폴더가 Excel 명단 비교의 폴더인지 확인할 수 없어 설치를 중단했습니다. 폴더와 파일은 그대로 두었습니다.', mbError, MB_OK, IDOK);
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
  Result := '지금 로그인한 Windows 계정에서 사용할 수 있도록 설치합니다.' + NewLine + NewLine +
    '• 이전 버전이 있으면 새 버전으로 바꾸고, 같은 버전이면 다시 설치합니다.' + NewLine +
    '• Excel을 열면 명단 비교 메뉴가 나타납니다.' + NewLine +
    '• 아래 폴더만 Excel의 [신뢰할 수 있는 위치]에 등록합니다. 새로 등록할 때 하위 폴더는 제외합니다.' + NewLine +
    '  이 폴더의 매크로는 별도 확인 없이 실행될 수 있습니다. Excel 명단 비교 파일만 보관해 주세요.' + NewLine + NewLine +
    ProductDirectory;
end;

procedure CaptureEngineOutput(const S: String; const Error, FirstLine: Boolean);
begin
  Log('Engine: ' + S);
end;

function EngineError(Code: Integer; Action: String): String;
var ActionText: String;
begin
  if Action = 'Uninstall' then ActionText := '제거' else ActionText := '설치';
  case Code of
    2: Result := '설치 또는 제거를 취소했습니다.';
    3: Result := 'Excel에서 작업 중인 내용을 저장하고 모든 Excel 창을 닫은 뒤 다시 실행해 주세요.';
    4: Result := 'Excel 명단 비교를 설치하거나 제거하는 작업이 진행 중입니다. 끝난 뒤 다시 실행해 주세요.';
    6: Result := '설치 폴더를 확인해 주세요. 회사에서 Excel 매크로 실행을 제한한 경우에는 IT 담당자에게 문의해 주세요.';
  else
    Result := ActionText + '를 마치지 못했습니다. 보안 정책 때문에 실행이 차단되었거나, 기존 설치 파일을 읽고 쓰지 못했을 수 있습니다.';
  end;
  Result := Result + #13#10 + '문제 확인용 코드 (' + ActionText + '): ' + IntToStr(Code) + #13#10 +
    '자세한 내용은 이 PC에 저장된 설치 기록(Setup Log 파일)에서 확인할 수 있습니다.';
end;

function RunEngine(Directory, Action: String): Integer;
var PreviousNoPause: String; Started: Boolean;
begin
  PreviousNoPause := GetEnv('SLC_SETUP_NO_PAUSE');
  if not SetEnvironmentVariable('SLC_SETUP_NO_PAUSE', '1') then
    RaiseException('설치에 필요한 준비 작업을 마치지 못했습니다. 설치 프로그램을 다시 실행해 주세요.');
  try
    Log('SLC_ENGINE_ACTION=' + Action);
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
    RaiseException('설치 파일이 원본과 다릅니다. 설치 프로그램을 다시 받아 실행해 주세요. 확인할 파일: ' + Name);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code: Integer;
begin
  Result := '';
  if EngineComplete then exit;
  if CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), ManagerDirectory) <> 0 then begin
    Result := '이 프로그램의 설치 폴더는 바꿀 수 없습니다. 설치 위치를 지정하지 말고 설치 프로그램을 다시 실행해 주세요.';
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
    if Code <> 0 then Result := EngineError(Code, 'Install')
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
    SuppressibleMsgBox('Excel 명단 비교의 설치 기록을 확인할 수 없어 제거를 중단했습니다. 설치 관리 폴더는 그대로 두었습니다.', mbError, MB_OK, IDOK);
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
    RaiseException('제거에 필요한 파일이 없습니다. 같은 설치 프로그램(EXE)을 다시 실행해 설치한 뒤 제거해 주세요.');
  { Run copies from the private temporary directory. Running a batch file inside
    the product would lock its working directory and delete the active batch. }
  StagedDirectory := ExpandConstant('{tmp}');
  if not FileCopy(EngineDirectory + '\Setup.ps1', StagedDirectory + '\Setup.ps1', False) or
     not FileCopy(EngineDirectory + '\Uninstall.cmd', StagedDirectory + '\Uninstall.cmd', False) then
    RaiseException('제거에 필요한 파일을 준비하지 못했습니다. 기존 설치는 그대로 두었습니다.');
  Code := RunEngine(StagedDirectory, 'Uninstall');
  if Code <> 0 then RaiseException(EngineError(Code, 'Uninstall'));
end;

procedure DeinitializeUninstall;
begin
  ReleaseManagerLock;
end;
