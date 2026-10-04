# DownloadVersionManager · 0.2.0 폴더 감시

**현재 상태(2026-10-04 KST): 무서명 기능 평가 prerelease 준비 완료, 공개 MSI 게시 전입니다.** 브라우저 확장 없이 지정 폴더를 감시하는 네이티브 Windows 프로그램입니다. 기존 0.1.0 평가 버전과 과거 실패 기록은 보존합니다.

[사용 안내](../../docs/tools/download-version-manager/index.md) · [0.2.0 명세](../../docs/tools/download-version-manager/next-version-specification.md) · [설계](../../docs/design/0028-download-version-manager-folder-input.md) · [실제 시험](TEST_RESULTS.md) · [남은 제한](KNOWN_LIMITATIONS.md)

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

이름 suffix는 사용자 채택 관례입니다. 처음부터 번호가 있는 별개 이름도 원래 대상이 있으면 처리될 수 있으므로 이런 이름을 별개 문서로 사용하는 폴더에는 감시를 적용하지 않습니다. 직접 덮어쓴 이전 내용의 복구는 보장하지 않습니다.

## 시작·설정·제거

일반 사용자 프로세스 한 개가 선택 폴더의 OS 변경 알림을 비재귀로 받습니다. **감시 시작**·**감시 중지**를 제공하며 창을 닫으면 감시를 종료합니다. 로그인 자동 실행을 선택했다면 다음 로그인에서 다시 시작합니다.

Windows `FOLDERID_Downloads`에서 현재 사용자 다운로드 위치를 해석합니다. 기본 위치 추종을 선택한 경우 앱 시작과 사용자 폴더 registry 알림에서 경로를 갱신합니다. 사용자 지정 폴더는 위치 추종 대상이 아닙니다.

설치 위치는 `%LOCALAPPDATA%/Programs/DownloadVersionManagerWatcher`, 설정·설치 등록·선택한 로그인 시작 항목은 HKCU입니다. 새 MSI 식별자와 경로는 0.1.0과 분리합니다. 구버전 설치·브라우저 등록·CompletionOrder는 자동 변환하거나 삭제하지 않습니다. 구버전 확장과 동일 폴더에서 함께 실행하지 않습니다.

제거 전에 프로그램을 닫습니다. 감시 폴더·History와 사용자 실행 설정은 보존합니다. 코드 서명이 없으며 조직의 도입·상용 승인을 의미하지 않습니다.

## 파일 보존

크기를 먼저 비교하고 같은 크기만 64 KiB 버퍼로 SHA-256을 계산합니다. 신규 객체와 그 파일 시간을 유지하는 이름 이동을 사용합니다. 파일 이동 실패 시 이전 이름 복구를 시도하고 복구 실패 위치를 안내합니다. 앱을 강제 종료하지 않습니다.

두 번의 이동은 하나의 트랜잭션이 아닙니다. 강제 종료·전원 장애 때 `_history` 또는 `.dvm-…pending`에 이전 객체가 남을 수 있습니다. 자동 복원·잔재 일괄 삭제는 없습니다. 파일 내용·내용 hash·telemetry를 외부에 전송하지 않습니다.

## 제작과 증거

```powershell
python tools/DownloadVersionManager/build/build-watcher.py --tests --msvc <MSVC-root> --sdk <SDK-root> --wix <wix.exe>
```

Windows x64 MSVC·Windows SDK·WiX 4·Python이 제작용으로 필요합니다. C++ `/MT` 실행 파일과 MSI 하나를 제작하며 최종 사용자에게 개발 도구가 필요하지 않습니다. 변경된 폴더 입력·기존 그룹 처리·설치 위험에 필요한 검증만 수행합니다.

`source/app.cpp`, `watcher.cpp`, `review.cpp`, 기존 `engine.cpp`를 새 빌드에서 사용합니다. 폴더 엔진 8건·watcher 15건·최초 그룹 4건과 MSI 구조 검사, 수정 후보의 설치/실행·repair·제거·파일 보존 5건, 화면 높이 수정 후보의 설치/실행·제거·보존 4건은 PASS입니다. 최종 메시지 수정 제작에는 바뀌지 않은 관련 설치 근거를 재사용했으며 새 late-failure의 설치 등록 rollback은 FAIL로 남습니다. [배포 기록](../../docs/delivery/download-version-manager-watcher-release-20261004.md)에 각 후보 지문과 한계를 구분했습니다.

기존 `version.json`의 0.1.0 / protocol 2, `source/host.cpp`, `extension`, `build/build.py`와 기존 시험·산출물은 구버전 근거로 남깁니다. 0.1.0의 Win11 설치 실패 복구 FAIL·단일 배포 FAIL·실제 브라우저 NOT RUN을 새 버전의 PASS로 바꾸지 않습니다.
