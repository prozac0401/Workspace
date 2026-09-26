# 시험 보고서

제품: 보이는 칸 붙여넣기 / VisibleCellsPaste 0.1.1 후속 수정 및 0.1.0 이력

기록일: 2026-09-26 · 2026-09-24 이력 보존
분류: 서명 없는 배포물. 실제 실행한 범위와 미검증 환경을 분리하며 조직 배포 승인을 의미하지 않습니다.

## 현재 판정: 후속 설치본의 사용·종료·제거·재설치 PASS

2026-09-26 후속 생산 DLL `7080305afd5a08b2184fbedf9ed3942502184213d096c33864ab3ce1c2ab0329`를 실제 설치한 뒤 정상 자동 메뉴로 붙여넣기, 별도 시작에서 붙여넣기·즉시 Undo를 수행했습니다. 두 경우 모두 UI의 저장 안 함으로 닫았으며 독립 지연 관찰에서 프로세스 소멸과 새 Excel 오류 이벤트·WER 0개를 확인했습니다. 수동 VBA·외부 Excel COM 검사·디버거 없이 실행했습니다.

이 문서는 확인한 실행 범위를 담은 공개 준비 스냅샷입니다. 최종 문서 반영·패키지·CI·실제 공개와 다운로드 결과는 GitHub PR/Release 및 별도 배포 기록으로 확인합니다. 두 합성 시나리오의 통과를 모든 환경의 종료 보증이나 이전 충돌 원인 확정으로 확대하지 않습니다. 같은 DLL의 제거·제거 후 시작·재설치·숨김 값 보존 및 반복 종료도 별도로 확인했습니다.

앞선 설치 후보 `8741b19f1b9533e05f3c6ad126b87ec31e326e71c05438de3bb0a96ec0072ed7`는 정상 자동 로드·붙여넣기 성공 뒤 08:32:09.9715100 UTC에 종료 충돌이 재현됐습니다. Application Error 1000 및 WER는 BEX64, ntdll.dll, c0000409, 부가 값 0xA를 기록했습니다. 최초 프로세스 관찰만으로 정상 종료라고 판정했던 중간 기록은 최종 실패 판정으로 정정해 보존합니다.

그 사건의 새 덤프는 찾지 못했습니다. 2026-09-24 덤프의 CLR RCW 정리·SafeReleasePreemp 스택을 같은 사건에서도 관찰했다고 쓰지 않으며, 상태바 수정·특정 객체·다른 추가 기능을 원인으로 확정하지 않습니다. 0.1.0과 이전 후보의 FAIL 이력은 후속 PASS와 함께 유지합니다.

### 버전·시험 단계별 결과

| 범위 | 현재 판정 | 근거·한계 |
|---|---|---|
| 0.1.0 실제 메뉴 사용 후 종료 | **FAIL 이력 보존** | 합성 시나리오 3회 실패. 릴리스는 draft·최신 표시 해제, 태그 유지 |
| 초기 0.1.1 build02 자동 검사 | **189 PASS** | 당시 8종 검사와 패키지 검사. 후속 제품 수정 전 결과 |
| 초기 0.1.1 실제 업그레이드·두 UI 종료 | **PASS 이력 보존** | DLL `68944bc…`에서 붙여넣기만 / 붙여넣기와 Undo 두 정상 시작 모두 자연 종료, 새 Excel 오류 이벤트 0개 |
| 실제 기능·복구 59개 | **본문 59 PASS / 정리 검증 FAIL** | 19+30+10 본문과 helper 통과. 종료 wrapper의 전역 상태 정확 복원 대조 실패로 전체 scope exit1 |
| 상태바 복원 수정 뒤 full-build-02 | **206 PASS** | 8종 자동 검사, 패키지·33개 소스·9개 문서 검사. DLL `8741b19f…` |
| 같은 후보의 R17 OS 클립보드 | **4 PASS / 8회 거절** | 제품 읽기 전후 sequence·owner·formats·payload SHA-256 불변 |
| 0.1.1 실제 제거·제거 후 시작·재설치 | **PASS** | 비승격 제거, 자체 메뉴 없음, 다른 메뉴·외부 합성 파일·보안 설정 보존. `8741b19f…` 재설치 성공 |
| 같은 최종 후보의 자동 메뉴·붙여넣기 | **PASS** | 외부 Excel COM 검사나 디버거 없이 85/90/78 입력 확인 |
| 같은 최종 후보의 붙여넣기 후 종료 | **FAIL** | 위 08:32:09 UTC의 새 종료 충돌. 초기 두 종료 PASS로 대체하지 않음 |
| 후속 raw 이벤트·연결 수명 소스 검사 | **개별 검사 PASS** | native COM/이벤트 36개씩 x64·x86, 연결 수명 46개, 안내/진입 26개. 실제 Excel 종료와 구분 |
| 후속 full-build-03 및 문서 재포장 | **284 PASS / 패키지 PASS** | 9종 검사·PE/COM·ZIP 내부 무결성 통과. 시험한 7개 비문서 payload를 보존한 문서 재포장으로 9개 문서·33개 소스·17개 항목·16개 내부 해시 일치 확인 |
| 후속 실제 기능·복구 60개 | **60 PASS / 정리 검증 PASS** | 20+30+10, scope exit0·cleanup0. 기존 파일 SHA·객체·개수·선택·5개 전역 속성의 타입·값 정확 복원. 외부 시험 엔진이며 새 설치본 종료 증거가 아님 |
| 후속 생산 DLL R17 OS 클립보드 | **4 PASS / 8회 거절** | DLL `7080305a…`의 실제 읽기. sequence·owner·formats·bytes 불변, Excel COM 접속 없음 |
| 후속 생산 DLL 실제 설치·정상 시작·두 UI 종료 | **PASS** | Excel 0개에서 비승격 설치. 자동 메뉴 붙여넣기 및 별도 붙여넣기·즉시 Undo 뒤 자연 종료. 지연 확인에서 프로세스 부재·새 오류/WER 0개 |
| 같은 설치본의 실제 개수 불일치·빈칸 지움 취소 | **PASS** | 원본3·보이는대상2 거절, 빈칸3의 지움 경고 Escape 취소, 기존101/104/107 유지. 최종 독립 확인은 UI 종료 151초 뒤 Excel0·새 오류/WER0·파일 SHA 동일 |
| 같은 DLL 제거·제거 후 시작·재설치 | **PASS** | 비승격 제거·자체 메뉴 부재·다른 메뉴 유지·같은 DLL 재설치 및 정상 자동 메뉴 확인 |
| 재설치 후 실제 숨김 값 보존·종료 | **PASS** | 붙여넣기 뒤 숨김을 풀어 E2:E8=85/102/103/90/105/106/78 확인. 종료 123초 뒤 프로세스 부재·새 오류/WER0·파일 SHA 불변 |
| main 반영·최종 CI·0.1.1 공개 | **공개 준비 기록** | 제품 소스는 PR #7로 main에 반영. 이번 최종 문서·패키지·CI·게시·다운로드 결과는 GitHub와 외부 배포 기록으로 확인 |

### 0.1.0 종료 실패와 초기 0.1.1 결과

2026-09-24의 0.1.0 실제 메뉴 사용 후 종료 실패 3회에는 자체 Undo를 실행하지 않고 붙여넣기만 한 경우도 포함합니다. 같은 환경의 Excel 기본 복사·붙여넣기·실행 취소 후 종료 대조는 정상 종료했으나, 모든 공존 조건이나 책임 객체를 확정하지 않습니다. 당시 덤프에는 CLR 종료 중 InnerCoEEShutDownCOM → RCWCleanupList::CleanupAllWrappers → RCW::ReleaseAllInterfaces → SafeReleasePreemp 및 잘못된 COM 해제 호출 대상이 관찰됐습니다. 이 진단은 9월 24일 사건에만 해당합니다.

초기 수명 수정은 임시 COM 범위·PreparedPaste 소유권·callback 반환·동일 작업 재진입·이전 Undo 해제 실패와 재연결 정리를 보완했습니다. 첫 중간 184개 회귀 뒤 build02의 코어 47·native 35·bulk 8·연결 17·COM 수명 22·전역 복원 8·안내/진입 22·설치 30, 총 189개가 통과했습니다. 당시 Windows CI 35990030412와 문서 CI 35990030354도 통과했습니다. 이후 소스의 검증 결과로 확대하지 않습니다.

9월 26일 초기 설치 DLL SHA-256은 `68944bc82381e664fd17f51e33e213574c3a852eb5ac7a892777111049dfd796`, ZIP은 `da11aacdaf2240c674903f7a6594160df8dc85d36da655e23ed2ca045641c9fd`입니다. 비승격 0.1.0→0.1.1 업그레이드 후 정상 자동 메뉴로 붙여넣기만 한 경우와 별도 시작에서 붙여넣기/Undo한 경우 모두 UI의 저장 안 함으로 닫고 프로세스 소멸·새 Excel Application 1000/1001/1002 이벤트 0개를 확인했습니다. 디버거·외부 Excel COM 검사·수동 VBA 실행은 없었습니다. 이 두 PASS는 이후 최종 후보의 종료 FAIL과 함께 보존합니다.

### 상태바 정확 복원 결함과 후속 수정

`regression-59/run-02/`의 19+30+10 본문은 통과했지만 종료 wrapper의 전역 상태 복원 대조가 실패했습니다. 진단에서 StatusBar는 Boolean false가 아닌 문자열 `"FALSE"`였고 나머지 네 전역 속성의 타입·값, 기존 워크북·선택·Protected View 개수는 보존됐습니다. 최초 wrapper의 원시 시작값은 기록되지 않았으므로 후속 진단으로 이를 추정하지 않습니다. 첫 `run-01`은 시험 시작 전 합성 파일 해시 읽기의 공유 모드 오류로 중단됐으며 시험용 읽기만 공유 모드로 보완했습니다.

