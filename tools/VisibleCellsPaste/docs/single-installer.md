# 단일 EXE 설치

대상: 제품 0.1.1 · wrapper 0.1.1.1 · 서명 없는 단일 설치 파일

Excel 문서를 저장하고 모두 종료한 뒤 **VisibleCellsPaste-0.1.1-Setup.exe**를 실행합니다. 안내에서 확인을 누르면 현재 Windows 사용자에게 설치합니다. 이후 Excel을 평소처럼 열고 셀 우클릭 메뉴를 사용합니다. ZIP 압축 해제와 Install.cmd 실행은 필요하지 않습니다.

이미 공개 ZIP으로 설치했다면 같은 기본 위치의 설치를 이어서 업데이트합니다. 통합문서·다른 추가 기능·Office 보안 설정은 설치 대상이 아닙니다. 사용자 비활성화 설정이나 외부 수정 파일은 기존 설치 엔진의 보존 규칙을 유지합니다. 기존 설치의 소유권을 확인할 수 없으면 진행하지 않습니다.

제거는 Excel을 모두 종료한 뒤 Windows **설치된 앱 → 보이는 칸 붙여넣기 → 제거**를 사용합니다. 기술 담당자는 같은 EXE에 `--uninstall`을 전달할 수도 있습니다. 일반 사용자가 별도 스크립트나 개발 도구를 설치할 필요는 없습니다.

검증한 EXE를 [단일 설치 릴리스](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.1.1-setup.1)에 게시했습니다. 기존 ZIP은 보존합니다. 현재 PC의 실제 붙여넣기·Undo·정상 시작/종료·제거를 확인했으며 x86 실제 Office·새 PC·재부팅 검증은 남아 있습니다. 조직 배포 승인은 별도입니다. 실제 시험과 한계는 Workspace의 순차 백로그 및 배포 기록을 따릅니다.

## 개발자 재현

공개 ZIP과 그 SHA-256을 명시합니다. 이 빌드는 추가 기능 DLL을 다시 컴파일하지 않습니다.

```powershell
powershell -NoProfile -File tools/VisibleCellsPaste/build/build-single-installer.ps1 -ZipPath <검증한-ZIP-경로> -ExpectedSha256 9555bf97c0d8ea0219a0692e6b1aad5594864a34af9cbf119c07fa7edbb20fa0
```

단일 EXE·SHA256SUMS·소스/입력/산출물 해시 기록은 `artifacts/visible-cells-paste/single-0.1.1`에 생성합니다. 설치 수명주기는 `installer/Test-SingleInstaller.ps1`로 검사하며, 기존 제품 설치나 Excel 프로세스가 있으면 시작하지 않습니다. 실제 UI와 Excel 동작은 별도로 확인합니다.

실행 중 `%TEMP%`의 이번 작업 전용 폴더에 payload를 풀고 설치 엔진 종료 후 정리합니다. 강제 종료나 파일 잠금이 있으면 임시 파일이 남을 수 있습니다. 사용자 임시 폴더 전체를 지우거나 다른 실행의 파일을 정리하지 않습니다.

## 실제 Excel 검증 재현

`build/Build-UiSmokeProbe.ps1 -Architecture x64`는 제품을 변경하지 않는 읽기 전용 검사 도구를 만듭니다. 출력은 `artifacts/visible-cells-paste/ui-smoke/x64/UiSmokeProbe.exe`입니다. 실제 Office 비트수에 맞춰 빌드하고 Excel 시험을 하나씩 진행합니다.

1. `UiSmokeProbe.exe create <새-xlsx-경로>`로 합성 파일을 만듭니다. 기존 파일은 덮어쓰지 않습니다.
2. 모든 Excel을 종료한 후 `UiSmokeProbe.exe start <EXCEL.EXE-경로> <합성-xlsx-경로>`로 정상 시작합니다. 반환한 PID를 사용해 `before <PID> <합성-xlsx-경로>`를 검사합니다.
3. 실제 UI에서 H1:J1을 복사하고 E2:E5를 선택하여 **보이는 칸에 붙여넣기**를 누른 뒤 `pasted <PID> <합성-xlsx-경로>`를 검사합니다.
4. 실제 메뉴의 **마지막 붙여넣기 되돌리기**를 누른 뒤 `undone <PID> <합성-xlsx-경로>`를 검사합니다. 세 단계는 각각 공통 13개 항목을 검사하며 독립 사례 39개를 의미하지 않습니다.
5. 합성 파일을 저장하지 않고 UI로 닫습니다. 프로세스 부재·파일 해시 보존, 재시작 시 메뉴 중복 부재, 제거 후 제품 메뉴 부재와 기존 메뉴 보존을 별도로 확인합니다.

검사 도구는 제품 명령 실행·셀 변경·문서 닫기·Excel 강제 종료를 하지 않습니다. 새 합성 파일 생성과 일반 프로세스 시작만 별도 명령으로 제공합니다. 값 검사는 정확한 파일 경로와 전용 시트 이름을 확인한 뒤 실행합니다.
