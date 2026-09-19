# FolderState 사용성 개선 검증 · 2026-09-19

제품: FolderState 0.1.3 로컬 후보 · 상태: 엔진·UI·문서·패키지 검사 완료, 평가용·미배포

## 변경 범위

관리 화면의 경로 입력과 확인한 대상을 분리하고, 폴더 전환 시 상태·아이콘 위치·결과를 함께 갱신했습니다. 상태 유무와 중단 복구 여부에 따라 작업 버튼을 구분하며, 결과에 대상과 성공·주의·실패를 표시합니다. 현재 상태 카드, 탐색기에서 보기, 별도의 아이콘 저장 위치 적용을 제공합니다. 지우기는 설명을 펼친 뒤 실행합니다.

Core의 ChangeMode는 기존 트랜잭션을 사용해 상태와 상태 변경 시각을 보존합니다. 업무 파일·폴더명·하위 검색·저장 형식·설치 권한은 변경하지 않습니다. 요구와 결정은 [사용성 명세](../tools/folderstate/usability.md), [ADR-0007](../design/0007-folderstate-usability.md)에 연결합니다.

## 실제 확인 결과

| 항목 | 결과와 범위 |
|---|---|
| 문서 | MkDocs strict 종료 코드 **0**, 최초 빌드 7.66초 및 최종 기록 반영 후 재확인 7.59초. 별도 사이트 검사도 최종 종료 코드 **0**이며 공개 15페이지·404·검색·사이트맵·로컬 링크 및 내부 자산 제외 검사 통과 |
| 엔진 | 결과 JSON의 total 47, 실제 항목 47, passed=true 47, failed 0이 일치합니다. **47/47 통과**. 새 저장 위치 변경 10개 시나리오와 기존 37개를 포함합니다. |
| WPF | **상호작용 12/12 통과**, 기본 화면 렌더까지 완료하고 종료 코드 **0**. 최소 크기와 최소 크기 하단 렌더도 각각 종료 코드 **0**입니다. 기본 900×780, 최소 760×560 PNG의 배경·네 아이콘·현재 상태 배지·하단 펼침과 스크롤을 육안 확인했습니다. |
| MSI | `scripts/build.ps1 -Version 0.1.3 -SkipTests` 종료 코드 **0**. 앞서 동일 엔진의 47개 통과와 최종 WPF 12개 통과 결과를 재사용했습니다. `scripts/verify-msi.ps1`도 종료 코드 **0**이며 버전 0.1.3, 파일 414개, 탐색기 명령 6개, 사용자별 설치와 HKCU 전용 레지스트리를 확인했습니다. 서명 상태는 **NotSigned**입니다. |

엔진 결과의 기록 시각은 2026-09-19 18:30:52 +09:00이며, 기록된 OS는 Microsoft Windows NT 10.0.22631.0입니다. 새 저장 위치 시험은 상태 없음, Local↔Portable 왕복과 시각·원본 보존, 알 수 없는 정보 보존, 외부 아이콘 보호, 설치 아이콘 누락, 단계별 롤백, 프로세스 중단 복구, 동시 변경, 동시 상태 변경 후 최신 값 유지, 이전 형식의 전환·reset을 확인했습니다.

WPF 상호작용 시험은 확인 전 적용 차단, 대상 전환과 빈 상태의 기본값, 오류 초기화, 잘못된 경로 차단, 중단 복구, 미적용 위치 선택과 상태 저장의 분리, 독립 위치 적용의 시각 보존, 성공·실패·주의 구분, 저장 성공 후 조회 실패를 확인했습니다. 초기 검증기는 제품의 `App.OnStartup` 경로에서 모달 창이 열려 완료되지 않았습니다. 공용 `Styles.xaml`을 제품 앱과 검증용 일반 `Application`이 함께 읽도록 바꾼 뒤 다시 실행하여 상호작용과 렌더 완료 및 정상 종료를 확인했습니다.

근거는 로컬 `artifacts/folderstate-usability-20260919/`의 다음 파일입니다.

