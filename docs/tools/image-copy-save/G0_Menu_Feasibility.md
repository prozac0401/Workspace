# 그림 복사·저장 · G0 메뉴 구현성 검증

도구 ID: ImageCopySave
기록 버전: 0.12 · 2026-09-27 후속 중간 실기
기준: [ImageCopySave-REQ-1.2](ImageCopySave_Requirements_v1.2.md)
기록 상태: 클래식 직접 표시 일부·MSI 시나리오·설정 복원 PASS, 기본 메뉴 경로 미확인·응답 없음 원인 미확정, 전체 G0 **미완료**
책임: 도구 개발·검증 담당
적용 정책: [추가 도구 개발 기준](../../policies/tools.md), [정책 문서 작성 규칙](../../policies/documentation.md)
현재 결정: [ADR-0023](../../design/0023-image-copy-save-classic-menu.md), 설치 권한 [ADR-0022](../../design/0022-image-admin-install.md)

## 현재 판정 — v1.2 공통 클래식 메뉴

사용자가 Windows 11 기본 메뉴의 ‘더 많은 옵션 표시’ 뒤에 나오는 공통 클래식 메뉴를 현재 경로로 선택했다. Windows 10 스타일의 클래식 직접 표시 설정에서는 같은 명령에 바로 접근한다. 이번 시험의 메뉴 모드 임시 전환과 원상복구도 승인했다. 이전 첫 Windows 11 메뉴 필수 조건과 클래식 전용이면 불합격이라는 판정은 v1.2에서 대체됐다.

새 후보는 native IExplorerCommand를 HKLM의 ExplorerCommandHandler와 x64 COM으로 등록하고 무서명 관리자 MSI가 제품 파일과 등록을 관리하는 방식이다. Windows 11 클래식 직접 표시 모드에서 독립 저장 명령과 실제 저장·복사, 여러 비이미지 상태의 완전 숨김을 확인했다. 제품 MSI 0.1.0 설치·손상 DLL Repair, 0.1.0→0.1.1 업데이트, 제거·깨끗한 상태의 의도된 설치 실패 롤백·0.1.1 재설치는 확인한 시나리오에서 PASS다. 실제 설치 helper의 비상승 실행은 앞선 0.1.0 실제 저장에서 확인했다. 현재 0.1.1 설치 상태이며 클래식 직접 표시 메뉴의 실제 저장·PNG 이미지 복사도 별도 확인했다. 시험 폴더 A에 8×8 PNG가 생성됐고 저장 전후 clipboard sequence 1442가 유지됐다. 복사 시 1442→1447로 갱신되며 PNG·CF_DIBV5·CF_BITMAP·CF_DIB가 게시됐고 파일 목록 형식은 없었다.

**전체 G0는 미완료다.** 기본 새 메뉴의 ‘더 많은 옵션 표시’ 경로, 미확인 기능의 대표 사례, 호출 문맥·회귀 전체와 보존 범위·원상복구는 아래 개별 상태로 관리한다. 클래식 직접 표시 전환 15회·46개 관찰 행은 모두 PASS다. 1~8회는 0.1.0, 9~15회는 0.1.1이며 같은 버전에서 전부 수행한 것으로 합치지 않는다. 02:53 UTC의 새 시험 Explorer 창에서는 기존 창 활성화 실패 이후 다시 관찰할 수 있었고 그 시점에는 기존 창과 프로세스를 보존했다. 후속 모드 시험에서는 승인된 수동 Explorer 재시작 한 차례와 Workspace 경로 복원이 있었다. 재시작 후 실제 ‘응답 없음’도 관찰했으므로 기존 활성화 실패까지 자동화 도구만의 원인으로 단정하지 않는다. 이전 관리자·SYSTEM sparse identity 등록이나 엔진 시험의 PASS로 빈 항목을 채우지 않는다. 이전 일반 사용자 등록의 0x80073D2B와 signed full MSIX의 0x800B0109도 새 경로의 현재 실패가 아니다.

사용자의 “불필요한 반복테스트는 지양하도록 합니다.” 지시에 따라 고정 20회 반복은 완료 관문에서 제외했다. 미확인 기능은 대표 1회 확인하며 실패나 관련 변경이 있을 때만 해당 사례를 다시 시험한다. 이미 수행한 관찰은 보존하고 16~20회와 다른 모드의 횟수 채우기 반복은 **사용자 지시에 따라 반복 생략**으로 기록한다. 생략한 반복은 제품 실패나 필수 잔여가 아니다. 기본 Windows 11 경로와 설정 원상복구는 필수로 유지한다.

## 현재 메뉴·설치 검증 매트릭스

