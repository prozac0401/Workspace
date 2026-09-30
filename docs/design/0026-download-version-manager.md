# ADR-0026 · 다운로드 이벤트와 단발 Native Host

상태: 채택 — 평가 구현, stable 인수 미완료  
날짜: 2026-09-30 · 결정 담당: 사용자 요구에 따른 개발 담당  
관련: [최초 명세](../tools/download-version-manager/specification.md), [추가 도구 개발 기준](../policies/tools.md)  
기존 관계: ADR-0025 다음 번호. 기존 도구의 공통 라이브러리 추출·대규모 변경 없음.

## 맥락

브라우저 중복 다운로드가 suffix를 늘린다. 사용자에게 방금 받은 파일은 원래 이름의 최신본이어야 한다. 바이트가 다른 이전 버전만 History에 남겨야 하며, 평소 Windows native process는 없어야 한다. 기존 Workspace의 .NET10·C++ MSVC·Windows SDK/CNG·WiX 제작 자원을 조사했다. 작은 한 요청 Host에는 native x64 C++와 static CRT를 선택한다.

## 결정

1. Chrome/Edge 공통 MV3 service worker가 다운로드 이름 결정과 완료 이벤트를 처리한다. 일시 저장 metadata를 `storage.local`로 복원하고 `sendNativeMessage` 한 번만 호출한다. 상주 watcher·service·tray·polling·keepalive·connectNative·daemon을 만들지 않는다. 파일 이동/hash 책임은 Host에만 둔다.
2. `onDeterminingFilename`의 tentative 이름을 보존하고 `suggest({filename: logicalName, conflictAction: 'uniquify'})`를 storage 쓰기 후 정확히 한 번 호출한다. 비동기 suggest에는 `true`를 반환한다. 완료에서 ID 한 건을 `downloads.search`로 조회해 실제 절대 경로를 사용한다. 브라우저 counter에서 원래 이름을 역추론하지 않는다. 기록한 이름에서 생성될 수 있는 forward uniquify 이름인지 검증하며 다른 basename이면 그대로 둔다. 사용자 Save As overwrite·경쟁 filename 확장은 안전 보장 밖이다.
3. 같은 바이트여도 새 객체가 이름을 승계한다. file ID/ADS/신규 속성을 유지하며 rename 후 캡처한 creation/access/write time를 다시 설정해 NTFS 이름 tunneling 영향을 줄인다. 오래된 객체 유지·신규 삭제 방식은 요구 위반이다.
4. 크기가 다르면 hash 읽기 없이 다른 내용으로 확정한다. 같으면 CNG BCrypt SHA-256과 64 KiB 버퍼를 사용한다. 전체 byte array/memory-map·문서 내용 해석·hash 저장은 없다. 기본 데이터 스트림의 바이트 동일성을 정의한다.
5. 다른 내용일 때만 parent의 `_history`를 만들고 기존 객체를 `stem_YYYYMMDD_HHMMSS.ext`로 이동한다. timestamp는 해당 이전 객체의 이동 후보를 정하는 로컬 시각이다. `_001` 이후 순번, overwrite 금지 handle rename, 10,000개 후보 상한을 쓴다. timestamp를 붙인 이름이 NTFS 255 code-unit를 넘으면 중단한다.
6. 기존·신규 핸들에 필요한 read/DELETE access와 신규 시간 설정 access를 확보한 뒤 비교한다. write/delete sharing 없이 외부 변경·이동을 제한한다. parent ancestor를 핸들로 고정하고 reparse/UNC/장치/ADS/traversal·hardlink·encrypted/offline/readonly·대소문자 구분 디렉터리를 거절한다. 로컬 고정 NTFS만 후보다. 자손 열거는 없다.
7. 다른 내용은 old → History → new → target, 실패하면 old handle → target rollback이다. 같은 내용도 old를 parent의 `.dvm-<128bit random>.pending`에 먼저 보존해 new 이동 실패의 rollback을 가능하게 한다. new 성공 후 그 old handle만 삭제한다. 삭제/시간 복원 실패는 완료한 최신본과 남은 이전 객체를 명확히 보고한다. 두 이름 변경은 단일 트랜잭션이 아니며 전원 차단·강제 종료 뒤 자동 스캔/복구는 하지 않는다.
8. canonical parent+logical target을 invariant lowercase·SHA-256으로 named mutex key로 만든다. `Global\\Workspace.DownloadVersionManager.v1.<digest>`가 Chrome/Edge 프로세스에 공통이다. 대기는 30초, 실패는 target_busy다. 협력하지 않는 같은 사용자 프로그램의 강제 변경까지 보장하지 않는다. 서로 다른 target은 병렬이다. 동시 요청의 최종본은 잠금 처리 순서이며 완료 시각을 영구 추적하는 기능은 제한으로 남긴다.
9. Native boundary는 브라우저 manifest의 정확한 `allowed_origins`와 Host의 argv origin 검증, flat JSON 엄격 파싱, duplicate/unknown field 거절, 64 KiB request 상한, protocolVersion 1이다. Host는 한 frame을 받고 한 frame을 stdout으로 쓰고 종료한다. stdout 로그·content script·externally_connectable·원격 입력·shell 실행 기능은 없다. 같은 Windows 계정의 로컬 프로세스는 OS상 동일 권한 주체이며 origin argv만으로 로컬 공격자를 인증한다고 주장하지 않는다.
10. per-user MSI 하나에 Host·공통 확장·연결 확인 popup·설치 마무리 안내를 넣는다. HKCU Chrome/Edge NativeMessagingHosts default value만 등록한다. manifest의 상대 exe 경로는 공식 Windows Native Messaging 계약이다. installer는 read-only native guard로 기존 소유 파일 hash와 실제 registration을 검사하고 표준 MSI actions에 쓰기/rollback을 맡긴다. 시스템 startup·service/task·브라우저 profile·강제 restart·reboot를 만들지 않는다.
11. 일반 Chrome Windows 외부 설치는 스토어 update URL과 사용자 승인 필요, 로컬 CRX 자동 활성화 불가다. Edge도 공식 store/external/enterprise 구분이 있고 Edge Add-ons ID가 development ID와 달라질 수 있다. MSI는 정책 등록·확장 sideload hack을 사용하지 않는다. 키가 있는 개발용 unpacked 확장은 두 브라우저에서 안정 ID 후보를 사용하되 실제 활성화/handshake를 별도로 시험한다. 정상 스토어 배포는 아직 미결정이고 **완전 자동 단일 설치 gate는 미충족**이다. 개발용 load fallback은 평가판으로만 안내한다. registry external discovery에 정상 browser restart가 필요할 수 있으나 installer가 강제하지 않는다.
12. History와 다운로드는 사용자 데이터다. 제거 시 개별 설치 파일/자기 HKCU 등록만 제거하고 History를 소유 목록·RemoveFile wildcard에 넣지 않는다. 다른 파일/외부 수정 등록은 guard로 보존하며 수정된 프로그램 파일은 서비스 작업을 중단해 보존한다.

