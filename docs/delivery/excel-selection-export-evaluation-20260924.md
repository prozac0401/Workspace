# 선택범위 내보내기 0.1.0-rc.9 · 현재 PC 평가 검증 기록

실행: 2026-09-24 KST · 상태: rc.9 현재 PC 평가 결과 반영 완료 · 서명 없는 평가판 · 전체 인수 및 조직 배포 승인 미완료

적용 요구는 [원작업지시 전체](../tools/excel-selection-export/specification.md), 설계는 [ADR-0009](../design/0009-excel-selection-export-com.md), 개별 인수 판정은 [요구사항과 시험 대응표](../tools/excel-selection-export/acceptance.md)를 따른다. rc.7의 실제 우클릭 결과 자동 전면 표시와 정상 UI 종료, 정식 COM 콜백 API 11사례·930 assertions가 통과했다. rc.9는 출력 중 입력 차단과 상태 복원 실패 처리를 보완한 최종 후보이며, 빌드191회·x64 설치를 확인했다. rc.9도 외부 COM 연결 없는 실제 우클릭에서 결과 자동 전면 표시를 통과했다. rc.9 정식 COM 콜백 API11사례·930 assertions도 통과했으며 실제 진행 창 취소11 assertions도 통과했다. 직접 엔진 거절9사례·92 assertions가 통과했고 부분 병합1사례는 시험 조건을 만들지 못해 미실행이다.

**실행 취소 기록은 보존되지 않았다.** rc.9에서 원본 셀을 직접 편집한 뒤 활성화된 Undo가 실제 내보내기 후 비활성화되는 것을 관찰했다. 원본 값·수식·서식의 전후 동일 여부와는 별도 제한이다.

**API 시험 뒤 Excel의 자연 종료도 실패했다.** 합성 문서를 닫은 후에도 창 없는 시험 Excel이 수분간 남았다. 원인은 미확정이며, 외부 COM 연결 없는 실제 사용자 UI 종료 PASS와 구분한다. 소유권과 빈 상태를 확인한 이번 시험 프로세스만 별도로 종료했으며 이를 자연 종료 성공으로 처리하지 않는다.

## 제품과 시험 범위

독립 제품 ExcelSelectionExport를 C# .NET Framework COM 추가 기능과 현재 사용자 설치 EXE로 구현했다. Excel 시작 시 컴파일된 메뉴를 준비하고 실제 내보내기는 메뉴 클릭에서 시작한다. 명단대조기와 COM 식별자, 소스, 설치 경로, 메뉴 및 제거 항목을 분리했다.

현재 PC에서 최소 자동 로드 설치 시험 M1을 수행한 뒤 기능 구현과 패키징을 진행했다. 사용자는 현재 PC에서 가능한 시험을 계속하고 격리 환경·Windows 재로그인·재부팅 미실행을 기록하도록 허용했다. 현재 PC의 결과를 원명세의 격리 환경 배포 게이트까지 통과한 것으로 표시하지 않는다.

착수 때 존재한 다른 도구의 미커밋 파일4개는 기준 SHA-256과 최종 점검의 해시가 모두 일치했다. 다른 작업에서 사용하는 Excel과 문서는 보존했다. 시험 인스턴스에 외부 작업의 문서가 들어온 사례에서는 소유권 검사가 후속 시험을 거절했고 그 인스턴스를 닫지 않았다.

## 실행 환경과 빌드

