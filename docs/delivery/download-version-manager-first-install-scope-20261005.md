# DownloadVersionManager · 0.2.1 최초 설치 검증 범위

**최신 실제 결과(2026-10-06 KST): 최종 정상 0.2.1의 위자드·진행 중 취소, 동등 payload 후반 실패 자동 복구, 정상 재설치·일반 권한 앱 실행·종료·제거와 원래 설정 복원이 PASS입니다.** 정식 릴리즈용 정상 MSI를 준비했으며 공개 게시는 실행하지 않았습니다. 아래 원 계획과 이전 FAIL/NOTRUN은 당시 기록으로 보존하며 최신 범위는 마지막 절을 따릅니다.

기준일: 2026-10-05 KST · 제품: 0.2.1 로컬 무서명 후보 · 상태: **실제 최초 설치·실행·제거 NOTRUN, 최초 설치 실패·취소 복구 BLOCKED / 실제 PASS 0**

요구: 일반 배포 대상의 0.2.1 최초 설치 → 정상 실행 → 명시적 종료 → 제거를 먼저 검증한다. 최초 설치 실패·취소 복구는 별도 안전 항목으로 기록한다. 사용자의 기존 0.2.0에서 0.2.1로 바꾸는 경로는 해당 PC의 선택 검증으로 구분한다. [명세](../tools/download-version-manager/next-version-specification.md), [추가 도구 개발 기준](../policies/tools.md), [문서 작성 규칙](../policies/documentation.md)을 따른다.

## 일반 배포 대상의 우선 경로

기존 DVM 설치와 실행 설정이 없는 전용 Windows 11 x64 일반 사용자 환경에서 정확한 0.2.1 production MSI를 사용한다. 이번 아이콘 반영 후보의 파일·SHA-256은 [아이콘 작업 기록](download-version-manager-icon-20261005.md)에 고정한다. 이전 tray-20261005 MSI는 역사적 산출물이며 새 후보의 설치 근거로 혼용하지 않는다.

| 순서 | 확인할 행동 | 완료를 판단할 근거 |
|---|---|---|
| 최초 설치 | 일반 사용자 설치, 합성 감시 폴더와 선택 설정 적용 | MSI 종료 코드 0, 예상 제품 등록·HKCU 설치/시작 등록·설치 EXE 지문·설정, 사용자 fixture 불변 |
| 정상 실행 | 설치된 EXE의 실제 첫 실행, 선택한 합성 폴더 감시 시작 | 정확한 설치 EXE에서 시작한 PID의 Workspace.DvmWatcher 창·감시 중지 버튼 활성·설정 저장. 기존 인스턴스 복원과 구분 |
| 정상 종료 | 트레이 종료와 같은 제품의 기존 종료 명령 사용 | 감시 정리 후 실행 프로세스 종료 코드 0. X·Alt+F4는 숨김이므로 완전 종료 근거로 사용하지 않음 |
| 제거 | 이번 시험이 만든 정확한 제품만 공식 Windows Installer 제거 | 제거 종료 코드 0, 제품·소유 EXE·설치/시작 등록 제거, 사용자 파일·_history·사용자 실행 설정 보존 |

필수 정상 경로에 구버전 설치나 0.2.0 업그레이드를 먼저 넣지 않는다. 완료한 엔진·감시·트레이 회귀 근거는 관련 범위에서 재사용하며 정상 설치 확인을 이유로 전체 기능·repair·성능 시험을 반복하지 않는다. 같은 버전 repair는 이번 우선 실행에서 제외한다. 실제 위자드의 모든 선택 화면, 다음 로그인과 모든 Windows 환경을 자동 명령 한 번으로 검증했다고 표시하지 않는다.

## 최초 설치 실패·취소 복구

정상 경로와 별도 결과를 기록한다. 이 구분은 실패 시 원상복귀의 기본 안전 요건을 면제하지 않는다.

