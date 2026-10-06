# DVM · UX 개선과 로컬 MSI 제작 기록

기록일: 2026-10-05 KST · 대상: DownloadVersionManager 0.2.1 무서명 로컬 후보 · 상태: UX·EXE·로컬 MSI 제작/구조 검증 완료, 설치·공개 미반영

사용자는 수정된 EXE의 날짜 이름·읽기 전용 보존 이유·긴 로그 수평 스크롤을 직접 확인한 뒤, 원래 처리 기능을 유지하면서 상용 품질 수준의 UX로 개선하고 로컬 MSI를 만들어 달라고 요청했다. 이 요청은 UX 개선과 로컬 패키지 제작의 승인이다. 설치·제거·repair·upgrade, 설치 실패 주입과 원격 공개는 포함하지 않는다. 무서명·설치 복구 미검증 상태를 상용 출시 승인으로 표시하지 않는다.

관련: [0.2.0 명세](../tools/download-version-manager/next-version-specification.md) · [폴더 입력 설계](../design/0028-download-version-manager-folder-input.md) · [날짜·보존 이유 설계](../design/0031-download-history-mtime-guidance.md) · [앞선 검증과 후속 사용자 확인](download-version-manager-mtime-guidance-20261005.md).

## 작업 기준과 보존

실제 작업 경로는 <local-worktree>이며 기준 HEAD는 94b3e3360e12c75479e6a901f4fe2271672001a1이다. 앞선 날짜·안내 변경과 설치 진단 작업은 미커밋 상태다. 시작 시 tracked/untracked 변경 전체를 artifacts/download-version-manager-watcher/ux-package-20261005/baseline에 보관하고 baseline.json에 지문을 기록했다. 원래 요청 경로 <original-workspace>와 실제 DVM 경로가 다른 이유는 앞선 기록을 따른다.

설치 진단 스크립트와 TEST_RESULTS.md·KNOWN_LIMITATIONS.md를 기존 내용 그대로 보존한다. 공개 안내의 설치 실패 복구 후속 단락을 수정하지 않는다. 설치 복구의 원인 미확정·BLOCKED와 기존 실패 기록도 유지한다. 이 기록은 기존 시험 기록을 덮어쓰지 않는 후속 기록이다.

## 요구와 완료 기준

| 요구 | 구현 범위 | 충분한 완료 근거 |
|---|---|---|
| 기능을 유지한 UX 개선 | 감시 위치·현재 상태·사용자 행동과 처리 결과를 기존 창에서 읽기 쉽게 배치하고 짧은 안내 사용 | 변경된 화면의 구조·문구·크기 대응·상태별 표시 확인, 원래 처리 함수·설정·보호 계약 보존 |
| 검증한 날짜·보존 안내 유지 | actual handle mtime, 확인된 읽기 전용 원인, 긴 로그의 수평 스크롤 | 관련 코드가 유지되면 앞선 자동·USER_CONFIRMED 근거 재사용. 영향이 있는 변경만 최종 diff에서 재확인 |
| 로컬 MSI 제작 | 기존 per-user/HKCU·자체 포함 payload와 MSI 제작 경로 사용 | 최종 EXE·MSI 빌드 결과, MSI 구조·내장 payload와 source manifest 연결, 파일 경로·SHA-256 |
| 설치 복구의 정확한 상태 | 이번 작업에서 설치 실패 시험이나 설치본 변경 없음 | 기존 BLOCKED/NOTRUN 보존, 향후 환경·시험·동등성·전후 증거를 별도로 정의 |

동일 내용의 신규 객체 원래 이름 승계, 다른 이전 내용만 History 보관, 3초 안정·잠금·동시 후보 보존, 최초 그룹 선택, 감시 시작·중지·종료, 사용자 폴더·기본 다운로드 위치 추종과 로그인 자동 실행 계약을 유지한다. UI 개선을 계기로 자동 재시도·권한 변경·새 처리 정책을 추가하지 않는다. 직접 덮어쓴 이전 내용을 복구하거나 Explorer의 충돌 선택 화면을 바꾸는 기능은 없다.

## 기존 근거와 후속 사용자 확인