| 항목 | 관찰값 |
|---|---|
| Windows | Windows11 x64, 빌드10.0.22631 |
| 사용자·설치 권한 | 현재 사용자 설치. 실제 설치 로그 User privileges None·Administrative install mode No |
| 실제 Excel | 설치형 Excel16.0, Build20326, x64. 업데이트 채널 미기록 |
| 런타임·컴파일러 | .NET Framework4.8.1 환경, C# 컴파일러4.8.9232.0. 제품 요구 런타임은 Framework4.8 이상 |
| 설치기 | 설치 로그 Inno Setup6.7.0. manifest의 설치기 버전0.0.0.0은 메타데이터 수집 제한 |
| 기반 소스 | 커밋89219d0f11c582fdb3649cb80527ee9c73defdd8 및 신규 제품 미커밋 변경. 소스별 SHA-256은 빌드 manifest에 기록 |
| 평가 패키지 | 0.1.0-rc.9 x86/x64 빌드·x64 현재 사용자 설치·완료된 실제 시험을 아래 구분. 전체 인수 미완료 |
| 완료된 기능/UI 증거 | 0.1.0-rc.9 정식 API11사례와 실제 우클릭·자동 전면 표시·정상 종료, Undo 손실 실측 |
| 어셈블리 | AssemblyVersion0.1.0.0, x86·x64 별도 EXE/DLL |
| 서명·조직 승인 | 서명 없음. 회사 정책의 설치 허용 및 배포 승인 미확정 |

사용자 VBA 코드 등록, Alt+F8/Alt+F11, VBS 실행, 매크로 허용, 추가 기능 수동 체크는 설치·정상 사용 단계에 없다. 시험에서도 이 조작으로 추가 기능을 활성화하지 않았다. 격리 프로필에서 VBA 접근 신뢰 off·문서 매크로 비허용 상태를 고정한 시험은 별도 미실행이다.

## 실제 결과

