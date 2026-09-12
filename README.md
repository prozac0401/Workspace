# Workspace · 업무 운영 기준

반복 업무의 파일·폴더·이메일 정책, FolderState 사용 안내, 설계 결정과 재사용 문서 양식을 관리합니다.

[문서 사이트](https://prozac0401.github.io/Workspace/) · [운영 정책](docs/policies/workspace.md) · [FolderState](docs/tools/folderstate/index.md) · [검증 기록](docs/delivery/verification.md)

GitHub Pages에는 업무 운영 정책과 FolderState 사용법만 게시합니다. 개발 명세·설계·양식·배포·검증 기록은 저장소에서 계속 관리하고 사이트 빌드·검색·사이트맵에서는 제외합니다. 실제 업무자료와 사용자 로그는 포함하지 않습니다. FolderState 설치 파일은 별도 검증용 산출물로 관리합니다.

## 문서 빌드

```sh
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
python scripts/check-site.py site
```

GitHub Pages 설정의 Source를 GitHub Actions로 선택하면 main의 문서 변경이 배포됩니다.
