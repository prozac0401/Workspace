# DownloadVersionManager · 실제 시험 기록

## Linux 후속 수정 · 2026-09-30

기준 소스는 main `c9a5b7084ebb6b7b612cc9301199641cdef2eda8`이다. 아래는 cloud Linux에서의 소스 수정·준비 검증이며 새 Windows MSI를 제작하거나 기존 Windows 인수 결과를 바꾸지 않았다.

- 확장 활성화가 자동 처리 시작점이고 ‘설치 연결 확인’은 진단뿐임을 확인했다. 팝업과 설치 마무리의 잘못된 시작 조건 안내를 바로잡았다. 진단 전후 모두 process 요청을 보내는 동작 회귀시험과 안내 회귀시험을 추가했다.
- late-failure harness에서 파일/Native 등록 보존 검증이 실패하면 FAIL 기록 전에 중단해 개별 state에 PASS만 남고 aggregate 결과가 없을 수 있음을 합성 lifecycle으로 재현했다. 중단한 trial과 실패 단계를 즉시 보존하고 예상 밖 실패 뒤에는 재설치·강제 정리 없이 멈추도록 증거 기록을 보완했다. 제품의 MSI rollback 동작을 고친 것은 아니다.
- Node 24.19.0 / Python 3.12.14에서 확장 **40 PASS**, late-failure 증거/중단 회귀시험 **10 PASS**, loopback fixture **3 PASS**, release gate **4 PASS**. 새 증거 회귀시험을 수정 전 harness에 적용하면 **2 PASS / 8 FAIL**로 누락을 재현했다. Windows Host·MSI·Chrome/Edge native integration은 이번 실행에서 **NOT RUN**이다.
- 문서 `mkdocs build --strict`와 `scripts/check-site.py`는 **PASS**다. 정적 팝업·설치 안내의 클라우드 브라우저 렌더링 시도는 loopback URL의 `ERR_BLOCKED_BY_CLIENT`로 **NOT RUN**이다. 소스/문구 검사를 실제 확장 UI·handshake 시험으로 간주하지 않는다.
- 상세 Win11 MSI 로그는 이 checkout에 없다. access denied(5)/재설치 1638 원인을 확정하거나 해결했다고 표시하지 않는다. 필요한 로컬 증거와 재실행 전 확인은 [integration 안내](tests/integration/README.md)를 따른다. 기존 `installerFailureRecovery` FAIL과 stable 차단은 유지한다.

로컬 로그는 `artifacts/download-version-manager/linux-followup-20260930/`에 보관한다. 소스 변경은 기존 MSI에 반영되지 않았으므로 다음 Windows 빌드·패키지 검증 뒤 후보를 다시 식별해야 한다.

## 후속 평가 · protocol 2 · 2026-09-30

최신 코드의 결과는 이 후속 기록을 기준으로 합니다. 아래 최초 protocol 1 기록과 이전 artifact는 당시 근거로 보존합니다. 새 출력은 `artifacts/download-version-manager/0.1.0-evaluation-followup-20260930/`이며 이전 MSI를 덮어쓰지 않았습니다.

| 시험 | 실제 결과 |
|---|---|
| Windows Host·protocol·ordering·NTFS | **82 PASS / 0 FAIL / 0 NOT RUN** |
| Node 확장·metadata 복원·완료 시각/token | **38 PASS / 0 FAIL**; 실제 browser contract와 구분 |
| release gate / loopback fixture | **4 PASS / 3 PASS** |
| size-first·same-content 최신 객체·변경 History·실제 잠금/ACL·rollback | **PASS** |
| B→A 역순·16 프로세스·브라우저 ID 충돌·중단 뒤 file ID 선택 | **PASS**: 더 늦은 완료 객체 유지 |
| 같은 완료 시각 / 손상·누락 상태 | **PASS**: 선후를 추측하지 않고 데이터 보존 |
| MSI 구조·추출·checksum | **PASS**; lifecycle과 별도 |
| 최신 MSI native lifecycle·순서 상태/다운로드/History 보존·최종 정리 | **15 PASS / 0 FAIL** |
| late installer failure 2개 지점 | **10 PASS / 4 FAIL / 0 NOT RUN**, 시험 등록 정리 완료 |
| Windows CI (windows-2025, source b4265f4) | **전체 job PASS**: Host 82, 확장 38, native lifecycle 15, late failure 10 PASS / 0 FAIL |
| 실제 Chrome·Edge·Native handshake·활성화 후 idle | **NOT RUN** |
| 완전 자동 단일 배포 / 설치 실패 복구 | **FAIL / FAIL**; stable 게시 차단 |