## 자원·언어 대안

C++17/static CRT는 외부 runtime 없이 Win32/CNG만 호출하며 기존 MSVC/SDK·WiX로 작은 exe+MSI를 만들 수 있다. .NET self-contained는 익숙한 JSON·복구 코드를 쓰기 쉽지만 이 제품에는 runtime payload와 초기화를 추가한다. 이번 C++ 후보가 실제 크기/새 프로세스 startup/peak/lifetime 측정에서 과도한 사용이나 안전성 한계를 보이면 동일 작업을 .NET 후보로 비교한 후 결정을 변경한다. 비교하지 않은 .NET 성능 수치는 만들어 넣지 않는다. 현재 측정과 환경은 [TEST_RESULTS](../../tools/DownloadVersionManager/TEST_RESULTS.md)에 기록한다.

## 개인정보·UX 예외

내용/hash/URL/경로를 장기 로그·telemetry로 남기지 않는다. storage는 download ID별 이름/시각/ready·processing 단계만 갖고 종료 시 지운다. 7일 stale은 다음 이벤트에서 정리하며 timer/자동 retry는 없다. 오류에는 경로 없는 최근 상태 한 건만 남긴다. 성공은 무알림, rollback 실패·불확실 작업은 직접 확인 안내다. 공통 도구 정책의 건별 미리보기·취소·감사 기록은 설치/활성화 설명·browser cancel·고정 이벤트 범위·중복 방지·rollback·최소 오류 기록으로 구체화한다. 추가 확인창/정상 장기 로그를 생략하는 제품별 예외를 채택한다.

## 검증·이행

production과 실패 주입 Host를 별도 compile하고 test binary를 MSI에 넣지 않는다. 실제 잠금/ACL·동시 프로세스·강제 중단·file ID/time·malformed protocol과 MV3 controller 시험, MSI 표/추출 hash 검사를 자동화한다. 실제 Chrome/Edge filename contract·대표 E2E·worker 종료/복원·Native handshake와 fresh/repair/upgrade/uninstall/reinstall은 별도 실기다. 누락/FAIL/NOT RUN을 stable PASS로 바꾸지 않는다. 서명 주체·스토어 계정·조직 배포 정책·새 PC 인증은 미결정이다.

## 공식 근거

- [Chrome downloads API](https://developer.chrome.com/docs/extensions/reference/api/downloads)
- [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
- [Chrome 외부 설치](https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions) · [기업 정책](https://support.google.com/chrome/a/answer/7532015?hl=en)
- [Edge 배포](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/alternate-distribution-options) · [Native Messaging](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/native-messaging)
- [Win32 SetFileTime](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfiletime)

확인일: 2026-09-30. 실제 브라우저 결과와 배포 관문은 별도 검증 기록이 근거다.
