# 무서명 MSI를 만들고 설치 시험하기

도구: ImageCopySave · MSI 기본 버전: 0.2.0 · 상태: 정식 Release 게시 완료 · Pages 안내 배포 중

책임: 도구 개발·검증 담당 · 적용 범위: Windows 11 x64

작성일: 2026-09-25 · 최신 확인: 2026-09-27

현재 제품은 **별도 서명 없는 자체 포함 MSI**로 설치합니다. 사용자가 승인한 설치 방식은 관리자 권한의 PC 전체 설치이며, 평소 그림 복사·저장은 일반 사용자로 실행합니다. 인증서 설치, 개발자 모드, PowerShell 실행, 수동 레지스트리 등록을 일반 사용자에게 요구하지 않습니다. MSI에 포함한 native 보존 검사는 설치 자원을 읽어 비교하고 실제 쓰기·제거·롤백은 Windows Installer가 담당합니다.

외부 호스트에서 같은 0.2.0 MSI의 전체 보존 시험 **32 PASS / 0 FAIL / 0 NOT RUN**을 확인했습니다. HKLM·HKCU 충돌 차단, 외부 수정 보존, 복구·업데이트·제거와 실패 롤백을 통과했고 합성 시험 등록을 정리하며 업무 자료 역할의 fixture는 보존했습니다. 기본 위치 최종 설치도 msiexec 0으로 PASS했으며 재시작 요구와 Explorer 강제 재시작은 없었습니다. 기본 설치본의 실제 탐색기 복사·저장 대표 확인도 PASS했으며, 저장 후 최종 행 선택은 미확인입니다. [0.2.0 정식 Release](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.0) 게시와 공개 MSI·체크섬 검증을 완료했습니다. Pages 안내 배포는 진행 중입니다. [최신 0.2.0 기록](../../../docs/delivery/image-020-release-20260927.md)에서 실제 결과와 남은 게시 절차를 확인합니다.

메뉴는 Windows 11 기본 모드에서 **우클릭 → 더 많은 옵션 표시**, 클래식 직접 표시 모드에서는 우클릭 메뉴에서 바로 접근합니다. 기본 메뉴의 복사·저장 두 기능은 사용자 직접 확인 PASS이며, 기존 클래식 메뉴의 대표 결과도 유지합니다. 모든 조건별 숨김·창/탭 검증으로 확대하지 않습니다. Windows 10 형식 메뉴라는 표현은 Windows 11의 표시 모드를 뜻하며 Windows 10 OS 지원 인증이 아닙니다. 설치기는 메뉴 모드 설정을 바꾸지 않습니다.

이전 0.1.1의 설치·누락 파일 복구·업데이트·제거·고의 실패 롤백·재설치 및 승인된 시험용 메뉴 설정 복구는 [당시 기록](../../../docs/delivery/image-classic-msi-20260927.md)으로 보존합니다. 과거 일시적인 Explorer 무응답은 원인 미확정입니다. 새 보호 기능이 이전 시험에 포함되어 있었다고 해석하지 않습니다.

## 일반 사용자 설치·복구·제거

공개한 `ImageCopySave-0.2.0-x64.msi`를 열고 설치를 선택한 뒤 Windows의 관리자 승인 창을 확인합니다. 설치 위치는 `Program Files\Workspace\ImageCopySave`입니다. 추가 런타임을 내려받지 않습니다.

그림 파일 한 개를 우클릭해 **그림으로 복사**를 선택합니다. 복사한 그림을 파일로 만들려면 저장할 폴더 빈 공간을 우클릭해 **복사한 그림 저장**을 선택합니다. 텍스트나 빈 클립보드에서는 저장 항목이 숨겨집니다.

같은 MSI를 다시 열면 복구 또는 제거를 선택할 수 있습니다. Windows 설정의 설치된 앱에서도 ImageCopySave를 제거할 수 있습니다. 제거는 설치한 프로그램 파일과 메뉴 등록을 대상으로 하며 저장한 PNG와 원본 그림을 삭제하지 않습니다.

