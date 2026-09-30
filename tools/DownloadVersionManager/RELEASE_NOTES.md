# DownloadVersionManager 0.1.0 · 평가 후보 릴리즈 노트 초안

**공개 Release를 게시하지 않았습니다. stable gate는 BLOCKED입니다.**

Chrome·Edge MV3 확장이 현재 다운로드의 원래 이름을 기록하고 완료 후 C++ Native Host를 한 번 실행합니다. 크기를 먼저 비교하고 같은 크기만 SHA-256 streaming으로 읽습니다. 같은 바이트도 방금 받은 파일 자체가 원래 이름을 승계하고, 달라진 이전 파일만 같은 parent의 `_history/stem_YYYYMMDD_HHMMSS[_001].ext`로 이동합니다. 정상 성공은 조용히 처리하며 잠금·권한 실패는 보존·rollback 후 짧게 알립니다.

단일 평가 MSI는 Host와 공통 확장·설치 마무리 안내를 포함합니다. 관리자 승인을 요구하지 않는 LocalAppData/HKCU 설치, 외부 사용자 runtime 없음, 코드 서명 없음입니다. MSI 후 각 브라우저에서 공식 개발용 확장 활성화가 필요합니다. 스토어 배포 전으로 일반 PC의 완전 자동 단일 설치를 충족한 정식판이 아닙니다.

Windows 11 x64·고정 로컬 NTFS에서 Host 61개, controller 29개, release gate 4개, loopback fixture 3개와 최종 native installer lifecycle 14개 기록을 통과했습니다. 설치 파일의 SHA-256을 검사했습니다. 실제 Chrome·Edge filename contract/E2E·Native handshake·활성화된 확장의 idle은 NOT RUN입니다. native 독립 snapshot은 0이며 실행 후 모두 종료했습니다.

지원 인증하지 않은 범위는 Windows 10·ARM64·네트워크/클라우드 경로·모든 기업 정책과 다운로드 방식입니다. 동시 완료는 mutex 처리 순서이며 전체 browser 완료 시각 정렬을 보장하지 않습니다. 전원 장애 자동 복구·restore UI·기존 suffix 일괄 정리·telemetry·cloud upload·background update는 없습니다. MSI 제품 게시 후 실패의 앞선 시험에서 제품 등록 롤백 실패가 관찰돼 모든 실패 지점의 복구를 인증하지 않습니다. [KNOWN_LIMITATIONS](KNOWN_LIMITATIONS.md)와 [실제 시험 기록](TEST_RESULTS.md)을 먼저 확인하세요.

제거는 프로그램 파일과 자기 Native Host 등록만 대상으로 하며 다운로드·History를 보존합니다. 각 브라우저의 확장은 사용자가 제거합니다. stable tag `download-version-manager-v0.1.0`은 모든 실제 인수·단일 배포 관문을 통과한 경우에만 사용합니다.
