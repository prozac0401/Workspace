# 배포·검증 안내

- [DownloadVersionManager 후속 검증](download-version-manager-followup-20260930.md) — 완료 순서 보완, Host 82/확장 38, native lifecycle 15, 실제 Windows CI PASS; Windows 11 late 설치 실패와 browser 관문은 미완료

DownloadVersionManager 0.1.0은 공개 릴리스 전의 [평가 후보 기록](download-version-manager-evaluation-20260930.md)입니다. 단일 MSI 후보와 자동시험을 만들었으며 브라우저 스토어 배포·활성화와 실제 E2E는 별도 관문입니다. 기존 도구의 출시 판정을 변경하지 않습니다.

그림 복사·저장의 [0.2.0 보존 보완과 정식 릴리스 작업](image-020-release-20260927.md)에서 외부 호스트에서 같은 0.2.0 MSI의 전체 보존 시험 **32 PASS / 0 FAIL / 0 NOT RUN**을 확인했습니다. HKLM·HKCU 충돌 차단, 외부 수정 보존, 복구·업데이트·제거와 실패 롤백을 통과했고 합성 시험 등록을 정리하며 업무 자료 역할의 fixture는 보존했습니다. 기본 위치 최종 설치도 msiexec 0으로 PASS했으며 재시작 요구와 Explorer 강제 재시작은 없었습니다. 기본 설치본의 실제 탐색기 복사·저장 대표 확인도 PASS했으며, 저장 후 최종 행 선택은 미확인입니다. [0.2.0 정식 Release](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.0) 게시와 공개 MSI·체크섬 검증을 완료했습니다. Pages 안내 배포와 실제 공개 URL·검색·사이트맵 검증도 완료했습니다.

현재 설치 안내와 버전별 검증 결과를 구분합니다. GitHub Release의 태그와 파일 해시를 기준으로 확인하세요.

## 현재 버전

| 도구 | 설치·사용 안내 | 배포와 검증 기록 |
|---|---|---|
| FolderState 0.1.3 | [설치·사용·문제 해결](../tools/folderstate/index.md) | [정식 전환](stable-tools-release-20261005.md) · [공개 MSI 수명주기](folderstate-lifecycle-20260926.md) · [2026-09-20 게시](releases-20260920.md) · [사용성 시험](folderstate-usability-20260919.md) |
| Excel 명단 비교 0.2.1 | [설치·사용](../tools/excel-list-compare/index.md) | [0.2.1 정식 배포·실제 Excel 검증](../../tools/ExcelSmartListCompare/docs/STABLE_RELEASE_REPORT.md) |
| 선택범위 내보내기 0.1.0-rc.10 평가판 | [설치·사용](../tools/excel-selection-export/index.md) | [rc.10 Undo 검증](excel-selection-export-undo-20260926.md) · [후속 게시](backlog-releases-20260927.md) |
| File List to Excel 1.2.0 | [설치·사용](../tools/file-list-to-excel/index.md) | [원본 릴리스](https://github.com/prozac0401/File-List-To-Excel/releases/tag/v1.2.0) · [Workspace 소개 게시](excel-tools-publication-20260924.md) |
| 보이는 칸 붙여넣기 0.1.1 | [설치·사용](../tools/visible-cells-paste/index.md) | [설치·검증](../../tools/VisibleCellsPaste/docs/install-security.md) · [단일 EXE 릴리스](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.1.1-setup.1) |
| 업무 책갈피 0.2.8 | [설치·사용](../tools/bookmark/index.md) | [정식 전환](stable-tools-release-20261005.md) · [0.2.8 안내 반영](bookmark-028-publication-20260927.md) · [이전 수명주기](bookmark-lifecycle-20260927.md) · [BookMark 릴리스](https://github.com/prozac0401/BookMark/releases/tag/v0.2.8) |
| 그림 복사·저장 0.2.0 | [설치·사용 안내](../tools/image-copy-save/guide.md) | [정식 Release](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.0) · [보존·설치·게시 기록](image-020-release-20260927.md) |

현재 안내하는 설치 파일은 서명되지 않았습니다. FolderState 0.1.3·Excel 명단 비교 0.2.1·업무 책갈피 0.2.8은 사용자 요청에 따라 정식 릴리스 채널로 게시했습니다. FolderState와 업무 책갈피는 기존 바이너리를 그대로 유지합니다. 같은 FolderState MSI의 실제 설치·복구·업데이트·제거와 자료 보존 기록, 업무 책갈피의 기존 브라우저 34개·패키지 54개 검사 및 사용자 Whale 저장·재열기 확인을 구분합니다. Excel 0.2.1은 수정한 저장 후보에서 실제 회귀·비교·설정·복구 검사를 통과했습니다. [최신 배포 기록](stable-tools-release-20261005.md)에 재사용한 근거와 미검증 환경을 남깁니다. 선택범위 내보내기는 전체 인수 미완료인 평가판이며 알려진 실패와 미실행 시험을 유지합니다. File List to Excel은 별도 저장소의 v1.2.0을 안내합니다. 정식 채널 게시와 코드 서명·상용 인수·회사별 도입 승인은 구분합니다.

[순차 처리 백로그](WORKSPACE_Tool_Backlog_20260926.md)에서 로컬 후보와 공개 버전의 차이·남은 작업을 확인합니다.

공개 선택범위 내보내기 rc.10은 [Undo 수정](excel-selection-export-undo-20260926.md)과 [종료 재검증](excel-selection-export-lifetime-20260927.md)·[설치 수명주기](excel-selection-export-installer-20260927.md)를 별도로 기록합니다. 검증한 동일 파일을 평가판으로 게시했으며 [게시 결과](backlog-releases-20260927.md)를 따릅니다.

## 개발·게시 절차

- [FolderState 빌드와 패키지 검사](build.md)
- [GitHub Pages 공개 범위와 검증](pages.md)
- [상용 배포 품질 기준](quality.md)
- [변경 이력](changelog.md) · [누적 검증 기록](verification.md)

## 이전 기록

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
