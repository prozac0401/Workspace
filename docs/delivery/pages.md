# GitHub Pages 운영

문서 주소: [Workspace 자료 정리와 업무 안내](https://prozac0401.github.io/Workspace/)

## 원본과 게시

docs/의 Markdown과 mkdocs.yml을 편집합니다. main 반영 후 Documentation 워크플로가 문서 빌드와 공개 범위·링크 검사를 통과하면 GitHub Pages에 게시합니다. 생성한 HTML을 직접 편집하지 않습니다.

워크플로 성공과 공개 URL의 HTTP 응답 및 새 문장·메뉴·검색·사이트맵을 함께 확인합니다. Pages의 Source는 GitHub Actions를 사용합니다.

## 공개할 내용

업무 운영 안내, 가짜 자료로 설명하는 교육 업무 예시, 공개가 허용된 아홉 프로그램의 설치·사용·문제 해결 안내를 올립니다. [현재 도구 버전](index.md)의 최신 요약과 각 상세 안내를 맞춥니다. 날짜별 과거 기록은 당시 버전과 시험 결과로 남깁니다.

개발 정책·최초 명세·설계 결정·문서 양식·제작 및 검증 기록은 저장소에서 보존하되 사이트에서 제외합니다. 실제 명단·메일·업무 경로·사용자 로그·인증서·설치 진단과 첨부 검토 원문은 사이트에 올리지 않습니다. 저장소 자체가 공개되어 있다는 사실은 Pages의 게시 범위와 별개입니다.

mkdocs.yml의 exclude_docs에서 전체 문서를 제외하고 검토한 문서와 자산만 허용합니다. 공개 목록을 scripts/check-site.py와 함께 유지합니다. PPTX·DOCX 원본과 설치 파일은 사이트에 복사하지 않습니다.

현재 공개 안내는 21개입니다. FolderState의 이전 설치·문제 해결 주소 2개에는 통합 안내로 이동하는 문서를 생성합니다. 이 두 주소를 메뉴·검색·사이트맵의 별도 안내로 싣지 않습니다. 공개 자산은 CSS와 FolderState 화면, 기존 WebP 이미지 6개와 교육 예시 화면 7개로 모두 15개입니다. 오피스 자동화 도구 안내를 추가하면서 공개 자산은 늘리지 않습니다.

ProbPacker의 Office Automation Tools 0.3.1은 [ADR-0034](../design/0034-office-automation-public-guide.md)에 따라 `tools/office-automation/` 한 페이지와 Workspace 공개 릴리스의 고정 태그 EXE·ZIP 링크로 안내합니다. 원본 ProbPacker는 비공개이므로 배포물만 Workspace에 동일 해시로 게시합니다. Python과 Office 설치의 차이, 자체 서명과 남은 검증 범위를 공개 안내에 직접 적습니다. 바이너리·QA 자료·인증서·원시 진단은 Pages로 복사하지 않습니다.

[정책 문서 작성 규칙](../policies/documentation.md), [교육 업무 안내 공개 결정](../design/0029-education-public-guide.md)을 따릅니다. 새 공개 문서가 생기면 메뉴·허용 목록·검사 목록을 함께 고칩니다.

## 설치 파일 연결

도구별 GitHub Release의 버전과 실제 첨부 파일을 대조합니다. 원칙적으로 각 버전의 파일이나 배포 안내에 연결하며, 서로 다른 도구가 섞이는 releases/latest/download를 쓰지 않습니다. 파일을 받을 수 있는 상태와 실제 설치·실행 확인은 구분합니다.

보이는 칸 붙여넣기는 기존 사용자 요청과 [ADR-0014](../design/0014-visible-cells-paste-download-list.md)에 따라 공개 설치 안내에서 Workspace Releases 목록을 연결합니다. 사용자는 도구 이름을 찾고 단일 EXE를 고릅니다. ZIP은 대안입니다. 상세 안내에는 특정 버전·직접 자산 URL과 개발 시험 결과를 넣지 않으며 사용에 필요한 제한은 유지합니다.

나머지 도구의 최신 버전과 파일명은 [배포 색인](index.md)과 [2026-10-05 문서 수정 기록](document-review-20261005.md)에서 확인합니다. 시험용 여부와 알려진 실패를 다운로드 전에 쉬운 말로 설명합니다. 일반 배포 전환을 코드 서명·상용 인수·회사 도입 승인으로 해석하지 않습니다.

## 게시 전 검사

```powershell
python -m mkdocs build --strict
python scripts/check-site.py site
```

검사기는 공개 안내 21개·이전 주소 이동 문서 2개·404 외의 HTML, 제외한 자산의 복사, 비공개 문서의 검색·사이트맵 노출, 깨진 로컬 링크를 실패로 처리합니다. 교육 안내 주소는 education-operations/이며 오피스 자동화 도구 주소는 tools/office-automation/입니다.

수정한 공개 문장과 메뉴 이름을눈으로 검토하고,작은 화면에서도 표·단계 안내를 읽을 수 있는지 확인합니다. 실제 비전공자의 이해도나 업무 효과를 측정하지 않았다면 미확인으로 남깁니다.

## 게시 후 확인과 복구

main에 반영한 변경 번호, Documentation 실행 주소, 완료 상태, 실제 공개 URL의 내용을 기록합니다. 공개 첫 화면과 새 교육 안내, 도구 페이지, 검색과 사이트맵을 확인합니다. 이전 개발 문서의 404와 제외한 원본 파일의 미노출도 확인합니다.

문제가 있으면 이전 정상 문서 변경으로 되돌려 다시 빌드·게시합니다. Pages의 설정이나 생성한 HTML만 바꿔 원본과 다르게 만들지 않습니다. 과거 브라우저·검색엔진의 저장 내용을 즉시 지우는 것까지 보장하지 않습니다.
