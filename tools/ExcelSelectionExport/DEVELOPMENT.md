# 선택범위 내보내기 개발·시험 안내

이 문서는 개발자용입니다. 사용자는 설치 EXE를 한 번 실행한 뒤 Excel에서 셀을 선택하고 메뉴를 누릅니다. 아래 개발 스크립트, 컴파일러, 시험 실행 파일은 사용자 설치 단계가 아닙니다. VBA 등록·실행, 매크로 허용, 추가 기능 수동 체크로 제품의 자동 로드를 대신하지 않습니다.

수정 전 원본 작업명세, 저장소 AGENTS.md, [도구 개발 기준](../../docs/policies/tools.md), [문서 작성 규칙](../../docs/policies/documentation.md)을 읽습니다. 다른 제품과 사용자의 변경 사항을 보존합니다.

## 제품 빌드와 단위시험

Windows 11 x64 개발 PC에 .NET Framework 4.8 이상의 C# 컴파일러와 Inno Setup 6이 필요합니다. 저장소 루트에서 실행합니다.

~~~powershell
powershell -NoProfile -File .\tools\ExcelSelectionExport\scripts\build.ps1 -Version 0.1.0-rc.10
~~~

이 명령은 x86/x64 추가 기능·설치 진단 도구를 컴파일하고, 메뉴 계약·가시 범위 계획·엔진 보호 조건 시험 및 설치 진단 단위시험을 실행한 뒤 설치 EXE를 만듭니다. 실제 Excel을 시작하거나 설치 프로그램을 실행하지 않습니다. 한 단계라도 실패하면 빌드를 중단합니다.

출력은 artifacts/selection-export/해당버전/입니다. 설치 파일, SHA256SUMS.txt, build-manifest.json과 시험 로그를 함께 확인합니다. 빌드 성공은 실제 Excel 로드·메뉴 클릭·내보내기·제거 시험의 통과를 뜻하지 않습니다. 서명되지 않은 평가 패키지를 배포 승인된 제품으로 표시하지 않습니다.

## 실제 Excel 시험 도구 컴파일

다음 스크립트는 여섯 시험 실행 파일을 **컴파일만** 합니다. Excel, 설치기, COM 추가 기능 또는 생성한 시험 프로그램을 실행하지 않습니다.

~~~powershell
powershell -NoProfile -File .\tools\ExcelSelectionExport\scripts\Build-IntegrationTests.ps1
powershell -NoProfile -File .\tools\ExcelSelectionExport\scripts\Build-IntegrationTests.ps1 -Architecture x86
~~~

기본 출력은 artifacts/selection-export/integration-tests/x64/이며 x86 옵션은 대응하는 x86/에 출력합니다. ExcelProbe.exe, FunctionalTests.exe, EngineFailureTests.exe, CancellationTests.exe, UndoHistoryTests.exe, OutputCancellationTests.exe와 컴파일 로그·integration-build-manifest.json이 생성됩니다. 컴파일할 때 제품 DLL은 필요하지 않습니다. EngineFailureTests는 실행 시 검증할 배포 DLL의 경로를 별도로 받습니다.

추가 기능과 시험 실행 파일의 비트수는 **설치된 Excel**에 맞춥니다. Windows가 x64라는 이유로 Excel도 x64라고 가정하지 않습니다. x86 시험 프로그램의 컴파일 성공을 x86 Excel의 실제 동작 검증으로 기록하지 않습니다.

## 시험 전 반드시 확인할 소유권

실제 시험에는 이번 시험에서 만든 합성 통합문서와 전용 Excel 프로세스만 사용합니다. 파일 경로는 저장소 artifacts/selection-export/ 아래의 새 이름을 사용합니다. 기존 업무 파일이나 사용자가 작업 중인 Excel에 연결하지 않습니다.

