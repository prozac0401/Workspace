# ADR-0010 · 보이는 칸 붙여넣기의 독립 COM 추가 기능

상태: 채택 · 0.1.0 독립 COM 구조. 정상 시작 자동 로드와 실제 메뉴 콜백 검증; 미검증 환경과 조직 승인은 별도  
날짜: 2026-09-24  
결정 담당: 도구 개발·검증 담당  
관련 요구사항·정책: [원본 작업지시](../tools/visible-cells-paste/original-specification.md), [요구사항 대응표](../tools/visible-cells-paste/acceptance.md), [추가 도구 개발 기준](../policies/tools.md), [정책 문서 작성 규칙](../policies/documentation.md)  
대체·대체됨 관계: 없음. 다른 제품의 설계·설치 식별자는 변경하지 않음.

## 맥락

요구된 사용자 경로에는 VBA 편집기, 모듈 가져오기, 매크로 수동 실행, 매번 추가 기능 열기가 없다. 원명세는 .xlam을 기본 후보로 두되 자동 로드·클립보드·되돌리기·설치 시험과 ADR을 갖춘 동등한 방식을 허용한다. 작업공간에는 독립 C# .NET Framework COM 추가 기능의 선행 구조가 있다. 이를 참고하되 별도 제품 식별자·소스·설치·이벤트·Undo 기록을 사용한다.

조사 환경은 Windows 11 빌드 22631, Excel x64 16.0.20326.20158이다. 이것은 환경 관찰이며 제품 실행 성공의 증거가 아니다.

## 결정

컴파일된 C# .NET Framework COM 추가 기능과 독립 설치/제거 런처를 tools/VisibleCellsPaste에 둔다. 사용자 PC에서 코드를 제작하거나 VBA 프로젝트에 접근하지 않는다. 실제 구조화 클립보드의 타입·끝 빈칸·프로세스 간 전달을 확인했다. 초기에는 사용자 Excel 유지 조건으로 설치 검증이 차단됐으나 후속 승인 후 정상 Excel 시작의 자동 연결과 실제 우클릭 붙여넣기·Undo를 확인했다.

- IDTExtensibility2가 받은 현재 Application만 연결한다. 다른 프로세스의 활성 범위를 원본이라고 추정하지 않는다.
- IRibbonExtensibility의 고유 컨텍스트 메뉴와 컴파일된 콜백을 사용한다. 시작 시 셀 데이터를 읽지 않는다.
- XML Spreadsheet를 엄격한 타입·차원 입력으로 사용하고 DateTime 위치는 같은 sequence의 제한적 Biff12 원시 숫자로 보완한다. 해당 형식이 없는 Excel에서 항상 동작한다고 주장하지 않는다. 모호하면 0개 수정으로 중단한다.
- 클립보드 스냅샷·순수 계획·Excel I/O·복구를 분리한다. 외부 엔터티·DTD·네트워크를 차단한다.
- 일반 사용자의 HKCU 등록과 고정 LocalAppData 위치를 사용한다. 실행 중 Excel을 강제 종료하지 않는다.
- 최근 1회 Undo는 메모리 백업과 객체 수명·이벤트·사후 상태·구조 근거를 조합한다. 검증되지 않은 구조 변경을 안전하다고 추정하지 않는다.

제품 ProgID는 Workspace.VisibleCellsPaste, CLSID는 {856B2219-6225-42ED-8FF1-2D06E5913AC8}, 관리 클래스는 VisibleCellsPaste.AddIn이며 다른 제품 식별자를 공유하지 않는다. 제품 버전은 0.1.0, AssemblyVersion은 0.1.0.0이다. 런처가 일반 사용자 HKCU의 제품 전용 COM/Excel Addins/제거 등록을 소유하며 installation.xml에 소유 값과 파일 해시를 기록한다.

## 검토한 대안

| 대안 | 장점 | 비용·판정 |
|---|---|---|
| .xlam + 런처 | 원명세 기본 후보, VBA 이벤트·OnUndo 연결 | 승인된 제작·서명·신뢰 조건 필요. 사용자 VBA 주입으로 해결하지 않음 |
| C# .NET Framework COM | 기존 제작 환경 활용, 형식 파서와 I/O 분리, 컴파일된 자동 콜백 | COM 등록·Office 비트수·이벤트·메뉴·동시 설치 시험 필요. 기본 후보 |
| VSTO | Office 수명 관리 체계 | 별도 런타임·배포 신뢰·매니페스트 부담. 현재 선택 아님 |
| 임시 통합문서 native paste | Excel 해석 활용 가능 | 클립보드·끝 빈칸·포커스·Undo 부작용을 먼저 증명해야 함. 현재 선택 아님 |
| 일반 텍스트/TSV만 읽기 | 단순함 | 끝 빈칸·원본 타입·셀 내부 탭/개행의 확정 부족. 채택하지 않음 |

