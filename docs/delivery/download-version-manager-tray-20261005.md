# DownloadVersionManager · 창 닫기와 트레이 유지 · 2026-10-05

상태: 로컬 0.2.1 EXE·무서명 MSI 제작 및 집중 검증 완료. 현재 설치본·공개 자산 미반영. 설치 실패 복구 BLOCKED, 실제 복구 PASS 0.

관련: [요구 명세](../tools/download-version-manager/next-version-specification.md), [ADR-0032](../design/0032-download-version-manager-tray-lifetime.md), [추가 도구 개발 기준](../policies/tools.md), [이전 UX·패키지 근거](download-version-manager-ux-package-20261005.md).

## 바뀐 동작과 작업 경계

감시 창의 X·Alt+F4가 사용하는 일반 닫기 요청은 기존 HWND를 숨긴다. 작업표시줄로 최소화하지 않는다. 트레이의 열기·더블클릭은 같은 창을 표시·활성화하며 로그·폴더·중지/감시 상태와 최대화 상태를 유지한다. 숨김과 재열기는 watcher를 시작·중지하거나 설정·타이머를 다시 만들지 않는다.

트레이 종료는 감시 stop/join 후 창을 파괴한다. 대기 중인 ReportMessage payload, 아이콘, registry 알림·event·timer·font를 정리한다. Windows 세션 종료 질의는 TRUE로 허용하며 취소된 종료는 그대로 둔다. 확정된 종료는 숨김을 거치지 않고 안전한 정리 경로를 사용한다. 최소화 버튼과 로그인 자동 실행·시작 표시·감시 시작 정책은 유지했다.

아이콘 최초 등록·유실 확인·Explorer TaskbarCreated 재등록에 실패하면 창을 유지하거나 복원하고 기존 처리 기록에 오류를 남긴다. TaskbarCreated 메시지 등록 자체가 실패해도 숨기지 않는다. 새 팝업·설정·서비스·감시 프로세스·IPC는 추가하지 않았다. 기존 singleton의 FindWindow와 복원 경로를 재사용하며 숨은 창도 같은 HWND로 표시한다.

메뉴는 Windows의 TrackPopupMenu 규칙에 따라 소유 창을 활성화하고 메뉴 종료 뒤 WM_NULL을 게시한다. [Microsoft 공식 API 문서](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-trackpopupmenu)를 확인했다. 메뉴 종료와 별개로 명시적 종료는 직접 안전한 정리 경로를 호출한다.

현재 설치본의 교체·제거, msiexec 실행, 설치 실패 주입·복구, 사용자 앱 강제 종료, Explorer 재시작·실제 로그오프, 관리자·보안/ACL 변경, commit/push/PR/merge/tag/release/게시/배포는 수행하지 않았다.

## 실제 작업 위치와 보존

처음 전달된 <original-workspace>는 main 89219d0f11c582fdb3649cb80527ee9c73defdd8이며 대상 도구가 없었다. git worktree 목록에서 요청의 카드 UI와 설치 진단 미커밋 작업이 있는 <local-worktree>를 확인했다. 해당 checkout은 detached HEAD 94b3e3360e12c75479e6a901f4fe2271672001a1이다. checkout/pull/reset/clean/stash는 실행하지 않았다.

시작 시 dirty 29개 파일, staged diff 없음, unstaged diff와 미추적 내용을 확인하고 artifacts/download-version-manager-watcher/tray-20261005/baseline 및 baseline.json에 모든 파일 원문·SHA-256을 저장했다. 이하 evidence 경로는 이 tray-20261005 디렉터리를 뜻한다.

| 이번 변경 파일 | 필요한 최소 변경 |
|---|---|
| tools/DownloadVersionManager/source/app.cpp | 아이콘·메뉴·복원·닫기/세션 종료·실패 fallback, 대기 로그 정리 및 기존 footer 안내 갱신 |
| tools/DownloadVersionManager/build/build-watcher.py | 기존 집중 시험에 tray target 연결만 추가. 0.2.1·패키지 identity·제작/UX gate 유지 |
| tools/DownloadVersionManager/tests/watcher/tray_smoke.cpp | 실제 HWND/임시 watcher와 Shell 모의 실패·실제 API 결과를 구분하는 집중 시험 |
| tools/DownloadVersionManager/README.md | 새 닫기·명시적 종료와 새 EXE 확인 안내 |
| docs/tools/download-version-manager/index.md, next-version-specification.md | 공개 0.2.0과 새 로컬 tray 행동 구분, 요구·근거 연결 |
| docs/design/0032-download-version-manager-tray-lifetime.md, docs/design/index.md | 창 수명과 감시를 분리한 결정과 실패 경로 |
| tools/DownloadVersionManager/TEST_RESULTS.md, KNOWN_LIMITATIONS.md | 기존 전체 원문 prefix를 보존하고 후속 범위·근거만 추가 |
| 이 기록 | 새 실행·재사용·USER_CONFIRMED·미실행·생성물 분리 |