| 시험 | 판정 | 실행 결과와 범위 |
|---|---|---|
| rc.9 빌드·단위시험·설치 | PASS | x86/x64 각각 M1 19회·계획26회·엔진 보호40회와 설치 사전검사21회, 총191회 통과. 두 설치 EXE 생성, x64 설치 종료0. 네 통합 시험 도구 컴파일 종료0 |
| rc.9 실제 메뉴·결과 전면 표시 | PASS | 정상 시작 후 외부 NativeOM/COM 연결 없이 실제 우클릭. 합성 A1:B2의4개 값 결과와 후속 단일 셀 결과가 각각 자동 전면 표시 |
| rc.9 원본 실행 취소 기록 | 보존 FAIL | 직접 원본 편집 뒤 Undo 활성, 실제 내보내기 후 원본으로 돌아왔을 때 Undo 비활성. 측정·공개 완료 |
| rc.9 실제 UI 종료 | PASS | 전체 시험 동안 외부 COM 미접속. 결과와 원본을 저장하지 않고 정상 UI로 닫은 뒤 시험 소유 Excel 종료, 다른 작업 인스턴스 유지 |
| rc.9 최종 정상 재시작 | PASS | 잔존 시험 프로세스 정리 뒤 새 Excel을 정상 시작. 외부 COM 없이 중복 없는 실제 우클릭 메뉴·자동 결과 없음 확인, Escape·Alt+F4 뒤 정상 종료. 내보내기 엔진 재시험은 아님 |
| rc.9 API 시험 뒤 자연 종료 | FAIL | ExcelProbe close 종료0으로 합성 원본을 닫은 뒤에도 창 없는 Excel이 수분간 남음. 원인 미확정. 아래 소유 프로세스 정리는 자연 종료 통과가 아님 |
| rc.9 정식 COM 콜백 API | PASS | rc.7과 동일한11사례930 assertions 완료, 성공·새 저장 전 결과 활성화·원본/전역 상태 대조 포함 |
| rc.9 산출물·원본 변경 보존 | PASS | EXE2개·manifest 소스13개·설치 DLL·착수4개 기존 파일 해시 일치, git diff --check 종료0 |
| rc.9 오프라인 안내 | PASS | 실제 설치된 README·CHANGELOG를 읽기 전용 SHA-256으로 비교해 저장소 파일과 각각 일치 |
| rc.9 실제 진행 창 취소 | PASS | 설치된 콜백 API에서20,000셀 처리 중 실제 취소 클릭. canceled·busy false, 원본 XML1,414,000자·Saved·원래 통합문서 객체·전역 상태 동일, 결과 없음, 원본 활성 등11 assertions 통과 |
| rc.9 취소 경로 클립보드 | PASS | 읽기 전용 GetClipboardSequenceNumber가 전후130으로 동일. 클립보드 내용을 읽거나 교체하지 않음. 다른 경로 일반화 안 함 |
| rc.9 취소 뒤 정상 재실행·클립보드 | PASS | 같은 설치 콜백의 한 셀 내보내기29 assertions 통과. 정상 출력 전후 클립보드 sequence130 동일, 내용 접근·교체 없음 |
| rc.9 직접 엔진 거절 | PARTIAL | 실행9사례92 assertions 통과, 부분 병합1사례 NOT_RUN. 숨김 절단 병합·Ctrl 다중 범위·전체 행/열·다중 시트·보이는 행0·입력1,001,000·가시100,172·문자열10,026,702자 초과를 의도한 사유로 거절. 원본·선택·전역 상태·통합문서 보존 |
| rc.8 빌드·설치 무결성 | PASS | 총183회 단위시험, x64 설치 종료0. 소스13개 해시와 설치 DLL의 패키지 DLL 일치 확인. 최종 기능 인수와 구분 |
| rc.7 빌드·현재 사용자 설치 | PASS | 총175회 단위시험, x86/x64 EXE 해시 재대조 일치, x64 설치 종료0 |
| rc.7 실제 우클릭·결과 전면 표시 | PASS | 외부 NativeOM/COM 검사 도구 연결 없이 실제 메뉴 클릭. 저장 전 단일 시트의 A1:B2 합성값4개가 있는 결과 창이 자동으로 전면에 표시됨. 시험 도구나 사람이 대신 활성화하지 않음 |
| rc.7 실제 UI 출력 후 종료 | PASS | 결과에서 Alt+F4·저장 안 함, 원본에서 Alt+F4 후 시험 소유 Excel 프로세스 종료. 다른 작업의 Excel 유지 |
| rc.7 정식 COM 콜백 API | PASS | structure·types·dates1900·dates1904·singlecell·formatting·mergefull·dynamicarray·table·conditionalformat·manualcached, 11사례930 assertions 통과. 완료 성공·저장 전 새 결과 활성화·원본/전역 상태 대조 포함 |
| rc.7 수동 계산 캐시 | PASS | 계산대기 상태2에서 입력3, 보유 수식 결과2를 준비. 결과2를 내보내고 원본 캐시·계산 모드 유지. 시험 종료 뒤 시험이 바꾼 계산 모드 복원 |
| rc.7 균일 글꼴·첨자 | PASS | 기본/표시 글꼴명이 구체적인 맑은 고딕 fixture에서 기본 서식·전체 셀 위/아래 첨자·행열 크기 비교 통과. 혼합 글꼴 지원을 의미하지 않음 |
| M1 현재 PC 최초 설치·메뉴 | PASS | 설치 EXE만으로 비관리자 설치와 COM 활성화. 정상 Excel 시작 후 실제 우클릭 메뉴의 컴파일된 M1 콜백을 실행하고 A1:B2 선택 유지 |
| M1 시작 시 자동 내보내기 없음 | PARTIAL | 클릭 전 Workbooks=1·clicks=0. 모든 파일 열기·선택 변경 조합은 미실행 |
| M1 재시작·두 프로세스 자동 로드 | PARTIAL | 서로 다른 새 Excel 프로세스에서 connected/ribbon true·clicks0. 두 프로세스 동시 실제 내보내기는 미실행 |
| 실행 중 같은 버전 설치·제거 차단 | PASS | M1에서 Excel 실행 중 E20 안내로 차단. 강제 종료 없음. 정상 제거 완료를 뜻하지 않음 |
| 버전별 경로 업데이트 | PARTIAL | 신규 버전 경로 설치 확인. 기존 프로세스는 로드한 DLL을 유지하고 새 프로세스부터 새 버전 사용. 전체 업데이트·제거 수명주기 미완료 |
| rc.4 직접 엔진 사전 거절 | PARTIAL | 숨김 절단 병합·Ctrl 다중 범위·전체 행·전체 열·다중 시트·보이는 행0·입력 초과·가시 셀 초과8사례 통과. 부분 병합·문자열 초과 준비 실패는 아래 별도 기록 |
| rc.4 설치 후 안전 대조 | PASS | 설치 후 기준과 후속 읽기 전용 검사 사이 보안·정책·다른 추가 기능 등록·기존 제품 파일 동일. 설치 전후 증거는 아님 |
| rc.5 설치 전후 안전 대조 | FAIL | 33범위 중29개 동일, HKCU Excel Options·Resiliency 양쪽 보기4개 변경. 전체 Compare FAIL 유지. 보안·정책·다른 추가 기능 등록·기존 제품 파일은 동일. 원인은 미확정 |
| 원작업지시·기존 변경 보존 | PASS | 원문 사본과 착수4개 미커밋 파일의 SHA-256 일치 |

