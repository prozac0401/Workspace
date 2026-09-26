# 그림 복사·저장 · G0 메뉴 구현성 검증

도구 ID: ImageCopySave  
기록 버전: 0.6 · 2026-09-27  
기준: [ImageCopySave-REQ-1.1](ImageCopySave_Requirements_v1.1.md)  
기록 상태: 검토 · G0 **BLOCKED** · Windows 11 탐색기 실기 **NOT RUN**  
책임: 도구 개발·검증 담당  
적용 정책: [추가 도구 개발 기준](../../policies/tools.md), [정책 문서 작성 규칙](../../policies/documentation.md)  
관련 결정: [ADR-0016](../../design/0016-image-copy-save-direct-menu.md) · 과거 [ADR-0015](../../design/0015-image-copy-save-g0.md)

## 현재 판정 — v1.1

2026-09-27 기존 허용 인증서로 사본 서명·SignTool 검증은 PASS였으나, 일반 사용자 MSIX 설치는 `0x800B0109`로 거절됐다. 실패 후 현재 사용자 패키지 등록은 0개다. 신뢰 저장소를 변경하지 않았으며 실제 메뉴·수명주기는 계속 미실행이다. [실행 근거](../../delivery/image-copy-save-signing-20260927.md).

사용자가 기본 ‘새로 만들기’ 내부 위치 조건을 해제했다. 저장 명령은 실제 로컬 폴더 배경의 Windows 11 첫 우클릭 메뉴에 별도 명령으로 제공하는 후보를 구현했다. 이미지가 없을 때 완전히 숨김, 상주 감시 없음, 레거시 메뉴에만 두지 않음, 설치기가 등록을 담당한다는 나머지 조건은 유지한다. [v1.0 원문](ImageCopySave_Requirements_v1.0.md)은 변경하지 않았다.

**기존 ShellNew 연결 방식 미확정은 개정 요구의 차단 사유에서 제외했다. 현재는 native IExplorerCommand와 full MSIX 후보를 실제 Windows 11에 신뢰되는 사용자별 패키지로 설치하고 메뉴 동작을 입증하지 못해 G0를 통과시키지 않는다.** DLL 직접 호출이나 MSIX 생성은 실제 메뉴 검증을 대체하지 않는다. M2 사용자 동작·결과 선택·오류 안내와 M3 수명주기도 완료 전이다.

## 구현한 후보와 검증 범위

- C++ x64 DLL의 Save/Copy 명령은 IExplorerCommand와 IObjectWithSite를 구현한다. Save는 호출한 보기의 IFolderView → IPersistFolder2 → 폴더 PIDL에서 대상을 확인한다. 활성 창이나 선택한 폴더로 대신 추정하지 않는다.
- GetState의 빠른 호출에서는 간단한 제외만 판정하고 추가 작업이 필요하면 E_PENDING을 반환한다. 느린 호출에서 경로·형식 메타데이터를 확인한다. Save는 PNG/DIBV5/DIB/BITMAP 형식이 없거나 조회가 불확실하면 ECS_HIDDEN을 유지한다. 픽셀 디코딩·파일 생성·클립보드 데이터 읽기는 상태 조회에 없다.
- 실제 고정 로컬 볼륨의 일반 경로만 취급한다. UNC, SUBST, 가상 문맥, reparse/recall 경로와 예약 장치 이름은 숨긴다. 이 보수적인 경계가 실제 Windows 11 문맥에서 맞는지 실기로 확인해야 한다.
- Invoke는 호출 시점 sequence와 원래 보기를 고정하고 동일 패키지 루트의 helper를 실행한다. 현재 station/desktop을 명시하며 탐색기에서 이미지 처리 완료를 기다리지 않는다. 잠금 안에서 기준값을 확인하고 결과 통신·같은 보기 선택·비모달 진행/취소·오류 UI를 연결했다. [ADR-0017](../../design/0017-image-copy-save-invocation.md)의 구현 계약이며 실제 Explorer 실기를 통과했다는 뜻은 아니다.
- full MSIX manifest는 native COM STA surrogate와 Directory\Background 저장 / 단일 파일 복사 등록을 선언한다. 앱 ID와 게시자 이름은 평가용 제안이며 최종 서명·신뢰 조건은 미결정이다.