일반·typed PIA·직접 IDispatch의 Boolean false 할당 모두 현재 Excel에서 문자열 FALSE로 읽혔습니다. 직접 VT_BOOL 전달도 같아 원인을 boxing으로 단정하지 않습니다. 빈 문자열과 null 입력은 실제 Boolean false로 읽혔고, saved Boolean false만 복원하는 로컬 후보는 실제 문자열 FALSE·한글 문자열을 그대로 보존했습니다. 제품은 공용 RestoreStatusBar로 기존 값을 할당하고, 저장값이 Boolean false인 COM 객체에서 실제 Boolean false인지 검사합니다. 그렇지 않으면 확인된 빈 문자열 reset을 적용해 다시 검사하고, 여전히 다르면 명시적으로 실패합니다. 실제 문자열은 변환하지 않습니다.

Prepare의 시작값 getter 실패는 변경 전 재시도 가능한 실패로 유지합니다. 상태 복원 실패는 state-restore-failed로 후속 쓰기를 차단하며, 완료 후 안내 실패와 분리합니다. 추가 기능의 상태 안내·종료 정리에서는 확인 실패가 완료된 셀 작업의 결과를 바꾸거나 타이머를 남기지 않도록 처리합니다. 자동 검사의 타입 비교를 문자열 비교로 완화하지 않았습니다. full-build-02의 206개 통과는 이 소스까지의 결과이며 뒤이은 종료 실패를 상쇄하지 않습니다.

### 종료 재현 뒤 추가한 COM 경계 보완

ComEventsHelper는 callback이 사용하지 않는 이벤트 인자도 관리 객체로 변환하므로 임시 RCW가 생길 수 있습니다. 특정 이벤트 인자가 이번 충돌 원인이라는 증거는 없습니다. 후속 구현은 전용 IDispatch sink가 기존 14개 이벤트의 DISPID만 관찰하도록 하여 DISPPARAMS·VARIANT와 Cancel 인자를 읽거나 바꾸지 않습니다. 별도 connection point와 자신의 Advise cookie만 소유하며 Unadvise 실패에도 획득한 connection point를 한 번 반환합니다. 연결 실패는 Undo 관찰 불가로 처리합니다.

OnConnection이 받은 Application 참조 한 번은 추가 기능이 소유하고, 엔진·Undo 관찰자는 빌립니다. IDTExtensibility2의 custom 인자는 설치된 PIA와 같은 [In] 계약으로 맞췄습니다. 명령·확인창·진행·상태 타이머 callback 중 연결 종료가 재진입하면 새 작업을 막고 가장 바깥 callback이 끝난 뒤 실제 정리를 수행합니다. 공유 객체의 임의 FinalRelease나 강제 GC는 사용하지 않습니다.

COM 수명 시험은 x64와 x86에서 각각 36개가 통과했습니다. 실제 CCW의 QI 정체성·IDispatch vtable 호출·14개 이벤트·빈 결과·Cancel 불변·늦은 callback을 검사하고, connection point의 실패·cookie 정리는 가짜 객체로 주입했습니다. 이는 실제 Excel connection point·32비트 Excel·정상 종료 검증이 아닙니다. 연결 수명은 46개, 안내/진입은 26개가 개별 통과했습니다. 안내 시험은 정상 연결 fixture를 명시하고 실제 실패주입 도달을 검사했으며 기존 성공 판정·복구 assertion을 유지했습니다.

### 새 소스의 실제 60개 회귀와 R17

`regression-60/raw-event-run-01/summary.json`에서 Functional 20·Extended 30·RemainingSafety 10, 합계 60개가 통과했습니다. scope exit0·실패0·cleanup0이며 기존 합성 파일 SHA-256, 워크북 객체·개수·선택·저장 상태와 Protected View 개수를 복원했습니다. EnableEvents·Calculation·ScreenUpdating·StatusBar·DisplayAlerts는 시작·종료의 실제 타입과 값이 모두 일치했습니다. StatusBar 시작·종료는 Boolean false였고 문자열 변환으로 비교 기준을 완화하지 않았습니다.

추가 U12-statusbar-ownership-all-paths는 실제 Boolean false와 실제 문자열 FALSE를 각각 Prepare·거절·Apply·Undo·쓰기 실패 복구·취소 복구·복구 실패 뒤에도 정확히 보존했습니다. 구 `68944bc…` 설치본의 Prepare-only 실패 재현과 새 소스의 통과를 분리해 보존합니다. 시험 DLL은 시험 전용 실패주입 빌드이며 생산 소스 13개의 해시가 full-build-03과 일치합니다. 외부 EXE에서 합성 불변 스냅샷으로 실행했고 기존 `8741b19f…` 설치 추가 기능이 함께 있었습니다. 따라서 새 DLL의 정상 자동 로드·실제 클립보드 붙여넣기·종료 안전성을 입증하지 않으며, 실패주입은 자연 발생 COM 장애를 재현했다는 뜻이 아닙니다.

`r17-os-clipboard-raw-event/summary.json`은 생산 DLL `7080305a…`로 합성 OS 클립보드 4종·8회 거절을 확인했습니다. 각 읽기 전후 sequence·owner·formats·payload bytes가 불변이었습니다. 승인된 두 소유 Excel의 정확한 실행 정체성만 허용하는 로컬 시험 사본을 사용했고 검사마다 일치를 확인했습니다. 원 시험 소스·제품은 변경하지 않았고 Excel 실행·COM 접속·설치·등록 변경은 없었습니다. 같은 시점의 60개 회귀는 OS 클립보드를 사용하지 않았습니다. 첫 CVTRES 실행 실패와 동일 컴파일 명령 재시도 성공도 보존합니다. R17 반복 실행은 요구사항 완료 수에 중복 합산하지 않습니다.

### 후속 DLL의 실제 설치·자동 메뉴·사용 후 종료

접근 거부되던 잔여 프로세스를 사용자가 정리한 뒤 Excel 0개를 확인하고 후속 생산 DLL `7080305a…`를 비승격 설치했습니다. 설치 exit0, 설치 DLL·소유 파일 해시·COM 등록·LoadBehavior 3을 확인했고 보안 정책과 다른 추가 기능 등록은 바뀌지 않았습니다. 설치 사전검사를 우회하지 않았습니다.

실제 UI 시험은 서로 다른 정상 시작으로 분리했습니다. 붙여넣기만 수행한 경우 가로 원본 85/90/78을 숨긴 행이 있는 E2:E8의 보이는 E2/E5/E8에 입력했습니다. 다른 정상 시작에서는 같은 붙여넣기 직후 선택을 유지한 채 자체 Undo로 101/104/107을 복원했습니다. 각각 자체 메뉴가 한 개씩 자동 표시됐으며 외부 Excel COM·디버거·수동 VBA 실행이 없었습니다.

두 창을 저장하지 않고 닫은 뒤 각각 540초·381초 시점의 독립 조회에서 해당 프로세스가 없었고, 시험 시작 이후 새 Excel Application 1000/1001/1002 이벤트와 WER는 0개였습니다. 앞선 오류는 UTC로 구분해 제외했습니다. 이는 제한된 관찰 시점의 실제 자연 종료 결과이며 이후 모든 종료 조건의 안전성을 보장하지 않습니다. UI에서 숨김 유지 여부는 확인했지만 숨긴 셀의 원시 값을 다시 읽지 않았으므로 그 값·타입 보존의 근거는 앞선 60개 회귀와 구분합니다.

세 번째 정상 시작에서 원본 3개·보이는 대상 2개는 0개 수정 안내와 101/104/107 유지로 거절됐습니다. 실제 빈칸 3개를 보이는 3개에 넣으려 할 때 지움 3개 확인을 표시했고 Escape로 취소해 같은 값을 유지했습니다. Alt+F4로 저장 안내 없이 닫았고 81초 뒤 Excel 0개·새 오류 이벤트 0개·파일 SHA 동일을 확인했습니다. 후속 독립 확인은 종료 151초 뒤에도 Excel 0개·새 오류/WER 0개와 두 합성 파일 SHA-256 불변을 확인했습니다. 같은 DLL의 제거·재설치 결과는 아래에 별도로 기록합니다.

### 같은 DLL 제거·재설치와 반복 종료

같은 생산 DLL `7080305a…`의 비승격 제거는 exit0으로 소유 매니페스트·등록·파일을 정리했습니다. 외부 합성 파일과 다른 추가 기능·보안 값은 유지됐습니다. 제거 후 정상 Excel 시작에 누락 파일 경고와 자체 두 메뉴가 없고 SelectionExport 메뉴가 남았습니다. 해당 창을 자연 종료한 뒤 367초의 독립 관찰에서 프로세스 부재·새 Excel 오류 이벤트/WER0을 확인했습니다.

이어서 같은 검증 ZIP으로 재설치하여 생산 DLL 해시·소유 파일·COM 등록·LoadBehavior 3과 보호 설정의 일치를 확인했습니다. 정상 자동 메뉴로 85/90/78을 붙여넣은 다음에만 Ctrl+Shift+9로 숨김을 풀어 E2:E8이 85/102/103/90/105/106/78임을 UI에서 직접 확인했습니다. 숨겼던 E3/E4/E6/E7의 원래값 102/103/105/106이 유지됐고 상태바는 준비 상태로 돌아왔습니다.

저장하지 않고 닫은 뒤 123초의 독립 관찰에서 프로세스 부재·새 오류 이벤트/WER0과 두 원본 합성 파일 SHA-256 불변을 확인했습니다. 전체 과정에는 외부 Excel COM 검사·디버거·수동 VBA가 없었습니다. 최초 세 사용 시나리오와 설치 수명주기 두 시나리오의 지연 관찰을 모두 보존하며, 이 결과를 다른 Office 빌드·32비트 Excel·모든 추가 기능 공존 환경의 보증으로 확대하지 않습니다.

### 로컬 증거와 배포 기록

