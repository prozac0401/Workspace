# 선택범위 내보내기 · RC11 오류 위치 안내 검증

기록일: 2026-10-03 · 대상: 0.1.0-rc.11 · 서명 없는 평가판

제품 책임: 도구 개발·검증 담당

관련 문서: [원작업지시](../tools/excel-selection-export/specification.md), [인수 대응표](../tools/excel-selection-export/acceptance.md), [RC10 Undo 검증](excel-selection-export-undo-20260926.md), [RC10 종료 후속 확인](excel-selection-export-lifetime-20260927.md), [RC10 설치 후속 확인](excel-selection-export-installer-20260927.md)

## 변경과 판단 범위

PR #10의 서식 오류 안내 개선은 지원하지 않는 서식을 처음 발견한 셀의 원본 행·열 번호를 기존 사유 앞에 붙인다. 지원 범위, 셀 제외 여부, 출력 생성과 정리 계약은 바꾸지 않는다. 이번 공개 후보는 RC11 평가판이며 정식·상용 배포 승인본이 아니다.

RC10의 실제 메뉴·Undo/Redo·설치·제거·종료 시험은 당시 버전의 기록으로 보존한다. 이번에는 변경된 두 거절 흐름만 실제 Excel에서 직접 실행했다. 설치된 메뉴 콜백이나 팝업, 새 RC11 설치·자동 로드의 완료로 해석하지 않는다.

## 환경과 실제 결과

| 항목 | 확인 범위·결과 |
|---|---|
| 환경 | 현재 PC의 Windows 11 Pro, 데스크톱 Excel x64 16.0.20430.20092 (Build 20430), .NET Framework C# 컴파일러 4.8.9232.0 |
| 후보 | PR head `82a690f624e83470129c8832688ec74356062745`의 제품 소스. 설치 버전은 RC11, 기존 COM AssemblyVersion `0.1.0.0` 유지 |
| 빌드·자동 검사 | x86/x64 DLL·설치 EXE 생성. 각 비트수 M1 19·planner 26·engine guard 51·output workspace 25, 공통 배포 21: 합계 **263 PASS** |
| 실제 실행한 DLL | x64 `ExcelSelectionExport.AddIn.dll`, SHA-256 `63a39d163bb46b0450fc257012bf7fffbee43eae4a8b9a9588025aae13c15b7d` |
| 방식 | ExcelProbe가 별도로 연 합성 통합문서·정확한 PID에 연결. 후보 DLL의 `ExportEngine.Run`을 STA에서 직접 호출. 사용자 업무 문서·기존 설치 등록 변경 없음 |
| 혼합 서식 | C24:G28 선택, 25행·D열 숨김, E27 문자별 Bold 혼합 및 실제 DisplayFormat의 mixed/null 확인. **15 PASS** |
| 그라데이션 | 같은 선택·숨김, E27 실제 선형 그라데이션 Pattern 4000 확인. **14 PASS** |
| 소유권·완료 검사 | 전용 PID·시작 문서·초기 상태와 마지막 원본 유지 확인 **7 PASS**. 두 사례 총 **36 PASS** |
| UI·종료 | Computer use로 전용 합성 시작 문서의 실제 화면과 완료 후 같은 문서를 확인. 두 임시 시험 문서만 저장 없이 닫고, 시작 문서는 ExcelProbe로 정상 Close/Quit. 전용 프로세스 자연 종료 PASS, 강제 종료 없음 |
| 로컬 증거 | `artifacts/selection-export/release-validation/`의 helper·결과 JSON·소유권 marker. 개인 경로와 원시 진단은 공개 안내·설치 자산에 포함하지 않음 |

빌드 중 일부 시험 EXE의 프로세스 생성이 Win32 5로 한 차례 거절됐으며, 기존 빌드 스크립트가 같은 EXE 생성을 재시도한 뒤 정상 실행했다. 실패한 시험 결과를 통과로 바꾼 것은 아니다. 상세 launch 기록은 로컬 artifacts에 보존한다.

문서 `python -m mkdocs build --strict`와 `scripts/check-site.py site`가 통과했다. 공개 19페이지·이전 주소 이동 2개·404, 공개 검색·사이트맵·허용 자산·로컬 링크를 확인했다. 이번 관련 Markdown의 상대 파일 링크 17개도 누락 0개다. 검증 기록·원시 진단은 생성 사이트에 포함되지 않는다.

## 두 거절 흐름의 완료 기준

두 사례 모두 다음을 실제 비교해 통과했다.

- 정확한 오류는 `원본 27행 5열: `과 기존 혼합 서식 또는 그라데이션 사유의 결합이다. 압축된 결과의 3행 2열로 안내하지 않는다. 원래 원인 예외도 보존한다.
- 거절 전후 원본 XML, 값·수식, 문자별 글꼴과 첨자, 그라데이션 색상점, 숨김·너비·높이, 저장 여부, 선택·활성 문서가 같다.
- Interactive·ScreenUpdating·EnableEvents·DisplayAlerts·Calculation 및 StatusBar의 값과 타입이 복구된다.
- 부분 결과 통합문서가 생기지 않으며 제품 임시 GUID 폴더 목록과 Excel PID 목록이 같다. 업무 폴더를 순회하거나 잔존 프로세스를 강제 종료하지 않는다.

## 남은 제한과 출시 채널

RC11에서 실제 메뉴·팝업, 재설치·자동 로드, Undo/Redo, 성공 출력, 취소와 다른 실패 단계는 재실행하지 않았다. 변경과 무관한 RC10 완료 수동 시험을 새 시험으로 합산하지 않는다. x86 Excel 실기, 새 사용자·격리 VM, 재로그인·재부팅, ACL·강제 중단, 모든 추가 기능·문서 조합, 코드 서명과 조직 배포 승인은 여전히 미완료다.

RC5 설치 전후 설정 비교의 29 PASS / 4 변경 FAIL과 원인 미확정, RC9 Undo 실패, 과거 API 시험의 Excel 잔존 및 후속 미재현 기록도 보존한다. 이번 오류 위치 개선이 그 원인을 새로 해결했다고 주장하지 않는다.

RC11은 제한을 명시한 GitHub 사전 릴리스로 제공한다. 최종 설치 파일 해시는 릴리스의 SHA256SUMS와 빌드 manifest에서 확인하며, 직접 native 시험한 위 DLL을 최종 패키지에 유지한다. 실제 게시와 원격 자산 검증은 별도 완료 기록으로 남긴다.