ExcelProbe의 start 명령은 지정한 새 .xlsx 합성 파일을 만들고, 확인된 Excel.exe를 /x로 실행하며 옆에 .xlsx.pid 표식을 기록합니다. 이미 존재하는 합성 파일을 덮어쓰지 않습니다. 표식을 임의로 만들거나 PID를 다른 Excel 프로세스로 바꾸지 않습니다.

FunctionalTests, EngineFailureTests, CancellationTests는 정확한 .xlsx.pid 경로를 요구합니다. 해당 PID의 Excel 창에서 얻은 Application인지 확인하고, 그 인스턴스에 표식의 합성 통합문서 하나만 열려 있는지 확인합니다. 다른 문서가 있거나 경로가 다르면 중단합니다. 시험 실행 전에 같은 조건을 직접 확인합니다.

다음은 컴파일된 시험 도구의 명령 규약입니다. 꺾쇠괄호 부분은 확인한 실제 절대 경로로 채웁니다. 실행 파일은 선택한 비트수의 출력 폴더에서 사용합니다.

~~~text
ExcelProbe.exe start "<검증한 Excel.exe 절대 경로>" "<새 합성파일.xlsx 절대 경로>"
ExcelProbe.exe inspect "<같은 합성파일.xlsx 절대 경로>"
FunctionalTests.exe "<같은 합성파일.xlsx.pid 절대 경로>" all
FunctionalTests.exe "<같은 합성파일.xlsx.pid 절대 경로>" manualcached
EngineFailureTests.exe "<같은 합성파일.xlsx.pid 절대 경로>" "<검증할 ExcelSelectionExport.AddIn.dll 절대 경로>" all
CancellationTests.exe "<같은 합성파일.xlsx.pid 절대 경로>"
OutputCancellationTests.exe "<4셀을 선택한 합성파일.xlsx.pid 절대 경로>" "<검증할 ExcelSelectionExport.AddIn.dll 절대 경로>"
ExcelProbe.exe close "<같은 합성파일.xlsx 절대 경로>"
~~~

검증할 DLL은 패키지의 해당 비트수 산출물 또는 설치된 정확한 버전 폴더의 파일을 지정합니다. EngineFailureTests는 파일 해시를 기록합니다. close는 이 합성 파일만 있는 시험용 인스턴스에만 사용합니다. 다른 문서나 소유권이 불확실한 창을 발견하면 사용자가 확인할 때까지 종료·강제 종료하지 않습니다.

FunctionalTests는 설치된 추가 기능의 컴파일된 콜백을 API로 호출합니다. 비동기 콜백 반환 뒤 최대 120초 동안 엔진 완료를 기다리고, 성공 뒤 최대 3초 동안 같은 인스턴스의 저장 전 새 결과가 실제로 활성화되는지 확인합니다. 시험 도구가 대신 결과를 활성화하지 않습니다. 제품의 지연 완료 콜백은 결과를 Activate한 뒤 해당 결과 창의 Hwnd로 전면 표시를 요청하고, 같은 Application의 ActiveWindow.Hwnd가 결과와 일치하는지 확인합니다. 이는 Excel 내부 활성 창의 확인이며 OS 전면 표시는 실제 UI 관찰과 구분해 기록합니다. 값·서식 출력 성공만으로 결과 표시까지 성공했다고 보고하지 않습니다. 오류·취소·시간 초과는 양성 시험 실패로 기록합니다. Excel의 실제 우클릭 메뉴를 사용했다는 증거는 아닙니다. 활성화 판정을 생략한 별도 데이터 진단 로그는 정식 API 통과로 집계하지 않습니다.

모든 양성 fixture의 원본을 Excel XML Spreadsheet 형식으로 전후 대조하며 값·수식·숨김·행열 크기·필터·저장 여부의 명시 검사도 유지합니다. 출력 표시 서식은 셀별로 비교합니다. 서식 양성 사례는 기본/표시 글꼴명이 구체적인 맑은 고딕을 사전 확인하며 전체 셀 위/아래 첨자를 포함합니다. Arial+한글 자동 대체에서 혼합 글꼴이 생겨 거절되는 제한은 별도 기록하며 지원 통과로 바꾸지 않습니다.

