# CI 범위

Windows GitHub-hosted runner에서 MSVC x64 static CRT·Windows SDK CNG Host, 별도 실패 주입 test Host, Node MV3 controller tests, 실제 NTFS host/protocol/concurrency 시험, 새 프로세스 자원 측정, WiX per-user MSI 제작과 구조/행정 추출/파일 SHA-256 검증을 실행합니다.

CI는 synthetic fixture의 native MSI fresh/repair/upgrade/uninstall/reinstall과 제품 게시 전·후 실패를 공식 Windows Installer API로 실행하도록 연결합니다. 기존 제품/NMI 등록이 있으면 preflight에서 중단합니다. late failure의 남은 자기 시험 등록은 공식 MSI 제거로 정리하며 registry 권한·MSI 내부 등록을 직접 수정하지 않습니다. 실패 복구 시험이 실패하면 job도 실패합니다.

확장을 기존 브라우저 profile에 설치하지 않고 스토어 심사·실제 사용자 Chrome/Edge·interactive installer GUI를 PASS로 만들지 않습니다. Windows Server 2025 runner는 Windows 11 표준 사용자/깨끗한 VM 실기를 대체하지 않습니다. build 실패는 성공 MSI로 게시하지 않습니다. 자동 release 단계는 없고 stable gate는 누락·FAIL·NOT RUN을 차단합니다. 원격 workflow 실행 결과는 실제 run이 완료된 뒤 TEST_RESULTS에 기록합니다.

관문 누락·평가 channel 차단과 loopback HTTP 합성 fixture 재현성도 자동 검증합니다. loopback 시험 서버는 시험 안에서 종료하며 제품의 background component가 아닙니다. completionOrder와 installerFailureRecovery를 stable 관문에 별도로 표시합니다. 임의 fixture의 최소 순서 registry 값만 시험 종료 때 정리하며 다른 값과 History는 보존합니다.

사용자 업무 문서·개인 profile·다운로드 기록을 읽지 않습니다. 합성 fixture만 생성하며 기본 출력은 `artifacts/download-version-manager`입니다. 정상제품에 실패 주입 기능·tests·로그·개인 데이터는 포함하지 않습니다. 생성 출력은 Git에 추가하지 않습니다.
