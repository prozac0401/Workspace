# 업무 책갈피 0.2.5 안내·Pages 반영

날짜: 2026-09-27 · 책임: 문서·배포 담당 · 상태: Pages 게시·실제 URL 확인 완료

## 대상과 변경

[BookMark 0.2.5 평가판](https://github.com/prozac0401/BookMark/releases/tag/v0.2.5)은 이미 공개된 제품이다. 이번 작업은 Workspace README·홈페이지·설치/사용 안내·배포 색인을 최신 공개 MSI·ZIP으로 연결한다. 제품을 재빌드하거나 기존 릴리스 자산을 교체하지 않는다.

메모를 스티커 제목으로 표시하고 제목 클릭/Ctrl+E로 편집하는 흐름, 새 기본 크기, 새 설치·업데이트 첫 실행의 스티커 모드와 크기 전환, DB v5 유지와 백업·구버전 복귀의 크기 제한을 설명한다. 0.2.3 이하 사용자 지정 설치 경로의 이행 절차는 보존한다.

0.2.5 릴리스 기록의 관련 자동검사93개, 100% 합성 화면11개와150% 합성 화면5개를 출처로 사용한다. 이번에 제품 시험을 재실행하거나 과거600개·설치118개를 합산하지 않았다. 실제 마우스·한글 IME·다중 모니터 등 미검증 범위를 유지한다.

## 공개 자산 확인

GitHub API에서 v0.2.5의 draft=false, prerelease=true와 2026-09-27T03:58:36Z 공개 시각을 확인했다. 다음 네 자산이 HTTP200이고 Content-Length가 API 크기와 일치했다. SHA256SUMS.txt의 파일별 해시 선언도 API digest와 일치했다. 설치 파일 전체를 재다운로드해 해시를 계산하거나 실행한 시험은 아니다.

| 자산 | 크기(bytes) | API·체크섬 선언 SHA-256 |
|---|---:|---|
| WorkBookmark-0.2.5-win-x64.msi | 75,596,440 | 283453550823347cbbf4bcd040cda8c203a85d9b863557d78fde2c306e2800d6 |
| WorkBookmark-0.2.5-win-x64.zip | 111,737,414 | a301004f05b8f5f3f3b7324ccb44f72a24cda21b4c6e367ee1cea21113957b4b |
| WorkBookmark-0.2.5-win-x64.validation.json | 10,034 | fa5cdb1dd0522a8c2750f1922e6a4b59c33ab7d48d2baaeb70d89655f71f8317 |
| SHA256SUMS.txt | 555 | API digest 확인; 다른 파일의 선언 대조에 사용 |

## 검증과 게시

최종 MkDocs strict 빌드와 생성 사이트 검사가 모두 종료0으로 통과했다. 공개19페이지+404·검색·사이트맵·비공개 제외·로컬 경로/자산 검사가 PASS다. 읽기 전용 문서 검토의 문구 보완을 반영했고 git diff --check도 통과했다. 공개 페이지19개와 기존 공개 범위는 유지하며 ImageCopySave MSI·진단·검토 자료를 Pages에 추가하지 않는다.

[그림 도구 배포 준비](image-release-readiness-20260927.md)의 소스·문서 반영과 제품 공개 보류를 구분한다. 그림 도구의 기본 메뉴 두 기능은 사용자 직접 확인으로 기록했지만 설치 자원 보존과 나머지 인수 항목은 미완료다.

로컬 원시 네트워크 결과와 빌드 로그는 artifacts/release-readiness-20260927 아래에 보존하며 사이트에 넣지 않는다. 실제 main·Documentation 실행·공개 URL 결과는 게시 후 이 기록에 추가한다.

## 실제 게시 결과

- 콘텐츠 커밋: [f4dd510](https://github.com/prozac0401/Workspace/commit/f4dd510d0f2258ba53c2e5486698f6a048f941b1). 이전 로컬 MSI 구현4커밋과 그림 도구 준비 판정, 업무 책갈피 안내를 순차 커밋으로 main에 반영했다.
- [Documentation 실행](https://github.com/prozac0401/Workspace/actions/runs/36294541024): completed / success.
- 실제 공개19페이지 모두 HTTP200. 홈과 업무 책갈피 페이지에0.2.5가 표시되며 MSI·ZIP 링크, 제목 편집, 첫 실행 스티커 모드·크기 변경 안내를 확인했다.
- ImageCopySave 안내, 이번 그림 도구 준비 기록과 업무 책갈피 게시 기록의 Pages 경로는 HTTP404로 제외됐다.
- 업무 책갈피 제품 파일은 기존 공개 자산을 연결했고 변경하지 않았다. ImageCopySave 검토용 MSI는 로컬에만 보존하고 공개 릴리스에 추가하지 않았다.
- 이 후속 커밋은 Pages에서 제외되는 게시 기록만 갱신한다. 공개 콘텐츠와 다운로드 파일은 변경하지 않는다.
