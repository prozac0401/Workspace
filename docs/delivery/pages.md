# GitHub Pages 운영

문서 주소: [Workspace 운영 기준](https://prozac0401.github.io/Workspace/)

## 원본과 게시

docs/의 Markdown과 mkdocs.yml을 편집합니다. main 반영 후 문서 워크플로가 strict 빌드를 통과하면 GitHub Pages용 정적 파일을 배포합니다. 저장소 Settings → Pages의 Source는 GitHub Actions로 설정합니다.

워크플로 파일을 추가한 것만으로 게시 완료로 간주하지 않습니다. Actions의 성공과 실제 URL의 HTTP 응답·문서 내용을 확인합니다. 계정 로그인이나 Pages 설정 권한이 없는 환경에서는 설정 안내와 빌드 결과를 남깁니다.

## 검토 범위

공개 가능한 정책·가상 양식·소스·명세만 배포합니다. 로컬 업무 경로·메일·명단·사용자 로그·인증서·설치 진단 파일은 포함하지 않습니다. site/ 출력 전체가 공개된다는 기준으로 검토합니다.

## 운영

오류가 있으면 이전 정상 문서 원본 커밋으로 되돌려 빌드합니다. 생성된 HTML만 직접 편집하지 않습니다. 제품 릴리스와 문서 게시를 연결하되 미검증 상태를 숨기지 않습니다.
