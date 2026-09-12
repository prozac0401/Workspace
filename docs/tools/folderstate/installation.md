# 설치·제거·업그레이드

## 배포 대상

Windows 11 x64가 기본 대상입니다. .NET 런타임을 포함한 MSI이므로 별도 .NET 설치가 필요하지 않습니다. ARM64 네이티브 패키지, Windows 10, SMB·동기화·보안솔루션 환경은 이번 검증 완료 범위가 아닙니다.

v0.1.0은 상용 정식판 승인 전의 검증용 배포입니다. 코드 서명·게시자·지원 정책과 별도 깨끗한 PC의 수명주기 검증은 [품질 기준](../../delivery/quality.md)을 확인합니다.

## 설치

FolderState-0.1.0-win-x64.msi를 열고 설치를 진행합니다. 현재 사용자 범위에 설치하며 관리자 권한 상승을 요청하지 않습니다.

| 항목 | 위치 |
|---|---|
| 프로그램·아이콘 | %LOCALAPPDATA%\Programs\FolderState |
| 시작 메뉴 | FolderState |
| 탐색기 메뉴 | HKCU\Software\Classes\Directory\shell\Workspace.FolderState |
| 로그 | %LOCALAPPDATA%\FolderState\logs |
| 업무 상태 | 선택 폴더의 .folderstate.ini |

메뉴가 보이지 않으면 탐색기 창을 다시 엽니다. 보안 설정을 끄거나 무조건 파일 차단 해제를 하지 않습니다.

같은 MSI를 다시 열면 유지 관리 화면에서 **복구** 또는 **제거**를 선택할 수 있습니다. 설치 위치는 사용자 설정에 기록하여 복구·업그레이드 시 유지합니다.

## 관리 명령

```powershell
msiexec /i "FolderState-0.1.0-win-x64.msi" /qn /norestart /l*v install.log
msiexec /fa "FolderState-0.1.0-win-x64.msi" /qn /norestart /l*v repair.log
msiexec /x "FolderState-0.1.0-win-x64.msi" /qn /norestart /l*v uninstall.log
```

종료 코드 0은 성공, 3010은 재시작 필요, 그 외는 로그를 확인합니다. 설치 로그에는 사용자 경로가 포함될 수 있습니다.

## 업그레이드와 제거

새 MSI는 고정 UpgradeCode와 증가한 세 자리 버전으로 기존 설치를 교체합니다. 이전 버전으로의 설치는 차단합니다. 같은 버전 파일을 다른 내용으로 다시 배포하지 않습니다.

제거는 프로그램·메뉴·로컬 아이콘·도구 로그를 정리합니다. 업무폴더를 검색하지 않으며 폴더 안의 상태정보와 Portable 아이콘을 일괄 제거하지 않습니다. Local 아이콘 경로가 없어지면 표시가 사라질 수 있지만 폴더·업무파일·저장 상태는 남습니다. 완전한 상태 초기화가 필요하면 프로그램 제거 전에 대상 폴더에서 초기화합니다.