| 근거 | 구분 | 재사용 범위 |
|---|---|---|
| 앞선 날짜·안내 최종 diff의 63 PASS / 0 FAIL | 당시 결과 보존 | 이번에 63개를 다시 실행하지 않음. 변경된 review 5개·log 1개는 아래 새 17개 안에서 다시 검증 |
| 변하지 않은 core 57 PASS | 기존 결과 재사용 | engine 27 + watcher 15 + formatter 13 + Host JSON 2. 해당 source/test 8개 지문이 앞선 final-manifest와 모두 같음을 확인. 이 해시 확인을 새 런타임 PASS로 세지 않음 |
| 수정 EXE의 History 이름 날짜 | USER_CONFIRMED, 2026-10-05 | 실제 보관 파일의 마지막 수정 시각을 사용한 해당 사용자 사례 |
| 수정 EXE의 읽기 전용 보존 이유 | USER_CONFIRMED, 2026-10-05 | 해당 안내가 읽힌 사용자 사례 |
| 수정 EXE의 긴 로그 수평 스크롤 | USER_CONFIRMED, 2026-10-05 | 해당 화면 사례. 모든 DPI·화면 크기·새 UX 표시 검증은 아님 |
| 앞선 실제 픽셀 가독성 NOTRUN | 당시 결과 보존 | 이후 USER_CONFIRMED를 덧붙였으며 과거 실행을 PASS로 고치지 않음 |
| 설치 진단 판정 회귀 8 PASS | 기존 자동 결과 재사용 | 판정 로직 근거. 실제 설치 복구 PASS는 아님 |

## 최종 구현과 최소 변경

| 변경 파일 | 최소 변경과 이유 |
|---|---|
| source/ui.h | Win32 공유 색·글꼴·카드·버튼 렌더링. 밝은 slate 배경, 흰 카드, 파란 기본 행동, Segoe UI 본문 16/제목 26/구역 18 DIP로 두 창의 표시를 일치시킴 |
| source/app.cpp | 감시 상태·폴더·기록을 순서대로 배치. 비어 있는 기록/200건 개수, 읽기 전용 경로 복사, 기존 native Tab·access-key 표시, 창 크기/DPI 대응. 900×800 기본과 720×640 DIP compact 배치·작업영역 제한, 오류 중지 시 idle 안내도 갱신 |
| source/review.cpp | 기존 초기 확인 창을 같은 표시로 개선. 파일 선택과 순서 확인을 나눠 표시하고 820×720 DIP 최소 크기·resize/DPI에 대응. 선택 초기값 -1·실행 가드·원래 파일 선택 보존·닫기/Esc 취소·snapshot 대조·처리 순서는 유지 |
| source/watcher.manifest | 별도 watcher의 0.2.1 identity, Common Controls v6·PerMonitorV2·longPathAware와 asInvoker. 기존 Host manifest와 설치 권한은 변경하지 않음 |
| tests/watcher/ux_smoke.cpp, ui_capture.h | 실제 app windowProc의 합성 HWND/임시 기록 시험과 native render capture. 설정 읽기/쓰기·감시 시작·사용자 폴더 처리 없이 UX 검증 |
| tests/watcher/review_smoke.cpp, log_smoke.cpp | 기존 기능 5개에 초기 확인 UI 3개를 추가하고 변경된 app 로그를 재검증. 합성 창·임시 fixture만 사용 |
| build/build-watcher.py | local 0.2.1, UX 시험 연결. compile-only와 package-only 분리, production source/EXE 지문과 정확한 EXE에 대한 UX 결과 연결 후 동일 EXE 패키징 |
| build/verify-watcher.py | MSI stream/CAB를 읽고 압축 해제해 payload 지문 검사. 검증을 위해 msiexec를 실행하지 않음. 이전 0.2.0 fixture로 도구 회귀 확인 |
| README.md, next-version-specification.md, 앞선 mtime 기록의 후속 절, 이 기록 | UX·로컬 MSI 제작 요구와 새/재사용/사용자 확인/미실행 근거 구분. 기존 mtime 기록은 원문 전체를 prefix 그대로 보존하고 USER_CONFIRMED 3건만 뒤에 추가 |

엔진·watcher·Host 처리 코드는 이번 후속 단계에서 변경하지 않았다. app의 설정·폴더 선택·singleton·시작 인수, review의 scan/capture·보호 대조·processGroup/reviewExisting 흐름은 baseline과 같다. 초기 사용자 동의 없는 실행이나 강제 권한 변경을 추가하지 않았다. 코드/표시 품질 개선은 상용 승인이나 모든 환경 인증을 뜻하지 않는다.

## 실행 환경과 명령

