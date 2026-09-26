# 백로그 항목별 릴리스 · 2026-09-27

사용자 요청에 따라 완료 커밋을 push하고 설치 파일과 GitHub Pages를 순차 게시한다. 업무 파일·원본 작업 폴더·사용자 로그는 게시하지 않는다. 실제 설치가 차단된 후보는 공개 다운로드로 안내하지 않는다. 과거 검증 기록의 미게시 표시는 당시 상태로 보존한다.

## Workspace 완료 커밋

`85fea6a4444374fb7a022a13c94287355c8b03ac`까지 15개 커밋을 main에 push했다. [문서 배포](https://github.com/prozac0401/Workspace/actions/runs/36264091587), [VisibleCellsPaste 빌드](https://github.com/prozac0401/Workspace/actions/runs/36264091577), [Windows 빌드·MSI](https://github.com/prozac0401/Workspace/actions/runs/36264091523)가 성공했다.

## T05 · 보이는 칸 붙여넣기

[0.1.1 단일 설치 릴리스](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.1.1-setup.1)를 게시했다. 태그는 위 완료 커밋을 가리킨다. 검증한 EXE 177,664 bytes의 SHA-256은 `bd55f32f3a9d467ed288696c8e80dd7f5e9eb97a280ba12a25fe622a5d26b464`다. 체크섬과 상대 소스 경로만 담은 manifest를 함께 제공한다. 공개 ZIP·제품 DLL은 변경하지 않았으며 기존 ZIP 릴리스도 보존한다. 실제 x86 Office·새 PC·재부팅 검증은 남아 있다.

공개 자산 API의 파일 크기·SHA-256이 로컬 검증 파일과 일치했다. 문서 strict 빌드와 공개19페이지·404·검색/사이트맵·비공개 제외·생성 링크 검사 PASS.

## T06·T07 · 선택범위 내보내기

[0.1.0-rc.10 평가판](https://github.com/prozac0401/Workspace/releases/tag/excel-selection-export-v0.1.0-rc.10)을 게시했다. 태그는 `85fea6a`다. x64 2,137,629 bytes·SHA-256 `9171be45330ce9af86ce7b5eb06614211e3620bd47893912b03dd6ff2829114a`, x86 2,137,740 bytes·`f7d46d731f2c5e34ab8747755252b0f02387e8ce8a44f489fc41e3238e21b79e`가 GitHub 자산과 일치했다. 빌드 manifest·체크섬·경로/로그 없는 검증 요약을 제공했다. 빌드 시점 입력15개 중 Test-Package.ps1만 후속 검사기 변경으로 다르고 제품 소스·설치기·빌드 입력은 같다. 기존 패키지 내부 README의 대기 문구는 제작 당시 상태이며 현재 공개 안내·릴리스 요약이 후속 결과를 설명한다. 실제 x86·새 환경·재부팅·전체 실패/취소·조직 승인은 미완료다.

공개 안내·README·CHANGELOG의 현재 상태를 정리했다. 문서 strict 빌드와 공개19페이지·404·생성 링크·비공개 제외 검사 PASS.

## T08 · BookMark

BookMark 수정 두 커밋을 main에 push하고 [0.2.4 평가판](https://github.com/prozac0401/BookMark/releases/tag/v0.2.4)을 `3f87da7`에 게시했다. 검증 MSI 75,451,327 bytes·SHA-256 `aebd7bb3844951a02b7323ffa1d1ddd16b06ff542f0bc90691de3eb1f6f370f3`가 GitHub 자산과 일치했다. 구조 검증 JSON·체크섬·후속 검증 요약을 첨부했다. 새 포터블 ZIP은 제작하지 않았으며 기존 0.2.3 ZIP을 버전 표시와 함께 보존한다. 실제 스티커 입력·IME·자동 저장·초안·작업 재개는 NOT_RUN, 재로그인·재부팅·추가 환경도 남아 있다. 두 저장소의 현재 설치 안내에 기존 사용자 지정 경로를 명시적으로 제거한 뒤 이전하는 절차를 반영했다.

BookMark 변경 문서의 상대 링크52개 누락0, Workspace strict 빌드·공개19페이지/404·생성 링크 검사 PASS.

## T09 · FolderState

[기존 0.1.3 RC1 릴리스](https://github.com/prozac0401/Workspace/releases/tag/folderstate-v0.1.3-rc.1)에 2026-09-27 후속 설치31검사·실제 메뉴/상태/복구와 보존 범위를 추가했다. 기존 자산3개의 이름·크기·SHA-256은 변경 전후 동일하다. 새 PC·재부팅·공유/동기화·접근성·회사 승인은 미검증으로 유지한다.

## T10 · File List to Excel

[기존 1.2.0 릴리스](https://github.com/prozac0401/File-List-To-Excel/releases/tag/v1.2.0)에 합성 폴더246검사·실제10파일 복사·원본 보존·제거와 T12 대표 공존 확인을 추가했다. 기존 MSI와 체크섬 자산2개의 이름·크기·SHA-256은 변경 전후 동일하다. File List 제품 소스는 변경하지 않았으며 업무 자료 수용·x86·추가 환경 검증으로 확대하지 않는다.

## T11·T12 · 명단 비교 R12와 공존

[기존 R12 릴리스](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.0-rc.12)와 공개 안내에 합성 대표 비교·정상 종료·다른 제품 순차 제거 후 보존 확인을 추가했다. 기존 자산8개의 이름·크기·SHA-256은 변경 전후 동일하다. T11의 전체 회귀·설치 수명주기 조건부 대기는 유지하며 이번 대표 공존 확인을 전체 재시험으로 표시하지 않는다. T12는 별도 제품 버전이 아니므로 네 제품의 동일 자산에 대한 검증 기록으로 연결한다.

## T02·T03·T04 · ImageCopySave

[설치 신뢰 차단 후보 초안](https://github.com/prozac0401/Workspace/releases/tag/untagged-1587bc4162cf82e91a17)을 생성했다. 릴리스 ID397361812, 예정 태그 `image-copy-save-v0.1.1`, 대상 커밋 `85fea6a`, draft=true·prerelease=true를 확인했다. 서명 사본 MSIX 64,335,585 bytes·SHA-256 `263bfb40780bd536034a8bf78e50a58bb57f683a998d03f9bd35b970cbcc5ae9`가 업로드 자산과 일치했다. 체크섬과 차단 요약을 첨부했다.

실제 설치0x800B0109와 격리 환경 native183/종료77은 해결되지 않았다. G0·외부 앱·설치 수명주기 NOT_RUN을 유지하며 초안은 공개 릴리스가 아니다. 공개 Pages 허용 목록이나 다운로드를 추가하지 않았다. 개인 키·인증서 암호·로컬 진단은 게시하지 않았다.

## 안내 최종 정리

기존 VisibleCellsPaste ZIP 릴리스의 문자로 표시되던 줄바꿈을 실제 Markdown 줄바꿈으로 정리하고 새 EXE 릴리스를 연결했다. 기존 자산2개는 불변이다. README·소스 설치 안내·배포 색인에서 과거 후보/미게시 문구를 정리했으며, 과거 시험 기록 원문은 당시 결과로 유지한다.

## GitHub Pages와 최종 검증

[77ab8a2 문서 배포](https://github.com/prozac0401/Workspace/actions/runs/36265171890)가 성공했다. 실제 공개 사이트19페이지 모두 HTTP200이며 BookMark0.2.4·선택범위rc.10·붙여넣기Setup.exe 안내를 확인했다. README와 현재 공개 설치 안내의 직접 다운로드15개 모두 HTTP200, 파일 크기도 공개 자산과 일치했다. 개발 배포 기록·ImageCopySave·개발 문서 정책 경로는 실제 사이트에서404로 공개 제외를 확인했다.

원시 HTTP 검사 결과는 로컬 artifacts의 publication 아래에 보관한다. 공개 다운로드에는 실제 검증한 파일만 첨부했으며 설치·Excel 시험을 병행하지 않았다. 마지막 현재 안내 문구 정리도 strict 빌드와 생성 링크 검사 후 push한다. BookMark main은 `6609de7`까지 push했으며 원래 두 저장소 작업 폴더의 사용자 변경은 보존했다.
