# Excel 명단 비교 RC13 · 실행·출하 준비

날짜: 2026-10-03 KST · 책임: 도구 개발·검증 담당

상태: 새 안내·Replace 실제 흐름 완료, StatusBar FAIL의 좁은 평가 수용·T11 미실행 거절 확인, T11·출하 대기

제품 버전: `0.2.0-rc.13` · 프로필: `focused-wording-evaluation` · `fullAcceptancePassed=false`

## 승인 범위와 변경

사용자가 선택한 작은 사용성 개선의 필요한 검사·버전·패키지·PR·병합·릴리스 준비 범위에서 명단 비교만 순차 진행한다. 제품 변경은 담은 첫 목록 요약의 기존 Replace 명령 안내와 릴리스·설치 버전 문자열이다. 비교 엔진·설정·스냅샷·취소·복구·설치 엔진의 기능은 바꾸지 않는다.

기준 소스는 `e41999684c6a21070e5d6fc96ebed593b0529b1d`, 원래 선택된 패치는 PR #10의 `82a690f624e83470129c8832688ec74356062745`다. 실제 제작 입력의 동결 커밋은 [Draft PR #13](https://github.com/prozac0401/Workspace/pull/13)의 `9ebaf3d661e1602e7bc6e60be4b9a0c0fe079160`이다. 기존 R12 공개 자산과 과거 검증 문서는 보존한다.

사용자는 후속 답변으로 SmartList부터 진행하고 임시 VBA 프로젝트 접근을 허용하는 승인을 했다. 기존 R12 설치·등록을 제거하거나 업그레이드하지 않는 격리 BuildOnly를 실행한 뒤 선택된 새 안내·Replace native 흐름을 확인했다. 설치·배포는 아직 실행하지 않았다.

이후 새 안내·Replace 실제 흐름을 실행했다. 최신 StatusBar 경중·필수 시험·배포조건 재분석과 조정 요청에 근거해 개발 담당은 [ADR-0022의 좁은 평가 조건](../../tools/ExcelSmartListCompare/docs/ADR-0022-R13-known-statusbar-evaluation.md)을 채택했다. 사용자가 이 완성 문안이나 최종 파일 게시를 승인했다는 뜻은 아니며 회사·조직의 승인도 아니다.

## 실제 결과

검증 담당이 현재 RC13 소스에서 실행한 집중 검사·격리 제작·저장 소스 audit·실제 새 안내/Replace 흐름을 아래에 기록한다. 환경은 Windows 11 10.0.22631, Excel 16.0 Build 20430 x64, Windows PowerShell 5.1.22621.6133이다. 소스 audit는 기존 문서용 Python 환경으로 실행했다. 확인 범위는 합성 한 흐름이며 전체 매크로·GUI suite와 후보 설치 확인은 별도 NOT_RUN이다.

실제 XLAM의 릴리스 식별자는 `0.2.0-rc.13`, SHA-256은 `484419befa0cd763635b1f9592cff43bd13e657e19d5a693d76a78fa071ed14e`다. 제작 최종 해시와 소스 audit 전후 해시가 일치한다. EXE·ZIP과 출하 자산은 아직 제작하지 않았다.

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
| 첫 native | 부분 FAIL·미완료 | 실제 StatusBar FAIL과 별도로 R12 UI 분리의 Workbooks 열거 준비 결함 확인. 메뉴 간섭 원인 미확정. Pos 복구는 별도 PASS |
| 두 번째 새 요약/Replace 실제 흐름 | flowComplete=true·총 native FAIL | 실제 증거 평가 11개 PASS / excelGlobalsPreserved 1 FAIL. typed globals 8개 중 StatusBar만 Boolean False → String FALSE, 기능·이전 결과·보존·정리 완료 |
| 알려진 StatusBar 평가 수용 | 실제 입력 통합 대조 PASS | 기본 게이트는 실제 native FAIL 거절, 정확한 후보·결정 SHA와 명시적 opt-in만 수용. 실제 FAIL 원문 유지,다른 필수 조건 유지 |
| 전체 내장 기능·GUI suite | NOT_RUN | 실제 확인은 선택된 합성 한 흐름. BuildOnly의 비어 있는 tests 목록도 기능 시험 PASS가 아님 |
| T11 새 후보 설치·대표 비교·결과·제거 | NOT_RUN·미실행 거절 확인 | 기존 R12 설치·등록 보존과 별도 일반 사용자 Windows·Excel 환경 대기. 실제 포장 명령이 T11 NOT_RUN 기록을 기대한 종료 코드 1로 거절 |
| 최종 EXE 실제 설치·제거 | NOT_RUN | T11 비공개 엔진 payload 설치와 구분, newWrapperActualInstallation=NOT_RUN |
| EXE·ZIP·버전·구성·SHA-256·공개 기록 | NOT_RUN | RC13 전용 profile·false 인수 상태·소스/후보/증거 해시, 새 설치·소스·검증 자산. 로컬 로그·사용자 정보 제외 |
| strict 문서 빌드·생성 링크·공개 범위 | 이번 갱신 후 PASS | MkDocs strict 성공. 공개 19개·이전 주소 2개·404·검색·사이트맵·로컬 링크 확인. 갱신한 7문서의 상대 파일 대상 46개 PASS이며 외부 URL·문단 앵커 시험은 아님. 소스 준비 시점의 새 링크 31개와 별도로 기록. RC13 내부 문서는 공개 사이트에서 제외 |
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

