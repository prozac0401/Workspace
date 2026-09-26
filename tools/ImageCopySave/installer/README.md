# 로컬에서 패키지를 만들고 설치 시험하기

도구: ImageCopySave · 패키지 기본 버전: 0.1.1.0 · 상태: 평가 후보, 설치 실기 NOT RUN  
책임: 도구 개발·검증 담당 · 적용 범위: Windows 11 x64 개발·검증 환경  
작성일: 2026-09-25

native Shell DLL과 자체 포함 helper를 full MSIX로 묶습니다. 로컬 빌드부터 패키지 확인까지 Git, 가상환경, 원격 CI가 필요하지 않습니다. **서명과 실제 설치·메뉴 검증이 끝나지 않은 평가 후보입니다.** 패키지 생성 성공을 제품 출시 승인으로 표시하지 않습니다.

일반 사용자는 신뢰되는 설치 파일을 열어 설치하고 Windows 설정의 설치된 앱에서 제거하는 흐름을 사용해야 합니다. 아래 스크립트는 개발·검증 담당자용이며, 일반 사용자에게 수동 등록이나 개발자 모드를 요구하는 설치 대체물이 아닙니다.

## 로컬 빌드

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

## 서명 주체와 신뢰 확인

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

서명 후 SignTool의 일반 인증 정책으로 패키지 무결성과 신뢰를 확인합니다. 외부 타임스탬프 서버에 전송하지 않는 로컬 평가용 절차이므로 인증서 만료 이후의 신규 설치를 보장하지 않습니다. 상용 배포용 서명·타임스탬프 정책은 별도로 결정해야 합니다.

[verify-package.ps1](verify-package.ps1)은 설치 없이 identity·아키텍처·서명 존재·SHA256을 읽습니다. -RequireTrustedSignature는 실제 서명 검증을 추가하고 unsigned 또는 신뢰 실패를 거절합니다.

```powershell
.\tools\ImageCopySave\installer\verify-package.ps1 -PackagePath 'D:\검증\signed.msix' -ExpectedPublisher 'CN=승인된 서명 주체' -RequireTrustedSignature -SignTool 'C:\승인된SDK\x64\SignTool.exe'
```

## 설치·업데이트·제거 시험

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

## 사용자가 PC에서 확인할 부분

1. 서명 인증서의 사용 권한과 이 PC의 패키지 신뢰·설치 허용 조건을 확인합니다. 조직이 관리하는 인증서는 담당자 결정이 필요합니다.
2. 신뢰된 설치 파일을 일반 사용자로 열어 설치합니다. 원래 폴더의 첫 우클릭 메뉴에서 그림을 저장하고, 텍스트·빈 상태에서는 메뉴가 완전히 사라지는지 확인합니다. G0 정식 시험은 이미지→텍스트→빈 상태→이미지를 20회 반복합니다.
3. 서로 다른 탐색기 창·탭에서 호출 폴더에 저장되고 생성 파일이 선택되는지, 다른 탭으로 이동하면 포커스를 빼앗지 않는지 확인합니다.
4. 그림으로 복사한 뒤 helper가 종료된 상태에서 그림판과 실제 사용하는 Word/PowerPoint/메일/메신저에 붙여넣습니다. 앱 버전과 투명도 결과를 기록합니다.
5. 설치된 앱에서 제거·재설치하고 메뉴 중복·잔재가 없는지, 기존 파일 연결·다른 메뉴·저장 PNG가 유지되는지 확인합니다.

이 결과와 Windows 빌드·패키지 해시를 [G0 기록](../../../docs/tools/image-copy-save/G0_Menu_Feasibility.md)과 [시험 결과](../TEST_RESULTS.md)에 남깁니다. 자동 시험과 직접 COM 호출 성공을 실제 Explorer 메뉴·외부 앱·설치 수명주기의 PASS로 바꾸지 않습니다.

## 검증과 근거

2026-09-25 로컬에서 PowerShell 구문 검사, 기존 unsigned 평가 MSIX의 identity/해시 읽기, unsigned 신뢰 검사 거절, 예상 Publisher 불일치 거절을 확인했습니다. 서명 실행, 인증서 신뢰 변경, 실제 설치·업데이트·제거는 실행하지 않았습니다. 최종 로컬 빌드 결과는 상위 [시험 결과](../TEST_RESULTS.md)를 따릅니다.

- [원명세 v1.0](../../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.0.md) · [현재 명세 v1.1](../../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.1.md) · [추가 도구 개발 기준](../../../docs/policies/tools.md).
- [Microsoft: Explorer 메뉴와 패키지 등록](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer).
- [Microsoft: SignTool로 MSIX 서명](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool) · [서명·신뢰 조건](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview).

2026-09-25: 기존 원격 패키징 기록과 실제 설치 미실행을 구분하고 로컬 일괄 빌드, 오래된 native DLL 차단, Publisher/Version 지정, 안전한 서명·검사·현재 사용자 설치/제거 절차를 추가했습니다.