설치·복구·업데이트·제거는 Explorer를 자동 종료하거나 Windows를 자동 재시작하지 않습니다. Windows가 사용 중인 파일 때문에 재시작을 요청할 수 있습니다. 작업을 저장한 뒤 직접 재시작하고 완료 여부를 확인합니다. 검증 스크립트의 `3010`은 재시작 필요로 별도 기록하며 깨끗한 제거 PASS로 바꾸지 않습니다.

## 제품 MSI 빌드와 정적 확인

개발 PC에는 기존 .NET/native 빌드 도구와 WiX 4가 필요합니다. 스크립트가 도구를 자동 설치하지 않습니다. [build-msi.ps1](build-msi.ps1)은 `build-package.ps1`에서 이미 자체 포함 게시·파일 해시를 검증한 payload를 입력으로 사용하고 최신 native 빌드의 소스/DLL 해시를 검사합니다. 이전 Appx manifest와 로고는 제외하며 제품 DLL·helper와 .NET Desktop 런타임을 MSI에 전부 포함합니다. Appx 등록은 수행하지 않습니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/build-msi.ps1 -Version 0.2.0
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/verify-msi.ps1 -MsiPath "<출력 MSI>"
```

출력은 실행별 `artifacts/image-copy-save/msi/<실행 ID>/` 아래에 생성됩니다. `build-metadata.json`에는 MSI SHA256, 서명 없음, ProductCode, 입력 파일 해시와 시험용 여부를 기록합니다. `verify-msi.ps1`은 MSI를 설치하지 않고 PC 전체 범위, 포함 파일, 두 COM 서버, 다섯 메뉴 등록, 내장 cabinet, native 검사 custom action 두 개의 바이너리·실행 순서·소유 목록과 자동 종료 방지 설정을 확인합니다. 정적 확인을 실제 설치·Explorer 시험 PASS로 취급하지 않습니다.

[build-guard.ps1](build-guard.ps1)은 정적으로 링크한 x64 보호 DLL과 합성 native 시험을 빌드합니다. DLL은 MSI Binary 테이블에 내장하며 설치된 프로그램 파일을 검사 실행 파일로 신뢰하지 않습니다. [보존 설계](../../../docs/design/0024-image-msi-preservation.md)의 즉시·지연 검사가 비교를 수행하고, 등록은 MSI의 기본 파일·레지스트리 기능으로 처리합니다. 별도 등록 실행 파일이나 설치 중 Appx/PowerShell custom action은 없습니다. `HKLM\Software\Classes`의 제품 소유 CLSID 두 개와 `Directory\Background\shell\Workspace.ImageCopySave.Save`, `SystemFileAssociations\.png|.jpg|.jpeg|.bmp\shell\Workspace.ImageCopySave.Copy`만 사용합니다. 기본 파일 연결과 다른 도구의 메뉴를 변경하지 않으며 모든 명령에 `NeverDefault`를 지정합니다.

[export-ownership-baseline.ps1](export-ownership-baseline.ps1)은 명시한 MSI의 감사 해시와 빌드 메타데이터를 대조해 schema 2 소유 목록을 만드는 빌드 전용 도구입니다. MSI를 읽기 전용으로 열어 404개 파일의 경로·크기·컴포넌트 GUID와 23개 문자열 등록 값을 확인하며 설치나 제품 등록 변경을 하지 않습니다. 결과에는 개인 경로를 포함하지 않습니다. 일반 유지보수 guard는 현재 설치 DB를 사용하고, 이전 패키지 갱신은 빌드 시 내장한 ProductCode·PackageCode별 감사 목록을 사용합니다. 설치 중 캐시 MSI를 MsiOpenDatabase로 열지 않습니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/export-ownership-baseline.ps1 -MsiPath "<감사할 MSI>" -ExpectedMsiSha256 "<확인한 SHA-256>" -OutputPath "<저장소 artifacts 아래 baseline.json>"
```

