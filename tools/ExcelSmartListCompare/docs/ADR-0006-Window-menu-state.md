# ADR-0006 · 파일 창 전환 시 메뉴 상태 동기화

상태: 채택 · 날짜: 2026-09-15 · 결정 담당: Excel 후속 수정 작업

관련 요구: 사용자 두 파일 비교 피드백, 인수 요구 U07~U10, 추가 도구 개발 기준. 조직 배포 승인을 뜻하지 않는다.

## 맥락

RC5에서 두 파일을 미리 열어 두고 첫 파일의 목록을 담은 다음 둘째 파일을 활성화하면, 둘째 창의 추가 기능 탭과 셀·행·열 우클릭 메뉴가 모두 첫 번째 목록 담기로 남았다. 실제 버튼을 실행하면 저장된 목록과 비교하므로 스냅샷 손실과 메뉴 표시 오류를 구분해야 한다. 반대로 비교 완료 후 첫 창에 돌아가면 그 창에는 비교 전 개수가 남았다.

Excel의 [단일 문서 창과 사용자 지정 UI](https://learn.microsoft.com/en-us/office/vba/excel/concepts/programming-for-the-single-document-interface-in-excel) 설명에 따라, 각 창의 컨트롤을 현재 공유 상태에서 갱신해야 한다. 다른 파일을 강제로 활성화해 순회하면 사용자 작업 흐름을 바꾸므로 현재 창을 갱신하는 방식을 선택한다.

## 결정

- 첫 번째 목록은 기존처럼 같은 Excel 프로세스의 메모리에 한 개만 보관한다. 디스크·클립보드·다른 프로세스에 선택값을 공유하지 않는다.
- 별도 `CSLCAppEvents` 클래스에서 [Application.WindowActivate](https://learn.microsoft.com/en-us/office/vba/api/excel.application.windowactivate)와 [Application.SheetBeforeRightClick](https://learn.microsoft.com/en-us/office/vba/api/excel.application.sheetbeforerightclick)을 구독한다.
- 파일 창 활성화와 우클릭 메뉴 표시 직전에 현재 창의 명령·개수 표시를 갱신한다. 처리 중에는 갱신 진입을 막는다. 선택 변경, 셀값 읽기, 원본 수정이나 우클릭 취소는 하지 않는다.
- 명령은 사용자가 선택한 **두 번째 목록 담아 비교**를 사용한다. 한 번 누르면 현재 선택을 두 번째 목록으로 읽고 바로 비교한다. 첫 번째 목록 비우기·바꾸기도 같은 공유 상태를 사용한다.
- 이벤트 연결은 추가 기능 수명 동안 유지하고 해제 시 참조를 끊는다. 이전 창의 CommandBar 참조를 재사용하지 않고 현재 창에서 자기 태그의 컨트롤만 찾는다.

## 검증과 경계

`tests/windows-window-state.ps1`은 같은 Excel에서 두 파일을 미리 열어 둔 상태, 창을 바꾼 뒤 비교·비우기·바꾸기, 새 파일, 같은 파일의 새 창, 첫 번째 목록의 원본 파일을 닫은 뒤 비교, 결과 생성 후 각 창의 초기 상태를 검증한다. 실제 CommandBar 명령 실행과 WindowActivate 이벤트를 사용한다. 자세한 실행 결과는 [창 전환 검증 기록](WINDOW_STATE_REPORT.md)을 따른다.

별도 Excel 프로세스의 파일까지 같은 스냅샷을 공유하는 변경은 아니다. 두 번째 파일은 첫 목록을 담은 Excel의 파일 → 열기에서 열 수 있다. 실제 우클릭·Esc 입력과 시각적 배치는 잠금 해제된 검증 환경에서 별도로 확인한다.
