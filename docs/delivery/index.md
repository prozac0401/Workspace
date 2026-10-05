# 배포·검증 안내

현재 공개된 설치 파일과 당시 확인 기록을 구분해 안내합니다. 아래 표는 **2026-10-05에 GitHub의 배포 페이지를 확인한 결과**입니다.

## 현재 공개 버전

| 도구와 버전 | 배포 상태 | 설치·사용 안내 | 배포와 확인 기록 |
|---|---|---|---|
| FolderState 0.1.3 | 일반 배포 | [설치·사용·문제 해결](../tools/folderstate/index.md) | [배포 페이지](https://github.com/prozac0401/Workspace/releases/tag/folderstate-v0.1.3) · [일반 배포 전환](stable-tools-release-20261005.md) · [설치·복구·제거 확인](folderstate-lifecycle-20260926.md) |
| Excel 명단 비교 0.2.1 | 일반 배포 | [설치·사용](../tools/excel-list-compare/index.md) | [배포 페이지](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.1) · [0.2.1 제작·확인 기록](../../tools/ExcelSmartListCompare/docs/STABLE_RELEASE_REPORT.md) |
| 선택범위 내보내기 0.1.0-rc.11 | 평가판 | [설치·사용](../tools/excel-selection-export/index.md) | [배포 페이지](https://github.com/prozac0401/Workspace/releases/tag/excel-selection-export-v0.1.0-rc.11) · [rc.11 확인 기록](excel-selection-export-rc11-20261003.md) |
| 파일 목록을 Excel로 1.2.0 | 일반 배포 | [설치·사용](../tools/file-list-to-excel/index.md) | [별도 저장소의 배포 페이지](https://github.com/prozac0401/File-List-To-Excel/releases/tag/v1.2.0) · [시험용 폴더의 실제 확인](filelist-synthetic-20260927.md) |
| 보이는 칸 붙여넣기 0.1.2 | 일반 배포 | [설치·사용](../tools/visible-cells-paste/index.md) | [배포 페이지](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.1.2) · [0.1.2 확인 기록](visible-cells-paste-012-20261003.md) |
| 업무 책갈피 0.2.8 | 일반 배포 | [설치·사용](../tools/bookmark/index.md) | [별도 저장소의 배포 페이지](https://github.com/prozac0401/BookMark/releases/tag/v0.2.8) · [일반 배포 전환](stable-tools-release-20261005.md) · [0.2.8 안내 반영](bookmark-028-publication-20260927.md) |
| 그림 복사·저장 0.2.1 | 일반 배포 | [설치·사용](../tools/image-copy-save/guide.md) | [배포 페이지](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.1) · [0.2.1 제작·확인·게시 기록](image-copy-save-021-20261003.md) |
| 내려받은 파일 관리 0.2.0 | 평가판 | [설치·사용](../tools/download-version-manager/index.md) | [배포 페이지](https://github.com/prozac0401/Workspace/releases/tag/download-version-manager-v0.2.0) · [0.2.0 설치·파일 보존·게시 기록](download-version-manager-watcher-release-20261004.md) |

현재 설치 파일에는 전자 서명이 없습니다. **일반 배포**는 GitHub에서 평가판 표시 없이 제공한다는 뜻입니다. 모든 환경에서의 확인이나 회사별 사용 승인을 뜻하지 않습니다. 두 평가판의 알려진 문제와 아직 확인하지 않은 환경은 내려받기 전에 설치 안내에서 읽으세요.

FolderState 0.1.3과 업무 책갈피 0.2.8은 기존 설치 파일을 그대로 일반 배포로 전환했습니다. 이 전환을 위해 새 파일을 만들거나 설치 시험을 다시 실행하지 않았습니다. Excel 명단 비교 0.2.1은 바뀐 파일에서 비교·설정·복구와 정상 종료를 확인했습니다. [2026-10-05 배포 기록](stable-tools-release-20261005.md)은 새 확인, 재사용한 근거, 사용자 확인과 남은 한계를 구분합니다.

[순차 처리 백로그](WORKSPACE_Tool_Backlog_20260926.md)에서 로컬 후보와 공개 버전의 차이·남은 작업을 확인합니다.

## 개발·게시 절차

- [FolderState 빌드와 패키지 검사](build.md)
- [GitHub Pages 공개 범위와 검증](pages.md)
- [상용 배포 품질 기준](quality.md)
- [변경 이력](changelog.md) · [누적 검증 기록](verification.md)

## 이전 기록

아래는 각 날짜에 사용한 파일의 확인 기록입니다. 현재 버전의 새 시험 결과로 합산하지 않습니다. 당시 실패와 미실행 항목도 그대로 보존합니다.

- [DownloadVersionManager 후속 검증](download-version-manager-followup-20260930.md) — 완료 순서 보완, Host 82/확장 38, native lifecycle 15, 실제 Windows CI PASS; Windows 11 late 설치 실패와 browser 관문은 미완료

DownloadVersionManager 0.1.0은 공개 릴리스 전의 [평가 후보 기록](download-version-manager-evaluation-20260930.md)입니다. 단일 MSI 후보와 자동시험을 만들었으며 브라우저 스토어 배포·활성화와 실제 E2E는 별도 관문입니다. 기존 도구의 출시 판정을 변경하지 않습니다.

그림 복사·저장의 [0.2.0 보존 보완과 정식 릴리스 작업](image-020-release-20260927.md)에서 외부 호스트에서 같은 0.2.0 MSI의 전체 보존 시험 **32 PASS / 0 FAIL / 0 NOT RUN**을 확인했습니다. HKLM·HKCU 충돌 차단, 외부 수정 보존, 복구·업데이트·제거와 실패 롤백을 통과했고 합성 시험 등록을 정리하며 업무 자료 역할의 fixture는 보존했습니다. 기본 위치 최종 설치도 msiexec 0으로 PASS했으며 재시작 요구와 Explorer 강제 재시작은 없었습니다. 기본 설치본의 실제 탐색기 복사·저장 대표 확인도 PASS했으며, 저장 후 최종 행 선택은 미확인입니다. [0.2.0 정식 Release](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.0) 게시와 공개 MSI·체크섬 검증을 완료했습니다. Pages 안내 배포와 실제 공개 URL·검색·사이트맵 검증도 완료했습니다.

공개 선택범위 내보내기 rc.10은 [Undo 수정](excel-selection-export-undo-20260926.md)과 [종료 재검증](excel-selection-export-lifetime-20260927.md)·[설치 수명주기](excel-selection-export-installer-20260927.md)를 별도로 기록합니다. 검증한 동일 파일을 평가판으로 게시했으며 [게시 결과](backlog-releases-20260927.md)를 따릅니다.

- [업무 책갈피 0.2.2 배포·Pages 반영](bookmark-022-publication-20260922.md)
- [업무 책갈피 0.2.1 배포·Pages 반영](bookmark-021-publication-20260922.md)
- [Excel R11 게시·검증](../../tools/ExcelSmartListCompare/docs/RC11_TEST_REPORT.md)
- [Excel RC10 게시](../../tools/ExcelSmartListCompare/docs/RC10_PUBLICATION_20260920.md) · [전체 흐름 판정](../../tools/ExcelSmartListCompare/docs/RC10_END_TO_END_REPORT.md)
- [2026-09-17 도구 다운로드·문서 통합](tools-release-20260917.md)
- [2026-09-14 설치·실행 검증](tools-release-20260914.md)
- [FolderState 0.1.0~0.1.1 화면 기록](../tools/folderstate/quick-guide.md)
- [Excel RC9 게시·검증](../../tools/ExcelSmartListCompare/docs/RC9_APPROVED_RETEST_20260917.md)

과거 기록은 당시 파일의 증거입니다. 현재 버전의 사용법이나 최신 시험 결과로 해석하지 않습니다. 초기 Excel 지시와 소스 압축본은 [원본 보존 폴더](../../tools/ExcelSmartListCompare/archive/README.md)에 있습니다.

[보이는 칸 붙여넣기 단일 EXE](visible-cells-paste-single-20260927.md)는 실제 Excel 후속 확인을 마친 동일 파일을 게시했습니다. [항목별 릴리스 기록](backlog-releases-20260927.md)에서 설치 자산과 Pages 결과를 확인합니다. ImageCopySave의 이전 MSIX 초안은 과거 설치 신뢰 오류 기록입니다. 이전 무서명 관리자 MSI 0.1.1은 [설치·대표 클래식 메뉴 검증](image-classic-msi-20260927.md)을 완료한 범위가 있습니다. [당시 배포 준비 판정](image-release-readiness-20260927.md) 이후 보존 보호를 보완했으며, 0.2.0의 실제 인수와 정식 Release 게시 결과는 [후속 작업 기록](image-020-release-20260927.md)을 따릅니다. 공개 MSI 다운로드와 Pages 설치·사용 안내를 제공하며 실제 공개 검증을 완료했습니다.