근거 루트는 `artifacts/visible-cells-paste/release-validation/resume-2026-09-26/`입니다. 원시 덤프·개인 경로·실행 식별자·진단 본문은 저장소·배포물·공개 사이트에 복사하지 않습니다.

| 범위 | 로컬 근거 |
|---|---|
| 초기 업그레이드·두 UI 종료 | `install/summary.json`, `ui-paste-only-observation.json`, `ui-paste-only-exit.json`, `ui-paste-undo-observation.json`, `ui-paste-undo-exit.json` |
| 59개 본문·상태바 대조 | `regression-59/run-02/`, 그 안의 `global-state-diagnostic/{setter-results,raw-setter-results,input-variants-results,candidate-restore-results}.json` |
| 상태바 수정·206개 전체 빌드 | `status-restore-fix/`, `final-full-build-02/immutable-build/` |
| 최종 후보 R17 | `r17-os-clipboard-final/{process.json,stdout.log,summary.json,fixtures/non-excel-clipboard-results.json}` |
| 제거·재설치 | `uninstall/summary.json`, `uninstall/ui-menu-absence.json`, `reinstall/summary.json` |
| 최종 후보 실제 붙여넣기·종료 실패 | `final-ui/paste-only-observation.json`, `final-ui/paste-only-final-outcome.json`, `final-ui/paste-only-failure-events.xml` |
| 새 WER와 덤프 부재 | `final-ui-crash-diagnostic/summary.json` |
| raw 이벤트 x86/x64 | `raw-event-fix/source-and-results.json`, `raw-event-fix/{x64,x86}/com-lifetime-tests.log` |
| 연결 재진입·안내 회귀 | `addin-deferred-disconnect/`, 그 안의 `presentation/after-fixture.log` |
| 새 소스 실제 60개 회귀 | `regression-60/raw-event-run-01/summary.json`, 같은 폴더의 `production-source-alignment.json` |
| 새 생산 DLL R17 | `r17-os-clipboard-raw-event/{summary.json,execution.json,fixtures/non-excel-clipboard-results.json}` |
| 이전 설치 차단 이력 | `residual-process-25276/result.json` |
| 후속 DLL 실제 설치·UI·종료 | `after-process-cleanup-7080/install/summary.json`, 같은 폴더의 `paste-only-observation.json`, `paste-undo-observation.json`, `ui-exit-independent.json`, `ui-exit-independent-all.json` |
| 후속 DLL 실제 거절·확인 취소·종료 | `after-process-cleanup-7080/refusal-cancel-observation.json`, `refusal-cancel-exit-observation.json` |
| 같은 DLL 제거·재설치 | `after-process-cleanup-7080/uninstall/summary.json`, `uninstall/ui-menu-observation.json`, `reinstall/summary.json`, `reinstall/ui-observation.json` |
| 제거 후 시작·재설치 뒤 반복 종료 | `after-process-cleanup-7080/ui-lifecycle-final-independent.json` |

R17은 실제 Windows 클립보드의 소유 합성 Unicode 텍스트·HTML 표·DIB 그림·파일 목록 4종을 최종 후보 DLL의 읽기 경로에 전달한 시험입니다. caller mode 0/1마다 VCP-CLIPBOARD-COPY-UNVERIFIED로 거절해 8회 모두 읽기 전후 sequence·owner·formats·payload SHA-256이 일치했습니다. Excel 실행·COM 접속은 없었습니다. 최초 helper 실행 EPERM과 동일 명령 한 번 재시도 exit0 기록을 함께 보존하며, 4개 사례를 59개 본문이나 이전 동일 R17과 중복 합산하지 않습니다.

앞선 종료 실패 후보 ZIP은 `4e7acf62…`였고 그 설치·재설치 성공을 후속 생산 DLL의 결과로 승계하지 않았습니다. full-build-03은 9종 284개와 PE/COM·ZIP 내부 무결성 검사를 통과했습니다. 그 최초 ZIP `5fe8f24c…`는 제작 중 갱신된 문서와 달랐으므로 중간 산출물로 보존했습니다. 이후 시험한 7개 비문서 payload를 바꾸지 않고 9개 문서를 다시 포장해 17개 항목·16개 내부 해시·33개 소스 일치를 확인했습니다.

후속 설치·두 UI 종료는 해당 생산 DLL을 설치해 별도로 확인했습니다. 이번 실행 결과를 반영하는 최종 문서 재포장도 같은 불변 payload를 사용하며 실제 ZIP 해시와 완료 판정은 외부 SHA256SUMS·배포 기록에 남깁니다. 제품 소스는 PR #7의 main 병합 `ecb4cf6`에 반영됐습니다. 이 문서 자체를 포함한 최종 변경의 main 반영·CI·공개·실제 다운로드 결과는 GitHub 기록으로 확인하며, 문서 작성만으로 게시 완료를 주장하지 않습니다.

## 2026-09-24 동결한 0.1.0 결과 요약

다음 수치와 전체 D/R/U/I/P 표는 게시 전 동결한 검증 범위를 보존한 것입니다. 게시 후 발견된 종료 실패와 0.1.1 재검증 상태는 위 추가 게이트를 따릅니다.

당시 필수 시험 76개 범위별 판정은 **PASS 69 / FAIL 0 / BLOCKED 0 / NOT RUN 7**입니다. 일부 ID의 PASS는 순수 로직 또는 실제 Excel에서 분리 검증한 구성요소 범위이며 아래 근거에 구분했습니다. NOT RUN 행도 일부 하위 검사가 통과했을 수 있습니다. 설치 후보의 정상 시작·자동 연결·실제 메뉴 붙여넣기·자체 Undo를 확인했습니다.

- 순수 파서·타입·계획·한도: 47 PASS, 0 FAIL.
- Biff12 날짜 보완·ZIP·native 좌표/타입·악성/절단 입력 순수 회귀:35 PASS,0 FAIL.
- 일괄 셀 스냅샷 순수 회귀: 8 PASS, 0 FAIL. 혼합 상태 fallback과 수식/상수 타입을 검증했습니다.
- 설치기 순수 소유권·경로·매니페스트·CLR 파일 로드:24 PASS,0 FAIL. 한글·공백·작은따옴표·퍼센트·#가 포함된 경로4종에 합성 검사용 DLL을 실제 분리 AppDomain으로 로드하는 검사를 포함합니다.
- 실제 Excel 후보02 회귀: 기본 19 + 확장 30 + 추가 안전 10 = 59 PASS, 0 FAIL. 세 helper와 소유 workbook 정리 wrapper가 모두 exit0입니다. 후보02 제품 소스 12개의 해시와 시험 DLL 소스가 일치했습니다.
- 최종 성능 행렬: 순수 모델8개+실제 Excel8개 =16 PASS. 설치된 추가 기능의 속도와 구분한 외부 COM 측정입니다.
- 실제 UI Ctrl+C: 세로 타입/빈칸/끝 빈칸, 가로, 전부 빈칸, 수식 결과 표본을 확인했습니다. 필터된 원본의 두 항목 순서와2×2 거절도 실제 UI 복사로 확인했습니다. 실제 Ctrl+X는 안전 거절했습니다.
- 별도 원본 PID14700과 대상 PID25804 사이에서 실제 클립보드5개를 읽어 대상에 쓰고 타입·형식·선택 밖 표본을 검사했습니다.
- 0.1.0의 실제 날짜·시간·백분율·빈칸·필터 표본과1900/1904 원시 숫자 보존을 확인했습니다. 설치 UI에서1900 원본→1904 대상에45200/0.5/0.125를 그대로 쓰고 대상0.0000 형식·숨긴 셀을 보존한 뒤 Undo했습니다. 이전 평가판의 DateTime 거절은 수정 전 증거입니다.
- COM 연결·종료 정리 순수 시험: 최초4개에 상태바 getter/setter 오류와 종료 정리4개를 더해8 PASS. 실제 자동 로드 증거와 구분합니다.
- 쓰기 진입·진행·결과 안내 예외 순수 회귀: 22 PASS. 전역 getter 4종 실패 시 변경 없이 재시도 가능하며, 완료 후 상태바 오류가 성공/Undo 결과를 실패로 바꾸지 않음을 fake 객체로 확인했습니다.
- 전역 상태 복원 실패 순수 회귀8 PASS: setter 개별·동시·부분 변경 후 실패, 나머지 복원 시도, 재진입/후속 쓰기 차단을 fake Application으로 확인했습니다. 실제 COM 장애 주입과 구분합니다.
- 별도 순수 한도 경계9 PASS: XML 페이로드32MiB±1byte, 원본50,000±1항목, 구간20,000±1개. 실제 선택200,000±1셀 시험과 합쳐 한도별 직전·정확·초과를 확인했습니다.
- 비승격 설치와 특수문자 경로의 업그레이드·자동 로드·정상 제거·제거 재실행, 기본 경로 재설치를 확인했습니다. 제거 후 자체 메뉴가 사라지고 외부 합성 파일과 SelectionExport 메뉴는 남았습니다. 같은 기본 설치 상태의 정상 시작 두 번에서 자동 연결과 중복 없는 메뉴를 확인했습니다. 다른 도구 동작은 별도 항목으로 구분합니다.
- 추가 안전 시험의 최초9 PASS/1 FAIL(Protected View StatusBar 접근)을 보존했습니다. 수정 후 읽기 전용/PV 집중2개와 이후 전체10개가 모두 통과했습니다. 위59개에 포함되며 중복집계하지 않습니다.
- 다른 프로세스의 HWND 소유 클립보드 점유에서 네이티브 읽기/열거가 제한시간 안에 거절되고 메타데이터가 유지됨을 확인했습니다. 읽기 중 교체 시험과는 구분합니다.

## 환경·실행 경계

Windows 11 빌드22631, Excel x64 16.0.20326.20158, 설치된 .NET Framework C# 컴파일러 환경입니다. Excel 32비트와 다른 Office 빌드는 실행하지 않았습니다. 처음에는 실행 중 Excel을 유지해야 하여 설치 시험이 BLOCKED였으나, 이후 사용자가 종료·설치·추가 검증을 승인하여 정상 설치 경로 시험을 재개했습니다. 설치 사전검사를 우회하지 않았습니다.