| 근거 파일 | 확인한 사실 |
|---|---|
| `engine-test-results.json` | 47개 결과와 실패 0, 개별 시나리오의 통과 여부 |
| `docs-verify.py`, `docs-final.log`, `docs-final.result.json` | 저장소의 문서 모듈로 `mkdocs build --strict` 실행, 7.66초, 종료 코드 0 |
| `site-links.log`, `site-links.result.json` | 공개 페이지·자산·검색·사이트맵·로컬 링크 검사 PASS, 종료 코드 0 |
| `final-doc-checks.json` | 최종 기록 반영 후 문서 strict 7.59초·사이트 링크·변경 범위 diff 검사 종료 코드 0 |
| `ui-verify-passed.log`, `ui-verify-passed.result.json`, `ui-verified.png` | 상호작용 12개와 기본 렌더 PASS, 종료 코드 0, 기본 화면 육안 확인 |
| `ui-minimum.log`, `ui-minimum.result.json`, `ui-minimum.png` | 최소 크기 렌더 PASS, 종료 코드 0 |
| `ui-minimum-bottom.log`, `ui-minimum-bottom.result.json`, `ui-minimum-bottom.png` | 최소 크기 하단 렌더 PASS, 종료 코드 0, 펼침·스크롤 육안 확인 |
| `release-package-no-server.log`, `release-package-no-server.result.json` | 릴리스 빌드 스크립트의 GUI·CLI 자체 포함 게시와 MSI 생성, 종료 코드 0 |
| `msi-verify-complete.json`, `msi-verify-complete.result.json` | 일반 호스트 PowerShell의 최종 MSI 구성 검사 출력과 종료 코드 0 |
| `package-evidence.json` | MSI 크기·SHA-256 일치, 최신 도움말 일치, 포함된 .NET·Windows Desktop 10.0.12 런타임 |

로컬 시험·렌더·진단은 artifacts 아래에 보관합니다. 업무 경로와 원시 로그를 공개 사이트에 추가하지 않습니다.

## 로컬 평가 패키지

- 파일: `artifacts/release/FolderState-0.1.3-win-x64.msi`
- 크기: 50,465,413바이트
- SHA-256: `753b61742b63c93958e9f61cf773377c8797c598f1dc5d3a6cbac86f37c27a73`
- 동봉 `.sha256` 값과 실제 파일을 스트리밍 계산한 값이 일치합니다. 게시 폴더의 `help.html`도 최신 원본과 일치합니다.

초기 빌드는 공유 컴파일러 응답을 기다려 중단했고, 최종 빌드에는 `UseSharedCompilation=false`, `DOTNET_CLI_USE_MSBUILD_SERVER=0`, `MSBUILDDISABLENODEREUSE=1` 환경 설정을 사용했습니다. 초기 Node 실행 환경의 MSI 검사는 메모리 부족으로 실패했습니다. 동일 MSI를 일반 호스트 PowerShell에서 다시 검사해 정상 종료를 확인했으며, 초기 실패를 패키지 검사 통과로 간주하지 않았습니다.

## 검증 한계와 배포 상태

실제 초보 사용자, 키보드만으로 전체 흐름 완료, Narrator, 고대비, 150/200% DPI, 공유·동기화·보안 프로그램 환경은 이번에 검증하지 않았습니다. 중단 시험은 프로세스 종료이며 전원 손실 시험이 아닙니다. 설치·업데이트·복구·제거의 실제 수명주기 시험과 코드 서명은 별도입니다.

현재 공개 설치 파일은 **0.1.2 RC1**이며 이번 변경을 포함하지 않습니다. 0.1.3은 서명되지 않은 로컬 평가용 후보이며 상용 승인 릴리스가 아닙니다. GitHub Release와 Pages에 게시하지 않았습니다. 여러 폴더 GUI 처리, 실행 취소, 탐색기 성공 알림, Windows 11 첫 메뉴 통합, 작업 기록 전용 화면은 후속 검토 대상입니다.
