# FolderState와 Excel 도구 · 별도 릴리즈 기록

날짜: 2026-09-14 · 상태: FolderState 평가용 후보 검증 통과 / Excel 빌드 차단

사용자 요청에 따라 같은 Workspace 저장소에서 도구별 소스·패키지·버전을 분리한다. 회사 정책 승인이나 상용 정식판 승인을 의미하지 않는다. 현 PC는 Windows 11 x64이며 일반 사용자로 실행했다.

## FolderState 0.1.0

현재 원격 소스 `e9e20e3efc15c042949721bdee8db8e835d70749`의 FolderState 엔진·WPF·설치 정의를 변경하지 않고 `scripts/build.ps1 -Version 0.1.0`으로 다시 빌드했다.

| 실제 검증 | 결과 |
|---|---|
| 엔진/파일시스템 통합 테스트 | 27/27 PASS |
| WPF smoke renderer | 레이아웃과 상태 아이콘 PASS, 빌드 경고·오류 0 |
| 자체 포함 MSI 빌드 | PASS |
| verify-msi.ps1 | 사용자별 설치, HKCU만 사용, 메뉴 명령 6개, 파일 414개 |
| 설치 전 확인 | 관련 MSI 제품 0개, FolderState 메뉴·설정 없음 |
| 실제 MSI 설치 | 종료 0 |
| 설치본 실행 | CLI 실행·상태 기록·메뉴 등록 PASS |
| 실제 MSI 복구 | 종료 0, 시험 중 제거한 제품 아이콘 복원 PASS |
| 실제 MSI 제거 | 종료 0, 프로그램·메뉴 제거 PASS |
| 합성 업무 파일과 상태정보 | 제거 후 모두 보존 PASS |
| 실제 화면 클릭·새 설치 화면 캡처 | BLOCKED_ENV — Windows 잠금 |

이번 설치 시험은 `scripts/test-installer.ps1`의 12개 결과가 모두 PASS였다. 전용 artifacts 설치 폴더와 합성 자료만 사용했다. 기존 설치가 없는 것을 확인한 뒤 실행했고 종료 상태도 미설치다. 이번에 상위 버전 업그레이드는 다시 실행하지 않았다.

배포 파일: `FolderState-0.1.0-win-x64.msi`.

SHA-256: `b96eb391ce3bbb3fb8a1ea2d025690cc9617d299a87064e8c272f02529f8fc67`.

서명: NotSigned. Windows 11 x64 한 PC에서의 위 검증만 확인했다. 모든 Explorer 화면·회사 보안 환경·SMB·동기화 폴더·다른 Windows 버전의 정상 동작을 보장하지 않는다. 공개 릴리즈는 prerelease/평가용으로 구분한다.

## Excel Smart List Compare 0.2.0

수정 소스를 `tools/ExcelSmartListCompare/`에 별도 포함했다. 한국어 Windows의 UTF-8 소스 읽기와 `.cmd` 종료 코드 유실을 수정하고 Windows 실행기·합성 자료 생성기를 포함한다. VBA 본체의 실제 동작은 아직 확인하지 못했다.

이번 재확인에서도 실제 새 Excel 인스턴스는 생성되었으나 VBA 프로젝트 접근은 차단되어 Preflight 종료 코드 5였다. Excel 버전은 16.0.20326.20132, 실제 EXCEL.EXE는 x64이다. 원래 매크로 보안, 신뢰 위치, 타 추가 기능 설정을 변경하지 않았다.

지난 단계의 실제 결과는 [Excel Windows E2E 보고서](../../tools/ExcelSmartListCompare/docs/WINDOWS_E2E_REPORT.md)에 있다. Python 53개와 설치 안전장치 10개 통과는 제품 비교 기능이나 성공 설치의 증거가 아니다.

설치→자동 로드→사용→재시작→재설치→제거 및 화면 캡처 퀵가이드는 **BLOCKED_POLICY / BLOCKED_ENV**다. 최종 XLAM이 없으므로 Excel은 소스 후보만 준비하며, 설치 가능한 제품의 공개 릴리즈로 게시하지 않는다. 별도 Excel draft에 포함하더라도 이는 검토용 소스다.

## 공개 자료와 로컬 자료

MSI, 해시, 사용자 안내, 식별자가 없는 검증 요약만 공개한다. 원시 MSI 로그, 계정 SID·사용자 경로, Excel 초기 레지스트리 snapshot, 실제 사용자 문서는 릴리즈 자산에 포함하지 않는다. 시험 fixture와 로그는 로컬 `artifacts`에 보존한다. 퀵가이드에 렌더링 이미지를 쓰는 경우 실제 캡처와 명확히 구분한다.

Excel의 빌드 접근과 화면 잠금 문제가 해결된 뒤 같은 최종 XLAM으로 기능·설치 수명주기를 검증하고 해시를 대조해야 한다. 결과가 없는 절차를 PASS로 표시하거나 두 도구 모두 정상 동작한다고 일괄 판정하지 않는다.
