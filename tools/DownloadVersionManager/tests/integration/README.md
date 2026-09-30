# 실제 브라우저·설치 시험

일반 사용자 Windows에서 기존 DownloadVersionManager 설치·양쪽 registry view의 NativeMessagingHosts·HKLM 충돌·동일 upgrade code 설치가 없는지 사전 검사한다. 기존 설치가 있으면 자동 제거하거나 덮어쓰지 않는다. 업무 profile 대신 `artifacts/download-version-manager` 안의 Chrome/Edge 별도 시험 profile과 합성 다운로드 directory를 사용한다. 보안 policy·실제 사용자 profile 파일을 직접 변경하지 않는다.

평가 MSI fresh install 후 설치된 extension을 공식 개발용 Load unpacked UI로 활성화한다. 스토어/정책 자동 설치 합격으로 확대하지 않는다. 실제 installed Chrome/Edge 버전과 확장 ID·Host 응답 버전·MSI SHA-256을 기록한다.

로컬 HTTP fixture로 `보고서.xlsx` Content-Disposition 다운로드를 차례로 실행한다. 첫 다운로드 이름, 동일 내용 재다운로드의 신규 file ID/time와 History 부재, 다른 내용의 History A/target B, 실제 프로세스 잠금에서 두 파일 보존/History 무변경/짧은 오류 알림을 확인한다. 추가로 원래 `(1)`·`(2)` 이름과 다른 parent, service worker suspend 뒤 완료 복원·metadata 정리, ping 후 Host 종료/idle 0을 관찰한다. API mock으로 실제 contract PASS를 대체하지 않는다.

설치 수명주기는 같은 MSI repair·누락 파일 repair, 같은 버전 재실행, 별도 시험용 0.1.1 upgrade, uninstall/reinstall, 별도 고의 실패 MSI rollback을 시험한다. production 0.1.0을 시험 후 복원하며 `_history`·다운로드·unrelated files/registry fixture를 보존한다. 시작 항목/service/task·재부팅 요구·강제 browser 종료 부재를 검사한다. 성공한 관련 시험을 이유 없이 재실행하지 않는다.

실제 시험 수행이 불가능하면 결과를 NOT RUN과 정확한 blocker로 남긴다. 모든 gate의 PASS가 없으면 `build/release-gate.py`는 stable을 차단한다.

## 사용자 PC 조작이 필요한 다음 단계

현재 후속 후보는 제품 0.1.0 / protocol 2다. 로컬 MSI·SHA256SUMS는 `artifacts/download-version-manager/0.1.0-evaluation-followup-20260930/`에 있다. 이전 protocol 1 후보와 섞지 않는다. 자동 installer 시험은 설치를 정리했으므로 평가 MSI를 설치한 뒤 시작 메뉴의 설치 마무리 안내를 사용한다.

1. Chrome와 Edge에 각각 로그인하지 않는 평가 profile을 만들고 기존 업무 profile과 구분한다. 시험 다운로드는 `artifacts/download-version-manager/browser-manual/Chrome` 또는 `Edge`처럼 분리한 합성 폴더에 저장한다.
2. 각 브라우저의 공식 확장 관리 화면에서 개발 모드와 압축 풀린 확장 로드를 선택하고 설치된 `extension` 폴더를 활성화한다. 기업 정책이 차단하면 정책을 바꾸지 않고 그 상태를 기록한다.
3. 양쪽 확장의 설치 연결 확인에서 Host 0.1.0 / protocol 2 연결을 확인한다. MSI 등록/직접 ping만으로 이 단계 PASS를 대신하지 않는다.
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
