# Excel 버전별 실기 검증

2026-11-11 KST. Windows Excel 실기 시험을 위한 패키지입니다. 확인 가능한 Windows 시험 PC가 오프라인이어서 현재 Excel 빌드별 실제 통과 결과는 0건입니다.

## 여기서 수행한 검사

- PowerShell 7.4.7/Linux에서 `tests/Test-Core.ps1` 45개 검사 통과. PowerShell 구문, 파일 형식 선택, 잠금·권한·COM 오류 분류, SHA-256 검증과 백업·복구본 보존을 검사했습니다.
- 그림 포함 BIFF8 XLS·OOXML XLSX의 파일 구조를 검사했습니다. VBA와 PNG가 든 합성 XLSM의 VBA 스트림과 이미지 바이트를 확인했습니다.
- Excel 아키텍처를 판별하는 PE 헤더 검사와 버전 수집 스크립트의 로드 검사를 Linux에서 수행했습니다.
- Excel COM 암호화·해제, 그림·개체 포함 XLS 저장, Windows NTFS의 잠금 및 파일 교체, BAT 메뉴 입력은 실기 미실행입니다.

## Windows에서 실행

Excel을 정상 종료하고 `tests\Run-ExcelCompatibility.bat`을 실행합니다. 표시된 새 시험 폴더를 확인한 후 `SYNTHETIC`을 입력합니다. 기존 문서 폴더를 지정할 필요가 없습니다.

명령으로 실행할 경우 존재하지 않는 새 폴더를 사용합니다.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-ExcelSynthetic.ps1 -EvidenceDirectory 'C:\Temp\EpsSynthetic-001'
```

| 증적 | 검증 항목 |
|---|---|
| `environment.json` | 실제 COM으로 실행한 Excel 버전, 빌드, EXCEL.EXE 파일 버전과 PE 아키텍처. Windows와 PowerShell 아키텍처, 확인 가능한 Office 제품·채널 |
| `fixture-results.csv` | Excel이 생성한 XLS·XLSX·Strict XLSX·XLSM·XLSB와 그림·도형, XLS 내 OLE 생성 시도 |
| `synthetic-results.csv` | 파일당 암호화, 이미 암호화됨, 틀린 암호 거부, 해제, 이미 평문 건너뜀. 전체 7개 합성 파일 기준 35건. VBA가 든 XLSM은 해제 후 VBA 스트림의 존재와 해시도 기록 |
| `controller\controller-results.csv` | 실제 컨트롤러를 호출해 미리보기, 승인 취소, 암호화, 공유 잠금·읽기 전용, 실패분 재시도, 해제 및 NTFS 교체 검증 |
| `interop-files.csv` | 다른 Excel 빌드에서 열어볼 합성 암호 파일의 형식, SHA-256, 생성 빌드·아키텍처 |

컨트롤러 시험은 합성 경로 안에서 승인 입력만 시험 코드로 공급합니다. BAT 메뉴에서 실제로 입력하는 시험은 별도로 수행합니다. OLE 생성이 차단된 PC는 `fixture-results.csv`에 `NotCovered`가 남습니다. 그림·개체의 종류와 존재, 셀 값·수식, VBA 프로젝트 유무는 재열기에서 검사합니다. OLE 내부 데이터와 그림의 픽셀·렌더링 동일성은 파일을 직접 확인해야 합니다. VBA 해시 차이가 있으면 코드와 동작을 별도로 비교해야 합니다.

## 판정 대상

Excel 제품과 세대, 비트 수가 다른 조합마다 독립된 결과가 필요합니다. Microsoft 365, LTSC 2024/2021, 2019/2016은 COM 주 버전이 모두 `16.0`으로 표시될 수 있습니다. About Excel에 나온 제품 이름과 `environment.json`의 빌드·아키텍처를 함께 대조합니다. [Microsoft Office 제품 버전 표](https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/install-different-office-visio-and-project-versions-on-the-same-computer)

| Excel 제품 | 검증할 조합 | 현재 |
|---|---|---|
| Microsoft 365 Apps | Windows 11, 배포 채널별 x86 / x64, 배포 중인 경우 Arm64 | 미실행 |
| Excel 2024 / Office LTSC 2024 | 실제 배포 제품별 x86 / x64 | 미실행 |
| Excel 2021 / Office LTSC 2021, 2019, 2016 | 제품 세대별 x86 / x64 | 미실행 |
| Excel 2013, 2010, 2007 | 각 세대와 해당 설치판 아키텍처. Windows PowerShell 5.1과 데스크톱 Excel 필요 | 미실행 |

각 조합에서 동일 빌드 암호화→해제를 먼저 실행합니다. 파일 교환이 필요한 두 버전은 A에서 생성한 암호 파일을 B에서 열어 해제하고, B→A도 확인합니다. 각 결과의 `interop-files.csv`로 송신 빌드와 파일 해시를 확인한 뒤, 합성 파일의 복사본만 별도 폴더에 넣어 수신 버전에서 `ExcelPassword.bat` 4번으로 해제합니다. 합성 암호는 `EpsTest-42!`입니다. 수신 버전의 `environment.json`, 해제 `results.csv`, 그림 확인 결과를 함께 보관합니다.

Strict XLSX 생성 시험은 Excel 2013 이상에서 실행합니다. Excel 2010은 Strict 읽기와 쓰기가 다릅니다. Strict를 저장할 수 없는 Excel은 다른 형식으로 바꾸지 않고 원본을 보존해야 합니다. 이 경우에도 실제 실패 기록과 원본 해시를 확인해야 합니다. Excel 95 등 BIFF8보다 이전의 XLS는 현재 보존 대상 형식에 포함하지 않습니다. [Microsoft Office 팀의 Strict 지원 안내](https://web.archive.org/web/20130122113810/http://blogs.office.com/b/office-next/archive/2012/08/13/the-new-office-expands-file-format-options.aspx) · [XlFileFormat](https://learn.microsoft.com/en-us/office/vba/api/excel.xlfileformat)

기존 업무 파일에 적용할 때는 대상 경로와 백업 위치를 확인하고 명시적으로 승인하는 기존 실행 절차를 사용합니다.
