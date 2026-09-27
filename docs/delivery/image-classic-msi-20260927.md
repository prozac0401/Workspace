# 그림 복사·저장 — 공통 메뉴와 무서명 MSI 검증

날짜: 2026-09-27 · 책임: 도구 개발·검증 담당 · 상태: 실기 검증 진행 중

## 적용한 요구

사용자가 Windows 11 기본 메뉴의 ‘더 많은 옵션 표시’와 Windows 10 형식의 직접 우클릭 메뉴 양쪽에서 접근하도록 승인했다. 시험을 위한 메뉴 모드 전환과 원상복구도 승인했다. [v1.2 변경 계약](../tools/image-copy-save/ImageCopySave_Requirements_v1.2.md)과 [ADR-0023](../design/0023-image-copy-save-classic-menu.md)을 적용한다. 실제 Windows 10 OS의 실행 검증으로 확대하지 않는다.

제품은 자체 포함 무서명 MSI이며, 설치는 관리자 권한으로 수행하고 평소 명령은 일반 사용자로 실행한다. 두 native COM 클래스와 폴더 배경·네 이미지 확장자의 메뉴 등록을 MSI 기본 자원으로 관리한다. 제품 MSI에는 MSIX, 인증서 설치, 실행형 custom action, 메뉴 모드 변경이나 Explorer 자동 종료가 없다. 이전 관리자 sparse identity 실증은 [당시 기록](image-admin-install-20260927.md)으로 보존한다.

## 패키지와 설치

| 항목 | 실제 결과 | 범위 |
|---|---|---|
| 0.1.0·0.1.1 MSI 구조 | PASS | 무서명, PC 전체 x64, 자체 포함 404개 파일, 내장 cabinet 1개, COM 서버 2개·verb 5개 |
| 정상 0.1.1 후보 | 생성·정적 검사 PASS | 50,245,652 bytes. 최종 재설치 상태 확인 |
| 0.1.0 최초 설치 | PASS | 관리자 상승 확인, msiexec 0, 모든 설치 파일 해시 일치, 재부팅 요구 없음 |
| 설치 파일 누락 후 복구 | PASS | 소유한 Engine.dll의 원본 해시 확인·백업·삭제 후 MSI 복구, 모든 파일 해시 복원, msiexec 0 |
| 0.1.0 → 0.1.1 업데이트 | PASS | 관리자 상승 확인, msiexec 0, 새 파일·등록 검증과 이전 제품 제거 확인 |
| 제거 | PASS | msiexec 0, 제품 파일·등록·설치 상태 제거 확인 |
| 고의 실패 롤백 | PASS | 의도한 msiexec 1603 이후 제품 파일·등록·설치 상태 잔류 없음 |
| 0.1.1 재설치 | PASS | msiexec 0, 모든 파일 해시·등록 확인, 최종 설치 상태 유지 |

0.1.1 후보 SHA-256: `418C8774355A59EAEF16CE24A318F91B8D5F77D29B517808B3AA83B9A7A917F5`.

고의 실패 MSI는 별도 ProductCode를 가진 로컬 시험 파일이며 일반 제품 검사기는 이를 거절한다. 제품 설치 파일로 전달하지 않는다. 복구 시험 스크립트는 설치 경로와 조상의 reparse point를 거절하며, 시험 실패 시 검증된 백업으로 누락 파일만 복원한다. 새로 존재하는 파일은 덮어쓰지 않는다. 이 방어의 합성 회귀 6건이 통과했다.

첫 업데이트 UAC 요청은 02:05:27Z에 시작해 02:07:30Z에 `ELEVATION_NOT_STARTED`로 끝났다. Windows 오류 문구는 ‘사용자가 작업을 취소했습니다’이며 원인을 사용자 직접 취소나 시간 초과 중 하나로 단정하지 않는다. 이후 승인된 요청으로 실제 업데이트가 통과했다. 직후 시험 묶음의 결과 읽기가 UTF-8 한글과 빈 이름의 레지스트리 기본값을 처리하지 못해 다음 단계 전에 멈췄다. UTF-8 Dictionary 읽기로 수정하고 실제 결과 파일 회귀를 통과한 뒤, 나머지 제거·롤백·재설치를 재승인해 순차 완료했다. 제품 설치 실패와 시험기 결과 읽기 실패를 구분한다. 모든 설치 단계에서 재부팅 요구는 없었으며 Explorer를 종료하지 않았다.