| 항목 | Windows 11 기본 새 메뉴 → 더 많은 옵션 표시 | Windows 11 클래식 직접 표시: 버전별 실기 | 관련 기준 |
|---|---|---|---|
| 실제 폴더 배경 독립 저장 명령 | NOT RUN | PASS: 합성 8×8 이미지에서 독립 명령 활성화 | AT-08·09 |
| 지원 이미지에서 표시, 텍스트·빈 상태·URL/HTML·파일 목록에서 완전 숨김 | NOT RUN | 이미지·이미지+텍스트 표시, 텍스트·빈 상태·URL/HTML·실제 파일 클립보드 완전 숨김 PASS | AT-01~06 |
| 상태 변경 후 다시 연 메뉴의 대표 표시·숨김 확인 | 대표 상태 확인 NOT RUN. 고정 횟수 반복은 사용자 지시에 따라 생략 | 15회·46행 모두 PASS: 0.1.0에서 1~8회, 0.1.1에서 9~15회. 16~20회는 사용자 지시에 따라 반복 생략 | AT-07: 정량 완료 관문 제외 |
| 회색 항목·빈 상위 메뉴·중복·불필요한 구분선 부재 | NOT RUN | 위 비이미지 상태에서 저장 항목 자체 없음 확인. 모든 선택·상태의 메뉴 잔재 검사는 NOT RUN | MNU-05 |
| 메뉴 열기만으로 이미지 디코딩·파일 생성·클립보드 변경 없음 | NOT RUN | URL·HTML·이미지+텍스트·실제 파일 클립보드 메뉴 열기 전후 sequence·파일 목록 불변 PASS. 디코딩 부재의 실행 계측과 전체 상태는 NOT RUN | AT-10 |
| 지원 이미지 한 개 복사, 다중·혼합·폴더·비지원 파일 숨김 | NOT RUN | PNG 한 개 복사 명령 표시·실제 복사 PASS(0.1.1 재확인), PNG 두 개와 TXT 선택에서 명령 없음 PASS. JPEG/BMP·혼합·폴더 선택 등은 NOT RUN | AT-11·12 |
| 호출 폴더·창·탭 보존, 실제 복사·저장·비모달 피드백 | NOT RUN | 0.1.1에서 시험 폴더 A의 8×8 PNG 실제 저장·클립보드 sequence 불변과 선택 PNG 실제 이미지 복사 PASS. 복수 창·탭과 피드백·취소 전체는 NOT RUN | AT-13·16~18·33 |
| 기존 기본 연결·다른 메뉴·복사/붙여넣기 유지 | NOT RUN | PNG 메뉴의 기존 Open 기본 항목 유지, 실제 파일 복사 후 일반 Paste 활성화 관찰. 기본 연결·타사 메뉴·복사/붙여넣기 전체 회귀는 NOT RUN | AT-44 |

| 제품·정리 항목 | 현재 상태 | 판정 경계 |
|---|---|---|
| 무서명 자체 포함 관리자 MSI 0.1.0 설치 | PASS | 실제 관리자 실행, exit 0, 재부팅 요구·Explorer 재시작 없음 |
| 손상 파일 Repair | PASS | 시험으로 제거한 ImageCopySave.Engine.dll 복구, exit 0, 재부팅 요구·Explorer 재시작 없음. 업데이트 실패 롤백과 구분 |
| 0.1.0→0.1.1 업데이트 | PASS | 실제 관리자 실행·exit 0, 재부팅 요구·Explorer 재시작 없음. 최초 UAC 취소와 별도 실제 실행 |
| 0.1.1 제거 | PASS | exit 0, 설치 여부 false·제품 등록 0개, 합성 보존 PNG 해시 불변 |
| 의도된 설치 실패 롤백 | PASS: 깨끗한 상태의 실패 주입 | 시험 전용 0.1.2 MSI의 예상 exit 1603 뒤 설치 여부 false·제품 등록 0개. 기존 버전이 남아야 하는 업데이트 실패 롤백과는 다른 시나리오 |
| 제거·롤백 후 0.1.1 재설치 | PASS | exit 0, 설치 여부 true·제품 등록 7개. 현재 메뉴 검증용으로 설치 유지 |
| 설치 단계의 재부팅·Explorer 재시작 | 없음 | 설치·Repair·업데이트·제거·실패 롤백·재설치 모두 rebootRequired=false, explorerRestarted=false |
| 일반 사용자 Explorer/helper 실행 | PASS: 0.1.0의 관찰한 실제 저장 실행 | 같은 현재 세션에서 실제 설치 helper와 Explorer의 TokenElevation=false 확인. 관리자 설치와 구분 |
| 사용자 PNG·원본·알 수 없는 외부 파일·타사 등록 보존 | 설치·Repair·업데이트·제거·실패 롤백·재설치의 합성 보존 PNG, MSI 전체 절차 후 시험 원본 3개 SHA-256 불변 PASS. 전체 보존 인수 NOT RUN | 알 수 없는 외부 파일·타사 등록·기본 연결을 포함한 최종 비교가 남음 |
| 기본 새 메뉴 모드 진입 | 설정 이동 PASS, 실제 경로 미확인 | HKCU override를 백업·이동하고 승인된 수동 Explorer 재시작 1회 후에도 관찰 메뉴는 클래식 |
| 원래 메뉴 모드·설정 복구 | 최종 03:27:33 UTC 복원 PASS | 원본 키·값·Owner·Group·DACL 보존, 백업 키 없음, securityModified=false, journal RESTORED. 03:11 중간 복원·03:21 재진입과 구분 |
| 검증용 Explorer 수동 갱신 | 승인된 재시작 1회·Workspace 경로 복원 PASS | 03:05 UTC 실시. 제품 설치기 동작과 구분하며 설치 단계의 explorerRestarted=false 기록은 유지 |
| Explorer 응답 없음 | 관찰 후 자체 회복, 원인 미확정 | 두 번째 배경 우클릭에서 실제 응답 없음 제목 관찰. 단일 덤프로 제품·타사·Explorer·자동화 원인을 확정하지 않음 |
| 무상주와 시험 소유 등록·프로세스·창 정리 | NOT RUN | 실제 저장 때 helper의 일시 실행은 확인. 제품·시험의 최종 잔재 확인은 별도 |
| 실제 Windows 10 OS 실행 | NOT RUN | Windows 11의 클래식 직접 표시를 Windows 10 지원 인증으로 사용하지 않음 |