MetadataPath를 생략하면 MSI 옆 build-metadata.json을 읽습니다. ReferenceBaseline을 지정하면 파일 경로·컴포넌트 GUID와 등록 값의 동일성도 확인합니다. 로컬 실패 시험 설치를 위한 same-ProductCode 복구 갱신은 빌드 시 특정 과거 PackageCode를 고정한 별도 후보만 허용하며, 실제 보존 검사를 계속 수행합니다. 공개 제품이나 일반 강제 설치 옵션으로 제공하지 않습니다.

## 0.2.0 보존 회귀와 실제 설치 수명주기

[test-msi-preservation.ps1](test-msi-preservation.ps1)의 기본 Inspect는 기존 설치·등록·시험 폴더 충돌을 읽어 확인합니다. Suite는 사전 검사를 통과한 뒤 전용 artifacts 디렉터리와 정확히 소유한 합성 등록만 사용합니다. 실패 시 다음 사례를 실행하거나 제품을 자동 제거하지 않고 검토를 위해 중단합니다. 업무 폴더와 기존 사용자 등록을 시험 자료로 사용하지 않습니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/test-msi-preservation.ps1 -MsiPath "<0.2.0 후보 MSI>" -Action Inspect
```

[invoke-msi-preservation-sequence.ps1](invoke-msi-preservation-sequence.ps1)은 기존 검증 후보에서의 업데이트·제거, 격리된 보존 회귀, 최종 설치를 정상 UAC 승인 아래 순서대로 수행하는 시험기입니다. 기본 Inspect로 고정할 입력·파일 해시와 사전 조건을 확인하며 Run은 승인된 시험 순서에 한해 실행합니다. 단계가 실패하거나 재부팅이 필요하면 중단합니다. 시험기를 직접 사용하지 않는 일반 MSI에도 내장 보호가 적용되어야 하며, 시험기의 사전 확인을 제품 기능의 증거로 대체하지 않습니다.

[invoke-msi-preservation-recovery.ps1](invoke-msi-preservation-recovery.ps1)은 실패 보고서가 가리키는 정확한 `artifacts/image-copy-save/msi-preservation/<실패 실행 ID>/installed-product`만 복구하는 개발자용 시험기입니다. 기본 `Inspect`는 제품·등록을 변경하지 않고 실패 보고서·고정한 MSI·설치 파일과 값의 일치를 확인합니다. 승인된 `Run`은 내장 감사 목록이 고정된 복구 갱신 → 수정 guard를 통한 시험 설치 제거 → 깨끗한 상태 확인 → 새 보존 회귀 → 최종 설치를 순서대로 실행합니다. 임의 설치 폴더나 레지스트리를 직접 정리하지 않으며 불일치·실패·재부팅 요구가 있으면 중단합니다.

개발자용 `-ServicedReport`는 이미 완료된 복구 갱신을 반복하지 않고 제거부터 재개하는 제한 옵션입니다. 감사한 08:13 실행의 recovery.json·MSI 로그 해시, 원래 실패 이력과 모든 후보 입력을 고정하고, 양쪽 guard PASS·InstallFinalize 완료·3010 및 현재 복구 패키지의 404파일·23등록 값을 다시 확인합니다. 제품 폴더나 현재 캐시를 향한 예약 작업은 차단하며 기존 예약 목록은 수정하지 않습니다. 임의의 3010 결과를 통과시키는 옵션이나 일반 사용자 제거 방법이 아닙니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/preservation-tests/test-recovery-resume.ps1 -ServicedReport "<감사한 08:13 실행의 recovery.json>"
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/invoke-msi-preservation-recovery.ps1 -FailedReport "<원래 실패 result.json>" -InstalledMsiPath "<원래 설치 MSI>" -RecoveryMsiPath "<고정 복구 MSI>" -MsiPath "<제품 후보 MSI>" -RollbackMsiPath "<짝지은 롤백 MSI>" -PreviousMetadata "<0.1.1 build-metadata.json>" -ServicedReport "<감사한 08:13 실행의 recovery.json>" -Action Inspect
```

