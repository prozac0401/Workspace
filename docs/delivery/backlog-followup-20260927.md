# 백로그 후속 작업 · 2026-09-27

상태: 이전 비상승 실행 이력, 관리자 후속은 별도 기록 · 책임: 개발·검증 담당 · 기준: Workspace 4f747d510214b4344be94363bb20b30173f6dbd3

후속 변경: 사용자가 설치 시 관리자 권한을 허용했다. [관리자 설치 후속 기록](image-admin-install-20260927.md)과 [ADR-0022](../design/0022-image-admin-install.md)가 현재 권한 조건을 정한다. 아래 표와 결과는 앞선 비상승 일괄 실행의 이력이다.

## 확정된 범위

사용자는 일괄 순차 실행을 승인했다. 이미지 도구는 별도 서명 없는 MSI를 목표로 하며 Windows 11 첫 메뉴·조건부 숨김·일반 사용자 조건을 유지한다. native183 격리 복구는 필수에서 제외하고 명시적 현재 사용자 클립보드 시험을 사용한다. BookMark는 기존 실사용 확인과 v0.2.3 이후 제품 입력 코드 무변경을 근거로 필수 재검증에서 제외한다. 과거 NOT_RUN은 소급 PASS로 바꾸지 않는다. T01·T05는 마지막 후속 재점검 순서로 유지한다.

| 순서 | 항목 | 현재 상태 |
|---|---|---|
| 0 | 환경·프로세스 정리 | **PASS**. 착수·종료 후 확인 완료, 기존 작업과 현재 Codex 연결 보존 |
| 1 | R01 무서명 MSI 설치 경로 | **BLOCKED**. 무서명 sparse identity 등록이 0x80073D2B로 거부됨 |
| 2 | R02 실제 Explorer G0 | **NOT RUN**. R01 등록 차단으로 첫 메뉴 검증 미실행 |
| 3 | R03 현재 사용자 시험 모드 | **구현·검증 완료**. 모드 계약 7 PASS, 전체 85 PASS / 0 FAIL / 1 NOT RUN, 클립보드 23개 모두 PASS |
| 4 | R04 이미지 기능·설치 수명주기 | 엔진/helper 및 Paint 대표 연동 PASS. **MSI 설치 수명주기 NOT RUN** |
| 5 | R06 배포 후보 정리 | **NOT RUN**. 이미지 MSI 미제작, 배포 후보 판정·원격 게시 없음 |
| 6 | T01 안내·다운로드 점검 | **PASS**. strict 빌드·로컬 사이트 검사, 원격 링크 39개 HTTP 200 |
| 7 | T05 단일 EXE 재점검 | **PASS**. wrapper 24개·설치 수명주기 19개, 실제 Excel 붙여넣기·되돌리기·재실행·제거 후 메뉴 부재와 최종 정리 확인 |

## 환경 준비

원본 checkout은 main 89219d0이며 로컬 수정·미추적 파일이 있다. 이를 변경·삭제하지 않고 최신 origin/main 기반 codex/image-msi-20260927 worktree를 artifacts/worktrees 아래에 생성했다. 기존 .tools를 junction으로 재사용한다. 이 junction의 대상은 별도 원본 경로이므로 생성물 정리 시 재귀 삭제하지 않는다.

조회 시 Excel·msiexec·기존 시험/빌드 프로세스는 없었고 사용 가능 메모리는 약 6478 MiB였다. 확인된 Node/REPL은 현재 Codex 도구 체인에 속하므로 일괄 종료하지 않았다. MSBuild 서버 정상 종료 호출은 성공했으나 컴파일러 서버 shutdown은 path1 오류였다. VBCSCompiler가 실행 중이라는 증거는 없었다. 업무 앱과 사용자 자료는 보존했다. [준비 기록](../../artifacts/batch-20260927/preparation.json)

## R01·R02·R06: 현재 설치 경로의 차단

