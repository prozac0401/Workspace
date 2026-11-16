# ExcelPasswordSafe 1.3.0 · 화면 개편과 실제 사용 검증

기록일: 2026-11-16 · 대상 버전: 1.3.0 · 로컬 평가 후보  
책임: 도구 개발·검증 담당  
관련 문서: [현재 명세](../tools/excel-password-safe/specification.md), [사용 안내](../tools/excel-password-safe/index.md), [기본 설계](../design/0018-excel-password-safe-explorer.md), [1.2.0 검증 기록](excel-password-safe-20261116.md)

## 요청과 변경 범위

사용자는 노랑·초록 계열을 사용한 화면을 선호하지 않는다고 알리고 더 현대적인 UI 구현과 잠금 해제 후 실제 동작 검증을 요청했다. 1.3.0은 차가운 흰색·슬레이트 회색·남색·코발트 파란색 구성, 둥근 카드와 입력창, 구분된 작업 선택으로 화면을 개편했다.

암호 설정·해제·변경의 입력 조건, 현재 사용자 DPAPI 전달, 원본 해시·백업·검증·원자 교체, 취소·복구, Explorer 메뉴와 MSI 설치 범위는 유지한다. 소스·화면·실제 Explorer 클릭·실제 Excel 처리·설치 수명주기 결과를 따로 기록한다. 1.2.0에서 잠금 화면 때문에 클릭하지 못했던 사실과 기존 검증 기록은 수정하지 않는다.

## 실행 결과

아래 표는 이번 버전에서 확보한 증거만 기록한다. 이전 버전의 통과 수를 새 시험 결과로 합산하지 않는다.

