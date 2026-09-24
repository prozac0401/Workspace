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

2026-09-24 게시와 공개 응답 확인을 완료했다. 게시 자체로 Undo 손실·API 종료 잔존·설정 비교 실패 또는 미실행 설치 시험을 통과 처리하지 않는다.

| 항목 | 실제 결과 |
|---|---|
| 검토·병합 | [PR #2](https://github.com/prozac0401/Workspace/pull/2) 병합. 공개 안내·검증 표현과 개인정보·원본 해시를 두 독립 검토에서 확인했다. 지적된 다운로드 전 제한 배치와 x86 파일명을 수정했다. |
| 릴리스 소스 | 태그 `excel-selection-export-v0.1.0-rc.9` → `f17bea7278f87c6a642c7555a0a5472f3308c658`. main 병합 커밋 `5533443464daebfe452f46b53f7ee7f2ae9e8ef5`. Git에 저장된 입력 13개도 manifest 해시와 일치. |
| GitHub 릴리스 | [0.1.0-rc.9 평가판](https://github.com/prozac0401/Workspace/releases/tag/excel-selection-export-v0.1.0-rc.9) 공개. draft=false, prerelease=true, latest=false로 게시. 공개 시간 2026-09-24 07:21:38 UTC. |
| PR 문서 검사 | [Documentation](https://github.com/prozac0401/Workspace/actions/runs/35968894581) build 성공. PR에서는 배포를 실행하지 않는 기존 설정에 따라 deploy 생략. |
| PR Windows 검사 | [Windows build and MSI](https://github.com/prozac0401/Workspace/actions/runs/35968894530) 성공. 기존 FolderState 빌드·MSI 검사이며 선택범위 내보내기의 추가 실기 시험으로 계산하지 않음. |
| main Pages 배포 | [Documentation](https://github.com/prozac0401/Workspace/actions/runs/35969183963) strict build·공개 범위 검사·deploy 모두 성공. |
| 실제 사이트 응답 | [홈](https://prozac0401.github.io/Workspace/), [선택범위 내보내기](https://prozac0401.github.io/Workspace/tools/excel-selection-export/), [File List to Excel](https://prozac0401.github.io/Workspace/tools/file-list-to-excel/) 모두 HTTP 200. 홈의 두 소개 및 각 페이지의 버전·기능·다운로드·제한을 확인. |
| 검색·사이트맵 | 공개 search_index.json·sitemap.xml HTTP 200, 두 새 경로를 포함해 각각 정확히 공개 18개 경로. |
| 제외 문서 | 선택범위 원문 명세와 이번 배포 기록의 Pages 주소 HTTP 404 확인. Git 저장소의 개발 원본은 보존. |

## 공개 자산 재검증

공개 다운로드 URL에서 다섯 파일을 다시 받아 로컬 원본과 크기·SHA-256을 대조했다. **5/5 HTTP 200·해시 일치**.

| 파일 | 바이트 | SHA-256 |
|---|---:|---|
| ExcelSelectionExport-0.1.0-rc.9-x64-Setup.exe | 2,134,431 | `f4a26afcdae580e486236070cd458d32f5fa3a8bc5f972ceadf7a45a6ac5baa7` |
| ExcelSelectionExport-0.1.0-rc.9-x86-Setup.exe | 2,134,510 | `46cb481f7c52a0a685ca7973135baa0e1a68706156a9f9bc7e73d2d5fbb26869` |
| SHA256SUMS.txt | 226 | `973c66b080a9e84b990623e383d2cb79485d1f4c1268c5606e1e0b02a2195f95` |
| build-manifest.json | 3,906 | `f82dcdc1f7ff9e4e1bd4a5b9d7bca3d5640fe8653f9461a9c3cd25069530d86b` |
| VALIDATION_SUMMARY.md | 5,703 | `16752cfc3de42d96e9ed5ae8b2642aecf77a933a0f2f96f4cb6e5eb057315683` |

File List to Excel은 원본 v1.1.0 저장소·릴리스·MSI·체크섬 링크 4개 HTTP 200을 확인했으며, 이번 작업에서 그 제품을 재빌드·재설치·재게시하지 않았다. 미게시 v1.2 파일 복사 기능과 Excel 통합문서 병합을 공개 기능으로 추가하지 않았다.

## 남은 제약

제품의 미실행 시험과 실패는 [평가 기록](excel-selection-export-evaluation-20260924.md) 그대로다. 기존에 사용 중인 다른 Excel 작업과 제품 설치 상태를 이번 게시 단계에서 조작하지 않았다. 코드 서명·정식 인수·회사 배포 승인으로 분류하지 않는다. 이후 바이너리가 바뀌면 새 버전과 해당 버전의 시험 기록을 만든다.