EngineFailureTests는 명시한 DLL의 엔진 API를 호출하므로 설치 등록·자동 로드·Ribbon 콜백 검증과 별도로 판정합니다. 부분 병합처럼 Excel이 선택을 자동 확대해 의도한 조건을 만들지 못하면 NOT_RUN_CASE로 남기고, 실행한 통과 사례 수와 구분합니다.

시험 도구는 자신이 만든 합성 원본과 결과만 정리합니다. FunctionalTests가 시간 초과·통신 실패로 엔진의 종료를 확인하지 못하면 관련 통합문서를 닫거나 시작 문서를 활성화하지 않고 보존 위치와 상태를 기록합니다. manualcached는 시험 인스턴스의 계산 모드를 일시 변경하며 엔진이 끝났다고 확인할 수 있을 때만 원래 모드로 복원합니다. 종료가 불확실하면 진행 상태를 확인하고 엔진 종료 뒤 계산 모드와 합성 문서를 수동 정리해야 합니다. COM 참조 해제만으로 실행 중 작업이 끝났다고 간주하지 않습니다.

CancellationTests는 합성 20,000셀을 준비한 뒤 `WAIT_FOR_PROGRESS_CANCEL`을 출력하고 실제 추가 기능을 호출합니다. 진행 창의 **취소**를 사람이 누른 뒤 원본 XML·저장 여부·Excel 전역 상태·결과 미생성을 확인합니다. 다른 Excel 자동화가 새 파일을 시험 인스턴스에 열거나 화면을 바꾸지 않는 시간에 실행합니다. 실제 취소 없이 끝난 작업은 취소 시험 통과가 아닙니다. 비동기 콜백 반환 후 최대 120초 동안 완료 상태를 확인합니다. 타임아웃이나 통신 실패로 엔진 종료를 확인하지 못하면 합성 원본을 닫지 않으며, 진행 창을 확인하고 엔진이 끝난 뒤 수동으로 정리해야 합니다.

`OutputCancellationTests.exe`는 합성 파일 하나만 있는 시험 인스턴스에서 현재 선택이 4셀인 조건을 요구합니다. 명시한 DLL의 엔진을 reflection으로 직접 호출하고 숨김 Excel에 출력을 작성하는 단계에서 취소를 주입합니다. 원본 XML·Saved·Excel 전역 상태·Undo 보존, 불완전한 출력의 롤백, 제품 임시 디렉터리와 작업용 Excel의 정상 종료를 검사합니다. 실제 메뉴나 사람이 진행 창의 취소 버튼을 누른 시험과 구분합니다. 결과 기록에는 정확한 DLL과 직접 엔진 호출이라는 시험 방식을 함께 적습니다.

## Undo 회귀 시험

rc.10은 원본 선택을 DTO로 읽은 뒤, 새 숨김 Excel 인스턴스에서 기존 writer로 값·서식을 기록하고 검증합니다. 검증한 `.xlsx`는 사용자 임시 폴더의 제품 전용 GUID 경로에 저장합니다. 작업용 통합문서를 닫고 전용 Excel을 정상 종료한 뒤, 원본 인스턴스의 `Workbooks.Add(template)`로 저장 전 새 결과를 만들고 값을 다시 검증합니다. 원본 인스턴스에서 결과 셀·서식·시트 이름을 다시 쓰지 않는 경계를 유지합니다. 단, 템플릿에서 만든 문서는 `Path`가 비어도 `Saved=true`일 수 있으므로 새 결과의 `Saved=false`만 설정해 저장 확인을 유지합니다. 이 플래그 대입에서도 원본 Undo가 유지되는지 실제로 검사합니다. 상세 결정과 임시 데이터 경계는 [ADR-0018](../../docs/design/0018-excel-selection-export-undo.md)를 따릅니다.

