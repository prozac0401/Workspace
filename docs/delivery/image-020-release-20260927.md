# 그림 복사·저장 0.2.0 · 보존 보완과 정식 릴리스 작업 기록

날짜: 2026-09-27 · 책임: 도구 개발·검증 담당 · 상태: **정식 Release 게시·공개 자산 검증 완료 — Pages 안내 배포 진행 중**

적용: [v1.2 변경 계약](../tools/image-copy-save/ImageCopySave_Requirements_v1.2.md), [보존 설계 ADR-0024](../design/0024-image-msi-preservation.md), [공개 안내 ADR-0025](../design/0025-image-public-guide.md), [도구 정책](../policies/tools.md), [문서 정책](../policies/documentation.md).

사용자는 기존 등록·외부 수정 파일 보존 문제를 해결하고 적용한 뒤 정식 릴리스까지 진행하도록 지시했다. 승인된 배포 형식은 Windows 11 x64용 자체 포함 무서명 MSI이며, 관리자 설치와 일반 사용자 실행을 분리한다. 서명 인증이나 회사 전체의 상용 배포 승인을 받았다는 뜻은 아니다.

## 정식 Release 게시와 공개 자산 확인

[image-copy-save-v0.2.0 정식 Release](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.0)를 2026-09-27 09:58:56 UTC에 게시했다. releaseId=397594542, draft=false, prerelease=false이며 태그 소스 커밋은 fe621a449a3e6c681c86166a0d8eb88580bb9564다. 제품 보존 시험 32개·기본 위치 설치·대표 탐색기 복사/저장을 확인한 같은 MSI를 게시했다.