Windows 11 23H2 x64, OS build 22631.6199의 일반 사용자 환경에서 별도 서명 없는 sparse identity 패키지를 만들고 등록을 시도했다. 패키지 제작 자체는 성공했지만 Windows가 “서명되지 않은 패키지에 실행 가능한 활성화를 포함할 수 없다”는 이유로 등록을 거부했다. 오류는 **0x80073D2B**다.

이 결과는 시험한 무서명 sparse identity 경로의 BLOCKED 판정이다. 무서명 MSI의 파일 배포가 Explorer 확장 등록까지 성립한다는 근거가 아니며, 모든 가능한 설치 경로가 불가능하다고 확대하지 않는다. 현재 요구를 만족하는 최소 등록 경로를 확보하지 못했으므로 이미지 MSI를 제작하지 않았고 실제 Explorer G0·MSI 설치/업데이트/제거·배포 후보 검증은 NOT RUN으로 남긴다.

probe의 정리는 PASS이며 남은 시험 identity 등록은 없다. 인증서·신뢰 저장소·개발자 모드·보안 정책을 변경하지 않았고 권한 상승이나 Explorer 강제 재시작도 하지 않았다. MSI 또는 새 릴리스를 원격 게시하지 않았다. [등록·정리 결과](../../artifacts/image-copy-save/unsigned-identity-probe/20260927T001700658Z-20f31ff8a8ed435997d40649509f80cd/result.json)

native Shell 정책·COM 경계 시험은 **66 PASS / 0 FAIL**이다. 이 시험은 클립보드 접근, 실제 명령 호출, COM 등록, Explorer UI를 수행하지 않았으므로 G0를 대신하지 않는다. [native 결과](../../artifacts/image-copy-save/native-shell/shell-results.json)

## R03·R04: 현재 사용자 클립보드와 대표 앱 연동

[현재 사용자 시험 모드](../tools/image-copy-save/current-session-testing.md)와 [ADR-0020](../design/0020-image-current-session-tests.md)에 따라 두 명시 옵션을 모두 받은 경우에만 WinSta0\Default에서 시험한다. 기본 격리 경로와 native183 실패 기록은 유지하며 자동 전환하지 않는다. 세션 mutex로 시험 조정자의 중복 실행을 막고, worker 문맥·실행 토큰을 확인한다. 사용자의 클립보드를 백업·복원하지 않는 조건으로 합성 데이터를 순차 실행했다.

최종 전체 시험은 일반 사용자, Windows NT 10.0.22631, x64, .NET 10.0.12에서 **86개 중 85 PASS / 0 FAIL / 1 NOT RUN**이다. 클립보드 관련 23개는 모두 PASS이며 실제 제품 helper, 투명도 왕복, 새 복사 보존, 병렬 저장, 지연 렌더링·watchdog·취소, shell 호출 방어를 포함한다. 전용 VHD의 실제 디스크 부족 시험 한 개는 일회용 GitHub-hosted 환경 전제 때문에 로컬에서 실행하지 않았다. 이 미실행 때문에 전체 실행의 종료 코드는 의도대로 2다. 로컬 디스크를 채우거나 환경변수를 가장하지 않았다. [최종 전체 결과](../../artifacts/batch-20260927/clipboard-full-accepted.json) · [종료 코드](../../artifacts/batch-20260927/clipboard-full-accepted.result.json)

클립보드를 접근하지 않는 모드 계약 검사는 **7 PASS / 0 FAIL / 0 NOT RUN**이다. 옵션 한쪽 누락, 잘못된 조합, 단일 시나리오, 문맥 검증, 조정자 없는 worker, 동일 세션의 중복 조정자 차단을 확인했다. [모드 계약 결과](../../artifacts/batch-20260927/mode-contracts-final.json)