Windows 11 x64 23H2 build 22631.6199, 일반 사용자/non-elevated token, 로컬 NTFS. Python 3.12.14, 기존 MSVC x64·Windows SDK 10.0.26100.0, C++17 /MT /W4 /WX /guard:cf. 실제 작업 기준은 위 detached HEAD 94b3e3360e12c75479e6a901f4fe2271672001a1과 미커밋 후속 diff다. Node child_process.execFile과 windowsHide=true로 실행했으며 관리자 권한·보안 정책을 변경하지 않았다.

아래 Python은 <local-python>, MSVC는 <original-workspace>/.tools/image-copy-save-native/msvc, SDK는 같은 image-copy-save-native/sdk, WiX는 <original-workspace>/.tools/wix/wix.exe다. 표의 evidence는 artifacts/download-version-manager-watcher/ux-package-20261005 아래를 뜻한다.

| 실행/검토 | 기대값 | 최종 결과 | evidence |
|---|---|---|---|
| build-watcher.py --compile-only --msvc MSVC --sdk SDK --output-dir evidence/production | 시험 hook 없는 0.2.1 EXE·static CRT·production source/hash manifest, MSI 미생성 | production EXE 빌드 PASS | production/compile.log, imports.log, production-build-manifest.json |
| build-watcher.py --test-only ux --msvc MSVC --sdk SDK --output-dir evidence/ux-production-theme; 해당 UX EXE를 production-manifest-fixture와 production/DownloadVersionManager.exe 인수로 재실행 | 900×800·compact 720×640·simulated 144 DPI geometry/render, 읽기 전용 경로 문자열, 상태별 버튼, watcher 미시작, native GetNextDlgTabItem, 200건/빈 화면, 긴 기록 범위. 마지막 실행은 정확한 production EXE의 manifest를 ActivateActCtx로 활성화 | 8 PASS / 0 FAIL | ux-production-theme/production-manifest-tests.log |
| build-watcher.py --test-only review --msvc MSVC --sdk SDK --output-dir evidence/review | UI normal/minimum 820×720/simulated 144 DPI 3개와 no-consent/skip/chosen-latest/외부 변경/읽기 전용 보호 5개 | 8 PASS / 0 FAIL | review/review-tests.log, review-fixtures-*/ |
| build-watcher.py --test-only log --msvc MSVC --sdk SDK --output-dir evidence/log | 실제 변경된 app 로그의 전체 이름 저장·이유/상태/오류·수평 범위 | 1 PASS / 0 FAIL | log/log-tests.log |
| production-resource-check.py production EXE | 내장 asInvoker/Common Controls v6/PerMonitorV2/longPathAware/0.2.1 identity | 정적 자원 검사 PASS, 런타임 수에 더하지 않음 | production-resource-check.json |
| package-gates.private.py | source/EXE/UX hash 불일치와 UX FAIL을 패키징 전에 거절 | 도구 회귀 4 PASS, 제품 런타임 수와 별도 | package-tools-check/package-gates.private.json, private.log |
| build-watcher.py --package-only --exe evidence/production/DownloadVersionManager.exe --production-manifest evidence/production/production-build-manifest.json --ux-verification evidence/ux-verification.json --msvc MSVC --sdk SDK --wix WiX --output-dir evidence/package | exact production EXE를 넣은 0.2.1 로컬 MSI, per-user/HKCU·자체 포함·금지 자원·내장 payload 지문 | MSI 제작과 읽기 전용 구조/payload 검사 PASS, 설치 수명주기 NOTRUN | package/package-command.private.json, build-manifest.json, package-verification.json |
| verify-watcher.py의 기존 0.2.0 fixture 읽기 | MSI 실행 없이 stream/CAB 추출·payload 지문 확인 | 도구 회귀 PASS, 새 후보 설치 검증 아님 | package-tools-check/read-only-verifier.final.log |

새 고유 런타임 결과는 **17 PASS / 0 FAIL**이다. main 8개를 intermediate와 정확한 production manifest로 반복한 결과는 한 번만 센다. 앞선 63개 전체를 다시 실행하지 않았으며 unchanged core 57개와 진단 판정 8개는 재사용으로 표시한다. review 5개·log 1개는 새 17개 안에서 다시 검증했으므로 과거 결과와 중복 합산하지 않는다. 빌드·정적 자원·도구 회귀·소스 해시·문서 검사도 제품 런타임 수에 더하지 않는다.