첫 native는 실제 StatusBar FAIL을 포함한 부분 FAIL과 미완료로 종료했다. 별도로 기존 R12 UI 분리를 Workbooks 열거로 처리한 준비 결함을 확인했으며 메뉴 상태 간섭의 인과는 확정하지 않는다. 이 시도를 성공한 전체 흐름으로 바꾸지 않는다. Pos 원복·기준 대조 PASS는 실패와 구분해 보존한다.

두 번째 native는 기존 R12를 정확한 이름의 Item으로 확인해 해당 세션 UI만 분리한 뒤 같은 후보로 2026-10-03 13:35:21~13:55:43 UTC에 실제 UI 한 흐름을 완료했다. 합성 원본 Alpha/Beta/Beta의 한 Beta를 Gamma로 의도적으로 수정했으며 저장하지 않았다. 첫 확인 파일과 교체 전 두 번째 확인 파일은 Beta를 유지했다. 실제 기존 Replace 명령을 UI에서 실행한 뒤 세 번째 확인 파일에 Gamma·서로 다른 값 3개·추가 개수 0개가 반영됐다. 요약 A14/B14 전체 안내는 두 줄·14항목으로 보였다. 이전 확인 파일·원본 서식·원본 디스크 내용은 보존됐으며 합성 메모리 수정은 의도한 범위였다.

전후 typed globals 8개 중 StatusBar만 Boolean False → String FALSE였다. raw native 총 FAIL, flowComplete=true와 실제 증거 평가의 11개 PASS / excelGlobalsPreserved 1 FAIL을 각각 보존한다. cleanupErrors=[]이며 소유 Excel이 자연 종료했고 남은 Excel은 없다. 후보 SHA는 같고 기존 R12 설치·등록을 업그레이드·제거하지 않았다. 매크로 포함은 사람이 직접 선택했으며 보안 UI 자동 조작·영구 보안 설정 변경·회사 정책 우회는 하지 않았다.

