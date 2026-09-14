# 승인 후 실제 Excel 재검증

> 이 문서는 잠금 해제 전의 과거 실행 기록이다. 정상 시작 경로로 빌드를 완료한 후속 결과는 [현재 Windows E2E 보고서](WINDOWS_E2E_REPORT.md)에 있다. 아래 차단 상태를 최종 후보의 현재 상태로 해석하지 않는다.

실행일: 2026-09-14 15:20~15:29 KST · 상태: **BLOCKED_POLICY / BLOCKED_ENV**

사용자가 현재 계정의 `HKCU\Software\Microsoft\Office\16.0\Excel\Security\AccessVBOM` 한 항목의 임시 허용과 원복을 승인했다. 새 Excel을 시작하기 전에 DWORD 1을 기록하고 실제 빌드·진단을 실행한 뒤, 각 실행의 `finally`에서 원래의 **값 없음** 상태로 복원했다. 다른 매크로 보안, 신뢰 위치, PowerShell 실행 정책, 추가 기능 설정은 변경하지 않았다.

**승인된 값을 적용해도 Excel이 VBA 프로젝트 접근을 거부했다.** 따라서 XLAM, 실제 비교 기능, 성공 설치·재시작·재설치·제거, Excel 설치용 릴리즈는 여전히 미완료다. 승인 대기가 원인인 상태는 해소됐지만, 실제 접근 차단은 해소되지 않았다.

## 실제 확인

| ID | 검증 / 기대값 | 실제 결과 | 상태 | 로컬 증거 |
|---|---|---|---|---|
| APPROVAL-01 | 승인 항목만 임시 적용하고 빌드 | AccessVBOM DWORD 1, Build 종료 5 | BLOCKED_POLICY | `20260914-approved-build-01/` |
| DIAG-01 | Excel의 원래 COM 오류 확인 | `0x800A03EC`, “Visual Basic 프로젝트는 프로그래밍 방식으로 액세스할 수 없습니다.” | PASS — 진단 수집 | `20260914-approved-diagnostic-01/` |
| DIAG-02 | 다른 계정·세션 또는 설정 원복 타이밍 문제인지 확인 | Excel과 PowerShell의 SID·세션 일치. Excel 시작 후에도 AccessVBOM=1 | PASS — 환경 확인 | `20260914-approved-diagnostic-02/` |
| DIAG-03 | `/x`로 시작한 Excel의 VBA 접근 비교 | 30초 안에 ROT 자동화 연결을 얻지 못해 비교 불가 | BLOCKED_ENV | `20260914-approved-normal-diagnostic-01/` |
| FIX-03 | 실패 원인을 잃지 않고 보고 | COM 속성의 직접 읽기가 null을 반환하는 현상을 확인. 명시적 속성 호출로 실제 Excel 오류와 HRESULT 보존 | PASS | `20260914-approved-diagnostic-fixed/excel-preflight.json` |
| BUILD-02 | 수정한 빌더로 승인 항목 적용 후 재빌드 | 원래 Excel 오류와 HRESULT를 출력하고 종료 5. XLAM 없음 | BLOCKED_POLICY | `20260914-approved-build-02/` |
| RESTORE-04 | 승인 범위 원복 | 임시 적용한 5회 모두 AccessVBOM 삭제로 원상복구 | PASS | 각 실행의 `accessvbom-approval-restoration.json` |
| SRC-03 | 수정 소스의 기존 Python/파서 검증 | Python 53개, Windows PowerShell 5.1 파서 9개 통과 | PASS — Excel 기능 검사 아님 | `20260914-approved-diagnostic-fixed/parser.json` 및 명령 출력 |
| GUI-02 | 실제 FolderState 창 캡처 | 접근성에는 시험 창이 보였지만 이미지는 Windows 잠금 화면. 캡처 자료로 사용하지 않음 | BLOCKED_ENV | `evidence/windows-e2e/approval-retest-summary.json` |

위 실행 폴더들은 유지보수 소스의 `artifacts/windows-e2e/` 아래에 있다. 작업은 WORKSPACE의 별도 `ExcelE2E-20260914/upstream/tools/ExcelSmartListCompare/`에서 수행했다. 원시 계정·경로·레지스트리 로그는 로컬 전용이며 배포 자산에 포함하지 않는다.

이번에 실제 확인한 Excel 실행 파일은 **16.0.20326.20144, x64**다. 이전 보고서의 16.0.20326.20132와 구분한다. Office를 업데이트하거나 복구하는 작업은 수행하지 않았다. Windows 11 Pro 10.0.22631, Windows PowerShell 5.1.22621.6133, 실제 데스크톱 계정의 일반 사용자 환경이다. COM 인스턴스의 `AutomationSecurity=2`를 유지했다.

## 수정과 복구

`Setup.ps1`과 `tests/windows-excel-preflight.ps1`에서 `VBProject` 속성을 명시적으로 호출해 원래 COM 예외를 보존했다. 기존에는 직접 속성 읽기가 null을 반환하면서 뒤따른 속성 오류만 남길 수 있었다. 설치기에는 보안 설정 변경 기능을 추가하지 않았다. VBA 비교 로직은 변경하지 않았다.

COM으로 만든 시험 인스턴스들은 `Quit`으로 종료했다. `/x` 비교 진단의 빈 시험 인스턴스 PID 26308은 ROT 연결 및 주 창 종료가 불가능해, 실행 경로·인수·생성 시각이 이번 시험과 일치함을 확인하고 **그 시험 PID만** 중지했다. 이 인스턴스에는 사용자 파일을 열지 않았다. FolderState 시험 창은 정상 종료했다. 이 정리 내역은 로컬 `upstream/artifacts/approved-diagnostic-cleanup.json`에 남겼다.

최종 제품 설치 상태는 미설치다. 기존 사용자 Excel을 종료하거나 업무 파일을 읽지 않았다. 관련 보안·추가 기능 등록의 전후 비교는 `evidence/windows-e2e/approval-retest-summary.json`에 기록한다. 다른 프로그램의 레지스트리 키 전체를 덮어쓰는 복원은 하지 않았다.

## 남은 작업

Windows 잠금을 해제한 실제 데스크톱에서 Excel의 승인된 VBA 접근 항목이 어떻게 표시되는지 확인하고, 같은 승인 범위에서 빌드를 재개해야 한다. 한 항목을 허용해도 접근이 거부되는 근본 원인은 아직 확정하지 못했다. 추가 보안 항목을 임의로 변경하지 않는다. 실제 화면 캡처와 기능·설치 수명주기 검증 전까지 Excel draft는 설치 불가능한 **소스 후보**로 유지한다.

[Microsoft의 VBA 접근 안내](https://learn.microsoft.com/en-us/office/vba/library-reference/concepts/security-notes-for-microsoft-office-solution-developers)는 VBA 프로젝트 접근 설정을 필요한 동안만 허용하고 이후 해제하도록 안내한다. 이는 설정의 기술 근거이며 이 제품의 기능 통과 증거는 아니다.
