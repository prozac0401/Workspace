# Workspace

**필요한 자료를 찾고, 다음에 할 일을 알 수 있도록 돕습니다.** 파일과 메일을 정리하는 방법, 폴더에 진행 상태를 표시하는 FolderState, 두 목록을 비교하는 Excel 명단 비교, 저장한 작업 위치로 돌아가는 업무 책갈피를 안내합니다.

[지금 할 일 찾기](docs/quick-reference.md)에서 자신의 상황을 골라 보세요. 처음 사용한다면 [업무 하나로 시작하기](docs/getting-started.md)를 따라 하면 됩니다. 반복하는 업무는 복사용 기본 폴더를 만들어 두고 새 업무를 시작할 때 복사해 씁니다. 업무가 끝나면 그 폴더를 통째로 보관합니다.

- **[FolderState 설치·사용](docs/tools/folderstate/installation.md)**: Windows 폴더 아이콘으로 업무 진행 상태를 표시합니다.
- **[Excel 명단 비교 설치·사용](docs/tools/excel-list-compare/index.md)**: 두 목록에서 다른 값과 중복된 값을 찾습니다.
- **[업무 책갈피 설치·사용](docs/tools/bookmark/index.md)**: 문서 위치·웹페이지를 남기고 목록이나 포스트잇 스티커에서 다시 엽니다.
- **[파일과 메일 정리하기](docs/policies/workspace.md)**: 현재 업무, 복사용 기본 폴더, 끝난 업무를 어디에 둘지 안내합니다.
- **[놓치는 일과 반복 작업 줄이기](docs/policies/work-efficiency.md)**: 요청을 모으거나 이전 해결 방법을 찾기 어려울 때 필요한 방법만 골라 씁니다.

[안내 사이트](https://prozac0401.github.io/Workspace/) · [폴더 상태 도구의 최초 명세](01_Windows_Explorer_폴더상태도구_명세.md) · [파일·폴더·메일 정리의 최초 설계안](02_사무실PC_파일폴더이메일_정리설계안.md)

업무 안내는 **제안 단계**입니다. 저장 위치와 자료 보관 기간 등은 회사에서 정한 기준을 따릅니다. 안내 사이트에는 업무 안내와 세 프로그램의 설치·사용법을 공개합니다. 개발 명세·설계·양식·배포·검증 기록은 저장소에서 관리하며 사이트에는 공개하지 않습니다.

## 프로그램 받기

| 프로그램 | 설치 파일 | 확인할 내용 |
|---|---|---|
| FolderState 0.1.3 RC1 | [Windows x64 설치 파일 (MSI)](https://github.com/prozac0401/Workspace/releases/download/folderstate-v0.1.3-rc.1/FolderState-0.1.3-win-x64.msi) · [배포 페이지](https://github.com/prozac0401/Workspace/releases/tag/folderstate-v0.1.3-rc.1) | [설치·업데이트·제거](docs/tools/folderstate/installation.md) |
| Excel 명단 비교 0.2.0 R12 | [Windows 설치 파일 (EXE)](https://github.com/prozac0401/Workspace/releases/download/excel-smart-list-compare-v0.2.0-rc.12/ExcelSmartListCompare-0.2.0-rc.12-Setup.exe) · [ZIP·배포 자료](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.0-rc.12) | [설치·사용 안내](docs/tools/excel-list-compare/index.md) |
| 업무 책갈피 0.2.2 | [Windows x64 설치 파일 (MSI)](https://github.com/prozac0401/BookMark/releases/download/v0.2.2/WorkBookmark-0.2.2-win-x64.msi) · [ZIP·배포 자료](https://github.com/prozac0401/BookMark/releases/tag/v0.2.2) | [설치·사용 안내](docs/tools/bookmark/index.md) |

Excel R12는 비교 로직을 유지하면서 차이 결과와 담은 목록 확인의 문구·표를 간결하게 정리했습니다. 사용자 요청에 따라 기존 테스트는 실행하지 않았으며 [R12 제작·배포 기록](tools/ExcelSmartListCompare/docs/RC12_RELEASE_REPORT.md)에 구분해 남깁니다. 세 프로그램의 설치 파일에는 코드 서명이 없습니다.

업무 책갈피 0.2.2는 포스트잇의 메모 글이나 빈 메모 영역을 한 번 눌러 바로 편집합니다. 스티커를 항상 위에 표시하고 파일 종류 아이콘을 보여 줍니다. 0.2.0과 같은 데이터 형식을 사용합니다. 업데이트 전에 [백업·복원 안내](docs/tools/bookmark/index.md#backup)를 확인하세요. 소스와 배포 파일은 별도 [BookMark 저장소](https://github.com/prozac0401/BookMark)에서 관리합니다.

현재 배포·검증 결과와 과거 기록은 [배포·검증 안내](docs/delivery/index.md)에서 구분해 확인하세요.

## 개발자가 프로그램을 만드는 방법

FolderState는 C# / .NET 10 / WPF로 만들었습니다. 아래 명령은 Windows 11 x64에서 실행합니다. .NET SDK 버전은 `global.json`을 따릅니다. 두 도구의 현재 확인 범위는 [배포·검증 안내](docs/delivery/index.md)를 참고하세요.

```powershell
dotnet run --project tests/FolderState.Tests -c Release
powershell -NoProfile -File scripts/build.ps1
```

설치 파일은 `artifacts/release/FolderState-0.1.3-win-x64.msi`에 만들어집니다. 파일이 바뀌었는지 확인하는 SHA-256 파일도 함께 생성합니다. 설치 파일에 실행에 필요한 .NET이 포함되어 있어 사용자 PC에 따로 설치할 필요가 없습니다. 현재 Windows 사용자 계정에 설치됩니다.

Excel 추가 기능의 [설치·사용 안내](tools/ExcelSmartListCompare/docs/RC12_USER_GUIDE.md)와 [제작·배포 범위](tools/ExcelSmartListCompare/docs/ADR-0020-R12-wording-release.md)를 참고하세요. 새 소스, 제작한 XLAM, 공개된 설치 파일을 구분합니다.

문서 사이트를 확인하려면 다음 명령을 실행하세요.

```powershell
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
python scripts/check-site.py site
python -m mkdocs serve
```

## 개발 파일의 위치

```text
src/          폴더 상태 엔진, WPF 관리 화면, CLI
tests/        실제 Windows 파일시스템 통합 테스트
installer/    사용자별 MSI 정의
tools/        Excel 명단 비교 등 별도 도구
scripts/      빌드·검증 스크립트
docs/         공개 안내와 개발·배포 문서 원본
assets/       다중 해상도 상태 아이콘
```

Excel 최초 입력 자료는 [원본 보존 폴더](tools/ExcelSmartListCompare/archive/README.md)에 있습니다. 생성물은 artifacts/, bin/, obj/, site/에 두고 Git에 포함하지 않습니다. 이전 로컬 ExcelE2E-* 시험 폴더도 추적하지 않습니다.

배포 단계와 확인 결과는 [품질 기준](docs/delivery/quality.md), [검증 기록](docs/delivery/verification.md)에서 확인하세요. 제작자를 확인하는 코드 서명과 새 PC에서의 설치·업데이트·제거 검증이 끝나기 전에는 상용 정식판으로 분류하지 않습니다.
