# CI 범위

## 0.2.0 폴더 감시

현재 Windows Server 2025 GitHub-hosted runner는 MSVC x64 /MT·Windows SDK·WiX 4로 네이티브 폴더 감시 프로그램과 단일 per-user MSI를 제작합니다. 변경 경로의 집중 검증은 폴더 엔진 8개, OS 알림 watcher 대표 세션의 15개 확인, 최초 기존 그룹의 4개 흐름입니다. 기존 브라우저 확장·전체 Host·성능·전체 MSI 수명주기 시험을 새 작업에 반복하지 않습니다.

MSI 구조·payload·SHA-256·외부 C/C++ runtime 의존성을 검사하고 제작 자산과 로그를 CI artifact로 저장합니다. 자동 Release·tag·설치·제거·로그인·OS 다운로드 위치 변경 단계는 없습니다. 정상 설치와 실제 GUI 감시 시작·제거·사용자 데이터 보존, 알려진 Win11 late-failure는 로컬의 격리된 합성 fixture에서 별도로 기록합니다. Server runner 성공을 Win11 설치 실패 복구 PASS로 확대하지 않습니다.

업무 파일·브라우저 profile·다운로드 기록은 읽지 않습니다. 출력은 `artifacts/download-version-manager-watcher` 아래에 한정합니다. 시험 바이너리·실패 주입 MSI·원시 진단은 사용자 MSI에 포함하지 않으며 생성 출력은 Git에 추가하지 않습니다. 실패한 CI와 미실행 설치 증거를 성공한 공개 제품으로 안내하지 않습니다.

아래는 기존 0.1.0의 당시 CI 범위이며 현재 watcher workflow가 이 전체 작업을 실행한다는 뜻이 아닙니다. legacy `build/build.py`와 소스·과거 결과를 보존합니다.

## 0.1.0 브라우저 확장·Host의 역사적 CI 범위

Windows GitHub-hosted runner에서 MSVC x64 static CRT·Windows SDK CNG Host, 별도 실패 주입 test Host, Node MV3 controller tests, 실제 NTFS host/protocol/concurrency 시험, 새 프로세스 자원 측정, WiX per-user MSI 제작과 구조/행정 추출/파일 SHA-256 검증을 실행합니다.

CI는 synthetic fixture의 native MSI fresh/repair/upgrade/uninstall/reinstall과 제품 게시 전·후 실패를 공식 Windows Installer API로 실행하도록 연결합니다. 기존 제품/NMI 등록이 있으면 preflight에서 중단합니다. late failure의 남은 자기 시험 등록은 공식 MSI 제거로 정리하며 registry 권한·MSI 내부 등록을 직접 수정하지 않습니다. 실패 복구 시험이 실패하면 job도 실패합니다.

확장을 기존 브라우저 profile에 설치하지 않고 스토어 심사·실제 사용자 Chrome/Edge·interactive installer GUI를 PASS로 만들지 않습니다. Windows Server 2025 runner는 Windows 11 표준 사용자/깨끗한 VM 실기를 대체하지 않습니다. build 실패는 성공 MSI로 게시하지 않습니다. 자동 release 단계는 없고 stable gate는 누락·FAIL·NOT RUN을 차단합니다. 원격 workflow 실행 결과는 실제 run이 완료된 뒤 TEST_RESULTS에 기록합니다.

관문 누락·평가 channel 차단과 loopback HTTP 합성 fixture 재현성도 자동 검증합니다. loopback 시험 서버는 시험 안에서 종료하며 제품의 background component가 아닙니다. completionOrder와 installerFailureRecovery를 stable 관문에 별도로 표시합니다. 임의 fixture의 최소 순서 registry 값만 시험 종료 때 정리하며 다른 값과 History는 보존합니다.

사용자 업무 문서·개인 profile·다운로드 기록을 읽지 않습니다. 합성 fixture만 생성하며 기본 출력은 `artifacts/download-version-manager`입니다. 정상제품에 실패 주입 기능·tests·로그·개인 데이터는 포함하지 않습니다. 생성 출력은 Git에 추가하지 않습니다.