| 항목 | 별도로 확보할 근거 | 현재 판정 |
|---|---|---|
| 설치 실행 전 위자드 취소 | 실제 취소 경계·1602·설치 전후 등록/파일/설정/사용자 fixture 불변 | 0.2.1 NOTRUN. 0.2.0의 이전 위자드 취소 PASS를 새 파일의 PASS로 옮기지 않음 |
| 설치 transaction 진행 중 취소 | 도달 가능한 실제 취소 지점, 완료 로그, 즉시 before/after 비교 | BLOCKED / 실제 PASS 0 |
| 최초 설치 실패 뒤 복구 | 정확한 production/test MSI의 동등성·지문, 의도한 실패 지점 도달, 제품/파일/등록/시작 항목/설정/보안 상태와 사용자 fixture의 완전한 원상복귀 | BLOCKED / 실제 PASS 0 |
| 복구 후 정상 재시도 | 먼저 완전한 복구 PASS를 확인한 뒤 별도 재시도 결과 | NOTRUN. 복구 미확인 상태에서 재설치·자동 제거로 증거를 바꾸지 않음 |

실패 주입과 transaction 취소는 승인된 전용 snapshot 복원 환경에서 수행한다. 현재 harness의 정상 경로도 동일한 환경 gate와 기존 설치 부재 preflight를 통과해야 한다. 임시 폴더만으로 실사용 계정을 전용 환경으로 판단하거나 실제 계정의 ACL/owner·보안 정책·Windows Installer 내부 등록을 바꾸지 않는다. 과거 0.1.0/0.2.0 실패와 원인 미확정·불완전한 공개본 동등성의 한계는 그대로 보존한다. 종료 코드나 일부 파일 보존만으로 복구 PASS를 선언하지 않는다.

## 사용자 PC의 0.2.0 업그레이드

이 PC에서 확인한 기존 0.2.0에서 0.2.1로 교체하는 경로는 사용자의 선택 검증이다. 일반 배포 대상의 최초 설치 필수 경로와 별도다. 이번 요청으로 기존 설치·설정·실행 중인 앱을 자동 종료·제거·교체하지 않았다. 필요한 경우 시험 환경에서 의도적으로 만든 0.2.0 기준을 사용하며, 현재 최초 설치 preflight를 우회하거나 repair를 업그레이드 성공으로 기록하지 않는다.

## 이번 읽기 확인과 최소 보완

현재 계정의 Windows Installer 관련 제품과 실행 설정을 읽기만 했다. 관련 Watcher 제품 버전은 **0.2.0**이고 기존 설치 경로와 SettingsVersion/Folder/FollowDownloads/InitialReviewFolder가 존재한다. 실행 token은 non-elevated·medium integrity·AppContainer 아님이다. preflight는 **Existing DVM installation must not be changed.**로 막았다. 승인된 전용 snapshot 환경 기록도 확보되지 않았다. 따라서 0.2.1 최초 설치·실행·제거를 현재 계정에서 실행하지 않았다. 상세 machine/SID/로컬 경로는 비공개 artifacts의 preflight.private.json에만 보관한다.

기존 test-watcher-installer.py는 WM_CLOSE 뒤 프로세스 종료를 기다렸다. 0.2.1에서 이 메시지는 창을 숨기므로 정상 종료 시험이 timeout으로 남을 수 있다. 시험 도구는 설치 EXE 지문을 확인하고 해당 EXE를 시작한 PID의 Workspace.DvmWatcher 창만 수집한다. 종료 직전 PID·창 class를 다시 확인한 뒤 기존 트레이 종료와 같은 WM_COMMAND 106을 한 번 보낸다. 보낼 수 없거나 정상 종료가 확인되지 않으면 기존 실패 snapshot/NOTRUN 보존 경로로 멈추며 강제 종료·자동 제거하지 않는다. 제품의 파일 처리·설치 로직은 이 보완으로 변경하지 않았다.

