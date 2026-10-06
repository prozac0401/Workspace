# DVM · 수정 시각과 보존 이유 안내 검증 기록

기록일: 2026-10-05 KST · 대상: DownloadVersionManager 0.2.0 로컬 소스 · 상태: 코드 개선·검증 완료, 설치·게시 미반영

요구: 새 History 이름은 실제 보관 객체의 마지막 수정 시각을 사용하며 기존 보관 이름·파일 보호를 유지한다. 확인된 읽기 전용 보호와 다른 접근 실패를 짧게 구분한다. 완료 근거는 변경 영역의 자동 시험·공용 소비처 빌드·문서 검사이며 설치 복구는 독립된 BLOCKED 항목이다. [요구사항](../tools/download-version-manager/next-version-specification.md) · [설계 결정](../design/0031-download-history-mtime-guidance.md).

## 실제 작업 기준과 기존 변경 보존

- 요청 경로 <original-workspace>는 main HEAD 89219d0f11c582fdb3649cb80527ee9c73defdd8, origin/main 추적(로컬 캐시 기준 103 commits 뒤)이다. DVM 소스가 없으며 Excel 문서 2개 수정과 기존 미추적 파일들이 있다. 이 폴더는 읽기만 했으며 checkout/pull/reset/clean/stash를 하지 않았다.
- 실제 DVM 변경 경로는 <local-worktree>이다. HEAD는 94b3e3360e12c75479e6a901f4fe2271672001a1, detached HEAD이고 추적 브랜치는 없다. 시작 시 staged diff는 없고 설치 진단 4개 tracked 수정 + 3개 신규 파일이었다. origin/main 로컬 참조는 c866435e278d84d4a110b5c3b23101e6dab53628이다. 최신 원격 상태로 가정하거나 fetch하지 않았다.
- HEAD와 제시된 c866435e의 DVM 경로 차이는 사용자 안내 index.md뿐이며 engine·watcher·host·review 소스는 동일하다. 제시된 과거 줄 번호를 현재 소스와 대조했다. AGENTS.md, 원 명세·0.2.0 명세·ADR·빌드·시험 안내와 문서/도구 정책을 읽었다. 해당 checkout에는 .agents/skills가 없다.
- 관련 기존 Codex 작업은 idle/notLoaded이고 같은 로컬 경로에서 활성 편집 중인 다른 작업은 발견하지 못했다. 이번 하위 작업은 엔진/문구, 문서, 시험을 서로 다른 파일로 분담했고 최종 소스 검토는 읽기만 했다.
- 시작 전 7개 파일을 비공개 evidence/baseline에 복사하고 기존 진단 manifest의 7개 SHA-256 모두와 일치함을 확인했다. 설치 진단 스크립트 4개, TEST_RESULTS.md, KNOWN_LIMITATIONS.md는 최종 바이트가 모두 동일하다. 겹친 index.md는 날짜·문구 안내만 수정했고 기존 ‘설치 실패 복구의 후속 확인’ 단락은 바이트 그대로 보존했다. 별도 기록을 사용해 기존 TEST_RESULTS.md에 시험 결과를 덧붙이지 않았다.

## 사용자 확인 결과

아래는 2026-10-05 사용자 확인이며 이번 자동 시험 결과와 별개다. 같은 수동 시험을 다시 요구하지 않았다.

| 사용 사례 | 판정 | 범위 |
|---|---|---|
| 읽기 전용 파일 2개, permission_denied와 원본 보존 | USER_CONFIRMED | 해당 사용 사례 |
| 읽기 전용이 아닌 동일 내용 자동 정리 | USER_CONFIRMED | 해당 사용 사례 |
| 새 내용의 번호 파일 유입 때 이전 내용 History 보관 | USER_CONFIRMED | 해당 사용 사례 |

Explorer 복사 충돌 선택 창은 Windows 기본 UI다. 번호 파일이 생성된 뒤 DVM이 처리한다. 직접 덮어써 이미 사라진 이전 내용의 사후 보관은 이번 기능이 아니다. 사진의 2024-09-27 09:42에는 초가 없으므로 정확한 초나 전체 메타데이터 동일성을 추정하지 않았다.

## 구현 선택과 최소 변경

