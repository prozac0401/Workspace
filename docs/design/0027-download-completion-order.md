# ADR-0027 · 완료 시각과 파일 객체로 최신 다운로드를 유지

상태: 채택 — 평가 구현, 실제 브라우저 인수 미완료

날짜: 2026-09-30 · 결정 담당: 사용자 요구에 따른 개발 담당

관련: [최초 명세](../tools/download-version-manager/specification.md), [추가 도구 개발 기준](../policies/tools.md)

대체 관계: [ADR-0026](0026-download-version-manager.md)의 완료 순서·protocol·최소 상태 보존 부분을 대체한다. 무상주 구조와 파일 안전성·배포 결정은 유지한다.

## 맥락

A 다음 B가 완료됐지만 Host가 B 다음 A를 처리하면 mutex만으로는 A가 원래 이름을 다시 차지한다. production Host의 합성 파일 시험으로 이 실패를 재현했다. Chrome/Edge의 download ID는 서로 충돌할 수 있으며 service worker의 호출 시각은 다운로드 완료 시각이 아니다.

## 결정

확장은 `downloads.search({id})`의 `DownloadItem.endTime`을 Unix milliseconds로 전달한다. filename 결정 때 만든 128-bit random request token을 metadata에 함께 보존해 worker 복원과 브라우저 간 ID 충돌을 처리한다. 완료 시각·token이 없으면 두 파일을 보존하고 중단한다. 공개 배포 전인 제품 버전 0.1.0은 유지하고, 필수 필드가 바뀐 Native Messaging protocol은 2로 올린다.

Host는 기존 target mutex 안에서 HKCU `Software\Workspace\DownloadVersionManager\CompletionOrder`의 대상별 값 한 개를 읽고 쓴다. 값 이름은 canonical target의 invariant-lowercase UTF-8 SHA-256이다. 이는 내용 hash가 아니라 같은 대상의 상태를 찾는 키다. 138-byte binary 값에는 schema, 이전·준비한 객체의 volume/file ID, 완료 시각, request token, 상태 무결성 checksum만 넣는다. 파일명·경로 원문·URL·문서 내용·내용 hash·다운로드별 성공 기록은 저장하지 않는다. 서로 다른 target은 계속 병렬이다.

현재 target의 실제 file ID에 해당하는 완료 기록보다 늦은 다운로드가 원래 이름을 승계한다. 늦게 전달된 이전 다운로드는 최신 target을 바꾸지 않는다. 내용이 같으면 그 이전 incoming 객체만 제거하고, 다르면 그 incoming 객체를 원래 logical name의 History 규칙으로 보존한다. 정상 순서의 동일 다운로드는 계속 신규 객체가 이름을 승계한다. 비교는 size-first와 64 KiB streaming SHA-256이다.

완료 시각이 같은 서로 다른 token은 선후를 알 수 없으므로 `completion_order_ambiguous`로 두 객체를 보존한다. 더 높은 download ID나 mutex 순서를 실제 완료 순서로 간주하지 않는다. 브라우저/OS 시계의 역행과 실제 API의 시각·정밀도는 실기 검증 범위다. 시간 기록만으로 벽시계 변경을 복원한다고 주장하지 않는다.

## 검토한 대안

호출 순서만 직렬화하는 방식은 재현한 요구 위반을 해결하지 못한다. 브라우저 storage만 사용하면 다른 브라우저의 최신 상태를 알 수 없다. 파일의 수정 시각만 사용하면 서버 시간과 사용자 편집이 완료 시각과 다를 수 있다. 사용자 문서의 ADS에 상태를 붙이는 방법 대신 사용자별 작은 registry 값을 선택했다. 상주 조정 프로세스나 polling은 idle process 0 요구에 어긋난다.

## 실패와 복구

첫 파일 이동 전에 이전 committed 객체와 incoming 객체를 한 값으로 준비한다. 프로세스 중단 뒤 target의 file ID가 이전 객체이면 그 이전 기록을, incoming 객체이면 새 기록을 사용한다. 비교/이동 실패로 최신 완료가 실제 이름을 승계하지 못했다면 원래 두 객체 보존·rollback 정책을 따른다. 기록이 없어진 target, 외부 교체, 손상/미래 schema를 뒤늦은 요청에서 조용히 초기화하지 않는다. 확인 불가하면 변경 없이 중단한다. 이후 더 늦은 완료는 보존된 파일을 지우지 않고 새 head를 만들 수 있다.

registry 쓰기가 실패하면 파일 이동 전에 중단한다. checksum 불일치도 변경 없이 중단한다. 전원 차단에 대한 registry/file 동시 durability는 인증하지 않으며 건별 `RegFlushKey`로 전체 hive의 강제 쓰기를 유발하지 않는다. 자동 잔재 검색·background retry는 없다.

## 영향과 이행

같은 버전의 평가 MSI라도 protocol 1 후보와 2 후보를 섞어 사용하지 않는다. 설치 파일·확장·Host 제품 버전은 0.1.0으로 일치한다. 순서 기록은 제거·재설치 사이의 지연 요청을 보호하기 위해 보존하고 installer의 삭제 자원으로 등록하지 않는다. 정상 성공의 장기 로그와 구별되는 기능 상태이며 target당 값 하나만 갱신한다. 알려지지 않은 registry 값과 사용자 History를 제거하지 않는다.

## 검증

Host 82개와 확장 38개 자동시험이 PASS다. 역순 A/B, 16개 병렬 요청, 동일 browser ID, 동일 바이트의 이전 요청, 같은 완료 시각, malformed/누락 metadata, 준비/rename 후 강제 종료, 정상/실패 rollback, 외부 target 교체, 손상된 138-byte 상태, unrelated registry 값 보존을 확인했다. Windows 11 x64에서 Host 209,920 bytes, 1 GiB 두 객체 비교에서 peak 14,225,408 bytes와 처리 후 native 0을 측정했다. 실제 Chrome/Edge endTime contract와 Native Messaging은 NOT RUN이다. 상세 수치는 [시험 기록](../../tools/DownloadVersionManager/TEST_RESULTS.md)에 남긴다.

공식 근거 (2026-09-30 확인): [Chrome downloads의 endTime](https://developer.chrome.com/docs/extensions/reference/api/downloads#property-DownloadItem-endTime), [FILE_ID_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_id_info), [작은 registry binary 값](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-storage-space), [RegSetValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsetvalueexw), [RegFlushKey의 비용](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regflushkey).
