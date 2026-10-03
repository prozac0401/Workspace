# Excel 명단 비교 R13 · 준비·검증 기록

버전: 0.2.0-rc.13 · 날짜: 2026-10-03

상태: 집중 소스·구문·합성 제작 방어 확인 완료 · 새 XLAM·설치 파일·실제 시험·출하 보류

프로필: `focused-wording-evaluation` · `fullAcceptancePassed=false`

## 변경 행동

담은 첫 목록 확인의 요약에서 ‘수정한 범위를 선택해 [첫 번째 목록 바꾸기]를 누르세요’라고 기존 교체 명령을 명시한다. 자동으로 갱신되지 않는다는 안내와 2열·14항목을 유지한다. 비교·개수 집계·설정·스냅샷·취소·복구·설치 엔진은 바꾸지 않는다.

새 후보의 VBA 릴리스 식별자와 설치 버전은 `0.2.0-rc.13`이다. 기존 R12 자산은 변경하지 않는다. RC13의 제작·시험·파일 해시가 확정되기 전에는 R12 파일에 이 변경이 반영됐다고 안내하지 않는다.

## 현재 결과와 남은 확인

소스 준비의 기준 커밋은 `e41999684c6a21070e5d6fc96ebed593b0529b1d`다. 새 후보의 동결 커밋·XLAM·EXE·ZIP·시험 환경과 해시는 실제 제작·검증 후 [실행 기록](../../../docs/delivery/excel-smart-list-compare-rc13-20261003.md)에 추가한다.

| 단계 | 이번 준비 시점의 판정 |
|---|---|
| 선택 요약 개선·RC13 버전·허용 버전 목록 | 소스 준비 완료 |
| 현재 집중 소스 검사 | 13 PASS / 0 FAIL / 0 ERROR / 0 SKIP · 명시한 목록 한정, 전체 suite 아님 |
| ASCII/UTF-8 일치 | 5쌍 PASS · 실제 VBA 컴파일·Excel 실행 아님 |
| RC12 대비 제품 변경 범위 | PASS · 태그 커밋 `c1e365d2155a594d4b864609da7656796bd1a345`와 실제 scope_guard 대조, 선택 안내 한 줄·버전만 변경, 나머지 엔진·설치 입력 불변 |
| PowerShell 구문 | Setup·격리 제작 실행기 두 AST 파싱 PASS |
| RC13 packager 구문·합성 방어 | Python AST PASS, 합성 방어 4 PASS · 실제 패키지 제작 아님 |
| 새 XLAM 제작·VBA 7개 모듈/RibbonX·버전·파일 불변성 | NOT_RUN |
| 동일 후보 내장 기능·정상 종료·임시 설정 원복·기존 설치 보존 | NOT_RUN |
| 새 요약 문구·기존 Replace 한 실제 흐름 | NOT_RUN |
| T11 새 후보 설치·대표 비교·결과·제거 | NOT_RUN · 기존 R12 설치·등록 보존 필요, 후보 설치·제거 시험 환경 없음 |
| EXE·ZIP·버전·구성·해시 | NOT_RUN |
| 문서 strict·생성 링크·공개 범위 | PASS · strict 빌드, 공개 19개·이전 주소 2개·404, 새 상대 파일 링크 31개 |
| Draft PR | 소스 준비 검토용 초안 예정 |
| 패키징·병합·태그·GitHub Release·다운로드 검증 | NOT_RUN · 보류 |

현재 집중 검사에서 `UsabilitySourceContracts.test_difference_is_one_sheet_and_preview_has_locations`는 오래된 시트명 기대값의 기존 FAIL 때문에 검사명으로 명시해 선정 목록에 포함하지 않았다. 실행한 13개는 모두 통과했으며 제외한 검사를 PASS로 바꾸지 않았다. 전체 suite나 전체 사용성 검사 통과가 아니다.