| 공개 자산 | 바이트 | SHA-256 |
|---|---:|---|
| [ImageCopySave-0.2.0-x64.msi](https://github.com/prozac0401/Workspace/releases/download/image-copy-save-v0.2.0/ImageCopySave-0.2.0-x64.msi) | 50,569,176 | 82A72EB85F41D6DF29BC94EE57215991BA41BEF542717D81CCC0C850C5F5134B |
| [SHA256SUMS.txt](https://github.com/prozac0401/Workspace/releases/download/image-copy-save-v0.2.0/SHA256SUMS.txt) | 94 | 327C1CD262007A7E088D828AFB777222773B32C5D663E94FC54C94CA073483C5 |

09:59:12~09:59:19 UTC 비인증 공개 GET에서 두 자산 모두 HTTP 200이며 MSI 크기·SHA-256과 체크섬 내용을 검증했다. 복구/롤백 MSI·원시 로그·SID·개인 경로는 공개 자산에 포함하지 않았다. Pages 안내 배포는 아직 진행 중이며 실제 배포 결과·공개 안내 URL 확인은 후속 기록으로 남긴다. 로컬 근거: artifacts/release-readiness-20260927/image-020-release-draft/public-release-verification.json.

## 최신 제품 결과 · 외부 전체 보존 시험 32/32 PASS

09:47:01~09:50:09 UTC 외부 호스트의 실제 Suite는 **32 PASS / 0 FAIL / 0 NOT RUN**이다. 대상 MSI는 공개 후보 82A72EB85F41D6DF29BC94EE57215991BA41BEF542717D81CCC0C850C5F5134B와 동일하다. 제품 소스나 MSI를 다시 바꾸지 않고 앱 호스트 밖에서 시험 자료를 생성·실행했다.

| 실제 검증 범위 | 결과 |
|---|---|
| HKLM·HKCU 일곱 루트씩, 기존 빈 폴더·파일 충돌 | 16 PASS: 기대한 설치 차단 |
| 새 설치 실패 롤백·정상 시험 설치 | 2 PASS |
| 이전 설치의 수정 파일/등록 차단·알 수 없는 자료 보존·업데이트 실패 롤백 | 4 PASS |
| 복구: 추가 스트림·수정 파일/등록·형식 변경 차단, 누락 파일 복원 | 5 PASS |
| 제거: 추가 스트림·수정 파일/등록·형식 변경 차단, 알 수 없는 자료 보존 | 5 PASS |

충돌 차단과 고의 실패 롤백 사례의 msiexec 1603은 해당 사례의 기대 결과이며, 정상 설치·업데이트·복구·제거는 0이다. 합성 등록은 EXACT_FIXTURE_CLEANED, 전체 정리는 EXACT_SYNTHETIC_FIXTURES_REMOVED_BUSINESS_FIXTURE_PRESERVED로 확인했다. businessFixturesDeleted=false, rebootRequired=false다. 이전 호스트 격리 조건의 FAIL 보고서는 고치지 않고 이 실제 재검증 결과와 함께 보존한다.

근거: artifacts/image-copy-save/msi-preservation/20260927T094701542Z-2e4f093f9abf4988a5b53b3e5c51bcd0/result.json 및 사례별 로그. 최종 기본 설치와 Release 게시는 별도 실제 결과로 위·아래에 구분한다.

## 최신 설치 결과 · 전체 재개와 기본 위치 설치 PASS

외부 continuation은 08:41에 남았던 정확한 시험 설치 제거 → 깨끗한 상태 확인 → 전체 보존 Suite → 최종 설치 전 깨끗한 상태 확인 → 기본 위치 최종 설치를 모두 PASS로 완료했다. launch는 COMPLETED, exitCode 0이며 continuation의 finalInstallAttempted=true다. 앞선 trial 잔류 상태는 그 당시 이력으로 유지하고 이번 제거 완료와 구분한다.

09:50:30~09:50:42 UTC 최종 Install은 같은 82A72EB8… MSI로 **PASS, msiexec 0**이다. 기본 위치 C:\Program Files\Workspace\ImageCopySave와 제품 등록 23값을 확인했다. rebootRequired=false, explorerRestarted=false, userFilesDeleted=false다. 설치 결과를 신규 GUI 전체 검증이나 정식 공개 완료로 확대하지 않는다.

로컬 근거: artifacts/image-copy-save/msi-preservation-development/normal-continuation-runs/20260927T094520179Z-0b8153e38bb04cce9337512f38dbde9d/의 continuation.json·launch.json, artifacts/image-copy-save/msi-lifecycle/20260927T095030651Z-4950c1cff7a2437581348696166cc45f/result.json.

## 최종 설치본 대표 GUI 확인

09:55:54 UTC 기본 설치본으로 실제 Explorer의 기존 클래식 직접 메뉴에서 그림으로 복사 → 복사한 그림 저장을 확인해 PASS했다. 150×150 합성 PNG의 22,500픽셀 차이는 0개였고 원본·출력 SHA-256은 C4A9281B384C4785705FAE1321F92FA7C738EBBB5C6C97D693A343A9FEF9C82A로 같았다. 저장 전후 클립보드 시퀀스 59→59와 PNG·DIBV5·Bitmap·DIB 형식을 유지했다. 메뉴 모드 변경과 Explorer 재시작은 없었다.

출력 파일 존재는 확인했으나 저장 직후 최종 행이 선택됐는지는 NOT_CONFIRMED다. 이 결과는 기본 설치본의 대표 복사·저장 두 동작에 한정하며, Windows 11 기본 메뉴 경로 두 기능의 기존 사용자 확인 PASS와 별개다. 모든 형식·창/탭·외부 앱 확인이나 자동 선택 PASS로 확대하지 않는다. 로컬 근거: artifacts/image-copy-save/release-smoke/20260927T081952101Z-243c6cd1dfed4440a7a308c1233e8582/result.json.

## 진단 이력 · 외부 실행으로 시험 HKCU의 호스트 가상화 확인

09:11 UTC v1 진단과 09:20 UTC v2 진단은 정상 UAC 승인 후 실행해 진단 절차 PASS를 기록했다. 두 결과 모두 동일 사용자·64비트로 표시된 경로에서 실행 전후 native EXE에는 시험 표식이 보이지만 MSI custom action에는 보이지 않는 차이를 확인했다. v2는 제품 관련 경로와 별도 합성 경로 등 3개 시험 표식 모두에서 같은 차이를 재현했다. 이 PASS는 진단·보존 범위이며 제품 MSI의 충돌 차단 PASS가 아니다.

v2에서는 Environment 조회가 같고 Classes 하위 키 개수는 native 863개·CA 862개였다. CA에 AcLayers가 로드되고 job 값이 CA 0·native 1인 차이도 관찰했다. AcLayers나 job 값 하나만으로 원인을 단정하지 않는다. 합성 등록 3개와 이번에 만든 상위 키를 정리했으며, 전후 기존 제품 404파일·23등록 값 불변과 진단 제품 미등록을 확인했다.

부모 실행 경로를 읽기 전용으로 확인한 결과 ChatGPT.exe에는 MSIX package identity가 있고 그 아래 실행 도구들은 직접 package identity가 없어도 job 안에 있었다. 실제 호스트 manifest의 Windows 11 virtualization:RegistryWriteVirtualization 제외 목록은 Chrome NativeMessagingHosts 한 곳뿐이었다. Microsoft 문서는 Windows 11의 새 제외 목록 선언이 이전 desktop6 선언보다 우선하며, 가상화된 HKCU 쓰기는 앱별 영역에 남아 외부 앱에서 보이지 않는다고 설명한다. [공식 flexible virtualization 문서](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization).

이 관찰과 실제 manifest·공식 동작을 근거로 호스트의 MSIX 레지스트리 가상화를 시험 HKCU 데이터가 MSI 작업과 분리된 원인으로 식별했다. 이어 사용자가 앱 밖에서 확인 명령을 시작하고 정상 UAC를 승인한 09:32 UTC 진단에서 이 차이를 확인했다. 실행 전 native·MSI custom action·실행 후 native가 모두 job 0이며, 세 시험 표식의 값이 모두 정확히 일치했다(읽기 관찰 수 15/9/15). 제품의 OpenPlainKey와 같은 경로도 모두 읽었다. 앱 호스트의 HKCU 쓰기 격리 때문에 앞선 시험 fixture가 MSI 작업에 보이지 않았음을 확인한 결과다.

외부 진단은 PASS이며 합성 등록 3개와 이번에 생성한 상위 키를 정리했다. 기존 제품의 404파일·23등록 값은 전후 그대로이고 진단 제품도 등록되지 않았다. v3 진단은 빌드만 보존하고 실행하지 않았다. 앞서 normal wrapper의 CheckOnly는 현재 앱 job 안에서 STOPPED_BEFORE_UAC_NOT_EXTERNAL_HOST로 차단돼 UAC·MSI·합성 등록 생성이 시작되지 않았다. 이후 사용자가 Win+R에서 저장소 루트 artifacts/image-msi-check.cmd를 실행해 위 외부 진단을 완료했으며, CheckOnly와 외부 실제 결과를 구분한다.

| 진단 근거 | 로컬 기록 |
|---|---|
| v1 실제 진단 PASS | artifacts/image-copy-save/msi-preservation-development/registry-context-runs/20260927T091128269Z-e9f6f113995a423f839eec371eb70310/diagnostic.json 및 comparison.json |
| v2 실제 진단 PASS·3개 표식·보존 확인 | artifacts/image-copy-save/msi-preservation-development/registry-context-v2-runs/20260927T092004437Z-f40a67ccb44d4618b670a07861891ad5/diagnostic.json 및 전후 native/MSI 로그 |
| 호스트 실행 문맥 | artifacts/image-copy-save/msi-preservation-development/probe-host-context-20260927T092535261Z.json |
| 현재 호스트에서 CheckOnly 사전 차단 | artifacts/image-copy-save/msi-preservation-development/normal-host-entry-20260927T093009734Z.json |
| 외부 호스트 v2 실제 진단 PASS | artifacts/image-copy-save/msi-preservation-development/registry-context-v2-runs/20260927T093231652Z-17568e714e414cfda1d034583e56f6f2/diagnostic.json 및 전후 native/MSI 로그 |

기존 제품 보존 Suite의 FAIL 보고서는 수정하지 않고 앱 호스트의 HKCU 격리 조건에서 얻은 결과로 분류한다. 진단 이후 제품 후보 82A72EB8…와 생산 소스의 추가 변경 없이 외부 호스트에서 전체 Suite를 재실행했고 위 최신 결과처럼 32개를 통과했다. 진단 PASS와 제품 실제 인수를 구분하며 최종 기본 설치·정식 게시 여부는 별도 기록한다. 원시 SID·환경 경로·호스트 manifest 원문은 공개 문서나 자산으로 옮기지 않는다.

## 제품 MSI 실제 판정 · 재개·제거 성공 후 HKCU 충돌 시험 재실패

08:40:23 UTC 요청은 정상 UAC 승인을 받아 자식 프로세스 18988이 시작됐다. 0CF8D470… 재개 실행기는 완료된 Service를 반복하지 않고 수정 guard를 통해 이전 시험 설치를 제거했다. 제거는 즉시·지연 guard PASS, msiexec 0으로 완료됐고 뒤이은 깨끗한 설치 상태 Inspect도 PASS다. 앞선 3010 복구 갱신과 제한적 재개 절차가 실제 후속 제거까지 진행된 결과이며 전체 보존 Suite 통과와는 구분한다.

| 이번 실제 단계 | 결과 |
|---|---|
| 이전 복구 시험 설치 제거 | PASS, msiexec 0, 즉시·지연 guard PASS |
| 제거 후 깨끗한 상태 Inspect | PASS |
| 새 후보 HKLM 루트 0~6 충돌 | 7 PASS, 각각 msiexec 1603으로 차단 |
| 새 후보 HKCU 루트 0 충돌 | FAIL, 기대한 차단 대신 msiexec 0 |
| 이후 보존 사례·최종 기본 설치 | NOT RUN, 첫 실패에서 중단 |

새 Suite는 08:41:48 UTC에 시작해 08:42:06 UTC에 FAIL로 중단했다. 합성 HKCU 등록은 EXACT_FIXTURE_CLEANED로 정리됐지만 제품 82A72EB8…는 이번 새 Suite의 installed-product 폴더에 남아 있다. 이전 실패 시험 설치의 제거 성공을 새 시험 설치의 제거 완료로 해석하지 않는다. 실행기는 STOPPED_FOR_REVIEW_NO_AUTOMATIC_PRODUCT_REMOVAL을 유지하고 최종 기본 위치 설치를 시도하지 않았다.

그 실행 직후에는 실제 로그의 사용자 문맥 일치, 7개 루트 검사 및 즉시·지연 guard PASS와 기대한 충돌 차단의 불일치를 조사했다. 당시 제품 guard와 시험 문맥 중 어느 쪽 원인인지 확정하지 않았고 후속 진단은 위에서 구분한다. 사용자 업무 자료 손실을 관찰한 것으로 설명하지 않는다. native·정적 PASS와 재개 성공으로 이번 Suite FAIL을 대체하지 않는다. 후보 MSI·제품 소스와 공개 안내는 그대로이며 정식 공개는 실행하지 않았다.

로컬 근거: artifacts/image-copy-save/msi-preservation-recovery/20260927T084011285Z-dc8b5daf7b314b00bdb921778f7141d0/의 launch.json·recovery.json 및 단계 로그, artifacts/image-copy-save/msi-preservation/20260927T084148973Z-ff188992c090420794dc8f3b47277316/result.json 및 fresh-HKCU-root-0.msiexec.log. 원시 SID·등록 경로 진단은 이 문서에 복사하지 않는다.

09:00 UTC 후속 진단은 UAC 승인 후 시작됐으나 native-before 결과 수집에서 중단됐다. MSI 동작은 0회, 제품 등록 변경은 없고 합성 등록은 EXACT_FIXTURE_CLEANED로 정리됐다. MSI custom action의 등록 문맥 진단은 아직 완료하지 않았으므로 이번 HKCU 실패의 원인을 확정하지 않는다. 로컬 근거: artifacts/image-copy-save/msi-preservation-development/registry-context-runs/20260927T085943091Z-e7de9c5c1fcd4f1e8584a84b378e9f31/diagnostic.json.

결과 수집을 수정한 진단 실행기는 비상승·fixture 없는 수집 확인에서 PASS했다. 이후 09:03:05 UTC 정상 UAC 요청은 09:05:07 UTC 취소로 반환돼 자식 프로세스가 시작되지 않았고 진단 MSI도 실행하지 않았다. 당시 사용자에게 가능한 재표시 시점을 물었으며 그 요청에서는 실제 custom action 진단이 미실행이었다. 이후 승인된 진단 결과는 위 최신 절에서 구분한다. 이 수집 확인을 제품 guard나 보존 Suite의 PASS로 바꾸지 않는다.

## 앞선 실제 결과 · 승인 후 복구 갱신 완료와 3010 중단

08:13:32 UTC 요청은 정상 UAC 승인을 받았고 프로세스 18256이 시작됐다. 08:14:27 UTC에 정확한 실패 시험 설치의 복구 갱신을 실행했으며, 즉시·지연 guard가 모두 PASS하고 InstallFinalize가 반환 값 1로 완료됐다. msiexec 결과는 **3010(성공, 재시작 필요 표시)**이었다. 0만 후속 진행 조건으로 허용한 실행기는 이 단계를 FAIL, 전체를 STOPPED로 기록했지만, 실제 설치가 시작되지 않았거나 1603으로 실패한 경우와 구분한다.

실제 설치 PackageCode는 기존 {E02D0EEC-5EF4-4BF1-85EF-20074416A568}에서 복구 후보의 {1ADCC104-A775-41C2-ABCC-11C1C5F601AA}로 바뀌었고 새 캐시 MSI가 등록됐다. 따라서 Service를 처음부터 반복하지 않고 이미 갱신된 정확한 시험 설치를 확인한 뒤 후속 제거 단계부터 재개하도록 준비한다. 이 실행에서 원래 시험 설치의 제거·새 보존 Suite·최종 설치는 수행하지 않았다. 3010을 재시작 요구 없는 exit 0이나 전체 수명주기 PASS로 바꾸지 않는다.

08:16 UTC 읽기 전용 사후 확인은 **404파일·23등록 값 정확 일치**, 변경 파일·추가 파일·알 수 없는 값·현재 사용자 충돌·추가 스트림·재분석 경로 0개로 PASS다. 제품 폴더와 현재 캐시를 향한 예약 작업은 없고, 이전 캐시 삭제 예약 한 건을 확인했다. 관계없는 예약 작업의 경로·내용과 사용자 SID는 이 문서나 공개 자료에 옮기지 않는다. 검증 실행기의 캐시 DB COM 객체 해제 누락을 보완했고, 이미 성공한 Service를 반복하지 않고 제거부터 진행하는 제한적 재개 절차를 아래처럼 검증했다.

공개 후보 82A72EB8…, 로컬 복구 2CFDEF33…, 짝지은 롤백 CD4CEBBD…의 파일은 아래 식별과 동일하며 이 후속 처리 때문에 다시 제작하지 않았다. 실제 보존 Suite·최종 설치·정식 공개는 아직 미완료다.

로컬 근거: artifacts/image-copy-save/msi-preservation-recovery/20260927T081319737Z-387c5de048534882b8c6b2be30b7ffef/의 launch.json·recovery.json·service-exact-failed-fixture.msiexec.log, artifacts/image-copy-save/msi-preservation-development/fixture-after-servicing3010-2026-09-27T08-16-23-755Z.json, 같은 디렉터리의 cache-pending-after3010-2026-09-27T08-17-07-329Z.json. 원시 진단 파일은 로컬에만 보존한다.

## 재개 준비 검증과 앞선 UAC 취소

COM 객체 해제 보완의 합성 MSI 파일 검사 5개가 PASS다. 반복 식별 조회, 쿼리 성공·예외 이후의 배타적 읽기 열기를 확인했으며 강제 GC·설치 캐시 열기·캐시 변경·설치·등록 변경은 하지 않았다. 당시 wrapper SHA-256은 B0AD5D5CC38EDDB31E6F1C6A6545B03E27B90AD9EFC06D7E5F3D83C3126C2703이다. 실제 캐시 잠금 원인의 단독 재현이나 MSI 수명주기 시험으로 확대하지 않는다.

완료된 3010 이력과 예약 경로를 검사하는 재개 회귀는 **27 PASS**, MSI 동작 0회·등록 쓰기 0회다. 감사한 보고서·로그 및 후보 입력의 불일치, guard 근거 누락, 미완료 설치, 제품 폴더·현재 캐시를 향한 예약 작업을 거절한다. 이미 감사한 이전 캐시 삭제 예약과 관계없는 예약 작업은 수정하지 않는다. 이 검사의 wrapper SHA-256은 **0CF8D4706E81676171237D752B0AFEF36952F7D25AC50A70DA6CBB77C89C5F91**이다. 재개 실행기와 새 회귀 도구는 로컬 커밋 bfa19302c3db51ada7945d61a18459840ca80f07에 보존했다.

08:27 UTC 실제 Inspect는 비상승·읽기 전용으로 PASS했다. 현재 복구 패키지의 404파일·23등록 값을 확인하고 serviceAlreadyCompleted=true, historicalRebootRequired=true를 유지한다. 계획은 완료된 Service를 반복하지 않고 수정 guard를 통한 시험 설치 제거 → 깨끗한 상태 확인 → 새 보존 Suite → 기본 위치 최종 설치다. 이 준비 과정은 기존 예약 목록이나 제품 등록을 수정하지 않았으며 native MSI 소스 8개와 위 후보 파일도 바꾸지 않았다.

| 준비 근거 | 로컬 기록 |
|---|---|
| COM 해제 회귀 5 PASS | artifacts/image-copy-save/msi-preservation-development/com-handle-lifetime-2026-09-27T08-20-08-646Z/result.json |
| 재개 이력·예약 경로 회귀 27 PASS | artifacts/image-copy-save/msi-preservation-development/resume-evidence-tests-2026-09-27T08-26-20-696Z.json |
| 실제 재개 Inspect PASS | artifacts/image-copy-save/msi-preservation-recovery/20260927T082711859Z-b1672f4467494cbe9a921257c854f462/inspection.json |

**앞선 Run은 08:28:59 UTC에 정상 UAC를 요청했으나 08:31:02 UTC에 취소로 반환됐다.** 상태는 ELEVATION_NOT_STARTED, 자식 processId는 null이며 recovery.json은 생성되지 않았다. 이 요청에서 제거·보존 Suite·최종 설치는 NOT RUN이었다. 이후 승인된 실제 재개는 위 최신 결과에서 구분한다. 요청 기록은 artifacts/image-copy-save/msi-preservation-recovery/20260927T082847714Z-c3418056f74a4650bf9bca88c6ea06c8/launch.json이다.

## 최신 후보 · 제품 정보 길이 처리 보완

앞선 복구 갱신에서 PackageCode 조회가 요구한 버퍼 길이는 첫 조회 32자에서 후속 조회 38자로 바뀌었다. 이 실제 사례를 재현하고 길이가 바뀌면 상한과 횟수를 제한해 다시 조회하도록 수정했다. native 회귀는 **39 PASS / 0 FAIL**이다. 합성 등록 fixture 생성·정리를 포함하며 제품 등록 변경·설치는 하지 않았다.

| 용도 | 파일·크기 | SHA-256 | 빌드 디렉터리 |
|---|---|---|---|
| 공개 대상 제품 후보 | ImageCopySave-0.2.0-x64.msi · 50,569,176 bytes | 82A72EB85F41D6DF29BC94EE57215991BA41BEF542717D81CCC0C850C5F5134B | artifacts/image-copy-save/msi/20260927T073556974Z-50f91399f1a740a98e502e6c8f35f1c7 |
| 로컬 전용 복구 갱신 | ImageCopySave-0.2.0-x64.msi · 50,589,848 bytes | 2CFDEF33340E6057F166F3769CA2BED7BE28D6F4F5581D03C10A362C290DCE56 | artifacts/image-copy-save/msi/20260927T073840180Z-d9c9b2cdd2684e16bdec6147c76cb9e2 |
| 제품 후보와 짝지은 고의 실패 롤백 | ImageCopySave-0.2.1-x64-ROLLBACK-TEST.msi · 50,589,868 bytes | CD4CEBBDC367659923E1C79F8D0ECA285DF75557F7DF7B373909E94BBC5534F2 | artifacts/image-copy-save/msi/20260927T073923904Z-005540799ba948729ba7c4ea190900c1 |

세 패키지의 build-metadata.json·verification.json은 제작 및 정적 검사 PASS다. 각각 무서명·자체 포함 404파일·guard schema 2·실행형 검사 CA 2개를 확인했다. 복구/롤백 후보는 해당 허용 옵션을 지정한 로컬 시험 파일이며 공개 자산이 아니다. 각 guard/build-metadata.json의 native 결과는 39 PASS다.

제품 빌드 디렉터리의 source-payload-verification.json은 07:40:18 UTC에 기존 사용자 확인을 받은 런타임 404파일의 동일성과 설치 소스 해시 8개의 일치를 확인했다. 이 결과를 실제 새 MSI 설치나 사용자 화면 시험으로 바꾸지 않는다.

artifacts/image-copy-save/guard-packagecode-sizing-20260927-verified/의 actual-installed-readonly-probe.log·full-recovery-readonly-probe.log에서 실제 설치 PackageCode 조회, 404파일·23등록 값의 소유 확인, 전체 복구 Prepare·현재 사용자 검사·지연 계획 검사를 확인했다. 새 복구 후보 빌드 디렉터리의 full-recovery-readonly-probe.log도 PASS다. MsiOpenPackageEx의 IGNOREMACHINESTATE로 제한한 핸들을 사용하는 읽기 전용 검사이며 installerActionsRun=false, productRegistrationModified=false다. 정상 MSI 동작의 실제 인수를 대신하지 않는다.

앞선 실제 Run 요청은 07:42:11 UTC에 정상 UAC를 요청했으나 07:44:14 UTC에 Windows가 취소를 반환했다. artifacts/image-copy-save/msi-preservation-recovery/20260927T074158463Z-9b8bd542b99347d08278bf5172d6ae49/launch.json의 상태는 ELEVATION_NOT_STARTED, processId는 null이다. 그 요청에서는 복구 갱신·제거·보존 Suite·최종 설치가 시작되지 않았으며, 이후 승인된 실제 복구 갱신은 위 최신 결과와 구분한다. 정식 Release와 공개 자산 게시는 여전히 미완료다.

## 변경한 범위

MSI 안에 정적으로 링크한 native 검사 DLL과 파일별 SHA-256 소유 목록을 넣었다. PC 전체 HKLM과 설치를 실행한 사용자 HKCU의 두 COM 루트·다섯 메뉴 루트 및 기존 설치 폴더의 충돌을 검사하고, 동일 패키지 유지보수에서는 현재 설치 DB와, 이전 패키지 갱신에서는 새 MSI에 내장한 감사된 이전 소유 목록과 비교한다. 파일 본문 변경, 추가 NTFS 스트림, 재분석 지점·하드 링크, 알려진 등록 값·형식 변경은 보존하고 중단하는 대상이다. 추가한 파일이나 알 수 없는 값은 제거 대상으로 추가하지 않는다. 과거 0.1.1의 자동 이행은 검증한 ProductCode·PackageCode·404파일 해시에 고정한다.

읽기 전용 즉시 검사와 지연 검사를 추가했으며 실제 파일·등록 쓰기와 롤백은 Windows Installer가 수행한다. 마지막 검사 이후 임의의 관리자 프로그램이 동시에 바꾸는 자원까지 원자적으로 보존한다고 약속하지 않는다. 초기 업그레이드 제거 순서와 동시 관리자 변경 경계는 ADR-0024를 따른다. 일반 사용자에게 수동 등록·레지스트리 편집·스크립트 실행을 요구하지 않는다.

이미지 엔진·helper·메뉴 런타임은 이번 MSI 보존 보완의 변경 대상이 아니다. 기존 PASS를 새 시험으로 합산하지 않고 아래 범위로 재사용한다. 05:35 UTC에 제작한 앞선 후보의 404개 런타임 파일을 실제 사용자 확인을 받은 0.1.1의 고정 목록과 대조해 모든 경로·SHA-256이 동일함을 확인했다. 당시 설치 소스 7개의 SHA-256도 해당 빌드 메타데이터와 모두 일치했다. 이후 아래 설치 API 보완으로 설치 소스가 변경됐으므로 이 일치 판정을 후속 후보에 그대로 적용하지 않는다.

## 앞선 복구 중단과 설치 API 보완 이력

06:57 UTC 후속 Run은 정상 UAC 승인 후 자식 프로세스가 실제로 시작됐다. 실패 시험 설치의 404개 파일·23개 등록 값을 다시 확인한 뒤, 원래 DE666CC6 후보 MSI로 정확한 시험 설치만 제거하려 했으나 ImageGuardPreflight에서 “Cannot establish installed component ownership”로 1603을 반환했다. InstallInitialize와 파일·등록 제거 작업 전에 중단됐고, 후속 깨끗한 상태 검사·새 보존 Suite·최종 설치는 실행하지 않았다. 이는 앞선 UAC 취소와 다른 실제 실행 실패다. 기록은 artifacts/image-copy-save/msi-preservation-recovery/20260927T065702167Z-66de6881b4a441d2a6db04ab0dae1d33/의 launch.json·recovery.json·fixture-remove.msiexec.log다.

읽기 전용 조회에서 해당 제품의 MsiGetComponentPathExW는 CA 밖에서도 404개 모두 UNKNOWN(-1), 길이 인수 32768 유지, 빈 경로를 반환했다. 명시적 MACHINE 문맥의 MsiQueryComponentStateW는 404개 모두 LOCAL(3), MsiGetComponentPathW는 404개 모두 LOCAL(3)과 정확한 경로를 반환했다. 관계없는 제품 세 개의 대표 컴포넌트에서도 같은 차이를 확인했다. 경로 길이·CA 내부 문맥만의 문제나 Windows 자체 결함이 확정됐다고 설명하지 않는다.

수정한 schema 2 guard는 PC 전체 제품·컴포넌트 등록을 명시적으로 확인한 뒤 기존 경로 API와 경로/길이 검사를 결합한다. Microsoft가 CA에서 금지한 MsiOpenDatabase 호출도 제거한다. 동일 패키지는 현재 설치 DB를, 이전 패키지는 빌드 때 읽기 전용으로 추출해 새 MSI에 내장한 ProductCode·PackageCode별 소유 목록을 사용한다. [ADR-0024](../design/0024-image-msi-preservation.md)에 공식 API 근거와 보존 경계를 반영했다.

[추출기](../../tools/ImageCopySave/installer/export-ownership-baseline.ps1)는 0.1.1 및 DE666CC6 후보에서 각각 404개 파일·23개 REG_SZ 값을 내보냈다. 두 목록의 파일 경로/컴포넌트 GUID와 등록 값이 정확히 일치했다. 잘못된 MSI 감사 해시·파일 크기·참조 컴포넌트 GUID 세 입력은 거절했고 기존 출력은 보존했다. 저장소의 0.1.1 schema 2 목록과 로컬 전용 DE666CC6 목록을 구분하며, 감사 결과는 artifacts/image-copy-save/ownership-baselines/20260927T071405882Z-fe3b93ecf8dc461aac103884bbc26e79/export-audit.json에 보존한다. 설치·제품 등록 변경은 하지 않았다.

구형 guard가 제거를 막는 이 정확한 로컬 시험 설치를 위해, 이전 PackageCode를 고정하고 보존 검사를 유지하는 same-ProductCode small update 복구 후보를 별도로 제작했다. 일반 공개 후보·고의 실패 롤백 후보와 구분한다. 복구 후보의 제작·정적 검사는 PASS지만 실제 복구 갱신은 아래처럼 중단했으며, 보존 Suite·최종 설치·공개 게시는 미완료다.

07:28:19 UTC 요청은 정상 UAC 승인 후 프로세스 17576을 시작했고, 07:29:13 UTC에 service-exact-failed-fixture 단계를 실행했다. 사용한 로컬 복구 MSI의 SHA-256은 C82B8B850F8C0EA41019826D9D664DC17808E11F02B948064DF025A3955EAA84, PackageCode는 {56B1E94C-6580-4C27-84BA-F0F1A9E2D181}이다. 시작 전 기존 후보의 원래 PackageCode와 404파일·23등록 값은 일치했다. 그러나 ImageGuardPreflight가 “Cannot inspect installed product”로 1603을 반환해 InstallInitialize 이전에 중단됐다. 이전 06:57 제거의 컴포넌트 경로 오류와 다른 단계이며, 당시 제품 정보 두 번째 API 조회를 진단했고, 이후 확인한 길이 변경과 수정 결과는 위 최신 후보 절에서 구분한다. 기존 시험 설치는 제거되지 않았고 새 보존 Suite와 최종 설치는 실행하지 않았다. 실제 실행 기록은 artifacts/image-copy-save/msi-preservation-recovery/20260927T072806286Z-7b882eeca6ea40a48502100b8ab108bf/의 launch.json·recovery.json·service-exact-failed-fixture.msiexec.log에 보존한다.

## 앞선 사용자 등록 검사 보완과 05:35 재제작 후보

첫 실제 MSI 시험의 HKCU 차단 누락 이후 사용자 문맥 확인을 강화했다. 즉시 작업에서 실행 토큰 SID와 Windows Installer의 UserSID가 일치해야 하며, RegOpenCurrentUser로 연 실제 사용자 등록 경로와 캡처한 SID에 대응하는 Classes hive 경로를 독립적으로 검사한다. 지연 작업에서도 Windows Installer UserSID가 전달한 사용자와 일치하는지 확인한 뒤 같은 사용자 범위를 검사한다. 문맥이나 hive 확인에 실패하면 허용으로 추정하지 않고 중단한다.

정상 HKCU Software\Classes는 운영체제가 관리하는 링크이므로 그 앵커와 아래 제품 소유 경로를 구분한다. 즉시·지연 단계의 사용자 문맥과 검사 루트 진단을 로컬 MSI 로그에 남긴다. 첫 실패의 정확한 Windows Installer 실행 문맥 차이는 아직 실제 재시험으로 입증하지 않았으므로 “SID 불일치가 확정 원인”이라고 단정하지 않는다. 수정 코드를 작성하고 단위검사를 통과한 사실과 실제 MSI에서 누락이 해소됐다는 판정은 별개다.

| 항목 | 재제작 후보와 실제 확인 |
|---|---|
| 제품 MSI | ImageCopySave-0.2.0-x64.msi, 50,537,248 bytes |
| 제품 SHA-256 | FDCD4201BB59E95B3513F2BD6849A80CDD2B7B986FF49297184DBDAED6F17159 |
| 제품 빌드 디렉터리 | artifacts/image-copy-save/msi/20260927T053516844Z-e9869cce2b8343e1a513c57da0dd3852 |
| 롤백 시험 MSI | ImageCopySave-0.2.1-x64-ROLLBACK-TEST.msi, 50,537,264 bytes. 공개 대상 아님 |
| 롤백 SHA-256 | F71BF7B8A98222B79468D42CA0FFC110A3C9563A0E7C07840A4CDCCBF9061885 |
| 롤백 빌드 디렉터리 | artifacts/image-copy-save/msi/20260927T053607328Z-b09fa73902d944d68d72d27d23b30613 |
| 소스·페이로드 | 두 파일의 설치 소스 해시 7개 일치, 자체 포함 404파일 인벤토리 일치 |
| Guard.cpp SHA-256 | DBC3CE9136D537CC29E4B99686D51594823FEF324F4D08652A008AF6CFAF1BE5 |
| native 보호 회귀 | 26 PASS / 0 FAIL. 별도 합성 레지스트리 fixture 생성·정리 확인, 제품 등록 변경·설치 없음 |
| 제품·롤백 MSI 정적 검사 | 둘 다 PASS. 롤백 파일은 AllowRollbackTest를 명시한 검사이며 고의 실패 파일임을 유지 |
| 첫 실패 설치의 복구 Inspect | PASS. 기존 후보 404파일·23등록 값 정확 일치, 알 수 없는 파일/값·현재 사용자 충돌·이름 있는 스트림·재분석 경로 0개 |
| 해당 후보 실제 보존 Suite·최종 설치 | NOT RUN: 첫 요청은 UAC 취소, 후속 승인된 Run은 원래 시험 설치 제거의 guard 오류 1603에서 중단. Inspect·정적·native PASS를 실제 Suite PASS로 승격하지 않음 |

26개 native 시험은 합성 사용자 등록을 실제로 만들고 정리하므로 registryModified=false로 설명하지 않는다. 기록의 registryFixtureCreated=true, registryFixtureCleaned=true, productRegistrationModified=false, installed=false를 구분한다. 실제 제품 MSI는 여전히 파일·등록 쓰기를 Windows Installer에 맡기는 읽기 전용 검사를 사용한다.

복구 Inspect는 2026-09-27 05:39 UTC에 비상승으로 실행했다. 계획한 후속 순서는 정확히 일치하는 실패 시험 설치만 그 원래 MSI로 제거 → 깨끗한 설치 상태 확인 → 수정한 보존 Suite → 기본 위치 최종 설치다. 후속 Run은 05:40:57 UTC에 정상 UAC를 요청했으나 05:43:00 UTC에 Windows가 취소 결과를 반환했다. ELEVATION_NOT_STARTED이며 자식 프로세스 ID가 없고 제거·설치 단계는 실행되지 않았다. 이 첫 시도의 기록은 artifacts/image-copy-save/msi-preservation-recovery/20260927T054050047Z-c68d56cb99ef448086349c7a2251bb7c/launch.json에 보존하며, 06:57 UTC 승인된 실제 후속 실행과 구분한다.


등록 충돌 시험기 자체의 정리 경계도 보완했다. 생성 전 소유 정보를 기록하고 등록 생성·읽기 확인·MSI 호출을 하나의 try/finally에 포함했다. 읽기 확인 실패, 호출 실패, 추가 외부 값 보존, 외부에서 바꾼 시험 값 보존의 합성 HKCU 회귀 4개가 PASS다. 제품 등록과 MSI 설치는 실행하지 않았다. 결과와 실제 시험 소스 해시는 artifacts/image-copy-save/msi-preservation-development/registry-fixtures-result.json에 저장했다. 실행 UTC는 기록하지 않아 추정하지 않았으며 결과 저장 시각과 구분했다. 이 시험기 변경으로 다음 Run은 입력 해시를 다시 고정한다.

## 첫 0.2.0 후보 식별

이 표는 HKCU 충돌 차단 실패가 발견된 **첫 후보**다. 최종 공개 파일의 식별 정보로 사용하지 않는다.

| 항목 | 기록 |
|---|---|
| 파일 | ImageCopySave-0.2.0-x64.msi |
| 크기 | 50,529,056 bytes |
| SHA-256 | DE666CC6115E0A459EFD1F75EBE6760EA58DA09E10E02CC669470E69AD41B092 |
| ProductCode | {589202C2-9A92-0BAE-E0A7-AEF17B34DF91} |
| 로컬 빌드 디렉터리 | artifacts/image-copy-save/msi/20260927T051022819Z-5960212b27ee44459203e8df016d0d77 |
| 정적 패키지 검사 | PASS: 무서명·PC 전체 x64·자체 포함 404파일·내장 CAB 1개·COM 2개/메뉴 5개·실행형 검사 CA 2개·Explorer 자동 종료 비활성 |
| native 보호 회귀 | 24 PASS / 0 FAIL. 실제 MSI 설치·등록 시험과 구분 |
| 시험 자료 보존 도우미 | 합성 primitive 6개 PASS. 실제 MSI 충돌 검증과 구분 |

별도 고의 실패 파일 ImageCopySave-0.2.1-x64-ROLLBACK-TEST.msi는 50,529,072 bytes, SHA-256 E25155D3360CB07AEC20A4D19CB57B8F5DB27A52218E08276F2DE31AA96DBFD5다. 같은 설치 소스 해시·페이로드로 제작하고 허용 옵션을 지정한 정적 검사는 PASS다. 이 파일은 공개 자산이 아니며 첫 후보와 같은 보호 코드이므로 수정 후 롤백 검증의 근거로 사용할 수 없다.

## 실제 첫 순차 실행 결과

| 단계 | 결과 | 실제 의미 |
|---|---|---|
| 0.1.1 → 첫 0.2.0 업그레이드 | PASS, msiexec 0 | 일반 설치 위치에서 새 제품·등록 확인, 합성 PNG 해시 유지 |
| 첫 0.2.0 제거 | PASS, msiexec 0 | 제품 설치 상태 false, 제품 등록 0개, 합성 PNG 해시 유지 |
| HKLM 기존 루트 0~6 충돌 | 7 PASS, 각 msiexec 1603 | 동일 이름의 COM·메뉴 합성 등록에서 설치 거절 확인 |
| HKCU 기존 루트 0 충돌 | FAIL, msiexec 0 | 예상한 보호 거절이 발생하지 않아 시험 전용 폴더에 첫 후보가 설치됨 |
| 이후 보존 회귀·새 롤백 시험 | NOT RUN | 첫 실패에서 중단. 미실행 항목을 PASS로 계산하지 않음 |

업그레이드·제거에서 재부팅 요구와 Explorer 재시작은 없었다. HKCU 실패는 기존 사용자 등록 충돌을 놓친 **차단 누락**이다. 이를 실제 사용자 업무 자료 손실을 관찰한 것으로 설명하지 않는다. 시험기는 STOPPED_FOR_REVIEW_NO_AUTOMATIC_PRODUCT_REMOVAL로 중단했고, 당시 전용 시험 폴더에 남은 제품 상태를 기록했다. 현재 설치 상태는 후속 정리·재실행 결과로 별도 확인해야 하며 자동 정리 완료로 표시하지 않는다.

첫 후보 이후 사용자 문맥 검사를 보완하고 위 새 후보를 제작했다. 첫 후보의 구조·native PASS는 실제 HKCU 통합 실패를 취소하지 않으며, 위 새 후보의 실제 회귀가 통과하기 전에는 최종 보존 인수를 대신하지 않는다.

## 재사용하는 기존 런타임 근거

- 엔진/helper 최신 현재 사용자 시험 85 PASS / 1 NOT RUN(일회용 CI 전용 디스크 부족), 실제 클립보드 23개 PASS, native 정책·직접 COM 66개 PASS를 당시 소스·환경의 결과로 유지한다.
- 그림판의 helper 종료 후 붙여넣기와 그림판 복사 → PNG 저장 대표 결과를 유지한다. 모든 외부 앱·투명도 보장을 뜻하지 않는다.
- 클래식 직접 표시 상태 전환 15회·46관찰과 0.1.1 대표 PNG 복사·저장을 유지한다. 16~20회는 사용자 지시에 따라 생략했으며 필수 잔여가 아니다.
- Windows 11 기본 메뉴 경로의 두 기능은 사용자가 “기본 메뉴 경로에서 두 기능 모두 정상”이라고 직접 확인했다. 사용자 확인 PASS이며 자동화·모든 조건별 숨김·창/탭 검증으로 확대하지 않는다.
- [0.1.1 당시 MSI 수명주기](image-classic-msi-20260927.md)는 당시 후보의 PASS다. 새 보호 기능의 전체 실기로 합산하지 않는다.

기존 UI 자동화는 창 활성화 오류로 중단한 이력이 있다. 과거 일시적인 Explorer 응답 없음은 자체 회복했으나 원인은 미확정이다. 새 자료 없이 제품 무관이나 자동화만의 문제로 결론내리지 않는다.

## 최종 인수·게시 전 채울 항목

1. 설치 API·감사 목록 방식을 반영한 새 복구/제품/롤백 후보의 제작·식별·정적 검사는 완료했다. 복구 갱신과 이전 시험 설치 제거는 완료했으나 새 Suite에서 HKCU 차단 실패가 재발했다. 호스트의 HKCU 시험 데이터 격리를 확인했고 외부 전체 Suite 32개를 통과했다. 기본 위치 최종 설치도 별도 실제 결과로 PASS를 확인했으며 공개 Release 자산 검증은 완료했으며 Pages 결과는 아직 확인 전이다.
2. 실제 보존 시험의 완료 범위와 수치는 위 32개 결과를 따른다. 미실행 GUI·다른 OS/앱 검증으로 확대하지 않는다.
3. 최종 설치본의 대표 복사·저장은 위 GUI 확인으로 PASS다. 저장 후 최종 행 선택은 NOT_CONFIRMED이며 기존 기본 메뉴 사용자 확인과 런타임 결과를 별도로 재사용한다. 조건별 메뉴·창/탭·오류/취소의 미관찰 항목은 NOT RUN으로 유지하고 원래 AT 목록 전체를 이번 수정의 새 반복 관문으로 만들지 않는다.
4. 공개용 릴리스 설명·지원 제한과 Release 자산 검증은 완료했다. 태그/소스 커밋·Release URL·draft/prerelease 상태·게시 시각은 위 게시 기록을 따른다.
5. 최종 공개 안내의 배포 준비 문구 교체, MkDocs strict·공개 목록 검사·Pages Actions·실제 공개 URL/검색/자산 확인.

Windows 10·ARM64·네트워크/가상 위치와 모든 Office·메일·메신저를 이번 Windows 11 로컬 지원 결과에 포함하지 않는다. 새 MSI 보존 회귀가 미완료인 상태를 제한사항 문구만으로 통과 처리하지 않는다. 기존 사용자 확인과 실제 런타임 근거를 보존하며, 확인하지 않은 GUI 항목을 전체 G0·44개 AT 완료로 표기하지 않는다.

## 로컬 증거와 공개 경계

원시 MSI 로그·사용자 SID·개인 경로·설치 상태 덤프는 공개 자산이나 Pages에 포함하지 않는다. 아래는 개발 검증자가 같은 작업본에서 찾을 상대 경로다.

- 재제작 후보: 위 두 새 빌드 디렉터리의 build-metadata.json, guard/build-metadata.json, 패키지 검사 출력.
- 복구 사전 확인: artifacts/image-copy-save/msi-preservation-recovery/20260927T053939025Z-f32a6f10489d479b913ccca6cad77586/inspection.json.
- 승인된 복구의 제거 실패: artifacts/image-copy-save/msi-preservation-recovery/20260927T065702167Z-66de6881b4a441d2a6db04ab0dae1d33/recovery.json.
- 제품 컴포넌트 API 비교: artifacts/image-copy-save/msi-preservation-development/component-api-readonly.json.
- 관계없는 제품 대표 조회 비교: artifacts/image-copy-save/msi-preservation-development/reference-component-api-2026-09-27T07-09-43-713Z.json.
- 첫 후보: 첫 후보 빌드 디렉터리의 build-metadata.json, guard/build-metadata.json, 패키지 검사 출력.
- 업그레이드: artifacts/image-copy-save/msi-lifecycle/20260927T052035232Z-b48b0bdc9faf4a769b846f7883c4b56f/result.json.
- 제거: artifacts/image-copy-save/msi-lifecycle/20260927T052144635Z-e492c8c85dcf455b983b259f825c749c/result.json.
- 첫 보존 회귀: artifacts/image-copy-save/msi-preservation/20260927T052216347Z-8954dc8580064f7f835ca261a92af07a/result.json 및 사례별 MSI 로그.
- 첫 후보 롤백 파일 구조: artifacts/image-copy-save/msi/20260927T051434216Z-732db584d2a54f4b90f7e965e82890f3/verification.json.
- 재제작 후보 롤백 파일 구조: artifacts/image-copy-save/msi/20260927T053607328Z-b09fa73902d944d68d72d27d23b30613/verification.json.
- 공개 안내 초안 검사: artifacts/image-public-guide-20260927/site. MkDocs strict 및 공개 20페이지+404·검색·사이트맵·로컬 링크 검사는 PASS이며 제품 인수를 뜻하지 않는다.
- 최신 문서 검사: artifacts/release-readiness-20260927/docs-schema2-final-candidate/verification.json. 07:48 UTC 기준 MkDocs strict, 공개 20페이지+404, 로컬 링크·자산, 검색·사이트맵 공개 범위, 비공개 원본·자산 제외 검사가 PASS다. 실제 Release 게시나 MSI 보존 인수를 뜻하지 않는다.

공개 범위에는 사용자 [설치·사용 안내](../tools/image-copy-save/guide.md)만 추가한다. 최종 배포용 설명은 로컬 artifacts/release-readiness-20260927/image-020-release-draft/에 준비하며 게시 전 검토 문구·미확정 필드는 제거하거나 실제 결과로 채운다.
