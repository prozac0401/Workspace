# ADR-0008 · 메뉴를 여는 시점의 목록 상태 사용

상태: 구현, 자동 검증 완료 · 실제 우클릭 표시 미검증 · 날짜: 2026-09-15 · 근거: RC6 설치 후에도 서로 다른 창의 컨텍스트 메뉴가 다르다는 사용자 재보고

## 문제와 기존 검증의 한계

사용자는 파일을 각각 열거나 첫 파일에서 둘째 파일을 여는 두 방식 모두에서 증상이 같다고 확인했다. RC6의 CommandBar 속성·창 이벤트 검사는 통과했지만 실제 우클릭 화면을 검증하지 못했다. 이를 파일 열기 방식 또는 다른 Excel 프로세스 문제로 단정하지 않는다.

Microsoft의 [SDI 안내](https://learn.microsoft.com/en-us/office/vba/excel/concepts/programming-for-the-single-document-interface-in-excel)는 창별 UI 사본과 기존 CommandBar 방식의 제한을 설명하고 XML UI를 권장한다. 기존 구현은 생성된 컨트롤의 Caption을 나중에 수정하므로 표시 사본과 갱신 이벤트에 의존한다.

## 결정

컨텍스트 메뉴를 XLAM에 포함된 RibbonX XML로 등록한다. `dynamicMenu`에 `invalidateContentOnDrop="true"`를 지정해 메뉴를 열 때마다 현재 첫 번째 목록으로 내용과 명령을 구성한다. 이 동작은 [Microsoft DynamicMenu 규격](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.office2010.customui.dynamicmenu)에 정의되어 있다.

첫 목록이 없으면 첫 번째 목록 담기, 있으면 두 번째 목록 담아 비교·항목 수·비우기·바꾸기를 제공한다. 표시된 작업과 실행을 분리해 담기 명령은 항상 담기, 비교 명령은 첫 목록이 있을 때만 비교한다. 오래된 명령이 실행되더라도 의미가 반대로 바뀌지 않는다. 추가 기능 탭의 기존 툴바는 유지한다.

메뉴 내용 생성은 셀값을 읽거나 원본·선택·활성 창·EnableEvents를 변경하지 않는다. Excel 프로세스 사이에 목록을 공유하거나 선택값을 디스크·클립보드로 옮기지 않는다. 기존 제품 컨텍스트 메뉴는 추가 생성하지 않아 중복을 피한다.

## 검증과 배포 판단

XML 구조·Office 로드 콜백·실제 Excel의 메뉴 내용 생성·명령 실행·비교 엔진·설치 수명주기를 각각 검증한다. COM 반환값을 실제 화면 클릭의 증거로 사용하지 않는다. 잠금 상태에서는 실제 우클릭 표시를 확인할 수 없으므로, 그 결과가 없으면 사용자 재보고의 해결을 확정하지 않는다.

실제 결과는 [RC7 검증 기록](CONTEXT_MENU_REPORT.md)에 기록했다. Office onLoad, 내용·창 검사 164개와 RC6 → RC7 설치는 통과했다. 실제 우클릭 표시는 잠금으로 미실행이며 사용자 재보고의 해결을 확정하지 않는다.
