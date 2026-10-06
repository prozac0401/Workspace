# DownloadVersionManager · 실행 파일·창·트레이 아이콘 · 2026-10-05

상태: **전용 아이콘 적용, 로컬 0.2.1 EXE·무서명 MSI 제작 완료.** 집중 native 결과 35 PASS / 최종 0 FAIL. 현재 설치본·공개 자산 미반영. 실제 최초 설치·실행·제거 NOTRUN, 최초 설치 실패·취소 복구 BLOCKED / 실제 PASS 0.

요구: 실행 프로그램과 트레이에 보이는 전용 아이콘을 만들고 적용한다. [원 명세](../tools/download-version-manager/next-version-specification.md), [추가 도구 개발 기준](../policies/tools.md), [문서 작성 규칙](../policies/documentation.md)을 따른다. 창 닫기·같은 창 열기·명시적 종료의 기존 근거는 [트레이 기록](download-version-manager-tray-20261005.md), 일반 대상과 개인 업그레이드의 구분은 [최초 설치 검증 범위](download-version-manager-first-install-scope-20261005.md)에 보존한다.

## 적용한 아이콘과 최소 변경

파란 둥근 사각형에 흰 다운로드 화살표와 원형 History 화살표를 결합했다. imagegen 스킬과 built-in image_gen의 새 이미지·transparent_background=true 모드로 생성했다. 원본은 RGBA 1254×1254이며 외곽 alpha 0을 보존했다. Pillow는 ICO 변환과 크기 축소만 수행했다. 전체 생성 prompt·출처·자산 지문은 artifacts/download-version-manager-watcher/icon-20261005/icon-generation.json에 기록한다.

| 파일 | 적용과 이유 |
|---|---|
| tools/DownloadVersionManager/assets/download-version-manager.png | 생성 원본 보존. 840,736 bytes, SHA-256 3dc0565671c4fd1301788bb266e1c6baf8f34484954517d762a45fe9ccb87419 |
| tools/DownloadVersionManager/assets/download-version-manager.ico | 16·24·32·48·64·128·256px의 32-bit RGBA 이미지 7개. 77,573 bytes, SHA-256 c9e656e4ce8732766144a166a4f852189ac4593a58165a53f1305e81c8379ab7 |
| source/app.cpp | production 창 class·큰/작은 창 아이콘·트레이가 같은 resource 101 사용. DPI 크기에 맞춰 로드하고 같은 크기 handle은 재사용. DPI 변경 때 트레이도 갱신하며 갱신 실패는 기존 접근 복구 경로 사용 |
| build/build-watcher.py | production EXE의 icon resource 내장, 동일 아이콘을 사용하는 집중 시험 연결, PNG/ICO를 source manifest의 지문에 포함 |
| tests/watcher/icon_smoke.cpp | 리소스·크기·handle 재사용·실제 창/트레이 descriptor·DPI·밝고 어두운 배경의 네이티브 렌더 집중 검증 |
| README·명세·TEST_RESULTS·KNOWN_LIMITATIONS·이 기록 | 로컬 후보의 적용 상태·새 지문·미실행 분리. 이전 시험 결과 원문 보존 |

비공유 LoadImageW handle을 크기별로 소유해 프로세스 수명 동안 재사용하고 종료 때 DestroyIcon한다. 공유 LR_SHARED 캐시가 이름 기준으로 크기를 무시할 수 있다는 [Microsoft 공식 LoadImageW 설명](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-loadimagew)을 확인했다. DPI 변경 시 교체한 이전 크기 handle도 cache가 유지해 창/트레이 사용 중 파괴하지 않는다. fallback 시스템 아이콘은 소유하지 않는다.

감시 엔진·History·파일 보호·잠금·상태·JSON·기존 로그 계약, 카드 UI 디자인, 버전 0.2.1·MSI identity·HKCU/per-user 정책은 그대로다. resource는 EXE에 내장하며 설치 폴더에 별도 PNG/ICO 파일을 요구하지 않는다. 같은 날 설치 검증 도구의 WM_CLOSE 종료 오인을 기존 트레이 종료 명령으로 고친 변경은 별도 최초 설치 기록에 설명한다.

## 이번 실제 검증

Windows 11 x64 23H2 build 22631.6199, 비상승 일반 사용자, 기존 MSVC x64·SDK 10.0.26100.0·WiX 4·Python 3.12.14를 사용했다. 실제 다운로드·History를 쓰지 않고 artifacts의 fresh fixture와 합성 HWND를 사용했다. 이하 경로는 artifacts/download-version-manager-watcher/icon-20261005 아래다.