공식 근거: [패키지의 Explorer 명령 통합](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer), [GetState 빠른/느린 호출 계약](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-getstate), [패키지 manifest 구성](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-manual-conversion). 확인일: 2026-09-25. 이 근거는 구현 후보의 API 계약이며 이 제품의 실제 표시 성공 증거가 아니다.

| 검증 | 현재 상태·증거 범위 |
|---|---|
| v1.1 요구·ADR·manifest·PowerShell 구문 | 작성·정적 확인 |
| native DLL 로컬 빌드·순수 정책/직접 COM 66개 | 최신 로컬66개 PASS / 0 FAIL. clipboard/Invoke/OS 등록·Explorer 미실행 |
| unsigned full MSIX pack/unpack·구조 검사 | 최신0.1.1 로컬 PASS, 입력408개 해시 일치. 서명·설치 성공을 의미하지 않음 |
| 기존 인증서 서명·SignTool 검증 | PASS, 현재 PC의 실제 MSIX 설치 허용을 보장하지 않음 |
| 일반 사용자 최초 설치 | FAIL / 0x800B0109, 실패 후 등록0개 |
| Windows 11 메뉴·Invoke·재설치/업데이트/제거 | BLOCKED / NOT RUN |

이전 후보는 도구 누락으로 CI에서 빌드했으나, 이번에는 Microsoft 고정 payload와 SDK NuGet 서명을 검증해 저장소의 `.tools`에 추출하고 로컬에서 빌드했다. 새 Git worktree·원격 CI는 사용하지 않았다. 시스템 개발 도구 설치나 인증서 신뢰 변경은 하지 않았다. 최신 서명·설치 상태와 산출물은 [로컬 인계 기록](../../delivery/image-copy-save-local-20260925.md)에 별도로 기록한다. 제품의 실제 메뉴 PASS와 빌드 PASS는 구분한다.

## 개정 G0의 남은 실기

신뢰되는 서명의 패키지와 격리된 Windows 11 일반 사용자 시험 환경이 필요하다. unsigned 파일을 관리자 우회 설치하거나 사용자에게 DLL 수동 등록을 요구하는 방식은 제품 설치 검증으로 인정하지 않는다. 재부팅 자체는 서명·신뢰·미완성 통합 동작을 해결하지 않는다.

| 순서 | 확인과 보존할 증거 | 현재 상태 | 관련 수용시험 |
|---|---|---|---|
| 1 | 실제 폴더 배경의 첫 우클릭 경로에서 저장 명령 접근, 더 많은 옵션 전용 아님 | NOT RUN | AT-08, AT-09 |
| 2 | 이미지→텍스트→빈 상태→이미지 20회, 새 메뉴마다 표시·완전 숨김 | NOT RUN | AT-01~07 |
| 3 | 회색·유령·빈 앱 메뉴·불필요한 구분선 부재 | NOT RUN | AT-07, AT-08 |
| 4 | 메뉴 진입의 형식 조회만 수행, 디코딩·파일 생성·클립보드 변경 없음 | NOT RUN | AT-10 |
| 5 | 두 창·두 탭·지원 밖 문맥의 정확한 대상, 감시/반복 등록/Explorer 재시작 없음 | NOT RUN | AT-11, AT-12, AT-42 |
| 6 | 일반 사용자 설치·재설치·업데이트·제거, PNG 연결·타사 메뉴 보존 | NOT RUN | AT-40, AT-41, AT-44 |

