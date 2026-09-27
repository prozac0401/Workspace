# ImageCopySave · 무서명 MSI 선행 구현성 확인

현재 설치 방침: 사용자가 관리자 설치를 승인했다. [ADR-0022](../../design/0022-image-admin-install.md)에 따른 관리자 무서명 등록·정리와 SYSTEM 진단 MSI 설치·제거, 비상승 사용자 등록은 PASS다. 제품 MSI와 새 메뉴 G0는 미완료다. 아래 비상승 0x80073D2B는 이전 조건의 이력이다.

도구 ID: ImageCopySave · 상태: 아래는 비상승 시험 이력, 관리자·SYSTEM 경로는 후속 PASS
날짜: 2026-09-27 · 책임: 개발·검증 담당
적용 정책: [추가 도구 개발 기준](../../policies/tools.md), [정책 문서 작성 규칙](../../policies/documentation.md)
관련 요구: [v1.1 명세](ImageCopySave_Requirements_v1.1.md) DEP-01~08·MNU-01~06, [ADR-0016](../../design/0016-image-copy-save-direct-menu.md)

## 목적과 범위

현재 결과는 [관리자 설치 후속](../../delivery/image-admin-install-20260927.md)을 따른다. 관리자 등록·정리, 진단 MSI의 SYSTEM 준비·프로비저닝·정리, 별도 비상승 사용자 등록을 통과했다. 최초 비상승 시험의 목적·오류·실행 증거는 아래에 보존한다.

사용자는 별도 서명 없는 MSI 패키징을 결정했다. MSI 자체의 무서명 제작과 Windows 11 첫 메뉴에 필요한 package identity 등록은 서로 다른 조건이다. MSI 제작 전에 **인증서·개발자 모드·보안 정책을 변경하지 않고 일반 사용자로 무서명 identity를 등록할 수 있는가**를 확인한다. MSI 선택은 사용자 결정이며, 아래 sparse 무서명 경로는 아직 채택하거나 배포 가능하다고 판정하지 않은 시험 후보다.

기존 full MSIX의 신뢰 오류 0x800B0109와 [당시 기록](../../delivery/image-copy-save-signing-20260927.md)은 보존한다. 이번 시험은 원본 패키지·인증서·외부 payload를 변경하지 않는다.

## 공식 계약과 현재 판단

| 항목 | 공식 근거와 적용 |
|---|---|
| 첫 메뉴 | native IExplorerCommand를 앱 identity에 연결한다. COM DLL과 windows.fileExplorerContextMenus를 manifest에 선언하며 sparse package도 같은 구조를 쓸 수 있다. GetState/ECS_HIDDEN으로 숨길 수 있다. [Explorer 공식 문서][1] |
| MSI와 identity | Windows build 19041 이상은 외부 설치 경로에 identity package를 연결할 수 있다. 공식 최종 사용자 설치 안내는 신뢰된 인증서로 서명한 identity package를 요구한다. MSI가 이 요건을 없애지는 않는다. [외부 위치 패키징][2] |
| unsigned 예외 | Windows 11에서 특수 Publisher OID와 AllowUnsigned가 제공된다. 공식 문서는 빠른 시험용으로 설명하며 광범위 배포에 쓰지 말라고 한다. 실행 콘텐츠는 관리자 설치가 필요하고 비실행 콘텐츠만 일반 사용자 예외가 있다. [Unsigned MSIX][3] |
| hosted app | unsigned hosted app은 자체 Executable·EntryPoint·TrustLevel 대신 HostId를 쓰고, 기존 identity를 가진 host가 필요하다. 현재 독립 helper·COM DLL 설계의 확정 대안이 아니다. [Hosted apps][4] |
| API 조합 | Add-AppxPackage의 AddSet에는 ExternalLocation·AllowUnsigned가 함께 있다. RegisterSet에는 AllowUnsigned가 없으므로 loose manifest 등록으로 대체하지 않는다. [PowerShell API][5] |