이번 delta는 11개 파일이다. source/engine.cpp·engine.h·watcher.cpp·watcher.h·host.cpp·review.cpp·ui.h·manifest와 installer/Watcher.wxs·watcher-config.cpp는 시작 시 파일과 같다. 엔진·파일 보호·History 날짜/충돌·잠금/재시도·JSON/상태/기존 로그 계약은 변경하지 않았다.

기존 설치 진단 7개 중 test-watcher-installer.py, installer_evidence.py, installer_windows_evidence.py, tests/test_installer_evidence.py는 바이트 지문이 같다. TEST_RESULTS.md 35,701-byte 및 KNOWN_LIMITATIONS.md 9,966-byte 원문 prefix를 보존했다. 설치 안내 docs/tools/download-version-manager/index.md는 창 닫기/종료 문구와 로컬 tray 절만 갱신했고 기존 설치·복구 진단 내용을 보존했다. 다른 기존 dirty 파일 21개는 바이트 지문이 같으며 기존 mtime/UX delivery 기록도 변경하지 않았다. <original-workspace>의 별도 작업에는 쓰지 않았다. 최종 보존·diff 근거는 preservation.json과 tray-only.patch에 둔다.

## 이번 실제 시험과 이전 근거

Windows 11 x64 23H2 build 22631.6199, 비상승 일반 사용자, Python 3.12.14, 기존 MSVC x64·SDK 10.0.26100.0·WiX 4를 사용했다. Python 경로는 <local-python>다. MSVC/SDK는 <original-workspace>/.tools/image-copy-save-native/msvc 및 sdk, WiX는 .tools/wix/wix.exe다. 사용자 다운로드나 History는 시험 대상으로 사용하지 않았다.

| 이번 실행 | 최종 결과 | 근거와 범위 |
|---|---|---|
| build-watcher.py --test-only tray | 21 PASS / 0 FAIL | tray-final-shell-proof/tray-tests.log 및 tray-fixtures-5b58ebe1d31f4bf2bb4d54d5cf15399e/tray-results.json |
| 같은 소스의 실제 HWND 닫기·열기·메뉴·최소화/최대화·반복 상태 | 위 21개에 포함 | SC_CLOSE/WM_CLOSE 경로, 동일 창·child/log/state, 12회 반복 중 후반 자원 증가 없음 |
| 숨긴 실제 watcher의 합성 파일 이벤트·History·중지 상태 | 위 21개에 포함 | fresh fixture watched 아래에서 기존/신규 바이트와 History·로그 확인, stopped 후보는 보존 |
| 최초/유실/재등록 실패와 TaskbarCreated·세션 종료 메시지 | 위 21개에 포함, 모의 | Shell mock과 실제 windowProc. 실제 Explorer 재시작·로그오프 시험으로 확대하지 않음 |
| 실제 Shell_NotifyIconW add/modify/delete | 위 21개 중 1개, 실제 API | 별도 합성 HWND에서 각각 1회 BOOL TRUE. 실제 바탕화면 아이콘 픽셀 시험과 구분 |
| 트레이 종료·정리·대기 후보/로그 보존 | 위 21개에 포함 | watcher 종료, window/icon/font/registry/event 정리, 큐 payload 제거. 시험 EXE exit 0; engine 이름 변경 중 실제 종료는 미실행 |
| build-watcher.py --test-only ux 및 정확한 production manifest 활성화 재실행 | 8 PASS / 0 FAIL | ux-final/production-manifest-tests.log. 실제 HWND geometry/render·controls/log; manifest는 production-final EXE에서 읽음 |
| build-watcher.py --test-only log | 1 PASS / 0 FAIL | log-final/log-tests.log. 변경된 app 로그의 전체 이름·원인·상태·오류·수평 범위 |
| production compile-only 및 package-only | PASS, 런타임 수와 별도 | /MT·/W4·/WX, 외부 C/C++ runtime 없음, source/EXE 지문 일치, 동일 EXE 패키징 |
| MSI read-only table/stream/CAB 검사 | PASS, 설치 시험과 별도 | package/package-verification.json. 설치하지 않고 payload 일치 |
| Authenticode | EXE·MSI 모두 NotSigned | signature-verification.private.json |

