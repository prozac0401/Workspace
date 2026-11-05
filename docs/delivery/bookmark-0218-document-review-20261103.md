# 업무 책갈피 0.2.18 설치·사용 안내 갱신

날짜: 2026-11-03 · 상태: 문서 검사 완료, PR에서 검토 · 이 변경의 Pages 배포는 미완료

## 요청과 완료 근거

2026-11-02 공개된 WorkBookmark 0.2.18 정식 릴리스에 맞춰 Workspace의 추천 버전·MSI·ZIP·체크섬·릴리스 링크·설치 예시·업데이트와 데이터 보존 안내 및 현재 공개 버전 표를 갱신한다. 새 자석 드래그와 폴더 펼침 공간 확보·복구를 설명한다. 완료 근거는 태그 고정 제품 문서 및 공개 자산 대조, 기존 MkDocs strict·로컬 링크·공개 범위 검사와 별도 PR이다. 제품 실행·설치 시험은 이번 문서 작업 범위가 아니다.

## 변경 범위와 보존

- 설치·사용 안내와 README의 추천 버전을 0.2.18로 맞추고 배포 표의 0.2.14를 갱신했다. 기존 0.2.14 및 이전 릴리스·실패·미실행 기록은 수정하지 않았다.
- 자석에 붙은 뒤 조금씩 계속 끌어 이동하는 방법, Alt 자유 이동과 기존 간격 유지, Shift 폴더 묶기를 설명했다.
- 펼친 폴더와 자식 전체의 사각형(자식 사이 빈 공간 포함) 확보, 주변 트리의 숨긴 자식 동반 이동, 중첩·다중 펼침, 접을 때 복구·재시작 재계산, 직접 옮긴 위치 저장·취소 시 복구 위치 유지, 새 폴더 위치와 편집·크기·이동 후 재계산을 설명했다. 빈자리 부족 시 기존 위치 유지와 사용자가 공간을 확보하는 방법을 포함했다.
- DB v8 유지, 0.2.12~0.2.17에서 추가 이전 없음, MSI·ZIP 종료 후 교체, ZIP 새 폴더 전체 해제·자동 실행 확인을 반영했다. 전체 폴더 백업과 이전 직전 DB 전용 .bak의 차이, 구버전 복귀 제한·제거 후 데이터 보존 안내는 유지했다.
- 다운로드 그림의 가로·모바일 SVG와 JSON 원본·대체 텍스트에서 버전 문자열만 수정했다. 기존 그림의 구조와 다른 그림·캡션은 유지하며 제품의 실기 증거로 취급하지 않는다. 새 그림이나 공개 자산·메뉴는 추가하지 않았다.

## 제품 릴리스와 검증 근거

[정식 릴리스](https://github.com/prozac0401/BookMark/releases/tag/v0.2.18)는 draft=false·prerelease=false이다. MSI·포터블 ZIP·Source.zip·SourceSnapshot.json·MSI 검증 JSON·SHA256SUMS.txt 6종의 게시와 파일명을 확인했다. [0.2.18 고정 릴리스 안내](https://github.com/prozac0401/BookMark/blob/v0.2.18/docs/release-notes-v0.2.18.md), [제품 사용 설명서](https://github.com/prozac0401/BookMark/blob/v0.2.18/docs/user-manual.ko.md), [검증 기록](https://github.com/prozac0401/BookMark/blob/v0.2.18/docs/evidence/release-0.2.18-2026-11-02/README.md)을 기준으로 대조했다.

제품 기록의 Release 빌드는 경고·오류 0개이며 기본 자동검사 1,091개와 별도 표시 포커스 구성요소 검사 8개, 합계 1,099개가 통과했다. 최초 Desktop EXE 시작 접근 거부와 DLL 진단 실패는 원문에 보존돼 있다. 같은 빌드 EXE 후속 실행에서 통과했으며 집중 검사·재시도는 합계에 중복해서 더하지 않는다. 이번 문서 작업에서 제품 검사를 재실행한 결과가 아니다.

자동검사는 구성요소·메시지·기하 배치 기반이다. 표시 포커스 8개는 같은 UI 스레드의 검사로 실제 다른 앱 Alt+Tab 검증을 뜻하지 않는다. 다중 모니터 검사는 기하 입력 기반이며 실제 모니터 조작 시험이 아니다. 실제 마우스·키보드, 한글 IME, 다른 앱 Alt+Tab, 혼합 배율 다중 모니터, MSI 설치·업데이트·제거·재부팅과 실사용 프로필 실행은 NOT RUN이다. MSI 구조·관리 추출 파일 대조와 실제 사용자 설치를 구분한다. 패키지는 미서명이다.

공개 SHA256SUMS.txt의 MSI·ZIP 지문은 릴리스 API의 asset digest와 일치한다. 이는 다운로드 파일 전체를 재해시한 결과가 아니다.

| 파일 | 게시된 SHA-256 |
|---|---|
| WorkBookmark-0.2.18-win-x64.msi | f5ac44d56d8e746c0081f205d9a499c6991ba92215773ef2b6294e0ec83c0ba6 |
| WorkBookmark-0.2.18-win-x64.zip | 877fe6e4cd8bb13fd568357fcf3de2b5983dcf6c6695ac866ffd6e2e9250a4cc |

## 이번 문서 검증

- `python -m mkdocs build --strict`: PASS (MkDocs 1.6.1 / Material 9.7.7).
- `python scripts/check-site.py site`: PASS. 공개 22페이지·이전 주소 2개·404, 검색·사이트맵·공개 범위·로컬 경로·자산 확인.
- 설치·사용 안내의 GitHub 링크 7개: 리다이렉트 후 HEAD HTTP 200. 릴리스·MSI·ZIP·체크섬·옛 이전 안내 2개·제품 매뉴얼. 외부 매뉴얼의 backup 앵커는 태그 소스에서 확인했다.
- 공개 체크섬 본문 GET: HTTP 200. MSI·ZIP 이름과 게시된 digest 대조 완료. 설치 파일 전체 다운로드·제품 재검증은 수행하지 않았다.
- 그림 원본 JSON·가로·모바일 SVG·본문 대체 텍스트의 0.2.18 표기 일치, 그 외 그림 변경 없음 확인.
- `git diff --check` (변경 대상): PASS.

## PR과 실제 공개 상태

이 변경은 별도 PR에서 검토한다. 병합하지 않았으며 새 변경의 Pages 배포 완료를 주장하지 않는다. 기존 main `eaa1cd21f1b1ba04eb3f105fb231f9aadaf2c781`의 [Documentation 실행 41297437415](https://github.com/prozac0401/Workspace/actions/runs/41297437415)은 success이다. 2026-11-03 공개 [설치·사용 페이지](https://prozac0401.github.io/Workspace/tools/bookmark/)는 HTTP 200이며 0.2.17 MSI 링크가 남아 있고 0.2.18 MSI 링크는 없음을 확인했다. 이는 기존 배포 상태이며 이번 변경 반영 성공을 뜻하지 않는다. PR 검사는 운영 Pages를 배포하지 않는다. 병합 후 해당 커밋의 build·deploy와 공개 본문·다운로드 링크를 별도로 확인해야 한다.