| 실행 | 결과 | 근거와 범위 |
|---|---|---|
| --test-only icon | **5 PASS / 0 FAIL** | verified-icon/icon-tests.log. 7개 리소스 크기, 7×100회 동일 handle 재사용·stock과 다른 픽셀, 창 큰/작은 아이콘 및 초기 모의 Shell 등록, 144 DPI의 창·실제 전달된 모의 tray 갱신, native DrawIconEx light/dark 렌더 |
| --test-only tray | **21 PASS / 0 FAIL** | verified-tray/tray-tests.log. 실제 HWND·메뉴·합성 watcher 파일 이벤트·정상 종료와 모의 Shell 실패/Explorer/세션 분기. 실제 Shell add/modify/delete 별도 1건은 포함. 물리 트레이 조작은 아님 |
| --test-only ux 및 exact production manifest 활성화 | **8 PASS / 0 FAIL** | verified-ux/production-manifest-tests.log. 최종 production EXE의 manifest를 activation context로 사용한 실제 HWND geometry·render·control/log 검사. production wWinMain 전체 실행은 아님 |
| --test-only log | **1 PASS / 0 FAIL** | verified-log/log-tests.log. 전체 파일명·원인·상태·오류·수평 범위 |
| production compile-only / exact EXE package-only | PASS | /MT·/W4·/WX, 외부 C/C++ runtime 없음, source/EXE 지문 gate 일치 |
| production EXE resource 읽기 | PASS | production-icon-verification.json. LoadLibraryExW AS_DATAFILE로 실행하지 않고 resource101과 RT_ICON 7개가 ICO frame 원문과 모두 일치함을 확인 |
| MSI table/stream/CAB 읽기 | PASS | package/package-verification.json. payload EXE 일치, per-user/HKCU·파일 1개·service 0. MSI 설치 시퀀스 실행 없음 |
| Authenticode | EXE·MSI **NotSigned** | signature-verification.private.json |
| 최초 설치 시험 도구 집중 회귀 | **4 PASS / 0 FAIL** | first-install-scope-20261005/app-exit-tests.private.log. PID/class와 명시적 종료·명령 전송 실패 mock. 실제 설치 PASS가 아님 |
| 기존 설치 증거 판정 회귀 | **8 PASS / 0 FAIL** | first-install-scope-20261005/evidence-tests.private.log. 이번 재실행이며 실제 복구 PASS가 아님 |

아이콘·tray·UX·log의 고유 native 집중 결과는 **35 PASS**이다. 반복 실행과 manifest 활성화 재실행은 중복 합산하지 않는다. installer 도구 4+8은 별도 자동 mock/판정 회귀이며 실제 설치·복구에 합산하지 않는다. 이전 core 57·review 8 PASS는 변경 없는 source/test 지문을 확인해 재사용하며 새 실행으로 표시하지 않는다. 날짜·읽기 전용·가로 스크롤과 카드 UI의 2026-10-05 USER_CONFIRMED는 당시 사용자 범위로 보존하며 새 아이콘 인수로 확대하지 않는다.

최종 tray의 첫 6회/마지막 6회 자원 peak는 handles 222/222, GDI 24/24, USER 32/32다. 종료 후 handles는 idle 220에서 208로 줄었다. 아이콘 source cache로 같은 크기의 요청이 핸들을 계속 만들지 않는 것을 함께 확인했다. 밝은·어두운 배경의 16~256px native BMP를 PNG로 변환해 직접 보고 작은 크기의 실루엣·외곽 투명도를 확인했다. 이는 실제 사용자 taskbar/notification area 픽셀 인수와 구분한다.

첫 icon C++ 컴파일은 Windows 매크로 small과 변수 충돌로 실패했다. 변수 이름만 고친 뒤 통과했다. 첫 리소스 검사 Python의 줄바꿈 literal syntax 오류도 고친 뒤 통과했다. 초기 로그·소스와 초기 검증 후보는 tests-icon, tests-icon-final, production-before-size-cache 및 icon-resource-first-attempt.private.log에 보존했다. 이 실패를 최종 runtime FAIL과 혼용하거나 삭제하지 않았다. 크기별 cache 최종 수정 이후 영향받는 icon·tray·UX·log를 전부 재검증했다.

## 새 EXE·MSI와 실행한 파일

실제 checkout은 <local-worktree>이며 detached HEAD 94b3e3360e12c75479e6a901f4fe2271672001a1과 보존한 미커밋 작업에 후속 변경을 더했다. <original-workspace>의 기존 작업에 쓰지 않았다. 아래 지문은 새 파일에서 직접 계산했다.

