# Excel 명단 비교 · 단일 EXE 설치

RC8은 Windows 데스크톱 Excel용 시험 후보이며 **Esc 실기 검사 실패로 배포를 보류했습니다.** 아래는 시험용 설치 절차입니다. 새 XLAM과 설치 파일을 한 EXE에 담았으며, 현재 판정은 [RC8 검증 기록](RC8_COMPLETION_REPORT.md)을 따릅니다. 로컬 시험 파일과 [이전 공개 릴리즈](https://github.com/prozac0401/Workspace/releases)를 구분합니다.

## 설치와 업데이트

1. 제공된 `ExcelSmartListCompare-0.2.0-rc.8-Setup.exe`와 검증 요약의 해시를 확인합니다.
2. 업무를 저장하고 모든 Excel 창을 닫습니다.
3. EXE를 실행하고 안내를 확인한 뒤 **설치**를 누릅니다.
4. Excel을 열고 첫 번째 목록에서 **첫 번째 목록 담기**, 다음 목록에서 **두 번째 목록 담아 비교**를 실행합니다.

이전 설치는 버전을 확인해 교체하고, RC8은 다시 설치합니다. 더 최신 버전이나 알 수 없는 설치 기록은 덮어쓰지 않습니다. [현재 검증 결과](RC8_COMPLETION_REPORT.md)를 확인하세요.

## 제거

Excel을 모두 닫고 **Windows 설정 → 앱 → 설치된 앱 → Excel 명단 비교 → 제거**를 실행합니다. 제품 파일과 자기 Excel 등록을 제거하고 다른 추가 기능·통합문서·사용자가 추가한 파일은 보존합니다.

`Uninstall.cmd`로 먼저 제거했다면 앱 목록의 항목은 남을 수 있습니다. 앱 목록에서 다시 제거하면 설치 관리 항목도 정리됩니다. 제거 파일이 누락됐다면 동일 EXE를 다시 설치한 뒤 제거할 수 있습니다.

RC8의 설치 폴더 CMD는 두 실행 파일을 새 임시 폴더로 복사해 실행 제어를 넘깁니다. 원래 CMD가 삭제돼도 제거 결과를 반환하며, 작은 실행 복사본은 사용자 임시 폴더에 남을 수 있습니다. 업무 파일은 복사하지 않습니다. 이전 RC7의 접근 거부와 자기 삭제 실패 이력은 [당시 기록](UNLOCKED_UI_REPORT.md)에 보존합니다. 첫 접근 거부 원인은 미확정이며 모든 제거 실패가 같은 원인이라고 판단하지 않습니다.

## 설치 위치와 실행 조건

- 제품: `%LOCALAPPDATA%\ExcelSmartListCompare`
- 설치 관리 파일: `%LOCALAPPDATA%\ExcelSmartListCompare.Setup`
- 관리자 권한 없이 현재 사용자에게 설치합니다. Windows 데스크톱 Excel과 Windows PowerShell이 필요합니다.
- 제품 폴더 한 곳만 Excel 신뢰 위치로 등록합니다. 새 항목은 하위 폴더를 포함하지 않습니다. 제품 폴더에는 제품 파일만 보관하세요.
- 그룹 정책과 유효 AllSigned 설정은 그대로 적용됩니다. 전역 매크로 설정과 영구 실행 정책을 변경하지 않습니다.

## 실패했을 때

Excel 실행 중이면 저장·종료 후 다시 실행합니다. 다른 설치가 진행 중이면 완료를 기다립니다. 처리 가능한 업데이트 실패는 이전 파일과 등록을 복구합니다.

제품 설치 완료 후 관리 항목 기록만 중단됐다면 같은 EXE를 다시 실행하세요. 제품 표식이 없는 관리 폴더는 덮어쓰지 않습니다. 설치 화면의 동작·종료 코드와 로컬 로그를 보관하세요. `%TEMP%`의 `Setup Log` 파일에는 사용자 경로가 포함될 수 있으므로 공개 게시하지 않습니다.

이 파일은 **코드 서명이 없는 평가용 설치기**입니다. Windows 또는 조직 정책이 실행을 제한할 수 있으며 회사 배포 승인판을 의미하지 않습니다. 다른 Office 환경과 미검증 항목은 [RC8 검증 기록](RC8_COMPLETION_REPORT.md)을 확인하세요.

## 제작과 재현

검증 대상 RC8 Release 폴더와 Inno Setup 6.5 이상이 필요합니다.

```powershell
python scripts/build-excel-onefile.py --engine-version 0.2.0-rc.8 --release-directory artifacts/excel-rc8-release/Release --output-directory artifacts/excel-rc8-onefile-new
```

출력은 저장소 `artifacts` 안의 새 경로여야 합니다. `installer/RC8-Payload.json`의 5개 고정 해시와 입력을 비교한 뒤 EXE, SHA-256, `OneFile-Build.json`을 만듭니다. 빌드만으로 실제 실행 검증이 완료되지는 않습니다. RC7을 재현할 때는 `--engine-version 0.2.0-rc.7`과 그 버전의 Release를 사용합니다. 원시 진단과 빌드 중간 파일은 배포 대상이 아닙니다.
