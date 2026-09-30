# 실제 브라우저·설치 시험

일반 사용자 Windows에서 기존 DownloadVersionManager 설치·양쪽 registry view의 NativeMessagingHosts·HKLM 충돌·동일 upgrade code 설치가 없는지 사전 검사한다. 기존 설치가 있으면 자동 제거하거나 덮어쓰지 않는다. 업무 profile 대신 `artifacts/download-version-manager` 안의 Chrome/Edge 별도 시험 profile과 합성 다운로드 directory를 사용한다. 보안 policy·실제 사용자 profile 파일을 직접 변경하지 않는다.

평가 MSI fresh install 후 설치된 extension을 공식 개발용 Load unpacked UI로 활성화한다. 스토어/정책 자동 설치 합격으로 확대하지 않는다. 실제 installed Chrome/Edge 버전과 확장 ID·Host 응답 버전·MSI SHA-256을 기록한다.

로컬 HTTP fixture로 `보고서.xlsx` Content-Disposition 다운로드를 차례로 실행한다. 첫 다운로드 이름, 동일 내용 재다운로드의 신규 file ID/time와 History 부재, 다른 내용의 History A/target B, 실제 프로세스 잠금에서 두 파일 보존/History 무변경/짧은 오류 알림을 확인한다. 추가로 원래 `(1)`·`(2)` 이름과 다른 parent, service worker suspend 뒤 완료 복원·metadata 정리, ping 후 Host 종료/idle 0을 관찰한다. API mock으로 실제 contract PASS를 대체하지 않는다.

설치 수명주기는 같은 MSI repair·누락 파일 repair, 같은 버전 재실행, 별도 시험용 0.1.1 upgrade, uninstall/reinstall, 별도 고의 실패 MSI rollback을 시험한다. production 0.1.0을 시험 후 복원하며 `_history`·다운로드·unrelated files/registry fixture를 보존한다. 시작 항목/service/task·재부팅 요구·강제 browser 종료 부재를 검사한다. 성공한 관련 시험을 이유 없이 재실행하지 않는다.

실제 시험 수행이 불가능하면 결과를 NOT RUN과 정확한 blocker로 남긴다. 모든 gate의 PASS가 없으면 `build/release-gate.py`는 stable을 차단한다.

## 사용자 PC 조작이 필요한 다음 단계