## 영향과 이행

완성 배포물은 .xlam 대신 COM DLL과 설치 런처가 될 수 있다. 제품 실행에 Python·Node.js·개발 SDK·VSTO를 요구하지 않는다. .NET Framework와 설치된 Windows 데스크톱 Excel의 적용 범위는 실제 시험 조합만 검증 완료로 표시한다. 32비트 빌드 생성과 Excel 32비트 실행 통과는 별개다.

서명·기관 추가 기능 정책은 미결정이다. 설치기는 Trust Center, AccessVBOM, 신뢰 위치, 그룹 정책, 파일 출처 표시를 완화하지 않는다. 조직 차단은 승인 조건을 안내하고 존중한다. 후속 사용자 요청으로 공개 릴리스와 사용법 중심의 사이트 게시가 승인됐다. 원문 명세·내부 시험 기록·로컬 진단 자료를 공개 사이트에 포함하지 않는다.

## 실패와 복구

쓰기 전 모든 대상 상태를 메모리에 백업한다. 부분 쓰기 가능성을 포함해 복구하고 복구 결과를 재검증한다. 실패 주소가 남으면 성공을 표시하지 않고 후속 쓰기를 차단한다. Excel COM 여러 호출은 원자적 트랜잭션이 아니며 프로세스 강제 종료·OS 장애·감지되지 않은 외부 동시 수정까지 보장하지 않는다.

Undo에는 동일 이름보다 실행 중 원래 객체를 사용한다. 후속 편집·구조 변경·이벤트 관찰 불가·현재 상태 불일치 때 거절한다. 자체 메뉴 Undo를 제공하되 COM 선택에서 Ctrl+Z 연결을 별도로 증명하지 않았다면 연결됐다고 설명하지 않는다. 실제 UI 입력으로 활성화한 기본 Undo가 도구 쓰기 뒤 비활성으로 바뀜을 확인했다. 기존 Ctrl+Z 기록이 지워질 수 있다는 사용 영향을 명시하며 자체 메뉴는 도구의 최근 한 번만 복구한다.

## 검증

M0에서 설치 후 정상 EXCEL.EXE 시작, 컨텍스트 메뉴 및 실제 Ctrl+C 구조화 데이터의 타입·끝 빈칸을 먼저 검증한다. 동일 파일/다른 파일/별도 프로세스를 나눠 기록한다. 직접 콜백 호출은 자동 로드 UI 시험을 대신하지 않는다.

M1 순수 단위 시험, M2 실제 쓰기·복구·Undo, M3 두 번 재시작·제거·공존, M4 경계·대량·패키지 해시를 분리한다. [시험 보고서](../../tools/VisibleCellsPaste/docs/test-report.md)가 현재 결과를 보유한다. 실제 파서47개·최종 기본Excel19개·최종 확장Excel30개 시나리오는 통과했다. 빈칸 쓰기의 기본 Undo 영향도 실제 probe로 재현·수정 후 회귀했다. 0.1.0에서는 정상 자동 로드·실제 메뉴 붙여넣기/Undo, 원시 날짜 숫자 보완, 읽기 전용/PV·피벗·그룹·객체 교체 시험을 추가했다. 수명주기·날짜·공존의 실제 범위와 남은 NOT RUN은 시험 보고서의 판정을 따른다.

## 공식 근거와 한계

- [Microsoft · Application.SheetChange](https://learn.microsoft.com/en-us/office/vba/api/excel.application.sheetchange): 사용자·외부 링크에 의한 셀 변경 이벤트. 모든 구조 변경을 완전 감지한다는 보증으로 해석하지 않음.
- [Microsoft · Application.OnUndo](https://learn.microsoft.com/en-us/office/vba/api/excel.application.onundo): 사용자 정의 Undo 절차 등록과 후속 작업의 영향.
- [Microsoft · COM 등록](https://learn.microsoft.com/en-us/dotnet/framework/interop/registering-assemblies-with-com): 관리 COM 활성화의 근거.

2026-09-24: 독립 COM 구조 채택. 초기 차단과 결함을 보존하고 후속 정상 자동 로드·메뉴·날짜 보완·안전 회귀를 추가했다. 실제 검증 완료 범위와 조직 승인을 구분한다.