초기 int/LONG max 컴파일 오류를 수정했고, review smoke가 WM_CREATE 직후 visible 상태 전에 판정하던 race를 바로잡은 뒤 최종 8 PASS를 얻었다. 첫 컴파일의 전체 원본 로그는 재실행 때 덮어써졌고, 당시 tool-result에서 보존한 부분 발췌는 initial-compile-attempt.private.txt에 남겼다. 이를 전체 컴파일 로그라고 표시하지 않는다. review-test-compile.initial-failure.log는 컴파일 성공 출력이며, 실제 초기 review 런타임 FAIL은 review-tests.initial-failure.log/first-failed.log에 보존했다. 최초 결과를 숨기거나 최종 PASS 수에 중복 합산하지 않았다. 감사에서 발견한 감시 오류 종료 후 stale hint와 작업영역을 넘는 main 최소 크기는 최종 compact/idle 표시 수정에 반영했다.

합성 native UI 화면은 ux-production-theme/production-manifest-fixture/main-native-normal.png와 main-desktop-capture.png다. 첫 파일은 실제 HWND를 화면 밖에서 정확한 production manifest로 렌더링한 근거이고, 두 번째는 합성 UI를 잠시 표시해 GetDC로 캡처한 근거다. 두 화면을 확인해 exact v6 theme의 경로와 physical GetDC capture의 경로/목록 테두리가 보이는 것을 확인했다. 사용자의 다운로드·History·설정에 쓰거나 watcher를 시작하지 않았다. production 앱 전체 실행·실제 다중 모니터 전환 검증으로 확대하지 않는다.

## 미실행과 적용 상태

| 항목 | 판정과 이유 |
|---|---|
| 정확한 production EXE의 wWinMain 전체 시작 | NOTRUN. <external-standalone-exe>의 기존 사용자 프로세스 PID <existing-user-pid>이 실행 중이므로 종료·재실행하거나 singleton/설정을 건드리지 않음. 동일 소스의 HWND 시험과 내장 manifest 검사를 구분함 |
| 모든 물리 DPI·모니터 전환·조직 정책·새 사용자 환경 | NOTRUN. normal/compact 및 simulated 144 DPI geometry·native render만 확인 |
| 기존 수정 EXE의 날짜·읽기 전용 이유·긴 로그 스크롤 | USER_CONFIRMED 3건, 2026-10-05. 새 0.2.1 전체 사용자 인수 시험으로 확대하지 않음 |
| 설치·제거·repair·upgrade·설치 실패/취소·실패 후 정상 재시도 | BLOCKED/NOTRUN. 승인된 전용 snapshot Windows 환경 없음. 실제 설치 복구 PASS 0 |
| 현재 설치본 반영·공개 배포 | 미반영. 새 version 0.2.1은 무서명 로컬 후보이며 공개 0.2.0 자산은 그대로 |

commit/push/PR/merge/tag/release/deploy, 사용자 프로세스 종료, 관리자 실행·ACL/보안 변경·Installer 등록 삭제를 하지 않았다. Watcher.wxs와 설정 DLL 소스는 HEAD diff 0이며 기존 installer 진단 7개는 시작 지문과 같다. 원래 <original-workspace>의 Excel 수정 2개와 기존 미추적 작업도 그대로다. preservation.json에 7개/핵심 입력 8개/이전 기록 prefix의 일치 근거를 보관한다.

## 생성물과 패키지 연결

production EXE 경로는 evidence/production/DownloadVersionManager.exe이며 SHA-256은 98c298e32a863e3cec85d8ed75cc91f95b00895f31ac79bfeb199726e8940a21이다. production-build-manifest.json과 ux-verification.json이 같은 EXE 지문과 source binding을 기록한다. compile-only는 패키징 전에 종료하며, package-only는 source·EXE·UX 지문을 확인하고 재컴파일 없이 동일 EXE를 넣는다. 패키징 뒤 EXE/source 지문도 다시 확인한다.

다음 로컬 MSI는 같은 production EXE를 포함한다. package/build-manifest.json과 package/package-verification.json이 양쪽 지문을 연결한다.

| MSI 항목 | 최종 값 |
|---|---|
| MSI 파일 경로 | artifacts/download-version-manager-watcher/ux-package-20261005/package/DownloadVersionManager-Watcher-0.2.1-x64.msi |
| MSI SHA-256 | d296b4d73954e1facc495f95bf1d0ec18f26f6acebab8adced2b046b946aac60 |
| 내장 payload·구조·제작 연결 | PASS · perUser=true, 내장 EXE 1개, services=0, 확장/Native Messaging 없음, HKCU Run 사용자 선택 기본 켜짐. stream/CAB 읽기·압축 해제로 내장 EXE SHA-256 98c298e32a863e3cec85d8ed75cc91f95b00895f31ac79bfeb199726e8940a21이 production/패키지 EXE와 같음을 확인. MSI 실행 없음, lifecycle NOTRUN |

