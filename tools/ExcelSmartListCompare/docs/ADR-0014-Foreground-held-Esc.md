# ADR-0014 · 실행 중인 Excel에서 눌린 Esc 확인

상태: 채택·candidate-07 반영, 100ms 바꾸기 상태 보존은 대조 실험에 근거한 부분 검증. 전체 취소 인수 NOT_MET, [제한 평가판 결정](ADR-0015-Limited-evaluation-release.md) 적용

날짜: 2026-09-17

결정 담당: 사용자 오류 재실험·개선 요청에 따른 도구 개발 담당

관련 요구사항·정책: [원래 검증 지시](../../../CODEX_EXCEL_E2E_TEST_PROMPT.md), [인수 기준](ACCEPTANCE_TESTS.md) P07~P10·C03~C05, [추가 도구 개발 기준](../../../docs/policies/tools.md), [허용 후 재실험 기록](RC9_APPROVED_RETEST_20260917.md)

관계: [ADR-0010](ADR-0010-Cancellation-and-removal.md)·[ADR-0011](ADR-0011-Bounded-processing-and-cancellation.md)의 오류 전달과 확정 전 복구를 유지한다. 키 상태 확인을 사용하지 않던 결정은 이번 작업 중·현재 Excel 창에 한정해 확장한다. 전역 단축키 등록·후킹·상시 감시는 계속 사용하지 않는다.

## 맥락

수정 전 RC9 candidate-05에서 100,000개 고유 값·셀당 48자 범위를 처리하며 Esc를 약 100ms 유지했다. 비교에서는 취소 안내와 기존 42개 목록 보존을 확인했지만, 첫 목록 교체에서는 두 번 모두 100,000개 교체가 완료됐다. 두 번째 교체 시험은 시험 호스트와 Excel이 정상 종료했고 원본·이전 결과·설정도 보존했다. 첫 시험의 반환 후 PowerShell 호스트 충돌과 제품의 취소 미감지는 구분한다.

