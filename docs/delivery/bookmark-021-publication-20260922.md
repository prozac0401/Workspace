# 업무 책갈피 0.2.1 공개 배포와 Pages 반영 · 2026-09-22

## 요청과 변경

사용자가 포스트잇 수정본의 확인 후 공개 배포를 요청했습니다. BookMark 저장소에서 제품 소스·MSI·ZIP을 배포하고, Workspace의 기존 공개 안내와 다운로드 링크를 0.2.1로 맞췄습니다.

- 스티커 모드 시작 시 자동 표시와 일반 창보다 항상 위 표시.
- 이어가기를 누른 스티커에만 처리 표시.
- 같은 스티커 안에서 메모 입력·저장·취소, 실패 시 입력 보존.
- 왼쪽 위 파일 종류 아이콘.
- DB v5 유지와 0.2.0에서 추가 데이터 변환 없음.

공개 범위는 기존 16개 페이지와 8개 자산을 유지합니다. 원시 진단·사용자 기록·소스·설치 파일을 Pages 출력에 복사하지 않습니다. 기존 Excel R11 작업 변경은 이번 커밋에서 제외합니다. [0.2.0 게시 이력](bookmark-pages-20260922.md)은 당시 검증 기록으로 보존합니다.

## 제품 확인

0.2.1 후보의 자동검사 586개와 100% 배율 WinForms 합성 화면 7개를 확인했습니다. 공개 준비 시 후보의 소스 스냅샷과 현재 빌드·소스·검사 파일 153개가 동일함을 대조했습니다. 소스 검토에서 새 배포 차단 결함은 발견하지 못했습니다. 공개용 안내를 정리한 커밋으로 새 패키지를 제작하고 최종 MSI·ZIP과 소스 커밋을 연결합니다.

코드 서명, 실제 설치·업데이트·제거·재부팅, 실제 한글 IME·마우스·다중 모니터·회사 환경의 전체 실기는 미완료입니다. 이를 자동검사 또는 파일 공개로 통과 처리하지 않습니다.

## 공개 결과

[BookMark v0.2.1](https://github.com/prozac0401/BookMark/releases/tag/v0.2.1)을 **2026-09-22 08:51:17 UTC**에 공개했습니다. 태그·소스 커밋은 `8213eb8e3a1d40ad4037ac71ab6bafc58533edb9`이며 최신 릴리스로 확인했습니다. 일반 릴리스 표시는 상용 인수나 실기 검증 완료를 뜻하지 않습니다.

`SourceSnapshot.json`은 `sourceMode=Commit`, `workingTreeHadChanges=false`이며 위 커밋과 일치합니다. 기능 소스는 이전에 검사한 후보와 동일하므로 자동검사 586개를 재실행하지 않고 결과를 재사용했습니다. 공개 커밋에서 Release 빌드·패키지를 다시 제작해 경고 0·오류 0, MSI 검사 54/54, 관리 이미지 추출 및 전체 파일 해시 일치를 확인했습니다. MSI는 `NotSigned`입니다.

GitHub 업로드 자산 6개의 크기와 SHA-256을 로컬 최종 배포본과 대조했습니다.

| 파일 | 크기(bytes) | SHA-256 |
|---|---:|---|
| `WorkBookmark-0.2.1-win-x64.msi` | 75,382,763 | `cbcb773dd0d47a9890457959a32f1bc37f89aa1d5cfcf58e19add21f0504f0ca` |
| `WorkBookmark-0.2.1-win-x64.zip` | 115,094,448 | `37a11ac322965f9376806a76227ebee93e8c7586b50ec1bfdec4acb94987289c` |
| `Source.zip` | 1,325,188 | `fbc460860ee98a7263162fe39dd19aed83379f7bbee76df9497440448cdfeaab` |
| `SourceSnapshot.json` | 296 | `66359bb9791d4a224a12953404ce796e1d35ddd88b47122f659f8e116352fa60` |
| `WorkBookmark-0.2.1-win-x64.validation.json` | 6,427 | `7e278fc4d23c29de203bf0942e0ba5e819f97ede83bc0ccd162f0a0b1add0724` |
| `SHA256SUMS.txt` | 555 | `50e78beca7630fec0c757bd702468a09b927fa7a6327b318f5d761d01a7da616` |

## 문서 확인과 Pages

로컬 `python -m mkdocs build --strict`와 `scripts/check-site.py site`를 통과했습니다. 공개 16페이지+404, 8개 자산, 검색·사이트맵 공개 범위와 로컬 링크를 확인했습니다. 생성된 업무 책갈피 페이지의 0.2.1 다운로드·검증 링크 5개와 새 조작 설명을 별도 검토했습니다. 이전 고정 버튼 안내, 업무 기록·로컬 경로·원시 진단 링크는 포함하지 않았습니다.

## 게시 후 확인

- 위 배포 파일 6개를 인증정보 없이 HTTPS로 다시 내려받아 모두 HTTP 200과 표의 SHA-256 일치를 확인했습니다. 내려받은 MSI의 `NotSigned`, 소스 커밋 정보, 패키지 검사 54/54와 실제 설치 `NOT RUN`도 대조했습니다.
- Workspace 안내 커밋은 `823ae5eb90f3cb15237a26435460ca75cb777f75`이며, [Documentation 실행 35707170181](https://github.com/prozac0401/Workspace/actions/runs/35707170181)의 빌드·Pages 배포 성공을 확인했습니다.
- [공개 업무 책갈피 안내](https://prozac0401.github.io/Workspace/tools/bookmark/)를 포함한 공개 페이지 16개와 자산 8개에서 비인증 HTTP 200을 확인했습니다. 홈페이지·도구 안내에 0.2.1이 표시되고, MSI·ZIP 다운로드가 v0.2.1을 가리키며, 이전 v0.2.0 다운로드 링크가 남지 않았습니다.
- 실제 HTML에서 같은 스티커 메모 입력, 일반 창 최상단 표시, 검사 수와 실기 제한을 확인했습니다. Pages 공개 범위와 기존 Excel R11 작업은 유지했습니다.

로컬 증거는 `artifacts/bookmark-021-publication-20260922/anonymous-download-verification.json`, `public-site-verification.json`, `pages-deploy.log`에 보관하고 Pages에 복사하지 않았습니다. 본 절은 게시 성공 후 결과를 기록하는 후속 문서 변경입니다.
