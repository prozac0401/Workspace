# 구조와 데이터 계약

## 구성

```text
Explorer 메뉴 ─→ FolderState.exe (WPF / 명령 처리)
관리 화면 ─────→ FolderState.Core
CLI ───────────→ FolderState.Core
                    ├─ 상태 메타데이터
                    ├─ desktop.ini 소유 키 수정
                    ├─ 변경 전후 기록·복원
                    └─ Explorer 갱신·로컬 로그
```

업무파일을 열거나 하위 목록을 얻는 API는 상태변경 경로에 없습니다. 작업은 선택 폴더의 고정 파일만 읽고 씁니다. 경로 조상 검증은 경로 깊이에, 일괄 처리는 지정한 폴더 수에 비례합니다.

## 소유 파일

| 이름 | 용도 | 보존·변경 |
|---|---|---|
| .folderstate.ini | 실제 상태·시각·모드·원래 설정 백업 | 소유자·버전 검증 후 원자적 교체 |
| desktop.ini | Explorer 표현 | IconResource / IconFile / IconIndex만 관리 |
| .folderstate.ico | Portable 아이콘 | 소유 해시가 맞을 때만 교체·삭제 |
| .folderstate.transaction | 중단 복원을 위한 임시 기록 | 성공 시 삭제; 충돌 시 보존 |
| .folderstate-랜덤.tmp | 같은 디렉터리의 임시 쓰기 | 정상 처리 후 삭제 |

업무 메타데이터는 Hidden/System으로 표시합니다. 폴더에는 기존 속성을 유지하며 ReadOnly 표시 비트를 추가합니다. 이는 파일 쓰기 권한을 변경하는 작업이 아닙니다.

```ini
[FolderState]
Version=1
Owner=FolderState
Status=doing
Updated=2026-09-12T10:46:00.0000000+09:00
Mode=local

[FolderStateBackup]
Data=Base64로 인코딩한 복원 데이터
```

백업에는 원래 desktop.ini 바이트·속성, 폴더의 원래 ReadOnly 비트, 마지막 도구 표현, Portable 아이콘 해시를 저장합니다. 업무파일 내용은 포함하지 않습니다. 원문 예시에 없는 Owner와 백업 필드는 안전한 소유 확인을 위해 필수로 추가했습니다. 이 정보가 없는 기존·외부 상태 파일은 추정하여 덮어쓰지 않습니다.

## 변경과 복구

1. 일반 폴더·조상 경로·메타데이터의 링크 여부를 검증합니다.
2. 경로별 프로세스 간 잠금을 획득합니다.
3. 이전 작업 기록이 있으면 내용 충돌을 검사하고 복원합니다.
4. 기존 설정과 변경 후 결과를 계산합니다.
5. 변경 전후 데이터를 디스크에 먼저 기록하고 flush합니다.
6. 같은 디렉터리의 임시파일과 원자적 replace로 고정 파일을 갱신합니다.
7. 속성을 반영한 뒤 작업 기록을 삭제하고 Explorer에 통지합니다.

여러 파일 전체가 하나의 파일시스템 원자적 연산인 것은 아닙니다. 오류·중단 시 기록으로 복원하며 외부 내용과 다르면 자동 덮어쓰기를 멈춥니다. 전원 손실·저장장치 결함에 대한 보장은 별도 검증 대상입니다. 강제 종료 시 임시파일이 남을 수 있으며 무작위 업무 폴더 탐색으로 정리하지 않습니다.

## 기존 설정 보존

UTF-16 LE/BE, UTF-8, 현재 Windows 코드페이지 입력을 읽습니다. Explorer에 적용하는 INI는 Unicode로 저장합니다. 중복 섹션·키는 모호하므로 변경하지 않습니다. 초기화 시 도구가 작성한 내용 그대로라면 원래 바이트·속성을 복원합니다. 외부에서 수정된 경우 소유한 아이콘 키만 조건부 복원하고 다른 섹션·키를 유지합니다.

단일 메타데이터는 512 KiB, 복원 기록은 4 MiB로 제한합니다. 변경된 외부 아이콘, 알 수 없는 상태 버전, 훼손된 복원 기록은 보존합니다. SMB의 교체·속성·잠금 의미는 로컬 NTFS와 다를 수 있어 지원 보증 범위가 아닙니다.

[Microsoft desktop.ini 공식 문서](https://learn.microsoft.com/en-us/windows/win32/shell/how-to-customize-folders-with-desktop-ini)