Undo 시험은 원본 값·수식 전후 비교와 별도로 실행합니다. 합성 원본에 실제 UI로 여러 번 편집해 Undo 기록을 만든 뒤, 설치한 제품의 실제 우클릭 메뉴로 내보냅니다. 원본으로 돌아와 Undo 활성 여부만 확인하지 말고 Ctrl+Z를 차례로 실행해 각 편집이 역순으로 되돌아가는지 대조합니다. 결과는 같은 인스턴스의 시트 한 개이며 `Path`가 빈 저장 전 문서인지, 원본 값·서식·저장 상태와 클립보드가 유지되는지도 확인합니다. 원인 분리용 단일 COM 호출 시험을 이 제품 시험 대신 통과로 집계하지 않습니다.

`UndoHistoryTests.exe`는 실제 UI 조작 사이에서 읽기 전용 검사를 수행합니다. 먼저 ExcelProbe로 새 합성 파일을 만들고 UI로 A1에 `History-A`, B1에 `314`, B2에 `=B1+1`을 순서대로 입력한 뒤 A1:B2를 선택합니다. 다음 순서에서 `before`·`exported` 등의 인수는 각각 별도 실행합니다.

~~~text
UndoHistoryTests.exe "<합성파일.xlsx.pid 절대 경로>" before
[실제 우클릭 메뉴로 내보낸 뒤 원본으로 돌아오기]
UndoHistoryTests.exe "<같은 합성파일.xlsx.pid 절대 경로>" exported
[Ctrl+Z 한 번 뒤 undo1, 다시 한 번 뒤 undo2, 다시 한 번 뒤 undo3]
[Ctrl+Y 한 번 뒤 redo1, 다시 한 번 뒤 redo2, 다시 한 번 뒤 redo3]
~~~

각 검사에서는 원본 값·수식이 기대한 역순 또는 정순으로 바뀌었는지, Undo·Redo의 활성 상태, 내보낸 결과가 계속 같은 내용인지 확인합니다. 내보낸 직후에는 같은 인스턴스의 통합문서 두 개, 단일 결과 시트·빈 결과 `Path`·`Saved=false`도 검사합니다. 도구가 원본 값을 쓰거나 대신 Undo·Redo를 실행하지 않으며, 키보드·메뉴 행동은 실제 UI로 수행해야 합니다.

성공·취소·실패 경로에서 작업용 Excel과 임시 파일이 정리되는지 확인합니다. 강제 종료는 finally 실행을 보장하지 않으므로 중간 파일이 남을 수 있습니다. 복구·정리 시험은 해당 작업의 제품 전용 GUID 경로와 직접 만든 Excel 인스턴스만 대상으로 하며, 기존 사용자 문서와 소유권을 확인하지 못한 프로세스는 건드리지 않습니다.

## 설치·메뉴 시험과 결과 기록

M1은 설치 EXE만으로 등록한 뒤 일반 Excel 시작 시 메뉴가 준비되고, 실제 메뉴 클릭이 컴파일된 콜백으로 이어지는지 먼저 확인합니다. 이후 새 프로세스·재시작·여러 통합문서·다른 도구 공존·설치·업데이트·제거를 각각 기록합니다. 실제 메뉴 클릭·취소 화면은 UI 시험으로 따로 확인합니다.

새 버전은 별도 versions/버전/비트수/ 경로에 설치됩니다. 열려 있던 Excel은 기존 DLL을 계속 사용합니다. 새 설치 파일을 만들었다는 이유로 실행 중인 Excel에 새 버전이 적용됐다고 판단하지 않습니다. 같은 버전의 파일 교체와 제거는 Excel이 열려 있으면 중단됩니다.

Test-Package.ps1의 Snapshot/Compare는 보안 설정과 다른 도구의 등록·고정 프로그램 파일에 대한 읽기 전용 지문 비교를 제공합니다. Lifecycle은 기존 제품 설치나 Excel 프로세스가 있으면 거절하며, 허용된 깨끗한 시험 환경에서만 설치·제거를 실행합니다. 현재 사용자의 업무 환경을 맞추려고 기존 제품이나 Excel을 임의 제거·종료하지 않습니다.

