# 그림 복사·저장 · Codex Windows 자동시험 기록

상태: 엔진77개 과거 PASS, native63개·unsigned 패키지 검사 PASS · 2026-09-25(KST) · 임시 원격 자원 정리 완료 · G0 BLOCKED 유지

사용자는 별도 원격 PC를 조작하지 않았다. Codex가 승인받은 공개 저장소 시험 브랜치에서 GitHub Actions를 실행하고 결과를 회수한 뒤 원격 시험 자료를 삭제했다. 로컬 Codex 호스트의 사용자 클립보드는 사용하지 않았다.

## 첫 단계: 엔진 결과

이 단계의 최종 **60 PASS / 0 FAIL / 0 NOT RUN**이다. 기존에 막혔던 실제 clipboard9개가 모두 포함된다. Windows Server 2025 x64, 관리자, 세션2, SDK10.0.401·런타임10.0.12 환경이다. 정확한 runner 이미지 이름은 windows-2025-vs2026, 버전20260922.246.2로 로그에 기록됐다.

| 실행 | 결과 | 후속 조치 |
|---|---|---|
| 36001597145 | 51 PASS / 9 NOT RUN | 새 station 생성은 성공. 초기화된 STA 스레드의 desktop 전환 오류170 수정 |
| 36002216827 | 58 PASS / 2 FAIL | 모든 clipboard 시험 진입. native-formats·지연 렌더링 실패 수정 |
| 36002778286 | 60 PASS | 전체 통과 확인 후 원격 자원 정리 |

[44개 수용시험과 상세 결과](../../../tools/ImageCopySave/TEST_RESULTS.md), [최종 JSON](../../../artifacts/image-copy-save/ci-remote-36002778286/results.json)을 참조한다. 첫51개와 실제 clipboard9개 모두 Windows에서 실행했다. 모의 API의 결과를 native 결과로 계산하지 않았다.

## 해결한 문제

1. 현재 호스트의 일반 사용자 실행은 station 이름 제한(오류5), OS 자동 이름의 기존 객체 충돌(오류183)로 막혔다. 이 제한을 해제하거나 기존 공간을 재사용하지 않았다.
2. Windows CI의 관리자 환경에서는 새 station 생성이 성공했다. 시험은 초기화된 STA 스레드에 SetThreadDesktop을 호출해 오류170이 발생했다. 이제 setup 프로세스가 격리 공간을 만들고, STARTUPINFO.lpDesktop으로 새 시험 프로세스를 그곳에서 시작한다. 특정 COM 창의 존재가 원인인지는 직접 관측하지 않았으며, 초기화된 스레드 이동을 없앤 수정으로 기술한다.
3. 이미지 읽기에서 자동 합성된 DIBV5를 원래 CF_BITMAP보다 우선하던 경로를 없앴다. PNG를 우선하고 bitmap 계열은 원래 게시 형식부터 열거하는 Windows 순서를 따른다. 생산자가 낮은 품질의 독립 표현을 먼저 게시하면 그 순서를 따른다는 제한이 있다.
4. 지연 렌더링 직후 sequence가 반드시 한 번 더 바뀐다는 시험 가정을 제거했다. 렌더러 호출·정확한 snapshot·metadata 조회 시 비렌더링은 검증한다. 명시적인 새 복사로 sequence를 변경한 뒤 오래된 Copy 거부·새 내용 보존·snapshot 독립성을 확인한다.

모든 case와 보조 프로세스는 private station의 이름, 비대화형 상태, Test desktop을 확인한 후만 clipboard에 접근한다. 기존 clipboard로의 대체 경로는 없다. 생성은 CWF_CREATE_ONLY로 새 객체만 허용한다. 관리자 권한은 CI runner가 제공하며 제품이나 시험 코드가 UAC 승격을 요청하지 않는다.

## 첫 단계의 원격 정리

| 항목 | 처리 및 확인 |
|---|---|
| 저장소 | prozac0401/Workspace |
| 시험 브랜치 | codex/image-copy-save-native-tests 삭제: DELETE204, 조회404 |
| 실행 기록과 로그 | 위3개 run 삭제: 각각 DELETE204, 조회404 |
| 시험 artifact | 각 run의 결과 artifact3개 삭제: 각각 DELETE204, 조회404 |
| workflow 등록 | 최종 조회404. 활성 workflow를 main에 추가하지 않음 |
| main | 시작 SHA와 동일: 1aede443e88786f17a4fa2c6f3138d113068e83f |
| 로컬 보존 | 소스, JSON, 로그, 실행 메타데이터, SHA-256 manifest, 삭제 확인 기록 |

