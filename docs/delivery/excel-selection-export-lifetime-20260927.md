# 선택범위 내보내기 · 종료 재검증

기록일: 2026-09-27 · 대상: 로컬 0.1.0-rc.10 x64 평가판 · 책임: 개발·검증 담당

관련 문서: [원작업지시](../tools/excel-selection-export/specification.md), [Undo 수정 기록](excel-selection-export-undo-20260926.md), [인수 대응표](../tools/excel-selection-export/acceptance.md), [순차 백로그](WORKSPACE_Tool_Backlog_20260926.md)

## 변경과 판정

원본 작업 폴더의 rc.10 제품 소스와 기존 Undo 수정 근거를 Git에 보존했다. 원격에 추가된 공개 FAQ는 유지한다. 중복 번호였던 로컬 Undo ADR은 [ADR-0018](../design/0018-excel-selection-export-undo.md)로 연결했다. 이번 종료 조사에서 제품 DLL은 변경하지 않았다.

ExcelProbe의 Close/Quit 호출 성공만으로 프로세스 종료를 성공 처리하던 판정을 수정했다. Application·Workbooks·Workbook과 inspect에서 획득한 COM 참조를 각각 finally에서 반환하고, 해당 프로세스가 15초 안에 자연 종료해야 성공한다. 다른 문서가 있거나 소유 fixture 경로가 다르면 닫지 않는다. 프로세스를 강제 종료하는 코드는 없다.

현재 PC에서는 수정 프로브의 종료 검사가 통과했다. 기존 프로브도 별도 대조에서 자연 종료했으므로, 과거 잔존 현상의 원인이 프로브에만 있었다고 단정하지 않는다. 이전 FAIL 기록은 당시 증거로 보존한다. 이번 변경은 참조 책임과 성공 판정을 명확히 하며, 재발 시 종료0으로 숨기지 않게 한다.

## 실제 확인

Windows 11, Excel x64 16.0 Build 20326, 합성 자료만 사용했다. 시작 전 Excel 0개와 선택범위 내보내기 미설치를 확인했다. 기존 다른 추가 기능의 등록은 변경하지 않았다.

| 시험 | 결과 |
|---|---|
| 미설치 상태의 합성 Excel Close/Quit | PASS · 명시적 COM 반환 후 자연 종료 |
| 기존 rc.10 x64 설치 EXE 실행 | PASS · 종료0, 실제 자동 연결 connected=True·ribbon=True |
| 설치 후 기능 미사용 Close/Quit | PASS · 수정 프로브가 실제 프로세스 부재 확인 |
| 설치된 rc.10의 API 구조 사례 | PASS · 1사례·225검사, 원본 보존·가시 범위 결과·결과 활성화·시험 문서 정리 |
| 위 기능 사용 후 Close/Quit | PASS · 수정 프로브가 실제 프로세스 부재 확인 |
| 기존 프로브 대조 | PASS · 별도 세션 종료0 뒤 해당 PID 부재. 과거 FAIL 원인 확정 불가 |
| x64 통합 helper 6개 컴파일 | PASS · 컴파일 종료0, 전체 6종 실기를 실행한 뜻은 아님 |

rc.10 설치 파일 SHA-256은 `9171be45330ce9af86ce7b5eb06614211e3620bd47893912b03dd6ff2829114a`이며 기존 Undo 기록의 최종 산출물과 같다. 단위249·API930·실제 메뉴 Undo/Redo110·출력취소17 검사는 이전 기록을 재사용하며 이번에 다시 실행한 수치에 합산하지 않는다.

초기 일반 사용자 PowerShell wrapper에서 인자 전달 실패가 있었고 Excel 시작 전에 종료했다. 직접 helper 실행 경로로 위 검사를 수행했다. 컴파일 직후 한 차례 실행 생성 실패도 재시도 전 기록했다. 이를 제품 실패나 제품 검사 PASS로 집계하지 않는다. 상세 로그와 합성 fixture는 로컬 `artifacts/audit/backlog-20260926`에 보관하고 공개 사이트에서 제외한다.

실제 UI 종료·여러 번의 장시간 사용·x86 Office·새 사용자 프로필·재부팅까지 확대해 통과했다고 주장하지 않는다. rc.10 설치는 다음 T07 설치 수명주기의 시작 상태로 인계한다. 공개 다운로드는 rc.9이며, rc.10 공개 릴리스·사이트 게시와 조직 배포 승인은 수행하지 않았다.