실제 기능 시험은 별도로 소유한 VCP 합성 통합문서·프로세스에서 수행했습니다. 외부 시험 프로그램이 엔진 assembly를 직접 호출한 결과와 설치 후 실제 메뉴 클릭 결과를 구분합니다. 이전 외부 엔진 검증만으로 자동 로드를 주장하지 않습니다. UI 복사는 실제 셀 선택과 Ctrl+C/Ctrl+X로 수행했습니다. 일반 사용자 배포에는 VCP_TESTING 실패 주입을 활성화하지 않습니다.

## 실제 명령과 증거

저장소 루트에서 아래 명령을 사용합니다. 로그·합성 표본은 artifacts/visible-cells-paste 아래의 로컬 증거이며 배포 ZIP에 넣지 않습니다.

| 범위 | 명령·방법 | 실제 결과·증거 |
|---|---|---|
| 순수 코어 | powershell -NoProfile -ExecutionPolicy Bypass -File tools/VisibleCellsPaste/tests/unit/Run.ps1 | 47 PASS/0 FAIL, unit/results.txt |
| 일괄 셀 읽기 순수 | BulkSnapshotTests의 fake range를 이용한 수식·상수·혼합 형식 회귀 | unit/bulk-snapshot-results.txt, 8 PASS. 최종 제작의 bulk-snapshot-tests.log에도 기록 |
| 기본 Excel 후보02 | FunctionalTests.exe 27888 <결과파일> --synthetic-regression | release-validation/final-regression/FunctionalTests.txt,19 PASS/0 FAIL·exit0. 순수 타입 스냅샷을 실제 Excel에 쓰는 회귀이며 실제 clipboard 읽기 증거와 구분 |
| 확장 Excel 후보02 | ExtendedTests.exe 27888 <결과파일>; 전용 workbook의 시험 시트만 생성·정리 | release-validation/final-regression/ExtendedTests.txt,30 PASS/0 FAIL·exit0. 선택적 세번째 인자는 시험명 필터 |
| 실제 숫자 표시·기본Undo 영향 | 숫자85를00085로 표시하여복사, UI타이핑2회후도구메뉴로붙여넣기 | numeric-display-ui-paste.json, builtin-undo-before/after.json. 자체Undo는numeric-display-ui-undo.json에서E2:E8의101..107·0.0000복구확인. 실제숫자85·대상0.0000·선택밖값유지, 기본Undo True→False |
| 실제 대량·진행 취소 | 설치candidate01로10,000개 원본→10,000개 교대 가시대상. 확인창 취소 후다시진행창에서취소 | release-validation/large-warning-ui.txt,large-warning-cancel.json,large-progress-cancel-result.json,large-cancel-completed-ui.txt. 전체19,999셀무변경/복구·전역상태유지. PV수정전설치후보의실제UI경로임 |
| 실제 확인창 | 빈칸3개를 포함한7칸 원본, 합산 경고 취소/확인·Undo | release-validation/blank-warning-ui.txt와blank-warning-cancel/confirmed/undo.json. 취소시7칸무변경, 확인후위치·형식유지, Undo원복 |
| 설치 UI | 정상 시작 후 실제 우클릭 메뉴로 붙여넣기·Undo | release-validation/candidate-ui-paste.json, candidate-ui-undo.json, candidate-contextmenu.txt. Connect=True, 가시E2/E5/E8 쓰기와원복·숨긴4셀보존 |
| 추가 안전 후보02 | RemainingSafetyTests.exe 27888 <결과파일> <소유fixture경로> | release-validation/final-regression/RemainingSafetyTests.txt,10 PASS/0 FAIL·exit0. 최초remaining-safety-candidate.txt의9 PASS/1 FAIL과수정후집중회귀증거를보존 |
| Protected View 수정 회귀 | 같은helper + R09- 필터, 전용수정DLL | release-validation/remaining-safety-pv-fixed.txt, 2 PASS/0 FAIL·exit0. ef559b7b… DLL; 읽기전용/PV 내용·타입·형식·파일해시보존 |
| 클립보드 점유 | ClipboardAdversarialHwndTests, 메시지전용창 소유PID검증 | release-validation/clipboard-adversarial-candidate.txt, 7 PASS/0 FAIL/1 NOT RUN. 4개순수unsupported parser+네이티브경합2+메타데이터보존1. 현재owner=Excel provenance는 미실행 |
| 이벤트·정렬 조사 | UndoEventProbe.exe 25804 <결과파일> | m0/undo-event-probe.txt, undo-sort-probe.txt |
| 실제 클립보드 | UI 복사 후 ClipboardIntegrationTests의 소유 PID 제한 읽기·쓰기 | m0/cross-process.json, clipboard-horizontal.json, clipboard-blank.json, clipboard-formulas.json, clipboard-cut.json, clipboard-filtered.json |
| 실제 겹침 | UI Ctrl+C H1:J1 후 OverlapClipboardTests로 I1:I3 쓰기·Undo | m0/overlap-ui-copy.txt, 3 PASS. 복사 후 원본I1이 덮여도 불변 스냅샷 유지 |
| 실제 날짜·체계 차이 | 실제 Ctrl+C와독립숫자디코더검토, 설치UI로다른날짜체계대상에붙여넣기/Undo | release-validation/date-capture/independent-date-review.json의7표본PASS 및cross-date-system-ui-paste/undo.json. raw숫자·빈칸·대상형식·숨김보존,달력보정없음 |
| 날짜 조사 이력 | 실제 날짜 Ctrl+C와 XML/CF_HTML·BIFF8 조사 | m0/clipboard-date.json, date-html/HTML-Format.bin. XML/HTML에는 raw45200이 없으나 BIFF8 RK에는 존재. 이전 평가판 거절 증거이며0.1.0 Biff12 보완 결과와 구분 |
| 설치 중단 | Setup --install / --uninstall, 한글·공백·작은따옴표가 있는 시험 경로 | installer-tests/excel-running-refusal-evidence.json. 두 호출 exit1, 대상 미생성·제품 HKCU 두 view/PID목록 동일 |
| 실제 설치 수명주기 | 비승격 후보03 업그레이드, 정상 UI 시작/종료, 제거·제거 재실행, 기본 경로 재설치 | release-validation/m3-execution-integrity.txt, m3-upgrade-custom.json, m3-custom-autoload.json, m3-uninstall-custom/repeat.txt, m3-uninstall-preserved.json, m3-uninstalled-menu.txt, m3-default-install.txt, m3-default-autoload.json. 등록만으로 자동 로드를 판정하지 않음 |
| 설치기 순수 | 제작 컴파일러로 Setup.cs+SetupTests.cs를 /main:SetupTests로 제작 후 전용 임시 경로 인자 실행 | installer-tests/result.txt 최초16 PASS;0.1.0/setup-tests.log는경로별합성DLL의실제CLR로딩8검사를더해24 PASS. 실제Excel설치수명주기와구분 |
| 쓰기 진입·진행·안내 예외 순수 | PresentationAndEntryTests의 getter/status/progress 오류 주입 및 상태별 안내 | release-validation/exception-paths/PresentationAndEntryTests.log, 22 PASS/0 FAIL. 전역 getter4·성공 표시6·Undo 표시1·timer 정리1·진행 오류 중 복구2·결과 안내8. 같은 소스로 전역 복원8·연결/종료8도 재통과. fake 객체이며 실제 Excel COM 장애 주입은 아님 |
| 전역 복원 실패 순수 | GlobalStateRecoveryTests의 fake Application setter 실패 주입 | unit/global-state-recovery-results.txt, 8 PASS. 상태 복원 오류를 모으고 나머지 setter 시도·busy/Suppress 복원·RecoveryRequired/Undo 비활성·후속 COM 접근0 확인 |
| 한도 정확 경계 | powershell -NoProfile -File tools/VisibleCellsPaste/tests/unit/Run-LimitBoundaries.ps1 | unit-boundaries/results.txt와runner-process.json,9 PASS·exit0. 페이로드33,554,432bytes·원본50,000·구간20,000의직전/정확/초과. 초기limit-boundaries9개/payload-boundary3개와중복집계하지않음 |
| COM 연결·종료 정리 | fake object의 연결·중복 연결·부분 실패·상태바 getter/setter 오류 | lifecycle-shutdown-validation/results.txt,8 PASS. 타이머·관찰자·app 참조·busy 정리. 실제COM 종료장애나설치정상시작시험과구분 |
| 빈칸 쓰기 조사 | EmptyWriteProbe.exe 25804 <결과파일> | m0/empty-write-probe.txt. ClearContents 뒤 기본Undo 활성, Value2=null 뒤 기본Undo 비활성·실제빈칸·형식 유지 관찰 |
| 이벤트 선언 | 설치된 Excel15.0 PIA reflection과 UndoEpoch.cs standalone csc /target:library | IID/DispId/서명 확인 및 컴파일 PASS. 이벤트 발생 자체는 별도 probe로 검증 |
| 문서 | .tools/docs-venv/Scripts/python.exe -m mkdocs build --strict; 같은 Python으로 scripts/check-site.py site | 둘 다 exit0. docs-validation/mkdocs-strict-final.log, check-site-final.log. 공개16페이지+404·비공개 경로 제외·로컬 링크 검사, 게시 없음 |

이전 평가판의 제작 검사는 75개(코어47 + 일괄 스냅샷8 + 연결 수명4 + 설치기16)였습니다. 0.1.0 후보02의 전체 제작은 native35·전역 복원8·설치 경로 추가8을 포함하는 126개를 모두 통과했습니다. package-candidate-02-evidence/summary.json은 exit0·소스 해시30개 일치·파일 해시16개 검증을 기록합니다.