| 시험 | 상태 | 결과·제한 |
|---|---|---|
| UI 소스·런타임 계약 독립 검토 | PASS | 명시적 Tab 순서·초점 표시·마스킹·접근성 이름·고정 상태/버튼 확인. C# Workflow·ApplyClick·RequestCancel·ReadProgress4개 구간이1.2.0과 동일. `ui-review-1.3.0-20261116/ui-review.json`, `workflow-comparison.json` |
| 암호 엔진 불변 확인 | PASS | 1.2.0 최종 빌드의 Common.ps1·Engine.ps1·ExcelPassword.Worker.ps1과 현재 소스의 SHA-256이3개 모두 동일. `ui-review-1.3.0-20261116/runtime-comparison.json`. UI 실제 동작 검증과 구분 |
| 코어·컨트롤러·앱 검사 | PASS | 최종1.3.0 빌드의 코어58개·컨트롤러 장애6사례·앱31개, 합계95개 통과. 실제 UI·Excel 조작 시험과 구분 |
| WPF 렌더·시각 검토 | PASS | 최종 빌드 `ui-smoke`에서 6상태 × 출력 DPI 96/144/192의 18장 + 520×520 소형 창 6장 = 24장. 앞선 동일 UI 후보004의 기본 변경·진행·작은 오류3화면을 독립 시각 검토. 기본 변경 폼의 동의 표시와 작은 창의 상태·버튼 노출 확인 |
| 실제 Explorer 메뉴·파일 전달 | PASS | 잠금 해제된 탐색기에서 합성 XLSX를 오른쪽 클릭하여 `Excel 암호 관리`를 보고 선택했다. 설치된1.3.0 앱의 전체 경로가 한글·공백·`&`를 포함한 선택 경로와 일치했다. TXT의 기본 컨텍스트 메뉴에는 명령이 없음을 확인. 다른 확장자의 실제 클릭과 구분 |
| 실제 UI 마스킹·동의·암호 확인 불일치 | PASS | 암호 마스킹과 동의 전 실행 비활성을 확인했다. 확인 암호가 다를 때 한국어 오류가 표시되고 파일 해시가 같으며 새 실행 폴더가 생성되지 않았다. `ui-modern-20261116/mismatch-result.json` |
| 실제 UI 암호 설정 | PASS | 완료 문구와 `작업 상태` 제목 복원, 입력 지움·동의 해제를 실제 화면에서 확인. `ui-modern-20261116/encrypt-result.json`: 현재 파일=결과 해시, 백업·recovery=원본 해시, 요청 파일 제거와 Excel 종료 확인 |
| 실제 UI 잘못된 현재 암호 거절 | PASS | 실제 암호 변경에서 `OpenFailedPossiblePasswordOrCorruption` 오류를 표시했다. 암호가 걸린 현재 파일·백업의 해시 유지, 요청 파일 제거와 Excel 종료 확인. `ui-modern-20261116/wrong-current-result.json`. 여러 줄 오류에도 상태·버튼이 보이고 본문 스크롤로 동의에 도달함을 확인 |
| 실제 UI 암호 변경 | PASS | 완료 문구·상태 제목·입력 초기화를 실제 확인. `ui-modern-20261116/change-result.json`의8개 확인이 모두 참: 설정 결과와 입력 연결, 현재·결과 해시, 백업·recovery·원본 해시, 요청 제거·Excel 종료 등. worker의 이전 암호 거절 검증도 통과 |
| 실제 UI 암호 해제·왕복 내용 확인 | PASS | 새 암호로 해제 완료, `decrypt-result.json`의8개 확인 모두 참. `roundtrip-content.json`에서 최종 평문 OOXML, 시트1개 이름, 셀·수식3개, 삽입 그림1개의 바이트가 원본 합성 fixture와 일치. 다른 형식·모든 통합문서 기능의 보존으로 일반화하지 않음 |
| MSI 제작·정적 검사 | PASS | `build-1.3.0-20261116-211627-83326b50` 빌드 통과. 현재 사용자·HKCU 메뉴4개·단일 파일 인수·payload6개·내장 파일 해시 확인. 미서명 평가 패키지 |
| MSI 정상 설치·복구·제거·재설치 | PASS | `installer-20261116-211820-aa45702e/installer-results.json`의63개 검사 통과. elevated=false. 최종1.3.0 MSI 설치·누락파일 복구·재설치·제거와 합성자료·기본연결 보존 확인 |
| MSI 1.2.0→1.3.0 업그레이드·다운그레이드 차단 | PASS | `installer-20261116-211928-50ec5f7a/installer-results.json`의79개 검사 통과. elevated=false. 설치위치 유지·하위버전 거절·최종제거 뒤 관련제품0개·메뉴4개 없음. 정상63개와 중복 합산하지 않음 |
| 실제 사용 시험 뒤 제거·보존 확인 | PASS | `ui-modern-20261116/cleanup-result.json`의16개 확인 모두 참. 관련제품0개, EXE·프로세스 제거, 메뉴4개 없음, 미선택 합성파일4개·백업4개 해시 보존, 최종 해제 파일 유지. 제거 뒤 실제 XLSX 우클릭에서도 명령이 사라짐을 확인. 시험용 Explorer 탭만 닫고 원래 Home 탭 보존 |
| 문서 strict 빌드·로컬 링크 | PASS | `.tools/docs-venv/Scripts/python.exe -m mkdocs build --strict`와 `scripts/check-site.py site` 종료0. 공개20페이지+404·검색·사이트맵·비공개 제외·로컬 자산/경로 확인. 관련 문서7개 상대링크32개 오류0 |
| 실제 물리 고DPI 모니터·다른 Office·새 사용자·화면 읽기 프로그램·Windows 고대비 | NOT RUN | 이번에 실행한 범위만 확인했다고 표시 |
| 코드 서명·조직 승인·인터넷 게시 | NOT RUN | 미서명 평가판. 공개 사이트 허용 목록 변경 없음 |