| 파일 | 이번 변경과 이유 |
|---|---|
| tools/DownloadVersionManager/source/engine.cpp | 실제 이동할 stale ? n.v : old->v 핸들에서 GetFileTime으로 mtime 조회. UTC와 동적 로컬 시간 변환을 이동/History 생성/order.prepare 전에 검증. 읽기 전용 확인 분기의 원인만 전달. |
| source/engine.h | 내부 readOnlyProtected bool 추가. 기존 Result 상태·오류 필드 유지, host JSON 필드 추가 없음. 시험용 시각/접근 오류 seam과 시간대 override는 DVM_TESTING만 컴파일. |
| source/watcher.cpp, source/watcher.h | 기존 formatter를 초기 그룹과 공유. ‘읽기 전용 보호: 파일 보존’ 또는 ‘접근 실패: 파일 보존’을 status·오류 번호·파일명 앞에 표시. 파일 정보 실패도 기존 file_info_failed/실제 오류를 표시. 기존 정상/잠금/cleanup/metadata/복구 안내 유지. |
| source/review.cpp | permission_denied/file_info_failed만 같은 짧은 안내를 사용. 나머지 그룹 처리 중단과 이전 파일 위치 안내 유지. |
| source/app.cpp | 기존 WS_HSCROLL 목록에 동일 글꼴로 측정한 문장 폭+8의 수평 범위를 설정. 긴 파일명·위치를 기존 스크롤로 읽을 수 있게 함. 새 팝업/설정 없음. |
| tests/watcher/engine.cpp | 기존 8개 유지 + 날짜/보존/원인 19개 추가. 새 임시 데이터만 사용. |
| tests/watcher/guidance.cpp, tests/watcher/log_smoke.cpp, tests/watcher/review_smoke.cpp | formatter 13개와 실제 app 로그 처리기 측정 1개, 최초 그룹의 원인 전달 1개 추가. 합성 Result/창/임시 파일만 사용. |
| build/build-watcher.py | 기존 --test-only에 guidance/log 연결. 일반 --tests에도 연결. MSI 제작·설치 코드는 변경하지 않았고 이번에는 early-return하는 test-only만 실행. |
| 사용자 안내 index.md, next-version-specification.md, README.md | 현재 공개 MSI의 기존 규칙과 미배포 소스 개선을 구분하고 기존 이름 유지·보존 이유·직접 덮어쓰기 한계를 일치시킴. |
| docs/design/0031-download-history-mtime-guidance.md, docs/design/index.md | 날짜 데이터 계약의 부분 변경을 문서 정책에 따라 ADR로 기록. 원 명세/이전 ADR의 과거 근거 유지. |
| 이 검증 기록 | 기존 설치 진단 작업과 분리한 실행/재사용/미실행 근거. |

GetFileTime은 기존 잠금 핸들에서 조회하며 경로를 다시 열지 않는다. 일반 폴더·최초 그룹은 직전 원래 객체 old->v, 기존 공용 완료 순서의 stale 처리는 실제 보관하는 n.v의 시각을 사용한다. FileTimeToSystemTime -> GetDynamicTimeZoneInformation -> SystemTimeToTzSpecificLocalTimeEx로 PC의 현재 선택 시간대에서 해당 날짜의 규칙을 적용한다. 고정 +09:00이나 현재 시간 대체는 없다. 과거 PC가 실제 사용한 시간대의 복원은 하지 않는다.

YYYYMMDD_HHMMSS 형식과 초 미만 절삭, 확장자, _001 이후 suffix, ReplaceIfExists=FALSE와 후보 10,000개 한도를 유지한다. 기존 History는 재명명하지 않으며 보관 객체의 시간은 이름에 맞춰 재설정하지 않는다. 기존 incoming 객체의 NTFS name-tunneling 대응 SetFileTime은 그대로다. 조회/변환 실패는 기존 file_info_failed와 Win32 오류로 끝나며 두 객체의 이름·위치를 유지한다.