새 고유 집중 자동 결과는 **30 PASS / 0 FAIL**이다(트레이 21 + UX 8 + 로그 1). 합성 HWND/모의 Shell·세션 분기와 실제 API/파일 이벤트를 위 표대로 구분한다. 반복 실행은 중복 합산하지 않는다. 빌드·소스/해시·문서/패키지 검사도 런타임 수에 합산하지 않는다.

첫 tray 실행은 17 PASS / 4 FAIL로 보존했다. 초기 비동기 watcher 시작 로그가 snapshot 이후 추가되는 시험 race와 메뉴/foreground 초기화 시점의 process-wide 자원 비교가 원인이었다. 진단 단계의 FAIL도 각 tray-debug·tray-handle-debug·tray-isolate-debug·tray-final 디렉터리에 보존했다. 반복 LoadIcon/ensureTray와 단순 hide/show는 핸들 증가가 없었고 foreground 활성화 후 자원이 안정되는 것을 따로 확인했다. 최종 시험은 시작 로그를 먼저 처리하고 초기화 뒤 첫 6회/마지막 6회 자원 peak 및 같은 HWND·child·state·log·아이콘 수를 비교한다. 최종 peak는 handles 219/219, GDI 18/18, USER 30/30이며 종료 후 핸들은 settled idle 217에서 209로 줄었다. 전 과정에서 제품 engine/watcher를 바꾸지 않았다.

종료 검토에서 대기 ReportMessage payload가 파괴된 HWND로 빠질 가능성을 확인해 stop/join 이후 큐를 직접 정리하도록 app.cpp를 보완했다. 그 최종 소스 뒤 tray 21·UX 8·log 1을 다시 확인했고 새 production EXE/MSI를 생성했다. 정확한 manifest UI 재실행의 Node 직접 spawn은 한 번 EPERM이었으며, 같은 시험 EXE를 정상 Python subprocess로 실행해 8 PASS를 얻었다. 권한·보안 설정은 바꾸지 않았다.

| 이전 근거 | 현재 구분 |
|---|---|
| 앞선 UX 집중 17 PASS | 역사적 결과 유지. 이번 main 8/log 1은 위 새 9개로 재검증, 변하지 않은 review 8은 이전 결과 재사용 |
| 기존 core 57 PASS | 이전 engine 27·watcher 15·formatter 13·Host JSON 2 결과 재사용. source/test 8개 지문을 mtime-guidance final-manifest와 대조해 모두 같음. 새 57 PASS가 아님 |
| 설치 진단 판정 8 PASS | 코드·시험 파일 그대로인 이전 자동 근거 재사용. 실제 설치 복구와 무관 |
| 날짜·읽기 전용·가로 스크롤 3종 | USER_CONFIRMED, 2026-10-05, 해당 사용 사례 |
| 새 카드 UI와 수정 전 현재 동작 | USER_CONFIRMED, 2026-10-05, 이번 요청에서 사용자 확인. 새 tray·모든 환경·설치/복구/upgrade 인수로 확대하지 않음 |

## 새 생성물과 실제 실행 경로

생성 기준은 위 detached HEAD와 보존한 미커밋 작업에 이번 11개 delta를 더한 최종 소스다. 기존 로컬 버전 0.2.1을 유지했다. production-final/production-build-manifest.json과 package/build-manifest.json이 source·EXE·MSI를 연결한다. EXE/MSI 크기와 SHA-256은 새 파일에서 직접 계산했다.

| 파일 | 경로·크기·시각·SHA-256 |
|---|---|
| 최종 EXE | artifacts/download-version-manager-watcher/tray-20261005/production-final/DownloadVersionManager.exe · **293,376 bytes** · 2026-10-05 15:41:35 KST · c8b8e729e373ce1ecc8622870205470fae898d43159612d45daed6c93bbafddb |
| 최종 무서명 MSI | artifacts/download-version-manager-watcher/tray-20261005/package/DownloadVersionManager-Watcher-0.2.1-x64.msi · **303,104 bytes** · 2026-10-05 15:46:33 KST · baf892b01a6899b941b9d40837edb9b5f636df334f30cf5adb41350fd4a418d7 |