production Host에서 원래 결함을 재현한 뒤 [ADR-0027](../../docs/design/0027-download-completion-order.md)에 따라 완료 시각과 실제 객체의 최소 상태를 구현했습니다. 늦게 전달된 이전 객체는 다르면 History, 같으면 제거하며 최신 객체는 유지합니다. 같은 millisecond·시계 역행은 제한입니다. 강제 종료·rollback·unrelated registry 보존을 시험했고 합성 fixture의 순서 값만 정리했습니다. 실제 브라우저에서 API 시간·filename semantics를 확인한 것은 아닙니다.

제품 게시 후 deferred 실패와 InstallExecute 후 immediate 실패 모두 파일/NMI 등록은 되돌아갔지만 MSI 제품 등록은 남았고 재설치는 **1638 FAIL**이었습니다. 로그 registry rollback에 access denied(5)가 있습니다. 공식 `MsiConfigureProductExW` 제거, 이어지는 설치·제거는 exit 0이며 업무/History fixture를 보존했습니다. `installer-late-fault-results.json`과 두 state/log를 로컬에 남겼습니다. 현재 PC 결과이며 깨끗한 Windows/CI 결과로 확대하지 않습니다.

Host 크기 **209,920 bytes (205 KiB)**, 새 프로세스 ping 10회 wall 중앙값 **21.323 ms**, lifetime **17.638–21.918 ms**. 10 MiB 두 파일 hash/compare **137.535 ms**, lifetime **185.825 ms**, peak **6,848,512 bytes**. 100 MiB 두 파일 hash/compare **1,317.722 ms**, lifetime **1,374.822 ms**, peak **14,311,424 bytes**. 추가 1 GiB 두 파일 비교(총 2 GiB 읽기)는 **13,920.919 ms**, lifetime **14,414.323 ms**, peak **14,225,408 bytes**입니다. 모든 측정 Host가 종료됐고 처리 전후 native process는 **0**입니다. OS cache를 비우지 않았으며 reboot cold-disk 측정이 아닙니다. 확장 활성화 상태의 browser idle은 NOT RUN입니다.