구현/시험 명령은 [소스 안내](../../../tools/ImageCopySave/README.md), [패키징·설치 현황](../../../tools/ImageCopySave/installer/README.md), [수용시험 기록](../../../tools/ImageCopySave/TEST_RESULTS.md)에 연결한다.

## v1.0 조사 이력 — 아래 판정과 미승인 표시는 당시 상태

아래는 2026-09-24의 기본 New 내부 동적 표시 조사 기록이다. 위치 변경안은 이후 사용자 승인과 v1.1로 채택되었으므로 아래의 “미승인”, “새 후보 없음”, “최소 확장 미구현”은 현재 후보의 상태를 뜻하지 않는다.

### 판정

**기본 ‘새로 만들기’ 내부에서 클립보드 이미지 유무에 따라 저장 명령 하나만 표시·숨김하는 구현은 아직 입증하지 못했다. G0는 BLOCKED이며 제품 배포 가능 판정은 보류한다.** 일반 IExplorerCommand의 ECS_HIDDEN 지원을 이 위치의 성공 증거로 사용하지 않는다.

문서에 방법이 없다는 사실만으로 Windows에서 절대 불가능하다고 결론 내리지 않는다. 이번 기록은 공식 계약 검토와 로컬 읽기 전용 관찰이며, 시험용 확장을 등록해 실패를 재현한 기록이 아니다. 동적 ShellNew 연결 방법이 확인되지 않아 해당 최소 확장을 구현·설치하지 않았고, 표시·숨김 화면 증거도 없다. 따라서 실제 메뉴 시험을 FAIL 또는 PASS라고 기록하지 않는다.

원명세 3.3에 따라 M1 독립 이미지 엔진·자동 시험은 진행할 수 있다. M2의 실제 Shell 연결과 M3의 제품 설치·제거·출시 판정은 G0 증거가 확보될 때까지 차단한다.

### 실행한 확인과 환경

| 확인 | 실제 결과 | 증거의 범위 |
|---|---|---|
| 원문·정책 검토 | 첨부 명세 v1.0, AGENTS.md, tools.md, documentation.md, 문서 양식 확인 | 요구와 문서 구조 확인 |
| OS 읽기 전용 조회 | Windows Professional, 23H2, x64, 빌드 22631.6199 | 이 빌드의 지원 인증 아님 |
| Explorer 파일·프로세스 조회 | 파일 버전 10.0.22621.4599, explorer 프로세스 1개 | 메뉴를 조작하거나 관찰한 증거 아님 |
| 기본 New 등록 읽기 | HKCR/Directory/Background/shellex/ContextMenuHandlers/New 기본값 {D969A300-E7FF-11d0-A93B-00A0C90F2719} | 기존 OS 등록 존재만 확인 |
| 공식 문서·소스 확인 | 아래 Microsoft 문서·스키마·고정 커밋의 샘플 및 SDK 헤더 확인 | API 계약·설계 후보 확인, 실제 메뉴 실행 증거 아님 |
| 확장 등록·실행·캡처 | NOT RUN | 시험용 Shell 확장 미등록, 화면 증거 없음 |
| 일반 사용자 설치·재설치·제거 | NOT RUN | 패키지·서명·최종 등록 방식 미확정 |

조회에 Windows PowerShell 5.1.22621.6133을 사용했다. 레지스트리·인증서·패키지·클립보드·기본 연결을 바꾸지 않았으며 Explorer를 종료하거나 재시작하지 않았다. 형식별 ShellNew 키를 추가로 조사하는 두 번째 읽기 전용 조회는 실행 도구 제한시간에 걸려 결과를 채택하지 않았다. 이 실패 역시 메뉴 실패 증거가 아니다.

