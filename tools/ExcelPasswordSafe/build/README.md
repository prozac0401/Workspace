# ExcelPasswordSafe MSI 만들기

제품 표시 버전은 **2**이며 MSI 내부 버전은 **2.0.0**입니다. 코드 서명 상태와 실제 검증 범위는 빌드·배포 기록에 별도로 남깁니다.

Windows 10 2004 이상 x64, Windows PowerShell 5.1, .NET Framework 4.8의 C# 컴파일러와 WiX Toolset 4가 필요합니다. 스크립트는 저장소의 `.tools/wix/wix.exe`를 기본 사용합니다. 사용자는 개발 SDK나 WiX를 설치하지 않습니다. 프로그램을 실행할 PC에는 데스크톱 Microsoft Excel이 필요합니다.

저장소 루트에서 다음을 실행합니다. Excel 실기 시험과 동시에 실행하지 마세요.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/ExcelPasswordSafe/build/build.ps1
```

실행마다 `artifacts/excel-password-safe/build-버전-시각-ID`를 새로 만듭니다. 기존 결과를 삭제하거나 덮어쓰지 않습니다. 앱 컴파일 → 핵심 시험 → 격리된 컨트롤러 장애 시험 → 폴더 일괄 처리 시험 → 앱 시험 → 위자드 재시도 계약 시험 → WPF 화면 렌더링 → MSI 생성 → MSI 표 검사 → 내장 파일 추출·해시 비교를 실행합니다. 빌드 도중 소스가 바뀌면 실패합니다. 실제 Excel 시험은 별도이며 Excel 실행 상태를 충돌시키지 않도록 순서대로 수행합니다.

`build-result.json`에는 실제 결과와 미검증 범위를 기록합니다. `source-sha256.txt`, `msi-verification.json`, `*.log`, `ui-smoke`, `app-tests`, `wizard-tests`, `batch-tests`는 로컬 검증 자료입니다. 설치 파일에는 자물쇠 아이콘을 내장한 실행 파일·실행 설정·런타임 스크립트 4개(`BatchEngine.ps1` 포함)·사용 안내만 포함합니다. 업무 파일, 테스트 파일, 암호, 로그는 넣지 않습니다.

기본 내부 버전은 2.0.0이며 결과 파일은 `ExcelPasswordSafe-2-win-x64.msi`입니다. 표시 버전은 내부 버전의 정수 주 버전을 사용합니다. `-SkipTests`는 패키지 구성만 확인할 때 사용합니다. 그 결과를 시험 통과 패키지로 표시하지 않습니다. `-Version 2.0.1`은 별도 버전의 MSI를 만듭니다. 실행 파일과 내장 매니페스트의 버전도 함께 지정합니다. 이전 산출물은 새 빌드가 덮어쓰지 않습니다. WiX가 별도 위치에 있으면 `-Wix 'WiX 실행 파일의 전체 경로'`를 지정합니다.

## 설치하지 않고 MSI 검사하기

```powershell
powershell.exe -NoProfile -File tools/ExcelPasswordSafe/installer/verify-msi.ps1 -MsiPath '실제 MSI 경로'
```

현재 사용자 설치, 파일 메뉴 4개·선택 폴더 메뉴 1개·폴더 배경 메뉴 1개와 각 메뉴의 3개 하위 명령(총 18개), 인수 인용, 기본 파일 연결을 건드리지 않는 등록 범위, 정확한 파일 목록, x64 패키지와 일반 사용자 실행 표시를 확인합니다. 파일 명령은 `--file "%1" --mode Encrypt/Decrypt/ChangePassword`로 선택한 작업을 직접 전달합니다. 폴더 명령은 `Directory` 선택 항목에 `%1`, `Directory\Background`의 빈 공간 메뉴에 `%V\.`를 인용하여 전달합니다. 끝의 `\.`는 같은 폴더를 뜻하며 드라이브 루트의 마지막 역슬래시가 닫는 따옴표를 이스케이프하지 않게 합니다. 드라이브·모든 파일 항목에는 등록하지 않습니다. 같은 ICO를 실행 파일·MSI 화면·앱 제거 목록·시작 메뉴 바로가기에 사용합니다. 설치 작업에 PowerShell을 실행하는 사용자 지정 동작은 없습니다. 검사는 1.3.0 이전 패키지의 파일 메뉴·6개 payload도 구분하여 읽으므로 업그레이드 시험에서 이전 MSI를 그대로 사용할 수 있습니다.

## 설치 위치 화면 검증

신규 설치 화면은 경로 입력과 기본 MSI 폴더 찾아보기를 제공합니다. 기본값은 `%LocalAppData%\Programs\ExcelPasswordSafe`입니다. 설치·폴더 선택 버튼의 `SetTargetPath` 이벤트를 진행 이벤트보다 먼저 실행하고 한국어 경로 오류 대화상자를 제공합니다. 업그레이드·복구에서는 저장된 위치를 유지하며 새 위치로 이동하려면 먼저 제거한 뒤 신규 설치합니다.

`verify-msi.ps1`은 경로 컨트롤·오류 대화상자·검증 이벤트 순서·아이콘·기존 위치 유지 조건을 검사합니다. 조용한 설치 수명주기 시험은 경로 화면을 조작하지 않습니다. 실제 찾아보기, 잘못된 경로, 쓰기 불가 경로에서의 차단, 취소 후 복귀는 전체 MSI UI에서 별도로 확인하고 결과를 기록합니다. 경로 검증을 위해 PowerShell이나 별도 실행 파일을 호출하지 않습니다.

구현 근거: Microsoft [SetTargetPath](https://learn.microsoft.com/en-us/windows/win32/msi/settargetpath-controlevent), [Error dialog](https://learn.microsoft.com/en-us/windows/win32/msi/error-dialog), [설치 위치 변경 제약](https://learn.microsoft.com/en-us/windows/win32/msi/changing-the-target-location-for-a-directory).

## 깨끗한 사용자 계정에서 설치 수명주기 시험하기

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/ExcelPasswordSafe/installer/test-installer.ps1 -MsiPath '실제 MSI 경로'
# 더 높은 버전의 별도 패키지를 준비했을 때:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/ExcelPasswordSafe/installer/test-installer.ps1 -MsiPath '현재 MSI 경로' -UpgradeMsiPath '더 높은 버전 MSI 경로'
```