연결 종료 회귀 4개를 추가한 후보03 전체 제작은 130개 모두 PASS·exit0입니다. package-candidate-03-evidence/summary.json에 ZIP 항목17개·파일 해시16개·소스 해시30개를 기록했습니다. 후속 쓰기 진입·진행·결과 안내 예외 22개도 통과하여 순수 시험 종류별 합계는 152개입니다. 이 22개 추가 후 전체 패키지 제작과 최종 ZIP 해시는 외부 최종 배포 기록으로 연결합니다. 후보의 해시를 최종 해시로 사용하지 않습니다. 별도 한도 경계 9개와 필수 요구사항 76개 ID는 다른 집계입니다.

최신 59개 회귀는 RegressionScope가 기존 3개 소유 workbook을 보존하고 새 VCP-Regression.xlsx에서 세 helper를 순차 실행했습니다. 자기 workbook만 닫고 기존 참조·개수·선택·전역 속성을 복원했으며 scope-process.json이 exit0을 기록합니다. 시험 DLL SHA-256은 4b7f7fc6f5cb8952a28762416152921097adcc6c0ff6e05b27d7936626d47af4이며, candidate-source-comparison.json에서 후보02 제품 소스 12개의 일치를 확인했습니다. 실패 주입 VCP_TESTING을 포함하는 시험 DLL이므로 배포 DLL과 바이너리 해시는 다릅니다.

이후 최종검토에서 두 예외 정리 경로를 보완했습니다. AddIn은 상태바 오류가 있어도 타이머·이벤트·참조를 finally에서 정리하며 연결/종료 순수8개가 통과했습니다. COM 객체 비교는 두번째 포인터를 얻지 못해도 첫번째 포인터를 finally에서 해제하도록 정적검토로 보완했습니다. 후자의 예외 자체를 실행한 별도 시험은 없습니다.

마지막 독립 검토에서는 쓰기 전 전역 getter가 실패하면 busy가 고착될 수 있는 경로와, 쓰기 성공 후 상태 표시 COM 오류가 “변경 없음” 안내로 바뀔 수 있는 경로를 보완했습니다. 모든 전역 시작값을 읽은 뒤 busy를 설정하고 성공 상태 표시는 best effort로 처리합니다. 복구 안내 progress가 실패해도 실제 복구 경로를 계속 실행하며 부분 복구 실패를 숨기지 않도록 했습니다. 현재 작업의 검증 거절과 이전 성공 기록을 구분하여 결과 안내가 잘못된 “변경 없음”을 약속하지 않게 했습니다. 새 fake 회귀 22개와 기존 전역 복원 8개·연결/종료 8개가 모두 통과했습니다. 정상 셀 쓰기·복구 알고리즘은 유지하며 예외 처리 경계를 보완했습니다. 앞의 실제 59개가 후속 예외 수정까지 실행된 것처럼 집계하지 않으며 최종 설치·UI 결과는 별도로 연결합니다.

실제 기능 helper는 System.Core, Microsoft.CSharp, System.Windows.Forms, System.IO.Compression, System.IO.Compression.FileSystem과 해당 시험 engine DLL을 참조해 제작합니다. 최종 사용자에게 이 제작 절차를 요구하지 않습니다.

## 실패 발견과 수정 이력

첫 기본 기능 실행은 숨긴 의존 수식의 재계산 결과를 상수처럼 비교하여 보존 검사에 실패했습니다. 수식은 정의·형식을 비교하도록 시험 판정식을 수정했고 run2의19개 시나리오는 통과했습니다. 최초 실행 중 helper 시간 제한도 있었으므로 해당 부분 실행을 완료 결과로 사용하지 않습니다.

첫 확장 실행은15 PASS/2 FAIL이었습니다. 그중 **동일 값 행 정렬 뒤 Undo 허용은 실제 제품 결함**이었습니다. 이벤트 probe에서 COM Range.Sort 뒤 Version0·EnableEvents=True·기본Undo비활성을 관찰했으며, 같은 관찰자의 일반 편집/선택/행삽입에서는 Version이 증가했습니다. 이벤트 등록 실패가 아니었습니다. 정렬 전 SortFields.Count0에서 정렬 후1로 바뀌고 범위·키가 남는 것을 확인했습니다.

제품을 수정하여 워크시트와 그 안의 모든 표에 기존 SortFields가 없을 때만 최근 Undo를 허용하고, Undo 직전에도 다시 검사합니다. 일반 정렬·표 정렬·기존 정렬이 있으면 즉시 Undo 거절·정렬 없는 정상 즉시 Undo를 모두 실제 Excel에서 재시험해 통과했습니다. 정렬 설정을 자동 지우지 않습니다. 정렬 메타데이터를 외부 코드가 지우는 경우까지 완전 보장하지 않습니다.

다른 최초 확장 실패는 이미 닫힌 시험용 다른 통합문서 RCW를 동적 호출로 해제하는 helper 정리 코드 오류였습니다. 정적 object 캐스트로 수정했고 다른 파일에서의 Undo 거절과 정리 모두 후속22개 실행에서 통과했습니다. 최초 실패는 m0/extended-results.txt, 수정 후 결과는 m0/extended-results-fixed.txt에 각각 보존합니다.

대량 검사·백업·복구를 연속 구간으로 묶은 뒤 추가한 혼합 타입·형식 시험에서 먼저 시험 fixture의 영문 General 형식이 한국어 Excel에서 0x800A03EC로 거절되었습니다. 새 셀의 실제 NumberFormat을 읽어 fixture를 교정했습니다. 교정 후에는 끝 Empty를 ClearContents로 쓰면 기본 Undo가 활성화되어 자체 Undo가 비활성화되는 별도 제품 결함을 확인했습니다. 보수적 Undo 조건을 낮추지 않았습니다.

독립 probe는 ClearContents 뒤 기본 Undo 활성, Value2=null 뒤 기본 Undo 비활성·상수/수식 제거·표시 형식 보존을 확인했습니다. 제품의 빈칸 쓰기·롤백·Undo 세 경로를 Value2=null로 바꾸고, 혼합 수식/문자열/빈칸/형식 복구와 전부 빈칸 붙여넣기 후 Undo를 각각 재시험해 통과했습니다. 초기 실패는 extended-results-optimized.txt와 extended-mixed-format-rerun.txt, 게이트 진단은 extended-mixed-format-gate.txt, probe는 empty-write-probe.txt, 수정 후 집중 회귀는 extended-mixed-final.txt·extended-blank-final.txt에 보존합니다. 해당 수정 후 당시 Functional19개와 Extended29개를 순차 실행하여48개가 모두 통과했으며 final-regression-chain.txt는 집중 시험을 포함한4개 helper의 정상 exit0을 기록합니다.

추가 교대5,000구간 성능 시험 후 데이터 검증 규칙의 SpecialCells 조회를 구간마다 반복하던 부분을 선택당 한 번으로 묶었습니다. 조회 결과는 실제 가시 대상과 다시 교차합니다. 가시 셀에만 있는 규칙 거절, 단일 대상 밖 규칙 허용, 숨긴 E3에만 있는 규칙·값·형식 보존을 포함한 최신 Extended30개와 같은 최종 엔진의 Functional19개를 재실행하여49개 모두 PASS·helper exit0을 확인했습니다. U08/U09 실패 주입·U11 취소·U12 전역 상태 복원도 포함합니다. 이전 성능 기록은 보존하며 최종 성능은 이 변경을 포함한 시험 DLL로 다시 측정하여 아래 최종 표에 기록했습니다.

실제 Protected View를 새로 시험하자 Prepare가 대상 거절 전에 StatusBar를 변경하여0x800A03EC를 내는 제품 결함을 발견했습니다. 최초 후보는9 PASS/1 FAIL로 보존했습니다. Protected View 검사를 상태바·선택·읽기전용 속성 접근보다 앞으로 옮기고 읽기 전용/PV 두 사례를 실제 Excel에서 재시험하여2 PASS·exit0을 확인했습니다. 모두 셀 내용·타입·형식·저장 파일 해시를 보존했습니다.

0.1.0 설치 최초 후보에서는 CodeBase에 이스케이프된 공백 때문에 자동 로드가 실패했습니다. 원시 file URI 등록으로 수정한 뒤 정상 시작에서 Connect=True와 실제 메뉴 붙여넣기·Undo를 확인했습니다. 파일이 설치된 사실만으로 자동 로드를 통과 처리하지 않았습니다.

클립보드 점유 helper의 최초 두 실행은 NULL 창으로 잠금을 여는 fixture여서 별도 프로세스 점유를 증명하지 못했고6 PASS/2 FAIL이었습니다. 메시지 전용 HWND와 실제 소유PID검증을 추가한 신규binary로 재실행해 경합시험을 통과했습니다. 최초 실패와 수정된 소스/실행해시를 각각 보존합니다.

## 마일스톤과 배포 상태

| 단계 | 실제 완료 범위 | 남는 제한 |
|---|---|---|
| M0 | 작업공간/원본/환경/구조 조사, 실제 타입·빈칸 클립보드, 정상 시작 자동 로드·메뉴콜백 | 관찰한 Windows/Excel 빌드에 한정 |
| M1 | 엄격한 XML과 제한적Biff12 숫자보완, 한열계획·수량·한도·악성입력순수시험 | 새 오류·지원형식 불일치 거절; 실제경로별 근거 구분 |
| M2 | 실제 쓰기·복구·타입·숨김·정렬·객체교체·readonly/PV/pivot/group 회귀, 설치UI붙여넣기/Undo | 아래 NOT RUN 환경과 외부 동시수정의 감지한계 |
| M3 | 비승격 설치·특수문자 경로 업그레이드·정상 자동 로드·제거/재제거·기본 경로 재설치 확인 | 동일 설치의 두 번 정상 시작 PASS; 다른 제품 동작·정책/32비트 미검증은 I01–I13에 구분 |
| M4 | 후보03 전체130검사·17ZIP항목/16파일해시·30소스해시·x86/x64 PE/COM/메뉴·시험기능제외검증PASS | 문서확정후최종해시·공개여부는실제생성/게시결과로기록 |