COM 콜백 API 시험은 실제 설치된 추가 기능의 콜백을 API로 호출한다. 직접 엔진 시험은 명시한 DLL의 엔진을 호출하며 메뉴·등록·자동 로드 검증이 아니다. rc.6 데이터 진단은 활성화 판정을 제외한 별도 검사였으며, 정식 rc.7 API와 구분한다. 실제 사용자 우클릭은 외부 COM 연결 없이 별도 기록했다. 취소 시험은 API로 콜백을 시작하고 사람이 실제 진행 창의 취소를 누르는 혼합 방식이다. 읽기 단계4725/20000에서 클릭했으며 callback25ms·전체18,189ms는 클릭 전 사람의 대기 시간을 포함하므로 취소 응답 지연 실측으로 표시하지 않는다.

단위시험은 메뉴 계약·독립 ID·COM 인터페이스, 가시 좌표와 제한, 계산 상태, 작은 읽기·쓰기·검증 블록, 전역 상태 복원·재시도·출력 중 UI 차단 등을 검사한다. 실제 Excel 데이터·서식·UI 시험을 대체하지 않는다.

## 실패 이력과 수정 범위

rc.2 계열의 직접 엔진 검사에서 동적 helper 호출의 RuntimeBinder 오류를 확인해 정적 클래스 호출로 수정했다. UI 상태 복원과 결과 활성화 순서를 보완한 rc.3 단일 셀 직접 엔진 시험은27 assertions가 통과했지만 실제 메뉴 증거는 아니다. 초기 API 도구의 null control 인자도 IDispatch 요구와 맞지 않아 콜백 진입 전에 실패했으며 도구 인자를 수정했다.

rc.3 구조 시험에서는 한국어 숫자 표시 형식과 혼합 Hidden 값의 일괄 판단 때문에18행 대신100행이 출력되는 오류를 확인했다. 이는 단순 UsedRange 서식 확장이 아닌 실제 데이터 오류였다. 로컬 숫자 형식과 각 행의 Hidden 확인으로 수정했고 rc.4 및 rc.7 구조 시험이 통과했다.

rc.4 실제 우클릭은 값을 생성했지만 원본이 전면에 남아 UI 흐름이 실패했다. 메뉴 반환 뒤 엔진·표시 처리를 예약하고, rc.7에서 새 Excel 창 생성 직전에 원래 UI 상태를 복원해 실제 자동 전면 표시를 통과했다. rc.8은 창 생성 직후 출력 작성 중 Interactive·ScreenUpdating을 다시 차단한다. rc.9는 전역 상태 복원이 끝나지 않으면 성공 보고·결과 활성화로 진행하지 않고 실패 처리와 정리 재시도를 수행하도록 보완했다. rc.8/rc.9 변경의 단위시험과 최종 실제 시험은 구분한다.

rc.6 formatting의 Arial+한글 문자열은 Excel의 기본 Font.Name과 DisplayFormat.Font.Name이 모두 DBNull이었다. 자동 대체 글꼴로 혼합 글꼴 상태가 된 셀은 현재 정책에 따라 거절되며 이 제한을 해소했다고 표시하지 않는다. 양성 fixture를 실제로 균일한 맑은 고딕으로 준비하고 기본/표시 글꼴 사전조건을 확인한 rc.7에서 서식·전체 셀 첨자가 통과했다. 셀 안의 부분 글꼴·부분 첨자 같은 혼합 서식과 그라데이션은 지원하지 않으며 명시적으로 거절한다.

