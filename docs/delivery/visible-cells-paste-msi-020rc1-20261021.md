# 보이는 칸 붙여넣기 · 0.2.0-rc.1 MSI 검증·배포 기록

기록일: 2026-10-21 · 버전: 0.2.0-rc.1 · MSI ProductVersion: 0.2.0<br>
상태: 서명 없는 사전 공개 릴리스 게시·다운로드 해시·Pages 운영 반영 확인 완료<br>
제품 책임: 도구 개발·검증 담당<br>
관련 문서: [원본 명세](../tools/visible-cells-paste/original-specification.md), [현재 대응표](../tools/visible-cells-paste/acceptance.md), [영역 ADR-0037](../design/0037-visible-cells-paste-rectangles.md), [MSI ADR-0038](../design/0038-visible-cells-paste-msi.md), [이전 로컬 평가](visible-cells-paste-rectangles-20261021.md)

## 요청·범위와 완료 근거

영역 붙여넣기 구현 뒤 사용자가 MSI 형태의 릴리스를 요청했다. 공개 0.1.2의 COM 수명·상태바 복원·Undo 안내를 보존한 최신 소스에 영역 처리를 통합하고 사용자별 x86·x64 MSI를 제작한다. 기존 작업공간의 별도 0.2.0-eval.1을 그대로 게시하거나 과거 성공을 새 후보의 성공으로 승계하지 않는다.

영역 변경은 기존 관련 자동 검사와 실제 Excel의 18개 집중 시나리오로 확인한다. 설치 변경은 MSI 정적 검사·일반 사용자 설치·실행 중 차단·정상 시작·제거·소유권 보존·중단 복구의 실제 위험에 연결된 항목으로 확인한다. 새 실패나 미해결 근거 없이 전체 GUI·전체 성능·반복 설치 시험으로 확대하지 않는다. 문서 양식의 검증·지원과 배포 기록 구분을 적용하며 별도 승인 절차를 만들지 않는다.

## MSI 계약

- `VisibleCellsPaste-0.2.0-rc.1-x64.msi`와 `VisibleCellsPaste-0.2.0-rc.1-x86.msi`는 각각 같은 비트 수의 Excel용이며 CAB를 내장한다.
- 현재 사용자 `%LOCALAPPDATA%\Programs\VisibleCellsPaste`와 HKCU를 사용한다. COM·Excel Addins 식별자는 기존 제품과 같고 MSI의 UpgradeCode는 별도로 관리한다.
- 기존 EXE·ZIP 또는 다른 MSI 버전은 먼저 제거하도록 안내하고 변경 없이 중단한다. 자동 전환·자동 업그레이드·Excel 강제 종료를 하지 않는다.
- 읽기 전용 native 사전 검사·실행 직전 검사를 거친 뒤 파일·등록 쓰기·삭제·롤백은 Windows Installer가 수행한다. 기존 Setup.exe를 MSI 내부에서 실행하지 않는다.
- 소유 파일 해시·등록 값이 달라지면 복구·제거를 거절한다. 비활성화된 LoadBehavior도 포함한다. 알 수 없는 추가 파일·등록 값은 보존한다.
- 유지 관리의 MSI 제품·설치 위치는 즉시 검사에서 독립 확인한다. 중단된 설치의 표식 누락은 이 확인과 남은 항목 검사를 전제로 처리하며 다른 소유자 표식은 거절한다. 지연 검사에서는 제거 중 바뀌는 MSI 제품 상태를 다시 조회하지 않는다.
- VBA 주입·보안 정책 완화·업무 파일 수정·원본/대상 자동 저장을 하지 않는다.

## 현재 실행 결과

