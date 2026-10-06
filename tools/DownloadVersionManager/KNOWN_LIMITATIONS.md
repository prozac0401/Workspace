# DownloadVersionManager · 남은 제한

## 0.2.1 정식 배포 기준 · 2026-10-06

사용자가 검증된 정상 0.2.1의 정식 Release와 Pages 게시를 승인했습니다. 배포 파일은 `DownloadVersionManager-Watcher-0.2.1-x64.msi`와 `SHA256SUMS.txt` 두 개이며 이미 시험한 정상 MSI를 그대로 재사용합니다. MSI SHA-256은 `0feea2fc119bad780da9dcb57d2a0303ef0e2e0c6f6a20a746fd3ab3f86a0ef5`입니다. 실패 기능은 없으며 시험 MSI·개인 진단·백업은 배포하지 않습니다.

[정식 Release](https://github.com/prozac0401/Workspace/releases/tag/download-version-manager-v0.2.1) · [설치·사용 안내](https://prozac0401.github.io/Workspace/tools/download-version-manager/) · [이번 게시 기록](../../docs/delivery/download-version-manager-guide-update-20261006.md)

설치기의 필요한 관리자 승인은 사용자가 직접 허용하며 현재 사용자 설치와 일반 권한 앱 실행을 유지합니다. 현재 Windows 11 x64 한 PC에서 취소·대표 후반 실패 뒤 자동 복구·정상 재설치·실행·종료·제거를 확인했습니다. 코드 서명과 조직 도입 승인은 별도입니다. 소스·자동 검사·실제 Release 자산·Pages 게시 확인은 이번 PR 본문에 기록합니다.

아래의 준비 완료·게시 미실행·과거 FAIL/NOT RUN 문구는 각 기록 시점의 결과로 보존합니다. 이번 배포의 자산과 다른 버전·미래 CI 재빌드 파일을 혼동하지 않습니다.

**최신 로컬 0.2.1 상태(2026-10-06 KST): 최종 정상 MSI의 두 취소·동등 payload 후반 실패 자동 복구·정상 재설치·일반 권한 실행/종료·제거·원래 설정 복원이 PASS입니다.** 확인 범위는 현재 Windows 11 x64 한 PC이며 무서명·조직 도입/상용 승인 미결정·다른 환경과 실제 CI 미검증은 남습니다. 새 공개 게시는 실행하지 않았으며 과거 FAIL/NOTRUN은 당시 기록으로 보존합니다.

## 0.2.0 폴더 감시 · 2026-10-04

- **무서명 기능 평가 prerelease를 게시했습니다.** 회사의 도입·상용 승인이나 모든 설치 실패 복구를 인증한 정식판으로 분류하지 않습니다.
- 초기 대상은 Windows 11 x64의 고정 로컬 NTFS 폴더 한 곳입니다. 하위 폴더·UNC·네트워크·ReFS·FAT·reparse/클라우드 연결·ARM64·모든 기업 정책은 지원하지 않습니다. hardlink·암호화·offline·읽기 전용 파일은 파일 처리 엔진이 보수적으로 거절합니다.
- 새 번호 파일과 원래 대상의 연결은 사용자가 채택한 이름 관례입니다. 원래부터 `파일 (1).ext`인 별개 파일도 `파일.ext`가 있으면 처리될 수 있습니다. 앱의 실제 다운로드 출처·의도는 알 수 없습니다. 원래 대상이 없으면 보존합니다.
- 3초 안정과 보호된 파일 핸들 확보는 처리 가능 조건이며 앱 내부 완료의 증명이 아닙니다. 긴 쓰기 중단·완료 이후 재개와 기존 파일 직접 덮어쓰기의 이전 바이트 보존은 보장하지 않습니다.
- 같은 원래 대상의 신규 후보가 함께 대기하면 모두 보존하고 해당 감시 세션의 자동 처리를 보류합니다. 번호·mtime·알림 시각을 기준으로 임의 최신 선택을 하지 않습니다. 최초 기존 그룹의 최신본과 전체 처리 순서는 사용자가 직접 확인합니다.
- OS 변경 알림 누락이나 후보 한도 초과 시 감시를 중지하고 보존합니다. 시작 전·중단 중 들어온 파일을 재생하거나 자동 일괄 정리하지 않습니다. 기본 다운로드 위치가 바뀌면 새 위치의 최초 이름 그룹 확인이 필요할 수 있습니다.
- 두 이름 변경은 한 파일시스템 트랜잭션이 아닙니다. 일반 실패는 rollback을 시도하며 강제 종료·전원 장애의 자동 복구와 잔재 스캔은 없습니다. `_history` 또는 `.dvm-…pending`에 남은 파일을 직접 확인합니다. 정전 durability는 미검증입니다.
- 바이트 비교는 기본 데이터 스트림의 SHA-256입니다. ADS·ACL·Office/PDF 의미를 비교하지 않습니다. 파일명에 timestamp를 붙여 NTFS 이름 한도를 넘으면 보존하고 중단합니다. History 충돌 후보 10,000개와 mutex 대기 30초는 기존 엔진 한도입니다.
- 브라우저/웹 프로그램의 다운로드 목록은 이동 전 이름을 가리킬 수 있습니다. 최종 파일은 감시 폴더에서 확인합니다. 구버전 0.1.0 확장과 같은 폴더에서 함께 실행하지 않습니다.
- **0.2.0 설치 실패 복구 제한:** 현재 Windows 11에서 InstallExecute 이후 의도적 실패를 주입하자 Windows Installer 제품 등록이 남고 registry rollback의 access denied(5)가 다시 관찰됐습니다. 시험으로 만든 제품은 공식 Windows Installer 제거로 정리됐고 사용자 파일을 보존했습니다. 수정 후보의 정상 설치·실행·repair·제거·파일 보존 5개와 화면 높이 수정 후보의 설치·실행·제거·보존 4개는 성공했습니다. 최종 안내 문구·표준 MSI 폴더 선택 변경에는 관련 설치 근거를 재사용했고 선택 경로 표시·설정 전달·취소만 별도 확인했습니다. 새 MSI 식별자만으로 0.1.0 실패가 해결됐다고 판단하지 않습니다.
- 로그인 자동 실행은 설치 시 기본 선택이며 위자드에서 해제할 수 있습니다. 프로그램을 종료하면 현재 감시는 끝나며 자동 실행을 유지했다면 다음 로그인에서 다시 시작합니다. 서비스·tray·자동 업데이트·telemetry·클라우드 전송·restore UI는 없습니다.

실제 완료 결과는 [TEST_RESULTS](TEST_RESULTS.md)를 기준으로 합니다. 이전 0.1.0의 결과는 아래에 당시 표현 그대로 보존합니다.

## 0.1.0 평가 버전의 역사적 제한

- **stable 배포 차단:** Chrome Web Store/Edge Add-ons 게시 ID·스토어 활성화·단일 배포 검증 미완료. 일반 unmanaged Windows의 Chrome은 로컬 CRX 자동 설치를 허용하지 않고 스토어 외부 설치에도 사용자가 활성화를 승인해야 합니다. 평가 MSI의 공식 개발용 불러오기는 사용자 작업이 필요합니다. 완전 자동 단일 설치 요구 PASS가 아닙니다.
- 초기 지원 후보는 Windows 11 x64의 고정 로컬 NTFS와 Chrome/Edge 현재 다운로드 이벤트입니다. Windows 10·ARM64·모든 기업 정책·UNC·네트워크·ReFS·FAT·reparse/클라우드 경로·대소문자 구분 디렉터리는 지원 인증하지 않습니다. hardlink·암호화·offline·읽기 전용 파일도 보수적으로 거절합니다.
- 저장 대화상자에서 다른 parent를 고르는 경우는 실제 저장 parent를 사용합니다. 원래 이름과 다른 basename 선택은 보존하고 처리하지 않습니다. 사용자가 브라우저의 덮어쓰기를 직접 승인한 경우 이미 잃은 이전 파일을 복원할 수 없습니다. 파일 이름을 변경하는 다른 확장과 함께 사용하지 마세요.
- 기존 `(1)` 파일 일괄 정리·Explorer 복사·Outlook/Teams 직접 감시·재귀 스캔·semantic diff·클라우드 업로드·restore UI·버전 브라우저·tray·자동 업데이트·telemetry는 없습니다.
- 같은 target은 mutex로 직렬화하고 완료 시각·file ID의 최소 HKCU 기록으로 지연된 이전 요청이 최신본을 바꾸지 않도록 합니다. 실제 Chrome/Edge `endTime` 계약은 NOT RUN입니다. 같은 millisecond에 완료된 서로 다른 다운로드는 선후를 추측하지 않고 둘 다 보존합니다. 시계 역행을 복원하는 기능은 없습니다.
- HKCU의 target별 138-byte 순서 기록은 제거·재설치 뒤에도 보존합니다. 대상 경로 hash·완료 시각·객체 ID·임의 식별자만 있는 기능 상태이며 내용/hash/URL/경로 원문·성공 로그를 저장하지 않습니다. 상태 손상·미래 schema·외부 교체로 순서를 확인할 수 없으면 파일을 보존하고 중단합니다. registry와 파일의 정전 동시 durability는 미검증입니다.
- 두 이름 변경은 하나의 파일시스템 트랜잭션이 아닙니다. 일반 실패는 rollback을 시도합니다. 강제 종료·전원 장애의 자동 복구나 잔재 스캔은 없으며 이전·신규 객체를 보존한 위치에서 수동 확인해야 합니다. 전원 차단 durability는 미검증입니다.
- 내용이 같으면 파일 전체 기본 데이터 스트림의 SHA-256을 비교합니다. ADS·ACL·Office 의미·PDF 표현 비교는 하지 않습니다. 신규 객체의 ADS와 속성은 복사하지 않고 그 객체 자체를 이름 이동합니다.
- timestamp 추가로 NTFS 파일 이름 길이를 넘으면 기존·신규 파일을 보존하고 중단합니다. History 이름 후보는 10,000개, mutex 대기는 30초입니다. 자동 background retry는 없습니다.
- 브라우저 다운로드 목록의 경로는 이름 이동 전의 suffix 경로를 가리킬 수 있습니다. 확장은 브라우저 기록을 조작하지 않습니다. 최종 파일은 선택한 폴더에서 확인하세요.
- 서명 없는 평가 MSI입니다. 실제 시험의 PASS/FAIL/NOT RUN 범위는 [TEST_RESULTS](TEST_RESULTS.md)를 기준으로 하며 다른 도구의 검증을 승계하지 않습니다.
- **설치 실패 복구 관문 FAIL:** 이 Windows 11 환경에서 제품 게시 후 deferred 실패와 InstallExecute 후 immediate 실패를 각각 시험했습니다. 파일·Native Host 등록은 되돌아갔지만 MSI 제품 등록이 남았고 바로 재설치는 1638로 실패했습니다. rollback 로그의 registry 작업에 access denied(5)가 있습니다. 공식 MSI 제거 뒤 재설치·제거는 성공했고 시험 등록을 정리했습니다. 제품 게시 전 실패 PASS를 이 두 실패의 해결로 간주하지 않습니다. 다른 깨끗한 Windows와 CI 비교는 별도 검증이며 OS registry 권한이나 Windows Installer 내부 등록을 임의 수정하지 않습니다.

공식 근거 (2026-09-30 확인): [Chrome 외부 설치](https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions), [Chrome 정책 설치](https://support.google.com/chrome/a/answer/7532015?hl=en), [Edge 외부 배포](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/alternate-distribution-options), [Edge Native Messaging와 스토어 ID 차이](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/native-messaging).

## 2026-10-04 후속 읽기 진단 보충 (로컬 미게시)

과거 0.2.0 late-failure의 원시 MSI를 확인했으며 최종 공개 MSI와 File·CAB·config DLL·custom action이 다르다. 실패 주입 파일 PackageCode는 당시 로그와 일치하지만 최종 공개 MSI의 직접 실패 주입 결과가 아니다. 초기 후보의 registry rollback access denied(5)와 Run 키 보안 문맥의 시스템 오류 1307, 제품 등록 잔류 FAIL은 그대로 유지한다. 정확한 token·before/after 보안 상태가 없으므로 패키지 작성 또는 Windows 프로필/권한 중 근본 원인은 아직 미확정이다.

설치 실패 원상복귀는 기본 안전 요건이며 평가판 제한으로 면제되지 않는다. 후속 trial 도구의 판정·패키지 연결·전용 snapshot 환경 gate를 보완했지만 제품 rollback 수정과 Windows 설치 복구 PASS는 없다. 승인된 전용 시험 환경 없이 실사용 계정에서 반복 실패 주입하지 않는다. 실제 계정의 ACL/owner·Windows Installer 등록을 수동 수정하거나 관리자 재시도로 문제를 우회하지 않는다. 새 증거는 [TEST_RESULTS](TEST_RESULTS.md)의 후속 기록에만 추가했으며 과거 0.1.0/0.2.0 FAIL과 NOT RUN은 보존한다.

## 2026-10-05 로컬 트레이 수정본의 적용 범위

위 0.1.0·0.2.0과 설치 읽기 진단의 제한은 당시 기록 그대로 보존한다. 과거의 ‘tray 없음’은 해당 공개 버전의 설명이다. 이번 로컬 수정본은 감시 창의 X·Alt+F4로 창을 숨기고 트레이의 열기·더블클릭으로 같은 창을 복원하며, 트레이 종료에서 실제로 감시·프로세스를 끝내는 후속 변경이다. 공개 0.2.0 MSI와 현재 설치본에는 반영하지 않는다. 감시 상태·최소화·로그인 자동 실행·시작 정책과 파일 보호 계약은 유지한다.

- 트레이 최초 등록 실패는 창을 유지하며 Explorer 재등록 실패는 숨은 창을 복원하고 기존 로그에 남긴다. 실사용 데스크톱의 Explorer 재시작이나 OS 로그오프·종료는 시험을 위해 실행하지 않는다. 모의 이벤트·코드 검토와 실제 Windows 세션 시험을 구분하며 새 실행 결과는 [트레이 작업 기록](../../docs/delivery/download-version-manager-tray-20261005.md)을 따른다.
- X는 완전 종료가 아니다. 새 EXE 확인에는 기존 앱의 트레이 종료와 프로세스 종료 확인이 필요하다. 이전 버전에 트레이 메뉴가 없으면 확인된 정상 종료 경로를 사용한다. 기존 앱을 안전하게 종료할 수 없는 경우 정확한 새 EXE의 전체 시작 확인은 NOTRUN으로 남기며 빌드·MSI payload 일치와 구분한다.
- **USER_CONFIRMED, 2026-10-05:** 사용자가 확인한 새 카드 UI와 현재 동작, 앞선 날짜·읽기 전용·수평 스크롤은 해당 사용 범위의 근거다. 트레이 수정 후 전체 인수나 모든 환경·설치·복구·업그레이드 검증을 뜻하지 않는다. 앞선 집중 17 PASS와 core 57 PASS·진단 판정 8 PASS 재사용도 이번 트레이의 새 PASS가 아니다.
- **설치 실패 복구 BLOCKED, 실제 복구 PASS 0:** 승인된 격리 Windows 환경 미확보·과거 FAIL·NOTRUN과 원인 미확정 상태를 유지한다. 이번 로컬 EXE·무서명 MSI 제작은 설치·제거·repair·upgrade·복구·상용 승인·공개 게시 성공을 뜻하지 않는다.

## 2026-10-05 · 0.2.1 설치 검증 범위 구분

- 일반 배포 대상은 기존 DVM 없는 0.2.1 최초 설치·정상 실행·트레이 종료·제거를 우선 검증한다. 최초 설치 실패·취소 복구는 별도 안전 항목이며 **BLOCKED / 실제 복구 PASS 0**이다. 안전 요건을 면제하거나 과거 실패를 해결된 것으로 바꾸지 않는다.
- 사용자 PC의 0.2.0 → 0.2.1 업그레이드는 선택 검증이며 일반 배포 대상의 필수 경로가 아니다. 현재 계정의 0.2.0 제품·실행 설정은 읽기만 했고 기존 설치 preflight가 막혔다. 새 후보의 실제 최초 설치·실행·제거는 **NOTRUN**이다.
- 정상 경로의 준비 명령은 rollback 없이 --skip-repair를 사용한다. 시험 도구는 0.2.1의 WM_CLOSE 숨김 계약에 맞춰 소유 PID/class를 확인한 기존 트레이 종료 명령으로 정상 종료를 요청한다. 이 mock 회귀 **4 PASS**와 기존 증거 판정 회귀 **8 PASS**는 실제 앱 구동·설치·복구 PASS를 대신하지 않는다. 실패 시 기존 snapshot 보존·중단 경로를 유지하며 현재 사용자 앱 종료·설치본 교체·강제 정리 없이 [최초 설치 검증 범위](../../docs/delivery/download-version-manager-first-install-scope-20261005.md)를 따른다.

## 2026-10-05 전용 아이콘 후보의 미확인 범위

최신 icon-20261005 로컬 0.2.1 후보의 아이콘·창·모의 tray descriptor/DPI·native 렌더는 자동 집중 검증했다. 실제 사용자 taskbar/알림 영역 픽셀과 production wWinMain 전체 실행·두 번째 singleton 실행은 NOTRUN이다. 현재 앱을 임의로 종료하지 않았다. 새 파일 지문과 resource/payload 근거는 [아이콘 기록](../../docs/delivery/download-version-manager-icon-20261005.md)을 따른다. 이전 tray-20261005 파일의 지문을 새 후보 값으로 쓰지 않는다.

일반 최초 설치 경로, 별도 실패·취소 복구, 개인0.2.0 업그레이드는 [최초 설치 범위](../../docs/delivery/download-version-manager-first-install-scope-20261005.md)대로 분리한다. 기존 설치와 전용 환경 부재로 실제 정상 lifecycle NOTRUN·복구 BLOCKED / 실제 PASS0 유지. 무서명 로컬 후보이며 현재 설치본 교체·공개 또는 상용 승인은 아니다.

## 2026-10-05 실제 PC의 0.2.1 후반 설치 실패

- 사용자가 실제 PC 시험 준비·진행을 명시 승인했다. 기존 0.2.1 정상 제거와 백업한 실행 설정 네 값 분리로 신규 설치 기준을 만들었다. 전용 VM·전체 OS snapshot이나 완전 클린 Windows 시험은 아니며, 실제 업무파일 대신 합성 fixture만 사용했다.
- 정상 MSI의 위자드 취소와 transaction 중 취소는 각각 exit 1602, 전후 상태 차이 0·UNKNOWN 0으로 **PASS**다. 진행 중 취소는 실제 파일 복사 후 WriteRegistryValues 실행 단계와 rollback을 확인했다.
- **후반 실패 자동 복구 FAIL:** 정확한 production payload·설정 DLL을 그대로 쓴 시험 MSI에서 InstallExecute 뒤 실패 action·exit 1603·rollback을 확인했지만 Windows Installer 제품·UpgradeCode·userdata·제거 등록이 남았다. 로그에 registry access denied(5)와 owner 복원 오류 1307이 있다. 종료 코드나 일부 파일 복귀만으로 PASS로 판정하지 않았다.
- 실패 직후 증거를 보존하고 후속 실패 시험을 중단했다. 사전 조건부 복구 계획에 맞는 정확한 시험 제품만 공식 제거 exit 0으로 정리하고 설치 전 상태와 같음을 확인했다. 원래 정상 MSI 재설치와 원래 설정·기본값·로그인 시작 항목 복원은 **PASS**, 앱은 종료 상태다. 이 정리 성공은 자동 rollback PASS가 아니다.
- 실제 감시 폴더 12개·History 3개의 직하 메타데이터와 CompletionOrder는 그대로다. 업무파일 내용·하위 폴더 전체 바이트 보존이나 타 PC 설치를 인증하지 않는다. 실제 계정 ACL/owner·Windows Installer 내부 등록을 수동 변경하거나 관리자 재시도로 우회하지 않았다.
- 초기 위자드 호출 오류는 NOTRUN, 취소 계측 도구 오류 두 실행은 FAIL로 보존한다. 도구 교정 후 최종 취소 PASS를 제품의 후반 실패 FAIL과 구분한다. 이번 실패 주입 MSI는 private 시험 전용이며 정식 자산에 포함하지 않는다.
- 정식 릴리즈 목표를 유지하되 재현된 후반 실패의 근본 원인과 제품 복구 수정·재검증은 아직 완료되지 않았다. 원래 정상 0.2.1 MSI는 바꾸지 않았고 새 정식 릴리즈는 게시하지 않았다. 무서명 사실과 조직 도입 승인 미결정을 유지하며 서명을 별도의 새 필수 시험 조건으로 추가하지 않는다.

[이번 실제 결과](../../docs/delivery/download-version-manager-first-install-scope-20261005.md)와 [TEST_RESULTS](TEST_RESULTS.md)를 따른다. 과거 0.1.0·초기 0.2.0 FAIL/NOTRUN은 해결된 것으로 바꾸지 않는다. 정확한 명령·원시 진단·사용자 경로·백업은 비공개 실행 근거에 보존한다.

## 2026-10-06 원인 분리 이후 남은 제한

강제 InstallExecute 없는 normalFinalize deferred 실패와 같은 MSI의 표준 msiexec /qn 실행도 실제 cmd exit 1·1603·rollback 뒤 등록 상태 차이 18개·UNKNOWN 0으로 **FAIL**이다. 추가 InstallExecute나 Python API 호출만이 원인이라는 가설은 배제했지만, 등록/owner 복원의 access denied(5)·오류 1307이 발생하는 근본 원인은 미확정이다. Windows 자체 결함으로 단정하지 않는다.

WordCount 10→2 권한 요청 후보는 기존 deferred 시험본과 PackageCode·Summary PID 15만 다른 비공개 진단용이다. 실제 권한 요청은 있었지만 credential request 0x800704C7·exit 1602로 후반 실패에 도달하지 못해 해당 대조는 **NOTRUN**, 해결이나 복구 PASS는 미확정이다. 원래 production의 권한 정책은 바꾸지 않았다. 2026-10-06 00:00 KST 원래 설치·설정·시작 항목·경로·PackageCode·지문·앱 종료 및 사용자 직하 메타데이터·History·CompletionOrder 복원을 확인했다. 사용자 UAC 승인 완료 후 대조가 남아 있으며 정식 릴리즈를 보류한다.

## 2026-10-06 최종 0.2.1 확인 이후의 제한

- 같은 PC에서 Installer 상승 권한을 허용하는 WordCount 10→2와 사용자의 UAC 승인으로 후반 실패의 등록 원상복귀가 성공했다. 이를 최종 정상 MSI에 반영했고 두 취소·후반 실패·복구 후 정상 재설치·앱 일반 권한 실행/종료·정상 제거·원래 설정 복원을 PASS로 확인했다. 이전 no-elevation FAIL과 승인 미완료 1602의 후반 실패 NOTRUN은 유지한다. Windows 자체 결함이나 모든 실패 지점의 해결로 확대하지 않는다.
- 설치는 현재 사용자 LocalAppData·HKCU를 사용하며 관리자 승인이 요청될 수 있다. 사용자가 직접 승인하고 설치 후 앱은 일반 권한으로 실행한다. 이번 추가 인자 없는 등록 앱 실행의 medium token을 직접 확인했으며 모든 실행 경로·다른 계정의 승인을 인증하지 않는다.
- 정상 MSI `0feea2fc119bad780da9dcb57d2a0303ef0e2e0c6f6a20a746fd3ab3f86a0ef5`와 동등 payload 시험 MSI의 직접 결과다. 시험 MSI·사용자 로그·SID·로컬 진단을 공개하지 않는다. 미래 CI 재빌드 파일은 별도 지문/검증이 필요하며 실제 CI는 NOTRUN이다.
- 실제 Windows 11 x64 한 PC·합성 fixture 범위이며 VM·전체 OS snapshot·완전 클린 Windows·다른 PC 시험이 아니다. 사용자 폴더/History 직하 메타데이터와 CompletionOrder는 보존했지만 업무파일 내용·하위 전체 바이트를 검사하지 않았다. 기존 비재귀·고정 로컬 NTFS·파일 처리/전원 장애 제한은 유지한다.
- 정식 릴리즈용 정상 MSI를 준비했으며 새 공개 게시는 실행하지 않았다. 코드 서명은 없고 조직 도입·상용 승인은 미결정이다. [최신 실제 결과](TEST_RESULTS.md)를 따른다.