초기 외부 COM 검사 뒤 백그라운드 Excel이 남아 도구의 참조 해제·GC 경계를 보완했다. 그러나 rc.9 API 시험의 최종 ExcelProbe close가 종료0을 반환하고 합성 문서를 닫은 뒤에도, 창이 없는 동일 Excel 프로세스가 수분간 남았다. 제품·검사 도구·외부 COM 참조 중 어느 원인인지 미확정이므로 API 경로의 자연 종료는 FAIL로 기록한다. 외부 COM 연결 없는 rc.1·rc.4·rc.7·rc.9 정상 UI 종료 PASS는 별도 증거다.

잔존 프로세스 정리 때는 이번 시험의 PID 표식·시작 시각·Excel 실행 파일 경로 일치와 표시 창 없음을 확인했다. 해당 빈 시험 프로세스만 종료했고 다른 작업의 Excel은 대상으로 삼지 않았다. 정리 도구 종료0은 자연 종료 성공을 의미하지 않는다. 이 정리용 도구와 상세 식별자는 로컬 artifacts에만 보관하며 제품이나 사용자 설치 절차에 포함하지 않는다.

rc.4 partialmerge는 Excel이 부분 선택을 병합 전체로 자동 확대해 NOT_RUN_CASE다. stringlimit은 엔진 호출 전 SourceSnapshot의 COM 오류로 실패했다. 동시 외부 자동화가 있었고 정확한 원인은 미확정이다. 장문값 분할 읽기·수식 상태 검사로 도구를 보완했으며 해당 rc.4 실패 이력은 유지한다. 최종 rc.9에서 문자열10,026,702자 초과 거절과 원본·전역 상태 대조가 통과했다. 이 사례의51,111ms는 합성 준비와 snapshot을 포함하므로 엔진 단독 성능값이 아니다. 외부 작업 문서가 시험 인스턴스에 들어온 후 재시도는 소유권 검사에서 중단했고 해당 인스턴스의 문서를 모두 보존했다.

rc.4 안전 대조 기준은 설치 완료 후 취득했다. 설치 전 snapshot 시도는 도구 오류로 실패했으므로 유효한 설치 전 기준이 아니다. rc.5는 유효한 설치 전후 기준으로 비교했으나 Options·Resiliency4범위가 달라 전체 FAIL이다. 동시간대 다른 Excel 작업 또는 설치 중 어느 동작이 원인인지 특정하지 못했다. 보안·정책·상대 제품의 개별 동일 결과를 전체 성공으로 확대하지 않는다.

초기 로그 이름의 closed-excel과 관계없이 당시 Excel이 남아 E20으로 차단된 제거·업데이트는 정상 제거 통과가 아니다. rc.9 최종 전체 수명주기 사전검사도 실행 중 Excel을 감지해 설치·제거 행동 전에 종료1로 거절했다.

## 미실행·미완료 항목

| 항목 | 상태와 영향 |
|---|---|
| 전체 인수 | rc.9 현재 PC의 명시 시험은 완료. 아래 미실행 조건과 보존 실패가 남아 원명세 전체 인수 미완료 |
| 외부 참조·매크로·외부 연결 보유 원본 | 해당 합성 조건 미실행. 완료된 출력에서 수식·연결·VBA 없음 검사는 수행했으나 보유 원본 배제의 전체 조건과 구분 |
| 조건부 서식 추가 조건 | 글자색·굵기·배경 통과. 조건부 테두리·숫자 형식, 아이콘·데이터막대 안내/취소는 미실행 |
| 실패·취소·상한·응답성 | rc.9 읽기 단계 실제 취소·거절9사례 완료. 부분 병합·정확 상한 성공·대량 경고·실제 오류 안내창·출력 후 실패·각 단계 취소·재진입·계산 중 상태·취소 지연 정량 시험 미완료 |
| 실행 취소 기록 | rc.9 실제 측정에서 기존 편집 Undo 손실 관찰. 보존을 보장하지 않음 |
| API 경로 자연 종료 | rc.9 합성 문서를 닫은 뒤 창 없는 Excel 잔존으로 FAIL·원인 미확정. 소유권 검증 후 해당 빈 시험 프로세스만 정리. 순수 UI 종료 PASS로 덮어쓰지 않음 |
| 클립보드 | rc.9 취소 및 정상 한 셀 출력 전후 각각 sequence 동일. 해당 실행 범위의 증거이며 모든 외부 자동화 조합을 의미하지 않음 |
| 혼합 글꼴·부분 서식 | 지원하지 않음. Arial+한글 자동 대체도 혼합 상태가 될 수 있으며 명시 거절 |
| Excel x86 실행 | x86 빌드·단위시험만 수행. x86 Office 설치·메뉴·출력 미실행 |
| 격리 환경·Windows 새 세션 | 깨끗한 프로필/VM·재로그인·재부팅 미실행. 사용자 후속 허용에 따라 명시 |
| 전체 제거·제거 후 메뉴·등록 | 미실행. 실행 중 다른 작업 Excel을 보존해 수명주기 사전검사가 거절 |
| 명단대조기·File List 전체 공존 | 독립 메뉴 동시 표시는 관찰. 동시 사용·양쪽 업데이트·각 제품 제거 전체 시험 미실행 |
| 설치 실패 복구 | 실제 중단·파일 잠금·등록 실패 주입과 복구 미실행 |
| 조직 정책·서명·런타임 누락 | 환경별 실제 시험 미실행. 보안 완화나 정책 우회 없이 조직의 허용 확인 필요 |