중간 전체 실행에서는 job 종료를 강화한 시험기에서 **84 PASS / 1 FAIL / 1 NOT RUN**이 나왔다. 실패 항목은 product-watchdog이며, job 종료 직후 이미 종료 중인 직접 자식에 TerminateProcess를 다시 호출하는 정리 경합이었다. job 종료 뒤 실제 프로세스 종료를 먼저 기다리고, 필요한 경우에만 직접 종료한 뒤 실제 종료와 전체 job의 ActiveProcesses=0을 확인하도록 수정했다. 확인에 실패하면 후속 클립보드 시나리오를 막는 동작은 유지했다. 수정 뒤 watchdog 단일 시험 PASS를 확인하고 전체를 다시 실행한 결과가 위 최종 결과다. 중간 실패 기록을 삭제하거나 소급 PASS로 바꾸지 않았다. [중간 실패](../../artifacts/batch-20260927/clipboard-full-final.json) · [수정 후 watchdog](../../artifacts/batch-20260927/clipboard-watchdog-race.json)

실제 Paint에서는 제품 helper가 이미지를 복사하고 종료한 뒤 붙여넣은 이미지 선택을 UI에서 확인했다. Paint에서 다시 복사한 이미지를 helper로 PNG 저장하는 왕복도 PASS이며, 결과는 150×150 PNG 한 개이고 합성 원본은 변경되지 않았다. 이 결과는 Paint 대표 연동만 확인한다. Explorer 호출, Word·PowerPoint·메일·메신저, 앱 간 정확한 알파 일치까지 확인한 것으로 기록하지 않는다. [Paint 결과](../../artifacts/batch-20260927/external-apps/results.json)

## T01: 안내·다운로드 후속 점검

python -m mkdocs build --strict는 종료 코드 0이었다. 로컬 사이트 검사는 공개 19개 페이지와 404, 검색·사이트맵의 공개 경로 제한, 비공개 자산 제외, 로컬 경로·자산 연결을 확인하고 PASS했다. [strict 빌드](../../artifacts/batch-20260927/t01-mkdocs.result.json) · [로컬 사이트 검사](../../artifacts/batch-20260927/t01-site.log)

공개 원본 19개 페이지에서 수집한 고유 URL **39개 모두 HTTP 200**을 확인했다. 기존 Pages 경로 19개와 GitHub 릴리스·다운로드 링크 20개다. 이 검사는 연결과 리다이렉트 대상 확인이며 설치파일의 실행·해시 검증과 구분한다. 변경한 개발 Markdown 13개의 로컬 참조도 깨진 경로 없이 확인했다. 이번 변경의 Pages 게시나 릴리스 갱신은 실행하지 않았다. [원격 링크 결과](../../artifacts/batch-20260927/t01-remote-links.json)

## T05: 보이는 칸 붙여넣기 단일 EXE 후속 점검

공개 0.1.1 ZIP의 파일 목록·16개 해시, x86/x64 PE·COM·Ribbon 메타데이터를 검사한 뒤 무서명 단일 EXE를 재빌드했다. wrapper 검사는 인수 처리, 안전하지 않은 압축 경로 거절, 압축 크기 상한, 한글·따옴표 인수 전달, 소유 파일 정리 등 **24개 PASS**다. [wrapper 결과 로그](../../artifacts/batch-20260927/t05-wrapper-build.log)

전용 한글·공백·따옴표 포함 설치 경로에서 기존 ZIP 설치→단일 EXE 전환, 파일 잠금 실패 시 보존과 재설치 복구, 비활성 상태·알 수 없는 파일/레지스트리 값 보존, 제거·반복 제거, 다른 추가 기능·Office 설정 보존을 확인했다. 설치 수명주기는 **19개 PASS**다. [설치 수명주기 결과](../../artifacts/visible-cells-paste/single-lifecycle-165f05fa23244aaa831fdf134f946cc0/results.json)

설치·수명주기 및 UI 시험에는 공개 EXE를 사용했다. EXE SHA-256은 bd55f32f3a9d467ed288696c8e80dd7f5e9eb97a280ba12a25fe622a5d26b464, 공개 ZIP SHA-256은 9555bf97c0d8ea0219a0692e6b1aad5594864a34af9cbf119c07fa7edbb20fa0이다. 재빌드 wrapper와 공개 설치파일의 실행 결과를 구분해 보존한다.

