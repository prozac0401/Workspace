# 업무 책갈피 0.2.0 안내의 Pages 반영 · 2026-09-22

## 요청과 변경 범위

사용자 요청에 따라 현재 개발·배포 중인 Bookmark의 최신 기능과 사용 방법을 Workspace GitHub Pages에 반영합니다. [ADR-0008](../design/0008-bookmark-public-guide.md)에 공개 범위 확장을 기록했습니다.

- [업무 책갈피 설치·사용](../tools/bookmark/index.md) 한 페이지를 공개 목록과 메뉴에 추가했습니다. 홈페이지·지금 할 일 찾기·README에서도 연결합니다.
- WorkBookmark 0.2.0의 설치·단축키·프로그램별 저장 범위, 포스트잇 조작, 삭제 복원, 설정·백업·업데이트·제거·문제 해결을 안내합니다.
- 0.1.7에서 읽을 수 없는 데이터 갱신, 메모장의 본문 보관, 미서명과 실제 환경 검증 제한을 사용자 페이지에 요약했습니다.
- 공개 문서는 총 16개이며 기존 공개 자산 8개를 유지합니다. BookMark 개발 자료·원시 진단·업무 데이터·다운로드한 설치 파일은 Pages에 복사하지 않습니다.
- 제품 소스와 배포 파일은 바꾸지 않습니다. 기존 Excel R11 관련 작업 중 변경도 이 문서 게시에 포함하지 않습니다.

## 근거와 배포 파일 확인

BookMark 저장소의 `6e58aafb68a4ee2894768e8307d91d5a8a784b5e`를 기준으로 초기 `01_IMPLEMENTATION_SPEC.md`, 최신 `docs/user-manual.ko.md`, `docs/release-notes-v0.2.0.md`, `docs/compatibility.md`, `docs/windows-installer.ko.md`와 실제 UI 메뉴·설정·스티커·삭제 복원 구현을 대조했습니다. 초기 명세에서 후속 구현으로 바뀐 브라우저·Office 범위와 자동 실행 기본값은 최신 안내를 따릅니다.

[BookMark v0.2.0](https://github.com/prozac0401/BookMark/releases/tag/v0.2.0)은 2026-09-22 06:00:38 UTC에 공개되었으며 GitHub의 사전 릴리스 플래그는 false입니다. 이 표시는 상용 인수 승인이나 모든 환경의 검증 완료를 뜻하지 않습니다.

비인증 HTTP로 아래 자산의 응답 200을 확인하고 실제 다운로드 파일의 SHA-256을 공개 `SHA256SUMS.txt`와 대조했습니다.

| 파일 | 크기 (bytes) | SHA-256 |
|---|---:|---|
| `WorkBookmark-0.2.0-win-x64.msi` | 75,298,595 | `1f4e074b2891632280986dc7b7382369273186fbfd99e1e48544a7461e40c8da` |
| `WorkBookmark-0.2.0-win-x64.zip` | 115,006,319 | `352e3e88f4c6661b82f3349f5b886d2ed3b6c494911961615bffe91fdfe89c18` |
| `WorkBookmark-0.2.0-win-x64.validation.json` | 6,427 | `01501c0843e4c26075396b3fabe8022f64c32377f0f3b23c9c1e038ebcb70ada` |

MSI Authenticode 상태는 `NotSigned`입니다. 공개 패키지 검증 JSON은 구조 검사 54/54와 관리 이미지 추출 성공을 기록하며 실제 설치·제거·재부팅은 `NOT RUN`입니다. 다운로드 검증 파일은 로컬 전용 `artifacts/bookmark-pages-20260922`에 보관합니다.

## 문서 검증과 게시

| 확인 항목 | 실제 결과 |
|---|---|
| 최신 사용법 검토 | 별도 검토에서 매뉴얼·UI 구현과 중대한 차이 없음. 복원 전 메모장 닫기와 MSI 하위 버전 덮어쓰기 제한을 보완 |
| `python -m mkdocs build --strict` | 통과. 저장소의 `.tools/docs-venv` Python 사용 |
| `python scripts/check-site.py site` | 통과. 공개 16페이지 + 404, 공개 자산 8개, 검색·사이트맵 공개 범위와 로컬 링크 확인 |
| 생성 HTML의 내부 앵커 | 17개 HTML에서 472개 로컬 앵커 링크 통과 |
| Edge 브라우저 | 새 안내의 상단·스티커 조작 표 표시, 홈페이지의 새 링크를 눌러 이동, ‘스티커’ 검색 결과에 새 페이지 노출 확인 |
| `git diff --check` | 통과 |

브라우저 점검은 데스크톱 화면에서 수행했습니다. 모바일 화면과 별도 화면 배율의 검사는 하지 않았습니다.

## 원격 게시 결과

- 안내 소스 커밋 `e8319e461e7cd0cf9d68bc7cad4bc768a7a19a4f`를 `main`에 게시했습니다.
- [Documentation 실행 35702855027](https://github.com/prozac0401/Workspace/actions/runs/35702855027)의 strict 빌드·공개 범위 검사와 Pages 배포가 성공했습니다.
- [공개 업무 책갈피 안내](https://prozac0401.github.io/Workspace/tools/bookmark/)를 포함한 16개 공개 경로와 8개 자산에서 비인증 HTTP 200을 확인했습니다. 새 페이지의 0.2.0 표시, 스티커·삭제 복원·구버전 제한, MSI·ZIP 링크와 홈페이지·빠른 판단의 연결을 확인했습니다.
- 실제 공개 검색 인덱스와 사이트맵은 허용한 16개 경로와 일치했습니다. 새 배포 기록과 ADR의 사이트 주소는 HTTP 404입니다.
- 공개 이미지 7개는 로컬 빌드와 바이트 단위로 일치합니다. CSS는 Windows의 CRLF와 CI의 LF 차이만 있으며 줄바꿈을 정규화하면 일치합니다.
- Edge에서 실제 공개 주소를 열어 새 제목·버전·다운로드·스티커·최근 삭제 안내가 표시되는 것을 확인했습니다.

위 결과의 로컬 확인 자료는 `artifacts/bookmark-pages-20260922/public-check.json`에 남겼으며 사이트에는 포함하지 않습니다. 본 기록은 성공한 게시 결과를 추가하는 후속 문서 변경입니다.

## 범위와 한계

이번 작업은 문서 작성과 배포 파일 확인입니다. WorkBookmark를 설치하거나 사용자 책갈피를 읽고 바꾸지 않았습니다. 제품 릴리스에 기록된 자동 검사 529개를 이번 Workspace 작업에서 다시 실행한 것으로 표시하지 않습니다. Office·브라우저·회사 인증·다중 모니터·설치 수명주기의 실기 미확인 범위도 유지합니다.
