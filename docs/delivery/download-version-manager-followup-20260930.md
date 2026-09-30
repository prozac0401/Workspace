# DownloadVersionManager · 순서 결함 보완과 추가 검증

날짜: 2026-09-30 · 제품 0.1.0 / protocol 2 · 판정: **stable BLOCKED / 평가 후보**

사용자가 직접 PC를 조작하는 부분을 남기고 독립 작업을 먼저 진행하라고 요청했다. [최초 평가](download-version-manager-evaluation-20260930.md)의 순서 역전 결함을 수정하고, 추가 Host/extension 시험·실제 native installer·자원 측정·Windows CI를 수행했다. 기존 업무 파일과 원래 main의 미커밋 변경을 유지했다. 설계 변경은 [ADR-0027](../design/0027-download-completion-order.md), 전체 시험은 [TEST_RESULTS](../../tools/DownloadVersionManager/TEST_RESULTS.md)와 로컬 artifact에 연결한다.

## 완료한 구현과 검증

확장은 공식 download `endTime`과 filename 결정 때 저장한 random token을 전달한다. Host는 target mutex 안에서 완료 시각과 실제 file ID의 최소 상태로 최신 객체를 유지한다. 역순 요청의 이전 객체는 다를 때만 History로 이동하며 같으면 제거한다. 같은 완료 시각은 선후를 추측하지 않고 두 파일을 보존한다. Native Messaging protocol은 2이고 제품 버전은 Host/확장/MSI 모두 0.1.0이다. 상주 프로세스·watcher·service·tray·polling·keepalive는 추가하지 않았다.

| 범위 | Windows 11 로컬 | Windows CI |
|---|---|---|
| Host/protocol/NTFS/ordering | 82 PASS, 0 FAIL | 82 PASS, 0 FAIL |
| 확장 controller/static | 38 PASS, 0 FAIL | 38 PASS, 0 FAIL |
| gate / loopback fixture | 4 PASS / 3 PASS | PASS |
| 정상 native MSI lifecycle·순서 상태·사용자 fixture 보존·정리 | 15 PASS | 15 PASS |
| 게시 후 deferred / InstallExecute 후 immediate 실패 | 10 PASS / 4 FAIL | 10 PASS / 0 FAIL |
| package construction·추출·SHA-256 | PASS | PASS; artifact 다운로드 후 실제 checksum 일치 |
| 실제 Chrome·Edge·Native handshake·활성화 후 idle | NOT RUN | NOT RUN |

로컬 late 실패에서는 파일과 NMI 등록은 복구됐지만 MSI 제품 등록이 남아 재설치가 1638로 실패했다. rollback registry access denied(5)를 확인했고 공식 MSI 제거로 자기 시험 등록을 정리한 뒤 설치·제거는 성공했다. CI는 이 두 지점에서 제품 등록까지 복구했다. **Windows Server runner PASS가 Windows 11의 관찰된 FAIL을 해결한 것은 아니다.** OS/사용자 권한의 정확한 원인은 미확정이고 깨끗한 Windows 11 표준 사용자 비교가 남는다. OS ACL·Installer 내부 registry를 직접 수정하지 않았다.

## 산출물과 지문

로컬 사용자 설치 후보는 `artifacts/download-version-manager/0.1.0-evaluation-followup-20260930/DownloadVersionManager-0.1.0-x64.msi` 하나다. 같은 폴더의 SHA256SUMS와 실제 MSI를 비교했다. 이전 평가 artifact를 덮어쓰거나 삭제하지 않았다. 시험용 0.1.1과 rollback MSI는 사용자 설치 자산이 아니다.

- 로컬 MSI SHA-256: `a9a93660699aea5b673cb4b223ac64c69b48a447c0b9144851d9e5bab85e5e25`.
- 로컬 production Host SHA-256: `13a2b18c90b16a83381ad7313a81d7c523dc03b1faf5131558ce0c29310a2713`.
- CI MSI SHA-256: `24161b41f93ea6d04d0bb8f399853c9784c2416defbc54a5ab59f6b86a265fb4`.
- CI verification ZIP SHA-256: `97fc96ac3a627a9467884b0603b80884e05f7085da705ffccee54800aa8b64ed`.

로컬/CI toolchain과 PE/MSI 제작 시각이 다르므로 두 MSI의 checksum을 혼용하지 않는다. 서명 없는 per-user 평가 설치이며 Native Host는 static CRT/Windows APIs 외의 사용자 runtime을 요구하지 않는다. source/runtime/test 파일 변경은 `b4265f4b08933be6b33609f25c45b9ca42452fee`에서 검증했다.

