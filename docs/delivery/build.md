# 개발과 빌드

## 요구 환경

저장소 main에는 FolderState 소스·테스트·설치 정의와 문서 원본을 함께 관리합니다. 저장소를 내려받은 로컬 Workspace에서 아래 명령을 실행합니다. GitHub Pages에는 업무 운영 기준과 FolderState 사용 안내만 게시합니다.

Windows 11 x64, global.json에 고정된 .NET 10 SDK, PowerShell을 사용합니다. 도구 매니페스트는 WiX 4.0.6을 고정합니다. 처음 복원 시 NuGet 네트워크 접근이 필요합니다. 생성된 아이콘은 저장소에 포함되며 재생성 때만 Pillow가 필요합니다.

```powershell
dotnet run --project tests/FolderState.Tests -c Release
powershell -NoProfile -File scripts/build.ps1 -Version 0.1.0
```

build.ps1은 통합 테스트 → WPF·CLI 자체 포함 publish → 고정 설치 파일 목록 생성 → WiX MSI 생성 → SHA-256 생성 순서로 실행합니다. 검증용 옵션 -SkipTests는 테스트를 건너뛴 사실을 별도로 기록할 때만 사용합니다.

출력은 artifacts/release 아래에 생성됩니다. 빌드 도구·중간 결과·인증서·로그는 Git에 포함하지 않습니다. 작업용 artifacts/publish는 빌드 시 검증된 저장소 내부 경로에서만 정리합니다.

## 문서

```powershell
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
python scripts/check-site.py site
python -m mkdocs serve
```

문서 원본은 docs/, 생성 결과는 site/입니다. 최초 원문 01·02의 사본은 docs/specifications/에 두며 원문 수정 시 동기화를 확인합니다.

## 릴리스

제품 버전은 MSI 제한에 맞는 major.minor.patch를 사용합니다. 서명은 게시자가 확정된 후 관리되는 인증서로 실행하며 개인키를 저장소에 넣지 않습니다. 배포 파일의 해시는 서명 후 다시 생성합니다. GitHub Release에는 검증 기록, MSI, SHA-256, 정확한 소스 커밋을 연결합니다.
