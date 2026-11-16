# ExcelPasswordSafe 1.1.0

Excel 파일의 **열기 암호**를 설정하거나 제거하는 Windows용 독립 도구입니다. 하위 폴더를 포함합니다. 시트 보호·통합문서 구조 보호·쓰기 암호 해제 도구가 아닙니다.

## 시작하기

1. ZIP 전체를 풀고, Excel을 모두 **정상 종료**합니다. 관리자 권한은 필요하지 않습니다.
2. `ExcelPassword.bat`을 실행합니다. 1/2번은 대상 목록만 확인합니다.
3. 실제 처리는 3/4번을 선택합니다. 대상 폴더와 백업 폴더를 입력합니다. 백업 폴더는 대상 밖이어야 합니다. 생략하면 `대상폴더.ExcelPasswordSafe\실행ID`를 사용합니다.
4. 화면의 **모든 대상 경로와 백업 경로**, `plan.csv`를 확인합니다. 정확한 `APPLY-실행ID`를 직접 입력해야 작업이 시작됩니다. 암호는 이후 숨김 입력합니다. 취소하려면 다른 문자열을 입력합니다.
5. 우선 별도로 복사한 소량의 대표 파일에서 실행하고 Excel 화면으로 그림·개체·매크로를 확인합니다. 검증 범위와 한계는 `VALIDATION.md`를 보세요.

**제공된 도구를 이용해 실제 업무 파일을 실행한 사실은 없습니다.** 대상·백업 목록과 명시적 승인 없이는 실제 파일을 교체하지 않습니다. 미리보기 뒤 실제 실행 시에는 새 목록을 만들고 다시 승인합니다.

Windows PowerShell 5.1과 데스크톱 Microsoft Excel이 필요합니다. 로컬 고정 NTFS 드라이브의 하위 폴더만 지원합니다. UNC·이동식 드라이브·네트워크 드라이브·전체 드라이브 루트는 거부합니다. OneDrive 등의 동기화 폴더는 동기화를 일시 정지한 별도 로컬 복사본으로 시험하세요. 실행 중 Excel을 새로 열지 마세요.

## 형식과 암호 정책

| 확장자 | 허용 실제 FileFormat | 처리 |
|---|---|---|
| `.xls` | 56, Excel 97–2003 BIFF8 | 원래 형식 56 유지 |
| `.xlsx` | 51 또는 Strict 61 | 확인된 실제 값을 그대로 유지 |
| `.xlsm` | 52 | 형식 및 VBA 유무 비교 |
| `.xlsb` | 50 | 바이너리 형식 유지 |

확장자만 보고 변환하지 않습니다. 실제 형식이 맞지 않거나 Excel 95 등 구형 XLS 형식이면 실패로 기록하고 원본을 유지합니다. CSV나 셀 복사 방식으로 재생성하지 않고 Excel 자체 `SaveAs`를 사용합니다. `SaveAs`의 FileFormat과 Password는 서로 다른 인수입니다.

모든 형식의 공통 호환 범위로 새 암호는 1~15자입니다. 현재 암호와 새 암호는 명령줄·BAT·CSV에 넣지 않습니다. 작업 전달 파일에는 현재 Windows 사용자에게 묶인 DPAPI 암호문을 사용하며 작업 후 삭제합니다. Excel COM 호출 중에는 메모리에 평문이 잠시 필요합니다.

한 번의 실행에는 기존 암호 하나를 적용합니다. 암호가 여러 종류라면 폴더나 실패 목록을 나누세요. 암호화 모드에서 기존 암호로 열린 암호 파일은 `AlreadyEncrypted`로 건너뜁니다. 암호 변경 기능은 제공하지 않습니다. 암호 해제 모드에서 평문 파일은 `AlreadyUnencrypted`로 건너뜁니다. 기존 암호를 모르면 암호화 파일도 열기에 실패할 수 있으며, 이때는 암호 문제로 **단정하지 않습니다**.

## 처리 순서

