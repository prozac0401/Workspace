# 업무 책갈피 0.2.17 공개 안내 후속 갱신

날짜: 2026-10-20 · 기준: main 5ef9735 (PR #32 병합 후)

## 요청과 변경 범위

추천 버전·MSI/ZIP/체크섬·파일명과 DB v8 유지 안내를 0.2.17로 맞춘다. 제목 클릭 선택·끌기 이동·더블클릭/F2/Ctrl+E 편집, Shift+드래그 묶기/넣기와 Alt 우선 자유 이동, 왼쪽 이동/폴더 픽토그램·자식 개수를 태그 고정 구현과 대조했다. 관련 SVG 원본을 갱신하고 교육 업무의 낡은 책갈피 그림은 최신 조작 SVG로 교체한다. 과거 PNG는 보존하되 본문에서 사용하지 않는다. 기존 PR #32의 백업·복원·DB 이전·설정 닫기·검색 안내와 이전 확인 기록을 보존한다. 제품 코드·사용자 데이터는 변경하지 않는다.

완료 근거: 정식 릴리스·소스 대조, MkDocs strict와 공개 출력/로컬 링크 검사, 공개 GitHub 링크 응답 확인, 후속 PR의 검사·병합과 Pages 배포 확인.

## 릴리스의 기존 검증과 한계

[정식 릴리스](https://github.com/prozac0401/BookMark/releases/tag/v0.2.17)는 API에서 draft=false, prerelease=false이며 MSI·ZIP·Source.zip·SourceSnapshot.json·MSI 검증 JSON·SHA256SUMS.txt 6종 게시를 확인했다. 태그 소스 커밋은 08d6694f45ea6c9cb5a6cec0dce1091cbeb4692f이다.

[0.2.17 검증 기록](https://github.com/prozac0401/BookMark/blob/v0.2.17/docs/evidence/release-0.2.17-2026-10-20/README.md)은 기본 자동검사 1,027개와 별도 표시 포커스 구성요소 8개, 합계 1,035개 통과와 Release 빌드 경고·오류 0개를 기록한다. 집중검사 285개는 부분집합으로 중복 합산하지 않는다. 비교 이미지의 2배·3배 열은 픽셀 확대이며 Windows 혼합 DPI 시험이 아니다.

실제 MSI 설치·업데이트·제거·재부팅, 실사용 프로필, 실제 마우스·키보드·한글 IME, 다른 앱 Alt+Tab/전경 순서와 혼합 배율 모니터 조작은 NOT RUN이다. MSI 구조 검사·관리 추출과 실제 설치를 구분한다. 패키지는 미서명이다. 이번 작업에서 제품 시험·배포 파일 전체 해시 검사를 재실행하지 않았다.

## 문서 검증

- MkDocs strict 빌드: PASS.
- `python scripts/check-site.py site`: PASS (공개 22페이지·이전 주소 2개·404, 검색·사이트맵·공개 범위·로컬 링크).
- 공개 안내의 GitHub 링크 7개: 리다이렉트 후 HEAD HTTP 200 (MSI·ZIP·체크섬·릴리스·이전 안내 2개·매뉴얼).
- 변경 파일 `git diff --check`: PASS.
- 제품 소스·사용자 데이터 변경 없음. 과거 검증 기록은 수정하지 않음.

PR·Pages 결과는 후속 실행 결과로 확인한다.
