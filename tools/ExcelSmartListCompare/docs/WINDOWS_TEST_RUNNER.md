# Windows 실기 실행 안내

상태: 일부 실행·정책 차단 · 2026-09-14. 실제 결과는 [Windows E2E 보고서](WINDOWS_E2E_REPORT.md).

기존 Excel을 사용자가 정상 종료한 뒤 프로젝트 루트에서 Windows PowerShell로 실행한다. 조직 정책이 막으면 설정을 우회하지 않고 멈춘다. RunId는 증거를 덮어쓰지 않도록 매번 새 값을 사용한다.

```powershell
powershell.exe -NoLogo -NoProfile -STA -File tests/Invoke-WindowsE2E.ps1 -Phase Preflight
powershell.exe -NoLogo -NoProfile -STA -File tests/Invoke-WindowsE2E.ps1 -Phase Build
powershell.exe -NoLogo -NoProfile -STA -File tests/Invoke-WindowsE2E.ps1 -Phase Guards
```

`Preflight`는 실제 Excel 생성/종료와 VBA 접근을 검사한다. `Build`는 기존 Setup의 실제 빌더를 실행한다. `Guards`는 **제품 미설치 환경 전용**이며 Excel 열림 차단·mutex 충돌·미설치 반복 제거·없는 XLAM 테스트를 실행한다. Guards를 설치 성공/rollback 시험으로 해석하지 않는다.

최종 Release가 생성된 후에만 다음 COM 기능 시험을 실행한다. 이 스크립트는 현재 PC에서 **제품 실행 미검증**이며 완전한 인수 테스트를 대신하지 않는다.

```powershell
powershell.exe -NoLogo -NoProfile -STA -File tests/Invoke-WindowsE2E.ps1 -Phase Functional
```

시험은 합성 A/B 파일, 닫힌 원본 snapshot, SLC_Run, 개수 차이, 결과 수식 여부, 파일 해시와 전체 시간을 검사한다. 매크로/오류 대화상자가 생기면 내용을 실제로 확인해야 한다. 실행기는 120초에 차단 상태를 기록하고 프로세스를 강제로 종료하지 않는다. 해당 단계가 남긴 소유 PID와 대화상자를 확인한 뒤 정상 종료한다. 무인 전체 GUI/E2E 실행기는 아직 제공하지 않는다.

`.cmd` 자체를 시험하려면 현재 테스트 셸에만 마지막 pause 생략 변수를 설정한다. 제품 설치·제거 확인 생략은 아래처럼 제품 ID를 명시한 경우에만 동작한다. Office 보안 경고와 별개다.

```powershell
$env:SLC_SETUP_NO_PAUSE = '1'
cmd.exe /d /c Build_Release.cmd
cmd.exe /d /c 'Release\Install.cmd -ConfirmProduct SLC-68A45C44-2026'
cmd.exe /d /c 'Release\Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026'
```

기본 사용자는 옵션 없이 Install.cmd / Uninstall.cmd를 실행하며 확인창과 마지막 대기를 그대로 본다. 종료 코드: 0 성공, 1 일반 실패, 2 확인 거절, 3 Excel 실행 중, 4 제품 잠금 충돌, 5 VBA 빌드 접근 차단.

성공 빌드 이후 남은 필수 순서는 설치 → Excel 정상 시작(먼저 XLAM 열기/AttachUI 금지) → 메뉴/일반 기능 → 종료 → 재시작 → 재설치 → 메뉴 중복 확인 → 제거 → 재시작 및 누락 경고 없음 확인 → 재제거 → 초기 상태 복구다. [인수 기준](ACCEPTANCE_TESTS.md)의 경계/취소/rollback/공존 검증도 수행한다. 현재 이 순서는 **미실행**이다.

원시 `baseline-*.json`에는 로컬 SID·경로가 포함될 수 있으므로 외부 공개하지 않는다. 배포 전에는 보고서의 실제 통과/차단 상태와 최종 설치 XLAM 해시를 다시 갱신한다.
