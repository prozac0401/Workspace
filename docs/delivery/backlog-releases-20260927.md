# 백로그 항목별 릴리스 · 2026-09-27

사용자 요청에 따라 완료 커밋을 push하고 설치 파일과 GitHub Pages를 순차 게시한다. 업무 파일·원본 작업 폴더·사용자 로그는 게시하지 않는다. 실제 설치가 차단된 후보는 공개 다운로드로 안내하지 않는다. 과거 검증 기록의 미게시 표시는 당시 상태로 보존한다.

## Workspace 완료 커밋

`85fea6a4444374fb7a022a13c94287355c8b03ac`까지 15개 커밋을 main에 push했다. [문서 배포](https://github.com/prozac0401/Workspace/actions/runs/36264091587), [VisibleCellsPaste 빌드](https://github.com/prozac0401/Workspace/actions/runs/36264091577), [Windows 빌드·MSI](https://github.com/prozac0401/Workspace/actions/runs/36264091523)가 성공했다.

## T05 · 보이는 칸 붙여넣기

[0.1.1 단일 설치 릴리스](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.1.1-setup.1)를 게시했다. 태그는 위 완료 커밋을 가리킨다. 검증한 EXE 177,664 bytes의 SHA-256은 `bd55f32f3a9d467ed288696c8e80dd7f5e9eb97a280ba12a25fe622a5d26b464`다. 체크섬과 상대 소스 경로만 담은 manifest를 함께 제공한다. 공개 ZIP·제품 DLL은 변경하지 않았으며 기존 ZIP 릴리스도 보존한다. 실제 x86 Office·새 PC·재부팅 검증은 남아 있다.

공개 자산 API의 파일 크기·SHA-256이 로컬 검증 파일과 일치했다. 문서 strict 빌드와 공개19페이지·404·검색/사이트맵·비공개 제외·생성 링크 검사 PASS.
