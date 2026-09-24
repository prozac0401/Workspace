# ADR-0009 · 선택범위 내보내기의 설치형 Excel COM 추가 기능

상태: 채택 · 구현 방향이며 배포 승인·전체 인수 통과를 뜻하지 않음

날짜: 2026-09-24

결정 담당: 도구 개발·검증 담당

관련 요구사항·정책: [원작업지시](../tools/excel-selection-export/specification.md), [요구사항·인수 대응표](../tools/excel-selection-export/acceptance.md), [추가 도구 개발 기준](../policies/tools.md), [정책 문서 작성 규칙](../policies/documentation.md)

대체·대체됨 관계: 없음. 명단대조기·FolderState의 기존 결정을 변경하지 않음.

## 맥락

사용자는 설치 프로그램을 한 번 실행한 다음 평소처럼 Excel을 열었을 때 셀 우클릭 메뉴가 준비되는 독립 제품을 요청했다. VBE, VBA 코드 등록, 매크로 실행·허용, 추가 기능 수동 체크와 매번 런처 실행은 사용자 흐름에 넣을 수 없다. 자동 실행 범위는 메뉴와 이벤트 준비이고, 선택 데이터 읽기와 내보내기는 사용자의 메뉴 클릭 뒤에만 시작한다.

기존 `ExcelSmartListCompare`는 별도 제품으로 설치되어 있으며 VBA 기반 설치·신뢰 위치 설정을 사용한다. 신규 제품은 그 메뉴, 설치 등록, 설정과 제거 경로를 재사용하지 않는다. 기존 제품에 대한 현재 미커밋 변경도 이 결정의 수정 범위가 아니다.

착수 당시 개발 PC에서 설치형 Excel의 Click-to-Run 플랫폼 `x64`, Visual Studio 2022 Community의 MSVC 14.41 계열, .NET Framework 4 계열 C# 컴파일러, .NET Framework Release 값 `0x82348`, Inno Setup 6을 확인했다. 표준 Windows SDK include 경로와 해당 SDK 등록은 확인되지 않았다. 이 조사 결과는 도구체인 선택의 근거이며 실행·호환 시험 결과가 아니다.

## 결정

`tools/ExcelSelectionExport`에 C# .NET Framework 기반의 컴파일된 in-process COM 추가 기능과 독립 Inno Setup 설치기를 둔다. 네이티브 Office API를 .NET COM 상호 운용으로 호출하며 VSTO 런타임, Python, 사용자 VBA 프로젝트를 제품 실행의 필수 조건으로 만들지 않는다.

- `IDTExtensibility2`로 현재 Excel 인스턴스의 연결·시작·종료를 처리한다. `OnConnection`이 받은 Application을 보관하고 임의의 `GetActiveObject`로 대상을 찾지 않는다.
- `IRibbonExtensibility`가 반환하는 RibbonX의 컨텍스트 메뉴와 컴파일된 공개 콜백으로 명령을 연결한다. RibbonX의 `onAction`은 COM 콜백 이름이며 VBA 매크로 이름을 `CommandBar.OnAction`에 넣는 방식이 아니다.
- Excel 일반 셀과 Table은 컨텍스트 메뉴가 다르므로 `ContextMenuCell`과 `ContextMenuListRange`를 각각 검증한다. 페이지 레이아웃 모드 지원을 선언할 때는 대응하는 `Layout` 메뉴도 별도로 확인한다.
- 메뉴 표시와 시작 콜백에서는 선택 값 읽기, 네트워크 접근, 계산, 내보내기나 저장을 하지 않는다. 작업 상태 및 가벼운 선택 조건만 확인한다.
- 출력은 연결된 Excel의 `Workbooks.Add`로 만드는 저장 전 통합문서 한 개·시트 한 개다. 원본 시트 복제, 클립보드 복사, 원본 재계산·갱신을 기본 경로로 사용하지 않는다.
- Excel COM 객체는 Excel UI/STA 문맥에서만 사용한다. 값을 복사한 독립 계획 모델은 Excel 없이 시험할 수 있게 분리한다.

