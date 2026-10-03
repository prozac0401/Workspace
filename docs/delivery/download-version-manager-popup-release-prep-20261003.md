# DownloadVersionManager · 팝업 개선의 출시 준비

날짜: 2026-10-03 KST · 제품 0.1.0 / protocol 2 · 상태: **소스·문서 검토 준비 / 공개 평가 MSI·stable 출하 보류**

사용자의 순차 출시 준비 요청에 따라 이미 main에 반영된 팝업 중복 클릭 개선의 근거와 남은 관문을 정리했다. 이 기록은 새 제품 버전, 설치 후보 제작 또는 출시 승인이 아니다.

## 소스와 변경 범위

- 기준 소스는 [main e41999684c6a21070e5d6fc96ebed593b0529b1d](https://github.com/prozac0401/Workspace/commit/e41999684c6a21070e5d6fc96ebed593b0529b1d)다. 좁은 개선은 [82a690f624e83470129c8832688ec74356062745](https://github.com/prozac0401/Workspace/commit/82a690f624e83470129c8832688ec74356062745)에 이미 반영됐다.
- 연결 진단 응답 대기 중 같은 팝업의 버튼을 잠그고 성공·실패·예외 뒤 다시 활성화한다. 팝업을 열기만 해서는 연결 요청을 보내지 않는다.
- 진단은 `handshake`를 통해 Host의 `ping`을 호출한다. 확장 활성화, 다운로드 처리, 파일 이동·History·완료 순서·설치 복구 계약은 바꾸지 않는다.
- [최초 명세](../tools/download-version-manager/specification.md), [ADR-0026](../design/0026-download-version-manager.md), [ADR-0027](../design/0027-download-completion-order.md), [추가 도구 개발 기준](../policies/tools.md)을 유지한다. 이번 변경은 이 delivery 기록 한 파일뿐이다.

## 현재 CI와 기존 증거의 관계

| 근거 | 실제 확인 | 판정 한계 |
|---|---|---|
| [이전 PR CI 37070713164](https://github.com/prozac0401/Workspace/actions/runs/37070713164) | head `82a690f…`, Windows evaluation SUCCESS. 당시 checkout merge ref `f75e956…`의 tree가 head와 같음 | 당시 정확한 소스의 Windows CI 증거이며 브라우저 실기 결과가 아님 |
| [최신 main CI 37114200238](https://github.com/prozac0401/Workspace/actions/runs/37114200238) | source `e3a95ff66202ba56ea6f2e89c0b0a7d5aa1b77ae`, SUCCESS | Windows Server 2025 runner 범위 |
| 최신 CI와 현재 기준 소스 | DVM subtree `ffde8081e3dd8087742c2ad67ca5322c1ef96293`, workflow blob `6a1e07d98e892853a32d698c13bdba2a5ad2caa1`이 동일. CI manifest의 소스 38개 raw SHA-256도 현재 소스와 일치 | 다른 도구 또는 다른 설치 후보에 승계하지 않음 |
| 최신 CI 자동시험 | Node 확장 46 PASS / 0 FAIL, Windows Host 82 PASS / 0 FAIL / 0 NOT RUN | Node DOM/runtime 모형은 실제 Chrome·Edge·Native Messaging 시험이 아님 |
| 최신 CI MSI 수명주기 | 정상 lifecycle 15 PASS, 두 late-failure 합계 10 PASS / 0 FAIL / 0 NOT RUN. 각 trial 정리·완료 상태 확인 | Server runner의 rollback·재설치 성공은 기존 Win11 실패를 해결한 근거가 아님 |
| 이번 순차 준비의 집중 확인 | 작업 담당자가 Node 24.13.1에서 기존 `^popup ` 시험 6개만 실행: 6 PASS / 0 FAIL / 0 SKIP | 전체 suite, 새 빌드·설치, 실제 브라우저·키보드는 실행하지 않음 |
| 이번 release gate 확인 | 작업 담당자가 변경하지 않은 gate에 최신 CI MSI·checksum·evaluation channel과 기존 FAIL/NOT RUN을 입력: 예상 exit 1, `stableAllowed: false`. checksum 일치로 checksum 차단 사유 없음 | 차단의 정상 동작 확인이며 제품 출시 PASS가 아님. MSI는 실행하지 않음 |

[기존 TEST_RESULTS](../../tools/DownloadVersionManager/TEST_RESULTS.md)의 2026-10-03 로컬 준비 기록은 당시 Node 모형 46 PASS와 Windows 제작·실물 NOT RUN을 보존한다. 이후 원격 CI의 제작 결과는 위 표로 구분하며, 과거 미실행 기록을 실제 브라우저 PASS로 바꾸지 않는다.

## 최신 CI 평가 후보 식별

최신 CI artifact `11270443697`의 ZIP·manifest·package 결과·MSI를 파일 실행 없이 읽었다. 이 후보는 새 공개 Release가 아니며, 과거 후보와 제품 버전이 같아도 지문을 혼용하지 않는다.

- ZIP SHA-256: `0338223b3dcdb0d30c47643c6eacf2025ee16b6a454fc468cbc99b957acf194c` — 원격 artifact digest와 일치.
- MSI: `DownloadVersionManager-0.1.0-x64.msi`.
- MSI SHA-256: `fe055cf7ff0d7ac1121775c477b5d963cc418ea860bc3e476d5a85f5f287995d` — 실제 파일, build manifest, package verification, SHA256SUMS 일치.
- build manifest: 0.1.0 / protocol 2 / `evaluation` / `signed: false` / x64 / static CRT·Windows APIs. 자동시험 완료와 별도로 interactive gates는 NOT RUN이다.
- package verification PASS: payload 13개, HKCU 행 18개, Native Host 등록 2개, 서비스·시작 항목 0. 구조·행정 추출 검증이며 확장 활성화 PASS가 아니다.
- CI의 0.1.1은 upgrade 시험 fixture다. 다음 제품 버전으로 결정하거나 사용자 설치 자산으로 게시하지 않는다.

현재 작업에서 production 버전·코드·TEST_RESULTS·공개 안내·workflow를 바꾸지 않았고, MSI 제작·설치·업그레이드·제거·브라우저 조작·보안 설정 변경을 하지 않았다.

## 보존하는 출하 차단점

| 관문 | 현재 판정 | 근거와 다음 경계 |
|---|---|---|
| Windows 11 설치 실패 복구 | **installerFailureRecovery FAIL** | 과거 제품 게시 후 deferred / InstallExecute 후 immediate 실패에서 파일·Native 등록은 복구됐으나 제품 등록 rollback에 access denied(5), 바로 재설치 1638. 정상 설치·공식 제거 성공과 구분 |
| 최신 CI 후보의 현재 Win11 수명주기 | **NOT RUN** | 이번 후보를 현재 Win11에 설치하지 않음. Server CI의 15 PASS 및 late 10 PASS와 분리 |
| 과거 실패 재현 자료 | 원인 미확정 | 실패 state의 MSI hash와 현재 같은 경로 파일 불일치, 당시 token/security descriptor 부재. 기존 파일을 원본으로 재실행하지 않음 |
| 단일 배포 | **singleDistribution FAIL** | Store ID·게시·활성화·통합 배포 미완료. 개발용 Load unpacked는 사용자 작업이 필요한 평가 방식 |
| 실제 Chrome·Edge | **NOT RUN** | protocol 2 handshake, filename/endTime 계약, 대표 E2E, worker 복원, 확장 활성화 후 idle. 직접 Host ping·Node 모형·Server CI로 대신하지 않음 |
| 정식 출시 | **stable BLOCKED** | 필수 gate의 FAIL·NOT RUN과 evaluation channel 유지. 팝업 수정은 이 차단점의 해결 근거가 아님 |

세부 실패·후속 조사와 완료한 시험은 [후속 Win11 기록](download-version-manager-followup-20260930.md), [KNOWN_LIMITATIONS](../../tools/DownloadVersionManager/KNOWN_LIMITATIONS.md), [실기 절차](../../tools/DownloadVersionManager/tests/integration/README.md)를 따른다. 성공한 전체 GUI·설치·Host suite를 이 팝업 변경 때문에 다시 실행하지 않는다.

[문서 정책](../policies/documentation.md)은 “스토어 배포와 실제 Chrome·Edge 관문을 통과하기 전에는 공개 설치 자산이나 정식 배포 완료를 안내하지 않습니다”라고 규정한다. 확인 시점의 Releases API에는 DVM 관련 공개·Draft Release가 없다. **공개 평가 MSI도 지금 게시하지 않는다.** 평가판 표시와 CI 성공만으로 이 조건을 충족했다고 판단하지 않는다. 조직 배포·스토어 계정·서명 주체는 미결정이다.

## 제안하는 최소 팝업 실물 확인 — 이번에는 NOT RUN

환경은 승인된 Windows 일반 사용자 환경과 업무용 profile에서 분리한 Chrome·Edge 평가 profile이다. 확인할 후보의 MSI 지문·확장/Host 0.1.0·protocol 2·브라우저 버전을 기록하고 공식 확장 활성화를 사용한다. 기존 설치·등록이 있거나 정책이 차단하면 덮어쓰기·설정 우회 없이 중단한다.

| 대상 | 절차 | 기대 결과 | 완료 기준 |
|---|---|---|---|
| 대기 중 중복 입력 | 팝업을 연 뒤 진단을 시작하고 응답 대기 중 마우스 반복 클릭과 Enter/Space 반복을 확인 | 열기만 했을 때 요청 없음. 첫 진단만 요청하고 대기 중 버튼 잠김 | Chrome·Edge별 요청 한 건·버튼 상태·키보드 결과가 관찰된 경우만 PASS. 대기 상태를 관찰하지 못하면 NOT RUN |
| 결과 뒤 수동 재확인 | 정상 연결 결과와 Host 미연결 오류 결과 뒤 버튼 상태를 확인하고 다시 한 번 진단 | 성공·오류 뒤 버튼 재활성화, 새 진단 한 건 가능, 결과 문구 일치 | Chrome·Edge별 성공/오류 두 경로의 재사용 결과가 확인된 경우만 PASS. 이전 연결 시험을 반복한 것으로 합산하지 않음 |

이 두 확인은 팝업 변경의 실물 관문이다. 제품의 미완료 Chrome·Edge 계약/E2E·worker·idle 및 Win11 실패 복구·단일 배포 관문과 분리한다. 소스·문서 Draft 검토는 진행할 수 있지만 출하 준비 완료, 태그·패키지·공개 게시·stable 승인은 선언하지 않는다.

## 검토 종료와 비공개 자료

이 기록을 검토 가능한 Draft 변경으로 마무리한다. 사용자가 승인한 순차 출시 준비 범위의 실물 확인에는 기존 설치·업무 profile을 보존할 평가 환경이 필요하다. 미선택 설치 결함 수정과 Store 배포 방식·계정·서명 선택은 별도 범위 결정이 남아 있다. raw installer 로그·로컬 절대 경로·사용자 자료는 이 문서와 공개 사이트·Release에 넣지 않는다. 이 delivery 기록은 공개 안내 페이지가 아니다.

문서 검증은 MkDocs strict, 공개 19개·이전 주소 2개·404·검색·사이트맵·생성 로컬 링크 PASS이며 새 상대 파일 링크 9개도 PASS다. 새 delivery 기록·로컬 artifact·원시 진단은 공개 사이트에서 제외된다.