| 이번 실행 | 결과 | 범위 |
|---|---|---|
| test_installer_app_exit.py | **4 PASS / 0 FAIL** | WM_CLOSE 숨김과 명시적 종료 구분, 다른 PID/class에 명령 금지, 명령 전송 실패 시 미완료·재시도 없음. mock 회귀이며 실제 앱/설치 실행 아님 |
| test_installer_evidence.py | **8 PASS / 0 FAIL** | 기존 복구 판정과 환경 gate 회귀. 이번 재실행을 실제 설치 복구 PASS로 세지 않음 |
| harness --help | PASS | 새 helper import·명령 parser 확인. 설치 시퀀스 실행 없음 |
| 읽기 전용 preflight | **BLOCKED** | 기존 0.2.0 설치·설정 확인. 설치/제거/repair/upgrade/실패 주입/취소·세션·사용자 앱 조작 없음 |

근거는 artifacts/download-version-manager-watcher/first-install-scope-20261005/의 app-exit-tests.private.log, evidence-tests.private.log, harness-help.private.log, preflight.private.json이다. 정상 설치 실행 수와 복구 PASS 수는 모두 **0**이다. 문서 strict·로컬 링크 최종 결과는 같은 작업의 아이콘 기록에 기록한다. 원시 진단과 이 내부 기록은 공개 사이트에 싣지 않는다.

## 깨끗한 환경에서 실행할 정상 경로 명령

아래 명령은 아직 실행하지 않았다. approved-environment.private.json은 현재 없는 파일이며, 확보한 전용 환경의 실제 machine/SID와 승인·snapshot 근거를 포함해야 한다. 기존 설치 부재 preflight와 MSI 옆 build-manifest.json의 지문 검증을 통과한 뒤 정상 최초 설치·실행·명시적 종료·제거만 수행한다. rollback MSI를 전달하지 않으며 --skip-repair로 이번 우선 범위를 유지한다. output 파일은 기존 진단과 겹치지 않는 새 이름을 사용한다.

~~~powershell
python tools/DownloadVersionManager/build/test-watcher-installer.py run --msi artifacts/download-version-manager-watcher/icon-20261005/package/DownloadVersionManager-Watcher-0.2.1-x64.msi --approved-environment artifacts/download-version-manager-watcher/first-install-scope-20261005/approved-environment.private.json --skip-repair --output artifacts/download-version-manager-watcher/first-install-scope-20261005/fresh-install-results-new.json
~~~

정상 제거가 실행 설정을 보존한 것을 확인한 뒤에는 이 시험이 새로 만든 합성 실행 설정만 기존 harness의 정리 단계에서 지운다. 사용자 계정의 기존 설정에는 이 절차를 적용하지 않는다. PowerShell wrapper는 환경 승인 인수를 아직 전달하지 않으므로 위 Python 진입점을 사용한다. 빈 승인 기록을 만들어 gate를 통과시키지 않는다. 이 준비와 자동 회귀 성공은 실제 최초 설치·제거 성공 또는 새 후보의 상용·공개 배포 승인이 아니다.

## 2026-10-05 실제 PC의 취소·실패 복구 시험

사용자가 정식 릴리즈를 목표로 실제 PC에서 시험을 준비하고 진행하도록 명시 승인했다. 기존 0.2.1을 정상 종료·백업·공식 제거하고, 백업한 DVM 실행 설정 네 값만 분리해 설치 전 기준을 만들었다. 이번 승인은 앞선 전용 snapshot 환경 조건과 별도로 기록한다. 전체 Windows snapshot은 없으며 완전 클린 OS나 다른 PC 시험으로 표현하지 않는다. 보안 정책·ACL/owner·Windows Installer 내부 등록의 수동 변경 없이 합성 설치·감시 폴더만 사용했다.

정상 MSI는 `DownloadVersionManager-Watcher-0.2.1-x64.msi` 380,928 bytes / SHA-256 `ff3d0b2746d5733b75621ece88a2aa94e93e25e0e97fdf78beb20a42507c2796`이다. 실패 시험 MSI는 `DownloadVersionManager-Watcher-0.2.1-late-failure-test-only.msi` 380,928 bytes / `a8ef067fa1bc0b8ec3f3bcd5b3f339793c9458bd9f9f9fd8e3ad79301b24d1cb`이며 공개 자산이 아니다. 두 MSI의 EXE·CAB·설정 DLL과 기존 MSI table/schema는 같다. 허용한 차이는 Type 19 실패 action, InstallExecute 6500·실패 action 6501 추가와 별도 PackageCode뿐이다. 정상 EXE는 372,224 bytes / `3cddb6e185c7f1741cce6bb9b5b91f9afb3898a7a983598cfdc976e1be592abd`로 유지했다.

