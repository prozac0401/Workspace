# 배포·검증 안내

현재 설치 안내와 버전별 검증 결과를 구분합니다. GitHub Release의 태그와 파일 해시를 기준으로 확인하세요.

## 현재 버전

| 도구 | 설치·사용 안내 | 배포와 검증 기록 |
|---|---|---|
| FolderState 0.1.3 RC1 | [설치](../tools/folderstate/installation.md) · [사용](../tools/folderstate/index.md) | [공개 MSI 수명주기](folderstate-lifecycle-20260926.md) · [2026-09-20 게시](releases-20260920.md) · [사용성 시험](folderstate-usability-20260919.md) |
| Excel 명단 비교 0.2.0 R12 | [설치·사용](../tools/excel-list-compare/index.md) | [R12 제작·배포 기록](../../tools/ExcelSmartListCompare/docs/RC12_RELEASE_REPORT.md) · [테스트 미실행 결정](../../tools/ExcelSmartListCompare/docs/ADR-0020-R12-wording-release.md) |
| 선택범위 내보내기 0.1.0-rc.9 평가판 | [설치·사용](../tools/excel-selection-export/index.md) | [실제 평가 결과](excel-selection-export-evaluation-20260924.md) · [GitHub 릴리스·Pages 게시](excel-tools-publication-20260924.md) |
| File List to Excel 1.2.0 | [설치·사용](../tools/file-list-to-excel/index.md) | [원본 릴리스](https://github.com/prozac0401/File-List-To-Excel/releases/tag/v1.2.0) · [Workspace 소개 게시](excel-tools-publication-20260924.md) |
| 보이는 칸 붙여넣기 0.1.1 | [설치·사용](../tools/visible-cells-paste/index.md) | [설치·검증](../../tools/VisibleCellsPaste/docs/install-security.md) · [공개 릴리스](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.1.1) |
| 업무 책갈피 0.2.3 | [설치·사용](../tools/bookmark/index.md) | [0.2.3 수명주기](bookmark-lifecycle-20260927.md) · [0.2.3 배포·Pages 반영](bookmark-023-publication-20260922.md) · [BookMark 릴리스](https://github.com/prozac0401/BookMark/releases/tag/v0.2.3) |

현재 안내하는 설치 파일은 서명되지 않았습니다. 선택범위 내보내기는 전체 인수 미완료인 평가판이며 알려진 실패와 미실행 시험은 실제 평가 기록에 남깁니다. File List to Excel은 별도 저장소의 v1.2.0과 선택형 Excel 파일 복사를 안내합니다. FolderState는 사전 릴리스이며, Excel R12는 사용자 요청으로 기능 테스트를 생략한 문구 교정 배포입니다. 업무 책갈피 0.2.3은 BookMark 저장소에서 배포하며 실제 설치 수명주기·회사 환경·한글 IME·여러 모니터의 전체 실기 검증은 미완료입니다. 제품의 자동검사·패키지 확인과 Workspace 문서 검증은 위 배포 기록에서 구분합니다. 파일 게시와 상용 인수 승인을 구분합니다.

[순차 처리 백로그](WORKSPACE_Tool_Backlog_20260926.md)에서 로컬 후보와 공개 버전의 차이·남은 작업을 확인합니다.

로컬 선택범위 내보내기 rc.10은 [Undo 수정](excel-selection-export-undo-20260926.md)과 [종료 재검증](excel-selection-export-lifetime-20260927.md)을 별도로 기록합니다. 공개 rc.9 다운로드를 바꾼 것은 아닙니다.

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
