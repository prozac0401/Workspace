# ExcelPasswordSafe · 최초 요청과 첨부 원본

도구 ID: ExcelPasswordSafe · 기록일: 2026-11-16  
상태: 요구 근거 보존 · 책임: 도구 개발 담당

## 사용자 요청

아래는 첨부 파일과 함께 받은 요청이다. 원문의 표현을 보존한다.

> 탐색기에서 마우스 오른쪽 클릭으로 나오는 context 메뉴에서 trigger 되는 기능을 개발하려 합니다. 위 excel 암호 를 거는 프로그램을 탐색기 컨텍스트 메뉴에 추가하고, 암호가 걸린 excel 의 경우 복호화도 지원가능해야해여. 암호가 걸려있을 경우, 암호를 변경하는것도 가능해야하고요. 위 기능을 지원하는 간결한 ux 를 구성하고, 암호화 복호화 기능 설치를 위한 msi 설치 프로그램도 만들어야합니다.

요청의 결과물은 탐색기에서 실행하는 암호 관리 창, 암호 설정·해제·변경 기능, MSI 설치 프로그램이다. 지원 파일 형식·암호 길이·복구 조건은 첨부 원본의 계약을 검토한 뒤 [현재 명세](specification.md)에 구체화한다. 조직 배포 승인이나 인터넷 게시를 요청한 것으로 해석하지 않는다.

## 첨부 원본

| 항목 | 값 |
|---|---|
| 파일 | `ExcelPasswordSafe_1.1.0.zip` |
| SHA-256 | `57A8970B8F1269A8E1E143D8CC2480BC0F813201E6F68EF53FA0B7F56F926D9A` |
| 보존 위치 | `tools/ExcelPasswordSafe/upstream/1.1.0/ExcelPasswordSafe/` |
| 원본 안내 | [README](../../../tools/ExcelPasswordSafe/upstream/1.1.0/ExcelPasswordSafe/README.md) |
| 원본 검증 기록 | [VALIDATION](../../../tools/ExcelPasswordSafe/upstream/1.1.0/ExcelPasswordSafe/VALIDATION.md) |

1.1.0은 폴더 아래 Excel 파일의 열기 암호 설정·해제를 제공하는 PowerShell 도구다. 탐색기 메뉴, GUI, 암호 변경, MSI는 포함하지 않는다. 원본은 수정하지 않고 보존한다. 원본의 Linux 순수 시험 결과를 새 Windows 제품의 실제 Excel·설치 시험 결과로 승계하지 않는다.

## 변경 추적

[제품 명세](specification.md) · [설계 결정](../../design/0018-excel-password-safe-explorer.md) · [검증 기록](../../delivery/excel-password-safe-20261116.md)