실제 Explorer·WPF 조작은 `ui-modern-20261116/gui-observations.json`의17개 관찰 항목으로 기록했다. 위 UI 행들은 이 관찰과 연결된 파일·백업 검사를 풀어 쓴 것이며 서로 중복 합산하지 않는다. 처리 중 입력·작업 선택 비활성화와 취소 버튼 제공, 완료 후 상태 제목·입력·동의 초기화, 정상 닫기와 제거 후 메뉴 소멸도 관찰했다. 실제 취소 버튼을 눌러 작업을 중단하는 시험이나 다른 파일 형식의 GUI 전체 경로 시험은 이번 기록에 포함하지 않는다.

## UI 후보 검토와 보완

완료·취소 본문을 표시해도 상태 카드 제목이 `처리 중`으로 남을 수 있던 점을 수정했다. 마지막 오류 상태를 보존하고 busy 상태가 끝날 때 제목을 다시 평가한다. 하단에 고정된 상태 카드에서 `아래 안내`라는 방향 표현을 `백업 안내`로 고쳤다.

비선택 작업 버튼의 글자 대비를 보완하고 Tab 순서를 명시했다. 확인한 정상 본문·백업·작업 선택·상태·실행 버튼·오류의 정적 색상쌍 대비는4.51~6.38:1이다. `contrast-review-final.json`에 계산 근거를 남겼다. 이 계산과 명시적 초점 스타일만으로 화면 읽기 프로그램이나 전체 접근성 표준 적합성을 판정하지 않는다.

스크롤 본문과 상태·실행 버튼 영역을 분리했다. 기본 창에는 암호 변경 입력과 백업 동의가 보이며, 작은 창에는 본문 스크롤과 오류·실행·닫기 영역이 함께 보인다. WPF 렌더는 클라이언트 내용을 대상으로 하며 물리 모니터 배율 변경 시험을 대신하지 않는다.

## 이전 버전에서 남은 제한

1.2.0의 제품 등록 이후 강제 실패 시험에서는 파일·메뉴는 제거됐지만 Windows Installer 등록이 남았다. 새 식별자를 준 시험 사본에서도 재현됐으며 제품 등록 전 실패 주입의 통과와 구분했다. 이 화면 개편으로 문제가 해결된 것으로 간주하지 않는다.

설치 실패 후 앱 항목만 남거나 재설치해도 메뉴가 없으면 같은 MSI를 열어 **프로그램 제거**를 선택한 다음 재설치한다. 정상 수명주기 통과는 모든 설치 실패의 자동 복구 통과를 뜻하지 않는다. 운영체제 권한이나 보안 설정을 바꿔 시험을 우회하지 않는다.

암호가 없던 원본의 백업·recovery에는 평문이 남을 수 있다. VBA 소스·그림·개체·외부 참조의 완전한 동작 보존은 대표 파일 검증이 필요하다. 1.2.0의 Excel34사례와 VBA 스트림·소스 비교 결과는 과거 근거이며 1.3.0의 새 실기 시험과 구분한다.

## 산출물과 재현

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/ExcelPasswordSafe/build/build.ps1 -Version 1.3.0
```

빌드·설치 진단과 합성 자료는 `artifacts/excel-password-safe/`에 보관한다. 최종 빌드 폴더는 `build-1.3.0-20261116-211627-83326b50`이며 `build-result.json`, `source-sha256.txt`, `runtime-continuity.json`, 시험 기록과 `msi-verification.json`을 함께 확인한다. 소스·안내·평가 MSI 제작과 공개 릴리스·사이트 게시는 별개의 작업이다.

| 패키지 항목 | 값 |
|---|---|
| 파일명 | `ExcelPasswordSafe-1.3.0-win-x64-evaluation.msi` |
| 사용자 전달 위치 | `artifacts/excel-password-safe/release/ExcelPasswordSafe-1.3.0-win-x64-evaluation.msi` |
| 크기 | 86,016 bytes |
| SHA-256 | `460D795DD6FB4FC46D441B31346A639AEAC89C08A881372F6B8DF62AC52D1900` |
| 서명·배포 상태 | 서명 없음, 로컬 평가용. 조직 승인·인터넷 게시 없음 |