[정리 증거](../../../artifacts/image-copy-save/ci-remote-session.json)에 상태 코드를 보존했다. 공개된 Git 객체와 제삼자 복제본까지 완전히 소거했다고 보장하지 않는다. PR·main 병합·Release·Pages 배포는 수행하지 않았다. 기존 작업의 소스와 로컬 검증 기록은 파기 대상에서 제외하고 보존했다.

## 후속 단계: 실제 제품 helper

최종 **68 PASS / 0 FAIL / 0 NOT RUN**이다. 총17개 격리 시험 중8개가 실제 ImageCopySave.Helper.exe를 실행한다. 환경은 앞 단계와 같은 Windows Server2025 x64 관리자이며, 결과 시각은2026-09-24T13:57:05.9044389+00:00이다.

| 실행 | 결과 | 관측 |
|---|---|---|
| 36007153901 | 67 PASS / 1 FAIL | 병렬 helper 저장 실패, 상세 원인 미수집 |
| 36007926703 | 68 PASS | 오류 코드 수집 추가 후 일시 성공. 원인 해결로 판정하지 않음 |
| 36008525124 | 67 PASS / 1 FAIL | 8회 반복 중2회차에서 clipboard read1418 재현 |
| 36009092514 | 68 PASS | Capture에 고유 HWND 적용 후4개 helper×8회 병렬 저장 및 전체 회귀 통과 |

실제 helper 완전 종료와 원본 이동·삭제 뒤 native Capture/PNG 저장, exact alpha, JPEG 방향, 손상 입력 보존, 빈/텍스트 저장 거절, 현재 이미지B 저장을 검증했다. 내부 취소 event 시험은 public Ctrl+C가 아니다. 멈춘 합성 공급자 시험은 WM_RENDERFORMAT 진입 후 실제 helper의 watchdog 종료, 남은 worker0, 외부 공급자 생존, 무파일을 확인했다. 외부 앱 붙여넣기나 Explorer 응답성 시험으로 확대하지 않는다.

[OpenClipboard](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openclipboard)의 서로 다른 창 간 배제 계약을 적용하여 Capture마다 고유한 message-only HWND로 열고, 스냅샷 바이트를 확보한 뒤 닫는다. EmptyClipboard/SetClipboardData 호출 없이 내용을 유지한다. 관측된 오류는 read1418이며 NULL 핸들의 내부 경쟁 메커니즘은 직접 확인하지 않았다. 부모·worker context 검사와 커밋 후 출력 오류의 불확실성 보고도 보강했다.

[최종 JSON](../../../artifacts/image-copy-save/ci-helper-36009092514/results.json), [별도 세션·정리 증거](../../../artifacts/image-copy-save/ci-helper-session.json), 실행별 로그·SHA-256 manifest를 로컬에 보존했다. 이번4개 run과4개 artifact는 각각 DELETE204/조회404, 시험 브랜치도 DELETE204/조회404이며 workflow는 조회404다. main은 동일 SHA를 유지했다. 기존3개 실행의 증거와 이번4개 실행의 증거를 덮어쓰지 않았다. 공개 Git 객체·제삼자 복제본의 완전 소거까지 보장하지 않는다.

## 추가 단계: 실제 오류·경계·성능

2026-09-24~25(KST)의 최종 **77 PASS / 0 FAIL / 0 NOT RUN**이다. 격리 clipboard21개 중 실제 helper12개를 포함한다. 새9개 시험은 스냅샷 확보 뒤 다른 helper가 복사한 내용 보존, 오래된 copy 거절, 손상 PNG/DIB clipboard, 프로세스 생성 후 내부 취소, 실제 읽기/쓰기 ACL 거부, 전용 VHD 디스크 부족, 실제 크기/픽셀 경계, 4K 엔진 반복 측정이다.

| 실행 | 결과 | 관측 |
|---|---|---|
| 36015489668 | 75 PASS / 2 FAIL / 0 NOT RUN | 시험용 ACL 복원 문자열 비교 실패 |
| 36016335606 | 75 PASS / 2 FAIL / 0 NOT RUN | ACE 동일·실효 권한 복원·AUTO_INHERITED 비트 차이 확인 |
| 36017035795 | 77 PASS / 0 FAIL / 0 NOT RUN | 최종 전체 통과 |

