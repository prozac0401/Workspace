# Excel Smart List Compare · Windows E2E 실제 실행 보고서

작성일: 2026-09-14 · 제품 소스 버전: 0.2.0 · 상태: **BLOCKED_POLICY / 배포 승인 불가**

**후속 실행:** 사용자의 AccessVBOM 임시 허용·원복 승인을 받고 재시도했지만 Excel은 여전히 접근을 거부했다. 실제 COM 오류 수집을 수정하고 원복을 검증했다. [승인 후 재검증 보고서](WINDOWS_APPROVAL_RETEST_REPORT.md)를 먼저 확인한다. 아래 최초 실행 결과는 당시의 설정·Excel 버전·증거를 보존한 기록이다.

실제 Windows Excel을 실행해 환경, 설치 안전장치, 합성 파일 생성과 종료를 검증했다. **VBA 프로젝트 접근 차단으로 XLAM 빌드에 실패했다. 따라서 설치 가능한 Release, 제품 기능 검증, 설치→재시작→재설치→제거 완료를 달성하지 못했다.** Windows 데스크톱도 잠겨 있어 GUI 클릭 검증은 차단됐다. Python 통과는 Excel 제품 기능 통과가 아니다.

## 입력과 작업 경계

- 원격: `https://github.com/prozac0401/Workspace`, 커밋 `e9e20e3efc15c042949721bdee8db8e835d70749`.
- 원격의 `CODEX_EXCEL_E2E_TEST_PROMPT.md` 및 `ExcelSmartListCompare_v0.2_Source.zip`을 별도 clone으로 받았다.
- 원본 ZIP SHA-256: `1096DFFF947442501F8ED9C906710A7DB146271055F47BB30F6528E317013319`.
- 작업 위치: `WORKSPACE/ExcelE2E-20260914/project/ExcelSmartListCompare_v0.2/`. 기존 Workspace 소스는 수정하지 않았다.
- 원본 지시/README/인수 기준/설치 스크립트/VBA/테스트와 Workspace 도구·문서 정책 및 양식을 읽었다.
- 원본 보고서는 역사적 기록으로 보존한다. 새 Windows 결과의 근거로 원본 Linux 로그를 재사용하지 않았다.

## 실제 환경

| 항목 | 확인값 |
|---|---|
| OS | Windows 11 Pro, 10.0.22631 |
| Windows 실행기 | Windows PowerShell 5.1.22621.6133, `powershell.exe -NoProfile -STA -File` |
| 명령 환경 | Windows 네이티브, WSL 아님 |
| 계정/세션 | 실행 SID와 같은 세션 Explorer SID 일치, 일반 사용자, 비관리자 |
| HKCU/LocalAppData | 해당 데스크톱 계정과 일치; 공개 보고서의 SID·계정·프로필은 마스킹 |
| Excel 파일 버전 | 16.0.20326.20132 |
| 실제 Excel COM | Version 16.0, Build 20326, Windows (64-bit) NT 10.00 |
| Excel 자체 비트수 | EXCEL.EXE PE Machine `0x8664` = x64. PowerShell 비트수에서 추정하지 않음 |
| VBA 프로젝트 접근 | 새 Workbook의 VBProject/VBComponents 접근 실패. 실제 빌더도 해당 제한에서 중단 |
| 매크로 실행 | XLAM을 만들지 못해 미실행. 허용 여부도 입증하지 못함 |
| AutomationSecurity | 테스트·설치용 새 인스턴스에서 `2`(ByUI). 보안 설정 완화 없음 |
| 화면 | 접근성 트리는 읽혔으나 캡처는 Windows 잠금 화면. 클릭/시각 검증 증거로 사용하지 않음 |

## 실제 결과 표

증거 기준 폴더는 `artifacts/windows-e2e/20260914-1346/`이다. 원시 로그/계정 정보는 로컬 전용이다. 배포 후보에는 식별자를 가린 `evidence/windows-e2e/` 요약 및 로그만 포함한다.

