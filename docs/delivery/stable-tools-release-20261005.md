# 정식 릴리스 채널 전환 · 2026-10-05

사용자는 Excel RC13의 미제 수정과 정식 배포, 특별한 문제가 없다면 FolderState·업무 책갈피의 정식 배포를 순차적으로 요청했습니다. 이 기록은 정식 채널 게시와 코드 서명·회사별 도입 승인을 구분합니다. 이전 FAIL·NOT RUN과 과거 평가판의 기록은 보존합니다.

## 현재 배포

| 도구 | 공개 릴리스 | 소스·파일 연결 | 이번 변경 |
|---|---|---|---|
| Excel 명단 비교 0.2.1 | [정식 Release](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.1) | 포장 소스 `0d76e5660ba529c42f5eb5089453f8cbc127ba98`, main 병합 `f9e4b77d67a4b66ec3ad2a486fe1d4208ac0ce2d` | 상태표시줄 보존, 새 회귀 검사 호출 인수 수정, 0.2.1 포장 |
| FolderState 0.1.3 | [정식 Release](https://github.com/prozac0401/Workspace/releases/tag/folderstate-v0.1.3) | 기존 RC1 소스 `e4e457ebab884222407cc2e8bc3473bb23d4fe4f`와 같은 MSI·체크섬·검증 JSON | 채널·사용 안내 변경. runtime·installer·assets·build 변경 없음 |
| 업무 책갈피 0.2.8 | [정식 Release](https://github.com/prozac0401/BookMark/releases/tag/v0.2.8) | 기존 태그/SourceSnapshot 소스 `d507a885ed5f73bca95ee0989bb2e0295915a787`와 같은 모든 첨부 자산 | 기존 릴리스의 prerelease 표시 해제, 사용자 Whale 확인과 현재 안내 추가 |

FolderState RC1과 업무 책갈피 0.2.8을 이미 사용 중이라면 채널 전환 때문에 재설치할 필요가 없습니다. 기존 RC1 릴리스와 모든 이전 자산은 보존합니다.

## 실제 파일 지문

| 파일 | SHA-256 |
|---|---|
| ExcelSmartListCompare-0.2.1-Setup.exe | `df1abba1720be680a16b983f552cfdae88b21eaf885f85a071008ee9a8b45db6` |
| FolderState-0.1.3-win-x64.msi | `27a63645375988aa31dc53ae537f6f01d7a466788812e377807ddfdbe2a79bbf` |
| WorkBookmark-0.2.8-win-x64.msi | `4e2dba00c42e7b169d0a88cb9b43d70ded960dc1ba1b50176624d903295a4ba0` |

기존 공개 FolderState·업무 책갈피 MSI는 이번 작업에서 실제 내려받은 바이트의 지문을 계산해 GitHub 자산 digest·첨부 체크섬과 대조했습니다. MSI 테이블을 읽기 전용으로 확인했으며 설치를 실행하지 않았습니다.

| 제품 | ProductCode | PackageCode | UpgradeCode |
|---|---|---|---|
| FolderState 0.1.3 | `{988DE6FC-A5D8-4879-AAA5-9D6B06CAE661}` | `{B43EAB73-5744-44F8-B20E-77FC8818C789}` | `{71B69B50-56F6-4FDC-A225-26B88FA22D50}` |
| WorkBookmark 0.2.8 | `{CCF6B586-B804-EE43-6E8F-2FBAB720368B}` | `{A2B412BC-FA3C-41CA-B037-EEA299F2D846}` | `{BB5C5CA8-5BA0-4B01-875E-9E295690C711}` |

## 시험과 재사용 근거

- **Excel 새 실행 PASS:** 집중 소스 계약 16개, 저장 VBA 7개 모듈·RibbonX 일치, 실제 Excel 16.0 build 20430에서 UiProbe·상태 보존·기존 사용성 회귀, 정상 종료와 기존 RC13 설치/임시 접근 설정 보존. 처음 후보의 컴파일 FAIL은 유지하며 새 후보로 수정했습니다. 상세는 [0.2.1 실제 검증·게시 기록](../../tools/ExcelSmartListCompare/docs/STABLE_RELEASE_REPORT.md)을 따릅니다. 공개 자산 6개를 실제 다운로드해 포장 파일과 대조했고 PR #17의 Windows/Documentation CI는 SUCCESS입니다.
- **FolderState 기존 PASS 재사용:** 동일 소스/패키지의 엔진 47개·WPF 12개·MSI 구성 검사와 같은 공개 MSI의 Windows 11 비상승 일반 사용자 설치·repair·0.1.0→0.1.3 upgrade·제거·자료 보존. 실제 Explorer 메뉴/네 상태·초기화·Portable·기존 아이콘/외부 수정 보존 근거는 [수명주기 기록](folderstate-lifecycle-20260926.md)에 있습니다. RC1 소스부터 이번 작업 시작 main까지 관련 runtime·installer·assets·build diff가 없으므로 반복하지 않았습니다.
- **FolderState USER_CONFIRMED:** 사용자는 여러 PC에서 사용 중임을 확인했습니다. 환경별 원시 로그가 제공된 새 시험은 아니며 자동시험 수로 합산하지 않습니다.
- **업무 책갈피 기존 PASS 재사용:** 기존 0.2.8의 경고/오류 없는 빌드, 브라우저 관련 자동검사 34개, MSI/ZIP 구성·추출 검사 54개. runtime·installer·DB v5·설정·사용자 표시/크기/경로 계약을 변경하지 않았습니다. [BookMark 정식 전환 기록](https://github.com/prozac0401/BookMark/blob/main/docs/stable-release-20261005.md)을 참고하세요.
- **업무 책갈피 USER_CONFIRMED:** 사용자가 실제 Whale 저장·재열기의 정상 동작을 확인했습니다. 정확한 Windows/Whale build·통제 절차·원시 로그는 제공되지 않았으므로 모든 Whale 환경 PASS나 확장 Native Messaging PASS로 확대하지 않습니다. 2026-09-27 미검증 기록은 당시 이력으로 유지합니다.

## 유지하는 검증 경계

새 Excel EXE 전체 설치 수명주기·실제 Esc/팝업 새 시험은 NOT RUN이며 동일 설치 동작의 RC13 결과와 RC11 취소 근거를 재사용합니다. FolderState의 .NET 없는 새 PC·로그인/재부팅·접근성/배율·network/cloud·조직 보안은 기존 미검증입니다. 업무 책갈피의 최종 0.2.8 MSI 실제 설치 수명주기·IME/배율/여러 모니터·실제 창 전환 자동 저장/실패 초안·로그인/재부팅·회사 인증·Office 32비트/UNC/OneDrive의 미검증 범위도 유지합니다. 이전 버전의 설치/스티커 성공을 이번 버전의 새 실기로 합산하지 않습니다.

서명되지 않은 파일을 정식 릴리스 채널로 게시했다는 사실과 전체 상용 인수·회사별 도입 승인은 다릅니다. DVM 설치 실패 자동 복구는 별도 범위로 진행 중이며 이번 정식 전환의 PASS로 취급하지 않습니다. 사용자 설치·업무 파일·기존 계정의 설치 실패 주입은 이번 작업에서 수행하지 않았습니다. 원시 진단·사용자 경로·보안 상태는 로컬 artifacts에만 보관합니다.

## 게시 후 확인

두 Release 모두 draft·prerelease가 아님을 실제 GitHub 조회로 확인했습니다. 새 FolderState 정식 태그의 자산 3개를 별도 위치로 내려받아 기존 RC1 바이트·체크섬·자산 digest와 모두 대조했습니다. 업무 책갈피는 기존 자산 6개의 ID·크기·digest가 그대로이며 태그를 옮기거나 파일을 교체하지 않았습니다.

문서 수정 후 MkDocs strict build와 생성 사이트 링크·공개 범위 검사(19페이지·legacy redirect 2개·404), 두 저장소에서 추가한 상대 Markdown 링크 39개, git diff whitespace 검사는 PASS입니다. 이 문서 검사를 제품 runtime/설치 시험에 합산하지 않습니다.
