# Workspace

**필요한 자료를 찾고, 다음에 할 일을 확인하는 방법을 안내합니다.** 파일과 메일 정리 방법과 아홉 가지 업무 도구의 설치·사용법을 볼 수 있습니다.

[안내 사이트](https://prozac0401.github.io/Workspace/)에서 필요한 상황을 고르세요. 처음 시작한다면 [업무 하나로 시작하기](docs/getting-started.md)를 보세요. 명단 비교나 제출물 정리에 도구를 쓰려면 [교육 업무에 도구 써 보기](docs/education-operations.md)를 따라 해 보세요.

업무 정리 방법은 **제안**입니다. 저장 위치, 자료를 볼 수 있는 사람, 보관 기간은 회사에서 정한 기준을 따릅니다. 공개 예시는 가짜 자료로 설명합니다.

## 프로그램 고르기

기존 도구의 공개 배포 목록은 **2026년 10월 5일**에 확인했습니다. 오피스 자동화 도구 안내는 **2026년 10월 6일의 0.3.1**을 기준으로 추가했습니다. 기존 도구의 설치 파일에는 제작자의 전자 서명이 없습니다. 오피스 자동화 도구는 자체 서명을 사용합니다. 설치 전에 사용할 PC와 알려진 제한을 확인하세요.

| 하고 싶은 일 | 최신 안내 | 공개 파일 |
|---|---|---|
| 폴더에 진행 상태 표시하기 | [FolderState 0.1.3](docs/tools/folderstate/index.md) | [설치 파일과 배포 안내](https://github.com/prozac0401/Workspace/releases/tag/folderstate-v0.1.3) |
| 두 명단의 차이와 중복 개수 찾기 | [Excel 명단 비교 0.2.1](docs/tools/excel-list-compare/index.md) | [설치 파일과 배포 안내](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.1) |
| Excel에서 보이는 칸만 새 파일로 만들기 | [선택범위 내보내기 0.1.0-rc.11 시험용](docs/tools/excel-selection-export/index.md) | [설치 파일과 배포 안내](https://github.com/prozac0401/Workspace/releases/tag/excel-selection-export-v0.1.0-rc.11) |
| 폴더 속 파일을 목록으로 보고 필요한 파일 모으기 | [File List to Excel 1.2.0](docs/tools/file-list-to-excel/index.md) | [설치 파일과 배포 안내](https://github.com/prozac0401/File-List-To-Excel/releases/tag/v1.2.0) |
| 숨긴 행을 건너뛰어 한 열에 값 넣기 | [보이는 칸 붙여넣기](docs/tools/visible-cells-paste/index.md) | [배포 목록에서 도구 이름으로 찾기](https://github.com/prozac0401/Workspace/releases) |
| 복사한 그림을 파일로 저장하기 | [그림 복사·저장 0.2.1](docs/tools/image-copy-save/guide.md) | [설치 파일과 배포 안내](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.1) |
| 보던 문서나 웹페이지 다시 열기 | [업무 책갈피 0.2.8](docs/tools/bookmark/index.md) | [설치 파일과 배포 안내](https://github.com/prozac0401/BookMark/releases/tag/v0.2.8) |
| 다시 받은 파일에 원래 이름 주기 | [다운로드 이름 유지 0.2.0 시험용](docs/tools/download-version-manager/index.md) | [설치 파일과 배포 안내](https://github.com/prozac0401/Workspace/releases/tag/download-version-manager-v0.2.0) |
| Excel 파일 합치기·나누기와 양식 문서 만들기 | [오피스 자동화 도구 0.3.1 시험용](docs/tools/office-automation/index.md) | [단일 EXE](https://github.com/prozac0401/Workspace/releases/download/office-automation-tools-v0.3.1/OfficeAutomationTools.exe) · [ZIP·배포 안내](https://github.com/prozac0401/Workspace/releases/tag/office-automation-tools-v0.3.1) |

오피스 자동화 도구(Office Automation Tools)는 비공개 ProbPacker 저장소에서 개발합니다. 같은 EXE·ZIP을 Workspace의 공개 릴리스에서 받도록 연결합니다. Python 설치 없이 EXE를 바로 실행하지만 Excel과 템플릿용 Word·PowerPoint는 필요합니다. 이번 EXE의 전체 화면·생성·종료 재검증과 임시 폴더 삭제 경고의 해결 확인은 남아 있습니다. [받기·사용 안내](docs/tools/office-automation/index.md)에서 원본 행 확인, 분석, 실행, 결과 확인과 세 기능의 상세 방법을 설명합니다.

보이는 칸 붙여넣기의 확인한 최신 배포 파일은 0.1.2입니다. 설치 안내는 기존 요청에 따라 배포 목록에서 파일을 고르는 방식으로 제공합니다.

시험용 두 도구는 정식 배포 전 단계입니다. 선택범위 내보내기는 32비트 Excel 등 확인하지 못한 환경이 남아 있습니다. 다운로드 이름 유지는 설치 실패 뒤 설치 기록이 남아 다시 설치하지 못할 수 있어 일상 업무 사용을 아직 권하지 않습니다.

FolderState 0.1.3과 업무 책갈피 0.2.8은 이전에 배포한 같은 파일을 정식 배포로 표시한 것입니다. 이 표시 변경 때문에 다시 설치할 필요는 없습니다. 회사 사용 승인과 모든 PC에서의 동작 확인은 별개입니다.

## 교육 업무에서 써 보기

[일곱 가지 교육 업무 예시](docs/education-operations.md)에서 지금 필요한 장면 하나를 고르세요. 가짜 자료를 준비하는 방법, 실행 순서, 기대 결과, 주의할 점을 함께 적었습니다. 도구를 모두 설치할 필요는 없습니다.

- [자료를 둘 곳 정하기](docs/policies/workspace.md)
- [반복 업무의 기본 폴더와 일정 준비하기](docs/policies/kits.md)
- [파일과 메일 정리하기](docs/policies/files-email.md)
- [끝난 업무 보관과 자료 보호](docs/policies/archive-security.md)
- [놓치는 일과 반복 작업 줄이기](docs/policies/work-efficiency.md)

## 문서와 확인 기록

편집할 문서는 docs/에 있습니다. 공개 사이트에는 업무 안내, 가짜 자료 예시, 허용한 프로그램의 설치·사용 안내만 올립니다. 개발 문서와 과거 확인 기록은 저장소에서 관리합니다.

[최신 버전과 확인 기록](docs/delivery/index.md) · [이번 문서 수정과 게시 기록](docs/delivery/document-review-20261005.md)

[폴더 상태 도구의 최초 명세](01_Windows_Explorer_폴더상태도구_명세.md) · [파일·폴더·메일 정리의 최초 설계안](02_사무실PC_파일폴더이메일_정리설계안.md)

## 개발자가 프로그램을 만드는 방법

FolderState는 C# / .NET 10 / WPF로 만들었습니다. 아래 명령은 Windows 11 x64에서 실행합니다. .NET SDK 버전은 `global.json`을 따릅니다. 각 도구의 현재 확인 범위는 [배포·검증 안내](docs/delivery/index.md)를 참고하세요.

```powershell
dotnet run --project tests/FolderState.Tests -c Release
powershell -NoProfile -File scripts/build.ps1
```

설치 파일은 `artifacts/release/FolderState-0.1.3-win-x64.msi`에 만들어집니다. 파일이 바뀌었는지 확인하는 SHA-256 파일도 함께 생성합니다. 설치 파일에 실행에 필요한 .NET이 포함되어 있어 사용자 PC에 따로 설치할 필요가 없습니다. 현재 Windows 사용자 계정에 설치됩니다.

Excel 추가 기능의 [설치·사용 안내](tools/ExcelSmartListCompare/docs/STABLE_USER_GUIDE.md)와 [제작·배포 범위](tools/ExcelSmartListCompare/docs/STABLE_RELEASE_REPORT.md)를 참고하세요. 새 소스, 제작한 XLAM, 공개된 설치 파일을 구분합니다.

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

배포 단계와 확인 결과는 [품질 기준](docs/delivery/quality.md), [검증 기록](docs/delivery/verification.md)에서 확인하세요. 사용자 요청에 따른 정식 릴리스 채널과 코드 서명·회사별 도입 승인은 구분합니다. 확인하지 않은 환경과 상용 인수 조건은 각 검증 기록에 남깁니다.