| ID | 검증 계층 / 환경 | 기대값 | 실제값 | 상태 | 증거 |
|---|---|---|---|---|---|
| ENV-01 | 네이티브 Windows/계정 | 실제 데스크톱 계정과 일치 | SID/세션 일치, 비관리자 | PASS | `baseline-before.json` |
| ENV-02 | Excel 실행 파일 | Excel 자체 비트수 확인 | PE x64, 파일 버전 확인 | PASS | `baseline-before.json` |
| ENV-03 | 실제 COM | 새 인스턴스 생성/종료 | PID 3440에서 생성·Workbook 생성·Quit; 최종 잔존 없음 | PASS | `excel-preflight.json`, `restoration.json` |
| ENV-04 | VBA 빌드 권한 | VBA 컴포넌트 가져오기 가능 | 접근 차단 | BLOCKED_POLICY | `build-policy.log` |
| ENV-05 | 정상 Excel 시작 | 합성 파일 열림 | `/x` 시작 PID 15472에서 Synthetic-B 열림, 접근성 트리 확인 | PASS | `normal-start.json`, `evidence/windows-e2e/ui-observation.json` |
| ENV-06 | 실제 화면/입력 | Excel 화면과 버튼 조작 | 초기 activation/geometry 오류, 이후 잠금 화면 확인. GUI 검증 중단 | BLOCKED_ENV | `evidence/windows-e2e/ui-observation.json` |
| FIX-01 | Python/한국어 Windows | UTF-8 파일 정상 읽기 | 원본 53개 중 오류 4개 → 수정 후 53개 통과 | PASS | `python-original.log`, `python-fixed.log` |
| FIX-02 | 실제 `.cmd` | 내부 실패 코드 보존 | 원본 내부 실패에도 0 → 수정 후 VBA 차단 5 | PASS | `cmd-original.log`, `cmd-original.exitcode.txt`, `cmd-fixed-build.exitcode.txt` |
| SRC-01 | 가져오기 파일 | UTF-8와 ASCII 동기화 | exporter 실행, 동기화 검사 통과. VBA 비교 로직 변경 없음 | PASS | `ascii-export.log`, `python-fixed.log` |
| SRC-02 | PowerShell 문법 | 파서 오류 없음 | 최종 스크립트 파서 검사 | PASS | `parser-final.json` |
| I01 | 실제 Excel Build | 테스트 후 XLAM 생성 | VBA 접근 단계에서 종료 5, XLAM 없음 | BLOCKED_POLICY | `cmd-fixed-build.log` |
| I04-a | `.cmd` + 실제 열린 Excel | 설치 중단, Excel 보존 | Install 종료 3, 소유 PID 유지 | PASS | `guards/GUARD-OPEN-INSTALL.log`, `guards/guards.json` |
| I04-b | `.cmd` + 실제 열린 Excel | 제거 중단, Excel 보존 | Uninstall 종료 3, 소유 PID 유지 | PASS | `guards/GUARD-OPEN-UNINSTALL.log`, `guards/guards.json` |
| I04-c | `.cmd` + 실제 열린 Excel | Build/Test도 중단 | 각각 종료 3 | PASS | `guards/guards.json` |
| I05 | 실제 빌더 | 정책 우회 없이 실패 | VBA 접근 차단 안내, 정책 변경 없음 | PASS | `cmd-fixed-build.log`, `restoration.json` |
| I09-a | 이름 있는 제품 mutex | 경쟁 요청 거절 | 시험 프로세스가 mutex 보유 중 Install/Uninstall 각각 종료 4 | PASS | `guards/GUARD-LOCK-INSTALL.log`, `guards/GUARD-LOCK-UNINSTALL.log` |
| I09-b | 설치와 제거의 실제 동시 실행 | 파일/등록 충돌 없음 | 두 실제 설치 트랜잭션의 동시 실행은 미실행 | NOT_RUN | XLAM 빌드 차단 |
| I07-absent | 미설치 제거/재제거 | 안전하게 종료 | 두 번 모두 종료 0, 제품 폴더 생성 없음 | PASS | `guards/GUARD-ABSENT-UNINSTALL.log`, `guards/GUARD-ABSENT-REUNINSTALL.log` |
| TEST-missing | 실제 Test_Excel.cmd | 없는 바이너리 실패 | 종료 1 | PASS | `guards/GUARD-MISSING-XLAM-TEST.log` |
| DATA-01 | 실제 Excel 합성 파일 | A/B 실제 xlsx 생성 | 두 파일 생성·정상 닫기, SHA-256 기록 | PASS | `synthetic-data/fixture.json`, `synthetic-data-create.exitcode.txt` |
| RUNNER-01 | 재실행기 | 차단 상태/종료 코드 전파 | Preflight 종료 5, 전후 snapshot 기록 | PASS | `../20260914-runner-preflight-fixed/commands.json` |
| RESTORE-01 | 제품 파일/등록 | 초기 미설치 상태 | 제품 폴더/파일 없음 | PASS | `restoration.json` |
| RESTORE-02 | 보안/타 추가 기능 등록 | 관련 값 보존 | 보안, 정책, OPEN 등록, Add-in Manager, COM Addins 비교 일치 | PASS | `restoration.json` |
| RESTORE-03 | 프로세스 | 시험용 Excel 잔존 없음 | 최종 Excel PID 없음 | PASS | `baseline-after.json`, `normal-start-cleanup.log` |

