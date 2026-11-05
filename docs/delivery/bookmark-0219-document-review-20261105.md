# 업무 책갈피 0.2.19 설치·사용 안내 갱신

2026-11-05 · [Workspace PR #36](https://github.com/prozac0401/Workspace/pull/36)

## 요청과 변경 범위

2026-11-04 22:36(KST) 공개된 0.2.19 정식판에 맞춰 기존 PR의 설치·사용 안내, 배포 표, 다운로드 그림을 갱신한다. MSI·ZIP·체크섬과 DB v8 보존 안내를 대조하고, 태그의 구현으로 스티커 묶기·Alt 자유 이동·폴더 펼침 순서·목록 드래그를 확인한다. 완료 기준은 문서 strict 빌드·링크 검사, 기존 PR 병합, 공개 Pages 확인이다. [0.2.18 검증 기록](bookmark-0218-document-review-20261103.md)은 당시 이력으로 보존한다.

## 제품 릴리스 기록

[정식 릴리스](https://github.com/prozac0401/BookMark/releases/tag/v0.2.19)와 [태그의 사용자 매뉴얼](https://github.com/prozac0401/BookMark/blob/v0.2.19/docs/user-manual.ko.md), [실사용 기록](https://github.com/prozac0401/BookMark/blob/main/docs/evidence/acceptance-0.2.19-2026-11-04/README.md)을 확인했다. 태그 소스는 `557000dbe7daf8b97b8a0b5bf5c0d5f288771c93`이다.

- 제품 배포 기록에는 자동검사 1,142개와 MSI 검사 54개 통과, 관리 추출 파일의 SHA-256 대조, 배포 파일 6개의 서버 지문 일치가 남아 있다. 일반 드래그 묶기, 목록 스크롤, 한글 메모와 폴더 관계 보존 등은 실사용 기록에 검증 방식과 후보별 범위가 구분돼 있다.
- MSI 실제 설치·업데이트·제거·재로그인 전주기, 혼합 배율 다중 모니터 이동, Office·탐색기 50회 실기 행렬은 릴리스의 완료 범위 밖이다. 관리 추출과 실제 설치는 별도 검증이다. 패키지는 미서명이다.
- IPC 최초 요청 1회가 약 3.05초로 제한 시간을 넘겼으며 재측정을 포함한 조사 결과는 11/12였다. 릴리스의 배포용 worker 합성 응답 6/6과 별개로 기록한다.

## Workspace 문서 확인

- `StickerManager`에서 강조 대상의 놓기 시점 재확인, Alt의 자석·묶기 건너뛰기, 화면에 보이는 최상위 폴더 묶음의 펼침 순서를 확인했다. `RecentForm`에서 드래그 중 목록 갱신 보류, 종료 후 갱신, 가장자리 대기 300ms와 이후 120ms 간격 스크롤을 확인했다.
- 공개 `SHA256SUMS.txt`의 본문 지문과 MSI·ZIP 등 나머지 다섯 배포 자산의 게시 지문을 GitHub Release API의 digest와 대조했다. 설치 파일 전체의 재해시와 제품 자동검사·설치 실기는 이번 문서 작업 범위 밖이다.
- 다운로드 그림 JSON·가로 SVG·모바일 SVG·본문 대체 텍스트에 동일한 버전을 사용한다. 실제 공개 반영 결과는 PR의 검증 기록에서 확인한다.
- MkDocs 1.6.1 strict 빌드와 `scripts/check-site.py site`를 통과했다. 공개 22페이지·이전 주소 2개·404, 검색·사이트맵·공개 범위·로컬 링크·자산을 확인했다. 공개 설치 안내의 BookMark 링크 7개는 리다이렉트 후 HTTP 200을 반환했다.