## 추가·작성 파일

이번 제품의 소스·설치기·시험·안내·검증 문서는 아래 독립 경로에 추가했다. 착수 시 존재한 다른 제품의 미커밋4파일은 수정하지 않았고 최종 해시 일치를 확인했다. 생성 EXE·DLL·로그·일회성 진단 도구는 artifacts 아래 로컬 산출물이며 제품 소스 목록과 구분한다.

| 구분 | 파일 |
|---|---|
| 메뉴·내보내기 엔진 | [src/](../../tools/ExcelSelectionExport/src/): AddIn.cs, ExportEngine.cs, VisibleRangePlan.cs |
| 설치·등록·사전검사 | [installer/](../../tools/ExcelSelectionExport/installer/): SelectionExport.iss, SetupProbe.cs |
| 재현 빌드·시험 도구 컴파일 | [scripts/](../../tools/ExcelSelectionExport/scripts/): build.ps1, Build-IntegrationTests.ps1 |
| 단위시험4개 | [tests/](../../tools/ExcelSelectionExport/tests/): M1Tests.cs, EngineTests.cs, EngineGuardTests.cs, SetupProbeTests.cs |
| 실제 Excel 시험 도구4개 | tests/: ExcelProbe.cs, FunctionalTests.cs, EngineFailureTests.cs, CancellationTests.cs |
| 설치 수명주기 시험 | tests/Test-Package.ps1 |
| 제품·개발 안내 | [README.md](../../tools/ExcelSelectionExport/README.md), [CHANGELOG.md](../../tools/ExcelSelectionExport/CHANGELOG.md), [DEVELOPMENT.md](../../tools/ExcelSelectionExport/DEVELOPMENT.md) |
| 요구·설계·인수·평가 | [specification.md](../tools/excel-selection-export/specification.md), [acceptance.md](../tools/excel-selection-export/acceptance.md), [ADR-0009](../design/0009-excel-selection-export-com.md), 이 평가 기록 |

## 산출물과 근거 위치

최종 후보 EXE는 로컬 artifacts/selection-export/0.1.0-rc.9에 있다. 아래 해시는 빌드 결과이며 전체 실제 인수 승인과 구분한다. 원시 설치 로그·프로세스·환경 진단은 로컬 artifacts에만 두고 공개 사이트에 넣지 않는다.

| 설치 EXE | SHA-256 |
|---|---|
| ExcelSelectionExport-0.1.0-rc.9-x64-Setup.exe | f4a26afcdae580e486236070cd458d32f5fa3a8bc5f972ceadf7a45a6ac5baa7 |
| ExcelSelectionExport-0.1.0-rc.9-x86-Setup.exe | 46cb481f7c52a0a685ca7973135baa0e1a68706156a9f9bc7e73d2d5fbb26869 |

