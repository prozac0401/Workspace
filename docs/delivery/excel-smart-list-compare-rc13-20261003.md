# Excel 명단 비교 RC13 · 실행·출하 준비

최초 기록: 2026-10-03 KST · 현재 계정 제안·정체 정정: 2026-10-04 KST · 책임: 도구 개발·검증 담당

상태: 최종 EXE 실제 설치·대표 비교·native 보존 대조 완료 · T11 부분 기록 보존 · 평가 출시 준비

제품 버전: `0.2.0-rc.13` · 프로필: `focused-wording-evaluation` · `fullAcceptancePassed=false`

## 승인 범위와 변경

사용자가 선택한 작은 사용성 개선의 필요한 검사·버전·패키지·PR·병합·릴리스 준비 범위에서 명단 비교만 순차 진행한다. 제품 변경은 담은 첫 목록 요약의 기존 Replace 명령 안내와 릴리스·설치 버전 문자열이다. 비교 엔진·설정·스냅샷·취소·복구·설치 엔진의 기능은 바꾸지 않는다.

기준 소스는 `e41999684c6a21070e5d6fc96ebed593b0529b1d`, 원래 선택된 패치는 PR #10의 `82a690f624e83470129c8832688ec74356062745`다. 실제 제작 입력의 동결 커밋은 [Draft PR #13](https://github.com/prozac0401/Workspace/pull/13)의 `9ebaf3d661e1602e7bc6e60be4b9a0c0fe079160`이다. 기존 R12 공개 자산과 과거 검증 문서는 보존한다.

사용자는 후속 답변으로 SmartList부터 진행하고 임시 VBA 프로젝트 접근을 허용했다. 처음에는 기존 RC11 설치를 바꾸지 않는 격리 BuildOnly·새 안내/Replace를 확인했고, 이후 승인된 현재 계정 Upgrade·부분 T11·제품 복구를 진행했다. 공개 배포는 실행하지 않았다.

이후 새 안내·Replace 실제 흐름을 실행했다. 최신 StatusBar 경중·필수 시험·배포조건 재분석과 조정 요청에 근거해 개발 담당은 [ADR-0022의 좁은 평가 조건](../../tools/ExcelSmartListCompare/docs/ADR-0022-R13-known-statusbar-evaluation.md)을 채택했다. 사용자가 이 완성 문안이나 최종 파일 게시를 승인했다는 뜻은 아니며 회사·조직의 승인도 아니다.

## 실제 결과

2026-10-04 최종 확인을 완료했다. 설치·시험 문서 정리·Excel 정상 종료는 사용자 확인, 대표 비교는 검증 담당의 Sky 실제 UI 관찰, 설치 경로·파일 해시·선정 설정은 일반 PowerShell의 native 읽기 대조로 구분한다. 각 목록 3개·제외 0개, Beta 2 대 1·첫 목록 초과 1개, Gamma 0 대 1·둘째 목록 초과 1개의 두 차이 행과 원본 여섯 셀 보존을 확인했다. 마지막 probe는 Excel 부재를 전후 검사했고 native 13개 객체와 선정 상태의 읽기 전후 불변을 확인했다.

최종 native 원시 SHA `a96f11a0633f11fa54f100f03ba09876b9750e21bf5802660f6a86a20f6bc546`에서 설치 XLAM·제품 README/Setup/Uninstall과 관리 엔진 3파일은 prepared payload와 일치했다. 기존 권한 14개는 historical 원문과 같으며 비교 설정·정책·매크로 보안·다른 추가 기능 등록·OPEN·기존 신뢰 위치는 설치 전 native 기준과 같다. 앱 제거 등록의 DisplayVersion·InstallDate만 공식 설치 변경이다. manifest 내용은 probe가 읽지 않아 내부 필드 확인은 주장하지 않는다. 이 결과는 앞선 LocalCache 복구·미완료 T11과 다른 실제 설치 근거다.

최초 UIA 입력의 접근성 값과 화면이 달라 빈 목록 안내가 나왔고 그 근거를 제외했다. 실제 키보드 입력을 화면에서 확인한 뒤 한 번의 유효 비교를 완료했다. 기존 StatusBar FALSE 실패는 남았다. 추가 시험·재설치·제거·RC11 복구는 실행하지 않았다. EXE 내 안내는 준비 당시 동결 snapshot이므로 오래된 '미제작·R12 공개' 문구가 남으며, 최신 상태는 이 기록·릴리스 설명·공개 안내가 우선한다. 같은 EXE를 재빌드하지 않는다.

현재 출시 경로는 [ADR-0024](../../tools/ExcelSmartListCompare/docs/ADR-0024-R13-final-installer-evaluation.md)를 따른다. 사용자가 과도한 시험을 금지하고 **최종 RC13을 설치하고 계속 사용**을 선택했다. 같은 후보의 완료된 제작·소스·새 안내/Replace 근거를 재사용하고 최종 EXE를 한 번 제작해 일반 Windows의 실제 설치·대표 비교 결과와 연결한다. 기존 T11은 PARTIAL / NOT_RUN_INCOMPLETE로 보존한다. 제거·RC11 원복·전체 GUI/성능/취소/설치 suite와 추가 ACL 실험을 반복하지 않는다. 최종 설치·비교·게시가 끝나기 전에는 출시 완료로 표시하지 않는다.

검증 담당이 현재 RC13 소스에서 실행한 집중 검사·격리 제작·저장 소스 audit·실제 새 안내/Replace와 후속 부분 T11을 기록한다. 환경은 Windows 11 10.0.22631, Excel 16.0 Build 20430 x64, Windows PowerShell 5.1.22621.6133이다. 전체 매크로·GUI suite는 NOT_RUN이며 과거 T11의 대표 비교·결과는 잠금 화면으로 미실행이었다. 최종 EXE의 대표 비교는 위 새 기록에서 완료했다.