### 제품 등록과 소유권

| 항목 | 결정 |
|---|---|
| 사용자 표시명 | 선택범위 내보내기 |
| 소스·테스트·패키지 경계 | `tools/ExcelSelectionExport` |
| 설치 권한·위치 | 현재 사용자, HKCU 및 `%LocalAppData%\Workspace\ExcelSelectionExport` |
| Excel 발견 등록 | `HKCU\Software\Microsoft\Office\Excel\Addins\Workspace.ExcelSelectionExport` |
| 최초 시작 시 로드 | 제품 등록의 `LoadBehavior=3` |
| COM 활성화 | 제품 CLSID·ProgID와 .NET Framework `InprocServer32` 등록. 설치기가 제품 소유 항목만 작성 |
| 32/64비트 | Excel 비트수에 맞춘 payload와 COM registry view. Windows x64만으로 Excel x64를 추정하지 않음 |
| 설정·제거 | 독립 앱 이름·제거 등록. 원본·결과 문서와 다른 추가 기능은 설치기 소유가 아님 |
| 배포 상태 | 서명 없는 평가 빌드. 조직별 서명·배포 승인 조건은 미결정 |

COM CLSID는 `{2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1}`, ProgID는 `Workspace.ExcelSelectionExport`, 관리 클래스는 `ExcelSelectionExport.AddIn`, DLL은 `ExcelSelectionExport.AddIn.dll`이다. 초기 AssemblyVersion은 `0.1.0.0`이며 M1 평가 제품 버전은 `0.1.0-m1`이다. 기능 구현 이후의 패키지 버전과 실제 해시는 해당 검증 기록에 남긴다. 버전이 바뀌어도 다른 제품의 식별자를 재사용하지 않는다. Office나 사용자가 바꾼 로드 상태를 상주 감시하며 되돌리지 않는다. 업데이트·재설치는 기존 비활성화 상태를 존중해야 한다.

`IDTExtensibility2`는 GUID `B65AD801-ABAF-11D0-BB8B-00A0C90F2744`의 dual interface이며 `OnConnection`, `OnDisconnection`, `OnAddInsUpdate`, `OnStartupComplete`, `OnBeginShutdown`의 DispId는 차례로 1~5다. `IRibbonExtensibility`의 GUID는 `000C0396-0000-0000-C000-000000000046`이고 `GetCustomUI`는 DispId 1의 BSTR 입력·반환 메서드다. 명시적인 COM 인터페이스 선언은 공식 인터페이스 및 설치된 Office PIA와 대조한다. 콜백은 제품 default interface `ICallbacks`(GUID `5AA04C49-1739-4704-A1CE-09E5B10A44A2`)를 통해 COM-visible IDispatch에서 실제 이름으로 찾아 호출할 수 있어야 한다.

## 검토한 대안

| 대안 | 이점 | 선택하지 않은 이유·남는 비용 |
|---|---|---|
| 네이티브 C++ COM | 관리 런타임이 필요 없고 COM 수명주기를 직접 통제 | 현 PC에서 Windows SDK가 확인되지 않으며 COM·UI 구현 비용이 큼. 향후 배포·격리 요구가 바뀌면 재검토 |
| C# .NET Framework COM | 설치된 컴파일러로 독립 DLL 제작 가능, Office 객체 모델과 테스트 모델 분리 용이 | Framework 존재와 COM 등록·비트수·공존을 실제 검사해야 함. 관리 COM의 수명·격리 위험은 남음 |
| VSTO | Microsoft의 Office 수명주기·격리 지원 | 별도 VSTO 런타임, manifest 신뢰·서명·배포 조건이 추가됨. 초기 자동 로드 검증 경로로 채택하지 않음 |
| VBA/XLAM | 기존 제품의 구현 경험 활용 가능 | 이번 요청의 수동 VBA·매크로 허용 없음 조건을 기존 신뢰 위치 방식으로 충족시킬 수 없음 |
| Office 웹 추가 기능 | 여러 플랫폼 배포에 유리 | 이번 Windows 설치형 제품의 로컬 설치·서식·COM 범위 계약과 다른 배포·호스팅 모델이 필요 |

