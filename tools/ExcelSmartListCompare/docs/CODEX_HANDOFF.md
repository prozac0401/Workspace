# Windows 빌드·실기 검증 인계

상태: 설치 가능한 0.2.0 RC1 평가용 후보 · 2026-09-14

[현재 Windows 보고서](WINDOWS_E2E_REPORT.md)에 최종 XLAM 해시, 실제 테스트, 실패 수정과 원상복구 결과를 기록했다. TEST_REPORT.md는 최초 Linux 기록이다. WINDOWS_INITIAL_E2E_REPORT.md와 WINDOWS_APPROVAL_RETEST_REPORT.md는 잠금 해제 전 기록이며 최종 상태를 뜻하지 않는다.

## 현재 구현

- 첫 Selection 전체를 기준으로 담고 다음 Selection과 비교한다. 방향·모드 선택과 두 열 자동 분할을 추가하지 않는다.
- 가시 셀의 값과 개수를 비교하며 텍스트 앞자리 0을 보존한다.
- 저장한 XLAM을 다시 열어 실제 VBA 검사를 실행한 뒤 Release를 만든다.
- 빌드·진단은 소유 PID를 확인한 정상 Excel 시작을 사용한다. 시험 Office의 COM 자동화 모드는 VBProject 접근과 설치본 재열기에서 실패했다.
- 설치·제거는 Excel을 시작하지 않고 자기 LocalAppData 파일과 HKCU의 정확한 제품 OPEN 경로만 관리한다.
- Esc 입력을 받을 수 있도록 Interactive=False를 설정하지 않는다. mBusy로 재진입을 막고 기존 기준과 설정을 복원한다.

## 후속 변경

1. 원래 E2E 지시, README, 추가 도구 개발 기준과 ADR-0002를 읽는다.
2. VBA는 UTF-8 소스를 수정하고 `python tests/export_ascii.py`로 가져오기 파일을 동기화한다.
3. Python 참조 검사와 실제 Excel 실행을 별도로 수행한다.
4. 허용된 개발 환경에서 Build_Release.cmd를 실행한다. 설치기에 보안 설정 변경을 넣지 않는다.
5. 바이너리가 바뀌면 같은 해시로 기능·취소·자동 로드·재설치·제거를 다시 검증한다.
6. Setup이 바뀌면 .cmd 종료 코드, 기존 Excel 보호, 실패 복구, 추가 파일 보존을 재검증한다.
7. 원시 계정·레지스트리·설치 로그는 로컬에 남기고 배포에는 식별자가 없는 요약과 실제 캡처만 넣는다.

업무 파일·기존 Excel 프로세스·타 추가 기능·전역 단축키·보안 정책을 임의로 변경하지 않는다. 스냅샷은 같은 Excel 프로세스의 메모리에만 둔다. 코드 서명, x86 Excel, 회사 배포 승인과 모든 추가 기능의 공존은 별도 인수 사항이다. 실행하지 않은 검사를 통과로 표시하지 않는다.