첫 명령은 이력·예약 경로의 순수 회귀이며 MSI 동작과 등록 쓰기를 하지 않습니다. Inspect 통과 뒤 승인된 실제 재개에만 같은 입력으로 `-Action Run -RequestElevation`을 사용해 정상 UAC를 요청합니다. 3010 원래 기록을 그대로 보존하며, 이후 단계가 실패하면 다시 중단합니다. 현재 실제 상태는 위 작업 기록을 따릅니다.

보존 회귀는 PC 전체 HKLM과 설치를 실행한 사용자의 HKCU 일곱 루트·설치 디렉터리 충돌, 수정 파일·값·추가 NTFS 스트림, 누락 파일 복구, 추가 파일·값·타사 등록·기본 연결 보존, 새 설치와 업데이트 실패 롤백을 대상으로 합니다. 시험 자료를 교체·정리하는 도우미는 [합성 primitive 시험](preservation-tests/test-fixture-primitives.ps1)으로 별도 확인합니다.

### 이전 0.1.x 수명주기 재현 절차

아래 버전별 예시는 앞선 0.1.x 시험을 재현하는 개발 절차입니다. 해당 PASS를 0.2.0의 새 보호 결과로 합산하지 않습니다.

아래는 개발·검증 담당자용이며 **한 번에 한 동작씩** 실행합니다. [invoke-msi-test.ps1](invoke-msi-test.ps1)은 정상 UAC 승인을 요청한 뒤 [test-msi-lifecycle.ps1](test-msi-lifecycle.ps1)을 실행합니다. 기존 설치나 같은 CLSID/메뉴 등록, 알 수 없는 설치 폴더가 있으면 최초 설치 시험을 시작하지 않습니다. 사용자별 등록이 PC 전체 등록을 가리는 경우도 중단합니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/invoke-msi-test.ps1 -MsiPath "<0.1.0 시험 MSI>" -Action Install
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/invoke-msi-test.ps1 -MsiPath "<같은 MSI>" -Action Repair -DamageOwnedFile
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/invoke-msi-test.ps1 -MsiPath "<0.1.1 MSI>" -Action Upgrade -PreviousMetadata "<0.1.0 build-metadata.json>"
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/invoke-msi-test.ps1 -MsiPath "<0.1.1 MSI>" -Action Remove
```

[invoke-msi-final-sequence.ps1](invoke-msi-final-sequence.ps1)은 승인된 최종 후보의 시험을 한 번의 정상 UAC 아래 순차 실행할 때 사용합니다. `-MsiPath`에 0.1.1 제품 MSI, `-RollbackMsiPath`에 별도 실패 시험 MSI를 지정하면 제거 → 실패 롤백 → 재설치를 실행합니다. `-PreviousMetadata`에 검증된 0.1.0 메타데이터를 추가하면 업데이트를 먼저 수행합니다. 승인 전에 파일 해시를 고정하고 각 단계의 실제 결과를 확인하며, 실패나 재부팅 요구가 있으면 다음 단계로 넘어가지 않습니다. 일반 사용자 설치 명령이 아닌 개발 시험 절차입니다.

복구 시험의 `-DamageOwnedFile`은 먼저 모든 설치 파일의 해시를 확인하고, 정확히 일치하는 `ImageCopySave.Engine.dll` 하나만 시험 기록 폴더에 백업한 뒤 제거합니다. 파일과 모든 조상의 junction·심볼릭 링크를 거절합니다. MSI 복구 후 모든 파일이 원래 해시로 돌아오는지 확인합니다. 실행 실패 시 대상 파일이 없을 때만 해시가 일치하는 백업을 복원하며, 이미 생성된 파일을 덮어쓰지 않습니다. [test-msi-recovery.ps1](test-msi-recovery.ps1)은 설치 없이 합성 파일로 이 복구 경계를 시험합니다.

설치 시험은 합성 PNG의 해시도 보존합니다. 프로세스 강제 종료나 전원 차단은 스크립트의 복구 실행을 보장하지 않으므로, 그런 중단 후에는 기록된 설치 상태를 확인한 뒤 같은 MSI의 복구 또는 제거를 실행합니다. 설치 폴더를 재귀 삭제하지 않습니다.

롤백은 별도의 실패 전용 MSI로 확인합니다. 제품 MSI에는 실패 주입 기능이 들어가지 않습니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/build-msi.ps1 -Version 0.2.1 -RollbackTest
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/invoke-msi-test.ps1 -MsiPath "<ROLLBACK-TEST.msi>" -Action Rollback
```