## 실제 Explorer 결과

시험 자료는 전용 합성 폴더와 이미지다. 기존 업무 Explorer 창과 파일은 조작하지 않았다. 아래 실제 메뉴와 8회 반복은 현재 PC의 Windows 11에서 클래식 메뉴를 직접 여는 설정과 0.1.0 설치로 확인했다. 0.1.1 재설치 후 재개는 UI 도구의 창 활성화 실패로 새 메뉴를 관찰하지 못했다. 두 버전의 자체 포함 404개 파일은 모두 해시가 같으며 버전·제품 코드만 변경했지만, 이를 재설치 후 UI 실행 증거로 대신하지 않는다.

| 시험 | 클래식 직접 표시 | Windows 11 ‘더 많은 옵션 표시’ |
|---|---|---|
| 이미지 단독 저장 명령 | PASS, 독립 활성 항목 | NOT RUN |
| 빈 상태·텍스트·URL·HTML | PASS, 저장 명령 완전 부재 | NOT RUN |
| 이미지와 텍스트 동시 제공 | PASS, 저장 명령 활성 | NOT RUN |
| PNG의 일반 Ctrl+C 파일 복사 | PASS, 저장 명령 부재·기존 붙여넣기 유지 | NOT RUN |
| 이미지 한 개에서 복사 명령 | PASS, PNG 실제 이미지 복사 성공 | NOT RUN |
| 텍스트 파일·PNG 두 개 선택 | PASS, 복사 명령 부재 | NOT RUN |
| 실제 PNG 저장 | PASS, 호출한 A 폴더에 8×8 PNG 생성 | NOT RUN |
| 이미지→텍스트→빈 상태→이미지 20회 | 8회·25개 관찰 PASS, 9~20회 미완료 | NOT RUN |
| 메뉴 모드 원상복구 | 아직 설정 변경 전 | NOT RUN |

첫 저장의 클립보드 시퀀스는 실행 전후 964로 동일했다. 파일 복사 메뉴를 실행한 뒤에는 PNG·CF_DIBV5·CF_BITMAP·CF_DIB 형식이 확인됐다. URL·HTML·혼합 이미지와 후속 반복 메뉴를 열 때 클립보드 시퀀스와 합성 폴더 파일 목록이 바뀌지 않았다. 외부 앱 전체의 붙여넣기·투명도 시험으로 확대하지 않는다.

실제 저장 중 설치 폴더의 `ImageCopySave.Helper.exe`와 Explorer가 같은 사용자 세션에서 모두 `elevated=false`인 것을 관찰했다. 명령 종료 뒤 읽기 전용 조회에서 helper가 남지 않는 것도 확인했다. 최초 관찰은 helper 종료 후였고, 재시도 하나는 UI 시험 입력이 의도한 저장 명령에 도달하지 않아 `NOT_FOUND`였다. 이후 제한 시간 내 프로세스를 관찰하는 읽기 전용 검사로 실제 helper를 확인했으며 앞선 미관찰 결과를 성공으로 바꾸지 않는다.

MSI 완료 후 9회차를 재개하려 했으나 UI 도구가 `failed to activate captured window`를 반환했다. 새 창 선택·관찰과 1회 복구 뒤에도 같은 오류여서 추가 입력을 중지했다. 새 메뉴 관찰이나 제품 실패로 합산하지 않는다. 사용자에게 시험 Explorer 창의 활성화를 요청했으며, 아직 메뉴 설정은 변경하지 않았다. 설치 후 합성 원본 세 파일의 해시는 모두 보존됐다.