제작 명령은 powershell -NoProfile -File tools/VisibleCellsPaste/build/build.ps1입니다. 0.1.0 생성 경로는 artifacts/visible-cells-paste/0.1.0/VisibleCellsPaste_0.1.0.zip이며 같은 폴더의 SHA256SUMS.txt가 ZIP 해시를 기록합니다. 패키지 내부 build-manifest.json은 컴파일러·비트수·소스 해시·서명 없음 분류를, 내부 SHA256SUMS.txt는 파일 해시를 기록합니다. 이 문서는 패키지 제작 전 확인한 결과의 스냅샷입니다. 최종 ZIP 해시·그 ZIP의 실제 설치 후 검증·게시 결과는 패키지 외부 배포 기록으로 연결합니다. 이전0.1.0-eval.1의75검사·17ZIP항목·16파일해시·PE/COM/Ribbon 검증은 이전 빌드의 사실이며 새 버전 검증을 대신하지 않습니다.

## 성능 측정

최종 성능 시험은 별도 .NET EXE가 소유한 target PID25888에 프로세스 간 COM으로 연결한 harness 측정입니다. **설치된 추가 기능의 Excel 내부 실행 속도 측정이 아닙니다.** 설치 자동 로드 여부와 별개로 이 외부 harness의 측정치를 제품 내부 실행 속도로 주장하지 않습니다.

0.1.0-eval.1의최종엔진으로100/1,000/5,000/50,000개를 연속·교대 숨김 각각 실행했습니다. 두 helper 모두 exit0이며8개 순수 모델+8개 실제 Excel 시나리오16 PASS/0 FAIL입니다. 교대50,000개는 구간 상한을 넘어 쓰기 전에 거절되는 것이 기대 결과입니다. 기존49개 기능 회귀와 별도 집계입니다.

Prepare는 대상 검사와 백업, Apply 합계는 재검증·쓰기·검증·Undo 기록·전역 상태 복원을 포함합니다. 아래 분할 값은 progress 시점의 근사 단계 시간이며 단일 측정입니다. fixture 제작과 사후 sentinel 표본 검사 시간은 표에서 제외하고 원본 로그에 남겼습니다.

| 항목 수·구간 | Prepare ms | Apply 합계 ms | 쓰기 전 재검증 ms | 쓰기 ms | 검증·기록·상태 복원 ms | 실제 쓰기 호출 | 결과 |
|---|---:|---:|---:|---:|---:|---:|---|
| 100·연속 | 1,040 | 1,145 | 262 | 119 | 764 | 1 | PASS |
| 1,000·연속 | 459 | 760 | 237 | 72 | 451 | 2 | PASS |
| 5,000·연속 | 422 | 490 | 147 | 192 | 151 | 10 | PASS |
| 50,000·연속 | 895 | 3,580 | 794 | 2,376 | 410 | 98 | PASS |
| 100·교대 숨김 | 3,569 | 6,762 | 3,413 | 2,595 | 754 | 100 | PASS |
| 1,000·교대 숨김 | 28,414 | 53,629 | 27,509 | 20,981 | 5,139 | 1,000 | PASS |
| 5,000·교대 숨김 | 139,752 | 264,950 | 137,717 | 103,039 | 24,194 | 5,000 | PASS |
| 50,000·교대 숨김 | 5,739 | — | — | 0 | — | 0 | VCP-SEGMENT-LIMIT로 사전 거절 PASS |

최종 근거는 m0/performance-final-contiguous.txt와 performance-final-alternating.txt 및 각각의 .command.json/.process.json입니다. 측정 DLL SHA-256은 f811d27d83ea44f6ab3fa5fba136a3056c268fc302a16ff4fb4a3189f259586e입니다. 이 시험 DLL은 실패 주입을 포함하는 외부 검증 전용 빌드이며 배포 DLL 해시와 구분합니다.

연속5,000/50,000개, 교대1,000/5,000개에서 확인 사유 플래그를 확인했습니다. 이 성능 harness에서는 실제 확인창을 클릭하지 않았습니다. 후속0.1.0 설치candidate01에서는10,000개교대가시대상의실제대량확인창취소·진행중취소/복구를별도로통과했습니다. 대상·숨김·선택 밖은 대표 sentinel 표본을 비교했으며 이 성능 시험을 시트 전체 보존 증명으로 확대하지 않습니다. 교대5,000개는 이 외부 harness에서 Prepare와 Apply 합계404,702ms가 걸렸습니다. 연속 구간 수에 따라 COM 호출 수가 달라지는 측정이며 설치된 추가 기능이나 다른 환경의 속도로 외삽하지 않습니다.

이전 performance-100-1000.txt, performance-optimized-contiguous.txt, performance-optimized-alternating.txt, performance-optimized-alternating-5000.txt는 최적화 전후 조사 이력으로 보존합니다. 위 최종 표에 이전 빌드 수치를 섞지 않았습니다. 별도 performance-model-boundaries.txt의10개 순수 모델은100/1,000/5,000/20,000/50,000의 연속·교대 구간과50,000교대 구간 한도 거절을 검사했고 Excel 호출이 없습니다.

50,000항목·200,000선택·32MiB·20,000구간은 설계 제한이며 모든 모양의 검증된 처리 속도가 아닙니다. 실제 진행창의쓰기중취소·복구는후속설치UI에서확인했습니다. 검사단계전용취소·모든환경의응답성까지보장하지는않습니다.

## 전체 필수 시험

