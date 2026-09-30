# DownloadVersionManager · 남은 제한

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