원인 플래그는 실제 처리 핸들의 FILE_ATTRIBUTE_READONLY를 확인해 보호한 분기에서만 true다. 열기 자체에 실패해 속성을 확인하지 못한 경우에도 읽기 전용으로 단정하지 않는다. UI에서 나중에 속성을 다시 읽지 않는다. 권한·읽기 전용 해제 권유, 자동 재시도, 큐/감시 종료 정책 변경은 없다. host.cpp/JSON serializer와 확장 소비처는 수정하지 않았고 protocolVersion 2의 기존 12개 응답 필드를 유지했다.

## 이번 실행 환경과 명령

Windows 11 x64 23H2, build 22631.6199 / 일반 사용자 token(Elevated=false), 로컬 NTFS. 기존 MSVC x64와 Windows SDK 10.0.26100.0, C++17 /MT /W4 /WX /guard:cf. Python 3.12.14. 실제 명령은 Node child_process.execFile의 절대 실행 파일/인수와 windowsHide=true로 실행했다. 기본 exec_command의 프로세스 생성은 오류 5로 거부되어 이 경로를 사용했고 권한 상승/보안 변경은 하지 않았다.

이하 Python은 <local-python>이며 evidence는 실제 작업 경로의 artifacts/download-version-manager-watcher/mtime-guidance-20261005이다. 비공개 run-focused.py는 기존 build.py의 compiler/command helper와 같은 옵션으로 EXE만 만들고 테스트를 실행하며 MSI code를 호출하지 않는다.

| 실제 실행 인수 | 기대값 | 최종 결과 | evidence 아래 로그 |
|---|---|---|---|
| run-focused.py engine | 이전/유입/현재 시각이 다름에도 실제 보관 대상 mtime. 내용·객체·생성/수정 시각·속성 보존. 동일 mtime/같은 초/과거 이름/10,000개 충돌 보호. 일반/legacy/stale와 역사적 Pacific DST. 조회/변환 실패 및 접근 실패 보존. | 27 PASS / 0 FAIL | engine-tests.log, engine-fixtures/engine-results.json |
| run-focused.py watcher | 기존 감지·안정·잠금·동시 후보·범위·중지/재시작·실패 후보 처리 회귀 | 15 PASS / 0 FAIL | watcher-tests.log, watcher-fixtures/ |
| run-focused.py review | 동의 없이 닫기·보존·선택 최신 처리·preview 후 변경 보존·읽기 전용 원인 전달과 나머지 그룹 보존 | 5 PASS / 0 FAIL | review-tests.log, review-fixtures-*/ |
| build-watcher.py --test-only guidance --msvc <original-workspace>/.tools/image-copy-save-native/msvc --sdk <original-workspace>/.tools/image-copy-save-native/sdk --output-dir evidence/runner-guidance | 확인된 읽기 전용/일반 접근/긴 이름/오류/잠금/cleanup/metadata/rollback 문구 계약 | 13 PASS / 0 FAIL | runner-guidance/guidance-tests.log, guidance-fixtures-*/guidance-results.json |
| build-watcher.py --test-only log --msvc 위와 동일 --sdk 위와 동일 --output-dir evidence/runner-log | 실제 app 584px 로그 처리기의 문장 측정·전체 파일명 저장·수평 범위 | 1 PASS / 0 FAIL | runner-log/log-tests.log |
| host-json-check.py | ready와 확인된 읽기 전용 응답의 기존 JSON 12개 필드, 버전/protocol/status/error, 파일 보존 | 2 PASS / 0 FAIL | host-json-results.json |
| run-focused.py production | test hooks 없이 watcher와 기존 host compile, 패키징 없음 | 두 EXE 빌드 PASS | DownloadVersionManager-compile.log, DownloadVersionHost-compile.log |

합계는 **새 실행 63 PASS / 0 FAIL**이다. 기존 engine 8/watcher 15/review 4의 27개도 이번 변경의 영향을 받아 다시 실행했으며 위 63개 안에 포함한다. 사전 재사용한 과거 27개를 중복 합산하지 않는다. 같은 guidance/log를 로컬 driver와 표준 test-only로 재확인한 14개 역시 한 번만 센다.