실제 XLAM의 릴리스 식별자는 `0.2.0-rc.13`, SHA-256은 `484419befa0cd763635b1f9592cff43bd13e657e19d5a693d76a78fa071ed14e`다. 제작 최종 해시와 소스 audit 전후 해시가 일치한다. 아래 최종 EXE는 비공개로 준비했고 ZIP·출하 자산은 아직 완성하지 않았다.

준비 당시 기록: 2026-10-04 커밋 `4e220b1a4b0fb408b2b60b47d1807cb84220ce51`과 ADR-0024 SHA `bab569ef4d97eb641f78f4ee54252c95a75f3049a17e79c8610712af80aeb023`로 `prepare`를 실제 실행했다. `ExcelSmartListCompare-0.2.0-rc.13-Setup.exe`는 2,246,844 bytes, 파일 버전 `0.2.0.13001`, SHA-256 `14b081882513a89ccff4123245bd8950ab87d18d697fdfc6e193f0155d2c8cea`다. compiler는 한 번 실행했고 payload·EXE·비공개 준비 기록만 생성했다. `publicationReady=false`, 실제 설치·대표 비교 NOT_RUN, T11 원시 NOT_RUN_INCOMPLETE를 유지한다. 같은 EXE를 설치 확인 후 재빌드 없이 완성·게시한다.

새 준비/완성 경계는 기존 16개와 신규 4개를 포함한 합성 검사 20 PASS다. 원시 증거 연결 보강 뒤 신규 4개만 다시 확인해 PASS였으며 두 실행을 합산하지 않는다. 문서 strict·공개 19페이지/이전 주소 2개/404·공개 범위·로컬 링크도 PASS, ADR-0024 포함 9문서의 상대 파일 대상 75개는 PASS다. 제품 실물·설치 PASS가 아니며 외부 URL·문단 앵커 시험은 아니다.

| 대상 | 상태 | 근거·완료 기준 |
|---|---|---|
| 소스·버전·RC13 실행기 허용 목록 | 준비 완료 | `SLC_ReleaseVersion` UTF-8/ASCII 쌍, 설치 버전, 허용 버전 한 항목. 실행기 방어는 유지 |
| 현재 집중 소스 검사 | PASS | PR13 전환 후 실제 실행 13 PASS / 0 FAIL / 0 ERROR / 0 SKIP. 명시한 집중 목록만 실행, 전체 suite 아님 |
| ASCII/UTF-8 VBA 내용 대조 | PASS | 5쌍 일치. 실제 VBA 컴파일·Excel 실행 아님 |
| RC12 대비 제품 변경 범위 | PASS | RC12 태그의 `c1e365d2155a594d4b864609da7656796bd1a345`와 실제 source scope_guard 대조. 요약 안내 한 줄·릴리스/설치 버전만 변경, 5쌍 일치, 나머지 엔진·설치 입력 불변 |
| PowerShell 구문 | PASS | `Setup.ps1`·`Invoke-IsolatedExcelCandidate.ps1` 두 AST 파싱 PASS |
| RC13 packager 구문·합성 방어 | PASS | Python AST 파싱 PASS, 합성 방어 4 PASS. 다른 SHA, NOT_RUN, 중복 JSON 필드, 선택하지 않은 엔진 변경 거절 |
| 강화한 평가 포장 게이트 집중 검사 | 최종 16 PASS / 0 FAIL | 합성 방어 검사. 이전 게이트 13개·14개 실행과 제품 소스 집중 13 PASS를 별도로 보존하고 합산하지 않음 |
| 임시 VBA 프로젝트 접근 | 승인 이행·두 시도 원복 PASS | 사전 일반·정책 경로 8곳의 부재 확인 후 명시적 승인을 받음. 두 제작 시도 각각 AccessVBOM 값 부재 → 임시 DWORD 1 → 값 부재로 정확히 복원 |
| 격리 BuildOnly | 첫 시도 FAIL·새 출력 경로 한 번 재시도 PASS | 첫 시도는 후보 저장 전 audit 파일 교체 IOException, 근본 원인 미확정. 재시도에서 RC13 후보 저장·in-memory import 대조 PASS, tests=[] |
| 저장한 XLAM·VBA 7개 모듈·RibbonX·릴리스 버전 | 첫 환경 FAIL·기존 문서 환경 PASS | 첫 Python의 oletools 누락으로 추출 0개·소스 audit FAIL. 의존성 설치 없이 기존 환경으로 같은 후보 재확인·모듈 7개·패키지 대조 PASS, 전후 SHA 동일 |
| 제작 세션 정상 종료·제한된 설치 보존 | 두 시도 PASS | 소유 Excel 자연 종료·AccessVBOM 정확한 원복·기존 Excel 보존, cleanupErrors 없음. helper의 5개 파일과 OPEN·Add-in Manager·제품 Trusted Location 대조 |
| 넓은 선정 파일·설정 보존 | 최종 기준 일치 PASS | 기존 제품·Setup 파일 10개 해시·선정 32개 레지스트리 대조 행 일치. Options의 Pos 원래 값 확인 후 해당 값만 복원, 전체 Windows 설정 검증으로 확대하지 않음 |
| 첫 native | 부분 FAIL·미완료 | 실제 StatusBar FAIL과 별도로 기존 설치 UI 분리의 Workbooks 열거 준비 결함 확인. 메뉴 간섭 원인 미확정. Pos 복구는 별도 PASS |
| 두 번째 새 요약/Replace 실제 흐름 | flowComplete=true·총 native FAIL | 실제 증거 평가 11개 PASS / excelGlobalsPreserved 1 FAIL. typed globals 8개 중 StatusBar만 Boolean False → String FALSE, 기능·이전 결과·보존·정리 완료 |
| 알려진 StatusBar 평가 수용 | 실제 입력 통합 대조 PASS | 기본 게이트는 실제 native FAIL 거절, 정확한 후보·결정 SHA와 명시적 opt-in만 수용. 실제 FAIL 원문 유지,다른 필수 조건 유지 |
| 전체 내장 기능·GUI suite | NOT_RUN | 실제 확인은 선택된 합성 한 흐름. BuildOnly의 비어 있는 tests 목록도 기능 시험 PASS가 아님 |
| T11 새 후보 설치·대표 비교·결과·제거 | PARTIAL / NOT_RUN_INCOMPLETE | Upgrade·설치 후보 자동 로드·제거·RC11 파일/등록 복구 확인. 잠금 화면으로 UI 입력 0회·비교/결과 미실행. 폴더 AI 표시 차이와 LastPurgeTime 관찰값 보존·정확 원복 미완료 |
| 최종 EXE 실제 설치·대표 비교 | NOT_RUN | ADR-0024의 RC13 유지 경로, 제거·RC11 원복 반복 없음 |
| EXE·ZIP·버전·구성·SHA-256·공개 기록 | 최종 EXE 비공개 준비 PASS · ZIP·출하 자산 미완성 | 같은 EXE 설치 후 재빌드 없이 완성, 로컬 로그·사용자 정보 제외 |
| strict 문서 빌드·생성 링크·공개 범위 | 2026-10-03 갱신 후 PASS · 2026-10-04 계정 결정·정체 정정 후 PASS | MkDocs strict 성공. 공개 19개·이전 주소 2개·404·검색·사이트맵·로컬 링크 확인. 현재 ADR-0023을 포함한 8문서 상대 파일 대상 60개 PASS이며 외부 URL·문단 앵커 시험은 아님. 이전 7문서 46개와 소스 준비 시점 31개 결과도 별도 보존. RC13 내부 문서는 공개 사이트에서 제외 |
| Draft PR | #13 게시·검토 중 | 소스·문서·제작 방어 변경의 초안이며 이번 실제 제작 결과 반영 중. 출시 완료를 뜻하지 않음 |
| 패키지·병합·태그·Release·다운로드 | NOT_RUN | 실제 후보 검토와 출하 판단 후 정확한 소스·자산·해시 일치 |