정책, Trust Center, 매크로 보안, 신뢰 위치, MOTW, 인증서 신뢰를 완화하지 않습니다. 사용자 또는 Office의 비활성화 상태를 강제로 바꾸지 않습니다. 승인된 환경에서 로드할 수 없으면 오류 코드와 필요한 승인 조건을 기록합니다. 개발 스크립트를 실행하기 위해 실행 정책을 우회하지 않습니다.

2026-09-24 현재 PC의 rc.9 평가에서는 빌드 단위191회, 정식 COM 콜백 API11사례·930 assertions, 실제 진행 창 취소11 assertions, 취소 뒤 재실행29 assertions가 통과했습니다. 직접 엔진 거절은 실행9사례·92 assertions 통과와 부분 병합1사례 미실행으로 구분합니다. 실제 우클릭·결과 전면 표시·정상 UI 종료, 취소/정상 출력의 클립보드 sequence 무변경을 별도 확인했습니다. 상세 조건과 남은 미실행 항목은 [평가 기록](../../docs/delivery/excel-selection-export-evaluation-20260924.md)을 따릅니다. 전체 제거·전체 공존·x86 Office·격리 VM·재부팅은 미실행이며 서명·조직 배포 승인은 미확정입니다.

rc.9 API 시험 뒤에는 ExcelProbe close가 종료0으로 합성 문서를 닫았어도 창 없는 Excel 프로세스가 수분간 남았습니다. 이 경로의 자연 종료는 실패이며 원인은 미확정입니다. PID 표식·시작 시각·실행 파일·표시 창 없음을 확인한 빈 시험 프로세스만 별도로 정리했고, 다른 작업 Excel은 유지했습니다. 외부 COM 없는 실제 UI 종료 통과와 구분하며 시험 도구의 종료 코드만으로 Excel 자연 종료를 보장하지 않습니다. 이 일회성 정리 도구는 제품이나 정식 통합 시험 도구에 포함하지 않습니다. 정리 뒤 새 Excel의 정상 시작·중복 없는 메뉴·자동 내보내기 없음·UI 정상 종료는 별도로 확인했으며 내보내기 엔진을 다시 시험했다는 뜻은 아닙니다.

rc.9 실제 UI 측정에서는 내보내기 전 활성화된 원본 편집 Undo가 내보낸 뒤 비활성화됐습니다. 원본 값·수식 전후 동일 검사와 실행 취소 기록을 구분합니다. 2026-09-26 조사에서 같은 Excel 인스턴스에 대한 시트 이름·기본 글꼴·셀 기록을 원인 동작으로 확인했으며, rc.10의 분리된 출력 경로로 수정합니다. 최신 결과는 [Undo 조사·수정 검증 기록](../../docs/delivery/excel-selection-export-undo-20260926.md)을 따릅니다. 최종 rc.10은 단위249개, 설치본 API11사례·930개, 실제 메뉴 Undo3·Redo3의 110개, 직접 엔진 출력단계 취소17개 검사를 통과했습니다. x86/x64 패키지와 x64 설치·DLL 해시 일치, 작업용 Excel 정상 종료·임시 파일 정리를 확인했습니다. 최종 원본 Excel은 API로 Close+Quit한 뒤 빈 프로세스가 남았으므로 기존 API 종료 제한은 유지합니다. rc.9 결과를 소급해 통과로 바꾸지 않습니다.

검증 기록에는 패키지 버전·해시, Windows/Excel 버전·비트수, 시험 방식, 실제 결과, 미실행 조건을 적습니다. 격리 프로필·재로그인/재부팅·x86 Excel 등 확인하지 않은 항목은 미실행으로 남깁니다. 사용자 경로를 포함할 수 있는 로그는 artifacts 아래에 보관하며 공개 문서·공개 사이트에 복사하지 않습니다.
