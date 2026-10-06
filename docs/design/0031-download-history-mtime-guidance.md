# ADR-0031 · 보관 대상의 수정 시각과 확인된 보존 이유 안내

번호 이관: 기존 로컬 ADR-0029의 결정·검증 기록을 보존하고, 최신 저장소의 교육 안내 ADR과 번호가 겹쳐 0031로 옮겼다. 아래 상태는 2026-10-05 당시의 기록이다.

상태: 채택 — 2026-10-05 로컬 소스 개선, 공개 MSI·현재 설치본 미반영

날짜: 2026-10-05 KST · 결정 담당: 사용자 확인에 따른 개발 담당

관련 요구: [0.2.0 명세의 REQ-DVM-NEXT-011·012](../tools/download-version-manager/next-version-specification.md) · 정책: [추가 도구 개발 기준](../policies/tools.md), [문서 작성 규칙](../policies/documentation.md)

대체 관계: [ADR-0026](0026-download-version-manager.md)의 History 이름 날짜 기준만 대체한다. [ADR-0027](0027-download-completion-order.md)의 완료 순서와 [ADR-0028](0028-download-version-manager-folder-input.md)의 입력·보호·설치 계약은 유지한다. 기존 명세·ADR·시험 기록은 당시의 근거로 보존한다.

## 맥락

사용자는 새 History 이름의 날짜를 보관 작업 시각보다 실제 보관 파일의 마지막 수정 시각으로 읽고 싶다고 확인했다. 읽기 전용 파일이 보존됐지만 기존 permission_denied만으로 이유를 알기 어려웠다. 같은 상태는 부모 폴더·파일 열기와 History 생성·이동의 다른 접근 실패에도 쓰인다.

2026-10-05 사용자 확인은 읽기 전용 파일 2개 보존, 읽기 전용이 아닌 동일 내용 정리, 다른 내용의 이전 파일 History 보관이다. 이 사용 사례를 USER_CONFIRMED로 보존하며 설치·복구 또는 모든 처리 경로의 PASS로 확대하지 않는다.

## 결정

History 후보 이름을 만들기 전에 실제 이동할 객체의 보호된 핸들에서 마지막 수정 FILETIME을 읽는다. 일반 폴더·최초 그룹 처리의 직전 원래 파일과 공용 엔진의 늦게 전달된 incoming 객체를 같은 역할로 가정하지 않는다. 읽은 UTC 값은 FileTimeToSystemTime과 SystemTimeToTzSpecificLocalTimeEx로 PC의 해당 날짜 시간대·서머타임 규칙을 반영한다. 현재 시각·생성 시각·고정 시간대는 쓰지 않는다.

YYYYMMDD_HHMMSS 형식, 확장자, _001 이후 충돌 회피와 10,000개 후보 상한을 유지한다. 초 미만 표시나 반올림은 추가하지 않는다. 과거 History 이름은 바꾸지 않고 이름을 맞추려고 보관 대상의 시각 메타데이터를 다시 설정하지 않는다.

엔진이 처리 당시에 확인한 읽기 전용 보호만 내부 결과의 원인 표시로 전달한다. watcher 안내의 앞부분은 ‘읽기 전용 보호: 파일 보존’이며 다른 permission_denied는 ‘접근 실패: 파일 보존’이다. Windows 오류 5나 상태 값만으로 원인을 확정하지 않는다. 기존 상태·오류·파일명·복구 위치·경고와 Host JSON 응답 형식을 유지한다. 나중에 UI에서 속성을 다시 읽어 원인을 추정하지 않는다.

## 검토한 대안

보관 작업 시각은 기존 구현과 호환되지만 사용자가 선택한 기준과 다르다. incoming 또는 경로를 다시 연 파일의 시각을 항상 쓰면 공용 엔진의 역순 처리나 객체 교체에서 잘못된 파일을 가리킬 수 있다. FileTimeToLocalFileTime은 현재 서머타임 설정을 사용하므로 해당 날짜의 동적 변환을 선택한다. 실패 시 현재 시각으로 대체하면 새 날짜 계약을 어기므로 채택하지 않는다.

긴 원인 설명을 로그 뒤에 덧붙이거나 새 팝업·설정·상태 코드를 추가하면 표시·호환 범위가 커진다. 확인된 이유를 짧게 앞에 두고 기존 표시 흐름을 사용한다. 기존 WS_HSCROLL 목록에 같은 글꼴로 측정한 문장 폭을 설정하여 긴 파일명도 기존 수평 스크롤로 읽을 수 있게 한다. 읽기 전용 속성을 해제하거나 권한을 바꾸도록 요구하지 않는다.

## 영향과 이행

새로 생성하는 History 이름만 새 기준을 적용한다. 파일 내용·메타데이터·보호·잠금·감시·실패 큐와 재시도 정책은 유지한다. 같은 수정 시각 또는 같은 초로 보이는 여러 파일도 기존 충돌 순번으로 보존한다. Explorer의 복사 충돌 화면이나 직접 덮어쓰기를 바꾸는 기능은 추가하지 않는다.

공개 0.2.0 MSI와 현재 설치본은 보관 작업 시각 규칙이며 이 소스 변경을 반영하지 않았다. 이번 작업에서 설치본 교체·제거·repair·upgrade, 새 MSI 제작과 원격 공개는 하지 않는다. 승인된 격리 Windows 시험 환경이 없어 설치 복구는 BLOCKED다.

## 실패와 복구

시각 조회·변환 실패는 이름·위치를 바꾸기 전에 기존 file_info_failed 상태와 Windows 오류를 남기며 파일을 보존한다. 이름 충돌 한도에서도 덮어쓰지 않는다. 두 번째 이동 실패·rollback 실패와 중단 뒤 파일 위치 안내는 기존 계약을 따른다. 원인을 확정하지 못한 접근 실패를 읽기 전용이라고 표시하지 않는다.

## 검증

최종 변경의 날짜 대상 선택·같은 초 충돌·과거 이름·내용과 수정 시각·로컬 시간·조회/변환 실패 보존, 확인된 읽기 전용과 다른 접근 실패의 formatter·공용 소비처·경고·실패 큐 회귀를 집중 확인한다. 별도 임시 fixture만 사용한다. 기존 PASS 재사용과 새 실행은 구분하며 같은 수동 시험을 사용자에게 다시 요구하지 않는다.

실제 app 로그 처리기를 합성 Windows 창에서 실행해 수평 범위 0을 확인했고, 문장 폭을 설정한 최종 코드에서 전체 파일명 저장과 스크롤 범위를 자동 검증했다. 이 제어값·폭 측정만으로 실제 픽셀 가독성 PASS를 선언하지 않는다. 실행 결과와 UI NOTRUN/BLOCKED는 [별도 검증 기록](../delivery/download-version-manager-mtime-guidance-20261005.md)을 따른다. 설치 실패 복구 시험은 이 검증 범위에 포함하지 않는다.

공식 근거(2026-10-05 확인): [Microsoft 파일 시각](https://learn.microsoft.com/en-us/windows/win32/sysinfo/file-times), [FileTimeToSystemTime](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-filetimetosystemtime), [SystemTimeToTzSpecificLocalTimeEx](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-systemtimetotzspecificlocaltimeex).