현재 집중 목록은 기존 오래된 시트명 기대값의 `UsabilitySourceContracts.test_difference_is_one_sheet_and_preview_has_locations`를 검사명으로 명시해 포함하지 않았다. 이 제외는 runner의 skip 결과가 아니므로 0 SKIP과 모순되지 않는다. 13개 선정 검사 PASS를 전체 `test_usability.py` 또는 전체 suite PASS로 표시하지 않는다. 오래된 기대값 문제와 과거 82/1/2 결과는 아래에 보존한다.

초기 합성 제작 방어 4건과 최종 포장 게이트 집중 16 PASS는 실제 후보 출하 완료가 아니다. 제품 소스 13 PASS와 포장 게이트의 이전 13개·14개 및 최종 16개 실행은 대상·시점이 달라 합산하지 않는다. 같은 후보의 제작·저장 소스·선택 native 흐름과 실제 StatusBar 평가 수용을 확인했지만 T11 증거가 없어 포장 명령은 거절됐고 패키징하지 않았다.

## 제작 시도와 증거 범위

첫 제작 시도는 Excel 자동화 설정 후 audit 파일을 원자적으로 교체하는 Save-Audit 단계에서 IOException으로 종료했다. 후보 저장 전이므로 candidateSaved=false, probe=NOT_RUN이며 제품 기능을 실행한 실패가 아니다. 파일 교체 오류의 근본 원인은 미확정이다. 실패 기록을 보존하고 같은 입력을 새 출력 경로에서 한 번 재시도했다.

재시도 BuildOnly는 후보 저장·입력 7개 해시·in-memory import 대조·소스의 RC13 릴리스 식별자·최종 후보 해시를 기록하고 PASS로 종료했다. 두 시도 모두 cleanupErrors=[]이며 accessRestored·installedPreserved·existingExcelPreserved·excelExited가 true다. 두 시도 각각 없던 AccessVBOM 값을 임시 DWORD 1로 설정한 뒤 값 부재 상태로 복원했으며, 소유 Excel이 자연 종료했다. 종료 실패를 강제 정리로 대체한 결과가 아니다.

helper의 installedPreserved는 install.json·XLAM·Setup.ps1·Uninstall.cmd·README.md의 5개 파일과 OPEN·Add-in Manager·제품 Trusted Location 대조 범위다. 이후 native 정리 후 기존 제품·Setup 파일 10개의 해시와 선정 32개 레지스트리 대조 행의 기준 일치를 확인했다. 정상 시작에서 바뀐 Options의 Pos는 원래 값 확인 후 해당 값만 복원했다. 이 선정 범위의 최종 보존 PASS를 전체 Windows 설정 검증으로 확대하지 않는다.

첫 외부 소스 audit는 선택한 Python 환경에 oletools가 없어 FAIL·추출 모듈 0개였다. 패키지 구조는 PASS였고 후보 전후 SHA는 동일하지만 직렬화 VBA 대조를 마치지 못했으므로 전체 audit PASS로 쓰지 않는다. 새 의존성을 설치하지 않고 기존 문서용 Python 환경에서 같은 XLAM을 읽어 7개 VBA 모듈·RibbonX·패키지 대조 PASS와 전후 SHA 불변을 확인했다. 첫 환경 실패 기록도 보존한다.

## 실제 native와 StatusBar 영향

첫 native는 실제 StatusBar FAIL을 포함한 부분 FAIL과 미완료로 종료했다. 별도로 기존 설치 UI 분리를 Workbooks 열거로 처리한 준비 결함을 확인했으며 메뉴 상태 간섭의 인과는 확정하지 않는다. 이 시도를 성공한 전체 흐름으로 바꾸지 않는다. Pos 원복·기준 대조 PASS는 실패와 구분해 보존한다.