현재 제공된 브라우저 자동화 도구는 네이티브 앱 조작이 비활성인 세션이다. 그러나 이를 모든 Windows API 접근 불가로 해석하지 않는다. 2026-09-24 후속 읽기 전용 probe stdout에서는 세션1의 Explorer1개, WinSta0\Default, UOI_IO=True, DESKTOP_READOBJECTS 권한의 OpenInputDesktop 성공을 확인했다. 입력·화면 캡처·UIA 동작·클립보드 API는 실행하지 않았으며 별도 JSON/정확한 UTC 시각은 보존하지 않았다. OS/Explorer 버전은 앞선 M0 조회값이고 재확인 시도는 실행 전 EPERM으로 막혔다. 이 관측은 격리 시험 환경 확보나 G0 메뉴 실기 성공의 증거가 아니다.

다음 읽기 전용 명령으로 환경을 다시 확인할 수 있다. 이 명령은 제품 설치 절차가 아니다.

```powershell
$os = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$os | Select-Object EditionID, DisplayVersion, CurrentBuild, UBR
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
(Get-Item "$env:WINDIR\explorer.exe").VersionInfo.FileVersion
(Get-Item "Registry::HKEY_CLASSES_ROOT\Directory\Background\shellex\ContextMenuHandlers\New").GetValue("")
```

### 검토한 방식과 확인된 차이

| 후보 | 공식 계약에서 확인한 내용 | 이번 판정 |
|---|---|---|
| ShellNew | Command, Data, FileName, NullFile로 파일 생성 방식을 지정한다. 검토한 절에는 클립보드에 따른 항목별 상태 콜백이 없다. | 문서 검토 완료. 동적 표시 실기는 NOT RUN. 정적 템플릿은 요구를 충족하지 못함 |
| IExplorerCommand::GetState | 해당 일반 명령의 ECS_HIDDEN 상태를 표현할 수 있다. 느린 상태 조회의 별도 호출 계약이 있다. | 일반 명령의 가능성과 ShellNew 내부 위치는 분리. 위치 검증 대체 불가 |
| 패키지의 windows.fileExplorerContextMenus | native COM 클래스와 파일·폴더·배경 문맥 연결 및 Windows 11 메뉴 통합을 설명한다. | 배경 등록만으로 기본 New 안에 들어간다고 추정하지 않음 |
| desktop5:Verb | 문서화된 속성은 Id와 Clsid이며 기본 New의 부모 항목 지정 속성이 제시되지 않는다. | 조사한 스키마만으로 요청 위치 구현을 입증할 수 없음 |
| INewMenuClient::IncludeItems | 보기에서 비폴더/폴더 범주를 필터링하는 플래그를 반환한다. | 특정 앱 명령 한 개의 클립보드 조건 필터로 해석할 근거 없음 |
| 패키징과 외부 위치(sparse package) | 사용자별 PackageManager 등록·제거와 신뢰된 서명 패키지를 설명한다. | 설치 경로 후보. 조직 신뢰 조건·일반 사용자 성공은 미검증 |