모드 전환 시험기는 기존 키를 복사·삭제하는 방식 대신 native `RegRenameKey`를 사용하도록 보완했다. 원래 키의 값·형식과 Owner/Group/DACL을 기록하고 왕복 시 비교하며, 외부 변경이나 대상 키 충돌이면 덮어쓰지 않는다. 별도 합성 HKCU 키의 왕복·보존·충돌 거절 7건과 시험 키 정리는 PASS다. 실제 메뉴 키는 Inspect만 수행해 원래 키 존재·백업 키 부재·변경 없음으로 확인했다. 합성 시험을 실제 메뉴 전환·복구 PASS로 합산하지 않는다.

## 근거와 남은 검증

로컬 진단은 공개 사이트에 포함하지 않는다.

- `artifacts/image-copy-save/msi/`: 패키지, 입력 해시, 빌드·정적 검사 근거.
- `artifacts/image-copy-save/msi-lifecycle/20260927T020108652Z-e87eb8d13468422590a0d946684cc47f/`: 최초 설치 PASS.
- `artifacts/image-copy-save/msi-lifecycle/20260927T020145046Z-b6795071d83d4d3797ab943c1901a090/`: 파일 누락 후 복구 PASS.
- `artifacts/image-copy-save/msi-test-launch/4e7d883423ba45af8259a792a84dece8/`: 업데이트 상승 요청 취소.
- `artifacts/image-copy-save/msi-lifecycle/20260927T022804961Z-d3e98faf27bd43c7b0bb37748c662bb7/`: 실제 업데이트 PASS.
- `artifacts/image-copy-save/msi-final-sequence/20260927T022738797Z-b020b49a17d44a4c9d2c7903414f341b/`: 업데이트 통과 후 시험기 결과 읽기 실패.
- `artifacts/image-copy-save/msi-final-sequence/20260927T023218720Z-24b38a00689d4157911b120071978ce1/`: 제거·고의 실패 롤백·재설치 PASS.
- `artifacts/classic-validation-20260927/explorer-observations.json`: 실제 메뉴·실행 관찰.
- `artifacts/classic-validation-20260927/classic-repeated-menu.json`: 반복 전환의 개별 관찰.
- `artifacts/classic-validation-20260927/runtime-save-observed2.log`: 실제 Explorer·설치 helper 비상승 확인.
- `artifacts/classic-validation-20260927/runtime-idle.log`: 명령 종료 후 helper 미잔류 확인.
- `artifacts/classic-validation-20260927/fixtures-after-msi-sequence.json`: MSI 완료 후 합성 원본 세 파일 해시 보존.
- `artifacts/classic-validation-20260927/ui-resume-block.json`: 재설치 후 UI 도구의 창 활성화 실패와 미완료 범위.
- `artifacts/admin-install-20260927/native-menu-rename-result.json`: 별도 합성 키의 native 이름 변경·권한 보존·충돌 거절 7건.

문서 엄격 빌드와 공개 사이트 검사는 PASS다. 공개 19개 페이지·404·검색·사이트맵·로컬 링크를 확인했고 진단 자료는 공개 출력에서 제외됐다. 변경 Markdown 12개의 로컬 링크 153개를 점검해 신규 깨진 링크는 없었다. 과거 시험 기록의 로컬 진단 링크 13개는 원래부터 현재 worktree에 없는 산출물을 가리키며 과거 이력으로 보존했다. 원명세 v1.0/v1.1은 변경하지 않았다.

두 메뉴 모드의 전체 인수, 반복 전환과 원상복구를 완료하기 전에는 G0 전체 PASS로 표시하지 않는다. 이번 MSI 설치·복구·업데이트·제거·고의 실패 롤백·재설치는 통과했다. 실제 Windows 10, 새 PC, 재부팅·재로그인, 모든 외부 앱은 이 기록의 범위 밖이다. 과거 엔진/helper·Paint 시험은 기존 기록의 범위에서 유지하며 이번 MSI·메뉴 실기에 중복 합산하지 않는다.
