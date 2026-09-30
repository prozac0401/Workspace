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