설치된 x64 Excel의 소유 합성 workbook에서 다음 네 단계가 각각 **13개 공통 확인 PASS**다. 이를 독립 사례 52개로 합산하지 않는다. 원본 값·숨긴 행 값·선택 밖 값·행 숨김 상태, E2/E4/E5의 정확한 값과 형식, 추가 기능 연결을 확인했다.

| 단계 | 실제 결과 | 근거 |
|---|---|---|
| 실행 전 | 연결됨, 클릭 0, idle | [before](../../artifacts/batch-20260927/t05-ui/before.json) |
| 실제 메뉴 붙여넣기 후 | 클릭 1, outcome/engine success | [pasted](../../artifacts/batch-20260927/t05-ui/pasted.json) |
| 실제 되돌리기 후 | 클릭 1, outcome/engine undone | [undone](../../artifacts/batch-20260927/t05-ui/undone.json) |
| Excel 재실행 후 | 자동 연결됨, 클릭 0, idle | [restart](../../artifacts/batch-20260927/t05-ui/restart-before.json) |

설치 후와 Excel 재실행 후의 실제 메뉴에서 “보이는 칸에 붙여넣기”와 “마지막 붙여넣기 되돌리기”가 각각 한 개였고 기존 “명단 비교” 메뉴도 남아 있었다. [설치 후 메뉴](../../artifacts/batch-20260927/t05-ui/installed-menu.txt) · [재실행 후 메뉴](../../artifacts/batch-20260927/t05-ui/restart-menu.txt)

별도로 설치한 UI 시험용 추가 기능도 제거 exit 0을 확인했다. 제거 후 세 번째 Excel 실행에서 제품의 붙여넣기·되돌리기 메뉴는 각각 0개, 기존 “명단 비교” 메뉴는 1개였다. 합성 workbook의 시험 전후 SHA-256은 동일했다. [UI 설치·기능·제거 종합 결과](../../artifacts/batch-20260927/t05-ui/results.json)

시험 창을 정상 종료한 뒤 EXCEL.exe, msiexec.exe, ImageCopySave*, VisibleCellsPaste*, dotnet.exe, VBCSCompiler.exe 프로세스가 남지 않았음을 확인했다. 자동 로드·제거 등록 키의 부재도 확인했다. 최종 정리는 PASS이며, 기존 사용자 업무 앱과 현재 Codex/Node 연결은 보존했다. 종료 시점 사용 가능 메모리는 약 5723 MiB였으며 이를 이번 정리의 확보량으로 해석하지 않는다. [최종 정리 기록](../../artifacts/batch-20260927/cleanup-final.json)

## 남은 범위와 판정 한계

- 이미지 MSI와 실제 Explorer 첫 메뉴는 미완료다. native·helper·Paint 시험 통과를 설치·G0 통과로 합산하지 않는다.
- 전용 VHD 실제 디스크 부족 한 개는 NOT RUN이다. 다른 외부 앱, x86 Office 실제 실행, 새 PC, Windows 재부팅·재로그인은 이번 확인 범위 밖이다. T05의 x86 정적 패키지 검사와 x64 Excel 재실행을 이 검증의 대체물로 사용하지 않는다.
- T05 수명주기에서는 레지스트리 ACL·전원 차단 주입 시험을 수행하지 않았다. 원격 게시와 이미지 MSI 제작은 하지 않았다.
- 별도 서명 없는 평가·검증 산출물이며 상용 승인 릴리스로 분류하지 않는다. 조직별 승인·설정이 결정되었다고 기록하지 않는다.
- BookMark 입력 재검증과 격리 환경 native183 복구는 이번 필수 범위에서 제외한 상태를 유지한다.

원시 경로·PID·사용자 설치 진단·일시 리다이렉트 URL은 로컬 artifacts/batch-20260927 및 도구별 artifacts 아래에 보존한다. 이 검증 기록과 증거는 공개 사이트에 포함하지 않으며 원본 checkout의 기존 로컬 변경도 보존한다.