| 이번 직접 실행 | 결과 | 근거와 범위 |
|---|---|---|
| 설치 실행 전 위자드 취소 | **PASS**, 취소 조작 USER_CONFIRMED | 정상 MSI exit 1602, InstallInitialize 미진입, 설치 전후 상태 차이 0·UNKNOWN 0 |
| 설치 transaction 진행 중 취소 | **PASS** | 정상 MSI의 파일 복사 뒤 WriteRegistryValues 실행 단계에서 IDCANCEL 반환, exit 1602·rollback ScriptType=2, callback 오류 없음, 상태 차이 0·UNKNOWN 0 |
| InstallExecute 뒤 의도적 실패 | **FAIL** | 정확한 시험 MSI의 실패 action 도달·exit 1603·rollback ScriptType=2를 확인했지만 제품·UpgradeCode·Installer userdata·제거 등록이 남음. 로그에 access denied(5)와 owner 복원 오류 1307, 즉시 상태 비교 UNKNOWN 0 |
| 자동 복구 PASS 뒤 정상 재시도 | **NOTRUN** | 후반 실패의 자동 복구가 FAIL이므로 해당 성공 시나리오로 재시도하지 않음 |
| 실패 제품의 조건부 공식 제거와 원래 설치 복원 | **PASS** | 실패 직후 증거 보존 후 정확한 시험 제품만 공식 제거 exit 0, 설치 전 상태와 동일함 확인. 원래 정상 MSI 재설치 exit 0, 원래 실행 설정·설치 기본값·로그인 시작 항목 복원, 앱 종료 상태 |

최종 확인 시각은 23:01 KST다. 실제 감시 폴더 12개와 History 3개의 직하 메타데이터 및 CompletionOrder는 시험 전과 같았다. 실제 업무파일 내용이나 하위 폴더의 전체 바이트 보존을 검사한 결과로 확대하지 않는다. 합성 fixture는 파일 ID·hash·보안 상태까지 비교했다. 앞선 동일 PC의 정상 lifecycle·실제 창/EXE 아이콘·X/Alt+F4 감시 유지·같은 창 복원 근거와 트레이 모양·재실행 대기 화면 USER_CONFIRMED는 재사용하며 중복 시험하지 않았다.

초기 위자드 호출의 잘못된 명령줄 exit 1639는 취소 시험 NOTRUN이다. transaction 취소의 초기 두 실행은 callback 계측 오류로 FAIL을 보존했고, 해당 도구만 고친 뒤 최종 실행에서 PASS를 얻었다. 실패 주입의 실제 복구 FAIL과 이 도구 오류를 혼용하지 않는다. 정확한 명령·개별 시각·원시 로그·즉시 상태·백업은 비공개 실행 근거에 보존한다.

정상 설치와 두 취소의 성공, 공식 제거·복원 성공은 후반 실패의 자동 rollback 성공이 아니다. 현재 정식 릴리즈를 막는 항목은 재현된 설치 후반 실패의 제품 등록 복구이며, 제품 복구 수정·재검증 PASS와 공개 게시는 아직 없다. 과거 0.1.0·초기 0.2.0 실패는 그대로 보존한다.

## 2026-10-06 원인 분리 대조와 원래 설치 복원

강제 InstallExecute를 추가하지 않고 기존 InstallFinalize 안에서 실행하는 Type 1058 `DeferredFailureProbe`를 6501에 넣었다. 이 시험 MSI는 정상 0.2.1과 payload·설정 DLL·기존 table/schema가 같고 별도 PackageCode를 사용한다. SHA-256은 `804b800490a819972d2d27a97a0c577e7c8bdb6571f00bd8eb008eb6c62f5806`이다.