| 범위 | 판정 | 실제 결과·제한 |
|---|---|---|
| 통합 소스 집중 자동 검사 | PASS | core57·native48·snapshot15·COM36·lifecycle46·presentation41 = 243개. 실제 Excel을 실행하지 않은 검사 |
| 전체 제품 제작·자동 검사 | PASS | 335회: core57·native48·snapshot15·lifecycle46·COM x64 36·COM x86 36·global20·presentation41·Setup36. 집중 검사와 중복 합산하지 않음 |
| 최신 통합 소스 실제 Excel 영역 회귀 | PASS | Excel x64에서 18/18. 합성 타입 스냅샷을 제품 엔진에 전달한 시험이며 실제 Ctrl+C·우클릭 경로와 구분 |
| x86/x64 MSI 제작·정적 검사·자산 해시 | PASS | 031400-bac791cc의 양쪽 MSI 제작·verify-msi 통과, native guard는 비트 수별 14/14. 같은 파일을 게시하고 아래 해시를 대조 |
| 게시한 MSI 일반 사용자 설치·파일 대조 | PASS | 031517-61ec7230에서 x64 설치 종료0, 설치 파일 해시·기존 알 수 없는 파일 보존 확인 |
| 게시한 MSI 정상 Excel 시작·제거 | PASS · 일반 Explorer 실행 | Excel 16.0 Build20430 x64에서 시작·재시작 각각 자동 연결과 정상 종료 확인. 표준 제거 종료0, 제품 상태-1, 합성 업무 파일 보존. 도구 실행 환경의 앞선 자동 로드 FAIL은 이력에 유지 |
| 잘못된 Excel 비트 수 차단 | PASS | 게시한 파일에서 예상 종료1603, 파일 미생성 확인 |
| MSI 정상 수명주기·외부 변경 보호 | PASS | 일반 Explorer에서 시작한 032832-591ce8b1 시험 25/25. 설치 등록30개·자동 로드·누락 파일/표식 복구·변경 파일/LoadBehavior/경로 변조 차단·추가 파일/값 보존·정상 제거·재제거1605 확인. 늦은 실패 주입은 포함하지 않음 |
| 실제 기존 EXE·다른 MSI 설치와 실행 중 Excel 충돌 | NOT RUN | 이번 25개 실기 시험에는 별도 기존 설치·실행 중 Excel 충돌 사례를 포함하지 않음. native guard 검사·과거 Setup 결과와 구분 |
| 표준 쓰기 뒤 실패 주입의 전체 롤백 | FAIL · 일반 Explorer에서도 재현 | 초기 030632-4191e75d 및 일반 Explorer의 desktop-rollback-20261021-033144에서 제품 파일·소유 등록은 제거됐지만 내부 Installer 등록 롤백 접근 거부5와 제품 상태5가 남음. 최신 시험 설치는 독립 제품·위치 확인 후 표준 /x 종료0·제품 상태-1·합성 업무 파일 보존으로 정리 |
| 실제 Excel 복사→설치된 Paste probe | 입력 전제 FAIL · 붙여넣기 미실행 | 초기 OpenClipboard 오류5와 별개로 일반 Explorer에서 합성 Range.Copy 후 복사 상태는 확인했으나 클립보드 소유 HWND/PID가0. 내용 읽기와 설치된 Paste 호출 전에 중단. 아래 조사 기록 참조 |
| 실제 Ctrl+C·우클릭 UI 전체 경로 | NOT RUN | COM Range.Copy 기반 probe와 구분. 클립보드 파서·메뉴 경로의 실제 성공 증거 없음 |
| Office 32비트 실제 실행·새 PC·전체 공존 | NOT RUN | x86 제작·COM 자동 검사를 Office 32비트 실제 실행으로 확대하지 않음 |
| 문서 strict·생성 링크·공개 범위 | PASS | 설치 실패 복구 안내 추가 후 MkDocs strict 종료0(2.70초), 생성 사이트 검사 종료0. 공개22페이지·이전주소2개·404, 검색·사이트맵·비공개 제외·로컬 경로/자산 확인. 변경 Markdown18개 상대링크191개 오류0, VCP SVG16개 XML 검사 통과. 동결한 동봉 문서9개 해시 불일치0 |
| PR-34 최초 제출 CI | PASS · 해당 커밋 한정 | 258a3cd6dd5ee27e9bc7009f6e96da32ba08d13f에서 Windows 검사2개와 문서 verify 성공. 후속 커밋·Pages 배포·릴리스 게시 결과와 구분 |
| PR-34 최종 제출 CI·병합 | PASS | 최종 head 7df45f74ebddda4f9c257cda03628a0e03ce5a3a에서 도구 MSI·일반 Windows·문서 verify 성공. 병합 커밋 b73ff5f0ab68a95cff27b14c67d67923578e0bef |
| GitHub 사전 공개 릴리스·다운로드 확인 | PASS | 2026-10-21 03:43:01 UTC 게시, draft=false·prerelease=true. 공개 자산3개를 다시 내려받아 전부 로컬 SHA-256과 일치 확인 |
| GitHub Pages 운영 반영 | PASS | 병합 커밋 b73ff5f의 운영 verify·build·deploy 성공. 03:44:06 UTC 배포 완료, 03:44:26 UTC 공개 안내 HTTP200·MSI·사각형 영역·Releases 목록 연결 확인 |