| 산출물 | 실제 checkout 아래 경로 | 크기·last write KST | SHA-256 |
|---|---|---|---|
| 최종 EXE | artifacts/download-version-manager-watcher/icon-20261005/production/DownloadVersionManager.exe | **372,224 bytes** · 2026-10-05 16:22:35 | 3cddb6e185c7f1741cce6bb9b5b91f9afb3898a7a983598cfdc976e1be592abd |
| 최종 무서명 MSI | artifacts/download-version-manager-watcher/icon-20261005/package/DownloadVersionManager-Watcher-0.2.1-x64.msi | **380,928 bytes** · 2026-10-05 16:24:53 | ff3d0b2746d5733b75621ece88a2aa94e93e25e0e97fdf78beb20a42507c2796 |

추출한 실제 payload은 package/package-extraction-1c0f5302d7844aafafe9808e8202b8ec/payload/ApplicationExe이다. 그 파일·package/DownloadVersionManager.exe·production/DownloadVersionManager.exe가 모두 372,224 bytes이고 EXE SHA-256이 같다. production/production-build-manifest.json, package/build-manifest.json, artifact-fingerprints.json, SHA256SUMS.txt가 최종 source·asset·EXE·MSI를 연결한다. 이전 tray-20261005 산출물 지문은 역사적 값으로 보존하고 최신 후보의 값으로 재사용하지 않았다.

실제 실행한 native 파일은 이 evidence 아래 verified-icon/DownloadVersionManager.Icon.Tests.exe, verified-tray/DownloadVersionManager.Tray.Tests.exe, verified-ux/DownloadVersionManager.Ux.Tests.exe, verified-log/DownloadVersionManager.Log.Tests.exe다. 각 전체 경로·크기·지문은 artifact-fingerprints.json에 고정했다. 네 시험은 최종 app.cpp와 동일 아이콘 resource를 사용한다. production EXE는 컴파일·리소스/manifest 읽기·패키징만 했고 wWinMain은 실행하지 않았다.

새 EXE 전체 실행 전에는 기존 앱의 확인된 정상 종료 경로로 프로세스가 끝난 것을 확인한다. 트레이 수정본은 **종료**를 사용하며 X는 숨김이다. 이전 버전에 그 메뉴가 없으면 확인된 기존 정상 종료 경로를 사용한다. 기존 앱이 남아 있으면 singleton이 그 창만 열 수 있으므로 새 빌드 실행 성공으로 기록하지 않는다. 이번 작업에서 사용자 앱 종료·교체는 수행하지 않았다.

## 최초 설치 우선순위·보존·제한

일반 배포 대상은 **0.2.1 최초 설치 → 정상 실행 → 명시적 종료 → 제거**를 먼저 확인한다. 최초 설치 실패·취소 복구는 별도 안전 항목이다. 사용자 PC의 0.2.0 업그레이드는 개인 선택 경로로 분리한다. 현재 계정에는 0.2.0 설치와 실행 설정이 있어 preflight가 차단하며 전용 snapshot 환경도 없다. 따라서 정상 lifecycle은 NOTRUN, 실패·취소 복구는 BLOCKED / 실제 PASS 0이다. 승인된 환경에서 이 최신 MSI로 정상 경로만 수행하는 준비 명령은 [최초 설치 검증 범위](download-version-manager-first-install-scope-20261005.md)에 기록했다.

기존 미커밋 원문과 진단은 baseline·역사적 보고서를 보존했다. TEST_RESULTS·KNOWN_LIMITATIONS와 명세의 후속 내용은 기존 파일 뒤에 추가했다. 최초 설치 도구는 X 숨김으로 인한 timeout을 막는 종료 helper만 변경했고 installer_evidence.py·installer_windows_evidence.py·기존 판정 test는 같다. source engine/watcher/review/ui·manifest와 installer WXS/config는 tray 기록의 지문과 같다. 보존 결과와 후속 diff는 preservation.json 및 icon-only.patch에 기록한다.

실제 Explorer 재시작·로그오프, engine 이름 변경 도중 종료, 실제 production singleton 재실행과 물리 taskbar/tray 확인은 NOTRUN이다. 현재 설치본 교체·제거, 실패 주입·강제 종료·보안/ACL 변경, commit/push/PR/tag/release/게시·배포는 하지 않았다. 로컬 무서명 후보이며 상용 승인 상태로 표시하지 않는다. 새 아이콘 작업에 필요한 추가 사용자 결정은 없다.

문서 strict 빌드와 생성 로컬 링크 검사 PASS: 공개 19개·이전 이동 2개·404, 검색·사이트맵 공개 범위 확인. 저장소 source 로컬 링크와 git diff --check도 PASS다. docs-strict.log·site-links.log·final-checks.json에 기록한다. 내부 delivery·진단·자산 산출물은 공개 사이트에 추가하지 않았다. 게시 없음.