0.1.1의 실제 저장·복사는 별도 대표 실행 근거로 추가했다. 앞선 0.1.0의 모든 선택 조건·메뉴 사례를 0.1.1에서 재실행한 것으로 바꾸지는 않는다. 각 PASS는 적힌 조건에서만 유효하다. 한 모드·일부 입력의 성공을 전체 AT나 두 모드 G0 통과로 확대하지 않는다. NOT RUN은 이 중간 기록에서 해당 실제 시험의 완료 증거가 없다는 뜻이다.

## 기본 메뉴 전환 시도와 응답 없음 관찰

HKCU 메뉴 override를 백업·이동한 EnableModern은 설정 작업의 성공이다. 03:05 UTC에 승인된 수동 Explorer 재시작을 한 차례 수행하고 Workspace 창의 원래 경로를 복원했지만 기존·새 창에서 관찰한 메뉴는 여전히 클래식이었다. Windows 11 ‘더 많은 옵션 표시’ 진입은 확인하지 못했다. 이 재시작은 제품 설치기가 요구하거나 수행한 동작이 아니다.

재시작 뒤 처음 이미지 활성화 메뉴를 닫고 두 번째로 폴더 배경을 우클릭했을 때 Explorer 제목에 ‘응답 없음’이 나타났다. 저장 명령을 실행한 상황은 아니었고 이후 자체 회복했다. 단일 최소덤프의 95개 스레드에서 제품 DLL 프레임은 0개였으며 메뉴 추적·메시지 대기 상태를 관찰했다. 단일 스냅샷이고 심볼 정보가 제한되어 일시적 정지 시점의 원인이나 제품과의 무관함을 증명하지 못한다. 제품·타사 확장·Explorer·자동화의 상호작용은 미분리이며 기존 창 활성화 실패도 도구만의 문제로 단정하지 않는다.

03:11 UTC에는 원래 HKCU 설정과 Owner·Group·DACL을 보존해 복원하고 백업 키 제거를 확인했다. 03:21 UTC에 추가 비교를 위해 다시 EnableModern 상태로 진입했으며, 03:27:33 UTC 최종 Restore에서 원본 키·값·Owner·Group·DACL 보존과 백업 키 제거, securityModified=false, journal RESTORED를 확인했다. 물리 우클릭 비교 결과를 확보하지 못해 해당 요청과 추가 재시도는 중단했다. 설정 복원은 완료됐고 기본 메뉴의 실제 접근은 미확인 필수 항목으로 남는다.

## 이번 중간 결과의 로컬 근거

이 절의 경로는 저장소 기준 로컬 시험 산출물이다. 사용자 로그·설치 진단과 원본 증거는 공개 사이트에 게시하지 않는다.