기존 ExcelPasswordSafe 설치·메뉴·등록 정보·기본 설치 폴더가 하나라도 있으면 시험을 거부합니다. 시험은 한글과 공백을 포함한 `artifacts/excel-password-safe/installer-시각-ID/사용자 지정 경로`에 설치하고 끝나면 제거합니다. 다른 도구의 설치 상태나 파일 연결은 변경하지 않습니다.

1.4.0에서 2로 올리는 시험은 보존된 1.4.0 MSI를 `-MsiPath`, 새 MSI를 `-UpgradeMsiPath`로 전달합니다. 이전 버전에는 배경 메뉴가 없어야 하고, 업그레이드 후 세 배경 명령과 확장자별 파일 하위 명령 3개가 추가되고 이전 파일 메뉴의 루트 `command`가 제거되어야 합니다. 복구·업그레이드 명령에 다른 위치를 지정해도 저장한 기존 설치 위치를 유지하는지 확인합니다. 제거 시 자기 메뉴만 없어져야 합니다. 기존 사용자가 설치한 제품을 시험 스크립트가 제거하거나 시험 설치로 대체하지 않습니다.

기본값은 배포 MSI 그대로 설치, 설치된 앱의 화면 렌더링, 누락 실행 파일 복구, 선택한 경우 업그레이드·다운그레이드 차단, 제거, 재설치를 확인합니다. 합성 파일·백업의 해시와 기본 파일 연결을 전후 비교합니다. 실제 탐색기 우클릭과 Excel 데이터 처리는 별도 시험이며 이 스크립트가 통과로 표시하지 않습니다.

오류 주입은 `-RollbackMode DeferredBeforePublish` 또는 `-RollbackMode LateAfterPublish`를 명시한 별도 시험입니다. 서로 다른 ProductCode·PackageCode를 가진 시험 MSI에만 실패 동작을 넣습니다. 전자는 파일·메뉴 기록 이후 제품 등록 전, 후자는 제품 등록까지 실행한 뒤 실패시킵니다. 실제 FileCopy·RegAddValue 실행과 파일·메뉴·MSI 등록의 복구를 각각 검사합니다. 배포 MSI에는 오류 주입 동작이 없습니다. 이 두 실패 시점은 다른 검증 항목이며 한쪽의 통과로 다른 쪽을 대체하지 않습니다.

2026-11-16의 늦은 오류 주입 시험에서는 파일·메뉴가 제거된 뒤 MSI 등록이 남았습니다. 해당 실패와 정상 설치 수명주기 결과를 따로 기록합니다. 문제가 남은 시험 제품은 Windows Installer의 제거 기능으로 정리하며 레지스트리 권한을 바꾸지 않습니다. 설치 실패 후 등록만 남은 사용자는 같은 MSI로 제거한 뒤 재설치해야 합니다.

검증 로그와 `installer-results.json`은 해당 시험 폴더에 보존합니다. 오류가 나면 로그를 확인합니다. 설치된 업무 환경을 정리하거나 탐색기·Excel을 강제 종료하지 않습니다.