초기 log 측정은 extent=0, 긴 문자열 2063px여서 FAIL했다. 문장 폭 설정 후 client=580px, 짧은 문장=510px, 이유+status+error=415px, 긴 문장=2063px, extent=2071px, scrollbar range=2070, 전체 문자열 보존=true로 PASS했다. 초기 guidance driver에는 필요한 --root가 빠져 usage exit 2가 났고 인수를 바로잡은 뒤 13 PASS를 얻었다. 두 초기 실행의 로그는 log-before-extent.log / guidance-initial-invocation.log에 보존했고 제품 시험 성공으로 세지 않았다. 최초 그룹의 원인 전달 시험을 추가한 첫 재실행은 private driver가 과거 fixture를 재사용해 exit 1이 났다. review-reused-fixture.log에 남기고 새 GUID fixture로 고쳐 최종 5 PASS를 확인했다. 제품 코드 실패나 추가 PASS로 중복 계산하지 않았다.

시험은 합성 폴더/파일만 사용했다. read-only 속성 시험은 해당 임시 파일만 설정·복원했으며 ACL/보안 정책은 변경하지 않았다. legacy 시험은 최초 부재를 확인한 자기 target hash의 CompletionOrder 값만 정리했고 다른 값·공유 key를 삭제하지 않았다. 내용·file ID·생성/마지막 수정 시각·속성의 확인은 PASS이며 모든 metadata/ACL/last-access의 완전한 동일성을 검증한 것은 아니다.

## 이전 근거 재사용과 남은 범위

| 구분 | 판정/근거 |
|---|---|
| 과거 engine 8 + watcher 15 + review 4 | 과거 27 PASS 근거는 기존 TEST_RESULTS/진단 manifest에서 확인. 이번 영향 영역은 위 새 실행에 다시 포함. 설치 복구 PASS 아님. |
| 설치 판정 회귀 | 기존 8 PASS 재사용. evidence-tests.private.log의 8 test/OK와 기존 manifest 확인, 이번 재실행 없음. 문법/diff/비승인 환경 차단/비동등 MSI 거절도 이전 근거이며 겹친 검사를 추가 test 수로 세지 않음. |
| 실제 로그 픽셀 가독성 | NOTRUN. 합성 Windows UI의 제어값/문장 폭은 시험했지만 pixel capture가 검은 화면이라 육안 근거 없음. 검은 PNG를 UI PASS로 쓰지 않음. |
| 모든 시간대/모든 OS·조직 정책·보안 descriptor | NOTRUN. 현재 PC 시간대와 명명된 Pacific 역사적 DST 자동 시험만 수행. |
| 현행 설치 실패/취소, 기존 설치 repair/upgrade 실패 복구, 실패 후 정상 재시도 | BLOCKED / NOTRUN. 승인된 격리 snapshot Windows 환경 미확보, 사용자에게 VM 없음. 실제 설치 복구 PASS 0. |
| 설치 실패 원인 | 초기 주입 MSI는 공개본과 payload/config DLL/custom action이 비동등. 초기 오류 5/1307·등록 잔류 근거와 원인 미확정 상태 유지. 이번에 다시 MSI를 대조하거나 설치한 결과 아님. |
| 문서 strict/생성 로컬 링크 | 최종 문서 검사 결과를 아래 완료 항목에 기록. |

## 생성물과 적용 상태

MSI·실패 주입 MSI·config DLL은 새로 만들지 않았다. 다음 파일은 로컬 검증용 EXE이며 정식 배포 파일이 아니다. 경로 기준은 evidence이며, SHA256SUMS.txt와 final-manifest.json에도 전체 경로/지문을 보관한다.

| evidence 상대 경로 | SHA-256 |
|---|---|
| DownloadVersionHost.exe | ad1b8bccea08b5b981d768a842b0ff5ee0b0a59b657bb257911666c58cc8f681 |
| DownloadVersionManager.exe | 7f45895083266a1125eb2e349c95fb404531abf4088e89cdaee70fc172c8a5fb |
| engine-tests.exe | f6f6febf569c9dfc6deb6b7e439b41280e65d2230b90f923a249540e3deb9f94 |
| guidance-tests.exe | 97437d722a112bd0be5f5cb32899ac623de4d6584c2e119d3ed7b492f11f554e |
| log-tests.exe | e6a8ea03f2f0f4f5d8a25f0f0f659049a4c11d092bfe5abbd9f67e5229e9b1e2 |
| review-tests.exe | 3f24c04e948b260ce922f868936b9bf0a0e5dfa7d2a96a97358bd9b15f8897ec |
| runner-guidance/DownloadVersionManager.Guidance.Tests.exe | dd93e6fd6fe35ec4555185bffa98c9f7406a00b614b2014e1d23a9f44c5b0265 |
| runner-log/DownloadVersionManager.Log.Tests.exe | e7da7b63a6b02ef6329a2afad0a79a5e22248c00a13de7efc01d32c4271e2297 |
| watcher-tests.exe | 79e98abdd167fd3997239c139b5377d45c654e9ae9b1a32d56135ffb86719d1d |