두 번째 native는 기존 설치를 정확한 이름의 Item으로 확인해 해당 세션 UI만 분리한 뒤 같은 후보로 2026-10-03 13:35:21~13:55:43 UTC에 실제 UI 한 흐름을 완료했다. 합성 원본 Alpha/Beta/Beta의 한 Beta를 Gamma로 의도적으로 수정했으며 저장하지 않았다. 첫 확인 파일과 교체 전 두 번째 확인 파일은 Beta를 유지했다. 실제 기존 Replace 명령을 UI에서 실행한 뒤 세 번째 확인 파일에 Gamma·서로 다른 값 3개·추가 개수 0개가 반영됐다. 요약 A14/B14 전체 안내는 두 줄·14항목으로 보였다. 이전 확인 파일·원본 서식·원본 디스크 내용은 보존됐으며 합성 메모리 수정은 의도한 범위였다.

전후 typed globals 8개 중 StatusBar만 Boolean False → String FALSE였다. raw native 총 FAIL, flowComplete=true와 실제 증거 평가의 11개 PASS / excelGlobalsPreserved 1 FAIL을 각각 보존한다. cleanupErrors=[]이며 소유 Excel이 자연 종료했고 남은 Excel은 없다. 후보 SHA는 같고 기존 RC11 설치·등록을 업그레이드·제거하지 않았다. 매크로 포함은 사람이 직접 선택했으며 보안 UI 자동 조작·영구 보안 설정 변경·회사 정책 우회는 하지 않았다.