실패 전용 MSI는 파일·레지스트리 작업을 실행한 뒤 오류를 발생시킵니다. Windows Installer의 롤백 후 제품 등록·파일·메뉴가 남지 않는지 확인합니다. 물리적인 전원 차단 시험을 대신했다고 기록하지 않습니다. 실제 결과는 `artifacts/image-copy-save/msi-lifecycle/<실행 ID>/result.json`과 MSI 로그에 남기며 공개 사이트에 포함하지 않습니다.

## 이전 Appx 경로의 이력

아래 절차는 Windows 11 첫 메뉴 배치를 검토하던 Appx/sparse 경로의 진단 기록입니다. 현재 classic 메뉴 제품 MSI의 필수 단계가 아닙니다. 일반 사용자 unsigned sparse 등록은 `0x80073D2B`, 과거 서명 full MSIX 설치는 `0x800B0109`로 차단됐습니다. 이후 관리자 unsigned sparse 등록·정리와 SYSTEM 진단 MSI·일반 사용자 등록 연결은 통과했습니다. 인증서와 보안 정책은 변경하지 않았습니다. [당시 서명 시험](../../../docs/delivery/image-copy-save-signing-20260927.md)과 [설치 권한 결정](../../../docs/design/0022-image-admin-install.md)을 이력으로 보존합니다.

### 이전 관리자 무서명 등록과 진단 MSI

