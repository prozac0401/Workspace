# 업무 책갈피 0.2.8 링크·사용 안내와 main 반영

날짜: 2026-09-27 · 책임: 문서·배포 담당 · 상태: main 반영·Pages 배포·실제 공개 링크 확인 완료

## 요청과 변경 범위

사용자는 그림 복사·저장 정식 릴리스와 BookMark 최신 버전의 GitHub Pages 링크를 확인하고 현재 작업을 main에 반영하도록 요청했다. 그림 복사·저장 0.2.0은 이미 main과 공개 안내에 반영돼 있었고 실제 MSI 링크도 HTTP 200이다. 해당 제품의 [보존·설치·정식 게시 기록](image-020-release-20260927.md)은 유지한다.

BookMark의 최신 공개 버전은 [0.2.8 평가판](https://github.com/prozac0401/BookMark/releases/tag/v0.2.8)이지만 Workspace 홈·README·설치 안내는 0.2.5를 가리켰다. 버전별 MSI·ZIP·체크섬·패키지 검증 링크를 0.2.8로 갱신하고 한 줄 메모·바로가기 화살표·편집 중 임시 확대·사용자 크기와 표시 모드 보존·Whale 지원 안내를 현재 사용법에 맞춘다. 제품 소스나 공개 설치 파일은 변경하지 않는다.

`releases/latest`는 최신 정식판 0.2.3으로 연결된다. 최신 공개 평가판을 안내하기 위해 0.2.8 고정 태그와 **평가판** 표시를 사용한다. 정식판으로 승격하거나 제품 검증을 다시 수행한 작업이 아니다.

## 공개 자산과 소스 확인

GitHub API에서 releaseId=397545366, draft=false, prerelease=true, 게시 시각 2026-09-27T07:09:03Z를 확인했다. BookMark 원격 main과 로컬 main은 d507a885ed5f73bca95ee0989bb2e0295915a787로 일치한다.

| 설치 자산 | 바이트 | API·체크섬 선언 SHA-256 |
|---|---:|---|
| WorkBookmark-0.2.8-win-x64.msi | 75,709,758 | 4e2dba00c42e7b169d0a88cb9b43d70ded960dc1ba1b50176624d903295a4ba0 |
| WorkBookmark-0.2.8-win-x64.zip | 111,858,965 | 643a496c6ac21f0b60685d45bfd68b35a3bcce3a0e34adeefb612fafbd035c78 |

공개 자산 6개의 HEAD 요청은 모두 HTTP 200이고 Content-Length는 API 크기와 일치했다. SHA256SUMS.txt를 읽어 나머지 5개 자산의 선언 해시와 API digest가 일치함을 확인했다. 이번 작업에서 MSI·ZIP 전체를 다시 내려받아 해시를 계산하거나 설치·실행한 것은 아니다. 그림 복사·저장 0.2.0 MSI도 HEAD 200과 50,569,176바이트를 확인했다.

BookMark 0.2.8 릴리스가 기록한 브라우저 자동검사 34개와 패키지 검사 54개는 제품 측 기존 근거다. 실제 Whale 창에서 저장·재열기는 미검증이며 이번 링크·문서 검사가 이를 대체하지 않는다. DB v5·설정 및 백업 안내, 코드 서명 없음과 다른 환경의 미검증 범위를 유지한다.

## 문서 검증과 main·Pages 결과

원래 작업 사본의 수정·미추적 문서와 도구 파일 164개를 현재 main 및 커밋 이력과 대조했다. 159개는 동일 내용·과거 반영본·재번호 문서 또는 최신 결과로 대체된 기록이었다. 아직 반영되지 않은 R11 사후 검증·성능 문서 4개와 ADR-0009의 후속 결정 연결 2문장을 이번 main 변경에 포함한다. 미반영 제품 소스 변경은 없었다. 원래 작업 사본은 변경하지 않는다.

R11의 기록은 2026-09-20 당시 결과이며 이번에 재실행한 시험이 아니다. 취소 안내·상태표시줄 실패와 전체 인수 미완료 판정도 함께 보존한다. ADR의 Undo 분리 참조는 현재 번호 ADR-0018로 연결한다. 원시 사용자 로그·설치 진단·첨부·생성 파일은 커밋하지 않는다.

MkDocs strict 빌드와 `scripts/check-site.py` 검사를 통과했다. 공개 20페이지·404와 자산 8개를 유지하며 검색·사이트맵에는 공개 경로만 들어 있다. 생성된 로컬 링크는 모두 연결되고 새 검증 기록·ADR·로컬 네트워크 결과는 Pages에 포함되지 않았다. `git diff --check`도 통과했다.

변경 10개 파일은 [3e4ff708769a01a1b47fee1ce778c10f934e7bde](https://github.com/prozac0401/Workspace/commit/3e4ff708769a01a1b47fee1ce778c10f934e7bde)로 원격 main에 반영했다. [Documentation 실행 36323149778](https://github.com/prozac0401/Workspace/actions/runs/36323149778)은 성공했으며 원격 main의 커밋도 일치함을 확인했다.

배포 후 실제 [홈](https://prozac0401.github.io/Workspace/)과 [BookMark 안내](https://prozac0401.github.io/Workspace/tools/bookmark/)에서 0.2.8 평가판과 고정 다운로드 링크 5개를 확인했다. 이전 0.2.5 다운로드 링크는 남아 있지 않다. [그림 복사·저장 안내](https://prozac0401.github.io/Workspace/tools/image-copy-save/guide/)는 0.2.0 MSI 연결을 유지한다.

공개 20개 경로·자산 8개·검색·사이트맵은 모두 HTTP 200이다. 검색과 사이트맵은 공개 20개 경로로만 구성되며 이번 내부 배포 기록·R11 명세·ADR의 Pages 경로 3개는 HTTP 404를 확인했다. 새 검증 문서의 상대 링크 30개와 날짜·버전 구분도 대조했다. 이번 검증은 문서·링크 확인이며 제품 기능·설치 재시험이 아니다.