현재 확인한 후보는 main `38640f518de0c25b52798e3d9ddd03b23d83f689`의 제품 0.1.0 / protocol 2 CI 평가 MSI다. [CI 36724339153](https://github.com/prozac0401/Workspace/actions/runs/36724339153)의 MSI·SHA256SUMS를 `artifacts/download-version-manager/windows-continuation-20260930/ci-36724339153/0.1.0-evaluation/`에 내려받았으며 실제 MSI SHA-256은 `4e4d26dc64e2fea0e6b323af036f7c195d4f1dd3e7178907209537e8d32bb7d8`이다. 현재 PC에서 사용자가 승인한 전용 설치·직접 Host 확인·공식 제거는 PASS이고 시험 설치는 정리했다. 이전 `0.1.0-evaluation-followup-20260930/`과 protocol 1 후보는 과거 증거로 보존하며 파일을 혼용하지 않는다. 실제 평가 MSI 설치·확장 활성화는 해당 작업의 사용자 승인을 확인하고 시작 메뉴의 설치 마무리 안내를 사용한다.

1. Chrome와 Edge에 각각 로그인하지 않는 평가 profile을 만들고 기존 업무 profile과 구분한다. 시험 다운로드는 `artifacts/download-version-manager/browser-manual/Chrome` 또는 `Edge`처럼 분리한 합성 폴더에 저장한다.
2. 각 브라우저의 공식 확장 관리 화면에서 개발 모드와 압축 풀린 확장 로드를 선택하고 설치된 `extension` 폴더를 활성화한다. 기업 정책이 차단하면 정책을 바꾸지 않고 그 상태를 기록한다.
3. 확장을 활성화하면 새 다운로드부터 자동 처리를 시도한다. 설치 연결 확인은 활성화 스위치가 아닌 진단이다. 시험 다운로드 전 양쪽 확장의 설치 연결 확인에서 Host 0.1.0 / protocol 2 연결을 확인한다. MSI 등록/직접 ping만으로 이 단계 PASS를 대신하지 않는다.
4. loopback fixture의 first → same → changed → locked를 각 브라우저에서 실행한다. 신규 객체의 file ID와 시간, 원래 이름, History 내용, 잠금 오류 알림을 기록한다. 원래 `(1)`/`(2)` 이름과 worker suspend도 확인한다. 잠금·snapshot·fixture 서버는 명시적인 시험 동안만 실행하는 개발 helper이며 제품에 설치하지 않는다.

확장 활성화 뒤의 HTTP 다운로드와 파일 검사는 이어서 진행할 수 있다. 깨끗한 Windows 11 표준 사용자에서 제품 게시 후 실패 복구를 비교하려면 별도 PC/VM 준비가 필요하다. 현재 PC에서는 해당 실패를 이미 재현했고 공식 제거로 자기 시험 등록을 정리했다. [TEST_RESULTS](../../TEST_RESULTS.md)의 FAIL을 실기 준비만으로 PASS로 변경하지 않는다.

## 명령과 시험 종료

```powershell
python tools/DownloadVersionManager/build/build.py --lifecycle-packages
python tools/DownloadVersionManager/build/build.py --version 0.1.1
python tools/DownloadVersionManager/tests/integration/installer.py prepare --msi artifacts/download-version-manager/0.1.0-evaluation/DownloadVersionManager-0.1.0-x64.msi --output artifacts/download-version-manager/0.1.0-evaluation/installer-results.json
python tools/DownloadVersionManager/tests/integration/installer.py resume --output artifacts/download-version-manager/0.1.0-evaluation/installer-results.json --upgrade artifacts/download-version-manager/0.1.1-evaluation/DownloadVersionManager-0.1.1-x64.msi --rollback artifacts/download-version-manager/0.1.0-evaluation/DownloadVersionManager-rollback-test.msi
python tools/DownloadVersionManager/tests/integration/presence.py --output artifacts/download-version-manager/0.1.0-evaluation/presence.json
# 실제 브라우저 확인에 필요한 합성 endpoint만 실행. 시험 후 Ctrl+C.
python tools/DownloadVersionManager/tests/integration/fixture-server.py --port 0
# 브라우저 시험이 끝나면 시험 소유 설치만 제거. 업무 fixture는 보존.
python tools/DownloadVersionManager/tests/integration/installer.py cleanup --output artifacts/download-version-manager/0.1.0-evaluation/installer-results.json
```

SDK 위치가 자동 검색되지 않으면 상위 빌드에 `--msvc`, `--sdk`, `--wix`를 명시한다. 버전 0.1.1과 rollback MSI는 실기 fixture이며 사용자 설치 asset으로 배포하지 않는다. `installer.py`는 Windows Installer 공식 API를 별도 제한 시간 자식 프로세스에서 호출한다. CLI·UI·깨끗한 VM 결과를 대신했다고 확대하지 않는다. 로그에는 로컬 설치 경로가 포함되므로 공개 사이트에 복사하지 않는다.

`--lifecycle-packages`는 제품 게시 전, 게시 후 deferred, InstallExecute 후 immediate 실패 fixture를 만든다. `installer_faults.py --production <MSI> --late <late-test-MSI> --postexecute <postexecute-test-MSI> --output <결과.json>`은 두 늦은 실패를 별도로 시험한다. preflight 뒤 이 시험이 만든 정확한 제품 등록만 공식 MSI 제거로 정리하고, 복구 실패는 exit 1로 보고한다. `resources.py --only-gib`는 이미 통과한 10/100 MiB를 반복하지 않고 선택적 1 GiB만 측정한다.

## 실패 증거 보존과 Linux에서 가능한 준비

`installer_faults.py`는 진행 중인 trial도 aggregate 결과에 기록한다. 파일/Native 등록 rollback 검증이나 보존 fixture 검증이 실패하면 해당 단계의 FAIL과 중단 상태를 남기고 즉시 멈춘다. 기존 설치·예상하지 않은 제품 등록은 자동 제거하지 않는다. 중단된 trial의 `cleaned`/`finished`를 확인하지 않은 채 다음 설치를 시도하지 않는다. timeout은 NOT RUN이며 복구 PASS가 아니다.

Linux에서는 `python tools/DownloadVersionManager/tests/integration/installer_faults_test.py`로 가짜 lifecycle 의존성의 증거 기록·중단 흐름만 시험할 수 있다. Windows MSI 실행, registry rollback, 재설치 성공을 검증하지 않는다. 이 회귀시험은 Windows 상위 빌드에도 포함한다.

Windows 11 잔류 원인 비교에는 실패 지점별 aggregate 결과, `post-publication-deferred-state.json`과 `post-InstallExecute-immediate-state.json`, 각 state의 `work` 아래 해당 실패·재설치의 `.log`/`-exit.json`, Windows build·표준 사용자/권한 수준 및 실제 MSI SHA-256이 필요하다. 기존 기록은 access denied(5)와 1638을 보고했지만 원본 로그 없이 권한 문제의 원인이나 제품 수정 방향을 확정하지 않는다. 상세 로그와 절대 로컬 경로는 private 진단으로 보관하고 공개 사이트/Release에 올리지 않는다. raw log의 CI 업로드를 자동 확대하지 않는다.

이번 인계 조사에서는 과거 두 late-failure state의 MSI SHA-256과 현재 같은 경로 파일이 불일치했다. 기록한 원본 파일을 확보하거나 새 후보·새 출력·별도 승인으로 시험을 설계하기 전에는 기존 경로 MSI를 원본으로 재실행하지 않는다. 현재 진단 token을 과거 실패 실행 권한으로 간주하지 않는다. 원본/현재 파일 지문과 `.log`/exit JSON 사본은 비공개 artifact로 보존하고 [후속 결과](../../TEST_RESULTS.md)를 따른다.