[Microsoft의 StatusBar 설명](https://learn.microsoft.com/en-us/office/vba/api/excel.application.statusbar)에 따르면 False는 Excel의 제어권이며 기본 상태 표시를 복원하는 값이다. String FALSE는 이 복원이 되지 않는 표시 결함으로 프로세스 안에서 평소 상태 표시가 가려질 수 있다. 이번 합성 데이터 기능이 복구 불가능하거나 중단됐다는 결과는 아니다. 정확한 원인은 미확정이다. 소스에는 이미 literal False 복원이 있고 과거 빈 COM 대조에서도 문자열 FALSE가 관찰됐으며 타 추가 기능의 영향을 배제하지 못했다. 해결 가능성은 있지만 검증되지 않은 한 줄 수정으로 해결했다고 주장하지 않는다.

최신 사용자 요청을 근거로 개발 담당은 ADR-0022에서 이 정확한 실패만 opt-in으로 평가 prerelease에 수용한다. 실제 FAIL·첫 시도 실패·기존 한계를 유지하며 다른 전역·원본·이전 결과·보안·기존 설치·설정·소유 정리·자연 종료는 계속 필수다. 수용 근거는 USER_REQUESTED_ANALYSIS_AND_RELEASE_CONDITION_ADJUSTMENT이며 결정 raw SHA와 정확한 후보를 묶는다. 최종 파일 게시·회사 승인을 받았다는 뜻은 아니다. `fullAcceptancePassed=false`·`stablePublishAllowed=false`를 유지한다.

최종 16개 방어 검사 후 실제 동일 후보의 BuildOnly·저장 소스 audit·소스 집중 13개·native 평가 기록과 현재 입력 해시를 연결한 두 번째 통합 대조도 PASS다. 직전 통합 대조 기록도 보존한다. 기본 게이트는 실제 native FAIL을 거절했고 명시적 opt-in만 같은 StatusBar FAIL을 원문 그대로 수용했다. 실제 포장 명령은 T11 NOT_RUN 기록을 기대한 종료 코드 1과 해당 정확한 실제 설치 흐름 증거 부재로 거절했다. 출력 폴더 생성·ISCC 시작·설치는 없었다. 이 실제 입력의 수용·미실행 거절 확인을 패키징 성공이나 T11 PASS로 쓰지 않는다.

## T11과 최종 포장의 순서

T11은 같은 후보와 동결 설치 입력의 비공개 엔진 payload로 실제 설치·대표 비교·결과·제거·복구를 구분한다. 별도 환경 경로는 미실행으로 보존하고 승인된 [현재 계정 경로](../../tools/ExcelSmartListCompare/docs/ADR-0023-R13-current-account-trial.md)의 부분 실행·제품 복구를 기록했다. 대표 비교·결과는 NOT_RUN_INCOMPLETE이며 최종 wrapper 실제 설치는 NOT_RUN이다.

설치 엔진은 같은 폴더의 XLAM·Setup.ps1·Uninstall.cmd·README.md를 Install.cmd로 설치할 수 있으므로 비공개 엔진 payload → T11 → 최종 포장 순서에는 논리적 순환이 없다. 최종 EXE를 처음 포장한 뒤 생기는 파일로 T11을 선행 증명한다고 해석하면 순환이 되므로 두 층을 구분한다. 최종 EXE의 실제 시험이 별도로 요구되면 비공개 EXE 제작·실제 시험·동일 해시 고정·공개 게이트 순서로 진행해야 한다. StatusBar 예외가 T11 미실행을 PASS로 바꾸거나 생략하는 근거는 아니다.

## 2026-10-04 현재 설치 정체와 비공개 백업 준비

manifest·제품/제거 관리 Setup·실제 XLAM 릴리스 literal을 읽어 현재 설치를 RC11로 확인했다. XLAM SHA는 `9b37c2f05318ef4500784978f62c0ea948bd2e703ef3e5590874c0ef89988176`이며 실행 소스 6개는 RC11 태그와 정규화 대조에서 같고 RC12 Main/Report와는 다르다. 앞선 제작·native에서 이 같은 파일을 R12라 부른 것은 설치 버전 표기 오류다. 원시 기록과 실제 보존 관찰은 덮어쓰지 않으며 이 정정과 함께 읽는다. 공개 R12·RC12 소스 기준·과거 R12 시험 생략 결정은 보존한다.

준비 당시 기록: 현재 계정 경로의 준비로 제품 5파일·제거 관리 5파일의 백업 해시 일치와 원본 상태 불변을 확인했다. 선정 registry 32개 영역과 ACL 14개 기록도 비공개로 보존했다. 읽을 수 있는 백업은 실제 복원 PASS가 아니다. [ADR-0023의 현재 계정 한 흐름](../../tools/ExcelSmartListCompare/docs/ADR-0023-R13-current-account-trial.md)은 후속 사용자 진행 지시에 따라 승인된 범위로 채택했다. 기존 제품의 OPEN/Manager와 제품 신뢰 등록 원복까지 필요하며 관리 파일·Windows 제거 등록은 유지한다. `unins000.exe`를 사용하지 않고 외부 변경·정책 차단은 중단 조건으로 둔다. 실제 설치·제거·복원·T11은 NOT_RUN이다. 후속 실제 결과는 현재 계정 결정과 검증 기록을 따른다.

준비 당시 기록: 복원 helper의 기본 읽기 대조는 원래 10파일·32개 registry 영역·14개 ACL과 실제 현재 상태가 같음을 확인해 PASS였다. 제품 파일·등록 쓰기는 없었고 실제 복원은 NOT_RUN이다. 원래 제품 바이트 또는 제거 후 부재만 허용하는 쓰기 경로를 별도로 검토하며, 외부 변경과 미복원 창 위치는 쓰기 전 중단 조건이다. ADR-0023의 포장 snapshot 추가 후 실제 증거 통합 대조 v3도 PASS였고 T11 NOT_RUN을 종료 코드 1로 거절했다. 출력 폴더·compiler·설치를 시작하지 않았다. 후속 실제 결과는 현재 계정 결정과 검증 기록을 따른다.

## 2026-10-04 현재 계정의 부분 T11과 제품 복구

승인된 동일 후보·동결 7입력으로 공식 Install.cmd를 한 번 실행해 RC11→RC13 Upgrade를 확인했다. 설치 엔진은 exit 0·InstallCommitted였다. 첫 실행 기록의 root 검증은 manifest 해시의 대소문자 대조 때문에 FAIL이었고 원문을 보존했다. 별도 읽기 대조가 실제 설치 바이트·manifest·등록·관리 파일·ACL 보존을 확인했으며 설치를 반복하지 않았다.

정상 Excel 시작에서 설치된 동일 RC13의 자동 로드를 확인하고 전용 합성 원본을 준비했다. 첫 화면 관찰이 Windows 잠금 화면이어서 UI 입력은 0회였고 목록 담기·대표 비교·결과 관찰은 실행하지 않았다. NOT_RUN_INCOMPLETE·observedFlowComplete=false·비어 있는 productActions와 원시 기록을 유지한다. 시험 소유 Excel은 cleanupErrors 없이 자연 종료했고 남은 Excel은 없었다. 후보 SHA와 제품·관리 파일은 그대로였다. 이미 완료한 새 안내·Replace 흐름이나 전체 GUI를 반복하지 않았다.

정리 후 선정 상태에서는 Options.Pos와 제품 밖 Trusted Documents.LastPurgeTime DWORD가 달라졌다. 두 값은 HKCU 32/64 대조에 같은 영역의 alias로 나타났다. LastPurgeTime의 원인은 미확정이며 제품 회귀나 Office 자동 정리로 단정하지 않는다. 최초 Pos 복구 guard는 이 외부 차이를 발견해 쓰기 없이 FAIL로 중단했다. 별도 독립 검토를 거친 좁은 복구가 관찰된 LastPurgeTime을 그대로 두고 승인된 시험 소유 Pos만 원래 typed 값으로 복원했다. Pos 기록의 nonProductRegistryWritesExecuted=false는 명칭이 넓어 실제 승인된 Pos 쓰기를 제외한 무소유 영역 쓰기 없음으로 별도 정정했다. 원시 기록은 수정하지 않았다.

동결 Uninstall.cmd의 공식 엔진 제거는 exit 0이었다. 후보 제품 파일·해당 OPEN·제품 신뢰 항목의 부재와 원래 관리 파일·Windows 앱 제거 등록 보존을 확인했다. unins000.exe는 실행하지 않았다. 이어 첫 제품 복구는 빈 제품 폴더를 만든 뒤 권한 exact 대조 실패로 중단했다. 이때 원래 제품 파일·등록 쓰기는 없었다. owner/group·DACL control은 같았지만 ACE 내용·순서가 달랐다. [SetNamedSecurityInfo의 상속 전파](https://learn.microsoft.com/en-us/windows/win32/secauthz/automatic-propagation-of-inheritable-aces)와 부합하는 추론이며 원래 기록의 실패를 지우지 않는다.

실패가 만든 빈 폴더의 identity·현재 SDDL·전체 선정 상태를 고정하고 SetFileSecurityW로 원래 owner/group/DACL을 전달했다. [이 API는 obsolete](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-setfilesecurityw)이며 일반 제품 설치 변경에 적용하지 않았다. 성공 반환 뒤 owner/group·전체 ACE 순서는 원래와 같았지만 자동 상속 AI 표시가 없어 exact SDDL 복원은 다시 FAIL이었다. [AI는 자동 상속 지원 표시](https://learn.microsoft.com/en-us/windows/win32/secauthz/security-descriptor-control)이므로 의미 없는 문자열 차이라고 단정하지 않는다. 두 번째 실패와 실제 차이를 보존했다. 파일·제품 등록은 이 시도에서도 쓰지 않았다.

이어 관찰된 단일 AI 표시 차이를 그대로 두고 원래 제품 5파일을 exclusive 생성으로 복구했다. 이 단계는 제품 폴더 ACL을 더 쓰지 않았다. actual SDDL을 숨기거나 원래 ACL 기록을 고치지 않았으며, owner/group·전체 ACE가 원래와 같고 AI 표시만 다르다는 guard를 고정했다. 파일의 바이트·기록 속성·시각 복원은 완료했지만, 제품 신뢰 키 생성 호출 뒤 Python 레지스트리 핸들 객체 구성 오류로 중단했다. 빈 제품 신뢰 키가 생성돼 있었고 Path·OPEN은 없었다. 원시 registryWritesExecuted=false가 이 빈 키 생성을 집계하지 못한 점을 실제 상태 대조와 별도 정정으로 보존했다.

최종 등록 복구는 이미 생성된 동일한 빈 키의 수정 시각·원래 ACL·전체 선정 상태를 다시 고정했다. 파일·ACL을 더 쓰거나 키를 생성·삭제하지 않고 winreg.OpenKey로 기존 키를 열어 원래 자료형의 소유 식별자·제품 ID·설명·하위 폴더 제한 4값을 쓰고, 제품 신뢰 Path와 원래 OPEN을 마지막에 복원했다. 각 단계의 실제 snapshot과 자료형을 대조했다. 최종 제품·관리 10파일의 바이트·기록 속성·시각과 원래 OPEN·제품 신뢰·다른 선정 영역을 확인했다. ACL 14개 중 13개는 원래 SDDL과 같고 제품 폴더 1개만 기록한 AI 차이를 유지했다. 다른 ACL 차이는 허용하지 않았다.

등록 복구 단계의 결과는 ORIGINAL_BYTES_REGISTRATION_RESTORED_WITH_OBSERVED_DIFFERENCES였다. exactAclRestored=false·exactOriginalProductRestored=false·exactSelectedStateRestored=false다. LastPurgeTime은 관찰값을 쓰지 않고 보존했다. 파일·등록 복구 완료를 정확한 제품·선정 보안 상태 전체의 원복이나 T11 PASS로 확대하지 않는다. AI 표시 차이를 평가 출시 조건으로 수용하는 결정을 내리지 않았다. 대표 비교·결과와 보존 미완료가 남아 T11은 PARTIAL / NOT_RUN_INCOMPLETE이며 StatusBar 예외가 이를 수용한 근거는 아니다. 최종 wrapper 실제 설치·포장·병합·태그·Release는 NOT_RUN, fullAcceptancePassed=false·stablePublishAllowed=false를 유지한다.

후속 복구 후보 진단은 비공개 출력 아래 새 빈 디렉터리 2개에만 한정했다. 같은 원래 descriptor에서 AI만 없는 시작 상태를 재현하고 `SetNamedSecurityInfo(info4)`와 독점 handle의 `SetSecurityInfo(info4)`를 비교했다. 두 API는 반환 0이었고 AI는 생겼지만 owner/group이 같은 상태에서 ACE가 5개에서 4개로 바뀌어 전체 원래 descriptor exact는 모두 false였다. 진단 완료는 복구 성공이 아니며 두 후보를 실제 제품에 적용하지 않았다. 설치 파일·등록·선정 상태와 현재 관찰 ACL 14개, 시험 부모 ACL의 불변을 대조했다. 제품·등록 쓰기·Excel 실행·설치·UI 입력은 없었다. 다른 시험 부모에서의 결과이므로 원래 실제 경로의 내부 원인 확정이나 복구 불가능 판정으로 확대하지 않는다. 동결 진단 소스 SHA는 `3525dc319c0b8d3e4d2c281eeac1568b27dd18108573b19b3f5d6d4505c15ef7`, 원시 기록 SHA는 `4fb338a639fb74acf88508af67144860be8ac5409807e4f8f552dfb12f291683`이다. 이 결과로 T11 또는 출시 조건을 완화하지 않는다.

## 2026-10-04 현재 실행 view의 ACL 복구와 남은 환경 대조

후속 빈 폴더 시험에서는 원래 전체 descriptor에 `SE_DACL_AUTO_INHERIT_REQ`(AR)만 메모리에서 추가하고 `SetFileSecurityW(info7)`를 적용했다. 원래 owner/group·ACE 5개·AI가 모두 정확히 일치했고 AR는 남지 않았다. 별도 원래 제품 5파일을 복사한 시험에서도 디렉터리만 한 번 적용한 뒤 파일의 바이트·기록 속성·생성/최종 쓰기 시각·identity·원시 ACL의 전후 동일성을 확인했다. 적용 후 자식 setter로 차이를 보정하지 않았다. 두 시험의 실제 설치 선정 상태·관찰 ACL 14개·시험 부모는 불변이었다. 빈 폴더 소스/원시 SHA는 `765fc8a4fbffaf20dcdd65ae0dddf9ccdd5182a0b5c9fb1ea68d198353b128d0` / `2ca5c7b7333747c6ac4c8463301966380eb8a41438765a209b6152a3d91f9318`, 5파일 시험은 `fb5f667cd98f7645c7b42a2c590e35d984349c8901b358b1ac6d2240e4d1a70f` / `c5e3d31a8d876d5547263f85172c1b45c7159a21ac192b53c57a9e23fe1151ce`다. 이 AR 요청은 [공식 control API](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-setsecuritydescriptorcontrol)를 사용한 원래 객체 복구 진단이며 제품 설치 엔진 변경이 아니다.

실제 대상의 첫 적용 시도는 `GetFinalPathNameByHandleW` 반환 경로와 논리 경로의 차이를 발견해 setter 전 `FAIL / NOT_RUN`으로 중단했다. 권한·파일·등록 쓰기는 없었고 실패 기록은 보존했다. 반환 경로는 Codex 패키지 LocalCache 아래였다. 별도 읽기 대조로 논리/물리 디렉터리와 원래 5파일의 device/inode·handle volume/file index·final path·바이트·기록 metadata·원시 ACL 전체가 같은 것을 확인했다. 원래 소유 directory identity와 두 부모 ACL도 고정했다. 매핑 원시 SHA는 `949501fbdf6f0e5ec182dff8523dbcdce5fcfc534132e52f348ae09c1f0318e7`이다.

이 동일 소유 객체에 한정한 새 복구 helper는 정확한 매핑·소유 identity·파일 10개·선정 32영역·권한 14개·부모 2개·Excel 없음·설치 mutex를 다시 대조한 뒤 논리 제품 경로의 descriptor를 한 번 적용했다. API BOOL 1/error 0, 전체 원래 directory SDDL과 자식 5파일 ACL, 원래 ACL 14개 모두 exact를 실제 확인했다. 파일·등록·부모·명시적 자식 setter는 실행하지 않았다. 자동 상속의 자식 영향은 setter 부재만으로 주장하지 않고 실제 자식 권한과 파일 전후 대조로 확인했다. 제품·관리 10파일의 바이트·기록 metadata, 제품 등록·두 부모·제품 5파일 identity는 보존됐다. 실제 복구 소스 SHA는 `e3bf8eee3407d110c16ccadd945e4817a65a07c949f14bd2f31f438ccdd565b7`, 원시 SHA는 `a41c42383356f027044fcd9d35a0166d4f6fedf6d94c05b31b2b3b1701d22bb4`다.

이 성공은 현재 실행 view에서 관찰한 소유 객체의 복구다. [MSIX 문서의 private-first/fallback 동작](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)과 부합하지만, 최초 RC11 백업·Upgrade 때의 물리 경로까지 같은 것을 증명하지 않는다. 일반 Windows/Excel이 보는 제품 파일·OPEN·신뢰 등록의 연결도 아직 확인하지 못했다. `GetCurrentPackageFullName`이 package identity 없음으로 반환한 같은 Python에서도 LocalCache final path가 관찰돼, 이 API 하나만으로 일반 실행 view를 확정하지 않았다. OPEN/신뢰 경로를 물리 경로로 바꾸거나 실제 AppData를 추가로 수정하지 않았다.

LastPurgeTime의 관찰값은 그대로이며 `exactSelectedStateRestored=false`, `initialBackupPhysicalViewConfirmed=false`, `nativeUnpackagedInstallationVerified=false`다. 원래 AI 차이가 남았다는 판단은 위 후속 실제 복구로 갱신하되, 과거 실패·원인 미확정·현재 환경 한계를 보존한다. 대표 비교·결과는 계속 미실행이고 T11은 PARTIAL / NOT_RUN_INCOMPLETE다. 새 Upgrade·Excel 실행·최종 EXE 설치·포장·병합·태그·Release는 이 복구에서 수행하지 않았다. StatusBar 예외·전체 인수 및 안정판 금지는 변경하지 않았다.

당시 제안한 최소 확인은 사람이 시작 메뉴에서 연 일반 PowerShell의 읽기 전용 대조였다. 그 읽기 진단은 아래에 완료 결과를 기록했고, 이후 T11 재개 계획은 ADR-0024의 최종 설치·RC13 유지 경로로 대체했다. 제품/관리의 알려진 10파일·handle 실제 경로·원래 권한 14개·선정 32영역을 새 비공개 기록에 읽고 전후 불변을 확인한다. 설치·Excel 시작·파일/등록/보안 변경은 없다. 일반 설치 view와 현재 관찰 view의 차이가 있으면 새 시험을 시작하지 않고 원래 백업·실제 값과 관계를 분석한다. 동일성이 확인된 뒤에만 최신 계속 지시 범위에서 같은 후보의 미완료 T11 재개 계획·새 시작 기준·원복 guard를 별도로 고정한다. 과거 한 흐름 기록을 수정·재사용하거나 사람이 재시도를 금지한 것으로 확대하지 않는다.

## 2026-10-04 일반 PowerShell의 읽기 진단: 실제 제품 부재

사용자가 시작 메뉴에서 연 일반 PowerShell로 읽기 전용 probe를 실행했다. 원시 SHA는 `f6b14d9dc7b2ad8eca60d4893bcd0bc1d3679370608d29aa7edc246c4704b039`, probe 소스 SHA는 `90ccaeb40d0725907d7749229460bc118d7da65fd8e5046692f4d566fbf166c0`다. 상태는 READ_ONLY_LAUNCH_VIEW_CAPTURED이며 제품·등록·ACL 쓰기, Excel·설치 실행, UI 입력은 없었다. 선정 상태·ACL·13개 객체의 전후 관찰을 대조했다. 현재 제품 디렉터리와 5파일은 absent다. 관리 폴더·Engine·5파일의 7객체는 실제 logical 경로와 handle final path가 정확히 같고 identity·기록 metadata가 전후 동일하다. 관리 5파일의 원래 바이트·기록 metadata도 exact다. 기존 ACL 8개는 원래와 같으며 제품 대상 6개는 부재다. nativeFileSystemViewConfirmed=false는 13개 중 6개 부재와 함께 원문으로 보존한다.

따라서 현재 Codex LocalCache의 14 ACL 복구와 일반 Windows의 원래 설치 복구는 다른 결과다. 일반 Windows에는 원래 제품 파일이 아직 없다. OPEN과 Location6의 값·자료형·소유 식별은 원본과 같으므로 등록 재생성·Path 변경은 필요하지 않다. 최초 백업·Upgrade 때의 물리 경로 기원은 여전히 미확정이고, 현재 부재를 선택한 안내 패치의 기능 회귀로 단정하지 않는다.

일반 진단의 선정 registry 32영역은 역사 원본과 Excel Options의 Maximized(DWORD)·PrinterName(REG_SZ) 데이터만 다르다. 32/64 alias로 반복돼 4 leaf 차이이며 값 존재·자료형·키 구조는 같다. 발생 원인·시점·시험 소유는 미확정이다. 일반 진단의 LastPurgeTime은 역사 원본과 같고, Codex 복구 view의 보존 관찰값과 다르다. 이 세 값은 각 view의 원시 기록을 유지하며 덮어쓰거나 원복하지 않는다. 다른 선정 등록과 Pos·OPEN·Location6는 역사 원본과 같다. 이 일반 진단 전체를 새 native 비교 기준으로 별도 고정한다.

현재 환경에서 공식 Volume GUID/current-SID HKU alias로 같은 대상만 읽은 대조도 일반 진단과 일치하지 않았다. 제품·등록·권한 쓰기는 없었다. alias 이름·package identity 없음만으로 일반 view를 얻었다고 주장하지 않고 그 방식의 실제 복구는 실행하지 않았다.

당시 제안한 다음 행동은 일반 PowerShell로 없는 제품 디렉터리와 원래 5파일만 복구하는 것이었다. 이 복구 제안은 미실행으로 남겼으며 이후 ADR-0024의 최종 RC13 설치·유지 경로로 대체했다. 일반 진단의 32영역과 관리 7객체·기존 8권한, 현재 사용자·원래 backup/source SHA와 제품 소유 식별을 쓰기 전에 다시 대조한다. private 단계에서 5파일의 원래 바이트·기록 속성·생성/최종 쓰기 시각·ACL을 확정하고, exclusive 생성한 실제 제품 폴더의 handle 경로·identity·volume을 확인한 뒤 replacement 없는 같은-volume move로 복원한다. 이미 활성인 OPEN·신뢰 등록을 고려해 XLAM은 마지막에 활성화한다. 새로 만든 소유 대상에만 필요할 때 원래 ACL을 복원하고, registry·관리 파일·부모 ACL·다른 추가 기능은 쓰지 않는다. 외부 변경·Excel·redirect·예상 밖 파일·불일치 시 중단하며 단일 실행 marker와 실패·partial journal을 보존한다.

원래 native 제품 복구는 아직 NOT_RUN이다. Codex 환경의 default 읽기 실행은 제품 부재 조건에서 setter/파일 쓰기 전에 FAIL / NOT_RUN으로 거절돼 잘못된 view의 실행을 수용하지 않았다. 일반 PowerShell의 실제 복구와 최종 대조 전에는 14권한·10파일이 native에서 복구됐다고 쓰지 않는다. 대표 비교·결과·새 Upgrade·최종 EXE·포장·병합·태그·Release도 미실행이며 T11 미완료·전체 인수 및 안정판 금지를 유지한다.

원시 백업·ACL·registry 값·사용자 경로·화면·진단은 artifacts에 비공개로 보존한다. 공개 기록에는 이 요약만 싣는다.

## 기존 증거의 경계

PR #10의 집중 13 PASS는 과거 소스 검사다. 부분 집계 82 PASS / 기준 main에도 있던 오래된 시트명 기대값 1 FAIL / 부분 스냅샷 누락 2 ERROR는 그대로 보존한다. `제외·발생위치` 기대값과 R12 `값과 위치` 출력의 차이는 새 안내 회귀가 아니며, 누락됐던 `modSLCMain.bas`·`Setup.ps1`은 현재 저장소에 있다. 이번 실행이 두 ERROR를 재현하거나 해결했다고 쓰지 않는다.

R11의 취소 완료 안내 FAIL과 상태표시줄 자료형 복원 FAIL은 별도 실제 기록으로 유지한다. 첫 목록·원본 복구 성공을 사용자에게 보이는 취소 완료 안내 성공으로 바꾸지 않는다. 이번 문구·버전 변경은 그 두 문제를 해결하지 않는다.

R12 제작 당시 전체 시험 NOT_RUN과 2026-09-27 대표 비교·공존·정상 종료 PASS를 구분한다. 후속 대표 결과는 같은 R12 파일의 제한된 합성 경로이며 R12 자체 재설치·제거와 전체 회귀가 아니다. R12 전용 시험 생략 예외를 RC13에 적용하지 않는다.

## 출하 판단과 미확인 범위

최종 EXE 실제 설치·정상 Excel 시작·대표 비교·원본 보존·소유 정리·정상 종료와 native 동일 후보·선정 설정 보존을 확인했다. 기존 T11은 PARTIAL / NOT_RUN_INCOMPLETE, StatusBar 실제 FAIL과 과거 82 PASS / 1 FAIL / 2 ERROR도 보존한다. RC13을 유지하며 제거·RC11 복구·전체 시험을 반복하지 않는다. 같은 EXE의 자산 완성과 PR 검토 후 서명 없는 평가 prerelease로 게시한다. 전체 인수·안정판·회사 승인은 아니다. 실제 게시·다운로드 결과는 후속 릴리스 기록을 따르며, 게시 전 공개 다운로드는 R12를 유지한다.

전체 GUI·공존·성능·취소·설치 suite를 무조건 재실행하지 않는다. 새 후보에서 실제 확인한 범위만 기록하며 x86 Office·새 PC·재부팅·회사 정책 환경, 서명·상용 인수는 별도 미확인 상태다. `fullAcceptancePassed=false`와 안정판 금지를 유지한다.

원시 로그·화면·사용자 경로·레지스트리와 업무 자료는 artifacts의 로컬 증거로 보존하고 공개 요약에는 복사하지 않는다. 기존 공개 R12는 새 RC13 자산이 검증·게시되기 전까지 공개 안내의 다운로드 대상으로 유지한다.

[R13 명세](../tools/excel-list-compare/r13-specification.md) · [RC13 최초 결정](../../tools/ExcelSmartListCompare/docs/ADR-0021-R13-focused-wording-evaluation.md) · [StatusBar 평가 수용 결정](../../tools/ExcelSmartListCompare/docs/ADR-0022-R13-known-statusbar-evaluation.md) · [현재 계정 시험·원복 제안](../../tools/ExcelSmartListCompare/docs/ADR-0023-R13-current-account-trial.md) · [후보 검증 기록](../../tools/ExcelSmartListCompare/docs/RC13_RELEASE_REPORT.md) · [T11 조건부 대기](WORKSPACE_Tool_Backlog_20260926.md) · [R12 대표 공존](excel-coexistence-20260927.md)