| 근거 | 로컬 위치 (artifacts/selection-export/ 기준) |
|---|---|
| 최종 후보 빌드·해시·단위시험 | 0.1.0-rc.9/build-manifest.json, SHA256SUMS.txt, x86·x64의 m1-tests.log·engine-tests.log·engine-guard-tests.log, probe-tests.log |
| 현재 사용자 설치 | rc9-install-result.txt, rc9-install.log 및 이전 버전별 설치 로그 |
| rc.9 정식 API·실제 UI·Undo | functional/rc9-positive.txt, functional/rc9-ui-observation.txt, functional/rc9-undo-observation.txt |
| rc.9 실제 취소·클립보드 관찰 | functional/rc9-cancellation.txt, rc9-cancel-ui-observation.txt, rc9-clipboard-success.txt, rc9-clipboard-observation.json |
| rc.9 최종 정상 재시작 | functional/rc9-final-restart-observation.txt |
| rc.9 API 잔존 정리 | functional/rc9-api-residual-cleanup.txt. 정리 성공은 자연 종료 통과가 아님 |
| rc.9 직접 엔진 거절9·미실행1 | functional/rc9-negative.txt |
| rc.9 최종 읽기 전용 무결성 대조 | rc9-final-readonly-verification.json |
| rc.7 정식 API·실제 UI | functional/rc7-positive.txt, functional/rc7-ui-observation.txt |
| rc.8 소스·설치 DLL 대조 | rc8-source-verification.json |
| 최초 자동 로드·재시작·실제 클릭 | m1/first-start-result.txt, restart-result.txt, ui-callback-observation.txt, M1-second-process.xlsx.inspect.txt |
| 초기 정상 UI 종료 | m1/normal-ui-shutdown-result.txt |
| rc.4 데이터·UI·거절·외부 간섭 | functional/rc4-positive.txt, rc4-date-isolated.txt, rc4-ui-observation.txt, rc4-negative.txt, rc4-external-interference.txt |
| rc.6 데이터 진단·혼합 글꼴 확인 | functional/rc6-data-diagnostic.txt, rc6-format-fields.txt, rc6-format-fields-direct.txt |
| 설치 후 안전 대조 | rc4-afterinstall-readonly-smoke3-baseline/safety-snapshot.json, rc4-afterinstall-readonly-smoke3-compare/checks.json |
| 설치 전후 안전 대조·수명주기 사전검사 | rc5-before/safety-snapshot.json, rc5-after/checks.json, rc5-safety-summary.json, rc5-lifecycle-preflight.txt, rc9-lifecycle-preflight.txt |
| 기존4개 변경 보존 | preexisting-final-check.json |
| 실행 중 설치·제거 차단 | m1/update-running-excel.log, uninstall-running-excel.log |
| 초기 helper·활성화 수정 이력 | functional/rc3-direct-singlecell.txt, rc3-direct-singlecell-fixed.txt, rc3-direct-singlecell-restored.txt |

## 문서 검증과 배포 상태

원작업지시 사본 SHA-256은87c72ee1abd991a42b19c7e833419d0b6ef7dce16bd0b99740239bee66c4854b다. 요구사항·설계·사용 안내·검증 기록을 별도 문서로 유지한다. 새 개발문서는 기존 기본 제외 정책을 따르며 공개 허용 목록·탐색 메뉴를 변경하지 않았다.

rc.9 평가 단계에서 저장소 문서용 Python의 mkdocs build --strict가 종료0(4.03초), scripts/check-site.py가 통과했다. 공개16페이지와404, 검색·사이트맵 공개 범위, 비공개 소스 제외 및 생성 링크를 확인했다. 최종 평가·인수·개발 안내3개의 상대 링크도 깨진 링크0개였다. 최신 로그는 artifacts/selection-export의 rc9-docs-build.txt·rc9-docs-links.txt, 이전 로그는 artifacts/excel-selection-export-docs에 보관한다. 문서 검증은 제품 인수를 대체하지 않는다.

이 산출물은 서명 없는 평가판이다. 전체 인수·조직 배포 승인·상용 승인·공개 릴리스·사이트 게시 완료를 의미하지 않는다.
