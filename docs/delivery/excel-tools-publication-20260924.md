# Excel 도구 릴리스와 Workspace 안내 게시 · 2026-09-24

사용자 요청: 선택범위 내보내기 GitHub 릴리스와 Workspace 도구 소개 게시, 기존 탐색기 연동 Excel 도구 소개 추가.

## 범위

선택범위 내보내기 0.1.0-rc.9의 이미 제작·시험한 x64/x86 설치기를 prerelease로 게시한다. 태그는 `excel-selection-export-v0.1.0-rc.9`이며 일반 최신 릴리스를 변경하지 않는다. File List to Excel은 별도 저장소의 이미 공개된 v1.1.0 목록·중복 찾기 기능만 소개한다. 제품 코드는 이번 게시 단계에서 변경하지 않는다.

[설계 결정](../design/0011-excel-tools-public-guides.md) · [실제 제품 평가](excel-selection-export-evaluation-20260924.md)

## 게시 전 확인

- 공개 문서 두 페이지, 홈·README·프로그램 메뉴·공개 허용 목록을 함께 갱신한다. 공개 18개 페이지와 기존 자산 8개를 유지한다.
- rc.9 설치 파일 2/2와 manifest 입력 13/13의 해시가 현재 소스와 일치한다. 제품 소스 19개 파일에는 바이너리·원시 로그가 없다.
- 릴리스 자산은 두 설치 EXE, SHA256SUMS.txt, build-manifest.json, 공개용 VALIDATION_SUMMARY.md로 제한한다. 진단·사용자 경로·시험 문서는 올리지 않는다.
- 동결된 README의 과거 공개 미포함 문구는 빌드 당시 기록이며 후속 게시 요청을 릴리스 설명에 명시한다.
- 기존 Excel 작업, 설치 상태, 명단 비교의 수정 사항과 별도 개발 중인 도구는 이번 게시에서 변경하지 않는다.

## 로컬 검증

- MkDocs strict 빌드 exit 0.
- scripts/check-site.py: 공개 18개 페이지 + 404, 검색·사이트맵 공개 범위, 제외 원본 자산 비노출, 로컬 링크 PASS.
- git diff --check: PASS.
- 게시 작업트리의 manifest 입력 13/13 해시 일치. 설치 EXE 2/2 체크섬 일치.

## 실제 게시 결과

이 문서를 작성한 준비 단계에서는 게시 전이다. strict 빌드·링크 검사, 독립 검토, GitHub Release 자산 해시, Pages Actions와 실제 URL 확인 결과는 게시 후 추가한다. 게시 자체로 Undo 손실·API 종료 잔존·설정 비교 실패 또는 미실행 설치 시험을 통과 처리하지 않는다.