키 입력 API가 성공했다고 Excel이 그 입력을 받았다고 판정하지 않는다. 현재 소스에서 비교와 교체는 값 읽기 경로를 공유하며, 실제 입력 실패의 근본 원인은 확정하지 못했다. Excel의 `EnableCancelKey=xlErrorHandler`는 감지한 사용자 중단을 오류 18로 전달한다. 기존 구현은 이 전달에 의존했다. [Microsoft EnableCancelKey 설명](https://learn.microsoft.com/en-us/office/vba/api/excel.application.enablecancelkey)

## 결정

- 기존 오류 18 처리와 `mCancelled`·`ERR_CANCEL`·확정 전 rollback을 유지한다. 처리 중인 경우에만 현재 눌린 Esc를 추가로 확인한다.
- foreground 창의 프로세스 ID가 VBA를 실행하는 Excel 프로세스 ID와 같을 때만 Esc 상태를 읽는다. 상태를 읽은 뒤 foreground 창 핸들이 그대로인지 다시 확인한다. 다른 프로그램의 창 내용이나 다른 키는 읽지 않는다. 현재 프로세스 식별은 [GetCurrentProcessId](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getcurrentprocessid), 창 소유 확인은 [GetWindowThreadProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowthreadprocessid)를 사용한다.
- [GetAsyncKeyState](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getasynckeystate)의 상위 비트만 판단한다. 반환형 `SHORT`를 VBA `Integer`로 받아 음수이면 현재 눌림으로 판단한다. 이전 눌림을 뜻하는 하위 비트는 다른 프로그램의 조회에 영향을 받으므로 사용하지 않는다.
- 기존 체크포인트의 `DoEvents` 전후에서 확인한다. 값 읽기·비교키 합집합·개수 비교·결과 행 준비에서는 64개마다 이벤트 전달 없는 가벼운 확인을 추가한다. 상태표시·`DoEvents`의 기존 간격과 셀·문자·시간 상한은 바꾸지 않는다.
- 키 상태를 감지하면 취소 신호를 남기고 기존 오류 처리로 넘어간다. 전역 단축키, 키보드 후크, 입력 생성, 타이머, 별도 실행 프로세스나 보안 정책 변경은 추가하지 않는다.
- API 호출에서 발생한 VBA 오류는 무시하지 않는다. 오류 18을 포함해 기존 작업 오류 처리로 전달하고, 확정 전이면 이전 목록을 복구한다. 운영체제 API가 실패를 나타내는 0을 반환하면 현재 입력을 감지하지 못한 것으로 처리하며 기존 native 취소 경로는 남는다.

## 검토한 대안

`EnableCancelKey`만 유지하면 변경 범위는 작지만 실제 교체 시험의 미감지를 보완하지 못한다. 상위 비트 조회를 기존 체크포인트에만 넣으면 두 체크포인트 사이에 누르고 놓은 입력을 놓칠 수 있어 64개마다 확인한다. 이 간격도 실시간 응답 시간의 보장은 아니다.

하위 눌림 기록 비트, 전역 키 등록과 후킹은 사용하지 않는다. 별도 모델리스 취소 창은 명시적인 취소 수단이 될 수 있지만 새 UI·창 수명·이벤트 검증이 필요하다. 기존 ‘첫 번째 목록 비우기’ 버튼은 실행이 지연되면 작업 종료 후 목록을 비울 수 있으므로 취소 버튼으로 안내하지 않는다.

## 영향과 이행

Windows 데스크톱 Excel용이다. VBA7에서는 `PtrSafe`와 `LongPtr`로 창 핸들을 전달하고, 이전 VBA 분기는 32비트 `Long`을 사용한다. 프로세스·스레드 ID는 `Long`, 키 상태는 `Integer`다. 올바른 선언 검토와 실제 32비트 Office 검증은 구분하며, 32비트 Office 실행은 미검증이다. [Microsoft 32·64비트 VBA 설명](https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/64-bit-visual-basic-for-applications-overview)

조직이 Office 매크로의 Win32 API 호출을 차단하면 새 확인 경로도 제한될 수 있다. 해당 정책을 해제하거나 예외를 자동 등록하지 않는다. 정책 차단 환경의 호환성을 실제 검증 없이 약속하지 않는다. [Microsoft ASR Win32 API 차단 규칙](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference#block-win32-api-calls-from-office-macros)

실행 중인 Excel 창에서 Esc를 누르고 유지한 상태가 확인 지점과 겹치면 취소를 요청한다. 짧게 누르고 놓는 입력의 감지, 일정 밀리초 이내 응답, COM 호출·정규화 한 번이 끝나기 전의 중단은 보장하지 않는다. foreground 조회 사이의 창 전환 경쟁도 완전히 없앨 수 없다. ‘작업을 취소했습니다’ 안내와 목록 상태를 확인하기 전에는 취소 완료로 판단하지 않는다. 경고창의 ‘아니요’로 작업 시작을 거절하는 동작은 유지한다.

변경은 candidate-07 XLAM SHA-256 `61574c0f0acc68fb7b49507fa95c7201768515f4c5edfd563e3caf3915c19efc`에 반영됐다. 저장 전·직렬화 소스 대조와 실제 실행을 구분해 기록했다. candidate-05는 변경 전 파일로 남기며 동일한 RC9 버전 표기만으로 변경 효과를 재사용하지 않는다.

## 실패와 복구

확정 전 취소·오류는 이전 첫 목록을 유지하고, 작성 중이던 새 결과만 닫는다. 원본과 이전 결과를 바꾸지 않는다. 최종 체크포인트 뒤 짧은 확정 구간에서는 기존처럼 취소를 비활성화하며, 이미 완료된 작업을 취소했다고 안내하지 않는다. 눌림이 확인되지 않은 경우 작업이 계속되거나 완료될 수 있다.

## 검증

`SLC_CancellationDecisionTests`는 외부 API나 Excel 상태 변경 없이 실제 판정 함수를 12개 독립 기대값으로 검사한다. 키가 올라온 상태, 하위 비트만 설정된 상태, 상위 비트가 설정된 상태, 다른 foreground 프로세스, 0인 프로세스 ID, 창 전환과 idle 상태를 포함한다. `SLC_TestAll`이 이 검사도 실행하고 통과 개수를 반환한다. 이 검사는 실제 키 전달·API 성공·취소 rollback의 증거가 아니다.

candidate-07에서 현재 확인한 범위는 다음과 같다.

| 검사 | 실제 판정 | 범위와 제한 |
|---|---|---|
| 내장 판정 함수 | 12개 PASS | 실제 Excel의 `SLC_TestAll`에서 정규화·19개 통합 검사와 함께 실행. 실제 입력 증거와 구분 |
| 첫 목록 바꾸기·100ms 요청 2회 | 해당 조건의 상태 보존은 대조 실험에 근거한 추론 PASS | 실제 down→keyup API 간격 133.251ms·125.706ms. 기존 42개 목록·후속 일치·원본 해시/Saved·이전 결과 표식/Saved·설정·정상 종료 확인 |
| 키 입력 없는 동일 작업 대조 | 100,000개 교체 완료 | 같은 파일·실행기·캐시 값과 수식 구성을 대조. Esc 두 조건에서만 더 일찍 반환하며 기존 목록 보존 |
| 취소 안내·내부 오류 코드·Excel의 직접 키 수신 | 미관찰 | 동작 추론과 구분하고 PASS로 표시하지 않음. 원시 helper의 미분류 결과 유지 |
| 키 입력 없는 선택·용량 회귀 | 선택 14조건 PASS, 용량 16조건 중 14완료·2시간 초과 | 고유값 각 20,000개 완료, 각 50,000·100,000개 시간 초과. 동일값 각 100,000개 완료는 고유값 완료 보장이 아님 |
| 실제 메뉴 진입 | 셀·행·열 명령 5개와 상태 단언 8개 PASS | Shift+F10·펼치기·항목 실행 뒤 결과·원본 보존·정상 종료 확인. 처리 중 Esc 검증과 구분 |
| 큰 범위 경고 아니요·입력 거절 | 보호 조건 7개 PASS | 실제 안내·버튼 응답과 상태 단언 128개를 결합한 별도 평가. 원래 조정기 실패는 보존하며 Esc 시험으로 합산하지 않음 |

근거는 로컬 `evaluated-cancellation07.partial.json`과 [허용 후 재실험 기록](RC9_APPROVED_RETEST_20260917.md)이다. 대조 평가는 P07의 해당 바꾸기 조건에만 적용하며 전체 취소·최종 릴리즈를 승인한 기록이 아니다. 개별 XLSX의 파일 해시는 다르지만 모든 캐시 값·수식 구성을 대조했고, 각 원본의 보존 여부는 자기 실행 전후 해시로 따로 확인했다. 입력 없는 대조와의 경과 시간 차이를 순수 처리 성능으로 사용하지 않는다.

다음 요구는 위 부분 검증과 별도로 판정한다.

- 비교·교체 각각의 100ms·500ms 눌림과 짧은 입력: 정확한 취소 안내, 기존 42개 목록·후속 비교·원본·편집 중인 이전 결과·설정·정상 종료를 함께 기록한다.
- 키 입력 없는 대표 용량·긴 문자열 처리와 기존 선택·정규화 회귀를 확인한다. 추가 조회의 실제 처리시간 영향도 기록한다.
- 기존 메모리 취소 주입 검사의 마지막 읽기·결과 작성·상태표시 오류 경로가 유지되는지 확인한다.
- 현재 확인한 Office 비트수만 실제 검증으로 표시한다. 32비트 Office와 API 차단 정책 환경은 실행하지 않았으면 미검증으로 남긴다.

구현 당시의 참조·정적 검사 통과를 최종 바이너리의 native 취소 통과로 대신하지 않는다. 실제 결과와 최종 지원 문구는 [허용 후 재실험 기록](RC9_APPROVED_RETEST_20260917.md)에 이어 기록한다.
