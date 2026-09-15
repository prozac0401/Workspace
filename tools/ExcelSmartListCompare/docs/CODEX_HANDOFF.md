# Windows 빌드·실기 검증 인계

상태: 설치 가능한 0.2.0 RC6 평가용 후보 · 2026-09-15

[RC6 창 전환 검증 기록](WINDOW_STATE_REPORT.md)에 새 XLAM의 검증 범위와 원복 상태를 기록했다. `CSLCAppEvents`가 창 활성화와 우클릭 직전 이벤트를 연결하고, 현재 창의 컨트롤만 공유 스냅샷에 맞게 갱신한다. UI 갱신을 위해 다른 파일을 활성화하거나 선택값을 읽지 않는다. 요구와 설계는 [ADR-0006](ADR-0006-Window-menu-state.md)을 따른다. RC1~RC5 보고서·캡처는 이전 기록이다.

## 현재 구현

- 첫 Selection 전체를 첫 번째 목록으로 담고 다음 Selection을 두 번째 목록으로 비교한다. 화면 용어와 검증 상태는 [창 전환 검증 기록](WINDOW_STATE_REPORT.md)을 따른다. 방향·모드 선택과 두 열 자동 분할을 추가하지 않는다.
- 가시 셀의 값과 개수를 비교하며 텍스트 앞자리 0을 보존한다.
- 기본 빌드는 저장한 XLAM을 다시 열어 실제 VBA 검사 후 Release를 만든다. RC5에서는 단독 재열기가 정체되어 저장된 파일을 승인된 제품 설치 경로에서 검증했다. 소스와 바이너리 대조, 실제 실행 결과를 확인한 뒤 `scripts/package-excel-wording-release.py`로 포장했으며 기본 빌드의 정상 종료로 기록하지 않는다.
- 빌드·진단은 소유 PID를 확인한 정상 Excel 시작을 사용한다. 시험 Office의 COM 자동화 모드는 VBProject 접근과 설치본 재열기에서 실패했다.
- 설치·제거는 Excel을 시작하지 않고 자기 LocalAppData 파일, HKCU의 정확한 제품 OPEN 경로와 제품 폴더 신뢰 위치를 관리한다.
- RC6 설치기는 이전 버전을 판별하고 제품 파일·OPEN·Add-in Manager 등록을 제거한 뒤 새 버전을 설치한다. 같은 버전 재설치, 최신 버전 보존, 패키지 사전 준비·원자적 파일 쓰기와 실패 복구는 [ADR-0007](ADR-0007-Replace-previous-installation.md), [업데이트 검증](UPGRADE_REPORT.md)을 따른다.
- Esc 입력을 받을 수 있도록 Interactive=False를 설정하지 않는다. mBusy로 재진입을 막고 담아 둔 첫 번째 목록과 설정을 복원한다.

## 후속 변경

1. 원래 E2E 지시, README, 추가 도구 개발 기준과 ADR-0002를 읽는다.
2. VBA는 UTF-8 소스를 수정하고 `python tests/export_ascii.py`로 가져오기 파일을 동기화한다.
3. Python 참조 검사와 실제 Excel 실행을 별도로 수행한다. `tests/windows-window-state.ps1`로 두 파일·새 창·비우기·바꾸기·완료 상태를 회귀 검사한다.
4. 허용된 개발 환경에서 Build_Release.cmd를 실행한다. 보안 설정 자동 변경의 후속 요청 예외는 RC2의 제품 폴더 신뢰 위치([ADR-0003](ADR-0003-Product-trusted-location.md))와 RC4 사용자 실행기의 프로세스 한정 준비·Setup.ps1 한 파일 차단 해제([ADR-0005](ADR-0005-Process-scoped-launchers.md))다. 제작자 빌드, 영구 실행 정책, 조직 정책, 다른 파일의 신뢰 범위로 넓히지 않는다.
5. 바이너리가 바뀌면 같은 해시로 기능·취소·자동 로드·재설치·제거를 다시 검증한다. RC6의 실제 우클릭·Esc·새 화면 확인은 잠금 상태 때문에 남아 있다. 이후 잠금이 해제된 검증 환경에서 진행하며, 이전 버전 결과로 통과 처리하지 않는다.
6. Setup이 바뀌면 .cmd 종료 코드, 기존 Excel 보호, 실패 복구, 추가 파일 보존을 재검증한다. `tests/windows-upgrade.ps1`의 격리 파일·레지스트리 거래와 `tests/windows-upgrade-lifecycle.ps1`의 실제 이전 패키지 → 새 패키지 설치를 구분하며, 배포 검증 요약의 설치기 SHA-256도 갱신한다.
7. 원시 계정·레지스트리·설치 로그는 로컬에 남기고 배포에는 식별자가 없는 요약과 실제 캡처만 넣는다.

업무 파일·기존 Excel 프로세스·타 추가 기능·전역 단축키·보안 정책을 임의로 변경하지 않는다. 스냅샷은 같은 Excel 프로세스의 메모리에만 둔다. 코드 서명, x86 Excel, 회사 배포 승인과 모든 추가 기능의 공존은 별도 인수 사항이다. 실행하지 않은 검사를 통과로 표시하지 않는다.
