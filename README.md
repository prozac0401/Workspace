# Workspace

반복 업무를 키트로 시작하고, 폴더의 상태로 진행 상황을 확인하며, 업무가 끝나면 컨테이너 전체를 보관하는 업무 운영 체계입니다.

- **01 FolderState**: Windows Explorer 폴더 상태표시 도구. C# / .NET 10 / WPF, 사용자별 MSI 설치.
- **02 운영 정책**: 파일·폴더·이메일, 원본 시스템, MASTER 키트, 설계와 문서 관리 기준.
- **공통 기반**: 향후 도구가 공유할 문서 양식, ADR, 명세 대응표, 테스트·배포 기준.

[문서 사이트](https://prozac0401.github.io/Workspace/) · [원문 01](01_Windows_Explorer_폴더상태도구_명세.md) · [원문 02](02_사무실PC_파일폴더이메일_정리설계안.md)

## 빌드

Windows 11 x64, .NET SDK는 `global.json`의 버전을 사용합니다.

```powershell
dotnet run --project tests/FolderState.Tests -c Release
powershell -NoProfile -File scripts/build.ps1
```

결과: `artifacts/release/FolderState-0.1.0-win-x64.msi` 및 SHA-256 파일. 자체 포함 배포이므로 사용자 PC에 .NET을 따로 설치하지 않습니다.

```powershell
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
python -m mkdocs serve
```

## 구조

```text
src/          상태 엔진, WPF 관리 화면, CLI
tests/        실제 Windows 파일시스템 통합 테스트
installer/    사용자별 MSI 정의
scripts/      재현 가능한 빌드·검증 스크립트
docs/         GitHub Pages 문서 원본
assets/       다중 해상도 상태 아이콘
```

현 배포 단계와 실제 검증 결과는 [품질 기준](docs/delivery/quality.md), [검증 기록](docs/delivery/verification.md)을 확인하세요. 코드 서명과 깨끗한 PC의 설치 수명주기 검증이 완료되기 전에는 상용 정식판으로 분류하지 않습니다.