- 실제 UI 관찰: `artifacts/classic-validation-20260927/explorer-observations.json`. 이미지 없음 완전 숨김, 이미지+텍스트 표시, PNG 복사·다중/TXT 제외, 메뉴 전후 sequence·파일 목록 비교가 포함된다. 최초 실제 저장은 합성 8×8 PNG이며 저장 전후 클립보드 sequence가 유지됐다. AT-04는 Explorer에서 sample.png를 실제 Ctrl+C하여 CF_HDROP 등 파일 형식만 있는 상태를 만든 뒤 저장 항목 없음·일반 Paste 활성화·sequence와 파일 목록 불변을 확인했다.
- 반복 전환 기록: `artifacts/classic-validation-20260927/classic-repeated-menu.json`. 초기 이미지 1개와 15회×3상태의 총 46행이 모두 PASS다. 1~8회는 0.1.0에서 02:26:42 UTC까지, 9~15회는 0.1.1에서 03:00:24 UTC까지 관찰했다. 16~20회는 사용자 지시에 따라 반복 생략이며 필수 잔여가 아니다.
- 초기 UI 복구: `artifacts/classic-validation-20260927/ui-recovery-new-window.json`. 02:53 UTC에 새 시험 Explorer 창으로 합성 A 폴더 이동과 저장 메뉴 표시를 확인했다. 기존 시험·업무 창 보존, Explorer 재시작·모드 변경 없음은 이 시점의 기록이다.
- 0.1.1 대표 실행: `artifacts/classic-validation-20260927/representative-ui-0.1.1.json`. 실제 저장은 유효한 8×8 PNG와 clipboard sequence 불변, 실제 PNG 복사는 이미지 형식 게시와 파일 목록 형식 부재로 PASS다.
- 승인된 수동 갱신: `artifacts/classic-validation-20260927/refresh-explorer-modern.result.json`과 `workspace-window-restored-modern.json`. 03:05 UTC 검증용 재시작과 Workspace 경로 복원 근거이며 제품 MSI 재시작 근거가 아니다.
- 응답 없음 관찰·진단: `artifacts/classic-validation-20260927/explorer-unresponsive-observation.json`, `explorer-hang-25028-summary.json`. 한 차례 최소덤프 수집과 오프라인 분석이며 원인 미확정이다. 덤프·스택·로컬 진단 원문을 공개 사이트에 게시하지 않는다.
- 설정 복원과 재진입: `artifacts/classic-validation-20260927/menu-mode-Restore-20260927T031132596.json`의 복원 PASS 뒤 `menu-mode-EnableModern-20260927T032100729.json`으로 시험 상태에 재진입했다. 이후 `artifacts/classic-validation-20260927/restore-menu-final.log`와 `.result.json`에서 03:27:33 UTC 최종 Restore PASS·exit 0을 확인했고 복원 journal은 RESTORED다.
- MSI 절차 후 원본 보존: `artifacts/classic-validation-20260927/fixtures-after-msi-sequence.json`. sample.png·second.png·note.txt의 SHA-256이 기준과 같음을 확인했다. 이 3개 합성 시험 파일의 결과를 임의 업무 파일·타사 설정 전체의 검증으로 확대하지 않는다.
- 실제 런타임 권한: `artifacts/classic-validation-20260927/runtime-save-observed2.log`. 두 번째 실제 저장 중 현재 세션의 설치 helper와 Explorer를 읽기 전용으로 조회해 둘 다 비상승임을 확인했다. helper를 놓친 이전 조회를 권한 PASS 근거로 사용하지 않는다.
- 제품 빌드: `artifacts/image-copy-save/msi/20260927T015542477Z-94a4973fa9cd4020b4dd6e3cb7f672ef/build-metadata.json`. 0.1.0 x64, NotSigned, 자체 포함 payload, HKLM 클래식 등록. MSI SHA-256은 `9F9E583BC9BC580BE2519DD5516D1BCF12CA1BAEFD93D6F456A5B51FA7D8C6A1`이다.
- 실제 설치: `artifacts/image-copy-save/msi-lifecycle/20260927T020108652Z-e87eb8d13468422590a0d946684cc47f/result.json`. 관리자 실행·exit 0, 설치 후 제품 등록 확인, 합성 보존 PNG 해시 불변.
- 실제 Repair: `artifacts/image-copy-save/msi-lifecycle/20260927T020145046Z-b6795071d83d4d3797ab943c1901a090/result.json`. 제거한 엔진 DLL 복구·exit 0, 합성 보존 PNG 해시 불변.
- 최초 업그레이드 요청 미시작: `artifacts/image-copy-save/msi-test-launch/4e7d883423ba45af8259a792a84dece8/launch.json`. 2026-09-27 02:07:30 UTC에 ELEVATION_NOT_STARTED로 기록됐다. UAC 취소로 시작하지 않은 요청이며 이후 실제 업데이트 결과와 구분한다.
- 실제 업데이트: `artifacts/image-copy-save/msi-lifecycle/20260927T022804961Z-d3e98faf27bd43c7b0bb37748c662bb7/result.json`. 0.1.0→0.1.1 관리자 업데이트 PASS·exit 0·재부팅 요구 없음.
- 결과 읽기 오류와 회귀: `artifacts/image-copy-save/msi-final-sequence/20260927T022738797Z-b020b49a17d44a4c9d2c7903414f341b/sequence.json`은 업데이트가 완료된 뒤 실행기가 결과 JSON을 읽다가 STOPPED가 된 이력이다. UTF-8과 빈 기본 레지스트리 값 이름을 Dictionary로 처리하도록 수정한 뒤 실제 결과 파일 읽기 회귀가 PASS했다. `artifacts/classic-validation-20260927/utf8-upgrade-result-fixed.log`와 같은 이름의 `.result.json`에 근거가 있다. MSI 업데이트 자체의 실패나 남은 단계의 실행으로 취급하지 않는다.
- 재승인 후 나머지 수명주기: `artifacts/image-copy-save/msi-final-sequence/20260927T023218720Z-24b38a00689d4157911b120071978ce1/sequence.json`. Remove(exit 0) → Rollback(예상 exit 1603) → Install(exit 0) 모두 PASS이며 각 상세 result.json을 연결한다. 제거와 실패 롤백 뒤 제품 등록은 0개, 마지막 설치 뒤 7개다. 0.1.1 MSI SHA-256은 `418C8774355A59EAEF16CE24A318F91B8D5F77D29B517808B3AA83B9A7A917F5`이고, 빌드 메타데이터는 NotSigned·자체 포함 payload를 확인한다. 최종 상태는 Explorer 검증을 위한 0.1.1 설치 유지다.

실행 안내는 [소스·빌드 안내](../../../tools/ImageCopySave/README.md), [설치 현황](../../../tools/ImageCopySave/installer/README.md), [수용시험 기록](../../../tools/ImageCopySave/TEST_RESULTS.md)에 연결한다. 아래 v1.1·v1.0 섹션은 당시의 요구·시도·판정이며 현재 제품 조건이 아니다.

## v1.1 조사 이력 — 첫 Windows 11 메뉴가 필수였던 당시 기록

### 당시 판정

사용자가 [ADR-0022](../../design/0022-image-admin-install.md)로 관리자 설치를 허용했다. 무서명 sparse 관리자 등록·정리, 진단 MSI의 SYSTEM 준비·프로비저닝·정리와 비상승 사용자 등록이 PASS다. 현재 Explorer는 구형 메뉴로 고정되어 새 메뉴의 표시·숨김을 관찰하지 못했다. 기존 설정은 보존했고 임시 등록과 시험 창은 정리했다. [최신 실행 근거](../../delivery/image-admin-install-20260927.md).

앞선 signed full MSIX의 `0x800B0109`와 비상승 unsigned sparse의 `0x80073D2B`는 이전 설치 조건의 이력이다. 관리자 설치의 현재 차단 사유가 아니다.

사용자가 기본 ‘새로 만들기’ 내부 위치 조건을 해제했다. 저장 명령은 실제 로컬 폴더 배경의 Windows 11 첫 우클릭 메뉴에 별도 명령으로 제공하는 후보를 구현했다. 이미지가 없을 때 완전히 숨김, 상주 감시 없음, 레거시 메뉴에만 두지 않음, 설치기가 등록을 담당한다는 나머지 조건은 유지한다. [v1.0 원문](ImageCopySave_Requirements_v1.0.md)은 변경하지 않았다.