최종 local MSI SHA-256은 `a9a93660699aea5b673cb4b223ac64c69b48a447c0b9144851d9e5bab85e5e25`입니다. 실제 [CI run](https://github.com/prozac0401/Workspace/actions/runs/36696781550)과 내려받은 artifact에서 MSI checksum 일치를 확인했습니다. CI MSI hash는 local MSI와 다릅니다. compiler·environment·artifact 및 문서 strict/링크 근거는 [후속 delivery 기록](../../docs/delivery/download-version-manager-followup-20260930.md)에 있습니다. CI의 Windows Server PASS로 local Windows 11의 late 실패를 해결했다고 판단하지 않으며 installerFailureRecovery는 FAIL입니다. 완료한 자동시험을 브라우저 실기 PASS로 확대하지 않습니다.

## 최초 평가 기록 · protocol 1 (후속 결과는 위 표)

날짜: 2026-09-30 · 제품 0.1.0 평가판 · **stable gate BLOCKED**

**결론:** 핵심 자동시험과 native MSI 수명주기는 통과했습니다. 실제 Chrome·Edge 계약/E2E·브라우저 Native Messaging·확장 활성화는 NOT RUN입니다. 완전 자동 단일 설치와 동시 완료 시각 순서는 미충족이며 stable 태그·Release를 게시하지 않았습니다. MSI 생성·직접 Host ping을 브라우저 handshake PASS로 바꾸지 않습니다.

## 환경·식별

- Windows 11 x64, build 22631.6199, 로컬 NTFS. 일반 사용자 per-user 설치, HKCU. 격리 VM 대신 기존 관련 제품/Host 등록 부재를 확인한 뒤 저장소 `artifacts`의 고유 시험 설치 폴더를 사용했습니다. 기존 사용자 profile·업무 파일은 시험하지 않았습니다.
- MSVC compiler 19.41.34123 / linker 14.41.34123, Windows SDK 10.0.26100.0, static CRT C++17/CNG, WiX 4.0.6, Python 3.12.14, Node 24.13.1. 개발용 도구만 필요하며 사용자 runtime은 추가하지 않습니다.
- 최종 MSI: `DownloadVersionManager-0.1.0-x64.msi`, SHA-256 `d6794c076541f343c10b9bf8b05ef836b51ad26968d566cbccad3fc7ce307861`.
- production Host SHA-256: `2c3797c6240a4fe870ee01cc4f7e58ef3602390627fb06be58a547f67fe3abe1`. Host·Extension·MSI 0.1.0, protocol 1. 개발용 확장 ID `knahdnpoplcleaoklikjmgpocealjogc`; Store ID는 미결정입니다.
- 근거 파일은 `artifacts/download-version-manager/0.1.0-evaluation/`의 `host-results.json`, `extension-tests.log`, `resource-results.json`, `package-verification.json`, `installer-transaction-results.json`, `installed-presence.json`, `cleaned-presence.json`, `release-gate-tests.log`, `fixture-tests.log`입니다. 로컬 installer 상세 로그·절대 경로는 공개 사이트에 포함하지 않습니다.

## 자동 검증

| 범위 | 실제 결과 | 근거·판정 한계 |
|---|---|---|
| Host·protocol·동시 프로세스 | **61 PASS / 0 FAIL / 0 NOT RUN** | 실제 Windows 실행. production/test Host 분리 |
| MV3 controller·정적 검증 | **29 PASS / 0 FAIL** | 공식 계약을 모델링한 Node mock. 실제 브라우저 contract는 NOT RUN |
| 릴리즈 관문 검증 | **4 PASS** | 각 누락 gate·FAIL·NOT RUN·평가 channel이 stable을 차단 |
| 로컬 HTTP fixture | **3 PASS** | 동일 A 바이트 재현, B 차이, 한글·원래 `(1)`/`(2)` header, 잘못된 fixture 거절. 브라우저 E2E 아님 |
| MSI 구조·행정 추출·파일 hash | **PASS** | 13개 payload, HKCU 18개 행, 양쪽 native 등록 2개, service/startup 0. test Host·wildcard 사용자 데이터 제거 없음 |
| SHA256SUMS | **PASS** | 최종 MSI 실측 hash와 일치 |

Host 시험은 target 부재/존재, 한글·Unicode·공백·여러 점·무확장·`.hidden`·260자 초과 경로, History 이름 길이 한계와 보존, 크기 다름의 hash 읽기 0, 같은 크기의 같음/다름·empty·64 MiB streaming을 포함합니다. 같은 내용에서 **신규 file ID와 creation/write time 유지** 및 History 미생성, 다른 내용의 확장자·timestamp·같은 초 `_001` 충돌·기존 History 사용자 파일 보존을 확인했습니다.

실제 Windows 파일 잠금과 History ACL 거절에서 두 파일 보존을 확인했습니다. rename/rollback/cleanup 실패 주입은 별도 test Host에서 수행했고 production은 주입 필드를 거절합니다. 강제 프로세스 중단 뒤 두 객체의 보존 위치를 검사했습니다. 같은 target 2/8/16개 프로세스와 서로 다른 target 병렬, Chrome/Edge 역할 동시 요청을 시험했습니다. 이는 브라우저 실기·정전 durability·전체 완료 시각 정렬 검증이 아닙니다.

Extension 시험은 첫/중복/완료·중단/취소/실패·동시 완료, 원래 `(1)`·`(2)` 이름, controller 재생성으로 worker suspend/resume 모델링, stale 정리, Host 미설치/error·protocol/version mismatch, 알 수 없는 처리 재실행 방지와 success 무알림을 확인했습니다. suffix를 역추론해 원래 이름을 만드는 코드는 없습니다.

## 후속 시험 · 확장 없이 요청 순서 역전 재현

2026-09-30 후속 질문에 따라 production Host와 고유 합성 폴더로 한 사례를 추가 확인했습니다. 기존 61개 시험을 반복하지 않았습니다. A가 먼저 완료되고 B가 나중에 완료된 상황을 모델링하되 Native 요청은 B → A 순으로 전달했습니다. 최종 target은 예상한 B가 아닌 A여서 **최신 완료본 순서 FAIL을 실제 재현**했습니다. 초기본·A·B의 세 내용은 모두 남아 **데이터 보존 PASS**입니다.

실제 browser E2E가 아닌 native 요청 시뮬레이션입니다. 실행한 소스 기준은 `a4a9c5b1a27bbe3e2e632d331f809970862e642b`, Host는 기존 검증 production binary입니다. 근거는 `artifacts/download-version-manager/0.1.0-evaluation/followup-order-c0034e8022ff47528f83400aa0d220c7/result.json`에 보존합니다. 기존 자동시험 PASS와 이 추가 인수 FAIL을 합쳐 전체 성공으로 표시하지 않습니다. 확장 활성화와 무관하게 수정·회귀시험을 진행할 수 있는 항목입니다.

## 실제 installer lifecycle

최종 MSI의 fresh install → 동일 버전 repair → 소유 파일 하나 누락 repair → 동일 버전 재실행 → 외부 수정 파일/Native Host default 보호 → 0.1.1 시험 upgrade → uninstall → 트랜잭션 실패 주입 → 0.1.0 reinstall → 시험 설치 제거를 수행했습니다. **14개 기록 PASS**, 정상 설치 작업 exit 0, 보호 거절·고의 실패 exit 1603(예상값)입니다. 시험용 0.1.1은 사용자 릴리즈가 아닙니다.

- 각 설치/repair/upgrade의 설치된 exe 직접 framed ping과 extension manifest 버전 일치를 확인했습니다. 실제 브라우저 경유 handshake는 NOT RUN입니다.
- 제거 후 양쪽 Native Host default와 제품 소유 설치 파일이 사라지고 무관한 registry named value가 보존됐습니다. 다운로드·History·무관한 파일의 fixture hash는 그대로입니다.
- 파일/레지스트리 쓰기 다음 deferred 실패 주입에서 payload·native default·MSI 관련 제품 등록이 모두 롤백됐습니다. fresh reinstall이 통과했습니다.
- 설치 중 및 최종 정리 후 실제 snapshot: 제품 native process 0, Run/RunOnce 항목 0, 서비스 이름 매치 0, scheduled task 이름 매치 0. MSI 구조/guard에 추가 실행·서비스/작업 생성·browser 종료 기능이 없습니다. 정상 결과에 3010/1641 재시작 요구는 없었습니다. 기존 OS 자체 reboot-pending 상태는 이 제품의 요청으로 해석하지 않습니다.
- 시험 후 공식 Windows Installer 제거로 관련 제품 등록·native default를 정리하고 사용자 역할 fixture를 보존했습니다. 깨끗한 VM·GUI 설치 접근성·일반 사용자 실제 browser restart/discovery는 NOT RUN입니다.

**앞선 FAIL도 보존:** 초기 MSI 행정 추출이 아닌 실제 실기의 제품 게시 후 immediate 실패 주입에서는 파일·native default가 제거됐지만 MSI 제품 등록이 남았습니다. Windows Installer 로그에 rollback registry 1401/1403/1404 오류가 있었고 다음 reinstall은 **1638 FAIL**이었습니다. 공식 `MsiConfigureProductExW` 제거는 exit 0으로 해당 시험 등록을 정리했습니다. 이를 성공으로 덮어쓰지 않습니다. 최종 트랜잭션 fixture는 제품 게시 전 파일/등록 쓰기를 되돌리는 범위이며 모든 실패 지점의 복구를 인증하지 않습니다. 앞선 결과는 `installer-final-results.json`·`installer-first-lifecycle-msi.msi`와 상세 로그에 보존됩니다.

초기 `msiexec` CLI 시도는 완료되지 않아 NOT RUN이며 공식 Windows Installer API 실기로 구분했습니다. 개발 초기에 stdout encoding과 dot-leading ancestor 검증 오류를 고친 뒤 최종 61개 Host 시험을 통과했습니다. 수정 전 결과를 최종 패키지 PASS에 합산하지 않습니다. Native/extension 소스가 바뀌지 않은 installer 변경은 hash를 확인한 `--package-only`로 재제작했고 관련 lifecycle을 검증했습니다.

## Resource usage

| 측정 | 실제 값 |
|---|---|
| exe 크기 | 203,776 bytes (199 KiB) |
| 새 프로세스 ping startup 10회 | wall 중앙값 25.180 ms, 첫 회 29.740 ms |
| ping process lifetime | 20.567–26.184 ms |
| ping peak working set | 6,283,264–6,307,840 bytes (약 6 MiB) |
| 10 MiB 파일 2개 동일성 비교 | hash/compare 129.561 ms, lifetime 178.695 ms, wall 182.229 ms, peak 6,586,368 bytes |
| 100 MiB 파일 2개 동일성 비교 | hash/compare 1,297.349 ms, lifetime 1,353.104 ms, wall 1,357.693 ms, peak 14,303,232 bytes |
| 처리 전후 native process | 0, 모든 측정 프로세스 종료 |
| 선택적 1 GiB / reboot cold-disk startup | NOT RUN |

10/100 MiB는 각각 두 파일의 총 20/200 MiB를 읽은 비교 시간입니다. OS cache를 비우지 않았습니다. 새 프로세스 측정을 재부팅 후 cold-disk 수치로 주장하지 않습니다. 64 KiB 스트리밍, 파일 전체 memory-map/array 없음. 브라우저 확장이 활성화된 환경에서의 idle 관문은 별도로 NOT RUN입니다.

## 실제 Chrome·Edge와 stable gate

| 관문 | 결과 | 정확한 blocker |
|---|---|---|
| Chrome API contract·대표 E2E 4 case | **NOT RUN** | Chrome 제어 surface 없음, 확장 활성화 불가 |
| Edge API contract·대표 E2E 4 case | **NOT RUN** | 자동 승인 검토가 `edge://extensions` 접근 거절: browser 제어는 HTTP/HTTPS만 허용 |
| 실제 Native Messaging handshake·worker suspend | **NOT RUN** | 활성화된 시험 확장 없음 |
| 활성화된 browser + idle native 0 | **NOT RUN** | native 독립 snapshot 0을 이 관문 PASS로 확대하지 않음 |
| 완전 자동 single distribution | **FAIL** | Chrome/Edge Store 미게시, MSI 후 공식 개발용 load/활성화 사용자 작업 필요 |
| 동시 요청의 엄격한 최신 완료 시각 순서 | **FAIL (설계 차이)** | target mutex 처리 순서. 브라우저 전체 endTime high-water 계약 없음 |
| known limitations | **PASS** | README·KNOWN_LIMITATIONS·ADR·guide에 구분 |
| stable gate | **BLOCKED** | 누락/미실행/미충족이 있으므로 stable tag·Release 없음 |

스토어/조직 정책·코드 서명·Windows 10·ARM64·네트워크/클라우드 경로·사용자 Save As 직접 덮어쓰기·모든 다운로드 방식은 검증되지 않았습니다. PowerShell wrapper는 이 환경에서 실행이 거절되어 NOT RUN이며 동일 Python 상위 제작 경로를 실제 실행했습니다. GitHub Actions 원격 실행과 공개 Release/Pages HTTP 검증은 게시하지 않아 NOT RUN입니다. 문서 strict/로컬 링크 결과는 [배포 기록](../../docs/delivery/download-version-manager-evaluation-20260930.md)을 따릅니다.

다음 인수 단계는 공식 평가 profile에서 MSI의 확장을 활성화하고 제공한 loopback fixture로 **Chrome·Edge 계약 + first/same/changed/locked + 실제 handshake**를 기록하는 것입니다. 이후 동시 완료 순서·스토어 단일 배포·추가 installer 실패 지점을 해결하고 모든 stable gate를 다시 판정합니다.
