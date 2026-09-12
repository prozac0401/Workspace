# Workspace · 업무 운영 기준

반복 업무의 파일·폴더·이메일 정책, FolderState 사용 안내, 설계 결정과 재사용 문서 양식을 관리합니다.

[문서 사이트](https://prozac0401.github.io/Workspace/) · [운영 정책](docs/policies/workspace.md) · [FolderState](docs/tools/folderstate/index.md) · [검증 기록](docs/delivery/verification.md)

공개 범위는 정책·설계·사용·배포 문서입니다. 실제 업무자료와 사용자 로그는 포함하지 않습니다. FolderState 설치 파일은 별도 검증용 산출물로 관리합니다.

## 문서 빌드

```sh
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
```

GitHub Pages 설정의 Source를 GitHub Actions로 선택하면 main의 문서 변경이 배포됩니다.
