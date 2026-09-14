# ADR-0005 · 폴더 아이콘 캐시 갱신과 Portable 리소스

상태: 채택 · 날짜: 2026-09-14 · 결정 담당: 도구 개발

관련 요구사항: 원문 01 §6·7·8·18, [추가 도구 개발 기준](../policies/tools.md). [ADR-0001](0001-engine.md)의 저장·복구 원칙을 유지하고 Explorer 갱신 방식을 보완한다.

## 맥락

Windows 11 실제 탐색기에서 상태 저장 성공 후 이전 아이콘이 남았다. 기존 엔진은 비동기 UPDATEITEM과 상위 UPDATEDIR만 보냈다. Portable은 같은 `.folderstate.ico`를 덮어써 이미지 캐시도 재사용했다. 알림 추가나 지연만으로 반복 전환을 해결하지 못했다.

## 결정

- Portable은 `.folderstate-<SHA256 소문자 64자리>.ico`에 저장한다. 현재 소유 파일만 기록하고 이전 소유 파일은 같은 트랜잭션에서 제거한다. 디렉터리를 검색하지 않는다.
- 상태 형식 2에 `PortableName`을 추가한다. 형식 1은 읽고 다음 지정·복구 때 전환한다. 기존 `.folderstate.ico`도 소유 해시가 맞을 때만 제거한다. 0.1.0 엔진은 형식 2를 거절하므로 새 엔진을 사용한다.
- 원자적으로 기록한 desktop.ini의 같은 필드를 `SHGetSetFolderCustomSettings(FCSM_ICONFILE, FCS_FORCEWRITE)`로 적용한다. 전후 INI 바이트를 검증하며 이 단계도 복원 기록 안에 둔다. Windows가 추가하는 폴더 ReadOnly 비트는 의도한 최종 값으로 맞춘다.
- Local의 IconResource는 Windows API와 같은 경로 표기로 저장한다. 한글·공백·쉼표 경로를 시험한다. CLI 인수의 따옴표 처리는 유지한다.
- 최종 알림은 해당 폴더 PIDL의 UPDATEITEM/FLUSH다. 상위 전체 갱신, 전역 캐시 삭제, Explorer 재시작, 상주 프로세스는 사용하지 않는다.
- 저장 후 알림 실패는 저장 실패와 구분해 경고한다. Windows 폴더 설정 API의 MAX_PATH 제한을 넘으면 상태 저장·PIDL 알림은 유지하고 표시 지연 가능성을 알린다.

## 검토한 대안

동기 알림이나 300ms 지연 재통지만으로 실제 반복 시험이 통과하지 않았다. 빈 필드 마스크로 설정 캐시를 갱신하는 시도도 실패했다. 같은 Portable 파일 이름을 유지하고 표준 설정 API를 호출해도 이전 그림이 남아 내용별 경로가 필요했다.

## 실패와 복구

형식 2 복원 기록은 최대 네 개의 정확한 파일 이름만 허용한다. 새 아이콘·이전 아이콘·desktop.ini·상태 파일의 변경 전후 데이터를 저장한다. 중단 뒤 외부 변경은 덮어쓰지 않는다. 이미 원래 바이트·속성인 파일은 다시 교체하지 않아, 읽을 수 있지만 삭제가 잠긴 아이콘 때문에 롤백이 막히지 않는다.

알 수 없는 상태 INI 항목과 백업 확장 속성은 지정·복구 시 보존한다. 초기화로 이 정보를 지우게 되면 `metadata_conflict`로 중단한다. 해석할 수 없는 스냅샷 확장 형식은 파일 전체를 보존하고 거절한다.

## 검증

Explorer의 자세히/큰 아이콘 보기에서 상태 전환·초기화를 확인한다. 자동 시험은 정확한 원본 복원, 형식 1 전환, 단계별 오류·프로세스 종료, 동시 실행, 잠금·외부 충돌, 긴 경로와 업무 파일 보존을 포함한다. 실제 결과와 환경 제한은 [후속 검증 기록](../delivery/robustness-20260914.md)에 구분한다.

근거: [SHGetSetFolderCustomSettings](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetsetfoldercustomsettings), [SHChangeNotify](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shchangenotify), [SHParseDisplayName](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shparsedisplayname).