합성 제작 방어 4건은 다른 SHA, NOT_RUN 증거, 중복 JSON 필드, 선택하지 않은 엔진 변경을 거절하는 검사다. 이 결과는 실제 BuildOnly·저장한 XLAM의 VBA/RibbonX 소스 audit·현재 집중 검사·새 안내/Replace native·T11 설치/비교/결과/제거 증거를 요구하는 RC13 출하 게이트를 대신하지 않는다.

별도 임시 VBA 프로젝트 접근 승인의 답변이 없어 설정은 변경하지 않았다. 읽기 전용으로 HKCU/HKLM의 32/64비트 일반·정책 경로 8곳에서 AccessVBOM 값 부재를 확인했고 설정 변경은 0회다. 기존 R12 설치와 등록이 있어 보존이 필요하다. 새 후보 제작·Excel·native·설치·패키징·병합·태그·Release는 실행하지 않았으며 보류한다. 문서 strict·생성 링크 확인은 별도 실행 대기다.

RC13 자체의 [ADR-0021](ADR-0021-R13-focused-wording-evaluation.md)을 적용한다. R12의 시험 생략 예외는 적용하지 않는다. 새 native 흐름·설치 확인이 남으면 미완료 상태와 이유를 기록하고 출하 판단을 다시 한다. 제작 성공이나 소스 검사 성공을 실제 Excel·설치 시험 PASS로 바꾸지 않는다.

## 보존하는 과거 증거

- [기존 PR #10](https://github.com/prozac0401/Workspace/pull/10), head `82a690f624e83470129c8832688ec74356062745`: 집중 Python/소스 검사 13 PASS, ASCII/UTF-8 일치. 실제 VBA·Excel 시험이 아니다.
- 같은 기록의 부분 집계 82 PASS / 기존 기대값 1 FAIL / 스냅샷 누락 2 ERROR: FAIL은 기준 main에도 있던 `제외·발생위치` 기대값과 R12의 `값과 위치` 출력 불일치다. 2 ERROR는 부분 스냅샷에 `modSLCMain.bas`·`Setup.ps1`이 없던 결과이며 현재 저장소 파일 부재가 아니다. 전체 suite PASS나 이번 문구 회귀로 표시하지 않는다.
- [R11 실제 상세 기록](RC11_POST_RELEASE_VALIDATION_20260920.md): 데이터 보존·복구와 별개로 취소 완료 안내 FAIL, 상태표시줄 `Boolean False`가 `String "FALSE"`로 바뀌는 복원 FAIL. 전체 인수 미완료와 `fullAcceptancePassed=false`를 유지한다.
- [R12 제작·배포 기록](RC12_RELEASE_REPORT.md): 당시 사용자 요청에 따른 전체 기능·설치 시험 NOT_RUN. [ADR-0020](ADR-0020-R12-wording-release.md)의 예외는 R12 한정이다.
- [2026-09-27 대표 공존 기록](../../../docs/delivery/excel-coexistence-20260927.md): 기존 R12 대표 비교·원본 보존·정상 종료와 다른 세 도구 순차 제거 후 자동 로드·메뉴·파일·설정 보존 PASS. R12 자체 재설치·제거·설정 변경이나 전체 기능·취소·설치 시험은 하지 않았다.

## 출하와 지원 범위

지금은 소스 준비 단계이며 새 후보 제작·출하를 보류한다. Draft PR은 이 소스와 제작 방어 변경을 검토하는 초안으로 준비한다. 별도 승인·기존 설치 보존 가능한 시험 환경과 실제 후보 증거를 확보한 뒤 출하 판단을 다시 한다. 무서명·회사 PC/조직 정책 환경 미확인과 기존 기능 한계는 유지한다. 안정판·상용 승인·전체 인수 완료로 표시하지 않는다. 원시 로그·사용자 경로·레지스트리와 업무 자료는 공개 패키지에 넣지 않는다.

[R13 명세](../../../docs/tools/excel-list-compare/r13-specification.md) · [후보 사용 안내](RC13_USER_GUIDE.md) · [현재 공개 R12](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.0-rc.12)