| ID | 시험 | 기대 결과 | 결과 | 실제 범위·증거·남은 항목 |
|---|---|---|---|---|
| D01 | 세로 3개 → E2/E5/E8 | 순서대로 입력, 숨긴 행 보존 | PASS | F: E2/E5/E8 순서, 숨김·선택 밖 정의/값/서식 표본 비교. |
| D02 | 가로 3개 → 같은 대상 | 왼쪽→오른쪽 순서가 위→아래로 입력 | PASS | 실제 UI 가로 Ctrl+C의 1×3 순서 확인 + X 가로 타입 스냅샷을 세로 대상에 쓰기. 실제 메뉴 클릭은 미검증. |
| D03 | 단일 셀 → 단일 셀 | 정확히 1개만 입력 | PASS | F: 단일 Boolean 값 입력과 선택 밖 표본 비교. |
| D04 | 원본 3개, 대상 2개 | 0개 수정 | PASS | X의3→2거절·E1:E5무변경에 더해 설치된 표 메뉴에서복사3개/대상2개경고와E2/E3 원래101/102유지 확인. table-mismatch-ui.txt·table-mismatch-result.json. |
| D05 | 원본 2개, 대상 3개 | 0개 수정 | PASS | X: 2→3 거절 및 E1:E5 전후 무변경. |
| D06 | 원본 1개, 대상 3개 | 반복 채우지 않고 0개 수정 | PASS | F: 1→3 거절, 반복 채우기 없음. |
| D07 | 처음/가운데/끝 빈칸 | 위치·개수 보존, 대응 대상 내용만 비움 | PASS | 실제 Ctrl+C 가운데/끝 Empty + F 처음 Empty·줄바꿈·타입 쓰기, 위치 유지. |
| D08 | 연속 빈칸 및 전부 빈칸 | 구조가 확정되면 정확한 개수 처리 | PASS | 실제 UI복사3×1 Empty3 읽기 + 전부 빈칸3개 쓰기→Undo의 원래 수식/문자열/논리/혼합형식 복구. extended-blank-final.txt. |
| D09 | `00123`, 긴 식별번호 문자열 | 문자열과 앞자리 0 보존 | PASS | F: 문자열00123·긴 식별번호를 실제 Excel 쓰기 후 엔진 타입/값 검증. |
| D10 | 숫자 123 + 표시 형식 00000 | 값 123, 대상 서식 유지 | PASS | 실제 숫자85를00085로 표시한 원본을Ctrl+C 후 설치 메뉴로E2에 입력. 값85·대상0.0000형식을 유지하고E3:E8은102..107그대로. 숫자표시서식과문자열00123을구분. numeric-display-ui-paste.json. |
| D11 | 공백·한글·이모지·셀 내부 탭/개행 | 셀 경계를 잘못 나누지 않음 | PASS | 실제 한글/개행 복사 + F 공백·한글·이모지·탭/개행 리터럴 쓰기. |
| D12 | 중복 값 | 제거하거나 순서를 바꾸지 않음 | PASS | N 중복 문자열 보존, X 동일 숫자3개 실제 쓰기·검증. |
| D13 | 수식 결과 숫자/문자/논리/오류 | 결과 값만 입력, 수식 이식 없음 | PASS | 실제 수식 결과 Number2/String빈값/Boolean/Error2042 읽기 + F/X 타입별 실제 쓰기 검증. 실제 메뉴 통합 시험과 구분. |
| D14 | 문자열 `=1+1`, `+001`, `@abc` | 수식 실행·자동 변환 없음 | PASS | X: =1+1/+001/@abc 및1-2/1,234/12% 리터럴·HasFormula=false·원래 형식 검사. |
| D15 | 진짜 오류와 오류처럼 보이는 문자열 | 타입 구별 | PASS | F: Error2042와 String#N/A를 구분해 실제 쓰기·검증. |
| D16 | `=""` 결과 | 항목 수 보존, 저장 한계 보고 | PASS | 실제 ="" 복사 결과 String빈값, X 상수 저장 후 실제 Kind=String·HasFormula=false. 이 Office 빌드에 한정. |
| D17 | 날짜·시간·백분율, 다른 대상 서식 | 값 붙여넣기 계약대로 동작 | PASS | 실제1900/1904 Ctrl+C의 날짜45200·시간0.5·백분율0.125·날짜시간45500.75·빈칸과필터표본의원시숫자를독립디코더/제품파서로확인. 설치UI로45200/0.5/0.125를0.0000서식대상에입력·숨김보존·Undo원복. |
| D18 | 1900/1904 체계 차이 | 원시 값 정책과 한계 명시, 임의 보정 없음 | PASS | 1900/1904원본의같은raw숫자보존과59/60/61경계확인. 실제1900원본→1904대상UI붙여넣기에서45200/0.5/0.125를보정없이유지. date-capture/independent-date-review.json 및cross-date-system-ui-paste/undo.json. |
| D19 | 2×2 표 복사 | 펼쳐 넣지 않고 0개 수정 | PASS | 실제 A1:B2 UI Ctrl+C를 VCP-XML-SHAPE로 엔진 쓰기 전 거절. m0/native-2x2/probe-result.txt, XML1066bytes·sequence502 유지. N 순수 파서도 PASS. |
| D20 | 원본과 대상 일부 겹침 | 스냅샷 기준으로 안정 처리 | PASS | 실제 H1:J1 UI Ctrl+C85/90/78 후 원본I1과 겹치는 I1:I3에 불변 스냅샷 쓰기. H1/J1 보존·즉시Undo 원래 타입/형식 복구, m0/overlap-ui-copy.txt 3검사 PASS·sequence544 유지. |
| R01 | AutoFilter로 숨긴 행 | 숨긴 셀 상수/수식/서식 유지 | PASS | X AutoFilter로 제외한 상수/수식 정의/숫자형식/배경과 필터 상태 보존. F 선택 밖 추가 표본 비교. |
| R02 | 수동 숨김과 필터 혼합 | 둘 다 제외 | PASS | X 실제 AutoFilter와 수동 숨김을 혼합해 E2/E8만 쓰기. |
| R03 | 그룹 접기 | 숨긴 행 제외 | PASS | X Outline.Group/ShowLevels 접기 후 숨긴 행 제외. |
| R04 | 보이는 대상 0개 | 0개 수정 안내 | PASS | F 보이는 칸0개 사전 거절·전후 무변경. |
| R05 | 선택 범위가 화면 아래로 이어짐 | 뷰포트 밖 가시 셀도 처리 | PASS | X E1:E100 중 viewport 밖 E100까지 입력. |
| R06 | 전체 열/행 선택 | 빠른 거절, 자동 축소 없음 | PASS | F 전체 열·X 전체 행 사전 거절. UsedRange 축소 없음. |
| R07 | 직접 만든 다중 영역 선택 | 명확한 제외 안내 | PASS | F Union으로 직접 만든 다중 영역 사전 거절. |
| R08 | 단일 셀 SpecialCells 경계 | 선택 밖 셀 수정 없음 | PASS | F 단일 셀 SpecialCells 결과를 교차하여 선택 밖 표본 유지. X 선택 밖의 인접 검증 규칙은 단일 대상에 적용하지 않음. |
| R09 | 병합/보호/읽기 전용/Protected View | 쓰기 전 중단 | PASS | F/X 병합·시트보호 및 혼합병합 거절 + 실제읽기전용/PV수정회귀2PASS. PV는상태표시접근전 VCP-PROTECTED-VIEW,값/타입/형식/저장SHA유지. |
| R10 | spill/배열/피벗/그룹 시트 | 쓰기 전 중단 | PASS | F/X spill·배열·혼합거절과추가 실제PivotTable 및 그룹선택2시트에서 VCP-PIVOT/VCP-GROUPED 사전거절·셀/구조보존. |
| R11 | ListObject의 값 열 | 정상 지원, 표 구조 보존 | PASS | F 값만 있는 ListObject 데이터 열 쓰기.0.1.0 실제 표 우클릭 메뉴로E2:E4에85/90/78입력 성공·선택범위 유지(table-ui-paste.json). |
| R12 | 표 계산 열·혼합 수식 열 | 숨긴 행 자동 채우기 없이 중단 | PASS | X AutoFill 설정을 fixture 제작 중에만 저장/복원해 혼합 열을 확정, 숨긴 비선택 E8 수식을 탐지하여0개 수정. |
| R13 | 표 헤더·합계 행/검증 규칙 셀 | 쓰기 전 중단 | PASS | F 검증 규칙, X 표 헤더/합계 행 및 선택 일부에만 있는 가시 검증 규칙 사전 거절. 숨긴 E3에만 규칙이 있으면 가시 E2/E4 쓰기 허용·숨긴 값/규칙/형식 유지. |
| R14 | 서로 다른 통합문서 | 올바른 대상만 수정 | PASS | 서로 다른 합성 원본/대상 파일·프로세스 사이의 쓰기 cross-process.json.0.1.0은 실제1900 원본파일→1904 대상파일의 UI 붙여넣기/Undo도 PASS. |
| R15 | 서로 다른 Excel 프로세스 | 클립보드 입력 정상, 잘못된 인스턴스 참조 없음 | PASS | 실제 source PID14700/target PID25804, UI Ctrl+C 후 타입5개 실제 입력·대상형식/선택밖 표본 보존. |
| R16 | 원본도 필터된 복사 | 실제 복사 항목 순서·개수 유지 | PASS | sourcePID28896에서 실제 AutoFilter로90행 숨김 후 A2:A4 UI Ctrl+C. 실제 XML2×1 Number85/78, sequence434유지. clipboard-filtered.json. 이 Office 빌드 표본에 한정. |
| R17 | 그림·파일·웹 표·텍스트 클립보드 | 지원 밖 입력으로 0개 수정 | NOT RUN | 순수 plain text/HTML/PNG/CF_HDROP 유사 바이트 4종 거절 PASS. 실제 OS 합성 입력 helper는 컴파일했으나 Windows Access denied로 본문이 실행되지 않음. 클립보드 변경0이며 실행 거절의 원인은 미확정. non-excel-clipboard/execution-blocked.json 및 결과 로그. |
| R18 | 읽기 중 클립보드 교체/점유 | 제한된 재시도 또는 0개 수정 중단 | NOT RUN | 실제 HWND소유프로세스 점유에서 NativeClipboard 읽기/열거 BUSY126/121ms·메타데이터보존 PASS. 읽는도중새복사교체 통합시험은 미실행. |
| R19 | 잘라내기 입력 | 원본 제거 없이 거절/제한 판정 검증 | PASS | 실제 UI Ctrl+X에서 VCP-CLIPBOARD-CUT 거절, 원본 cut상태 보존·대상 생성/쓰기 없음. clipboard-cut.json. |
| R20 | 잘못된 HTML offset/거대 선언 차원 | 파서 예외 격리, 메모리 폭증·쓰기 없음 | PASS | N 거대 선언·확장 인덱스·역행·잘못된 구조 거절. HTML은 지원 입력이 아니며 파싱 경로 없음. |
| R21 | 외부 리소스 포함 XML/HTML | 외부 통신·실행 없음 | PASS | N DTD/외부 엔터티·스크립트 구조 거절. 네트워크/외부 리소스 로딩 경로 없음. |
| R22 | 선택 안/밖 우클릭 | 현재 실제 선택을 정확히 반영 | PASS | 실제 E2:E8 선택 후 바깥 F2 우클릭은 현재 선택 F2를 반영하여 3대1 불일치·0개 쓰기. 다시 선택 안 우클릭은 E2/E5/E8에85/90/78, 숨긴 4셀 보존. outside-rightclick-result.json, inside-rightclick-result.json 및 거절 UI. |
| U01 | 정상 붙여넣기 직후 되돌리기 | 값·수식·빈칸·서식 복구 | PASS | F 원래 값 복구 및 X 정렬 수정 후 정상 즉시 Undo 회귀 PASS. |
| U02 | 일반 수식 덮어쓰기 후 되돌리기 | 원래 수식 종류와 표현 보존 | PASS | F Formula2 =10+5 원래 속성/표현 복구. 추가 X 혼합 수식/문자열/빈칸·서식의 일괄 백업/복구 및 개별 fallback 검증. |
| U03 | 사용자 수정 후 되돌리기 | 덮어쓰지 않고 거절/무효화 | PASS | F 붙여넣기 뒤 사용자 역할 COM 편집42를 보존하고 Undo 거절. |
| U04 | 정렬/행 삽입·삭제/동일 값 행 이동 | 다른 행 복구 없이 거절/무효화 | PASS | 초기 동일 값 정렬 시험 FAIL 재현·수정 후 X 일반/표 정렬·기존 정렬 제한·행삭제 PASS, F 행삽입 PASS. 초기 실패를 아래에 보존. |
| U05 | 시트 이름 변경/시트 교체/파일 닫기 | 잘못된 객체로 복구하지 않음 | PASS | X 이름변경거절 + RemainingSafety 실제동일이름시트교체·같은파일닫기재열기,사후값이같아도Undo거절·객체내용/타입/형식/저장해시유지. |
| U06 | 동일 이름의 다른 파일 | 다른 파일 수정 없음 | PASS | RemainingSafety: 다른경로의동일파일명·시트명·주소·사후값으로교체해도Undo거절. 원래/새파일저장해시와새객체내용보존. |
| U07 | 다른 파일에서 되돌리기 클릭 | 뒤에서 이전 파일을 수정하지 않음 | PASS | X 다른 소유 통합문서가 활성일 때 거절, 원래/새 파일 내용 보존. |
| U08 | N번째 구간 쓰기에 오류 주입 | 이전 변경과 부분 쓰기 복구 확인 | PASS | F 두번째 쓰기 후 시험용 실패 주입, 전체 백업 복구와 정의/값/서식 표본 검증. |
| U09 | 복구에도 오류 주입 | 복구 미완료 명시, 성공 표시 없음 | PASS | F 복구0번째 셀 추가 실패 주입, 실패주소·RecoveryRequired·후속 쓰기 거절. |
| U10 | 확인 창 취소 | 0개 수정 | PASS | 설치 UI의7칸/내용비움3칸 합산 확인창에서 취소 클릭 후E2:E8의값101..107·0.0000형식이모두유지. 재실행확인뒤빈칸/날짜숫자쓰기·자체Undo원복도확인. blank-warning-ui.txt 및cancel/confirmed/undo.json. |
| U11 | 쓰기 중 취소 | 변경 복구 또는 미완료 명확 보고 | PASS | F 쓰기후취소주입·복구PASS. 설치candidate01의10,000가시칸실제진행창에서쓰기중취소, 복구중/완료안내와전체19,999셀777복원·전역상태원복·engine=rolled-back 확인. large-progress-cancel-result.json. |
| U12 | EnableEvents=False/Calculation=Manual 시작 | 종료 후 시작값 그대로 | PASS | F Events=False/Manual/ScreenUpdating=False/customStatus 시작값 정확 복구, 해당 상태 Undo 거절. |
| U13 | 다른 추가 기능의 후속 작업/Undo 변경 | 충돌 없이 기록 무효화 또는 안전 거절 | NOT RUN | X 후속 자동화의 다른 셀 편집을 감지하여 거절 PASS. 실제 다른 추가 기능/기본 Undo 변경 공존 미실행. |
| U14 | 반복 클릭·재진입 시도 | 중복 작업 없음 | NOT RUN | X 동일 엔진 재진입 Apply 거절 PASS. 실제 UI 반복 클릭·메시지루프 조합 미실행. |
| U15 | 숨긴 수식이 대상 값을 참조 | 수식 정의 유지, 정상 재계산은 허용 | PASS | F/X 숨긴 의존 수식의 정의 유지. 재계산 결과 변화는 정상으로 판정. |
| U16 | 다음 작업의 검증 실패 | 기존 유효 Undo를 불필요하게 훼손하지 않음 | PASS | F 다음 개수 검증 실패 뒤 이전 유효 Undo 동작. |
| U17 | Excel 기존 Undo 기록 영향 | 실제 영향을 측정하고 문서에 명시 | PASS | 실제Q2/Q3타이핑2회로 기본Undo 활성(True)을 만든 뒤 도구 붙여넣기 후False가됨을관찰. 기존기록보존을약속하지않고Ctrl+Z대신자체최근1회메뉴를안내. builtin-undo-before/after.json. |
| I01 | 일반 사용자 계정 설치 | 관리자 권한 요구 없음 | PASS | Medium 무결성(S-1-16-8192)·Administrators deny-only인 비승격 프로세스로 실제 설치 exit0. m3-execution-integrity.txt, m3-upgrade-custom.json, m3-default-install.txt. |
| I02 | 설치 후 정상 Excel 시작 | 수동 매크로 없이 메뉴 자동 등장 | PASS | 0.1.0 후보 정상Excel시작 후Connect=True,실제일반셀메뉴붙여넣기·Undo콜백성공. 사용자VBA수동실행없음. candidate-ui-paste/undo.json. |
| I03 | Excel 정상 재시작 2회 | 매번 자동 로드, 메뉴 중복 없음 | PASS | 후보03 기본 설치를 바꾸지 않고 정상 시작 PID28252와 PID18768에서 모두 자동 연결·자체 메뉴 각 1개 확인. m3-default-autoload.json, m3-default-second-autoload.json 및 각 메뉴 UI 기록. |
| I04 | 새 통합문서/다른 파일/표 셀 | 메뉴와 실행 경로 유지 | PASS | 정상 시작의 새 통합 문서1에서 실제 메뉴 확인(autoload-fixed-first-contextmenu.txt), 다른1900/1904파일의 메뉴 실행, 실제 표 셀 메뉴85/90/78쓰기. table-contextmenu-ui.txt·table-ui-paste.json. |
| I05 | 재설치/업그레이드 | 한 제품만 등록, 중복 메뉴 없음 | PASS | 기존 특수문자 경로 설치를 후보03으로 업그레이드 exit0. 정상 Excel PID24840에서 자동 연결, 자체 메뉴 각1개 확인. m3-upgrade-custom.json, m3-custom-autoload.json 및 m3-custom-autoload-menu.txt. |
| I06 | 다른 Excel 도구와 동시 설치 | 다른 메뉴·동작·등록 보존 | NOT RUN | 실제 설치·제거·재설치 후 SelectionExport 메뉴 유지 확인. 다른 제품 동작과 모든 등록의 공존 전체 시험은 미실행. |
| I07 | 실행 중 Excel이 있는 상태의 설치/제거 | 강제 종료·사용자 문서 손실 없음 | PASS | --install/--uninstall 모두 exit1 사전 중단, 제품 HKCU 두 view/PID목록 동일·대상 폴더 미생성. installer-tests/excel-running-refusal-evidence.json. |
| I08 | 정상 제거 후 Excel 시작 | 자체 메뉴/자동 로드/누락 경고 없음 | PASS | 후보03 제거 exit0·자체 HKCU 추가 기능 등록 제거 후 정상 시작. 자체 메뉴와 누락 파일 경고 없이 SelectionExport 메뉴 유지. m3-uninstall-custom.txt, m3-uninstalled-menu.txt. |
| I09 | 제거 재실행 | 안전한 멱등 동작 | PASS | 실제 제거 재실행 exit0, 확인된 설치가 없어 변경하지 않음. m3-uninstall-repeat.txt. |
| I10 | 공백·한글·작은따옴표 경로 | 설치·콜백·제거 정상 | PASS | 실제 ‘설치 경로's’에서 설치·자동 로드·메뉴 붙여넣기/Undo·후보03 업그레이드·제거 완료. 외부 합성 user-preserved-fixture.txt 보존. candidate-ui-paste/undo.json, m3-custom-autoload.json, m3-uninstall-preserved.json. |
| I11 | 매크로 차단/신뢰 미충족 | 차단 진단, 보안 설정 자동 완화 없음 | NOT RUN | 보안 완화 코드 없음 검토. 조직 차단 정책을 적용한 실제 설치 진단 미실행. |
| I12 | 사용자 VBA 수동 실행 0회 | 정상 설치·사용·제거 전 과정 만족 | PASS | 실제 설치→정상 시작→우클릭 붙여넣기/Undo→정상 종료→제거→재실행 전 과정에서 사용자 VBA 수동 실행0회. 컴파일된 COM 콜백 사용. |
| I13 | Office 32/64비트 | 실제 시험한 조합별 결과 구분 | NOT RUN | Excel x64 기능 시험만 실행. 32비트는 빌드와 실제 실행을 구분하며 실제 실행 미검증. |
| P01 | 100/1,000/5,000/50,000개 | 검사·쓰기·검증 시간과 환경 기록 | PASS | 최종 연속 범위4크기 actual COM 측정·검사/백업·재검증·쓰기·검증/복원 시간 기록. 외부 EXE 측정이며 설치된 추가 기능 속도와 다름. |
| P02 | 동일 수량, 연속/교대 숨김 | 구간 수별 성능·경고 확인 | PASS | 기록된외부COM연속/교대100·1,000·5,000·50,000행렬과경고플래그/한도거절PASS. 설치후10,000가시칸·10,000구간의실제대량확인창과취소19,999셀무변경확인. 성능숫자와설치UI시험을구분함. |
| P03 | 항목/선택/페이로드 상한 초과 | 과도한 작업 전 0개 수정 중단 | PASS | N50,001항목/200,001선택/32MiB초과/20,001구간 사전 거절. COM 대량 처리 성능과 구분. |
| P04 | 최대 허용 크기 직전/경계 | off-by-one 오류 없음 | PASS | 실제 선택199,999/200,000셀 허용·숨김 보존,200,001셀 거절. 별도 순수9개: 원본49,999/50,000/50,001, 구간19,999/20,000/20,001, 유효 XML33,554,431/432/433bytes의직전·정확허용/초과거절. 실제모든조합성능보장을뜻하지않음. |