`GUARD-OWNED-PID-PRESERVED`를 포함한 설치 안전장치 실행은 10개 PASS이다. 이는 성공 설치 10건을 의미하지 않는다. 원본 빌드 시 기존 PID 24632를 감지한 중단도 실제로 확인했다.

## 실행하지 못한 제품 검증

| ID / 범위 | 미실행 항목 | 상태 / 이유 |
|---|---|---|
| API-01 | 실제 XLAM의 SLC_Version, SLC_TestAll, SLC_AttachUI, SLC_UiReady | BLOCKED_POLICY — XLAM 빌드 불가 |
| S01~S09 | SLC_Run 가로/세로/사각형/단일/다중/겹침, 두 실제 파일 비교, 원본 종료 후 snapshot, 독립 프로세스 경계 | BLOCKED_POLICY |
| F01~F08 | AutoFilter/Table, 숨김 행·열, 제목/합계 제외, 빈칸/오류/병합, 계산 상태 | BLOCKED_POLICY |
| C03~C08 | 성공/오류/취소 설정 복원, 이전 결과, HasFormula=False, 실제 정규화·개수 비교, Undo | BLOCKED_POLICY |
| P01~P10 | 19,999/20,000/100,000/100,001, 조각·스캔·문자 상한 전후, 경고 아니요, Esc, 성능 단계별 실측 | BLOCKED_POLICY — 참조 테스트 통과로 대체하지 않음 |
| I02/I03/I06/I07/I08 | Release 설치, 정상 시작 자동 로드, 재시작, 재설치, rollback, 실제 제거 후 재시작, 설치 폴더의 사용자 파일 보존 | BLOCKED_POLICY |
| I10 | 한국어/공백 경로의 성공 설치 및 x86 Excel | NOT_RUN — 현재 빌드 불가, x86 Excel 환경 없음 |
| C01/C02/I11 | 타 추가 기능/메뉴/PERSONAL.XLSB/단축키의 제품 설치 전후 실제 공존 | NOT_RUN — 제품 미설치. 레지스트리 보존 관찰과 구분 |
| GUI-01 | 셀/행/열 우클릭, 추가 기능 탭, 두 파일 선택→기준→비교, 경고 기본 버튼/거절/취소 | BLOCKED_ENV 및 BLOCKED_POLICY |
| SETUP-CANCEL | 기본 설치/제거 확인창의 아니요 및 종료 2 | NOT_RUN — 잠긴 데스크톱. 기본 확인 코드는 유지 |
| SIGN-01 | 조직 서명/승인 배포 및 모든 Office 버전 | NOT_RUN — 조직 결정/다른 환경 없음 |

## 수정 사항과 확인된 오류

1. `tests/test_reference.py`: UTF-8 인코딩 지정으로 실제 한국어 Windows CP949 오류 4개 해결.
2. 네 `.cmd`: `pause` 전에 종료 코드 저장, 마지막에 그대로 반환. 기본 사용자 대기는 유지. `%*`로 제품 한정 확인 인자를 전달.
3. `Setup.ps1`: 제품 한정 명시적 확인 옵션과 종료 코드 2/3/4/5 추가. VBA·매크로·신뢰 위치·PowerShell 정책을 변경하는 코드는 추가하지 않음.
4. Windows 실행기, 계정/등록 snapshot, 소유 PID 정리, 합성 파일 작성, 설치 guard 및 COM 기능 실행기 추가. [설계 결정](ADR-0001-Windows-test-entrypoints.md) 참조.