근거: [ShellNew와 cascading menu](https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers#extending-a-new-submenu), [GetState](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-getstate), [패키지 Explorer 명령](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer), [desktop5:Verb](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-desktop5-verb), [IncludeItems](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-inewmenuclient-includeitems), [외부 위치 패키지 등록](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps). 확인일: 2026-09-24.

IExplorerCommand::EnumSubCommands로 앱이 소유하는 하위 메뉴를 만드는 것과 Windows 기본 ‘새로 만들기’에 항목을 넣는 것은 같은 증거가 아니다. 앱 하위 메뉴 이름을 ‘새로 만들기’로 정하거나 기존 New COM 등록을 교체하는 방식은 사용하지 않는다. Windows 11의 일반 메뉴 확장은 app identity와 IExplorerCommand가 안내된 경로이며, 기존 메뉴만 제공하는 방식은 첫 우클릭 접근성의 합격 증거가 아니다. [Windows 11 메뉴 설계](https://blogs.windows.com/windowsdeveloper/2021/07/19/extending-the-context-menu-and-share-dialog-in-windows-11/)

### SDK·공식 샘플 추가 검토

2026-09-24에 Microsoft 공식 샘플 소스와 공개 SDK 헤더를 읽기 전용으로 재검토했다. 아래 소스 링크는 조사한 커밋에 고정되어 있다. 새 등록·설치·클립보드 조작·탐색기 UI 시험은 실행하지 않았다.

| 추가 후보·근거 | 소스에서 확인한 계약 | G0에 남는 간극 |
|---|---|---|
| IExplorerCommandState와 CommandStateHandler | 공식 샘플의 RegisterExplorerCommandStateHandler는 일반 ProgID의 Shell\Verb 키에 CommandStateHandler를 등록한다. [등록 소스](https://github.com/microsoft/Windows-classic-samples/blob/434f6002bdf9cf9829406c3ff2b33387982d6168/Samples/Win7Samples/winui/shell/appshellintegration/ExplorerCommandVerb/RegisterExtension.cpp#L352), [상태 처리 샘플](https://github.com/microsoft/Windows-classic-samples/blob/434f6002bdf9cf9829406c3ff2b33387982d6168/Samples/Win7Samples/winui/shell/appshellintegration/ExplorerCommandVerb/ExplorerCommandStateHandler.cpp) | 일반 verb의 동적 상태 등록이며 기본 ShellNew 항목에 연결하는 예제가 아니다. 별도 인터페이스라는 이유로 ShellNew 지원을 추정할 수 없음 |
| INewMenuClient와 SDK 선언 | IncludeItems는 NMCII_FLAGS 출력만 받으며 특정 항목 식별자를 입력받지 않는다. 플래그는 NONE, ITEMS, FOLDERS이다. SelectAndEditItem은 생성된 항목의 선택·편집을 다룬다. [고정 SDK 헤더](https://github.com/microsoft/win32metadata/blob/5c5efbc01d4c87f6830ec304d42777991d533154/generation/WinSDK/RecompiledIdlHeaders/um/ShObjIdl_core.h#L26777) | 범주 제어와 생성 후 처리가 명령 하나의 표시·숨김 콜백 계약을 제공하지 않음 |
| AppliesTo와 패키지 스키마 | AppliesTo는 대상 항목의 빠른 속성을 AQS로 평가하는 일반 verb 조건이다. 검토한 desktop5:Verb 및 uap:FileTypeAssociation 스키마에도 기본 New 항목별 상태 콜백 연결은 제시되지 않는다. [AppliesTo](https://learn.microsoft.com/en-us/windows/win32/shell/context-menu-handlers#getting-dynamic-behavior-for-static-verbs-by-using-advanced-query-syntax), [파일 형식 연결 스키마](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap-filetypeassociation) | 클립보드 이미지 유무를 평가하여 기본 New 항목 하나를 제외하는 경로를 입증하지 못함 |

[IExplorerCommandState 문서](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-iexplorercommandstate)의 GetState도 일반 명령 상태 계약이다. SDK에 NewMenu CLSID 또는 INewMenuClient가 존재한다는 사실 자체는 타사 명령의 동적 ShellNew 연결을 보장하지 않는다.

**아직 확인하지 못한 핵심 계약은 “기본 New가 열릴 때마다 앱의 항목별 상태 콜백을 호출하도록 등록하고, 그 제외 상태를 Windows 11 첫 메뉴의 기본 New 내부에 적용하는 공개 연결 방식”이다.** 일반 ECS_HIDDEN 호출 성공이나 앱이 만든 하위 메뉴는 이 간극을 해결하지 않는다. 이번에 검토한 문서·소스 범위에서는 해당 계약을 갖춘 새 구현 후보를 찾지 못했으며, 이것을 모든 Windows 구현에서의 불가능성 증명으로 확대하지 않는다. 근거 있는 최소 확장 후보가 확인되기 전까지 G0는 **BLOCKED**, 실제 메뉴 시험은 **NOT RUN**을 유지한다.

### G0 재개 시 필요한 실제 시험

먼저 공식 API·등록 계약을 근거로 요청 위치를 대상으로 하는 최소 확장을 제시한다. 격리된 Windows 11 x64 시험 환경에서 설치 전 기본 메뉴·연결·등록 상태를 기록하고, 설치기가 등록을 담당하게 한다. 일반 사용자에게 수동 DLL 등록·개발자 모드·레지스트리 편집을 요구하는 절차는 합격할 수 없다.

| 순서 | 실기 확인과 보존할 증거 | 현재 상태 | 관련 수용시험 |
|---|---|---|---|
| 1 | 기본 New 내부 위치와 첫 우클릭 경로의 연속 화면 | NOT RUN | AT-08, AT-09 |
| 2 | 이미지→텍스트→빈 상태→이미지 20회, 매번 새 메뉴의 표시·완전 숨김 | NOT RUN | AT-01~07 |
| 3 | 회색·유령·빈 앱 메뉴·불필요한 구분선 부재 | NOT RUN | AT-07, AT-08 |
| 4 | 메뉴 진입은 형식 확인만 수행하고 디코딩·파일 생성·클립보드 변경 없음 | NOT RUN | AT-10 |
| 5 | 상태 변경마다 등록 변경·감시 프로세스·Explorer 재시작 없음 | NOT RUN | AT-07, AT-42 |
| 6 | 일반 사용자 설치·재설치·업데이트·제거 및 PNG·타사 메뉴 보존 | NOT RUN | AT-40, AT-41, AT-44 |

화면 자료에는 빌드·시각·시험 번호를 대응시키고 업무 파일·개인 클립보드 내용은 포함하지 않는다. 일반 메뉴용 GetState 단위시험, 인위적으로 만든 HMENU, 직접 COM 메서드 호출은 이 표의 실기 성공을 대신하지 않는다. 서명·신뢰·조직 정책이 충족되지 않으면 조건을 그대로 기록하고 설정을 완화해 통과시키지 않는다.

### 변경안 — 미승인

| 변경안 | 바뀌는 요구 | 상태 |
|---|---|---|
| 요청 위치를 유지하고 추가 조사·실기를 계속한다 | 요구 변경 없음. 문서화된 연결과 실제 증거 확보 필요 | 현재 진행 경계 |
| 실제 폴더 배경의 별도 Windows 11 명령으로 저장 위치를 옮긴다 | MNU-01, AT-08. 완전 숨김·첫 메뉴·무상주 조건은 유지 | UNAPPROVED. 구현·등록·완료 처리하지 않음 |

고정 ShellNew 템플릿, 빈 PNG 선생성, 항상 보이는 오류 안내 명령, 회색 항목, 감시 프로그램, 반복 등록 수정, 비공개 후킹은 변경안으로 채택하지 않는다. 메뉴 위치 변경은 사용자가 합의한 요구 변경이 있을 때만 별도 명세 개정으로 처리하며, 본 기록 작성으로 승인이 발생하지 않는다.

### 변경 이력

- 2026-09-24 · 0.1: 원명세 G0의 첫 증거 검토. 읽기 전용 환경 관찰, 공식 계약 비교, 미실행 시험과 변경안 기록.
- 2026-09-24 · 0.2: 공식 샘플·SDK 고정 소스로 일반 verb 상태 처리와 기본 New 연결을 구분하고, 미확인 공개 계약을 명시. G0 BLOCKED·탐색기 실기 NOT RUN 유지.

- 2026-09-24 · 0.3: 로컬 desktop 읽기 전용 접근 성공과 네이티브 UI 실기 미실행을 구분. 새로운 동적 ShellNew 후보는 없으며 G0 판정 유지.

- 2026-09-25 · 0.4: 사용자 승인 v1.1 위치 변경과 native/full-MSIX 후보를 현재 판정으로 분리. 실제 G0 통과 여부는 보류.
