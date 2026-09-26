# 단일 EXE 설치 후보

대상: 제품 0.1.1 · wrapper 0.1.1.1 · 서명 없는 로컬 평가 산출물

Excel 문서를 저장하고 모두 종료한 뒤 **VisibleCellsPaste-0.1.1-Setup.exe**를 실행합니다. 안내에서 확인을 누르면 현재 Windows 사용자에게 설치합니다. 이후 Excel을 평소처럼 열고 셀 우클릭 메뉴를 사용합니다. ZIP 압축 해제와 Install.cmd 실행은 필요하지 않습니다.

이미 공개 ZIP으로 설치했다면 같은 기본 위치의 설치를 이어서 업데이트합니다. 통합문서·다른 추가 기능·Office 보안 설정은 설치 대상이 아닙니다. 사용자 비활성화 설정이나 외부 수정 파일은 기존 설치 엔진의 보존 규칙을 유지합니다. 기존 설치의 소유권을 확인할 수 없으면 진행하지 않습니다.

제거는 Excel을 모두 종료한 뒤 Windows **설치된 앱 → 보이는 칸 붙여넣기 → 제거**를 사용합니다. 기술 담당자는 같은 EXE에 `--uninstall`을 전달할 수도 있습니다. 일반 사용자가 별도 스크립트나 개발 도구를 설치할 필요는 없습니다.

현재 공개 릴리스의 다운로드는 기존 ZIP입니다. 이 EXE를 공개 게시하거나 조직 배포 승인을 받은 것으로 안내하지 않습니다. 실제 시험과 한계는 Workspace의 순차 백로그 및 배포 기록을 따릅니다.

## 개발자 재현

공개 ZIP과 그 SHA-256을 명시합니다. 이 빌드는 추가 기능 DLL을 다시 컴파일하지 않습니다.

```powershell
powershell -NoProfile -File tools/VisibleCellsPaste/build/build-single-installer.ps1 -ZipPath <검증한-ZIP-경로> -ExpectedSha256 9555bf97c0d8ea0219a0692e6b1aad5594864a34af9cbf119c07fa7edbb20fa0
```

단일 EXE·SHA256SUMS·소스/입력/산출물 해시 기록은 `artifacts/visible-cells-paste/single-0.1.1`에 생성합니다. 설치 수명주기는 `installer/Test-SingleInstaller.ps1`로 검사하며, 기존 제품 설치나 Excel 프로세스가 있으면 시작하지 않습니다. 실제 UI와 Excel 동작은 별도로 확인합니다.

실행 중 `%TEMP%`의 이번 작업 전용 폴더에 payload를 풀고 설치 엔진 종료 후 정리합니다. 강제 종료나 파일 잠금이 있으면 임시 파일이 남을 수 있습니다. 사용자 임시 폴더 전체를 지우거나 다른 실행의 파일을 정리하지 않습니다.
