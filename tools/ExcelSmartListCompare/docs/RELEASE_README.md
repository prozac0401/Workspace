# Excel Smart List Compare 0.2.0 RC2

Windows 데스크톱 Excel용 명단 비교 추가 기능입니다. 코드 서명이 없는 평가용 배포 후보입니다.

## 설치와 사용

1. ZIP을 모두 압축 해제합니다. Excel 업무를 저장하고 모든 Excel 창을 닫습니다.
2. Release 폴더의 Install.cmd를 실행하고 이 제품 설치를 확인합니다.
3. Excel을 열고 첫 범위 선택 → 추가 기능 탭의 '명단 비교: 기준 담기' → 두 번째 범위 선택 → '명단 비교: 기준 n건과 비교'를 누릅니다.
4. 필요한 결과는 새 통합문서로 저장합니다. 원본과 기존 결과를 덮어쓰지 않습니다.

Release 폴더의 QuickGuide.html은 실제 화면 캡처를 포함한 오프라인 안내입니다. Windows-E2E-Report.html과 Validation.json에 실제 통과·미실행 항목을 구분했습니다.

## 제거와 다시 설치

Excel을 모두 닫고 이 폴더 또는 설치 폴더의 Uninstall.cmd를 실행합니다. 다시 설치하려면 새 Release의 Install.cmd를 실행합니다.

설치 위치: %LOCALAPPDATA%\ExcelSmartListCompare

Install.cmd가 이 제품 폴더만 Excel 신뢰 위치로 자동 등록합니다(하위 폴더 제외). 이 폴더의 파일은 매크로 알림 없이 실행될 수 있으므로 제품 파일만 보관하세요. 기존 신뢰 위치는 보존하며 제거할 때는 설치기가 만든 변경되지 않은 항목만 삭제합니다. 회사 정책에서 사용자 신뢰 위치를 막으면 종료 코드 6으로 중단합니다. 전역 매크로 설정과 회사 정책은 변경하지 않습니다.

Trust-Location-Report.html에는 RC2의 실제 Excel 재검증과 PC 원복 결과를 기록합니다. Windows-E2E-Report.html은 변경하지 않은 RC1 VBA 엔진의 기존 실행 기록입니다.

일반 사용자 설치이며 별도 Python이나 VBA 프로젝트 접근 권한이 필요하지 않습니다. 설치·제거는 Windows PowerShell을 사용합니다. 조직의 매크로/설치 정책이 차단하면 승인된 배포 절차를 이용하세요.

## 사용 경계

- 같은 Excel 프로세스 안에서만 기준을 공유합니다. Excel을 완전히 종료하면 기준은 사라집니다.
- 필터로 제외되거나 숨긴 셀은 읽지 않습니다. 일반 범위의 제목은 빼고 선택합니다.
- 이메일은 @ 앞 ID로 비교하고 텍스트 앞자리 0은 보존합니다. 값별 개수도 비교합니다.
- 처리 중 원본을 편집하지 말고 기다리세요. 취소는 Esc입니다. Excel이 제어권을 반환하는 체크포인트에서 처리합니다.
- VBA 실행 후 Excel 기본 Undo 기록 보존은 보장하지 않습니다.

수정 소스, 최신 안내 및 별도 FolderState 릴리즈: https://github.com/prozac0401/Workspace/releases