| 추가 대조 | 실제 결과 |
|---|---|
| 기존 InstallFinalize 안의 deferred 실패 | **FAIL**: 실제 cmd exit 1·MSI exit 1603·rollback ScriptType=2, 등록 상태 차이 18개·UNKNOWN 0. access denied(5)·owner 복원 오류 1307 |
| 동일 시험 MSI의 표준 msiexec /qn 실행 | **FAIL**: 같은 실패 지점과 등록 상태 차이 18개·UNKNOWN 0. 추가 InstallExecute 또는 Python API 호출만이 원인이라는 가설은 배제 |
| WordCount 10→2 권한 요청 후보의 패키지 대조 | **PASS**: 기존 deferred MSI 대비 31개 table/schema·CA·Property·sequence·CAB·설정 DLL 동일. 차이는 Summary의 PackageCode와 PID 15뿐. SHA-256 `532e1c3d1f1f73381de92d0ed760b2c739cb5b2ec6f324461493ce5503d3852a` |
| 권한 요청 후보의 실제 후반 실패 대조 | **NOTRUN(실패 지점 미도달)**: msiexec /passive에서 상승 권한 요청을 확인했지만 credential request가 0x800704C7을 반환하고 MSI exit 1602로 종료. 상태 차이 0·UNKNOWN 0은 실패 rollback PASS 근거가 아님 |

확인된 실패 지점은 Windows Installer의 등록/owner 복원 중 접근 실패다. 근본 원인이나 Windows 자체 결함으로 확정하지 않는다. 실패 제품의 조건부 공식 제거 후 설치 전 상태와 같음을 확인했고, 원래 production 재설치 exit 0과 실행 설정 네 값·설치 기본값·로그인 시작 항목·설치 경로·PackageCode·MSI/EXE 지문을 복원했다. 2026-10-06 00:00 KST 최종 확인에서 앱은 종료 상태이며 실제 감시 폴더 12개·History 3개 직하 메타데이터와 CompletionOrder도 같다.

권한 요청 후보는 비공개 진단용이며 원래 production 패키지의 권한 정책은 바꾸지 않았다. 사용자 UAC 승인이 완료된 실제 후반 실패 대조가 남아 있고 제품 수정·자동 복구 PASS·정식 게시는 미확정이다. 정확한 명령·개별 원시 판정·로그·백업은 비공개 실행 근거에 보존한다.

## 2026-10-06 최종 권한 수정과 실제 설치·복구 검증

사용자가 직접 UAC를 승인한 권한 대조에서 실제 후반 실패 exit 1603·rollback ScriptType=2 뒤 등록을 포함한 설치 전 상태 차이 0·UNKNOWN 0을 확인했다. 같은 PC에서 상승 권한을 허용하지 않은 패키지의 등록 복원이 실패했고, MSI Summary WordCount의 상승 권한 불필요 플래그(0x8)를 제거해 10→2로 바꾸고 인간의 관리자 승인을 허용하자 복원에 성공했다. 이번 PC의 권한 경계가 실패를 가르는 근거이며 Windows 자체 결함이나 모든 환경의 원인으로 확대하지 않는다.

이 변경을 production 제작 과정과 검증기에 반영했고 설치 버튼에 권한 승인 방패를 표시했다. 현재 사용자 LocalAppData·HKCU 설치와 앱의 asInvoker 계약은 유지한다. 설치 중 Windows가 관리자 승인을 요청할 수 있으며 사용자가 직접 승인한다. 시험 도구의 --allow-uac는 MsiSetInternalUI NONE|UACONLY를 명시 선택하고 기본 NONE 동작은 유지한다. MSI 등록·ACL/owner를 수동 삭제·변경하지 않았다.