경로는 실제 작업 checkout <local-worktree> 아래다. 시각은 최종 파일 last-write 기준이며 artifact-fingerprints.json에 UTC/KST를 함께 기록했다. 이전 98c298… EXE와 d296b4… MSI 지문은 이번 값으로 재사용하지 않았다.

MSI에서 읽기 전용으로 추출한 실제 EXE는 package/package-extraction-4122de049d2a4adb8bc4efa73dd41a5c/payload/ApplicationExe다. 이 파일과 package/DownloadVersionManager.exe, production-final/DownloadVersionManager.exe의 SHA-256이 모두 c8b8e729e373ce1ecc8622870205470fae898d43159612d45daed6c93bbafddb로 같다. MSI는 per-user/HKCU·내장 EXE 1개·service 0이며 기존 설치 정책을 유지한다. msiexec와 설치 시퀀스는 실행하지 않았다.

실제 실행한 시험 EXE 경로는 evidence 아래 tray-final-shell-proof/DownloadVersionManager.Tray.Tests.exe, ux-final/DownloadVersionManager.Ux.Tests.exe, log-final/DownloadVersionManager.Log.Tests.exe다. final-manifest.json에 이 파일들의 전체 경로와 새 지문을 기록한다. 정확한 production EXE는 manifest를 읽고 패키징했지만 wWinMain 전체 실행은 하지 않았다.

현재 실제 사용자 앱 PID <existing-user-pid>의 경로는 <external-standalone-exe>다(process-paths.private.json). 이를 종료·교체하거나 새 EXE 실행으로 기존 인스턴스만 열리는 동작을 새 빌드 구동으로 기록하지 않았다. 새 EXE를 직접 확인하려면 기존 앱의 트레이 종료로 프로세스 종료를 확인한 뒤 실행한다. 트레이 종료 메뉴가 없는 이전 버전은 그 버전의 확인된 정상 종료 경로를 사용한다. X는 이번 수정본에서 완전 종료가 아니다.

## 미실행·제한과 최종 문서 검사

| 항목 | 판정과 이유 |
|---|---|
| 실제 제목 X 클릭·키보드 Alt+F4, 물리 트레이/작업표시줄 픽셀 | NOTRUN. 공통 native SC_CLOSE/WM_CLOSE와 HWND visibility만 실행, 실제 사용자 앱의 UI 조작 없음 |
| 실제 Explorer 재시작 | NOTRUN. TaskbarCreated와 Shell 실패 모의만 실행; 실사용 Explorer 강제 재시작 없음 |
| 실제 Windows 로그오프/종료 | NOTRUN. query/canceled/confirmed 메시지 모의만 실행; 실제 세션 변경 없음 |
| engine 이름 변경의 한가운데에서 종료 | NOTRUN. 안정화 대기 후보의 정상 Exit 보존과 기존 stop/join 검토만 수행. 강제 중단 시험을 새 PASS로 쓰지 않음 |
| 최종 production wWinMain·실제 singleton 두 번째 실행 | NOTRUN. 기존 사용자 앱이 실행 중이며 안전한 종료/분리 조건 없음. FindWindow와 같은 복원 helper는 코드 검토·합성 HWND 복원 근거 |
| 실제 설치·repair·upgrade·제거·취소·실패 복구 | BLOCKED/NOTRUN. 승인된 전용 snapshot Windows 환경 없음. 실제 복구 PASS 0 유지 |
| 현재 설치본·공개 배포 반영 | 미반영. 무서명 로컬 후보이며 상용 승인 아님 |
| 문서 strict·생성 로컬 링크·source 로컬 링크·git diff 검사 | PASS. docs-strict.log, site-links.log, final-checks.json에 근거. 공개 19개·이전 이동 2개·404 및 공개 범위만 검사, 새 내부 기록·진단·로컬 산출물은 사이트 제외. 게시 없음 |

문서 빌드의 첫 bundled Python 호출은 mkdocs 모듈이 없어 실패했다. 기존 <original-workspace>/.tools/doc-deps의 저장소 지정 의존성을 PYTHONPATH로 해당 프로세스에만 연결해 python -m mkdocs build --strict와 scripts/check-site.py를 통과했다. 새 설치나 시스템 환경 변경은 없으며 첫 실패 로그도 보존했다.

사용자에게 영향 없는 기존 전체 정상 흐름의 수동 재시험을 요구하지 않는다. 이번 로컬 작업을 위해 필요한 새 사용자 결정은 없다. 실제 새 EXE 전체 실행과 설치·복구는 위 안전한 조건을 확보한 별도 범위다.