직접 관리 COM을 선택했다고 메모리 격리와 다른 추가 기능과의 공존을 보장하지 않는다. Microsoft가 설명하는 관리 COM 격리 위험을 반영해 반복 연결·해제, 여러 Excel 프로세스, 종료 후 잔류 프로세스와 다른 제품 동시 사용을 인수 시험에 포함한다. 필요한 경우 별도 ADR로 VSTO 또는 네이티브 shim을 검토한다.

## 영향과 이행

사용자 흐름은 **설치 → Excel 실행 → 유한한 셀 범위 선택 → 우클릭 → 선택범위 내보내기 → 새 Excel로**다. 저장 위치를 먼저 묻지 않으며 결과 저장은 사용자가 Excel의 일반 저장 기능으로 수행한다.

기능 평가 버전부터 DLL과 설치 사전검사 도구는 제품 폴더의 `versions/<제품버전>/<Excel 비트수>`에 설치한다. 신규 버전 경로가 아직 없으면 열린 Excel을 유지한 채 새 버전을 설치할 수 있으며, 기존 Excel은 이미 로드한 DLL을 사용한다. 새 프로세스 또는 전체 Excel 종료 후 다시 시작한 시점부터 새 등록을 사용한다. 실제로 이 동작을 확인하기 전에는 열린 Excel에 새 기능이 즉시 적용됐다고 안내하지 않는다.

같은 버전의 payload가 이미 있는 상태에서 Excel이 열려 있으면 파일 교체를 막고 저장 후 종료를 안내한다. 제거는 모든 Excel을 닫은 뒤에만 진행한다. 기존 프로세스를 강제 종료하거나 문서를 저장하지 않는다. 설치기는 매크로 보안, Trust Center, 그룹 정책, 신뢰 위치, 인증서 신뢰 또는 파일 출처 표식을 완화하지 않는다. 버전별 설치 전환의 실제 설치·제거 결과는 별도 검증 기록에 남긴다.

기관이 추가 기능을 금지하거나 신뢰된 서명을 요구하면 관련 진단과 필요한 승인 조건을 표시한다. 서명 없는 평가 빌드가 모든 PC에서 경고 없이 실행된다고 주장하지 않는다. 사용자 비활성화 및 Office 복원력 정책의 차단 상태는 보존한다.

## 실패와 복구

메뉴는 제품 고유 ID로 소유권을 구분하고 전체 메뉴 초기화·삭제를 하지 않는다. 다시 연결해도 중복 메뉴·이벤트가 없어야 하며 종료·연결 해제 시 자신이 연결한 이벤트만 해제한다.

내보내기 실패·취소는 자신이 이번에 만든 불완전한 통합문서만 닫는다. 원본과 다른 통합문서의 값·서식·필터·숨김·저장 여부를 바꾸지 않는다. 변경한 Excel 전역 상태는 원래 값으로 복원하며 계산 모드는 가능한 한 변경하지 않는다. 원본 실행 취소 기록은 실제 시험 전에는 보존한다고 안내하지 않는다.

설치 실패, 정책 차단, 비트수 불일치, 누락 런타임과 COM 로드 실패를 같은 성공 메시지로 숨기지 않는다. 제품 소유 항목의 부분 변경·롤백과 기존 등록·다른 제품 보존은 설치 수명주기 시험에서 확인한다. 상세 경로와 진단은 로컬 증거로 두고 공개 사이트에 포함하지 않는다.

## 검증

