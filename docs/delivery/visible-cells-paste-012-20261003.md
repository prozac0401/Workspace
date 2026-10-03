# 보이는 칸 붙여넣기 · 0.1.2 출시 검증

기록일: 2026-10-03 · 대상: VisibleCellsPaste 0.1.2 · 서명 없는 배포물

제품 책임: 도구 개발·검증 담당

관련 문서: [원작업지시](../tools/visible-cells-paste/original-specification.md), [기존 인수 대응표](../tools/visible-cells-paste/acceptance.md), [제품 시험 보고서](../../tools/VisibleCellsPaste/docs/test-report.md), [배포 점검표](../../tools/VisibleCellsPaste/docs/release-checklist.md)

## 변경 범위

Workspace PR #10의 안내 개선은 붙여넣기가 끝났지만 기존 안전 조건 때문에 자체 Undo를 제공하지 못하는 경우 이를 상태바에 함께 알린다. Undo 거절 안내는 변경 없음이 이번 되돌리기에 해당한다는 뜻을 명시하고, 기존 완료 기록이 있을 때만 마지막 붙여넣기가 취소되지 않았다는 설명을 붙인다. 기존 값 쓰기·Undo 판단·이벤트 관찰·COM 수명·상태바 복원 정책은 유지한다.

0.1.2 배포에 맞춰 DLL 어셈블리·설치 등록 상수·설치 manifest는 0.1.2.0, 단일 EXE wrapper는 0.1.2.1로 맞췄다. 기존 설치 manifest의 허용 범위를 현재 버전만으로 바꾸면 공개 0.1.1 설치를 업데이트할 때 거절하므로, 같은 제품의 정확한 0.1.0.0·0.1.1.0 COM key/name만 계속 허용한다. 다른 제품·향후 버전의 임의 등록을 허용하지 않는다. 이 보정은 새 버전 제작에 필요한 호환 처리이며 Undo 기능 확대가 아니다.

## 환경과 자동 결과

현재 PC의 Windows 11 Pro·.NET Framework C# 컴파일러 4.8.9232.0·Windows PowerShell 5.1에서 `build/build.ps1 -Version 0.1.2`를 실행했다. x86/x64 DLL·설치 엔진·ZIP 생성과 다음 검사가 통과했다. 빌드가 실제 Excel 설치·자동 로드·사용을 검증하는 것은 아니다.

| 자동 검사 | 결과 |
|---|---|
| Core / native clipboard 형식 fixture / bulk snapshot | 47 / 35 / 8 PASS |
| AddIn lifecycle / COM x64 / COM x86 | 46 / 36 / 36 PASS |
| Global state recovery / presentation·entry / Setup | 20 / 41 / 33 PASS |
| 합계 | **302 PASS**, 안내 집중 회귀 15개와 새 이전 버전 호환성 3개 포함 |
| 후보 ZIP | 명시한 17항목·16파일 해시·x86/x64 PE·COM identity/dual interface·Ribbon callback/ID/tag·일반 DLL의 fault injection 부재 PASS |
| 컴파일 소스 | 원래 build manifest의 33개 입력 SHA-256. 최종 문서 재포장에서도 시험한 실행 payload와 이 manifest를 유지 |

설치 관련 자동 검사는 합성 파일의 소유권·경로·등록 목록과 CLR CodeBase를 확인했다. 0.1.0.0·0.1.1.0 각각의 이전 버전 기록과 현재 기록 4개씩을 중복 없이 보존하고 제거용 manifest를 읽을 수 있음을 확인했다. 외부 CLSID·Office 보안 키·향후 0.1.3.0 등록은 거절했다. 이 자동 검사를 실제 설치·업그레이드·제거 시험의 새 통과로 집계하지 않는다.

## 변경 안내의 최소 native 확인

시험한 x64 생산 DLL의 SHA-256은 `b9d79b4007d818e9208053467e68d15185716dfda030abf23bab3a04195177e0`이다. 기존 정렬 설정 때문에 Undo가 제공되지 않는 붙여넣기 성공 상태바와 이어지는 Undo 거절 안내를 한 합성 흐름으로 확인했다. 외부 callback 시험과 별도 설치본의 실제 UI 시험을 구분한다.

### 외부 callback 흐름: 36 PASS·종료 FAIL

시험 소유 Excel에 생산 DLL의 OnConnection을 수동 호출하고 Excel Range.Copy로 복사한 뒤 실제 Paste callback을 수행했다. 성공 상태바의 새 Undo 사용 불가 문구를 실제 화면에서 확인했고 생산 타이머가 상태바를 정확한 Boolean false로 복원한 것을 검증했다. 실제 Undo의 세 줄 생산 안내 창은 사용자가 확인 버튼을 누른 뒤 호출이 복귀했다. 거절 전후 셀·서식·숨김·선택 밖 무변경과 전역 속성 타입/값 복원을 포함한 36개 assertion이 통과했다. 하나의 흐름에 대한 검사이며 독립 native 사례 36개나 자동 로드·설치 시험을 의미하지 않는다.