**기존 ShellNew 연결 방식 미확정과 비상승 설치 거절은 현재 차단 사유에서 제외했다. 새 메뉴에서 native IExplorerCommand의 실제 표시·숨김을 입증하지 못해 G0를 통과시키지 않는다.** DLL 직접 호출이나 진단 MSI 성공은 실제 메뉴 검증을 대체하지 않는다. M2 사용자 동작·결과 선택·오류 안내와 M3 제품 수명주기도 완료 전이다.

### 구현한 후보와 검증 범위

- C++ x64 DLL의 Save/Copy 명령은 IExplorerCommand와 IObjectWithSite를 구현한다. Save는 호출한 보기의 IFolderView → IPersistFolder2 → 폴더 PIDL에서 대상을 확인한다. 활성 창이나 선택한 폴더로 대신 추정하지 않는다.
- GetState의 빠른 호출에서는 간단한 제외만 판정하고 추가 작업이 필요하면 E_PENDING을 반환한다. 느린 호출에서 경로·형식 메타데이터를 확인한다. Save는 PNG/DIBV5/DIB/BITMAP 형식이 없거나 조회가 불확실하면 ECS_HIDDEN을 유지한다. 픽셀 디코딩·파일 생성·클립보드 데이터 읽기는 상태 조회에 없다.
- 실제 고정 로컬 볼륨의 일반 경로만 취급한다. UNC, SUBST, 가상 문맥, reparse/recall 경로와 예약 장치 이름은 숨긴다. 이 보수적인 경계가 실제 Windows 11 문맥에서 맞는지 실기로 확인해야 한다.
- Invoke는 호출 시점 sequence와 원래 보기를 고정하고 동일 패키지 루트의 helper를 실행한다. 현재 station/desktop을 명시하며 탐색기에서 이미지 처리 완료를 기다리지 않는다. 잠금 안에서 기준값을 확인하고 결과 통신·같은 보기 선택·비모달 진행/취소·오류 UI를 연결했다. [ADR-0017](../../design/0017-image-copy-save-invocation.md)의 구현 계약이며 실제 Explorer 실기를 통과했다는 뜻은 아니다.
- full MSIX manifest는 native COM STA surrogate와 Directory\Background 저장 / 단일 파일 복사 등록을 선언한다. 앱 ID와 게시자 이름은 평가용 제안이다. 이후 unsigned sparse 관리자 설치 조건은 ADR-0022로 결정했고, 자체 포함 제품 MSI identity는 통합 단계에서 고정한다.

공식 근거: [패키지의 Explorer 명령 통합](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer), [GetState 빠른/느린 호출 계약](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-getstate), [패키지 manifest 구성](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-manual-conversion). 확인일: 2026-09-25. 이 근거는 구현 후보의 API 계약이며 이 제품의 실제 표시 성공 증거가 아니다.

| 검증 | 현재 상태·증거 범위 |
|---|---|
| v1.1 요구·ADR·manifest·PowerShell 구문 | 작성·정적 확인 |
| native DLL 로컬 빌드·순수 정책/직접 COM 66개 | 최신 로컬66개 PASS / 0 FAIL. clipboard/Invoke/OS 등록·Explorer 미실행 |
| unsigned full MSIX pack/unpack·구조 검사 | 최신0.1.1 로컬 PASS, 입력408개 해시 일치. 서명·설치 성공을 의미하지 않음 |
| 기존 인증서 서명·SignTool 검증 | PASS, 현재 PC의 실제 MSIX 설치 허용을 보장하지 않음 |
| 이전 signed MSIX 일반 사용자 설치 | FAIL / 0x800B0109, 당시 실패 후 등록0개 |
| 관리자 unsigned sparse 등록·정리 | PASS, 전체 사용자·프로비저닝 잔여0개 |
| SYSTEM 진단 MSI 설치·제거 / 비상승 사용자 등록 | PASS, 제품 MSI 수명주기와 구분 |
| Windows 11 새 메뉴·Invoke / 제품 재설치·업데이트·제거 | BLOCKED / NOT RUN |

이전 후보는 도구 누락으로 CI에서 빌드했으나, 이번에는 Microsoft 고정 payload와 SDK NuGet 서명을 검증해 저장소의 `.tools`에 추출하고 로컬에서 빌드했다. 새 Git worktree·원격 CI는 사용하지 않았다. 시스템 개발 도구 설치나 인증서 신뢰 변경은 하지 않았다. 최신 서명·설치 상태와 산출물은 [로컬 인계 기록](../../delivery/image-copy-save-local-20260925.md)에 별도로 기록한다. 제품의 실제 메뉴 PASS와 빌드 PASS는 구분한다.

### 개정 G0의 남은 실기

사용자가 선택한 현재 사용자 환경과 정상 관리자 승인 설치 경로를 사용한다. 별도 서명은 요구하지 않는다. 현재 PC의 구형 메뉴 고정 설정 처리 후 새 메뉴 실기가 필요하다. 사용자에게 DLL 수동 등록을 요구하지 않으며, 등록 성공이나 Explorer 재시작 자체를 G0 통과로 판정하지 않는다.