원작업지시의 M1 자동 로드 게이트를 우선한다. 설치기가 만든 등록으로 정상 Excel 시작 시 메뉴가 나타나고 실제 UI 메뉴 클릭이 컴파일된 기능으로 이어지는지 확인한다. 개발자의 직접 COM 메서드 호출이나 매크로 실행만으로 이 항목을 통과 처리하지 않는다.

2026-09-24 후속 사용자 지시에 따라 현재 PC에서 가능한 시험을 진행하고, 격리된 새 사용자 프로필/VM 및 Windows 재로그인·재부팅 시험은 실제 수행하지 않았다면 **미실행**으로 남긴다. 현재 PC의 M1 메뉴·콜백 확인 뒤 로컬 기능 구현·검증을 진행할 수 있으나, 이것을 원명세 전체 배포 게이트 통과로 확대하지 않는다.

빌드, 계획 모델 단위시험, 실제 Excel 자동화, 실제 UI 조작, 설치·업그레이드·제거, 공존 시험은 [대응표](../tools/excel-selection-export/acceptance.md)에 별도로 기록한다. 시험에 쓰는 데이터는 합성 데이터만 사용한다. 이 ADR 작성 시점에는 M1 실제 결과가 확정되지 않았으며 통과를 선언하지 않는다.

## 확인 자료

- [Microsoft · Excel COM 추가 기능과 Automation 추가 기능](https://support.microsoft.com/en-us/excel/excel-com-add-ins-and-automation-add-ins): Excel의 in-process COM, `IDTExtensibility2`, HKCU 등록 및 Application 참조.
- [Microsoft · COM 추가 기능 생성](https://learn.microsoft.com/en-us/office/client-developer/infopath/external-automation/how-to-create-a-com-add-in-to-add-custom-features-to-infopath): Office 공통 로드 등록과 `LoadBehavior=3`, 관리 COM 격리 주의. InfoPath 전용 API는 Excel 구현 근거로 사용하지 않음.
- [Microsoft · Office Fluent Ribbon 개요](https://learn.microsoft.com/en-us/office/vba/library-reference/concepts/overview-of-the-office-fluent-ribbon): 관리·비관리 COM의 RibbonX와 컴파일된 콜백.
- [Microsoft · IRibbonExtensibility](https://learn.microsoft.com/en-us/dotnet/api/microsoft.office.core.iribbonextensibility?view=office-pia), [IDTExtensibility2](https://learn.microsoft.com/en-us/dotnet/api/extensibility.idtextensibility2?view=visualstudiosdk-2022): 인터페이스 식별자·서명. 후자 문서의 Visual Studio 추가 기능 폐기 안내는 Office 제품 판정으로 전용하지 않음.
- [Microsoft · Context Menu XML](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-customui2/db5b22ab-d58e-459b-81a2-b9e51c23e9cc), [공식 Excel 컨트롤 ID 목록](https://github.com/OfficeDev/office-fluent-ui-command-identifiers/blob/main/Microsoft%20365/Current%20Channel/excelcontrols.xlsx).
- [Microsoft · .NET Framework COM 등록](https://learn.microsoft.com/en-us/dotnet/framework/interop/registering-assemblies-with-com), [Regasm 도구](https://learn.microsoft.com/en-us/dotnet/framework/tools/regasm-exe-assembly-registration-tool): 관리 COM 활성화·CodeBase 등록. 최종 사용자가 Regasm을 직접 실행하는 흐름은 제공하지 않음.
- [Microsoft · 추가 기능 보안 설정](https://support.microsoft.com/en-US/Office/add-ins/view-manage-and-install-add-ins-for-excel-powerpoint-and-word), [RequireAddinSig 정책](https://support.microsoft.com/en-US/Office/resolve-warning-for-the-requireaddinsig-security-policy): 추가 기능 자체의 차단·신뢰 조건은 문서 VBA 허용 여부와 별도로 검사.

2026-09-24: 최초 작성. 독립 COM 제품의 구현 방향과 현 PC 검증·전체 인수의 구분을 기록함.