최종 정상 MSI는 `DownloadVersionManager-Watcher-0.2.1-x64.msi` 380,928 bytes / SHA-256 `0feea2fc119bad780da9dcb57d2a0303ef0e2e0c6f6a20a746fd3ab3f86a0ef5`, PackageCode `{0EA40200-9B82-4D18-9DBE-5045742A195D}`다. 앱 EXE는 앞선 `3cddb6e185c7f1741cce6bb9b5b91f9afb3898a7a983598cfdc976e1be592abd`를 재컴파일 없이 사용했다. 최종 후반 실패 전용 MSI의 SHA-256은 `4c617ecfc94c091c5831181cc93a12ecdd6caabed3e3c83c12173aa798047c48`이며 정상 MSI와 CAB·설정 DLL·기존 table/schema가 같다. 허용 차이는 Type 1058 DeferredFailureProbe·NOT REMOVE/6501 추가와 별도 PackageCode뿐이고 강제 InstallExecute 추가는 없다. 시험 MSI는 공개 자산이 아니다.

| 최종 실제 실행 | 결과와 범위 |
|---|---|
| 정상 MSI의 위자드 취소 | **PASS**: exit 1602·설치 실행 전 취소·상태 차이 0·UNKNOWN 0. 취소와 설치 버튼 방패는 USER_CONFIRMED |
| 정상 MSI의 transaction 취소 | **PASS**: 실제 payload 복사 뒤 WriteRegistryValues 실행 단계에서 IDCANCEL, exit 1602·rollback ScriptType=2·callback 오류 없음·상태 차이 0·UNKNOWN 0 |
| 동등 정상 payload의 후반 실패 | **PASS**: 파일·등록·제품 게시 뒤 실제 cmd exit 1·MSI 1722/1603·rollback ScriptType=2, 제품 미등록·상태 차이 0·UNKNOWN 0. 즉시 판정 전에 공식 제거나 수동 정리 없음 |
| 자동 복구 PASS 뒤 정상 재설치 | **PASS**: 정상 MSI 완료 exit 0, 제품 상태 5·0.2.1·per-user·정상 PackageCode·EXE 지문·설치 기본값·Run 정확, 실행 설정 네 값 미생성·프로세스 0 |
| 일반 권한 앱 실행과 종료 | **PASS**: 등록 앱을 추가 인자 없이 실행해 0.2.1 감시 대기 확인, 원래 사용자·medium integrity 8192·elevated=false·Limited token. 트레이 종료 USER_CONFIRMED 뒤 프로세스 0·실행 설정 불변 |
| 정상 제거 | **PASS**: 공식 제거 exit 0, 제품 상태 5→-1, 전체 측정 상태가 설치 전 기준과 동일·UNKNOWN 0 |
| 원래 위치 설치와 사용자 설정 복원 | **PASS**: 정상 MSI exit 0·실행 설정 네 값 guard 복원 exit 0·최종 22개 확인 통과. 원래 설정·기본값·Run·경로·시작 메뉴 바로가기와 정확한 MSI/EXE, 앱 종료·구 0.2.0 미등록 확인 |

최종 확인은 2026-10-06 05:29 KST다. 실제 감시 폴더 12개와 History 3개의 직하 메타데이터, CompletionOrder·기존 portable·원래 production compile manifest는 보존했다. 업무파일 내용이나 하위 폴더를 읽어 전수 보존을 확인한 결과는 아니다. 최초 토큰 진단의 읽기 전용 조회 오류와 수정 전 소스를 보존하고 올바른 고정 DWORD 조회로 일반 권한을 확인했으며 앱 실패로 분류하지 않는다.

이전 no-elevation 후반 실패 FAIL, 계측 오류와 UAC 승인 미완료 1602/후반 실패 NOTRUN은 그대로 유지한다. 실제 한 Windows 11 x64 PC·합성 fixture의 직접 승인 시험이며 전체 OS snapshot·완전 클린 Windows·다른 PC 결과가 아니다. 기존 엔진·UI·아이콘 근거는 관련 범위에서 재사용했다. CI의 세 경로/조건 수정과 YAML·정상 자산 경로 검사는 PASS지만 실제 CI 실행·GitHub Release 게시는 NOTRUN이다. 미래 CI의 재빌드 파일은 이 지문과 혼용하지 않고 별도 검증한다. 무서명과 조직 도입·상용 승인 미결정은 공개 안내에 유지하며, 정확한 명령·원시 로그·사용자 경로·SID·백업은 비공개 실행 근거에 보존한다.
