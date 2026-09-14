# Windows 실기 실행 안내

2026-09-14 · 결과는 [Windows E2E 보고서](WINDOWS_E2E_REPORT.md), 요구 전체는 [인수 기준](ACCEPTANCE_TESTS.md)을 따른다. 매크로 알림과 경고 대화상자는 실제 화면에서 확인한다. 무인 전체 GUI 실행기는 아니다.

## 빌드·기능

기존 Excel을 사용자가 저장·종료한 뒤 도구 루트에서 **Windows PowerShell 5.1**로 실행한다. 매번 새 RunId로 증거를 보존한다.

```powershell
powershell.exe -NoLogo -NoProfile -STA -File tests/Invoke-WindowsE2E.ps1 -Phase Build -RunId build-01
powershell.exe -NoLogo -NoProfile -STA -File tests/Invoke-WindowsE2E.ps1 -Phase Functional -RunId functional-01
```

Build는 정상 Excel 시작으로 저장된 XLAM의 버전과 내장 19개 검사를 실행한다. Functional은 실제 COM에서 SLC_Run, 서로 다른 파일, 닫힌 A 스냅샷, 개수, 결과 수식 여부와 원본 파일 해시를 검사한다. 둘은 자동 로드·GUI 검사의 대체물이 아니다.

Preflight의 기존 COM VBProject 진단은 `/automation` 경로의 관찰이다. 시험 Office에서는 이 경로가 차단돼도 정상 시작 빌드는 가능했다. COM 진단만으로 빌드를 판정하지 않는다. 원시 baseline에는 로컬 식별자가 있으므로 공개하지 않는다.

## 설치 수명주기

```powershell
$env:SLC_SETUP_NO_PAUSE = '1'
cmd.exe /d /c 'Release\Install.cmd -ConfirmProduct SLC-68A45C44-2026'
powershell.exe -NoLogo -NoProfile -STA -File tests/windows-normal-start.ps1 -FixturePath artifacts/Guide-A.xlsx -OutputPath artifacts/start-01.json -ExpectInstalled
```

제품 ID는 이미 승인받은 제품 설치 확인을 생략한다. RC2에서는 제품 설치 폴더 한 곳의 신뢰 위치 등록도 설치 범위에 포함한다. 하위 폴더와 다른 위치, 전체 매크로 설정은 변경하지 않는다. 기본 사용자는 옵션 없이 실행해 등록 범위가 표시된 확인창과 마지막 대기를 본다.

Normal-start는 시험용 일반 XLSX만 정상 Excel로 연 뒤 소유 PID·자동 로드·Cell/Row/Column 메뉴 1개씩·도구 모음 4개를 읽는다. 먼저 XLAM을 열거나 AttachUI를 호출하지 않는다. 관찰 후 시험 파일을 화면에 남긴다.

생성한 PID와 디렉터리를 확인한 뒤 windows-close-owned.ps1로 해당 프로세스의 시험 파일만 닫는다. 알 수 없는 파일이 있으면 중단한다. 완전 종료를 기다린 뒤 재시작 → 재설치 → 재시작 → 제거 → 재시작을 반복한다. 제거 후에는 -ExpectInstalled를 빼서 제품 메뉴 0개와 자동 로드 없음을 검사한다.

## 선택·경고·복구

정상 로드된 시험 전용 Excel PID에 한해 사용한다.

- windows-public-matrix.ps1: SLC_Run의 14개 선택·필터·수동 계산·이전 결과 보존 검사.
- windows-warning-cases.ps1: 20,000셀 경고에서 **아니요**, 빈 B, 병합 셀, 4,097자 안내를 화면에서 확인·닫는다. 기준과 설정을 확인한 뒤 보존된 기준으로 비교한다.
- 실제 Esc는 도구 모음으로 대량 작업을 시작하고 진행 상태가 보일 때 누른다. 취소 메시지와 기준 보존을 확인한다. 시간 보호 메시지는 Esc 통과가 아니다.

## 설치 보호·실패 주입

- windows-install-rollback.ps1 -ReleaseDirectory Release -OutputDirectory artifacts/rollback-01: 이 시험에서 설치한 제품 전용이다. 소유 매니페스트 교체 실패를 주입하고 기존 5개 파일 해시와 모든 OPEN 값을 비교한다.
- windows-remove-owned.ps1: 시험용 추가 파일을 만든 뒤 Uninstall.cmd가 보존하는지 검사한다. 시험이 만든 해당 파일만 확인 후 정리한다.
- Invoke-WindowsE2E.ps1 -Phase Guards: **제품 미설치 상태 전용**. 기존 Excel 보호, mutex, 반복 제거, XLAM이 없는 격리 패키지의 설치·진단 거절을 검사한다.

- windows-trusted-location.ps1 -OutputDirectory artifacts/trust-isolated-01: 실제 Office 설정과 분리한 HKCU 시험 브랜치에서 신뢰 위치 소유권·외부 수정·동시 생성·중단 단계·롤백·RC1 업그레이드를 검사한다. 실제 Excel 시작 검증은 별도로 수행한다.

종료 코드: 0 성공, 1 일반 실패, 2 제품 확인 거절, 3 Excel 실행 중, 4 잠금 충돌, 5 VBA 빌드 접근 차단, 6 사용자 신뢰 위치 차단 정책. 마지막에 초기 보안·타 추가 기능·설치·프로세스 상태를 비교하고 복원 결과를 기록한다. 전체 경계값·다른 Office 버전은 별도 인수 범위다.