| 순서 | 확인과 보존할 증거 | 현재 상태 | 관련 수용시험 |
|---|---|---|---|
| 1 | 실제 폴더 배경의 첫 우클릭 경로에서 저장 명령 접근, 더 많은 옵션 전용 아님 | NOT RUN | AT-08, AT-09 |
| 2 | 이미지→텍스트→빈 상태→이미지 20회, 새 메뉴마다 표시·완전 숨김 | NOT RUN | AT-01~07 |
| 3 | 회색·유령·빈 앱 메뉴·불필요한 구분선 부재 | NOT RUN | AT-07, AT-08 |
| 4 | 메뉴 진입의 형식 조회만 수행, 디코딩·파일 생성·클립보드 변경 없음 | NOT RUN | AT-10 |
| 5 | 두 창·두 탭·지원 밖 문맥의 정확한 대상, 감시/반복 등록/Explorer 재시작 없음 | NOT RUN | AT-11, AT-12, AT-42 |
| 6 | 관리자 승인 제품 설치·재설치·업데이트·제거와 일반 사용자 실행, PNG 연결·타사 메뉴 보존 | 제품 MSI NOT RUN; 진단 MSI 설치·제거 PASS | AT-40, AT-41, AT-44 |

구현/시험 명령은 [소스 안내](../../../tools/ImageCopySave/README.md), [패키징·설치 현황](../../../tools/ImageCopySave/installer/README.md), [수용시험 기록](../../../tools/ImageCopySave/TEST_RESULTS.md)에 연결한다.

## v1.0 조사 이력 — 아래 판정과 미승인 표시는 당시 상태

아래는 2026-09-24의 기본 New 내부 동적 표시 조사 기록이다. 위치 변경안은 이후 사용자 승인과 v1.1로 채택되었으므로 아래의 “미승인”, “새 후보 없음”, “최소 확장 미구현”은 현재 후보의 상태를 뜻하지 않는다.

### 판정

**기본 ‘새로 만들기’ 내부에서 클립보드 이미지 유무에 따라 저장 명령 하나만 표시·숨김하는 구현은 아직 입증하지 못했다. G0는 BLOCKED이며 제품 배포 가능 판정은 보류한다.** 일반 IExplorerCommand의 ECS_HIDDEN 지원을 이 위치의 성공 증거로 사용하지 않는다.

문서에 방법이 없다는 사실만으로 Windows에서 절대 불가능하다고 결론 내리지 않는다. 이번 기록은 공식 계약 검토와 로컬 읽기 전용 관찰이며, 시험용 확장을 등록해 실패를 재현한 기록이 아니다. 동적 ShellNew 연결 방법이 확인되지 않아 해당 최소 확장을 구현·설치하지 않았고, 표시·숨김 화면 증거도 없다. 따라서 실제 메뉴 시험을 FAIL 또는 PASS라고 기록하지 않는다.

원명세 3.3에 따라 M1 독립 이미지 엔진·자동 시험은 진행할 수 있다. M2의 실제 Shell 연결과 M3의 제품 설치·제거·출시 판정은 G0 증거가 확보될 때까지 차단한다.

### 실행한 확인과 환경

| 확인 | 실제 결과 | 증거의 범위 |
|---|---|---|
| 원문·정책 검토 | 첨부 명세 v1.0, AGENTS.md, tools.md, documentation.md, 문서 양식 확인 | 요구와 문서 구조 확인 |
| OS 읽기 전용 조회 | Windows Professional, 23H2, x64, 빌드 22631.6199 | 이 빌드의 지원 인증 아님 |
| Explorer 파일·프로세스 조회 | 파일 버전 10.0.22621.4599, explorer 프로세스 1개 | 메뉴를 조작하거나 관찰한 증거 아님 |
| 기본 New 등록 읽기 | HKCR/Directory/Background/shellex/ContextMenuHandlers/New 기본값 {D969A300-E7FF-11d0-A93B-00A0C90F2719} | 기존 OS 등록 존재만 확인 |
| 공식 문서·소스 확인 | 아래 Microsoft 문서·스키마·고정 커밋의 샘플 및 SDK 헤더 확인 | API 계약·설계 후보 확인, 실제 메뉴 실행 증거 아님 |
| 확장 등록·실행·캡처 | NOT RUN | 시험용 Shell 확장 미등록, 화면 증거 없음 |
| 일반 사용자 설치·재설치·제거 | NOT RUN | 패키지·서명·최종 등록 방식 미확정 |

조회에 Windows PowerShell 5.1.22621.6133을 사용했다. 레지스트리·인증서·패키지·클립보드·기본 연결을 바꾸지 않았으며 Explorer를 종료하거나 재시작하지 않았다. 형식별 ShellNew 키를 추가로 조사하는 두 번째 읽기 전용 조회는 실행 도구 제한시간에 걸려 결과를 채택하지 않았다. 이 실패 역시 메뉴 실패 증거가 아니다.

현재 제공된 브라우저 자동화 도구는 네이티브 앱 조작이 비활성인 세션이다. 그러나 이를 모든 Windows API 접근 불가로 해석하지 않는다. 2026-09-24 후속 읽기 전용 probe stdout에서는 세션1의 Explorer1개, WinSta0\Default, UOI_IO=True, DESKTOP_READOBJECTS 권한의 OpenInputDesktop 성공을 확인했다. 입력·화면 캡처·UIA 동작·클립보드 API는 실행하지 않았으며 별도 JSON/정확한 UTC 시각은 보존하지 않았다. OS/Explorer 버전은 앞선 M0 조회값이고 재확인 시도는 실행 전 EPERM으로 막혔다. 이 관측은 격리 시험 환경 확보나 G0 메뉴 실기 성공의 증거가 아니다.

