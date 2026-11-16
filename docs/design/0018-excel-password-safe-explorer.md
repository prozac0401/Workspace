# ADR-0018 · Excel 열기 암호를 탐색기에서 관리

상태: 채택 — 이번 로컬 구현의 설계 결정이며 조직 배포 승인을 뜻하지 않음  
날짜: 2026-11-16  
결정 담당: 도구 개발 담당  
관련 요구사항: [REQ-EPS-001~010](../tools/excel-password-safe/specification.md)  
적용 정책: [추가 도구 개발 기준](../policies/tools.md), [정책 문서 작성 규칙](../policies/documentation.md)  
대체 관계: 기존 ADR 대체 없음. 첨부 1.1.0은 원본으로 보존

## 맥락

첨부 ExcelPasswordSafe 1.1.0은 폴더를 지정하는 PowerShell 메뉴에서 암호 설정·해제를 수행한다. 사용자는 탐색기의 파일 우클릭을 시작점으로 삼고 암호 변경도 지원하는 간결한 화면과 MSI를 요청했다. 암호 해제·변경에는 현재 암호가 필요하며 기존 원본 백업·검증·복구 계약도 유지해야 한다.

## 결정

확장자별 HKCU 정적 메뉴 `Excel 암호 관리` 하나로 독립 WPF 앱을 실행한다. `MultiSelectModel=Single`로 파일 하나만 대상으로 한다. WPF 앱은 .NET Framework 4.8을 사용하고 Windows PowerShell 5.1 엔진과 별도 STA Excel 작업 프로세스를 호출한다. MSI는 현재 사용자에게 앱과 메뉴를 함께 설치한다. Windows 11에서는 `더 많은 옵션 표시`를 사용한다.

한 창에서 설정·해제·변경을 선택한다. 현재·새 암호를 구분하고 새 암호 확인을 받는다. 암호를 메뉴 명령줄에 넣지 않는다. 현재 사용자 DPAPI 암호문과 승인한 원본 SHA-256을 접근 제한된 실행 폴더로 전달한다. 원본 교체는 엔진만 수행하며, Excel 작업 프로세스는 임시 복사본과 결과만 다룬다. 이 구분은 코드 책임 경계이며 운영체제의 별도 권한 격리는 아니다.

실제 형식과 파일 내용을 최대한 유지하기 위해 Excel 자체 `SaveAs`를 사용한다. 백업·의미 비교·재열기·암호 거절 확인 후 원자 교체하며 실패 시 자동 복구하지 않는다. 앱 제거는 프로그램·자기 메뉴만 대상으로 하고 사용자 백업을 보존한다.

Windows PowerShell 5.1의 한글 경로를 유지하도록 JSON을 UTF-8로 명시해서 읽는다. Excel `Workbooks.Open`은 읽기 전용·암호·링크 갱신 금지 인수를 명시하고 마지막 선택 인수 `CorruptLoad`는 생략한다. Microsoft가 문서화한 생략 기본값은 `xlNormalLoad`이며 개체 모델 호출에서 복구를 시도하지 않는다. 복구·데이터 추출 방식으로 재시도하는 변경이 아니다. 실제 호출 호환성 결과는 검증 기록에 남긴다. [Microsoft Workbooks.Open](https://learn.microsoft.com/en-us/office/vba/api/excel.workbooks.open)

## 검토한 대안

| 대안 | 장점 | 이번 선택에서 제외한 이유 |
|---|---|---|
| 메뉴 세 개에 각각 설정·해제·변경 등록 | 한 번에 작업 선택 | Explorer 메뉴가 늘어나고 암호·백업 확인 화면은 여전히 필요 |
| Windows 11 첫 메뉴용 COM 확장 | 첫 우클릭에서 바로 표시 | 셸 내부 모듈·패키지 등록 수명주기와 검증 범위가 커짐. 요청은 첫 메뉴를 별도 요구하지 않음 |
| 독립 파일 형식 라이브러리로 재저장 | Excel 설치 불필요 | 기존 XLS/XLSM/XLSB·개체 보존 계약을 새로 입증해야 함 |
| 폴더 재귀 일괄 UX 유지 | 여러 파일 한 번에 처리 | 파일 우클릭의 명확한 범위와 맞지 않음. 원본 1.1.0에 별도 보존 |

## 영향과 이행

선택 파일 하나를 미리 확인한 뒤 작업을 실행한다. 암호 설정·변경의 새 암호는 Excel SaveAs 호환 계약에 따라 1~15자다. 실행 전 기존 Excel을 정상 종료해야 한다. 로컬 고정 NTFS, 정확한 실제 파일 형식과 허용 보안 상태로 범위를 제한한다.

원본 ZIP과 최초 요청을 보존하고 새 런타임·앱·설치 소스를 별도 디렉터리에 둔다. 기존 정책·사용자 파일·다른 도구 등록을 변경하지 않는다. 이번 문서와 패키지 제작은 공개 사이트·릴리스 게시와 별개다. 회사 승인, 코드 서명 주체와 대규모 배포 방식은 미결정이다.

## 실패와 복구

승인 이후 원본·백업·임시 결과가 달라지거나 Excel 검증이 실패하면 교체를 막는다. 뮤텍스와 파일 공유 모드로 중복 쓰기를 제한한다. 취소는 교체 진입 전까지 반영하며 이미 시작된 교체는 결과 확인까지 마친다.

프로세스 중단·제한시간 초과는 원본과 복구 자료를 남긴다. 교체 결과가 불확실하면 성공이나 원본 미변경으로 단정하지 않는다. 현재 파일과 백업의 해시를 조사하여 사용자가 복원 대상을 정한다. 원본이 평문이었다면 백업도 평문이며 임시 결과에도 평문이 남을 수 있다.

## 검증

코어 실패·동시 실행·중단·교체 시험, 합성 Excel 설정·변경·해제 시험, WPF 렌더, MSI 구성·설치·복구·제거를 독립 판정한다. 실제 Explorer 클릭과 각 Excel 버전별 검증은 자동 검사와 구분한다. [실제 결과](../delivery/excel-password-safe-20261116.md)가 없는 항목은 미검증으로 유지한다.

근거: [Microsoft 정적 메뉴 선택](https://learn.microsoft.com/en-us/windows/win32/shell/shortcut-choose-method), [선택 모델](https://learn.microsoft.com/en-us/windows/win32/shell/how-to-employ-the-verb-selection-model), [Workbook.SaveAs](https://learn.microsoft.com/en-us/office/vba/api/excel.workbook.saveas), [AutomationSecurity](https://learn.microsoft.com/en-us/office/vba/api/excel.application.automationsecurity).