[Windows CI run 36696781550](https://github.com/prozac0401/Workspace/actions/runs/36696781550)은 해당 source commit에서 전체 job success로 완료했다. `windows-2025`, Windows build 26100, MSVC 14.51.36231, SDK 10.0.26100.0이다. Windows 11 로컬은 build 22631.6199, MSVC compiler 19.41.34123이다. CI artifact를 내려받아 ZIP digest와 MSI checksum, 실제 lifecycle/late-failure JSON을 확인했다. 원격 CI와 공개 stable Release는 다른 결과다.

## 자원과 정리

로컬 Host 209,920 bytes (205 KiB), 새 프로세스 startup 중앙값 21.323 ms. 10/100 MiB 두 객체 hash/compare 137.535/1,317.722 ms. 선택적 1 GiB 두 객체는 총 2 GiB를 읽어 13,920.919 ms, peak working set 14,225,408 bytes, lifetime 14,414.323 ms였다. 모든 측정 Host가 종료됐고 native idle 0이다. OS cache를 비우거나 재부팅 cold-disk를 측정하지 않았다.

최종 MSI의 설치 중·정리 후 실제 native process/startup/service/scheduled-task 제품 항목은 모두 0이었다. 시험 설치·late 실패 등록은 공식 제거로 정리했고 NMI defaults도 없다. 업무/History/unrelated file·registry fixture는 보존했으며 순서 시험의 자기 synthetic registry 값만 정리했다. 실제 확장 활성화 상태의 browser idle은 별도 NOT RUN이다.

## 남긴 사용자 조작과 관문

[실기 절차](../../tools/DownloadVersionManager/tests/integration/README.md)에 따라 평가 MSI 설치, Chrome/Edge 별도 profile, 공식 개발용 확장 활성화와 설치 연결 확인이 필요하다. 이어서 합성 HTTP endpoint의 first/same/changed/locked, 원래 `(1)`/`(2)` 이름, metadata 복원, 실제 Native Messaging과 처리 후 idle을 확인한다. 파일·잠금·snapshot·자원 검사는 명시적인 fixture 범위에서 이어서 수행할 수 있다. profile/보안 정책을 코드로 우회하지 않는다.

singleDistribution FAIL, 실제 양쪽 browser 계약/E2E/handshake/idle NOT RUN, Windows 11 installerFailureRecovery FAIL로 stable gate가 차단된다. 완전 자동 확장 배포의 Store/정책·서명 주체와 깨끗한 Windows 11 환경도 미결정이다. stable tag/Release·Pages 게시를 진행하지 않았다.

## 문서와 Git

MkDocs strict와 로컬 link/asset 검사 PASS: 공개 안내 19개 + redirect 2개 + 404, 공개 검색·사이트맵 일치, 비공개 진단 제외. Python 12개 AST syntax PASS. 문서 source는 Markdown이며 raw installer 로그·user path·verification ZIP는 공개 사이트에 넣지 않았다.

`codex/download-version-manager`의 구현 commit `b4265f4`를 push해 CI를 실행했다. 후속 변경은 결과 기록만 추가하며 native/extension/installer 소스는 바꾸지 않는다. 문서만 기록하는 commit은 이미 PASS한 실행을 이유 없이 반복하지 않도록 CI를 생략하고, 검증 대상 source SHA를 위에 명시한다. 원래 `D:\Github_REPOS\Workspace`의 main/사용자 변경과 기존 tag/Release를 유지한다.

## 인계 후 Windows 11 조사와 최신 CI 후보 확인

2026-09-30 후속 인계 요청으로 [main 38640f518de0c25b52798e3d9ddd03b23d83f689](https://github.com/prozac0401/Workspace/commit/38640f518de0c25b52798e3d9ddd03b23d83f689)를 fetch·확인했다. 원래 main HEAD `89219d0f11c582fdb3649cb80527ee9c73defdd8`와 사용자 변경을 보존하고 별도 작업 트리에서 진행했다. 승인된 9개 파일 패치를 다시 적용하지 않았다. 2026-10-01 사용자가 commit·push를 요청해 이번 기록·안내 변경을 별도 브랜치와 PR로 원격 검토할 수 있게 반영한다. Release·Pages 게시는 이번 범위에 포함하지 않는다.

### 최신 CI 후보와 승인한 설치

[CI run 36724339153](https://github.com/prozac0401/Workspace/actions/runs/36724339153)의 Windows job은 completed/success다. artifact 11102247940을 새 `artifacts/download-version-manager/windows-continuation-20260930/` 폴더에 내려받아 ZIP digest, MSI checksum, build manifest와 기준 소스 일치를 확인했다. CI 증거는 Host 82, 확장 40, native lifecycle 15, late-failure 10 PASS / 0 FAIL이며 Windows Server 2025 범위다. 전수 자동시험을 현재 PC에서 반복하지 않았다.

- ZIP SHA-256: `3e8516965610c7f641f4a51064f1ef4ef468dc3d2dcd4e26ac9772eed0a08d10`.
- 0.1.0 / protocol 2 MSI SHA-256: `4e4d26dc64e2fea0e6b323af036f7c195d4f1dd3e7178907209537e8d32bb7d8`.
- MSI 위치: `ci-36724339153/0.1.0-evaluation/DownloadVersionManager-0.1.0-x64.msi` (위 새 artifact 폴더 기준).

읽기 전용 preflight 후 사용자가 이 후보의 전용 시험 설치, Chrome/Edge HKCU Native Host 등록, 공식 MSI 제거를 승인했다. Windows 11 현재 PC에서 install/uninstall exit 0, 설치된 payload 13개 hash 일치, 직접 Host 0.1.0 / protocol 2 응답과 합성 파일 보존을 확인했다. **5 PASS / 0 FAIL / 0 NOT RUN**이며 관련 제품·등록·소유 파일은 최종 제거했다. 설치 중/제거 후 native process·startup·service·scheduled task 제품 이름 매치는 모두 0이다. 브라우저 확장 활성화·늦은 실패 주입 재시험은 이번 승인 범위에서 제외했다.

현재 진단은 build 22631.6199, token 비상승·integrity RID 8192, restricted/AppContainer false다. 현재 사용자의 비상승 실행 결과이며 깨끗한 Windows 11 표준 사용자 계정이나 과거 실패 MSI의 token을 검증한 결과는 아니다.

### 과거 실패 증거와 식별 불일치

이전 작업 트리에서 aggregate와 두 state, 실패·재설치 `.log`/exit JSON을 찾았다. 두 로그 모두 Installer-managed product/SourceList/UpgradeCodes registry rollback의 system error 5와 rollback error skip을 기록하며 재설치 exit JSON은 1638이다. 두 state는 공식 제거와 최종 cleanup 완료를 기록한다. 합성 다운로드·History·무관한 파일 6개의 현재 hash는 preserve 목록과 일치한다. **기존 10 PASS / 4 FAIL과 installerFailureRecovery FAIL을 유지**한다.

| 과거 trial | state가 기록한 실패 MSI SHA-256 | 현재 같은 경로 MSI SHA-256 |
|---|---|---|
| post-publication-deferred | `65ac4d029faa73e92c3e92d376882fcfb8b634c9b42a1d839024afda798a6ffc` | `87bbeaf1fae0f5815afc7dfb12a616c978e4eb20ef058cdbb7b79684b9812ec3` |
| post-InstallExecute-immediate | `1527c9c0ace7ccea90efe01117c92ea1cb63df37d8abb02e5da536eeade82690` | `40c84a66c06531e093ce8d23e915013871e672509ddc055bbd154f9daa3b794f` |

이전 artifact 아래 MSI 14개에서 기록한 원본 hash와 일치하는 파일을 찾지 못했다. 현재 경로 파일은 원본 실패 패키지로 재사용하지 않는다. 로그/state는 당시 FAIL 근거로 보존하지만 원본 MSI와 당시 token/security descriptor 부재로 정확한 원인·제품 수정 방향은 미확정이다. MSI 로그의 WindowsBuild 속성을 실제 Windows patch build로 해석하지 않았다. 오류 해석은 [Installer registry 오류 메시지](https://learn.microsoft.com/en-us/windows/win32/msi/windows-installer-error-messages)와 [MSI 실행 오류 코드](https://learn.microsoft.com/en-us/windows/win32/msi/error-codes)를 참조하며, 오류 코드만으로 환경·권한의 원인을 확정하지 않는다.

비공개 사본은 새 artifact 폴더의 `prior-evidence/`, `prior-win11-evidence.json`, `investigation-summary.json`, `previous-msi-inventory.json`이다. 현재 경로 MSI 사본은 원본과 구분해서 이름을 붙였다. 새 CI 증거는 `ci-artifact-verification.json`, 현재 PC의 설치·제거는 `browser-evaluation/installation-state.json`, `installed-presence.json`, `removed-presence.json`, `after-removal-preflight.json`으로 확인한다. 원본 로그와 로컬 사용자 경로는 저장소 문서·공개 사이트에 넣지 않는다.

### 남은 관문

실제 Chrome/Edge protocol 2 handshake, first/same/changed/locked와 신규 객체 ID·시간/History, 원래 `(1)/(2)` 이름, worker 종료 후 metadata 복원, 활성화한 browser의 idle 0은 **NOT RUN**이다. 현재 제어 surface는 기존 Edge profile뿐이며 Chrome/평가 profile과 native UI 제어가 없다. 업무 profile을 시험하지 않았다. 별도 평가 profile 준비와 공식 확장 활성화·연결 확인은 사용자 조작과 해당 범위 승인 후 진행한다.

깨끗한 Windows 11 표준 사용자 비교도 환경·실행 승인과 실패 MSI 원본 식별이 준비될 때까지 NOT RUN이다. 이번 정상 설치·제거 PASS는 과거 늦은 실패 복구 PASS를 대신하지 않는다. singleDistribution FAIL, installerFailureRecovery FAIL, stable BLOCKED를 유지하고 새 기능 수정·서명·스토어·릴리즈를 진행하지 않았다.

이번 기록 추가 후 `python -m mkdocs build --strict`와 `scripts/check-site.py`는 PASS다. 공개 페이지 19개 + redirect 2개 + 404, search/sitemap의 공개 범위와 로컬 링크·자산을 확인했고 진단 자료는 제외됐다. 최신 MSI·checksum과 위 FAIL/NOT RUN을 넣은 release gate는 예상 exit 1, `stableAllowed: false`로 차단했다. 실행 결과는 새 artifact 폴더의 `mkdocs-strict.log`, `site-links.log`, `current-release-gates.json`, `current-release-gate-result.json`에 보존한다.