다음 읽기 전용 명령으로 환경을 다시 확인할 수 있다. 이 명령은 제품 설치 절차가 아니다.

```powershell
$os = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$os | Select-Object EditionID, DisplayVersion, CurrentBuild, UBR
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
(Get-Item "$env:WINDIR\explorer.exe").VersionInfo.FileVersion
(Get-Item "Registry::HKEY_CLASSES_ROOT\Directory\Background\shellex\ContextMenuHandlers\New").GetValue("")
```

### 검토한 방식과 확인된 차이

| 후보 | 공식 계약에서 확인한 내용 | 이번 판정 |
|---|---|---|
| ShellNew | Command, Data, FileName, NullFile로 파일 생성 방식을 지정한다. 검토한 절에는 클립보드에 따른 항목별 상태 콜백이 없다. | 문서 검토 완료. 동적 표시 실기는 NOT RUN. 정적 템플릿은 요구를 충족하지 못함 |
| IExplorerCommand::GetState | 해당 일반 명령의 ECS_HIDDEN 상태를 표현할 수 있다. 느린 상태 조회의 별도 호출 계약이 있다. | 일반 명령의 가능성과 ShellNew 내부 위치는 분리. 위치 검증 대체 불가 |
| 패키지의 windows.fileExplorerContextMenus | native COM 클래스와 파일·폴더·배경 문맥 연결 및 Windows 11 메뉴 통합을 설명한다. | 배경 등록만으로 기본 New 안에 들어간다고 추정하지 않음 |
| desktop5:Verb | 문서화된 속성은 Id와 Clsid이며 기본 New의 부모 항목 지정 속성이 제시되지 않는다. | 조사한 스키마만으로 요청 위치 구현을 입증할 수 없음 |
| INewMenuClient::IncludeItems | 보기에서 비폴더/폴더 범주를 필터링하는 플래그를 반환한다. | 특정 앱 명령 한 개의 클립보드 조건 필터로 해석할 근거 없음 |
| 패키징과 외부 위치(sparse package) | 사용자별 PackageManager 등록·제거와 신뢰된 서명 패키지를 설명한다. | 설치 경로 후보. 조직 신뢰 조건·일반 사용자 성공은 미검증 |

