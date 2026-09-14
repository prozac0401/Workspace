# FolderState와 Excel 도구 · 별도 릴리즈 기록

날짜: 2026-09-14 · 상태: FolderState 평가용 릴리즈 게시 완료 / Excel 빌드 차단·draft 보관

사용자 요청에 따라 같은 Workspace 저장소에서 도구별 소스·패키지·버전을 분리한다. 회사 정책 승인이나 상용 정식판 승인을 의미하지 않는다. 현 PC는 Windows 11 x64이며 일반 사용자로 실행했다.

## FolderState 0.1.0

기준 소스 `e9e20e3efc15c042949721bdee8db8e835d70749`의 FolderState 엔진·WPF·설치 정의를 변경하지 않고 `scripts/build.ps1 -Version 0.1.0`으로 다시 빌드했다. 도구별 소스와 검증 안내를 반영한 릴리즈 커밋은 `98a9f7c77ed18461b551914713b2b9287486bf80`이다.

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

서명: NotSigned. Windows 11 x64 한 PC에서의 위 검증만 확인했다. 모든 Explorer 화면·회사 보안 환경·SMB·동기화 폴더·다른 Windows 버전의 정상 동작을 보장하지 않는다.

[FolderState 0.1.0 RC1](https://github.com/prozac0401/Workspace/releases/tag/folderstate-v0.1.0-rc.1)을 **prerelease/평가용**으로 게시했다. MSI와 해시, [오프라인 퀵가이드 HTML](https://github.com/prozac0401/Workspace/releases/download/folderstate-v0.1.0-rc.1/FolderState-0.1.0-QuickGuide.html), 검증 요약 JSON 및 안내·검증 파일 해시 등 자산 5개를 포함한다. GitHub가 반환한 각 자산의 SHA-256이 로컬 검증본과 모두 일치했다. 퀵가이드는 현재 렌더링 이미지만 포함하며, 요청받은 실제 설치·사용 화면 캡처는 미완료다.

같은 릴리즈 커밋의 [Windows 빌드 CI](https://github.com/prozac0401/Workspace/actions/runs/34812270842)와 [문서 CI](https://github.com/prozac0401/Workspace/actions/runs/34812270804)도 성공했다. CI 성공은 위 로컬 MSI 설치 시험이나 Excel 기능 검증을 대신하지 않는다.

## Excel Smart List Compare 0.2.0

수정 소스를 `tools/ExcelSmartListCompare/`에 별도 포함했다. 한국어 Windows의 UTF-8 소스 읽기와 `.cmd` 종료 코드 유실을 수정하고 Windows 실행기·합성 자료 생성기를 포함한다. VBA 본체의 실제 동작은 아직 확인하지 못했다.

이번 재확인에서도 실제 새 Excel 인스턴스는 생성되었으나 VBA 프로젝트 접근은 차단되어 Preflight 종료 코드 5였다. Excel 버전은 16.0.20326.20132, 실제 EXCEL.EXE는 x64이다. 원래 매크로 보안, 신뢰 위치, 타 추가 기능 설정을 변경하지 않았다.

지난 단계의 실제 결과는 [Excel Windows E2E 보고서](../../tools/ExcelSmartListCompare/docs/WINDOWS_E2E_REPORT.md)에 있다. Python 53개와 설치 안전장치 10개 통과는 제품 비교 기능이나 성공 설치의 증거가 아니다.

설치→자동 로드→사용→재시작→재설치→제거 및 화면 캡처 퀵가이드는 **BLOCKED_POLICY / BLOCKED_ENV**다. 최종 XLAM이 없으므로 설치 가능한 제품의 공개 릴리즈로 게시하지 않았다. 별도 [Excel 릴리즈 draft](https://github.com/prozac0401/Workspace/releases/tag/untagged-9920a6f2bbe73f0fb8e1)에 검토용 소스 후보 ZIP과 해시만 업로드했다. 이 draft는 저장소 권한이 있는 사용자만 볼 수 있으며 공개 제품 릴리즈가 아니다.

최초 소스 후보 ZIP의 SHA-256은 `f6678ea66818252ea014e35be5b6f7deb33b5331dcf4dff15d8590beb8bb8bde`이며 업로드 당시 GitHub 자산 digest와 일치했다. 유지보수 소스는 `main`의 `tools/ExcelSmartListCompare/`에서 확인할 수 있다.

사용자가 AccessVBOM 한 항목의 임시 변경·원복을 승인한 뒤 실제 재시도했다. Excel 시작 후에도 값이 1이고 실제 계정·세션이 일치했지만, Excel 16.0.20326.20144 x64는 `0x800A03EC`로 VBA 접근을 거부했다. 임시 적용한 값은 5회 모두 즉시 원복했다. 설치기와 사전 점검에서 원래 COM 오류가 누락되는 문제를 수정해 실제 Excel로 재검증했다. [승인 후 재검증 보고서](../../tools/ExcelSmartListCompare/docs/WINDOWS_APPROVAL_RETEST_REPORT.md)에 차단·원복·정리 내역을 구분했다. Windows 화면은 여전히 잠겨 있으며 잠금 해제를 요청한 상태다.

후속 소스 후보는 `ExcelSmartListCompare_v0.2_SourceCandidate_BLOCKED_POLICY_20260914_r2.zip`이다. SHA-256은 `ad2ee868751e20340a851a7db18050cf433a2cfca9783525743281abf1f2107d`다. 78개 파일의 ZIP CRC 및 내부 해시 목록을 검증했고, XLAM과 원시 레지스트리·계정 로그는 포함하지 않았다. 이 후보 역시 설치 가능한 Release를 대신하지 않는다.

## 공개 자료와 로컬 자료

MSI, 해시, 사용자 안내, 식별자가 없는 검증 요약만 공개한다. 원시 MSI 로그, 계정 SID·사용자 경로, Excel 초기 레지스트리 snapshot, 실제 사용자 문서는 릴리즈 자산에 포함하지 않는다. 시험 fixture와 로그는 로컬 `artifacts`에 보존한다. 퀵가이드에 렌더링 이미지를 쓰는 경우 실제 캡처와 명확히 구분한다.

Excel의 빌드 접근과 화면 잠금 문제가 해결된 뒤 같은 최종 XLAM으로 기능·설치 수명주기를 검증하고 해시를 대조해야 한다. 결과가 없는 절차를 PASS로 표시하거나 두 도구 모두 정상 동작한다고 일괄 판정하지 않는다.