ACL 진단에서 실제 접근 거부는 오류5였고, 복원 후 ACE 순서·바이트와 실제 읽기/쓰기 권한이 동일했다. SDDL 차이는 SE_DACL_AUTO_INHERITED(0x400)의 0→1이었다. [Windows 자동 상속 계약](https://learn.microsoft.com/en-us/windows/win32/secauthz/automatic-propagation-of-inheritable-aces)에 맞춰 이 변화만 허용하고 다른 제어 비트·DACL null/버전·ACE·임시 Deny 제거·실효 접근을 모두 검사하도록 시험 판정을 교정했다. 문자열까지 동일했다고 기록하지 않는다. 제품 엔진과 권한 복원 코드는 변경하지 않았다.

실제 디스크 부족은 명시 opt-in과 GitHub-hosted Windows 관리자 조건을 확인한 뒤 새128MiB VHD에서만 실행했다. 정확한 이미지→디스크→고유 볼륨 ID를 검증하고 기존 파일 보존·불완전 파일0·자체 볼륨 분리를 확인했다. 시스템 볼륨을 채우거나 로컬 디스크로 대체하지 않았다.

oplock break는 발생시킨 PID를 알려주지 않는다. 오래된 copy 거부·새 B/sequence 보존은 확인했지만 취소의 정확한 helper I/O 단계 진입을 증명하지 않았다. 원시 stdout/stderr 비노출은 합성 fixture의 실패 경로 한정이며 전체 로그/네트워크 인증이 아니다. 4K 수치는 합성 gradient/alpha 엔진 저장/읽기 측정으로 메뉴·helper·clipboard·사용자2초 목표를 대신하지 않는다.

[최종 JSON](../../../artifacts/image-copy-save/ci-extended-36017035795/results.json), [실행·삭제 증거](../../../artifacts/image-copy-save/ci-extended-session.json), 실행별 로그·SHA-256 manifest를 로컬 보존했다. 이번3개 run·artifact는 각각 DELETE204/조회404, 브랜치도 DELETE204/조회404, workflow는 조회404이며 main SHA는 그대로다. 이전 두 단계 증거를 덮어쓰지 않았다. 공개 Git 객체나 제삼자 복제본의 완전 소거를 보장하지 않는다.

44개 수용항목은9 PASS(명시한 엔진/helper 범위)/22 BLOCKED/13 NOT RUN이다. AT-19·26·31만 승격했고 G0·Windows 11 일반 사용자·앱 붙여넣기·설치/제거는 미완료다.

## v1.1 native 메뉴 후보 — 2026-09-25

사용자 승인으로 기본 New 내부 위치 조건을 해제하고 실제 폴더 배경의 별도 Windows 11 첫 메뉴 명령을 구현했다. [개정 명세](ImageCopySave_Requirements_v1.1.md)와 [G0 현재 판정](G0_Menu_Feasibility.md)을 기준으로 한다.

| 실행 | 결과 | 범위 |
|---|---|---|
| 36075520486 | native 시험 빌드 FAIL | 매크로 중복 정의 경고를 오류로 처리. 시험·패키징 미실행 |
| 36075794514 | native63 PASS / 0 FAIL, unsigned MSIX 검사 PASS | policy/direct COM만. clipboard·Invoke·등록·설치·Explorer UI 없음 |

최종 컴파일러 MSVC14.51.36231, SDK10.0.26100.0을 사용했다. MSIX는64,309,547bytes이며 입력408개와 해제 파일의 해시가 일치했다. package-result의 signing/installation/explorerG0는 NOT RUN이다. 같은 native 바이너리를 로컬 Windows 11 Pro x64(kernel10.0.22631)에서 직접 실행해 동일63개 PASS를 확인했다. 로컬 컴파일러 헤더/라이브러리는 갖추어지지 않아 빌드는 실행하지 않았다.

[최종 native JSON](../../../artifacts/image-copy-save/ci-shell-36075794514/artifact/native-shell/shell-results.json), [패키지 검사](../../../artifacts/image-copy-save/ci-shell-36075794514/artifact/package-evaluation/package-result.json), [로컬 결과](../../../artifacts/image-copy-save/native-local-results.json), [시험 및 삭제 증거](../../../artifacts/image-copy-save/ci-shell-session.json)를 보존했다. 두 artifact와 두 실행, 임시 브랜치를 DELETE204/GET404로 삭제 확인했고 workflow조회404, main SHA는 불변이다. 공개 Git 객체와 제삼자 복제본까지 소거했다고 보장하지 않는다.

앞선77개 엔진/helper 시험을 이 단계에서 재실행한 것은 아니다. 44개 수용시험 집계도9 PASS/22 BLOCKED/13 NOT RUN을 유지한다. G0 실제 메뉴, 호출 시점에서 helper 시작까지의 시퀀스 기준 전달, 비모달 결과/취소·같은 탭 선택, 신뢰되는 서명과 설치 수명주기가 남아 있다.

[비활성 native CI 템플릿](../../../tools/ImageCopySave/build/windows-shell-ci.yml)은 build-shell.ps1과 build-package.ps1을 실행한다. 엔진77개 템플릿과 별개이며 등록이나 설치 작업을 포함하지 않는다.

## 남은 검증

- 이 결과는 Windows Server 관리자 환경의 엔진 시험이다. Windows 11 일반 사용자 설치·사용(AT-41) 인증이 아니다.
- 초기 helper-exit은 시험용 publisher이고, 후속 product-*는 실제 제품 helper다. 실제 helper 종료 후 native Capture는 통과했으며 그림판·Office 등 외부 앱 붙여넣기는 남아 있다.
- 사용자 승인 v1.1은 폴더 배경의 별도 Windows 11 첫 메뉴를 대상으로 한다. native 후보가 생겼지만 실제 동적 숨김·메뉴 검증 전이므로 G0는 아직 BLOCKED다.
- 멈춘 합성 공급자와 내부 취소 event는 통과했다. 실제 외부 공급 앱, public Ctrl+C·최종 취소 UX, 외부 앱 붙여넣기, 설치·재설치·업데이트·제거는 이 CI로 통과 처리하지 않는다.

## Windows 11 탐색기 자동시험 환경 조사

2026-09-24 읽기 전용 계정 조회에서 현재 저장소는 개인 공개 저장소이며 연결 계정의 조직·조직 소속 목록은 비어 있었다. 사용할 수 있는 조직의 Windows 11 x64 runner는 확인되지 않았다. 결제 상태나 요금제는 추정하지 않는다.

[GitHub 표준 runner 목록](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)의 Windows x64는 Server 환경이고 Windows 11 표준 이미지는 ARM64다. ARM64 실행은 원명세의 x64 제품 시험을 대신하지 않는다. [Larger runner](https://docs.github.com/en/actions/reference/runners/larger-runners)는 Base Windows 11 Desktop x64 후보를 제공하지만 유료 자원이며 별도 계정·권한·예산 확인이 필요하다. 이번 작업에서 계정·요금제·runner를 생성하거나 변경하지 않았다.

Windows 11 이미지가 있다는 사실만으로 탐색기 UI 자동시험이 가능한 것은 아니다. 실제 OS/아키텍처, 일반 사용자 세션, 실행 중인 Explorer, 잠기지 않은 데스크톱, 입력과 화면 캡처를 먼저 검증해야 한다. [Microsoft UI Automation 안내](https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/ui-automation)도 실제 입력에 잠금 해제된 데스크톱을 요구한다. 이후 설치기로 G0 후보를 등록하고 실제 메뉴의 화면·상태 전환을 수집해야 한다. 이 조사는 v1.0 당시 기록이며, 2026-09-25 사용자 승인으로 위치를 변경한 뒤 별도 첫 메뉴의 native/full-MSIX 후보를 구현했다. 신뢰되는 서명과 실제 Windows 11 동작은 아직 미검증이므로 환경 확보만으로 완료를 약속하지 않는다.

로컬 호스트의 후속 읽기 전용 probe에서는 세션1의 Explorer1개, WinSta0\Default, UOI_IO=True와 OpenInputDesktop(DESKTOP_READOBJECTS) 성공을 stdout으로 확인했다. UIAutomation DLL도 존재했다. 네이티브 자동화 provider의 비활성을 모든 Windows API 접근 불가와 동일시하지 않는다. 입력·캡처·UIA 제어·클립보드 시험은 실행하지 않았고 별도 JSON 및 정확한 UTC 시각은 없다. 기존 OS/Explorer 버전의 후속 재조회는 실행 전 EPERM으로 막혔다. 일반 설치 경로에서 VirtualBox·VMware·QEMU·Sandbox·vmcompute를 찾지 못했고 HypervisorPresent=false였으나, 모든 가상화 수단이 불가능하다는 증거는 아니다. 이 읽기 전용 관찰 자체로 새 격리 환경이나 G0 연결을 확보했다고 판정하지 않는다. 개정 위치의 후보는 [현재 G0 기록](G0_Menu_Feasibility.md)에서 따로 추적한다.

## 재현 방법

[CI 스크립트](../../../tools/ImageCopySave/build/ci.ps1)는 helper·시험을 빌드하고 --require-clipboard 및 --helper로77개를 실행한다. 총77개·격리21개·실제 helper12개와 확장9개 필수 시험이 모두 PASS인지 확인한다. 결과 파일 누락·NOT RUN·FAIL을 성공으로 처리하지 않는다. 결과는 artifacts/image-copy-save/ci 아래 JSON과 소유 로그3개에 기록한다.

~~~powershell
./tools/ImageCopySave/build/ci.ps1 -DotNet ./.tools/dotnet/dotnet.exe
~~~

현재 로컬 호스트에서는 새 station 생성 제약으로 격리21개가 NOT RUN일 수 있다. 이번77개를 로컬에서 전체 실행하지 않았으며 마지막 로컬51 PASS/17 NOT RUN은 이전68개 구성의 기록이다. 실제 디스크 부족은 IMAGE_COPY_SAVE_TEST_ISOLATED_FS=1, GITHUB_ACTIONS=true, RUNNER_ENVIRONMENT=github-hosted 및 기존 관리자 토큰이 필요하다. workflow 템플릿이 이 opt-in을 설정한다. 로컬에서 환경 변수를 가장하여 실행하는 절차는 제공하지 않는다. 일반 Windows 시험의 ACL 변경은 새로 만든 소유 fixture에만 적용하고 복원한다. 큰 fixture는3GiB 메모리 여유가 없으면 NOT RUN이며 테스트 성공으로 계산하지 않는다. CI 통과가 호스트 권한 변경을 의미하지 않는다. [workflow 템플릿](../../../tools/ImageCopySave/build/windows-ci.yml)은 로컬에 비활성으로 보존했다. 후속 시험은 사용자가 승인한 임시 시험·증거 회수·원격 자료 삭제 범위에서만 진행하며, main 병합이나 제품 배포를 포함하지 않는다.

자체 포함 시험 ZIP은 build/build.ps1 -PublishRemoteTests로 재생성할 수 있다. 현재 스크립트는 실제 helper도 ZIP 내부 helper 폴더에 포함하도록 구성했다. 직접 시험 실행 시 --helper에 절대 실행 파일 경로를 지정할 수도 있다. 이전에 생성한 로컬 ZIP은 이번 CI 수정 전의 과거 산출물이며 최신 통과 소스의 배포본으로 사용하지 않는다. 사용자에게 다른 PC에서 수동 실행하라는 요구가 아니다.

## 이전 Codex 내부 진단

현재 프로세스는 WinSta0·비승격 토큰이었다. LOGON_NETCREDENTIALS_ONLY 임시 후보는 동일 사용자·무결성·승격 상태와 새 AuthenticationId를 보였으나 기존 Job 소속·그룹 검사를 통과하지 못했다. 자식을 정지 상태에서 종료했고 자식 코드·station 생성·clipboard API를 실행하지 않았다. 이 경로는 채택하지 않았다.

해당 진단에서 .NET 최초 실행의 개발 HTTPS 인증서 설치 메시지가 출력됐지만 신뢰 명령은 실행하지 않았고 실제 인증서 생성 여부는 확인하지 않았다. 이후 기존 DOTNET_CLI_HOME과 인증서 자동 생성 비활성 설정을 사용했다. SID가 포함된 로컬 진단·첨부·기존 로그·실제 자격증명은 원격에 업로드하지 않았다.

## 공식 근거

- [CreateWindowStationW — 이름과 생성 전용 플래그](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-createwindowstationw)
- [Window Stations — station별 clipboard](https://learn.microsoft.com/en-us/windows/win32/winstation/window-stations)
- [SetThreadDesktop — 창·hook이 있는 스레드의 제한](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setthreaddesktop)
- [Thread Connection to a Desktop — STARTUPINFO 연결](https://learn.microsoft.com/en-us/windows/win32/winstation/thread-connection-to-a-desktop)
- [EnumClipboardFormats — 원래 게시 형식과 합성 순서](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumclipboardformats)
- [GetClipboardSequenceNumber — sequence 의미](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclipboardsequencenumber)
- [GitHub-hosted runners — Windows 관리자 환경](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
