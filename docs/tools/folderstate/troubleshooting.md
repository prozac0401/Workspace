# 명령줄과 오류 해결

## CLI

```powershell
FolderState.Cli.exe set doing "D:\Work\10_Active\2026-10_과정\03_교육생선발"
FolderState.Cli.exe set done "D:\Work\회차\04_입과안내" --mode portable
FolderState.Cli.exe status "D:\Work\회차\04_입과안내" --json
FolderState.Cli.exe repair "D:\Work\회차\04_입과안내"
FolderState.Cli.exe reset "D:\Work\회차\04_입과안내"
FolderState.Cli.exe set todo "D:\Work\단계1" "D:\Work\단계2" --json
```

대상은 전체 경로로 입력합니다. 최대 100개 명시 목록을 처리하며 재귀·와일드카드 검색은 없습니다. 한 폴더의 실패가 다른 폴더의 성공을 되돌리지 않습니다. 종료 코드는 0 성공, 1 작업 실패, 2 인수 오류입니다. JSON 출력은 자동화에서 사용합니다. GUI 실행파일도 set/reset/repair 형식을 받아 탐색기 메뉴에서 사용합니다.

## 오류별 조치

| 오류 | 의미 | 조치 |
|---|---|---|
| access_denied | 권한 또는 보안 차단 | 대상 쓰기 권한과 조직 정책 확인 |
| io_error | 잠금·연결·저장 공간 문제 | 사용 중 프로그램·연결·공간 확인 후 재실행 |
| icon_missing | 설치 리소스 누락·손상 | MSI의 프로그램 복구 후 폴더 아이콘 복구 |
| icon_conflict | 외부 도구가 아이콘 변경 | 현재 설정 확인 후 초기화하고 재지정 |
| portable_conflict | Portable 아이콘의 소유 이름·해시가 맞지 않음 | 해당 파일을 보존하고 충돌을 수동 확인 |
| metadata_conflict | 상태 파일에 외부 정보가 추가됨 | 초기화를 중단하여 보존; 원본을 유지하고 지원 요청 |
| shell_metadata_changed | Windows 설정 적용 결과가 예상과 다름 | 복원 기록을 보존하고 지원 요청 |
| invalid_metadata | 손상·외부 형식·미래 버전 | 메타데이터 원본을 보존하고 지원 요청 |
| recovery_pending | 이전 작업 중단 | 상태 아이콘 복구 실행 |
| recovery_conflict / recovery_failed | 중단 이후 외부 변경·복구 실패 | 메타데이터를 삭제하지 말고 잠금·변경 내용 확인 |
| reparse_point / hard_link | 연결·자리표시자 또는 하드링크 | 실제 로컬 일반 폴더 사용 |
| busy | 같은 폴더의 다른 작업 | 잠시 후 다시 실행 |
| metadata_too_large | 고정 메타데이터 크기 초과 | 기존 설정 보존 후 검토 |

## 화면이 갱신되지 않을 때

0.1.1은 해당 폴더의 아이콘 필드를 Windows 설정 API로 적용한 뒤 동기 갱신 알림을 보냅니다. Portable도 다른 아이콘 내용에 다른 파일 경로를 사용합니다. 먼저 상태 저장 성공 여부를 확인하고 **상태 아이콘 복구**를 실행합니다. 260자 이상 경로는 Windows 설정 API의 제한 때문에 표시 지연 경고가 나올 수 있습니다. 계속 이전 아이콘이 보이면 F5 또는 해당 폴더 창 다시 열기로 확인합니다. Explorer 강제 종료나 전역 아이콘 캐시 삭제는 도구가 자동 수행하지 않습니다.

인터넷에서 받은 desktop.ini나 아이콘, 복사 시 누락된 속성, 동기화 자리표시자에는 추가 제한이 있을 수 있습니다. 도구는 보안 출처 표시를 자동으로 제거하지 않습니다.

목록은 바뀌었지만 오른쪽 **세부 정보**의 선택 미리보기만 이전 아이콘일 수 있습니다. 다른 항목을 선택한 뒤 돌아와 확인하세요. 0.1.1 실제 Windows 시험에서도 이 미리보기 지연이 관측됐습니다. 목록 갱신과 선택 미리보기의 동작을 구분합니다.

## 로그

operations.jsonl에는 시각, 동작, 대상 경로, 이전·새 상태, 결과, 오류 코드·메시지가 기록됩니다. 업무폴더 안에는 로그를 쌓지 않습니다. 기본 외부 전송이나 원격 분석이 없습니다. 지원에 전달하기 전 실제 사용자·업무 경로를 가립니다.