그러나 같은 외부 호스트의 close/Quit는 15초 제한 안에 끝나지 않았으며 창이 숨겨진 뒤에도 시험 소유 Excel 프로세스가 남아 **종료 검사 FAIL**이었다. 잔류 프로세스는 후속 별도 작업에서 강제 정리했다. 강제 정리를 자연 종료 PASS로 집계하지 않는다. 원인은 미확정이며 이번 문구 패치의 회귀나 과거 종료 충돌 재현·해결로 단정하지 않는다.

### 같은 DLL의 설치본 실제 UI 흐름: 좁은 PASS

설치 전 양쪽 레지스트리 view에서 자체 제품 값 부재를 확인하고 후보 ZIP의 설치 엔진으로 시험 전용 위치에 같은 DLL을 `--silent` 설치했다. 최종 단일 EXE wrapper는 이 설치에서 사용하지 않았으므로 새 wrapper의 실제 설치 PASS로 바꾸지 않는다.

이후 Excel을 정상 `/x` 경로로 시작하고 외부 Excel COM·수동 OnConnection 없이 실제 UI에서 H1:J1을 Ctrl+C로 복사해 E2:E8의 제품 메뉴로 붙여넣었다. 보이는 E2/E5/E8의 숫자 85/90/78과 노란 배경·굵게·0.00 표시를 직접 확인했고 새 성공 상태바의 Undo 사용 불가 문구를 즉시 관찰했다. 실제 제품 Undo 메뉴를 눌러 세 줄 거절 안내를 확인 버튼으로 닫은 뒤 보이는 값이 유지된 것을 확인했다.

UI의 닫기와 저장 안 함을 거친 뒤 2026-10-03 10:34:17 UTC 독립 관찰에서 시험 소유 프로세스가 없었고 자연 종료를 확인했다. 해당 흐름 이후 새 Excel Application 1000/1001/1002 오류 이벤트는 0개였으며 합성 파일의 디스크 해시는 처음과 같았다. 시험 설치 제거는 종료0이었고 원래 자체 제품 등록 부재와 Excel 프로세스 0개를 복원했다. 이 설치본의 한 실제 메뉴 흐름·종료 결과는 앞선 외부 호스트 종료 FAIL을 지우거나 원인을 입증하지 않는다.

## 배포물과 미실행 범위

문서 동결 후 실행 payload 6개와 원래 build manifest를 바이트 단위로 유지하고 문서 9개만 다시 포장했다. 컴파일 입력 33개 해시가 그대로이며 최종 ZIP의 17개 항목·16개 내부 해시·PE/COM/Ribbon 검사가 통과했다. 이를 SHA-256으로 지정해 단일 EXE를 제작했고 wrapper 24개 검사가 통과했다. EXE의 0.1.2.1 어셈블리/파일 버전, NotSigned 상태, 내장 ZIP 바이트와 내장 예상 해시가 최종 ZIP과 일치함을 실행 진입점 호출 없이 확인했다. ZIP은 170,320바이트/SHA-256 `940f9c54382d1d18ded221cd26012d7cfe23551359cd138a763ea56df2e9f309`, EXE는 182,784바이트/SHA-256 `826108f3532d72e150e09fd55c2c6b721ec655ead0fa120f23d68f8828367ba9`이다. 문서 strict와 공개 사이트 검사도 통과했다(공개 19페이지·레거시 리다이렉트 2·404, 검색·사이트맵·로컬 링크·비공개 자료 제외). PR별 CI·main 병합·실제 게시 자산 결과는 문서 동결 이후의 [0.1.2 릴리스](https://github.com/prozac0401/Workspace/releases/tag/visible-cells-paste-v0.1.2) 및 PR에서 확인한다. 최종 해시는 릴리스의 SHA256SUMS와 별도 패키징 manifest에서 확인한다. 로컬 증거는 `artifacts/visible-cells-paste/release-validation/`에 남기며 원시 진단·개인 경로·합성 파일·클립보드 덤프는 공개 사이트나 배포물에 넣지 않는다.

0.1.1의 실제 설치·메뉴·Undo·정상 종료·제거·재설치는 당시 결과로 보존한다. 0.1.0과 이전 후보의 종료 FAIL, 이후 확인한 PASS 및 이전 충돌 원인 미확정도 유지한다. 이번 문구 개선이 과거 종료 원인을 새로 해결한 것으로 쓰지 않는다.

이번 변경과 무관한 기존 완료 전체 GUI·전체 설치 수명주기·전체 Excel suite는 재실행하지 않았다. 이번 추가 설치는 변경 안내와 자연 종료를 확인하기 위한 시험 전용 한 흐름이다. Office x86 실기·새 PC·새 프로필·재부팅·다른 추가 기능 전체 공존·코드 서명·조직 승인 미결정은 유지하며, 단위시험의 x86 native COM vtable 호출을 Office x86 통과로 확대하지 않는다.