산출물 계보도 구분한다. 앞선 mtime-guidance의 사용자 확인 EXE SHA-256은 7f45895083266a1125eb2e349c95fb404531abf4088e89cdaee70fc172c8a5fb이며 새 98c298e32a863e3cec85d8ed75cc91f95b00895f31ac79bfeb199726e8940a21과 의도적으로 다르다. 차이는 UX·0.2.1 버전·watcher manifest이며 engine/watcher 지문과 기존 USER_CONFIRMED 근거는 보존한다. 새 MSI는 최종 동결 production EXE와 package/추출 EXE의 같은 바이트를 포함하지만 production 전체 시작은 NOTRUN이다. SHA256SUMS.txt와 final-manifest.json에 production/package EXE·MSI, 설정 DLL(c508d920c9179940c89372f4eabaf79e09d348537bca2ed42b4d39d44d3bdee7), 비공개 wixpdb·시험 EXE의 전체 경로와 지문을 보관한다. ux-package-only.patch는 기존 날짜·진단 작업을 제외한 후속 변경 14개 파일의 diff이며 마지막 문서 변경 뒤 갱신한다.

MSI의 File 1/Media 1/Registry 6/CustomAction 4/ServiceInstall 0/ServiceControl 0/CreateFolder 0을 package-table-proof.private.json에서 확인했다. 실패 주입 package는 만들지 않았다. 최종 MSI와 EXE의 Authenticode 상태는 모두 NotSigned이며 signature-verification.final.private.json에 보존했다.

로컬 제작·구조 확인은 설치·구동·복구 성공을 뜻하지 않는다. 코드 서명이 없으며 상용 출시 승인과 공개 자산 교체는 별도 요청이 필요하다.

## 문서와 작업 보존 검사

- PASS: python -m mkdocs build --strict, 이번 evidence의 site 출력. 생성 출력은 의도한 artifacts 하위 경로에서만 관리했다. docs-strict.log에 결과 보존.
- PASS: python scripts/check-site.py evidence/site. 공개 19개·이전 이동 2개·404와 생성 로컬 링크/검색/사이트맵을 확인했다. 새 검증 기록·ADR·진단·로컬 EXE/MSI는 공개 출력에서 제외된다. site-links.log에 보존했고 게시하지 않았다.
- PASS: git diff --check와 preservation.json의 기존 진단 7개·core 8개·mtime 기록 원문 prefix 보존. 이 문서의 로컬 링크도 최종 작성 후 확인한다.

## 설치 복구 시험을 재개할 환경

현재는 사용자에게 전용 Windows VM이 없으므로 설치 복구를 BLOCKED로 유지한다. 실사용 PC·계정의 반복 실패 주입, 관리자 실행, ACL/owner·보안 정책 변경, Windows Installer 내부 등록의 수동 삭제로 이 상태를 우회하지 않는다. 화면을 조작할 수 있거나 임시 시험 폴더만 있다는 이유로 격리됐다고 판단하지 않는다.

재개에는 사용자가 승인한 전용 Windows 11 x64 snapshot 복원 환경이 필요하다. 실제 machine·일반 사용자 SID가 승인 기록과 같고 non-elevated medium-integrity token이어야 한다. 승인·snapshot·환경 식별 근거를 보관하며 합성 감시 폴더와 업무파일 fixture만 사용한다. 각 시험 전에 snapshot 기준을 정하고 기존 설치 유무를 목적에 맞게 확인한다. 초기 시험은 기존 DVM 설치가 없는 기준, repair/upgrade 시험은 시험 환경에서 의도적으로 만든 기존 설치 기준이다.

현재 test-watcher-installer.py의 preflight는 기존 DVM 설치가 있으면 막는다. 기존 설치에 대한 repair/upgrade 실패·취소 시험은 이 preflight를 우회하지 않고 전용 시험 기준과 별도 승인된 시험 절차를 마련해야 한다. 현재 도구가 모든 아래 사례를 자동화한다고 설명하지 않는다.

## 향후 production/test MSI 동등성과 증거