- 승인한 시점의 SHA-256을 기록하고, 원본에 쓰기를 허용하지 않는 읽기 핸들을 유지합니다. Excel 잠금 파일이나 읽기 전용 속성도 확인합니다.
- 원본 바이트를 `originals\상대경로`에 새 파일로 백업하고 해시를 확인합니다. 백업 실행 폴더의 상속 권한은 끊고 현재 사용자와 SYSTEM에만 권한을 줍니다. 백업은 자동 삭제하지 않습니다.
- 원본과 같은 폴더에 `.eps-…-source.확장자` 작업 복사본을 만듭니다. 링크 기준 폴더 변경을 줄이기 위한 조치입니다. 원본 이름 자체에 의존하는 참조까지 동일함을 보증하지는 않습니다.
- 별도 PowerShell STA 프로세스가 새 Excel 인스턴스로 복사본을 열고 `.eps-….확장자`로 저장합니다. 매크로 자동 실행·이벤트·링크 갱신을 끕니다. 계산 모드는 Excel이 파일을 열 때 적용하는 설정을 따릅니다. 자동 복구 열기 옵션을 사용하지 않습니다.
- 결과를 닫고 다시 열어 FileFormat, HasPassword, VBA 유무, 시트 이름·종류·표시 상태, UsedRange 범위와 수식/상수 해시, 도형·그림·개체 이름/종류 목록을 비교합니다. 암호화는 임의의 다른 암호가 Excel의 정상 암호 오류로 거절되는지도 확인합니다.
- 결과·원본·백업 해시가 유지되는지 다시 확인하고 `File.Replace`로 교체합니다. 삭제 후 이동 방식으로 우회하지 않습니다. 교체 전 원본은 같은 폴더의 `.eps-….recovery`에도 남깁니다. 결과·recovery 해시를 확인해야 성공입니다.

## Excel 보호와 장애 처리

기존 Excel이 실행 중이면 처리 시작을 거부합니다. 사용자의 Excel을 연결해 재사용하거나 강제 종료하지 않습니다. 도구가 만든 것으로 확인한 인스턴스에만 정상 `Quit()`을 호출합니다. Excel 종료가 멈추거나 COM 호출이 응답하지 않으면 제한시간 뒤 **자신이 시작한 PowerShell 자식만 종료**하고 나머지 파일은 `SystemCircuitOpen`으로 기록합니다. Excel은 남아 있을 수 있으므로 사용자가 직접 확인하고 정상 종료해야 합니다.

COM 서버 오류는 새 작업 프로세스로 제한적으로 재시도합니다(기본 최대 2회). 등록/라이브러리 오류는 즉시, 반복 COM 오류는 차단 장치로 중단합니다. 단순 파일 오류는 해당 파일만 실패하고 다음 파일로 진행합니다. 디렉터리 열거 자체가 실패하면 누락된 대상을 승인받지 않도록 실행 전 중단하며 `EnumerationFailed`를 기록합니다. 경로의 재분석 지점은 거부하고 하위 junction/symlink는 탐색하지 않습니다.

문서 또는 VBA 프로젝트에 서명된 파일, 공유 통합문서, 쓰기 예약 파일은 건너뜁니다. 발견된 Excel 4.0 매크로 시트는 처리하지 않습니다. Excel 보안 경고가 COM 설정으로 모두 억제되는 것은 아니므로 이 경우 제한시간에 도달할 수 있습니다. Office 설치·레지스트리·보안 정책은 변경하지 않습니다.

## 로그와 재시도

실행 폴더의 `results.csv`에는 시간, 작업 방식, 전체 경로, 원본 해시, 백업, 임시 경로, 시도 횟수, 상태, 오류 분류, 단계, HRESULT 체인, 원인 메시지, 결과 해시를 기록합니다. 성공·건너뜀·실패를 구분합니다. 잠금/권한은 해당 Windows 오류가 확인될 때만 확정합니다.

| 주요 분류 | 의미/대응 |
|---|---|
| `AlreadyEncrypted` / `AlreadyUnencrypted` | 열린 파일의 암호 상태 확인 후 건너뜀 |
| `FileInUse` | Windows 공유 위반 또는 Excel 소유 파일 확인. 정상 종료 후 재시도 |
| `AccessDenied` / `ReadOnlyAttribute` | 권한 또는 파일 속성 확인 |
| `OpenFailedPossiblePasswordOrCorruption` | 암호·손상·보안 제한 등 열기 원인이 불명확. 실제 Excel로 확인 |
| `ComRegistrationOrLibrary` | LIBRARYNOTREGISTERED, TYPE_E_CANTLOADLIBRARY, 클래스 등록 오류 등. Excel 설치 복구/버전 점검 |
| `ComServerError` | RPC_E_SERVERFAULT, RPC 서버 중단, 연결 해제, 호출 거절 등 |
| `ValidationFailed` | 다시 열기/암호/내용 비교 실패. 원본 교체 안 함 |
| `SourceChanged` / `ChangedSinceRetryLog` | 승인 이후 변경 또는 재시도 로그 이후 변경 등 |
| `WorkerTimeout` / `ExcelStillRunning` | Excel 상태를 직접 확인. 남은 임시 파일을 조사 |
| `CommitUncertain` | 교체 전후 판단이 불확실. **자동 재시도 금지**, 원본·백업·recovery 해시 조사 |

