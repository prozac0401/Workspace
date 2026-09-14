# ADR-0005 · 사용자 실행기의 설치 준비 통합

상태: 채택 · 날짜: 2026-09-15 · 결정 담당: 사용자 요청에 따른 설치 변경

관련 요구사항·정책: 실제 사용 PC의 RC3 설치 오류, 수동 준비의 자동화 및 릴리즈 반영 요청, [도구 개발 기준](../../../docs/policies/tools.md).
대체 관계: RC3까지의 PowerShell 준비 자동화 금지에 아래 한정 예외를 추가한다. [ADR-0002](ADR-0002-Excel-native-lifecycle.md)의 설치 수명주기와 [ADR-0003](ADR-0003-Product-trusted-location.md)의 Excel 신뢰 범위는 유지한다.

## 맥락

실제 사용 PC에서 RC3 설치가 `UnauthorizedAccess`로 실패했다. 사용자가 `Restricted`, `MachinePolicy=Undefined`, `UserPolicy=Undefined`를 확인했다. 프로세스 한정 `RemoteSigned`, RC3의 `Setup.ps1` 차단 해제, 설치 실행으로 동작했다고 보고한 뒤 이 절차를 한 번에 처리하고 스크립트를 릴리즈에 포함해 달라고 요청했다. 이 보고는 RC4 패키지의 현장 검증과 구분한다.

## 결정

RC4의 `Install.cmd`, `Uninstall.cmd`, `Test_Excel.cmd`는 아래 준비를 먼저 실행한다. 소스 제작용 `Build_Release.cmd`는 바꾸지 않는다.

1. 같은 폴더의 고정 `Setup.ps1` 파일이 있는지 확인한다. 경로는 환경 변수의 데이터로 전달하며 PowerShell 코드에 삽입하지 않는다. CMD의 지연 확장은 끈다.
2. `MachinePolicy`·`UserPolicy` 중 하나라도 지정됐거나 유효 정책이 `AllSigned`이면 파일의 다운로드 차단 표시와 기존 정책을 그대로 두고 설치 본체를 실행한다. 원래 정책이 실행을 막으면 그 오류를 반환한다.
3. 위 설정이 없으면 `Unblock-File -LiteralPath`로 해당 `Setup.ps1` 한 파일의 다운로드 차단 표시만 제거한다. 폴더 검색·다른 파일·XLAM의 차단 해제는 하지 않는다.
4. 새 Windows PowerShell 프로세스에만 `-ExecutionPolicy RemoteSigned`를 적용하고 `-STA -File`로 설치 본체를 실행한다. 기존 인자는 스크립트 인자로 전달한다.
5. 준비 실패 시 본체를 실행하지 않는다. 본체의 종료 코드와 제품 확인창은 유지한다. 준비 내부의 종료 코드 2는 기존 정책 사용 신호이며, 본체의 취소 코드 2는 그대로 호출자에게 전달한다.

그룹 정책은 PowerShell 자체에서도 프로세스 정책보다 우선한다. 사용자·컴퓨터의 영구 실행 정책, 매크로 설정, 서명 인증서, AccessVBOM은 변경하지 않는다. 설치 본체의 프로세스가 종료되면 임시 정책은 사라지지만 파일 한 개의 다운로드 차단 해제는 유지된다. 정책을 해제해 달라는 조직 승인 절차를 이 구현이 대신하지 않는다.

## 검토한 대안

매번 명령 입력은 이번 사용자 불편을 해결하지 못한다. 영구 `CurrentUser` 변경과 `Bypass` 실행은 이번에 성공한 절차보다 범위가 넓다. 별도 EXE/MSI 설치 엔진은 현재 명세의 사용자별 파일·등록·롤백 구현을 다시 만들게 된다. 세 사용자 CMD 실행기의 짧은 준비 구문을 동일하게 유지하고 Windows 프로세스 시험으로 검증한다.

## 영향과 이행

제품 VBA와 XLAM은 RC3와 동일하다. 설치 본체는 `installerVersion`만 `0.2.0-rc.4`로 갱신한다. RC4의 제거 실행기는 기존 설치 방식대로 제품 폴더에 복사된다. RC1~RC3 설치 기록을 읽는 형식, 파일 백업과 복원, 외부 파일 보존은 바꾸지 않는다. 새 설치 ZIP과 수정 소스를 별도 릴리즈로 제공하고 RC3 자산은 보존한다.

## 실패와 복구

준비 중 실패하면 본체를 시작하지 않고 0이 아닌 코드로 종료한다. 다운로드 차단 해제 이후 사용자가 설치를 취소하거나 본체가 실패해도 배포 폴더의 Setup.ps1 차단 표시는 자동 복원하지 않는다. 파일 내용과 다른 파일의 차단 표시는 보존한다. 본체의 오류 복구·동시 실행 잠금·등록 해제 동작은 기존 구현을 따른다.

## 검증

[RC4 검증 보고서](WINDOWS_LAUNCHER_REPORT.md)에 Restricted 프로세스·다운로드 표식·특수문자 경로·종료 코드·실패 주입·기존 AllSigned 보존·실제 Setup 잠금 시험과 정책 모의 시험을 기록한다. 회사 그룹 정책을 실제로 변경하는 시험은 하지 않는다. Excel 전체 실기와 UI 클릭 재검증 여부는 보고서의 한계에 명시한다.

근거: Microsoft의 [PowerShell.exe 프로세스 실행 정책 및 인자](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1), [실행 정책 우선순위와 파일 차단](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies).