현재 설치본 미반영. 설치·제거·repair·upgrade·관리자 실행·보안 변경·현재 다운로드/History 수정 없음. commit/push/PR/merge/tag/release/deploy 없음. 로컬 EXE 빌드와 소스 수정이 공개 MSI 교체를 의미하지 않는다. 상용 승인이나 새 버전 공개로 분류하지 않는다.

사용자 결정이 필요한 구현 항목은 없다. 추후 육안 표시 검증은 화면 캡처 가능한 Windows 시험 조건, 설치 복구 재개는 공개/시험 MSI 동등성·승인된 격리 환경·복구 전후 증거가 필요하다. 이번 날짜/문구 결과를 설치 복구 성공으로 승격하지 않는다.

## 완료 검사

- PASS: python -m mkdocs build --strict --site-dir evidence/site. 지정한 생성 출력이 evidence 안에 있음을 먼저 확인했다.
- PASS: python scripts/check-site.py evidence/site. 공개 페이지 19개 + 기존 이동 페이지 2개 + 404, 공개 검색/사이트맵과 생성 로컬 링크/자산. 새 ADR/검증 기록/진단 원본은 공개 출력에서 제외됨. 게시하지 않았다.
- PASS: git diff --check. 기존 7개 바이트/설치 단락 보존과 installer/Watcher.wxs·설정 DLL·host.cpp 무변경 확인.
- 비공개 근거: baseline.json, preservation.json, final-manifest.json, final-changes.patch, SHA256SUMS.txt, docs-strict.log, site-links.log. 전체 working-tree diff와 이번 변경만의 patch를 구분하여 저장했다.

## 후속 사용자 확인 · 2026-10-05

앞의 63 PASS는 당시 최종 diff에 대한 자동 시험 결과로 그대로 보존한다. 실제 로그 픽셀 가독성의 NOTRUN도 당시 실행에서 육안 증거를 얻지 못했다는 기록이며 PASS로 바꾸지 않는다. 이후 사용자가 수정된 로컬 EXE를 직접 실행해 아래 세 항목을 확인했다.

| 수정된 EXE의 확인 항목 | 판정 | 근거와 범위 |
|---|---|---|
| 새 History 이름에 실제 보관 파일의 마지막 수정 시각 표시 | USER_CONFIRMED | 2026-10-05 사용자 직접 확인, 해당 실행 사례 |
| 읽기 전용 보호 때문에 파일을 보존한 이유가 읽히는 안내 | USER_CONFIRMED | 2026-10-05 사용자 직접 확인, 해당 안내 사례 |
| 긴 로그를 수평 스크롤하여 읽을 수 있음 | USER_CONFIRMED | 2026-10-05 사용자 직접 확인, 해당 화면 사례 |

이 후속 확인 3건은 자동 시험 수에 더하지 않으며 모든 파일명·DPI·OS·설치 경로의 PASS로 확대하지 않는다. 같은 수동 시험을 다시 요구하지 않는다. 설치 실패·취소·repair/upgrade 실패 복구와 정상 재시도는 승인된 격리 Windows 환경이 없어 계속 BLOCKED/NOTRUN이다. 현재 설치본 미반영과 설치 복구 PASS 0은 유지한다.

사용자는 이어 원래 처리 기능을 유지한 상용 품질 수준의 UX 개선과 로컬 MSI 제작을 요청했다. 이는 설치·제거·repair·upgrade 또는 공개 배포의 승인이 아니다. 후속 요구와 로컬 제작 결과는 [UX·로컬 MSI 기록](download-version-manager-ux-package-20261005.md)에서 별도로 구분한다.