[관리자 후속 결과](../../../docs/delivery/image-admin-install-20260927.md)는 unsigned sparse 관리자 등록·정리, SYSTEM staging/provisioning·제거, 별도 비상승 사용자 등록의 실제 PASS를 기록한다. 아래는 개발자용 진단이며 제품 설치 절차가 아니다. 외부 payload를 참조하는 진단 MSI를 다른 PC에 배포하지 않는다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/invoke-admin-probe.ps1 -ExternalLocation "<이 작업 트리 artifacts 아래 staging>" -MakeAppx "<기존 SDK x64 MakeAppx.exe>"
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/build-msi-context-probe.ps1 -ProbePackage "<위 시험에서 생성된 unsigned probe msix>" -ExternalLocation "<같은 staging>"
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/test-msi-context.ps1 -Msi "<생성된 진단 MSI>" -OutputDirectory "<생성된 실행 디렉터리>"
```

마지막 명령은 정상 UAC 승인 후 설치·진단·정리·MSI 제거까지 순차 실행한다. 기존 제품/시험 등록이나 probe 설치 디렉터리가 있으면 시작하지 않는다. 시험 기록에는 관리자 등록과 SYSTEM 동작을 구분한다. Explorer 설정·인증서·실행 정책을 변경하지 않는다.

일반 사용자 등록 연계 시험은 빌드에 -WaitForUserRegistration을 지정한다. system-probe.log의 AWAITING_ORDINARY_USER를 확인한 뒤 **비상승** 세션에서 생성된 MsiContextProbe.exe --register-user "<실행 디렉터리의 ordinary-user.log>"를 실행한다. system-probe.log.complete 파일을 만들면 정리하며, 신호가 없어도 120초 후 정리한다. 이 신호 파일은 명령이나 입력 경로로 해석하지 않는다. 중단·전원 차단 시 finally를 보장하지 않으므로 진단을 강제 종료하지 않는다. 다음 실행은 잔여 등록을 자동 인수하지 않는다.

## 이전 full MSIX 로컬 빌드

개발 PC에는 .NET SDK 10.0.401 또는 global.json이 허용하는 패치, MSVC C++ x64 컴파일러·헤더·desktop 라이브러리, Windows 11 SDK 10.0.22000.0 이상의 헤더·라이브러리·x64 MakeAppx가 필요합니다. 최종 패키지는 .NET 및 Windows Desktop 런타임을 자체 포함합니다.

저장소 루트에서 실행합니다. 빌드 스크립트는 도구를 자동 설치하거나 PC 설정을 바꾸지 않습니다. .tools/dotnet/dotnet.exe가 있으면 우선 사용합니다. 이번 PC에 검증해 준비한 .tools/image-copy-save-native/msvc 및 sdk도 자동 탐색합니다.

```powershell
powershell.exe -NoLogo -NoProfile -STA -File .\tools\ImageCopySave\build\build-local.ps1
```

[build-local.ps1](../build/build-local.ps1)은 엔진/helper 빌드·자동 시험 → native DLL 빌드·직접 COM 시험 → unsigned 패키지 생성·해제·내용 검증을 순서대로 수행합니다. 설치된 도구 자동 탐색이 불가능하면 -DotNet, -VCToolsRoot, -WindowsSdkRoot, -WindowsSdkVersion, -MakeAppx로 **이미 확보한** 경로를 지정합니다.

단계를 나눠 실행할 수도 있습니다.

```powershell
.\tools\ImageCopySave\build\build.ps1 -DotNet .\.tools\dotnet\dotnet.exe
.\tools\ImageCopySave\build\build-shell.ps1
powershell.exe -NoLogo -NoProfile -STA -File .\tools\ImageCopySave\build\build-package.ps1 -DotNet .\.tools\dotnet\dotnet.exe
```

패키징은 최신 native 빌드의 소스 해시와 DLL 해시를 검사합니다. 소스가 바뀌었거나 시험 metadata가 없으면 기존 DLL을 재사용하지 않고 중단합니다. helper/엔진은 게시 전후 소스·빌드 설정 해시가 일치해야 하며, 제품 이름 ImageCopySave와 지정한 패키지 버전으로 게시합니다. 이 일치 검사는 관리코드 시험 합격을 대신하지 않습니다. MakeAppx 검증은 끄지 않으며, 생성한 패키지를 다시 풀어 모든 입력 파일의 SHA256, CLSID, 실행 파일 경로, 아키텍처와 필수 자산을 확인합니다.

출력은 artifacts/image-copy-save 아래에 둡니다.

| 위치 | 확인할 내용 |
|---|---|
| automated-results.json | 엔진/helper 자동 시험과 NOT RUN 사유 |
| native-shell/shell-results.json | 등록 없는 native 정책·직접 COM 시험 |
| native-shell/build-metadata.json | 컴파일러·SDK·native 소스 및 DLL 해시 |
| package-evaluation/package-result.json | 최신 패키징 결과·실제 MSIX 경로·SHA256·로그 |
| package-evaluation/staging, unpacked, logs | 실행별 입력·해제 결과·빌드 기록 |

패키징은 실행별 새 디렉터리를 사용합니다. 로그·진단은 로컬 산출물이며 공개 사이트에 올리지 않습니다. status=PASS는 기록에 표시된 검사 범위에 한정합니다. productionRelease=false, signing/installation/explorerG0=NOT RUN을 유지합니다.

## 이전 full MSIX 평가 절차 — 현재 실행 지시 아님

아래 서명·설치 절차는 과거 평가 경로의 재현 기록입니다. 현재 무서명 MSI 요구의 후속 작업으로 실행하지 않습니다.

### 서명 주체와 신뢰 확인

기본 Name=ImageCopySave.Evaluation과 Publisher=CN=ImageCopySave.Evaluation은 평가 시안입니다. 최종 배포 identity·서명 주체·조직 설치 허용은 미결정입니다. 인증서가 PC에 있다는 사실만으로 사용 권한이나 다른 PC에서의 신뢰가 확인되지는 않습니다.

인증서 책임자가 사용을 허용한 코드서명 인증서의 Subject를 Publisher로 지정해 다시 빌드합니다. 원본 manifest는 보존하고 패키지용 복사본만 수정합니다. -Version은 같은 identity의 업데이트 시험용으로 증가시킬 수 있습니다.

```powershell
# 실제로 사용 승인을 받은 인증서의 전체 Subject로 지정합니다.
.\tools\ImageCopySave\build\build-package.ps1 -DotNet .\.tools\dotnet\dotnet.exe -Publisher 'CN=승인된 서명 주체' -Version '0.1.1.1'
```

[sign-package.ps1](sign-package.ps1)은 명시한 CurrentUser/My 인증서를 사용하여 **새 파일 사본**에 서명합니다. Subject 일치, 유효기간, 코드서명 용도와 개인키 존재를 검사합니다. 인증서 생성·가져오기·신뢰 저장소 수정·개인키 내보내기를 하지 않습니다. 원본 unsigned 파일과 이미 존재하는 출력은 덮어쓰지 않습니다.

```powershell
# 개발·검증 담당자만 실행합니다. 값은 실제 파일과 승인된 인증서로 바꿉니다.
.\tools\ImageCopySave\installer\sign-package.ps1 -PackagePath 'D:\검증\unsigned.msix' -OutputPath 'D:\검증\signed.msix' -CertificateThumbprint '인증서의 40자리 지문' -SignTool 'C:\승인된SDK\x64\SignTool.exe' -WhatIf
# 확인한 동일 명령에서 -WhatIf를 제거하면 새 파일 사본에 서명합니다.
```

서명 후 SignTool의 일반 인증 정책으로 패키지 무결성과 서명을 확인합니다. 이 검사 성공만으로 Windows 앱 패키지 배포의 신뢰·설치 허용을 보장하지 않습니다. 실제 설치 결과를 별도로 확인합니다. 외부 타임스탬프 서버에 전송하지 않는 로컬 평가용 절차이므로 인증서 만료 이후의 신규 설치를 보장하지 않습니다. 상용 배포용 서명·타임스탬프 정책은 별도로 결정해야 합니다.

[verify-package.ps1](verify-package.ps1)은 설치 없이 identity·아키텍처·서명 존재·SHA256을 읽습니다. -RequireTrustedSignature는 실제 서명 검증을 추가하고 unsigned 또는 신뢰 실패를 거절합니다.

```powershell
.\tools\ImageCopySave\installer\verify-package.ps1 -PackagePath 'D:\검증\signed.msix' -ExpectedPublisher 'CN=승인된 서명 주체' -RequireTrustedSignature -SignTool 'C:\승인된SDK\x64\SignTool.exe'
```

### 설치·업데이트·제거 시험

신뢰된 서명 패키지를 일반 사용자 계정에서 열어 설치합니다. Windows가 인증서나 조직 정책 때문에 거절하면, 인증서/PC 관리 담당자가 허용 조건을 해결해야 합니다. unsigned 예외 설치, 개발자 모드 전환, 수동 DLL 등록, 레지스트리 수정으로 우회하지 않습니다.

개발·검증 담당자는 [manage-install.ps1](manage-install.ps1)로 현재 사용자만 대상으로 검사할 수 있습니다. 기본 Inspect는 읽기만 합니다. 변경 작업은 정확한 Publisher를 요구하고 상승된 관리자 세션, 충돌 identity, unsigned/신뢰 실패를 거절합니다. Install은 기존 설치 없음, Update는 같은 identity의 더 높은 버전을 요구합니다.

```powershell
powershell.exe -NoProfile -File .\tools\ImageCopySave\installer\manage-install.ps1 -ExpectedPublisher 'CN=승인된 서명 주체'
# 안전 조건을 통과한 뒤 -WhatIf를 제거하면 해당 작업을 실제 수행합니다.
powershell.exe -NoProfile -File .\tools\ImageCopySave\installer\manage-install.ps1 -Action Install -PackagePath 'D:\검증\signed.msix' -ExpectedPublisher 'CN=승인된 서명 주체' -SignTool 'C:\승인된SDK\x64\SignTool.exe' -WhatIf
powershell.exe -NoProfile -File .\tools\ImageCopySave\installer\manage-install.ps1 -Action Remove -ExpectedPublisher 'CN=승인된 서명 주체' -WhatIf
```

설치·제거에는 Windows 패키지 API만 사용합니다. 다른 앱이나 사용자가 만든 PNG를 검색·삭제하지 않습니다. Explorer 강제 종료, 앱 강제 종료 옵션, 인증서 신뢰 변경을 수행하지 않습니다. Windows가 로그아웃을 요구하면 사용자가 작업을 저장한 뒤 직접 로그아웃/로그인하고 결과를 기록합니다.

실패하면 Windows의 오류와 현재 설치 identity·버전을 확인합니다. 자동 광범위 정리나 강제 다운그레이드는 하지 않습니다. 제거 후 재설치, 더 높은 버전으로 업데이트, 설치 중단/실패의 복구와 기존 사용자 PNG 보존은 실제 패키지로 별도 시험합니다.

### 이전 경로의 PC 확인 항목

1. 서명 인증서의 사용 권한과 이 PC의 패키지 신뢰·설치 허용 조건을 확인합니다. 조직이 관리하는 인증서는 담당자 결정이 필요합니다.
2. 신뢰된 설치 파일을 일반 사용자로 열어 설치합니다. 원래 폴더의 첫 우클릭 메뉴에서 그림을 저장하고, 텍스트·빈 상태에서는 메뉴가 완전히 사라지는지 확인합니다. G0 정식 시험은 이미지→텍스트→빈 상태→이미지를 20회 반복합니다.
3. 서로 다른 탐색기 창·탭에서 호출 폴더에 저장되고 생성 파일이 선택되는지, 다른 탭으로 이동하면 포커스를 빼앗지 않는지 확인합니다.
4. 그림으로 복사한 뒤 helper가 종료된 상태에서 그림판과 실제 사용하는 Word/PowerPoint/메일/메신저에 붙여넣습니다. 앱 버전과 투명도 결과를 기록합니다.
5. 설치된 앱에서 제거·재설치하고 메뉴 중복·잔재가 없는지, 기존 파일 연결·다른 메뉴·저장 PNG가 유지되는지 확인합니다.

이 결과와 Windows 빌드·패키지 해시를 [G0 기록](../../../docs/tools/image-copy-save/G0_Menu_Feasibility.md)과 [시험 결과](../TEST_RESULTS.md)에 남깁니다. 자동 시험과 직접 COM 호출 성공을 실제 Explorer 메뉴·외부 앱·설치 수명주기의 PASS로 바꾸지 않습니다.

## 검증과 근거

2026-09-25 로컬에서 PowerShell 구문 검사, 기존 unsigned 평가 MSIX의 identity/해시 읽기, unsigned 신뢰 검사 거절, 예상 Publisher 불일치 거절을 확인했습니다. 서명 실행, 인증서 신뢰 변경, 실제 설치·업데이트·제거는 실행하지 않았습니다. 최종 로컬 빌드 결과는 상위 [시험 결과](../TEST_RESULTS.md)를 따릅니다.

- [원명세 v1.0](../../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.0.md) · [현재 변경 계약 v1.2](../../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.2.md) · [추가 도구 개발 기준](../../../docs/policies/tools.md).
- [Microsoft: Explorer 메뉴와 패키지 등록](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer).
- [Microsoft: SignTool로 MSIX 서명](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool) · [서명·신뢰 조건](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview).

2026-09-25: 기존 원격 패키징 기록과 실제 설치 미실행을 구분하고 로컬 일괄 빌드, 오래된 native DLL 차단, Publisher/Version 지정, 안전한 서명·검사·현재 사용자 설치/제거 절차를 추가했습니다.
