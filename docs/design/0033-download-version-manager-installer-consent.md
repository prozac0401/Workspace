# ADR-0033 · DVM 설치기의 관리자 승인과 일반 권한 앱 실행

상태: 채택 — 최종 정상 0.2.1 제작과 현재 Windows 11 x64 한 PC의 실제 검증에 반영

날짜: 2026-10-06 KST · 결정 담당: 사용자 승인에 따른 개발 담당

관련 요구사항·정책: [REQ-DVM-NEXT-010과 최종 0.2.1 근거](../tools/download-version-manager/next-version-specification.md), [추가 도구 개발 기준](../policies/tools.md), [문서 작성 규칙](../policies/documentation.md)

대체 관계: [ADR-0028](0028-download-version-manager-folder-input.md)의 현재 사용자 LocalAppData·HKCU 설치와 일반 사용자 감시 앱 계약을 유지하며, 0.2.1 설치기에 Windows의 상승 권한 요청과 사용자의 직접 승인을 허용한다. 앞선 무상승 설치와 실패 기록은 당시 근거로 보존한다.

## 맥락

같은 PC에서 상승 권한을 요청하지 않는 패키지는 실제 후반 실패와 rollback에 도달했지만 Windows Installer 제품 등록이 남았다. 추가 InstallExecute 없이 normal InstallFinalize에서 실행한 동등 payload의 deferred 실패도 같은 등록 잔존을 보였다. 정상 제거·재설치 성공을 자동 rollback 성공으로 간주하지 않았다.

## 결정

WiX 제작 뒤 공식 Summary API로 WordCount의 상승 권한 불필요 플래그 0x8을 제거해 10에서 2로 바꾸고, 저장·다시 읽기와 패키지 검증으로 값을 확인한다. 설치 버튼에는 방패를 표시한다. Windows가 관리자 승인을 요청하면 사용자가 직접 승인하며 도구가 자격 증명이나 동의를 대신 입력하지 않는다. WordCount의 의미는 [Microsoft의 공식 설명](https://learn.microsoft.com/en-us/windows/win32/msi/word-count-summary)을 따른다.

현재 사용자 설치 범위와 LocalAppData·HKCU 경로, 앱의 asInvoker·일반 권한 실행을 유지한다. 설치 권한 허용을 앱의 상시 상승 실행이나 시스템 전체 설치로 바꾸지 않는다. 검증한 기존 EXE를 재컴파일하지 않고, 원래 컴파일 입력과 변경된 패키지 제작 입력을 구분해 기록한다.

## 검토한 대안

무상승 경로를 그대로 두면 이 PC에서 재현한 후반 실패의 등록 복구 요건을 충족하지 못한다. 계정 ACL·owner·보안 정책이나 Windows Installer 내부 등록을 수동으로 바꾸는 방식은 채택하지 않는다. 이번 판단은 같은 PC의 권한 대조와 검증한 패키지에 근거하며 Windows 전체의 결함 원인을 확정하지 않는다.

## 영향과 이행

0.2.1 설치에는 관리자 승인 화면이 나타날 수 있다. 설치 후 감시 앱은 일반 사용자 권한으로 실행한다. 파일·History·기존 설정 보존과 명시적 정상 종료를 유지한다. 서명은 없고 조직 도입·상용 인증을 얻었다고 표시하지 않는다. Pages와 정식 Release 게시는 사용자가 승인했으며 실제 자산·checksum·문서 게시 결과는 배포 후 확인한다.

## 실패와 복구

동의를 완료하지 않은 취소는 후반 실패 지점에 도달한 시험으로 세지 않는다. 설치 중 취소나 동등 payload의 의도한 후반 실패 뒤에는 제품 등록·파일·설정·시작 항목·fixture의 설치 전 상태와 차이·UNKNOWN을 확인한다. 종료 코드만으로 복구 PASS를 선언하지 않으며 기존 FAIL·계측 오류·NOTRUN을 보존한다.

## 검증

사용자가 직접 UAC를 승인한 권한 대조는 같은 PC·같은 사용자에서 실제 후반 실패와 rollback에 도달했고 수동 정리 없이 등록을 포함한 상태 차이 0·UNKNOWN 0이었다. 최종 정상 MSI SHA-256 `0feea2fc119bad780da9dcb57d2a0303ef0e2e0c6f6a20a746fd3ab3f86a0ef5`의 두 취소·동등 payload 후반 실패 자동 복구·정상 재설치·일반 권한 앱 실행/종료·제거·원래 설정 복원이 PASS다. 앱의 실제 medium token도 확인했다.

[최초 설치 검증 기록](../delivery/download-version-manager-first-install-scope-20261005.md)의 최신 절과 [시험 결과](../../tools/DownloadVersionManager/TEST_RESULTS.md)를 근거로 재사용한다. 다른 PC·클린 Windows·모든 실패 지점·모든 실행 경로의 인증으로 확대하지 않는다. 새 시험 절차나 전체 suite 재실행을 추가하지 않는다.
