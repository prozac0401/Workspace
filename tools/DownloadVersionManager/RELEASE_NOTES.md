# DownloadVersionManager 0.2.0 · 폴더 감시 릴리즈 노트

**[무서명 기능 평가 prerelease](https://github.com/prozac0401/Workspace/releases/tag/download-version-manager-v0.2.0)를 게시했습니다.** 관련 설치·실행·제거 근거를 확보했고 알려진 실패 복구 제한을 포함합니다. 상용 승인 또는 모든 설치 실패 복구를 인증한 릴리즈로 분류하지 않습니다.

사용자 설치 파일은 `DownloadVersionManager-Watcher-0.2.0-x64.msi` 하나입니다. 현재 사용자에게 설치하며 외부 runtime과 브라우저 확장이 필요하지 않습니다. 설치 위자드에서 현재 Windows 다운로드 폴더 또는 다른 폴더를 고릅니다. 기본 다운로드 위치 변경 추종과 로그인 자동 실행은 기본 선택이며 해제할 수 있습니다.

처음 기존 번호 그룹을 미리 보고 최신으로 남길 파일을 직접 선택합니다. 원래 이름의 파일 선택은 그룹 전체 보존입니다. 번호 파일을 선택하면 전체 그룹의 처리 순서를 확인하고 정리를 실행하며 선택 파일을 마지막에 원래 이름으로 이동합니다.

이후 새 `파일 (n).ext`를 같은 폴더의 기존 원래 대상과 연결합니다. 3초 안정·잠금 조건으로 처리하고 같은 대상의 동시 후보는 모두 보존합니다. 같은 바이트면 신규 객체가 원래 이름을 승계하며 이전 객체는 제거합니다. 다른 바이트면 이전 파일만 `_history/stem_YYYYMMDD_HHMMSS[_001].ext`에 보관합니다.

Windows 11 x64·고정 로컬 NTFS에서 폴더 엔진 8건, watcher 대표 세션 15건, 최초 그룹 처리 4건이 PASS입니다. MSI 구조·정적 runtime과 수정 후보의 실제 설치·실행·repair·제거·사용자 파일 보존 5건, 화면 높이 수정 후보의 설치·실행·제거·보존 4건도 PASS입니다. 최종 안내 문구·위자드 폴더 선택 수정에는 설치·처리 경로의 관련 근거를 재사용하고 표준 MSI 선택 창의 경로 표시·설정 전달·취소를 따로 확인했으며 최종 파일 자체를 다시 설치했다고 주장하지 않습니다. 기존 전체 Host/확장·성능 시험을 반복하지 않았습니다.

실제 위자드에서 현재 Windows 다운로드 위치·기본 위치 추종·로그인 자동 실행 체크와 취소를 확인했습니다. 다음 Windows 로그인과 실행 중 OS 다운로드 위치 변경은 NOT RUN입니다. 최종 MSI SHA-256은 `c7be2ea44b09b2afd9d3a82956150aafba5390a8013ceccfeacd6583965a30e7`입니다.

**설치 실패 복구에는 알려진 제한이 있습니다.** 현재 Windows 11에서 새 MSI의 InstallExecute 이후 실패 주입 시 제품 등록 rollback의 access denied(5)가 관찰됐습니다. 시험 제품의 공식 Windows Installer 제거는 성공했고 사용자 파일은 보존했습니다. 정상 설치 결과와 실패 복구를 구분하며, 이전 0.1.0의 실패가 해결됐다고 표시하지 않습니다.

파일명 관례는 앱의 원래 이름을 증명하지 않으며 원래부터 번호가 있는 별개 파일도 처리될 수 있습니다. 3초 안정은 앱 완료의 증명이 아닙니다. 직접 덮어쓰기의 이전 바이트·긴 쓰기 중단·재귀·네트워크·클라우드 연결·ARM64는 지원하지 않습니다. 강제 종료·전원 장애의 자동 복원 화면은 없습니다. 파일 내용·telemetry를 외부에 보내지 않습니다.

감시 중 일반 사용자 프로세스 한 개가 유지됩니다. 창을 닫으면 감시가 끝나며 시작 메뉴에서 다시 실행할 수 있습니다. 제거 전에 프로그램을 닫습니다. 감시 폴더·History와 사용자 실행 설정은 보존합니다. 구버전 0.1.0 설치·브라우저 등록·순서 상태는 자동 변경하지 않으며 같은 폴더에서 구버전 확장과 함께 실행하지 않습니다.

태그: `download-version-manager-v0.2.0`. [MSI 다운로드](https://github.com/prozac0401/Workspace/releases/download/download-version-manager-v0.2.0/DownloadVersionManager-Watcher-0.2.0-x64.msi) · [SHA256SUMS](https://github.com/prozac0401/Workspace/releases/download/download-version-manager-v0.2.0/SHA256SUMS.txt). 게시된 두 자산을 실제 다운로드해 체크섬을 확인했습니다. 실제 결과는 [TEST_RESULTS](TEST_RESULTS.md), 제한은 [KNOWN_LIMITATIONS](KNOWN_LIMITATIONS.md)를 따릅니다.

## 0.1.0 당시 릴리즈 노트 초안 — 미게시 기록 보존

**공개 Release를 게시하지 않았습니다. stable gate는 BLOCKED입니다.**

Chrome·Edge MV3 확장이 현재 다운로드의 원래 이름을 기록하고 완료 후 C++ Native Host를 한 번 실행합니다. 크기를 먼저 비교하고 같은 크기만 SHA-256 streaming으로 읽습니다. 같은 바이트도 방금 받은 파일 자체가 원래 이름을 승계하고, 달라진 이전 파일만 같은 parent의 `_history/stem_YYYYMMDD_HHMMSS[_001].ext`로 이동합니다. 정상 성공은 조용히 처리하며 잠금·권한 실패는 보존·rollback 후 짧게 알립니다.

단일 평가 MSI는 Host와 공통 확장·설치 마무리 안내를 포함합니다. 관리자 승인을 요구하지 않는 LocalAppData/HKCU 설치, 외부 사용자 runtime 없음, 코드 서명 없음입니다. MSI 후 각 브라우저에서 공식 개발용 확장 활성화가 필요합니다. 스토어 배포 전으로 일반 PC의 완전 자동 단일 설치를 충족한 정식판이 아닙니다.

Windows 11 x64·고정 로컬 NTFS에서 Host 61개, controller 29개, release gate 4개, loopback fixture 3개와 최종 native installer lifecycle 14개 기록을 통과했습니다. 설치 파일의 SHA-256을 검사했습니다. 실제 Chrome·Edge filename contract/E2E·Native handshake·활성화된 확장의 idle은 NOT RUN입니다. native 독립 snapshot은 0이며 실행 후 모두 종료했습니다.

지원 인증하지 않은 범위는 Windows 10·ARM64·네트워크/클라우드 경로·모든 기업 정책과 다운로드 방식입니다. 동시 요청은 브라우저 완료 시각·파일 객체 ID로 최신본을 유지합니다. 같은 millisecond의 두 완료와 시계 역행은 제한이며 실제 브라우저 contract는 미검증입니다. 전원 장애 자동 복구·restore UI·기존 suffix 일괄 정리·telemetry·cloud upload·background update는 없습니다. MSI 제품 게시 후 실패의 앞선 시험에서 제품 등록 롤백 실패가 관찰돼 모든 실패 지점의 복구를 인증하지 않습니다. [KNOWN_LIMITATIONS](KNOWN_LIMITATIONS.md)와 [실제 시험 기록](TEST_RESULTS.md)을 먼저 확인하세요.

제거는 프로그램 파일과 자기 Native Host 등록만 대상으로 하며 다운로드·History를 보존합니다. 각 브라우저의 확장은 사용자가 제거합니다. stable tag `download-version-manager-v0.1.0`은 모든 실제 인수·단일 배포 관문을 통과한 경우에만 사용합니다.
