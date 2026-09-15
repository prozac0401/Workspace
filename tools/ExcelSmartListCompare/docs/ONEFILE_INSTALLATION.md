# Excel 명단 비교 · 단일 EXE 설치

RC7의 비교 기능과 설치 엔진을 그대로 담은 Windows x64용 설치 프로그램입니다. ZIP을 풀거나 PowerShell 명령을 입력할 필요가 없습니다.

## 설치와 업데이트

1. [단일 EXE 다운로드](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.0-rc.7-setup.1)에서 `ExcelSmartListCompare-0.2.0-rc.7-Setup.exe`를 받습니다.
2. 업무를 저장하고 모든 Excel 창을 닫습니다.
3. EXE를 실행하고 안내를 확인한 뒤 **설치**를 누릅니다.
4. Excel을 열고 첫 번째 목록에서 **첫 번째 목록 담기**, 다음 목록에서 **두 번째 목록 담아 비교**를 실행합니다.

기존 설치가 있으면 원래 엔진이 버전을 확인합니다. 이전 버전은 교체하고 RC7은 다시 설치합니다. 더 최신 버전이나 알 수 없는 설치 기록은 덮어쓰지 않습니다. 이 EXE에는 RC7의 XLAM과 설치 파일이 그대로 포함되므로 RC7 메뉴 기능의 검증 범위도 [기존 기록](CONTEXT_MENU_REPORT.md)을 따릅니다.

## 제거

Excel을 모두 닫고 **Windows 설정 → 앱 → 설치된 앱 → Excel 명단 비교 → 제거**를 실행합니다. 제품 파일과 자기 Excel 등록을 제거하고 다른 추가 기능·통합문서·사용자가 추가한 파일은 보존합니다.

기존 `Uninstall.cmd`로 먼저 제거한 경우 앱 목록의 항목은 남을 수 있습니다. 앱 목록에서 다시 제거하면 설치 관리 항목도 정리됩니다. 제거 파일이 누락됐다면 동일 EXE를 다시 설치한 뒤 제거할 수 있습니다.

## 설치 위치와 실행 조건

- 제품: `%LOCALAPPDATA%\ExcelSmartListCompare`
- 설치 관리 파일: `%LOCALAPPDATA%\ExcelSmartListCompare.Setup`
- 관리자 권한 없이 현재 사용자에게 설치합니다. Windows 데스크톱 Excel과 Windows PowerShell이 필요합니다.
- 기존 설치와 동일하게 **제품 폴더 한 곳**만 Excel 신뢰 위치로 등록합니다. 새 항목은 하위 폴더를 포함하지 않습니다. 제품 폴더에는 제품 파일만 보관하세요.
- 그룹 정책과 유효 AllSigned 설정은 그대로 적용됩니다. EXE 포장이 PowerShell 또는 매크로 정책의 실행 허용을 대신하지 않습니다.

## 실패했을 때

Excel 실행 중이면 저장·종료 후 다시 실행합니다. 다른 설치가 진행 중이면 완료를 기다립니다. 처리 가능한 업데이트 실패는 기존 엔진이 이전 파일과 등록을 복구합니다.

제품 설치 완료 후 관리 항목 기록만 중단됐다면 같은 EXE를 다시 실행하세요. 제품 표식이 없는 관리 폴더는 자동으로 덮어쓰지 않으므로, 알 수 없는 폴더 안내가 나오면 해당 폴더를 확인해야 합니다. 경로·조직 정책 문제는 설치 화면의 종료 코드와 로컬 로그를 확인합니다. 설치 로그는 `%TEMP%`의 `Setup Log` 파일이며 사용자 경로를 포함할 수 있으므로 공개 게시하지 않습니다.

이 파일은 **코드 서명이 없는 평가용 설치기**입니다. Windows 또는 조직 정책이 실행을 제한할 수 있으며 회사 배포 승인판을 의미하지 않습니다. 실제 확인한 환경과 미검증 항목은 [단일 EXE 검증 기록](ONEFILE_REPORT.md)을 확인하세요.

## 제작과 재현

기존 공개 RC7 ZIP의 Release 폴더와 Inno Setup 6.5 이상이 필요합니다. 저장소에서 실행합니다.

```powershell
python scripts/build-excel-onefile.py --release-directory artifacts/excel-rc7-release/Release --output-directory artifacts/excel-onefile-new
```

출력 폴더는 저장소의 artifacts 안에 있는 새 경로여야 합니다. 입력 5개 파일이 공개 RC7의 고정 해시와 다르면 빌드를 거절합니다. EXE, SHA-256 파일과 `OneFile-Build.json`이 생성됩니다. 검증 로그와 빌드 중간 파일을 배포할 필요는 없습니다.