5번 메뉴에서 이전 `results.csv`를 선택하고 기존 작업 방식과 원래 대상 폴더를 입력하면 **최종 상태가 실패인 파일만** 대상으로 삼습니다. 성공·건너뜀은 제외하며 새 실행 폴더·백업·승인을 다시 사용합니다. 이전 로그의 원본 해시와 다르면 자동 처리하지 않습니다. 삭제되거나 대상 밖으로 이동한 파일은 새 탐색에 나오지 않습니다. 이 경우 이전 로그와 계획을 직접 대조하세요. 잠금 등 사전 검사에서 실패한 파일은 원인 해소 후 이 기능으로 재시도합니다.

갑작스런 종료 시 `*.state.json`에서 `Validated`, `CommitIntent`, `Committed`와 해시를 확인할 수 있습니다. `CommitIntent`만 남은 경우 자동 복구하지 않습니다. 계획 및 로그가 남은 실행에 중복 작업하기 전에 상태를 조사하세요.

## 백업과 복구

암호화 전 백업은 **암호가 없는 원본일 수 있습니다**. 접근을 제한해 보관하고 필요 시 사용자가 정리하세요. 같은 폴더의 작업 복사본과 임시 결과는 처리 중 존재합니다. 오류/시간 초과 시 남을 수 있으며 해당 폴더의 접근 정책도 적용됩니다. 특히 실패한 암호 해제 결과는 평문일 수 있습니다. Excel이 정상 종료된 뒤 경로와 상태를 확인해 정리하세요. `.recovery`는 원본 바이트를 가진 파일이며 자동 삭제하지 않습니다.

복구할 때는 Excel을 정상 종료하고 백업 SHA-256을 `plan.csv`/`results.csv`와 대조합니다. 현재 결과도 별도 보관한 뒤, **교체할 대상과 사용할 백업을 확인하고 승인한 후** 해당 원본 백업을 원래 경로로 복사합니다. 이 도구는 자동 복구/자동 롤백을 실행하지 않습니다.

## PowerShell에서 사용

```powershell
# 미리보기
.\ExcelPassword.ps1 -Mode Encrypt -Root 'C:\Data\Excel'
# 목록 확인 및 직접 승인 후 실행
.\ExcelPassword.ps1 -Mode Encrypt -Root 'C:\Data\Excel' -Execute
# 암호 해제
.\ExcelPassword.ps1 -Mode Decrypt -Root 'C:\Data\Excel' -Execute
# 실패분 재시도: 새 목록과 백업을 보여주고 다시 승인
.\ExcelPassword.ps1 -Mode Encrypt -Root 'C:\Data\Excel' -RetryLog 'C:\Logs\results.csv' -Execute
```

BAT은 해당 PowerShell 프로세스에만 ExecutionPolicy Bypass를 적용합니다. 시스템 정책을 변경하지 않습니다. 조직 정책으로 실행이 금지된 환경에서는 담당자 기준을 따르세요. 종료 코드는 0=완료/미리보기, 1=파일별 실패 포함, 2=취소, BAT의 3=초기 실행 오류입니다.

## 구성과 근거

- `ExcelPassword.bat`: 메뉴와 경로 입력
- `ExcelPassword.ps1`: 대상 검토·승인·백업·재시도·교체
- `ExcelPassword.Worker.ps1`: 원본 교체 권한이 없는 작업 로직(임시 파일만 기록)
- `Common.ps1`: 공통 형식·검증·오류·교체 함수
- `tests/Run-ExcelCompatibility.bat`: 버전·빌드 수집과 Windows Excel 합성 시험
- `VALIDATION.md`: 실제 수행 결과 및 미검증 범위

여기서 “원본 교체 권한이 없다”는 작업 로직의 범위입니다. 운영체제에서 별도의 권한 격리 토큰으로 실행하는 것은 아닙니다.

참고: [Workspace 공존 검증 스크립트](https://github.com/prozac0401/Workspace/blob/main/scripts/test-excel-coexistence.ps1), 확인한 blob SHA `896787ca6bdcc09ae84c15aa5baa71de0a4b9d88`. 시작 전 Excel 확인, 기존 설치/설정 보존 원칙을 참고했으며 해당 저장소에 새 기능을 반영하지는 않았습니다.

Microsoft 공식 문서: [Workbook.SaveAs](https://learn.microsoft.com/en-us/office/vba/api/Excel.Workbook.SaveAs), [XlFileFormat](https://learn.microsoft.com/en-us/office/vba/api/excel.xlfileformat), [Workbooks.Open](https://learn.microsoft.com/en-us/office/vba/api/excel.workbooks.open), [AutomationSecurity](https://learn.microsoft.com/en-us/office/vba/api/excel.application.automationsecurity).