F는 release-validation/final-regression/FunctionalTests.txt(19개), X는 같은폴더의ExtendedTests.txt(30개), 추가안전은RemainingSafetyTests.txt(10개), N은unit/results.txt(47개)입니다. 이전m0/run2/fixed/optimized 결과와PV최초실패도수정이력으로보존합니다. 실제클립보드/UI증거는m0와release-validation에구분합니다.

## 종료 관찰의 구분

설치 후보의 UI X 종료(PID24840·28252)와 이전 소유 시험 PID27888의 Close/Quit는 프로세스 종료를 확인했습니다. 반면 COM 검사 helper를 연결했던 두 번째 정상 시작 PID18768은 Close(false)/Quit 반환과 창 소멸 뒤에도 30초 넘게 프로세스가 남았습니다. 승인된 시험 프로세스 정리 범위에서 해당 PID만 강제 정리했으며 m3-second-shutdown-process.json에 기록했습니다. 추가 기능 자체와 외부 COM 참조의 원인은 분리하지 못했습니다. 이 실행을 자연 종료 PASS로 집계하지 않으며, UI 정상 종료가 항상 실패한다고도 단정하지 않습니다. 설치기 자체는 Excel을 강제 종료하지 않습니다.

## 남은 제한과 개인정보

Excel 32비트, 읽기 중 클립보드 교체, 실제 다른 추가 기능 공존 등 NOT RUN 행의 범위를 완료했다고 주장하지 않습니다. 날짜는 검증된 Biff12 숫자 보완 자료가 필요하며 모든 Office 형식을 지원하지 않습니다. 최근 Undo는 원래 선택·이벤트 감지·기본 Undo 비활성·정렬 설정 없음 등 보수적인 조건이 있습니다. 여러 COM 쓰기는 데이터베이스 트랜잭션이 아니며 프로세스 강제 종료·OS 장애·감지되지 않은 외부 동시 수정은 완전 복구 보장 밖입니다.

시험용 값만 로컬 증거로 저장했습니다. 실제 사용자 클립보드·업무파일·개인 설정·비밀키·진단 로그는 배포물과 공개 사이트에 넣지 않습니다. 조직별 서명·추가 기능 승인 조건은 미결정이며 설치기가 보안 정책을 낮추지 않습니다.