[0.2.0-rc.1 사전 공개 릴리스](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.2.0-rc.1)는 `prozac0401/Workspace`에 게시했다. 태그 `visible-cells-paste-v0.2.0-rc.1`과 PR 병합 커밋은 모두 `b73ff5f0ab68a95cff27b14c67d67923578e0bef`를 가리킨다. 공개 시각은 2026-10-21 03:43:01 UTC(한국 시각 12:43:01)다.

[PR-34](https://github.com/prozac0401/Workspace/pull/34)의 최초 제출 CI 근거는 [Windows 검사](https://github.com/prozac0401/Workspace/actions/runs/39539300611), [도구 Windows 검사](https://github.com/prozac0401/Workspace/actions/runs/39539300607), [문서 verify](https://github.com/prozac0401/Workspace/actions/runs/39539300613)다. 최종 head의 [도구 MSI 검사](https://github.com/prozac0401/Workspace/actions/runs/39539788613), [일반 Windows 검사](https://github.com/prozac0401/Workspace/actions/runs/39539788605), [문서 verify](https://github.com/prozac0401/Workspace/actions/runs/39539788634)도 성공했다. 두 PR 문서 실행의 Pages build·deploy는 SKIPPED였으며 이를 공개 사이트 배포 성공으로 계산하지 않는다.

병합 뒤 [Pages 운영 실행](https://github.com/prozac0401/Workspace/actions/runs/39540078195)은 같은 병합 커밋에서 verify·build·deploy를 모두 통과했다. [공개 설치·사용 안내](https://prozac0401.github.io/Workspace/tools/visible-cells-paste/)의 HTTP200 응답과 MSI·사각형 영역 안내, 기존 Releases 목록 연결을 확인했다. 실제 응답 검사 근거는 `artifacts/visible-cells-paste/0.2.0-rc.1/published-guide-check.json`이다.

## 산출물·해시

게시한 파일은 `artifacts/visible-cells-paste/0.2.0-rc.1/msi/20261021-031400-bac791cc`의 검증한 산출물 그대로다. 릴리스에서 MSI2개와 SHA256SUMS.txt를 다시 내려받아 아래 로컬 SHA-256과 전부 일치함을 확인했다. 근거는 `artifacts/visible-cells-paste/0.2.0-rc.1/download-verified/verification.json`이다. 공개 자산은 이3개뿐이며 rollback-test MSI, 내부 manifest·실기 로그·개인 경로·합성 업무 자료는 포함하지 않았다.

| 파일 | 최종 로컬 SHA-256 | 원격 다운로드 대조 |
|---|---|---|
| VisibleCellsPaste-0.2.0-rc.1-x64.msi | `660de50f9d379fccb4b4c9a3257902c9a917109bb1b981fae1c7fae81d6e4194` | MATCH |
| VisibleCellsPaste-0.2.0-rc.1-x86.msi | `97a9332db7939eff2ff2ee144ea5af1401d4c7fc0db5bdc7d95eefaee10aed0c` | MATCH |
| SHA256SUMS.txt | `934d52f7854c0cf60fd4d0eafb21a11b9f7eab8ec59fd1fc7a7768e75e1a17c8` | MATCH |

MSI ProductVersion은 0.2.0, AssemblyVersion은 0.2.0.0이다. x64 MSI는 311,296바이트, x86 MSI는 278,528바이트다. 각 패키지는 제품 DLL과 동결한 안내 문서 9개를 포함한다. x86 제작·native 검사 성공은 Office 32비트의 실제 실행 성공을 뜻하지 않는다.

## 설치 시험 이력과 남은 실패

각 실행의 결과는 `artifacts/visible-cells-paste/msi-tests/<실행ID>/results.json`과 같은 폴더의 MSI 로그로 보존한다. 실패 주입 자산은 공개하지 않는다.

| 실행 | 확인 내용 | 판정·후속 처리 |
|---|---|---|
| 20261021-030430-2d2c5005 | 최초 하네스의 msiexec 인수 인용 | 첫 비트 수 검사에서 예상1603 대신1639. 모든 인수를 따옴표로 감싼 하네스를 고쳤다. MSI 동작에 진입하기 전 실패이며 제품의 비트 수 차단 실패로 해석하지 않음 |
| 20261021-030632-4191e75d | 표준 파일·등록 쓰기 뒤 실패 주입 | 예상1603과 소유 파일·표식 제거는 각각 PASS. Windows Installer 내부 HKU/HKLM 등록 롤백에서 접근 거부5가 발생해 제품 상태5가 남았으며 다음 설치도1603. 전체 실패 복구는 FAIL |
| 같은 실행의 정리 로그 | 생성한 시험 설치만 공식 제거 | 기존 guard가 표식 누락을 거절한 기록을 보존. 수정 소스로 제거한 중간 상태는 advertised1. 시험에서 확인한 제품 표식만 정확히 복원한 뒤 표준 msiexec /x 종료0, 최종 제품 상태-1을 확인. 합성 업무 파일 보존 |
| 20261021-031517-61ec7230 | 도구 실행 환경의 설치·자동 로드 검사 | 비트 수 차단·설치 종료0·파일 대조·추가 파일 보존 PASS. 자동 로드 검사는 COM 색인 오류로 FAIL. 이후 일반 Explorer 실행 환경과 읽히는 사용자 등록이 다른 사실을 확인했으며, 이 FAIL을 정상 사용자 실행 실패로 확대하지 않음 |
| installed-startup/desktop-startup-first.log | 일반 Explorer 실행 환경에서 같은 설치의 정상 시작 | 시작과 재시작 모두 자동 연결·정상 종료 PASS. 같은 제품 표준 제거 종료0, 제품 상태-1, 합성 업무 파일 보존은 desktop-suite-progress.json에 기록 |
| 20261021-032832-591ce8b1 | 일반 Explorer에서 시작한 정상 수명주기 시험 | 25/25 PASS. 설치 등록30개·파일 해시·자동 로드·파일/표식 누락 복구·외부 변경 차단·추가 파일/값 보존·제거·재제거 확인. desktop-suite-result.json의 complete/success=true와 설치 probe의 시작·재시작·정상 종료 PASS 확인 |
| desktop-rollback-20261021-033144 | 일반 Explorer 환경에서 늦은 실패 한 번 재확인 | 최종 guard를 포함한 031400-761aff63-rollback-test 사용. FailRollbackTest 도달·종료1603, 소유 파일과 등록30개 제거·합성 업무 파일 보존. 내부 롤백 오류와 제품 상태5·RelatedProducts 잔존으로 전체 FAIL 재현 |
| 같은 실행의 official-recovery-remove.log | 최신 시험 설치의 표준 제거 | 독립 MSI 제품·정확한 설치 위치 확인 후 /x 종료0, 제품 상태5→-1, 합성 업무 파일 보존. desktop-rollback-recovery-result.json success=true. 내부 등록·ACL 수동 수정 없음 |

읽기 전용 guard는 실제 설치 시험에서 드러난 세 문제를 고쳤다. impersonation 중 캐시된 HKCU 대신 RegOpenCurrentUser로 현재 사용자 hive를 연다. MSI 제품 상태·설치 경로는 즉시 사전 검사에서만 확인하고 지연 검사는 전달받은 인수와 남은 항목을 검사한다. 중단 설치에서 소유 표식이 없을 때는 독립 MSI 제품·경로 확인을 전제로 진행하지만 다른 소유자가 적힌 표식과 변경된 파일·등록 값은 계속 거절한다. 이 수정이 Windows Installer 내부 등록 롤백의 접근 거부를 해결했다는 뜻은 아니다.

자동 로드 조사에서는 도구 실행 환경과 일반 Explorer 실행 환경이 같은 사용자 등록을 읽지 않는 차이를 관찰했다. 실제 사용자 경로의 시작·재시작·정상 종료를 직접 확인해 자동 로드 여부를 판정했다. 특정 패키지 기술이나 Windows 내부 구현을 원인으로 확정하지 않는다. 앞선 실행 환경의 실패 로그를 지우거나 검사 성공으로 고치지 않는다. 관련 근거는 `artifacts/visible-cells-paste/installed-startup/desktop-startup-first.log`, `registry-explorer-context.json`, `desktop-suite-result.json`과 정상 suite 폴더의 `installed-excel-probe.log`다.

내부 등록 롤백의 접근 거부와 제품 상태 잔존은 이 PC의 [이전 DownloadVersionManager 후속 검증](download-version-manager-followup-20260930.md)과 같은 관찰 양상이다. 동일한 원인이라고 확정하지 않으며 이번 기록에서도 미해결로 남긴다. Windows Installer 내부 등록이나 ACL을 수동 수정하지 않았다. 시험에서 만든 제품 표식의 제한된 복원은 일반 사용자 복구 방법으로 안내하지 않는다.

25개 정상 수명주기 시험에는 늦은 실패 주입을 포함하지 않았다. 이후 실행 환경에 따라 사용자 등록 관찰이 달랐다는 새 근거가 생겨 일반 Explorer에서 해당 실패 경로만 한 번 다시 확인했고, 같은 실패가 재현됐다. 추가 반복은 하지 않는다. 정상 경로와 실패 후 공식 제거가 통과해도 이 FAIL을 PASS로 바꾸거나 전체 실패 복구가 확인됐다고 기록하지 않는다. 최신 재확인·정리 요약은 `artifacts/visible-cells-paste/installed-startup/desktop-rollback-result.json`과 `desktop-rollback-recovery-result.json`이다.

## 실제 클립보드 조사

앞선 별도 작업공간 조사에서는 OpenClipboard가 오류5 접근 거부로 끝났다. 이번 후보는 정상 Explorer에서 시작한 Excel의 합성 통합문서에 COM Range.Copy를 실행해 설치된 Paste 콜백까지 확인하려 했으나, 첫 probe는 복사 소유권 전제에서 FAIL로 중단됐다. Ctrl+C 키나 우클릭 UI를 조작한 시험이 아니다.

한 번의 제한된 진단에서는 WinSta0/Default, ExcelVisible=True, CutCopyMode=1을 확인했다. 약2초 동안 클립보드 소유 HWND/PID는 모두0이고 sequence는345로 변하지 않았다. 소유자를 확인할 수 없어 클립보드 내용은 읽지 않았으며 설치된 Paste 콜백도 호출하지 않았다. 실제 클립보드 형식·파서·셀 쓰기·되돌리기의 성공 증거로 계산하지 않는다. 업무 데이터는 수집하지 않았으며 추가 원인 조사는 하지 않는다.

근거는 `artifacts/visible-cells-paste/installed-rectangle-clipboard/actual-clipboard-report.txt`, `diagnostic-clipboard-report.txt`, `diagnostic-console.log`다. `final-result.json`에는 probe 종료1과 당시 아직 종료 중인 Excel 때문에 MSI 제거를 보류한 상태가 남아 있다. 이후 Excel이 종료된 것을 확인하고 표준 /x로 정리했으며 `cleanup-result.json`은 success=true, 제거 종료0, 제품 상태-1, 소유 파일 잔존0을 기록한다. Excel 강제 종료나 내부 Installer 등록 수동 수정은 하지 않았다. 정상 정리 성공이 클립보드 probe의 FAIL을 바꾸지는 않는다.

## 문서와 공개 안내

패키지 문서는 제작 전에 동결했다. 동결 시점의 집중 243개 결과와 이후 실제 MSI 수명주기·게시 결과를 구분한다. 최종 결과를 동봉 문서 안에 넣기 위한 반복 MSI 제작·설치를 하지 않는다. 기존 0.1.2·0.1.1·0.1.0의 성공·종료 실패와 0.2.0-eval.1 별도 평가 기록은 보존한다.

공개 안내는 최신 문서 정책에 따라 기존 Workspace Releases 목록으로 연결하고 영역 선택·Excel 비트 수별 MSI·이전 설치 제거·복구 방법을 설명한다. 특정 버전·직접 자산 URL·내부 시험 수치·서명 경고를 공개 페이지와 검색에 새로 넣지 않는다. 사전 공개 상태·서명·미검증·정확한 자산 해시는 이 기록과 릴리스 노트에 보존한다. 페이지 내용 반영과 실제 Pages 배포 완료도 구분한다.

문서 명령은 문서용 Python의 `-m mkdocs build --strict`와 `scripts/check-site.py site`다. 이번 실행 결과·상대 링크 검사 요약은 artifacts/visible-cells-paste/msi-docs-20261021/validation.json에 기록했다. VCP의 기존 그림 JSON 8개·SVG16개만 다시 생성했으며 새 공개 자산 경로나 다른 도구의 그림을 추가하지 않았다.

## 남은 한계

서명 없는 사전 공개 버전이며 회사별 배포 승인을 뜻하지 않는다. 실제 Ctrl+C 영역 입력은 이번 후보의 전체 경로로 검증하지 못했다. 표준 쓰기 뒤 실패 주입에서 Windows Installer 내부 제품 등록의 롤백은 실패했으며 미해결이다. MSI 설치·정적 확인·자동 검사 성공을 클립보드·모든 환경·전체 수명주기 보증으로 확대하지 않는다. 외부 동시 편집과 Excel 강제 종료·OS 장애에 대한 완전한 데이터 복구 보장도 하지 않는다.