근거: [ShellNew와 cascading menu](https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers#extending-a-new-submenu), [GetState](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-getstate), [패키지 Explorer 명령](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer), [desktop5:Verb](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-desktop5-verb), [IncludeItems](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-inewmenuclient-includeitems), [외부 위치 패키지 등록](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps). 확인일: 2026-09-24.

IExplorerCommand::EnumSubCommands로 앱이 소유하는 하위 메뉴를 만드는 것과 Windows 기본 ‘새로 만들기’에 항목을 넣는 것은 같은 증거가 아니다. 앱 하위 메뉴 이름을 ‘새로 만들기’로 정하거나 기존 New COM 등록을 교체하는 방식은 사용하지 않는다. Windows 11의 일반 메뉴 확장은 app identity와 IExplorerCommand가 안내된 경로이며, 기존 메뉴만 제공하는 방식은 첫 우클릭 접근성의 합격 증거가 아니다. [Windows 11 메뉴 설계](https://blogs.windows.com/windowsdeveloper/2021/07/19/extending-the-context-menu-and-share-dialog-in-windows-11/)

### SDK·공식 샘플 추가 검토

2026-09-24에 Microsoft 공식 샘플 소스와 공개 SDK 헤더를 읽기 전용으로 재검토했다. 아래 소스 링크는 조사한 커밋에 고정되어 있다. 새 등록·설치·클립보드 조작·탐색기 UI 시험은 실행하지 않았다.

| 추가 후보·근거 | 소스에서 확인한 계약 | G0에 남는 간극 |
|---|---|---|
| IExplorerCommandState와 CommandStateHandler | 공식 샘플의 RegisterExplorerCommandStateHandler는 일반 ProgID의 Shell\Verb 키에 CommandStateHandler를 등록한다. [등록 소스](https://github.com/microsoft/Windows-classic-samples/blob/434f6002bdf9cf9829406c3ff2b33387982d6168/Samples/Win7Samples/winui/shell/appshellintegration/ExplorerCommandVerb/RegisterExtension.cpp#L352), [상태 처리 샘플](https://github.com/microsoft/Windows-classic-samples/blob/434f6002bdf9cf9829406c3ff2b33387982d6168/Samples/Win7Samples/winui/shell/appshellintegration/ExplorerCommandVerb/ExplorerCommandStateHandler.cpp) | 일반 verb의 동적 상태 등록이며 기본 ShellNew 항목에 연결하는 예제가 아니다. 별도 인터페이스라는 이유로 ShellNew 지원을 추정할 수 없음 |
| INewMenuClient와 SDK 선언 | IncludeItems는 NMCII_FLAGS 출력만 받으며 특정 항목 식별자를 입력받지 않는다. 플래그는 NONE, ITEMS, FOLDERS이다. SelectAndEditItem은 생성된 항목의 선택·편집을 다룬다. [고정 SDK 헤더](https://github.com/microsoft/win32metadata/blob/5c5efbc01d4c87f6830ec304d42777991d533154/generation/WinSDK/RecompiledIdlHeaders/um/ShObjIdl_core.h#L26777) | 범주 제어와 생성 후 처리가 명령 하나의 표시·숨김 콜백 계약을 제공하지 않음 |
| AppliesTo와 패키지 스키마 | AppliesTo는 대상 항목의 빠른 속성을 AQS로 평가하는 일반 verb 조건이다. 검토한 desktop5:Verb 및 uap:FileTypeAssociation 스키마에도 기본 New 항목별 상태 콜백 연결은 제시되지 않는다. [AppliesTo](https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers#getting-dynamic-behavior-for-static-verbs-by-using-advanced-query-syntax), [파일 형식 연결 스키마](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap-filetypeassociation) | 클립보드 이미지 유무를 평가하여 기본 New 항목 하나를 제외하는 경로를 입증하지 못함 |

[IExplorerCommandState 문서](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-iexplorercommandstate)의 GetState도 일반 명령 상태 계약이다. SDK에 NewMenu CLSID 또는 INewMenuClient가 존재한다는 사실 자체는 타사 명령의 동적 ShellNew 연결을 보장하지 않는다.

**아직 확인하지 못한 핵심 계약은 “기본 New가 열릴 때마다 앱의 항목별 상태 콜백을 호출하도록 등록하고, 그 제외 상태를 Windows 11 첫 메뉴의 기본 New 내부에 적용하는 공개 연결 방식”이다.** 일반 ECS_HIDDEN 호출 성공이나 앱이 만든 하위 메뉴는 이 간극을 해결하지 않는다. 이번에 검토한 문서·소스 범위에서는 해당 계약을 갖춘 새 구현 후보를 찾지 못했으며, 이것을 모든 Windows 구현에서의 불가능성 증명으로 확대하지 않는다. 근거 있는 최소 확장 후보가 확인되기 전까지 G0는 **BLOCKED**, 실제 메뉴 시험은 **NOT RUN**을 유지한다.

### G0 재개 시 필요한 실제 시험

먼저 공식 API·등록 계약을 근거로 요청 위치를 대상으로 하는 최소 확장을 제시한다. 격리된 Windows 11 x64 시험 환경에서 설치 전 기본 메뉴·연결·등록 상태를 기록하고, 설치기가 등록을 담당하게 한다. 일반 사용자에게 수동 DLL 등록·개발자 모드·레지스트리 편집을 요구하는 절차는 합격할 수 없다.

| 순서 | 실기 확인과 보존할 증거 | 현재 상태 | 관련 수용시험 |
|---|---|---|---|
| 1 | 기본 New 내부 위치와 첫 우클릭 경로의 연속 화면 | NOT RUN | AT-08, AT-09 |
| 2 | 이미지→텍스트→빈 상태→이미지 20회, 매번 새 메뉴의 표시·완전 숨김 | NOT RUN | AT-01~07 |
| 3 | 회색·유령·빈 앱 메뉴·불필요한 구분선 부재 | NOT RUN | AT-07, AT-08 |
| 4 | 메뉴 진입은 형식 확인만 수행하고 디코딩·파일 생성·클립보드 변경 없음 | NOT RUN | AT-10 |
| 5 | 상태 변경마다 등록 변경·감시 프로세스·Explorer 재시작 없음 | NOT RUN | AT-07, AT-42 |
| 6 | 일반 사용자 설치·재설치·업데이트·제거 및 PNG·타사 메뉴 보존 | NOT RUN | AT-40, AT-41, AT-44 |

화면 자료에는 빌드·시각·시험 번호를 대응시키고 업무 파일·개인 클립보드 내용은 포함하지 않는다. 일반 메뉴용 GetState 단위시험, 인위적으로 만든 HMENU, 직접 COM 메서드 호출은 이 표의 실기 성공을 대신하지 않는다. 서명·신뢰·조직 정책이 충족되지 않으면 조건을 그대로 기록하고 설정을 완화해 통과시키지 않는다.

### 변경안 — 미승인

| 변경안 | 바뀌는 요구 | 상태 |
|---|---|---|
| 요청 위치를 유지하고 추가 조사·실기를 계속한다 | 요구 변경 없음. 문서화된 연결과 실제 증거 확보 필요 | 현재 진행 경계 |
| 실제 폴더 배경의 별도 Windows 11 명령으로 저장 위치를 옮긴다 | MNU-01, AT-08. 완전 숨김·첫 메뉴·무상주 조건은 유지 | UNAPPROVED. 구현·등록·완료 처리하지 않음 |

고정 ShellNew 템플릿, 빈 PNG 선생성, 항상 보이는 오류 안내 명령, 회색 항목, 감시 프로그램, 반복 등록 수정, 비공개 후킹은 변경안으로 채택하지 않는다. 메뉴 위치 변경은 사용자가 합의한 요구 변경이 있을 때만 별도 명세 개정으로 처리하며, 본 기록 작성으로 승인이 발생하지 않는다.

### 변경 이력

- 2026-09-24 · 0.1: 원명세 G0의 첫 증거 검토. 읽기 전용 환경 관찰, 공식 계약 비교, 미실행 시험과 변경안 기록.
- 2026-09-24 · 0.2: 공식 샘플·SDK 고정 소스로 일반 verb 상태 처리와 기본 New 연결을 구분하고, 미확인 공개 계약을 명시. G0 BLOCKED·탐색기 실기 NOT RUN 유지.

- 2026-09-24 · 0.3: 로컬 desktop 읽기 전용 접근 성공과 네이티브 UI 실기 미실행을 구분. 새로운 동적 ShellNew 후보는 없으며 G0 판정 유지.

- 2026-09-25 · 0.4: 사용자 승인 v1.1 위치 변경과 native/full-MSIX 후보를 현재 판정으로 분리. 실제 G0 통과 여부는 보류.
