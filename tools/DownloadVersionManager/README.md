# DownloadVersionManager · 0.2.0 폴더 감시

## 0.2.1 정식 배포 기준 · 2026-10-06

사용자가 검증된 정상 0.2.1의 정식 Release와 Pages 게시를 승인했습니다. 배포 파일은 `DownloadVersionManager-Watcher-0.2.1-x64.msi`와 `SHA256SUMS.txt` 두 개이며 이미 시험한 정상 MSI를 그대로 재사용합니다. MSI SHA-256은 `0feea2fc119bad780da9dcb57d2a0303ef0e2e0c6f6a20a746fd3ab3f86a0ef5`입니다. 실패 기능은 없으며 시험 MSI·개인 진단·백업은 배포하지 않습니다.

[정식 Release](https://github.com/prozac0401/Workspace/releases/tag/download-version-manager-v0.2.1) · [설치·사용 안내](https://prozac0401.github.io/Workspace/tools/download-version-manager/) · [이번 게시 기록](../../docs/delivery/download-version-manager-guide-update-20261006.md)

설치기의 필요한 관리자 승인은 사용자가 직접 허용하며 현재 사용자 설치와 일반 권한 앱 실행을 유지합니다. 현재 Windows 11 x64 한 PC에서 취소·대표 후반 실패 뒤 자동 복구·정상 재설치·실행·종료·제거를 확인했습니다. 코드 서명과 조직 도입 승인은 별도입니다. 소스·자동 검사·실제 Release 자산·Pages 게시 확인은 이번 PR 본문에 기록합니다.

아래의 준비 완료·게시 미실행·과거 FAIL/NOT RUN 문구는 각 기록 시점의 결과로 보존합니다. 이번 배포의 자산과 다른 버전·미래 CI 재빌드 파일을 혼동하지 않습니다.

**최신 로컬 0.2.1 상태(2026-10-06 KST): 최종 정상 MSI의 두 취소·동등 payload 후반 실패 자동 복구·정상 재설치·일반 권한 실행/종료·제거와 원래 설정 복원이 PASS입니다.** 사용자 PC에는 수정한 정상 0.2.1과 원래 설정을 복원했고 앱은 종료 상태입니다. 정식 릴리즈용 정상 MSI를 준비했으며 공개 게시는 실행하지 않았습니다. [최신 실제 범위와 결과](../../docs/delivery/download-version-manager-first-install-scope-20261005.md)를 따릅니다. 이하 0.2.0 공개 상태와 이전 FAIL/NOTRUN은 당시 기록입니다.

**현재 상태(2026-10-04 KST): [무서명 기능 평가 prerelease](https://github.com/prozac0401/Workspace/releases/tag/download-version-manager-v0.2.0) 게시 완료입니다.** 브라우저 확장 없이 지정 폴더를 감시하는 네이티브 Windows 프로그램입니다. 기존 0.1.0 평가 버전과 과거 실패 기록은 보존합니다.

[사용 안내](../../docs/tools/download-version-manager/index.md) · [0.2.0 명세](../../docs/tools/download-version-manager/next-version-specification.md) · [설계](../../docs/design/0028-download-version-manager-folder-input.md) · [실제 시험](TEST_RESULTS.md) · [남은 제한](KNOWN_LIMITATIONS.md)

**2026-10-05 로컬 소스 개선:** 새 History 이름은 실제 보관 대상의 마지막 수정 시각을 사용하고, 확인된 읽기 전용 보호와 다른 접근 실패의 안내를 구분합니다. 공개 0.2.0 MSI의 보관 작업 시각 규칙과 현재 설치본은 그대로입니다. 이번 변경의 실행 결과·미실행 항목은 [별도 검증 기록](../../docs/delivery/download-version-manager-mtime-guidance-20261005.md), 결정 이유는 [ADR-0031](../../docs/design/0031-download-history-mtime-guidance.md)를 따릅니다.

**같은 날의 후속 작업:** 사용자가 수정 EXE의 날짜 이름·읽기 전용 보존 이유·긴 로그 수평 스크롤을 직접 확인했습니다(USER_CONFIRMED). 이어 원래 기능을 유지한 UX 개선과 로컬 MSI 제작을 요청했습니다. [후속 작업 기록](../../docs/delivery/download-version-manager-ux-package-20261005.md)에 변경·시험·생성물 지문을 구분합니다. 현재 설치본 반영과 공개 배포는 하지 않으며, 설치 실패 복구는 전용 snapshot Windows 시험 환경이 없어 BLOCKED입니다.

**2026-10-05 트레이 후속 작업:** 사용자가 새 카드 UI와 현재 동작도 직접 확인했습니다(USER_CONFIRMED). 이번 로컬 수정본은 X·Alt+F4로 감시 창을 숨기고 트레이에 유지하며, 트레이의 **열기** 또는 더블클릭으로 같은 창을 다시 엽니다. 감시 시작·중지 상태와 화면 기록은 유지하고 **종료**에서 감시와 프로세스를 끝냅니다. 공개 0.2.0 MSI와 현재 설치본에는 이번 변경을 반영하지 않았습니다. 설계는 [ADR-0032](../../docs/design/0032-download-version-manager-tray-lifetime.md), 새 실행·패키지 결과는 [트레이 작업 기록](../../docs/delivery/download-version-manager-tray-20261005.md)을 따릅니다.

## 사용 흐름

`DownloadVersionManager-Watcher-0.2.0-x64.msi` 한 파일을 설치합니다. 위자드에서 현재 Windows 다운로드 위치 또는 다른 폴더 한 곳을 선택합니다. 기본 다운로드 위치 변경 추종과 로그인 자동 실행은 기본 선택이며 해제할 수 있습니다. 외부 runtime이나 브라우저별 확장 설치는 필요하지 않습니다.

처음 폴더를 사용할 때 기존 `파일.ext`와 `파일 (n).ext` 그룹을 미리 보여 줍니다. 사용자가 번호 파일을 최신으로 선택하고 표시된 전체 그룹의 처리 순서에 동의하면 정리합니다. 선택 파일을 마지막에 원래 이름으로 이동합니다. 원래 파일 선택·그룹 보존·남은 그룹 모두 보존도 가능합니다. 검토를 취소하면 감시를 시작하지 않습니다.

그 뒤 새 번호 파일은 같은 폴더의 원래 대상과 연결합니다. 3초 안정과 보호된 핸들 확보를 처리 조건으로 사용합니다. 이 조건은 앱 내부 다운로드 완료의 증명이 아닙니다. 같은 대상의 후보가 동시에 대기하면 모두 보존합니다.

| 두 파일 | 결과 |
|---|---|
| 바이트가 같음 | 신규 객체가 원래 이름을 승계하고 이전 객체 제거, History 없음 |
| 바이트가 다름 | 이전 객체를 `_history/stem_YYYYMMDD_HHMMSS[_001].ext`에 보관, 신규 객체가 원래 이름 승계 |
| 원래 대상 없음·잠금·관찰 이후 외부 변경 | 보존 |
| 동시에 같은 대상 후보 여럿 | 모두 보존하고 해당 세션의 자동 처리 보류 |

로컬 소스의 새 History 날짜는 실제 이동하는 객체의 보호된 핸들에서 읽은 마지막 수정 시각입니다. PC의 해당 날짜 시간대 규칙으로 변환하고 기존 초 단위 이름·충돌 순번을 유지합니다. 기존 History 이름과 보관 대상의 수정 시각 메타데이터는 바꾸지 않습니다. 시각 조회·변환에 실패하면 현재 시각으로 대체하지 않고 파일을 보존합니다.

이름 suffix는 사용자 채택 관례입니다. 처음부터 번호가 있는 별개 이름도 원래 대상이 있으면 처리될 수 있으므로 이런 이름을 별개 문서로 사용하는 폴더에는 감시를 적용하지 않습니다. 직접 덮어쓴 이전 내용의 복구는 보장하지 않습니다.

## 시작·설정·제거

일반 사용자 프로세스 한 개가 선택 폴더의 OS 변경 알림을 비재귀로 받습니다. **감시 시작**·**감시 중지**를 제공합니다. 이번 로컬 트레이 수정본에서 감시 창의 X·Alt+F4는 창을 숨기며, 작업표시줄의 최소화 창을 남기지 않습니다. 트레이의 **열기** 또는 더블클릭으로 같은 창을 복원하고, **종료**로 감시와 프로세스를 안전하게 끝냅니다. 숨기거나 다시 열어도 감시 상태를 바꾸거나 감시를 중복 시작하지 않습니다. 최소화 버튼·시작 시 창 표시·감시 시작·로그인 자동 실행 정책은 기존과 같습니다.

트레이 등록이나 Explorer 재시작 뒤 재등록이 실패하면 창을 유지하거나 복원하고 기존 로그에 오류를 남깁니다. 이미 실행 중인 앱이 있으면 두 번째 실행은 기존 창을 다시 엽니다. Windows 로그오프·종료는 창 숨김과 구분해 정리합니다. 공개 0.2.0에서는 창 닫기가 프로그램 종료이며, 트레이 동작은 새 로컬 수정본에 적용합니다.

Windows `FOLDERID_Downloads`에서 현재 사용자 다운로드 위치를 해석합니다. 기본 위치 추종을 선택한 경우 앱 시작과 사용자 폴더 registry 알림에서 경로를 갱신합니다. 사용자 지정 폴더는 위치 추종 대상이 아닙니다.

설치 위치는 `%LOCALAPPDATA%/Programs/DownloadVersionManagerWatcher`, 설정·설치 등록·선택한 로그인 시작 항목은 HKCU입니다. 새 MSI 식별자와 경로는 0.1.0과 분리합니다. 구버전 설치·브라우저 등록·CompletionOrder는 자동 변환하거나 삭제하지 않습니다. 구버전 확장과 동일 폴더에서 함께 실행하지 않습니다.

제거나 새 EXE 실행 전에 기존 프로그램을 정상 종료합니다. 이번 로컬 트레이 수정본에서는 트레이의 **종료**를 선택하고 프로세스가 끝났는지 확인합니다. X는 완전 종료가 아닙니다. 이전 버전에 트레이 종료 메뉴가 없으면 해당 버전에서 확인된 정상 종료 경로를 사용하며 강제 종료하지 않습니다. 단일 인스턴스 때문에 기존 앱이 남아 있으면 새 EXE를 실행해도 기존 창만 열릴 수 있습니다. 감시 폴더·History와 사용자 실행 설정은 보존합니다. 코드 서명이 없으며 조직의 도입·상용 승인을 의미하지 않습니다.

## 파일 보존

크기를 먼저 비교하고 같은 크기만 64 KiB 버퍼로 SHA-256을 계산합니다. 신규 객체와 그 파일 시간을 유지하는 이름 이동을 사용합니다. 파일 이동 실패 시 이전 이름 복구를 시도하고 복구 실패 위치를 안내합니다. 앱을 강제 종료하지 않습니다.

로컬 소스의 안내는 엔진이 처리 당시 읽기 전용 속성을 확인한 경우 `읽기 전용 보호: 파일 보존`을 먼저 표시합니다. 다른 접근 실패는 `접근 실패: 파일 보존`으로 표시합니다. 기존 `permission_denied`와 Windows 오류, 파일명·복구 위치·경고는 유지하고 구버전 Host JSON 응답 형식은 바꾸지 않습니다. 사후 파일 속성 조회로 원인을 추정하거나 권한 변경·자동 재시도를 추가하지 않습니다.

두 번의 이동은 하나의 트랜잭션이 아닙니다. 강제 종료·전원 장애 때 `_history` 또는 `.dvm-…pending`에 이전 객체가 남을 수 있습니다. 자동 복원·잔재 일괄 삭제는 없습니다. 파일 내용·내용 hash·telemetry를 외부에 전송하지 않습니다.

## 제작과 증거

```powershell
python tools/DownloadVersionManager/build/build-watcher.py --tests --msvc <MSVC-root> --sdk <SDK-root> --wix <wix.exe>
```

Windows x64 MSVC·Windows SDK·WiX 4·Python이 제작용으로 필요합니다. C++ `/MT` 실행 파일과 MSI 하나를 제작하며 최종 사용자에게 개발 도구가 필요하지 않습니다. 변경된 폴더 입력·기존 그룹 처리·설치 위험에 필요한 검증만 수행합니다.

`source/app.cpp`, `watcher.cpp`, `review.cpp`, 기존 `engine.cpp`를 새 빌드에서 사용합니다. 폴더 엔진 8건·watcher 15건·최초 그룹 4건과 MSI 구조 검사, 수정 후보의 설치/실행·repair·제거·파일 보존 5건, 화면 높이 수정 후보의 설치/실행·제거·보존 4건은 PASS입니다. 최종 안내 문구와 표준 MSI 폴더 선택 수정에는 관련 설치 근거를 재사용하고 경로 선택·설정 전달·취소를 별도로 확인했으며 새 late-failure의 설치 등록 rollback은 FAIL로 남습니다. [배포 기록](../../docs/delivery/download-version-manager-watcher-release-20261004.md)에 각 후보 지문과 한계를 구분했습니다.

기존 `version.json`의 0.1.0 / protocol 2, `source/host.cpp`, `extension`, `build/build.py`와 기존 시험·산출물은 구버전 근거로 남깁니다. 0.1.0의 Win11 설치 실패 복구 FAIL·단일 배포 FAIL·실제 브라우저 NOT RUN을 새 버전의 PASS로 바꾸지 않습니다.

## 2026-10-05 전용 아이콘과 최초 설치 우선순위

최신 로컬 0.2.1 후보는 파란 다운로드·History 아이콘을 실행 파일·창·트레이에 내장합니다. 원본은 assets/download-version-manager.png, 7개 크기의 Windows 아이콘은 assets/download-version-manager.ico입니다. 적용·검증·새 EXE/MSI 지문은 [아이콘 기록](../../docs/delivery/download-version-manager-icon-20261005.md)을 따릅니다. 공개 0.2.0과 현재 설치본은 교체하지 않았습니다.

일반 대상은 0.2.1 최초 설치·정상 실행·명시적 종료·제거를 우선 확인합니다. 최초 설치 실패·취소 복구는 별도 항목이며 사용자 PC의 0.2.0 업그레이드는 선택 경로입니다. 현재 계정의 기존 설치와 전용 환경 부재로 실제 최초 설치는 NOTRUN, 복구는 BLOCKED / 실제 PASS 0입니다. 안전한 준비 명령과 시험 도구의 트레이 종료 대응은 [최초 설치 범위](../../docs/delivery/download-version-manager-first-install-scope-20261005.md)에 기록합니다.

## 2026-10-05 실제 PC 복구 시험 이후의 상태

사용자의 명시 승인으로 동일 PC에서 기존 0.2.1을 정상 제거하고 백업한 실행 설정을 분리해 취소·실패 시험을 진행했다. 전체 Windows snapshot·완전 클린 OS·다른 PC 검증은 아니다. 정상 MSI의 두 취소는 exit 1602와 설치 전후 상태 동일로 PASS다. 정확한 payload의 시험 전용 MSI에서 InstallExecute 후 실패를 유발하자 exit 1603·rollback 뒤에도 제품 등록이 남아 자동 복구는 FAIL이다. 공식 제거와 원래 MSI 재설치·설정 복원 성공을 rollback 성공으로 바꾸지 않는다.

앞선 정상 lifecycle·실제 창/EXE 아이콘·창 숨김 중 감시·동일 창 복원 근거와 트레이 아이콘 모양·재실행 대기 화면 USER_CONFIRMED는 재사용했다. 원래 production MSI/EXE와 사용자 직하 메타데이터·History·CompletionOrder를 보존했다. 제품 복구 수정·재검증과 정식 공개는 아직 없으며, 원시 설치 진단과 사용자 경로는 비공개로 보존한다. [실제 시험](TEST_RESULTS.md)과 [현재 제한](KNOWN_LIMITATIONS.md)에 개별 결과를 기록한다.

## 2026-10-06 추가 대조 이후의 상태

강제 InstallExecute 없는 normalFinalize deferred 실패와 표준 msiexec /qn 대조에서도 실제 실패 후 등록 상태 차이 18개가 남아 자동 복구는 FAIL이다. 추가 InstallExecute나 Python API 호출만이 원인이라는 가설은 배제했지만 근본 원인은 아직 확정하지 않았다. 권한 요청 후보는 Summary WordCount와 PackageCode만 바꾼 비공개 진단용이며, 실제 권한 요청 뒤 승인 미완료·exit 1602로 종료해 후반 실패 대조는 NOTRUN이다. 원래 production의 권한 정책은 그대로다. 2026-10-06 00:00 KST 원래 설치·설정·시작 항목과 사용자 직하 메타데이터·History·CompletionOrder의 복원, 앱 종료를 확인했다. 해결 검증과 정식 릴리즈는 보류한다.

## 2026-10-06 최종 정상 0.2.1의 설치·배포 상태

Installer 상승 권한을 허용하는 Summary WordCount 10→2와 설치 버튼 방패를 정상 제작 과정에 반영했다. 현재 사용자 LocalAppData·HKCU 설치를 유지하며 Windows가 관리자 승인을 요청하면 사용자가 직접 승인한다. 설치 후 앱은 일반 권한으로 실행한다. 외부 runtime은 필요하지 않고 코드 서명은 없다.

최종 정상 MSI `DownloadVersionManager-Watcher-0.2.1-x64.msi`의 SHA-256은 `0feea2fc119bad780da9dcb57d2a0303ef0e2e0c6f6a20a746fd3ab3f86a0ef5`다. 같은 Windows 11 x64 PC에서 두 취소·동등 payload 후반 실패 자동 복구·복구 후 정상 재설치·추가 인자 없는 앱의 medium token·트레이 종료·정상 제거를 확인했다. 원래 설치 위치와 실행 설정·기본값·Run을 복원했고 최종 앱은 종료 상태다. 과거 no-elevation FAIL과 UAC 미승인으로 후반 실패에 도달하지 못한 NOTRUN은 보존한다.

정식 릴리즈용 정상 MSI를 준비했지만 GitHub Release 게시는 실행하지 않았다. 공개 0.2.0 자산·링크는 유지한다. CI의 0.2.1 정상 자산 경로/조건과 YAML 검사는 PASS, 실제 CI는 NOTRUN이며 미래 재빌드 파일의 지문은 별도 검증한다. 다른 PC·클린 OS·모든 설치 실패 지점은 인증하지 않으며 조직 도입·상용 승인은 미결정이다. [실제 시험](TEST_RESULTS.md)과 [현재 제한](KNOWN_LIMITATIONS.md)을 따른다.