실패 주입은 승인된 환경과 정확한 패키지 지문을 갖춘 후에만 진행한다. 당시 검증 대상 production MSI와 test MSI의 ProductCode·UpgradeCode·ProductVersion, 사용자 설치 scope·rollback 설정, File/Component/Registry/Shortcut/Directory/Upgrade/Media/UI/ControlEvent 테이블을 대조한다. 내장 CAB와 설정 DLL·custom action Binary stream의 SHA-256도 같아야 한다. 허용하는 차이는 지정한 시험 전용 실패 action과 실행 순서뿐이다. 각 주입 지점은 해당 시험 목적에 맞게 도달 여부를 증명한다.

새 로컬 후보는 당시 공개 0.2.0 파일과 바이트가 다를 수 있다. 새 후보의 복구 결과를 기존 공개 파일의 직접 재현 결과로 옮기지 않는다. 어느 production/test 쌍을 시험했는지 양쪽 SHA-256·PackageCode·제작 source manifest로 연결한다. 기존 초기 주입 MSI가 공개본과 비동등했던 한계와 오류 5/1307·제품 등록 잔류는 그대로 보존한다.

각 시험 직전과 실패·취소 직후, 재시도나 정리 전에 evidence를 먼저 저장한다. 증거는 다음을 포함한다.

- OS·machine·SID·token·snapshot·명령·시각·MSI 지문과 verbose MSI 로그, 종료 코드, 취소 또는 주입 지점의 실제 도달 여부.
- 제품 상태와 related products, HKCU 설정·Run·Uninstall·Installer Products/UpgradeCodes 및 HKLM 사용자별 Installer 등록, 값을 읽을 수 있었는지와 owner/DACL.
- 합성 설치 폴더·바로가기·감시 폴더·기존 History의 존재/이름·내용 SHA-256·file ID·생성/수정 시각·속성·owner/DACL.
- 실패/취소 직후의 before/after 차이와 UNKNOWN 항목. 종료 코드 하나 또는 일부 파일 삭제만으로 복구 PASS를 판단하지 않음.

## 향후 복구 시험 목록 · 현재 모두 BLOCKED/NOTRUN

| 시험 | 승인된 환경에서 할 일 | 기대 결과와 판정 근거 |
|---|---|---|
| 초기 정상 설치 | 기존 DVM 없는 snapshot에서 production 설치·구동·공식 제거 | 선택 설정·등록·실행·사용자 파일 보존과 제거 결과 기록. 복구 실패 시험과 별도 근거 |
| 초기 설치 취소 | 위자드 진행 전후와 transaction 진행 중 도달 가능한 취소 경계에서 사용자 취소 | 실행 전 상태로 복원, 사용자 fixture 불변, 제품 등록 잔류 없음. 실제 취소 지점과 전후 snapshot 확인 |
| 초기 설치 늦은 실패 | 동등 test MSI로 payload/등록 변경 뒤 지정 late-failure 주입 | 주입 도달·예상 실패 코드와 완전한 전후 복원 일치. 5/1307 등 오류와 미확인 보안 상태 보존 |
| 기존 설치 repair 실패/취소 | production으로 만든 기존 설치·설정·사용자 fixture를 기준으로 repair 중 실패/취소 | 기존 프로그램·설정·등록·로그인 항목·사용자 데이터가 시험 전 상태로 복구되고 기존 제품 구동 가능 |
| 기존 설치 upgrade 실패/취소 | 실제 의도된 버전·UpgradeCode 관계의 구버전을 시험 환경에 설치한 뒤 새 후보 upgrade 실패/취소 | 구버전 설치·등록·설정·구동과 사용자 데이터 보존. 가상의 버전 조합이나 같은 버전 repair를 upgrade PASS로 세지 않음 |
| 실패/취소 후 정상 재시도 | 해당 사례의 완전 복원 PASS를 확인한 뒤 같은 목적의 production 설치/repair/upgrade 재시도 | 1638 등 등록 잔류로 막히지 않고 목적 동작 완료, 사용자 데이터 보존. 복원·재시도 결과 각각 기록 |

복원 후 차이가 남으면 FAIL, 증거가 불완전하거나 UNKNOWN이면 NOTRUN/BLOCKED로 남긴다. 복구 PASS를 얻지 못한 상태에서는 정상 재시도나 자동 제거로 증거를 바꾸지 않는다. 환경 snapshot 복원은 증거를 저장한 뒤 다음 시험의 기준 준비에만 사용하며 제품의 자동 복구 성공으로 세지 않는다.
