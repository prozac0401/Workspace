# DownloadVersionManager · 0.1.0 평가 후보 제작·검증

날짜: 2026-09-30 · 판정: **stable BLOCKED / 로컬 평가 후보** · 조직 도입 승인: 미결정

이 문서는 최초 protocol 1 평가 기록이다. 순서 결함 보완·protocol 2·추가 installer/resource·실제 Windows CI 결과와 새 MSI는 [후속 검증 기록](download-version-manager-followup-20260930.md)을 따른다. 아래 당시 결과를 현재 판정으로 확대하지 않는다.

사용자의 신규 제품 개발·조건부 릴리즈 지시에 따라 [최초 명세](../tools/download-version-manager/specification.md), [ADR-0026](../design/0026-download-version-manager.md)와 제품을 추가했습니다. 기존 사용자 작업을 보존하기 위해 원격 main `5fb9728`에서 관리 worktree와 `codex/download-version-manager` branch를 만들었습니다. 기존 도구 공통화·리팩터링은 하지 않았습니다.

## 산출물과 실제 검증

`tools/DownloadVersionManager/`는 MV3 확장, C++ x64 단발 Host, Host/extension/integration tests, 상위 build·MSI 검증·release gate, per-user WiX MSI 및 제품 안내를 포함합니다. Host/Extension/Installer 0.1.0, protocol 1이며 서명 없는 평가판입니다. Host는 OS Win32/CNG와 static CRT를 사용하고 별도 사용자 runtime·상주 watcher·service·tray·polling은 없습니다.

최종 로컬 설치 asset은 `artifacts/download-version-manager/0.1.0-evaluation/DownloadVersionManager-0.1.0-x64.msi` 하나이며 SHA256SUMS도 같은 폴더에 있습니다. 최종 MSI hash는 `d6794c076541f343c10b9bf8b05ef836b51ad26968d566cbccad3fc7ce307861`입니다. rollback MSI와 0.1.1은 개발 검증 fixture로 사용자 설치 자산에 포함하지 않습니다.

| 범위 | 결과 |
|---|---|
| 실제 Windows Host/protocol/concurrency | 61 PASS, 0 FAIL, 0 NOT RUN |
| Node MV3 controller/static | 29 PASS; 실제 browser contract는 NOT RUN |
| release gate / loopback fixture | 4 PASS / 3 PASS |
| MSI 구조·행정 추출·SHA-256 | PASS |
| 최종 native installer lifecycle·데이터 보존·정리 | 14개 기록 PASS |
| 제품 게시 후 late failure rollback의 앞선 시험 | FAIL: MSI 제품 등록 잔존·reinstall 1638; 공식 제거로 정리 |
| 실제 Chrome / 실제 Edge contract·E2E | NOT RUN / NOT RUN |
| 실제 browser Native Messaging·활성화·idle | NOT RUN |
| 완전 자동 단일 배포 / 엄격한 동시 완료 시각 순서 | FAIL / FAIL (설계 차이) |
| stable tag·GitHub Release·Pages 게시 | 미게시 |

Windows 11 x64 build 22631.6199, 고정 로컬 NTFS에서 합성 fixture를 사용했습니다. fresh/repair/missing-file repair/same-version/외부 수정 보호/0.1.1 upgrade/uninstall/트랜잭션 실패 rollback/reinstall/최종 제거를 실제 Windows Installer API로 확인했습니다. 다운로드·History·무관한 파일/등록 값은 보존했습니다. 전체 실패 지점·깨끗한 VM·GUI는 인증하지 않습니다. [제품 TEST_RESULTS](../../tools/DownloadVersionManager/TEST_RESULTS.md)가 세부 판정과 로컬 근거 파일의 위치를 제공합니다.

실측 Host 크기 203,776 bytes, 새 프로세스 startup 중앙값 25.180 ms. 10/100 MiB 두 파일 비교 시간 129.561/1,297.349 ms, peak working set 6,586,368/14,303,232 bytes입니다. 설치 중과 정리 후 native 0·startup 0·제품 service/task 0을 확인했습니다. 활성화된 확장을 포함한 실제 browser idle 검증과 reboot cold-disk startup은 NOT RUN입니다.

## 공개 범위·관문

일반 unmanaged Windows Chrome의 공식 외부 배포는 스토어와 사용자 승인이 필요하며 로컬 CRX 자동 활성화를 허용하지 않습니다. Edge Add-ons의 ID도 개발 ID와 다를 수 있습니다. MSI에 extension을 포함하는 사실만으로 통합 설치 PASS를 선언하지 않습니다. 공식 개발용 load fallback을 평가로 구현했고 보안 정책·profile을 우회하지 않았습니다. 현재 자동 승인 검토는 Edge 확장 관리 URL을 거절하며 Chrome 제어 surface도 없습니다. 실제 handshake를 대신할 경로를 사용하지 않았습니다.

공개용 [사용 안내](../tools/download-version-manager/index.md)만 MkDocs nav/허용 목록에 추가합니다. 명세·ADR·이 기록·installer 로그·절대 사용자 경로·verification 자료는 사이트에서 제외합니다. 공개 MSI나 release URL을 만들어 넣지 않았습니다. 로컬 strict/링크 검증 결과는 최종 Git 기록과 함께 아래에 남깁니다.

다음 인수 단계는 공식 평가 profile의 확장 활성화와 제공한 HTTP fixture의 양쪽 browser contract·대표 E2E입니다. Chrome Web Store/Edge Add-ons 배포 방식·계정, 동시 완료 순서, 추가 installer 실패 복구 범위를 해결한 뒤 `release-gate.py`의 전체 PASS를 확인해야 stable 게시가 가능합니다.

## 문서·Git 최종 확인

`python -m mkdocs build --strict` **PASS** (MkDocs 1.6.1). `python scripts/check-site.py` **PASS**: 공개 안내 19개 + 이전 주소 redirect 2개 + 404, 공개 검색·사이트맵 allowlist 일치, 비공개 원본·diagnostics 제외와 로컬 링크/asset 정상입니다. 생성 `site` 경로는 이 worktree 안의 의도한 출력 위치임을 확인했습니다. 로그는 제품 artifact 폴더의 `mkdocs-strict.log`·`site-links.log`에 있습니다. 10개 Python 파일의 AST syntax도 PASS입니다.

제품 구현·시험·MSI·CI commit은 `021da1f4922d82971f919bf7db4732a289c5b41f`입니다. 평가 보고·명세·ADR·공개 안내 연결은 후속 문서 commit으로 분리합니다. 원본 main의 미커밋·미추적 파일과 기존 artifact/tag/release를 유지합니다. stable gate가 차단되어 원격 push/tag/release는 진행하지 않습니다. 전체 최종 SHA는 branch log와 로컬 `final-verification.json`에서 확인합니다.
