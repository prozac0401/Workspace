# 변경 이력

## 0.1.0 · 평가 후보 · 2026-09-30

- 후속 평가에서 protocol 2의 완료 시각·다운로드 token과 138-byte HKCU 상태를 추가해 역순 요청이 최신 객체를 바꾸는 결함을 수정했습니다. 같은 완료 시각은 두 파일을 보존합니다.
- Host 82건·확장 38건과 1 GiB streaming 시험을 통과했습니다. 제품 게시 뒤 두 실패 지점의 MSI 등록 rollback/reinstall 실패는 별도 관문으로 남깁니다.

- MV3 다운로드 완료 이벤트와 단발 Native Messaging x64 C++ Host를 추가했습니다.
- 크기 우선·streaming SHA-256 비교, 신규 객체의 원래 이름 승계, 다른 이전 내용만 timestamp History로 이동합니다.
- 대상 mutex, 안전한 핸들 이동, rollback과 정확한 실패 경로, 정상 성공 무알림을 제공합니다.
- per-user 단일 MSI 후보와 공식 개발용 확장 활성화 안내를 제공합니다. 스토어 배포·완전 자동 통합 설치는 미완료이며 stable 릴리스가 아닙니다.