VBA 본체를 실행할 수 없어 비교 엔진 오류가 없다고 결론내리지 않는다. 새 `windows-functional.ps1`은 SLC_Run/닫힌 A snapshot/독립 기대값/출력/원본 해시 검사용 코드지만, XLAM 실행 경로는 **NOT_RUN**이다. 파서 검사만으로 기능 성공을 주장하지 않는다.

시험 도구의 개발 중 오류도 보존했다. 최초 guard 실행은 Windows PowerShell의 stderr 처리가 조기 중단시켜 cmd 내부 stderr 결합으로 수정했다. 열린 xlsx의 배타적 해시 읽기 실패는 파일을 정상 닫고 해시하도록 수정 후 두 파일 생성 성공을 재확인했다. 정상 시작의 ROT 연결 첫 시도는 `MK_E_UNAVAILABLE`로 실패했다. 최종 합성 파일 세션의 PID 확인/정상 Quit은 성공했다. 재실행기 첫 preflight의 C# heredoc 편집 오류도 수정 후 실제 종료 5를 확인했다.

## 사용자 데이터 보호와 복구

초기 제품은 미설치였다. 시작 전부터 존재한 PID 24632는 임의 종료하지 않았으며, 사용자가 해당 PID 중지를 명시 승인한 뒤 COM으로 PID와 열린 통합문서 0개를 확인했다. 정상 `Quit` 후에도 남아 있어 **승인된 그 PID만** 중지했다. 이 명시적 사용자 요청은 초기 프로세스 복구 대상에서 제외한다.

테스트가 만든 Excel만 정상 종료했다. 업무 파일을 열거나 저장하지 않았다. 합성 자료와 로그는 별도 작업 폴더에만 남긴다. 최종 제품은 미설치이며 제품 등록, 보안/정책, 타 추가 기능 등록은 보존됐다. Excel이 정상 실행 중 갱신한 일반 옵션 전체를 덮어써 복원하지 않았다. 원시 계정/경로/로컬 진단은 ZIP 공개본에서 제외한다. 화면 캡처가 잠금 화면이었으므로 Excel 스크린샷으로 첨부하지 않는다.

## 산출물과 재개 조건

- 수정 소스와 Windows 테스트: 이 프로젝트 및 `tests/`.
- 합성 xlsx 두 개 및 원시 실행 증거: `artifacts/windows-e2e/20260914-1346/`.
- 공유 가능한 결과: `evidence/windows-e2e/`.
- `Release/BUILD_BLOCKED.txt`: 설치 가능한 배포물이 아님을 명시. `.xlam` 및 성공을 암시하는 가짜 테스트 결과는 만들지 않았다.
- `ExcelSmartListCompare_v0.2_SourceCandidate_BLOCKED_POLICY_20260914.zip`: **소스 배포 후보**이며 최종 사용자 설치용 ZIP이 아니다. 설치 가능한 Release/ZIP 요청은 미완료다.
- 원본/수정 비교: `CHANGES.patch`. 해시: 프로젝트 `SHA256SUMS.txt`, 작업 폴더 `DELIVERABLES_SHA256.txt`.

승인된 VBA 빌드 환경(또는 사용자가 준비한 해당 접근)과 잠금 해제가 필요하다. 준비 후 [Windows 실행 안내](WINDOWS_TEST_RUNNER.md)에 따라 실제 빌드부터 재개한다. 마지막 빌드 XLAM의 해시를 실제 설치본 및 최종 배포본과 대조하기 전에는 배포 완료로 표시하지 않는다.

## 기술 근거

COM 기본 보안값을 신뢰하지 않고 기존 ByUI 의도를 유지한다. [Microsoft: AutomationSecurity](https://learn.microsoft.com/en-us/office/vba/api/excel.application.automationsecurity). VBA 프로젝트의 프로그래밍 접근 신뢰는 별도 접근 설정이다. [Microsoft: Office solution security](https://learn.microsoft.com/en-us/office/vba/library-reference/concepts/security-notes-for-microsoft-office-solution-developers). 이 문서는 동작 근거이며 본 제품의 테스트 성공 증거가 아니다.