[Microsoft의 StatusBar 설명](https://learn.microsoft.com/en-us/office/vba/api/excel.application.statusbar)에 따르면 False는 Excel의 제어권이며 기본 상태 표시를 복원하는 값이다. String FALSE는 이 복원이 되지 않는 표시 결함으로 프로세스 안에서 평소 상태 표시가 가려질 수 있다. 이번 합성 데이터 기능이 복구 불가능하거나 중단됐다는 결과는 아니다. 정확한 원인은 미확정이다. 소스에는 이미 literal False 복원이 있고 과거 빈 COM 대조에서도 문자열 FALSE가 관찰됐으며 타 추가 기능의 영향을 배제하지 못했다. 해결 가능성은 있지만 검증되지 않은 한 줄 수정으로 해결했다고 주장하지 않는다.

최신 사용자 요청을 근거로 개발 담당은 ADR-0022에서 이 정확한 실패만 opt-in으로 평가 prerelease에 수용한다. 실제 FAIL·첫 시도 실패·기존 한계를 유지하며 다른 전역·원본·이전 결과·보안·기존 설치·설정·소유 정리·자연 종료는 계속 필수다. 수용 근거는 USER_REQUESTED_ANALYSIS_AND_RELEASE_CONDITION_ADJUSTMENT이며 결정 raw SHA와 정확한 후보를 묶는다. 최종 파일 게시·회사 승인을 받았다는 뜻은 아니다. `fullAcceptancePassed=false`·`stablePublishAllowed=false`를 유지한다.

최종 16개 방어 검사 후 실제 동일 후보의 BuildOnly·저장 소스 audit·소스 집중 13개·native 평가 기록과 현재 입력 해시를 연결한 두 번째 통합 대조도 PASS다. 직전 통합 대조 기록도 보존한다. 기본 게이트는 실제 native FAIL을 거절했고 명시적 opt-in만 같은 StatusBar FAIL을 원문 그대로 수용했다. 실제 포장 명령은 T11 NOT_RUN 기록을 기대한 종료 코드 1과 해당 정확한 실제 설치 흐름 증거 부재로 거절했다. 출력 폴더 생성·ISCC 시작·설치는 없었다. 이 실제 입력의 수용·미실행 거절 확인을 패키징 성공이나 T11 PASS로 쓰지 않는다.

## T11과 최종 포장의 순서

T11은 같은 후보와 동결 설치 입력의 비공개 엔진 payload를 별도 일반 사용자 Windows·Excel 환경에 설치해 대표 비교·결과·제거·초기 상태 복원을 확인하는 최소 흐름이다. 현재 계정의 기존 R12를 제거·업그레이드하지 않는다. 환경 확보와 T11은 NOT_RUN이다. 이 흐름은 최종 EXE 실제 설치 시험이 아니며 newWrapperActualInstallation=NOT_RUN을 유지한다.

설치 엔진은 같은 폴더의 XLAM·Setup.ps1·Uninstall.cmd·README.md를 Install.cmd로 설치할 수 있으므로 비공개 엔진 payload → T11 → 최종 포장 순서에는 논리적 순환이 없다. 최종 EXE를 처음 포장한 뒤 생기는 파일로 T11을 선행 증명한다고 해석하면 순환이 되므로 두 층을 구분한다. 최종 EXE의 실제 시험이 별도로 요구되면 비공개 EXE 제작·실제 시험·동일 해시 고정·공개 게이트 순서로 진행해야 한다. StatusBar 예외가 T11 미실행을 PASS로 바꾸거나 생략하는 근거는 아니다.

## 기존 증거의 경계

PR #10의 집중 13 PASS는 과거 소스 검사다. 부분 집계 82 PASS / 기준 main에도 있던 오래된 시트명 기대값 1 FAIL / 부분 스냅샷 누락 2 ERROR는 그대로 보존한다. `제외·발생위치` 기대값과 R12 `값과 위치` 출력의 차이는 새 안내 회귀가 아니며, 누락됐던 `modSLCMain.bas`·`Setup.ps1`은 현재 저장소에 있다. 이번 실행이 두 ERROR를 재현하거나 해결했다고 쓰지 않는다.

R11의 취소 완료 안내 FAIL과 상태표시줄 자료형 복원 FAIL은 별도 실제 기록으로 유지한다. 첫 목록·원본 복구 성공을 사용자에게 보이는 취소 완료 안내 성공으로 바꾸지 않는다. 이번 문구·버전 변경은 그 두 문제를 해결하지 않는다.

R12 제작 당시 전체 시험 NOT_RUN과 2026-09-27 대표 비교·공존·정상 종료 PASS를 구분한다. 후속 대표 결과는 같은 R12 파일의 제한된 합성 경로이며 R12 자체 재설치·제거와 전체 회귀가 아니다. R12 전용 시험 생략 예외를 RC13에 적용하지 않는다.

## 출하 판단과 미확인 범위

임시 VBA 프로젝트 접근 승인 이행·원복, RC13 제작·저장 소스 audit·선정 보존 대조·새 안내/Replace 실제 흐름과 소유 정상 종료를 마쳤다. native 총 FAIL은 StatusBar만 남았고 실제 입력의 좁은 평가 수용·T11 미실행 거절을 확인했다. 기존 R12 설치·등록은 제거하거나 갱신하지 않았다. T11·최종 EXE 실제 설치와 EXE·ZIP·패키징·병합·태그·Release는 NOT_RUN 또는 대기다. #13은 Draft로 유지하며 나머지 필수 증거를 확보한 뒤 평가 출하 판단을 다시 한다. 회사 정책·신뢰 저장소를 우회하지 않는다.

전체 GUI·공존·성능·취소·설치 suite를 무조건 재실행하지 않는다. 새 후보에서 실제 확인한 범위만 기록하며 x86 Office·새 PC·재부팅·회사 정책 환경, 서명·상용 인수는 별도 미확인 상태다. `fullAcceptancePassed=false`와 안정판 금지를 유지한다.

원시 로그·화면·사용자 경로·레지스트리와 업무 자료는 artifacts의 로컬 증거로 보존하고 공개 요약에는 복사하지 않는다. 기존 공개 R12는 새 RC13 자산이 검증·게시되기 전까지 공개 안내의 다운로드 대상으로 유지한다.

[R13 명세](../tools/excel-list-compare/r13-specification.md) · [RC13 최초 결정](../../tools/ExcelSmartListCompare/docs/ADR-0021-R13-focused-wording-evaluation.md) · [StatusBar 평가 수용 결정](../../tools/ExcelSmartListCompare/docs/ADR-0022-R13-known-statusbar-evaluation.md) · [후보 검증 기록](../../tools/ExcelSmartListCompare/docs/RC13_RELEASE_REPORT.md) · [T11 조건부 대기](WORKSPACE_Tool_Backlog_20260926.md) · [R12 대표 공존](excel-coexistence-20260927.md)