manifest-only sparse 파일에 EXE가 물리적으로 없더라도 외부 실행 파일의 활성화 선언은 별도로 판정된다. 아래 실제 시험에서 Windows는 이 후보의 실행 가능한 활성화를 이유로 일반 사용자 무서명 등록을 거절했다. 따라서 확인한 후보는 일반 사용자 설치 요구를 충족하지 못한다. 모든 OS·다른 설계의 불가능성을 증명한 결과로 확대하지 않는다.

## 시험 입력·출력과 실행

스크립트는 tools/ImageCopySave/installer/probe-unsigned-identity.ps1이다. 최신 build-package.ps1이 만든 **staging 디렉터리**를 명시적으로 전달한다. Windows 11 x64, Windows PowerShell 5.1 x64, 상승하지 않은 사용자 세션에서 실행한다.

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ImageCopySave/installer/probe-unsigned-identity.ps1 -ExternalLocation "<현재 작업 트리 artifacts 아래 staging 절대 경로>" -MakeAppx "<기존 SDK x64 MakeAppx.exe 절대 경로>"
```

- Name은 ImageCopySave.UnsignedSparseProbe, Version은 0.1.1.0, Publisher는 CN=ImageCopySave.UnsignedSparseProbe, OID.2.25.311729368913984317654407730594956997722=1로 고정한다.
- 매번 artifacts/image-copy-save/unsigned-identity-probe 아래 새 실행 폴더를 만든다. 입력·출력은 해당 작업 트리 artifacts 내부로 제한하고 재분석 지점은 거절한다. 파일·폴더를 삭제하지 않는다.
- 외부 helper·DLL·런타임·로고의 존재와 해시를 기록한다. payload는 수정하지 않고, 새 identity MSIX에는 manifest와 패키지 메타데이터만 넣는다.
- 두 기존 Shell CLSID, Directory\Background와 파일 선택의 verb, AppListEntry=none을 유지한다. AllowExternalContent=true, RuntimeBehavior=win32App과 필요한 Win32 capabilities를 선언한다.
- 공식 sparse 제작 안내에 따라 MakeAppx pack /nv를 사용한다. 외부 파일 참조의 빌드 검증 옵션이며 OS 등록 검증이나 보안 정책을 끄지 않는다. 실제 등록은 Windows가 판정한다. [제작 절차][2]
- result.json과 가능한 deployment event는 해당 실행 폴더에만 기록한다. 실제 HRESULT·native error·상승 여부·등록·제거 결과를 남긴다. securityChanged=false는 시험 코드가 보안 설정을 변경하지 않았다는 의미이며 외부 주체의 동시 변경까지 감시한다는 뜻은 아니다.

## 동시 실행·제거와 복구

현재 사용자에게 ImageCopySave* 패키지나 두 CLSID의 일반 COM 등록이 하나라도 있으면 중단한다. 세션 mutex로 같은 probe의 동시 실행을 막고 등록 직전 다시 확인한다. 일반 사용자 권한으로 다른 사용자의 등록을 전수 검사하지 않으며 판정 범위도 현재 사용자다.

등록 전에 Windows [PackageFullNameFromId API][6]로 예상 PackageFullName을 계산한다. 호출 성공만으로 통과하지 않고 정확한 identity·publisher·version·architecture·상태를 확인한다. finally에서는 **이번 호출이 등록을 시도했고 예상 PackageFullName과 identity 필드가 모두 일치하는 패키지 하나만** 제거한다. 그 후 현재 사용자의 ImageCopySave 등록이 없는지 확인한다. Explorer를 종료·재시작하지 않는다.

강제 종료·전원 차단에서는 finally 실행을 보장하지 않는다. 다음 실행은 잔여 등록을 자동 인수·삭제하지 않고 사전 검사에서 중단한다. 이때 실행 기록의 예상 PackageFullName과 실제 등록을 대조해 해당 시험 identity만 별도로 복구한다. 업무 폴더·원본 그림·클립보드는 시험 대상이 아니다.

## 검증과 판정

2026-09-27, Windows 11 23H2 x64 / **22631.6199**의 상승하지 않은 현재 사용자 세션에서 최신 package staging을 외부 경로로 지정해 실제 실행했다.

| 수행 단계 | 실제 결과 |
|---|---|
| 기존 제품·probe 등록과 COM 충돌 확인 | PASS. 시험 전 해당 등록 없음 |
| unsigned sparse 생성·archive 확인 | PASS. 2,136 bytes, 서명·실행 파일 없는 identity MSIX |
| 현재 사용자 Add-AppxPackage -AllowUnsigned -ExternalLocation | **BLOCKED / 0x80073D2B**. Windows가 unsigned package의 실행 가능한 활성화를 거절 |
| 실패 후 정리와 재조회 | PASS. 제거할 probe 등록이 없었으며 ImageCopySave 잔여 등록 0개 확인 |
| 보안·신뢰 설정 변경 | 없음. securityChanged=false, elevated=false |
| Explorer G0·MSI 설치 수명주기·배포 | NOT RUN. 등록 선행 조건이 성립하지 않음 |

배포 오류의 내부 AppxException HRESULT는 **0x80073D2B**다. 바깥쪽 .NET 예외의 0x80131500과 구분한다. OS 메시지는 “서명되지 않은 패키지에 실행 가능한 활성화를 포함할 수 없기 때문에” 설치할 수 없다고 명시했다. 이 결과로 **R01의 현재 무서명 sparse 후보는 BLOCKED**, 등록 의존 R02·R04 설치 부분·R06 게시 작업은 NOT RUN이다. 독립 이미지 엔진의 현재 세션 시험과 T01·T05 작업은 이 차단과 별도로 진행할 수 있다.

원본 결과·MakeAppx 로그·배포 event는 로컬 artifacts/image-copy-save/unsigned-identity-probe/20260927T001700658Z-20f31ff8a8ed435997d40649509f80cd/result.json 및 같은 폴더에 보존한다. 패키지 SHA-256은 29E812EC824FF42F887F361BBD7AA5B7D0F375D0D972539B8D9873B524BE5ED1이다. 정확한 시험 identity의 예상 PackageFullName은 ImageCopySave.UnsignedSparseProbe_0.1.1.0_x64__bys59z1khays2였다.

| 실제 결과 | 판정 |
|---|---|
| 등록 PASS + 정리 PASS | 종료 코드 0. 이 PC의 일반 사용자 임시 등록만 입증. COM·Explorer G0·배포 지원은 별도 검증 |
| OS 등록 거절 + 정리 PASS | 종료 코드 2, BLOCKED. HRESULT·event로 후보의 일반 사용자 경로 판정. 상승·신뢰 설정 변경 없이 기록 |
| 준비·빌드·identity 검증·정리 실패 | 종료 코드 1, FAIL. 구체 단계를 확인하며 제품 MSI 설치 실패와 구분 |

시험 스크립트의 구문 분석은 오류 0이었다. MSI는 제작하지 않았고 관리자 재시도·인증서/신뢰 설정 변경·서명 대체·레거시 메뉴 대체를 하지 않았다. 일반 사용자와 무서명 조건을 유지한 현재 후보의 차단을 기록하며, 미실행 Explorer·설치 수명주기 항목을 자동시험 결과로 통과 처리하지 않는다. 로컬 진단·계정 경로를 공개 사이트에 싣지 않고 평가 결과와 공개·상용 배포 승인을 구분한다.

[1]: https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer
[2]: https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps
[3]: https://learn.microsoft.com/en-us/windows/msix/package/unsigned-package
[4]: https://learn.microsoft.com/en-us/windows/uwp/launch-resume/hosted-apps
[5]: https://learn.microsoft.com/en-us/powershell/module/appx/add-appxpackage?view=windowsserver2025-ps
[6]: https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-packagefullnamefromid
