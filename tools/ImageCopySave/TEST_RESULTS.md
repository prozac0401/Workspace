# 그림 복사·저장 · 검증 기록

기록일: 2026-09-25(KST) · 제품 판정: **G0 BLOCKED / 배포 불가** · v1.1 독립 메뉴 승인, 변경된 경로의 G0 실기 NOT RUN

## 로컬 통합 후보 재검증 — 2026-09-25

새 Git worktree·원격 CI 없이 현재 작업 폴더에서 수행했습니다. Invoke 기준값 전달, WinExe 비모달 진행·취소·결과, UTF-8 결과 연결과 같은 보기 선택 후보를 구현했습니다. [ADR-0017](../../docs/design/0017-image-copy-save-invocation.md)과 [PC 확인 절차](../../docs/tools/image-copy-save/local-verification.md)를 함께 확인합니다.

- 최신 엔진/helper 자동시험: **62 PASS / 0 FAIL / 24 NOT RUN, 총 86개**. `artifacts/image-copy-save/helper-finish-results.json`. 기존 클립보드 21개와 새 Shell 경로 2개는 fresh private station 생성 오류 183으로 미실행, 전용 VHD 디스크 부족 1개는 로컬 실행 대상이 아니므로 미실행입니다. 사용자 클립보드로 대체하지 않았습니다.
- helper Release 빌드: 경고 0·오류 0. 프로토콜 거절, 완료/불확실/오류 메시지 분리, broken pipe에서도 Shell 저장 성공과 결과 경로 유지 시험은 PASS입니다.
- WPF 진행·저장·오류 3종 비표시 렌더링과 육안 확인: PASS. `artifacts/image-copy-save/helper-feedback-render`. 실제 포커스·취소 버튼·앱 붙여넣기 검증은 아닙니다.
- native DLL과 시험 실행 파일을 **로컬에서 새로 빌드**하고 **66 PASS / 0 FAIL**. MSVC 19.41.34123, SDK 10.0.26100.0, x64 static CRT, `/W4 /WX`와 linker `/WX`. `artifacts/image-copy-save/native-shell/shell-results.json`, `build-metadata.json`. 다른 폴더·중첩 경로·개행/NUL 결과 거절을 추가했습니다. 실제 Invoke·Explorer는 실행하지 않았습니다.
- 로컬 도구는 고정 Microsoft payload SHA256, SDK NuGet author/repository 서명과 실행 파일 Authenticode를 확인해 `.tools/image-copy-save-native`에만 추출했습니다. 시스템 설치는 하지 않았습니다. 초기 컴파일의 Shell 헤더 누락과 링크의 OLDNAMES.lib 누락은 수정·보완한 뒤 재빌드에 통과했습니다.
- 최신 패키지 생성·서명·설치 상태는 [이번 인계 기록](../../docs/delivery/image-copy-save-local-20260925.md)에 별도로 기록합니다. unsigned나 로컬 자체서명 평가 패키지를 상용 승인 릴리즈로 표시하지 않습니다.

현재 G0·M2 실기·M3 설치 수명주기는 여전히 미완료입니다. 아래 과거 PASS는 당시 실행한 범위의 이력이며 새 Shell 통합 후보 전체의 인증으로 확장하지 않습니다.

## 이전에 확인된 엔진·helper 실행 결과

로컬 초기 환경: Windows 11 Pro 23H2 x64, OS 빌드 22631.6199(런타임 표기 Microsoft Windows NT 10.0.22631.0), Explorer 10.0.22621.4599. SDK 10.0.401, 런타임 10.0.12. 이 환경을 제품 지원 인증 목록으로 표시하지 않습니다.

- 개발용 helper Release 빌드: PASS, 경고 0·오류 0.
- PowerShell `build/build.ps1`: 초기 구성에서 실제 실행 PASS. 이전77개 구성은 CI의 `build/ci.ps1`로 실행했으며 자체 포함 ZIP 재생성은 하지 않았습니다.
- 이전 확장 Windows CI 시험: **77 PASS / 0 FAIL / 0 NOT RUN**. 격리 clipboard21개 중 실제 제품 helper12개 포함. 실행 시각 2026-09-24T15:03:11.8505622+00:00. Windows Server 2025 x64, OS10.0.26100.0, 관리자, 세션2, SDK10.0.401·런타임10.0.12. Windows 11 일반 사용자 인증은 아닙니다.
- 마지막 로컬 회귀는 이전68개 구성의 51 PASS / 0 FAIL / 17 NOT RUN입니다. 77개 구성은 아래 과거 CI에서 실행했으며 이번 native 후보 작업에서 엔진/helper 시험을 재실행하지 않았습니다. 로컬 격리 권한 제한이 해제된 것은 아닙니다.
- v1.1에서 번호를 유지한 수용시험 44개: **9 PASS(Windows 엔진·helper 범위), 22 BLOCKED, 13 NOT RUN**. 통합 제품 합격 판정이 아닙니다.
- 로컬에서는 오류5→자동 이름 충돌183으로 격리 생성이 막혔습니다. 사용자 승인 후 CI의 새 private station에서 실제 시험을 완료했습니다. 사용자 클립보드는 대신 사용하지 않았습니다.
- 승인된 첫 우클릭 독립 메뉴·외부 앱 붙여넣기·설치·제거 실기는 NOT RUN입니다. 기본 New 내부 위치는 v1.0의 과거 검증 대상입니다.

초기 로컬 자동 결과 JSON과 실행 로그는 로컬 `artifacts/image-copy-save/automated-results.json`, `tests-final.log`, `build-script.log`에 있습니다. 생성 진단 파일은 공개 사이트에 포함하지 않습니다. JSON을 다시 생성하는 명령은 [README](README.md)에 있습니다.

## v1.1 메뉴 위치와 native 후보 — 2026-09-25

사용자가 ‘새로 만들기’ 내부 배치 조건을 해제했다. 현행 기준은 [v1.1 개정명세](../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.1.md)와 [ADR-0016](../../docs/design/0016-image-copy-save-direct-menu.md)의 **실제 로컬 폴더 빈 공간에서 여는 Windows 11 첫 우클릭 메뉴의 독립 명령 ‘복사한 그림 저장’**이다. 기본 New 내부 동적 항목을 입증하지 못한 기록은 v1.0 당시의 조사 결과로 남기며, 현행 요구의 미승인 대안으로 취급하지 않는다.

지원 이미지가 없으면 `ECS_HIDDEN`으로 완전히 숨기는 조건, 회색 메뉴·상주 감시·‘더 많은 옵션 표시’ 전용·사용자 수동 등록 금지, 기존 New와 기본 연결 보존은 유지한다. 위치 승인으로 G0·설치 실기나 44개 AT를 PASS로 올리지 않는다.

| 새 산출물·시험 | 현재 상태 | 증거 범위 |
|---|---|---|
| native IExplorerCommand + IObjectWithSite 후보 | x64 DLL 빌드 PASS | 문맥·형식 상태 판정과 helper 실행 위임 후보. Explorer에 등록하거나 실제 메뉴를 시험하지 않음 |
| native 순수 정책·직접 COM 경계 63개 | **63 PASS / 0 FAIL — CI 및 로컬 동일 시험** | 소스 목록은 63개. DLL 직접 로드·가짜 COM 객체·합성 형식 플래그만 사용하며 클립보드·Invoke·Explorer·등록·설치를 시험하지 않음 |
| unsigned full MSIX 생성·압축 해제·구조 검사 | **PASS** | package identity 후보와 build/검사 절차. 서명·신뢰·사용자 설치 성공 증거 아님 |
| 변경된 위치의 G0 실제 메뉴 및 설치 수명주기 | **NOT RUN** | Windows 11 첫 메뉴·20회 표시/숨김 전환·일반 사용자 설치·재설치·업데이트·제거 증거 필요 |

이전 후보에서는 native `Invoke`가 명령 종류와 경로만 helper에 전달하여 초기 시퀀스 공백과 결과/UI 연결이 남아 있었다. 이번 로컬 통합 후보에서 해당 연결을 구현했으며 최신 자동 결과는 문서 상단에 기록한다. 실제 호출 시점부터 완료까지의 클립보드·포커스·탭 동작은 아직 통합 검증 전이다.

위 63개 자동 경계 시험의 결과가 나와도 실제 클립보드 기반 메뉴 표시, 호출 폴더·탭 식별, helper 실행·피드백·선택, 설치·제거의 통합 증거를 대신하지 않는다. 아래 과거 77개 엔진/helper 결과는 보존한 이전 실행이며, 이번 native 후보 작업에서 재실행한 결과가 아니다.

## native 후보의 실제 실행 결과

2026-09-25 Windows Server 2025 x64 CI 실행 36075794514에서 **63 PASS / 0 FAIL**, DLL·시험 실행 파일 빌드와 unsigned MSIX 생성·압축 해제 검사가 통과했습니다. MSVC 14.51.36231(compiler 19.51.36256.0), Windows SDK 10.0.26100.0, 정적 CRT, /W4 /WX 및 linker /WX를 사용했습니다. 최종 소스 커밋은 c459edfbf1ccb8577bd97975b8dbd5966db3a07a이며 업로드 파일34개의 SHA256을 로컬 소스와 대조했습니다.

- [CI native 결과](../../artifacts/image-copy-save/ci-shell-36075794514/artifact/native-shell/shell-results.json), [컴파일 정보](../../artifacts/image-copy-save/ci-shell-36075794514/artifact/native-shell/build-metadata.json). 실제 clipboard/GetState 지원 이미지 상태·Invoke·OS COM 활성화·Explorer UI는 실행하지 않았습니다.
- 같은 DLL/시험 실행 파일을 로컬 Windows 11 Pro x64, kernel10.0.22631에서 등록 없이 실행해 **동일63개 PASS**를 확인했습니다. [로컬 결과](../../artifacts/image-copy-save/native-local-results.json), [환경·해시](../../artifacts/image-copy-save/native-local-environment.json). 로컬 native 빌드는 도구 헤더/라이브러리 부재로 NOT RUN이고 CI 바이너리를 사용했습니다. 최초 실행은 슬래시 경로를 거부한 CLI 사전 검사로 종료2였고 시험에 진입하지 않았습니다. 정규 Windows 경로로 수정 후 통과했습니다. [실행 기록](../../artifacts/image-copy-save/native-local-run.json).
- [패키지 검사 결과](../../artifacts/image-copy-save/ci-shell-36075794514/artifact/package-evaluation/package-result.json): MSIX 64,309,547bytes, 입력408개 모든 파일 해시 일치, 압축 해제409개, x64/CLSID/문맥/런타임·필수 PNG 확인. 서명 파일 없음. SHA256: 08886067B353E24F4FAFE9310066AE16BECBA2EA119F3E0D0ABCC779F3D26AEE. signing/installation/explorerG0는 모두 NOT RUN입니다.

첫 CI 실행36075520486은 시험 코드의 매크로 중복 정의(C4005→/WX)로 빌드가 실패해 63개 시험과 패키징은 실행되지 않았습니다. guard를 적용하고 DLL의 .def 출력 이름 경고를 수정한 두 번째 실행이 위 최종 결과입니다. 첫 실패 로그도 보존했습니다. 두 실행의 artifact2개와 run2개, 임시 브랜치는 DELETE204 후 GET404로 삭제를 확인했고 workflow조회404, main은 시작 SHA와 동일합니다. [전체 시험·소스·정리 증거](../../artifacts/image-copy-save/ci-shell-session.json)를 참조하세요. 공개 Git 객체나 제삼자 복제본까지 소거했다고 보장하지 않습니다. PR·main 병합·제품 배포는 하지 않았습니다.

## 마일스톤

| 단계 | 상태 | 남은 조건 |
|---|---|---|
| M0/G0 | BLOCKED | v1.1 독립 메뉴 후보 로컬 빌드·정책/직접 COM 66개 PASS. 실제 등록·첫 메뉴·화면 증거 NOT RUN |
| M1 | 최신 로컬 62 PASS / 24 NOT RUN | 과거 77 PASS와 새 보호 경로의 시험을 구분. 격리 clipboard·일반 사용자 외부 앱 미검증 |
| M2 | 구현 후보 완료, 실기 BLOCKED | Invoke 기준값·결과 연결·같은 보기 선택·비모달 UI 구현. G0·탭/포커스·취소 입력·외부 앱 붙여넣기 NOT RUN |
| M3 | BLOCKED | 빌드·서명·설치/제거 절차 작성. 실제 서명·설치 상태는 인계 기록, 전체 수명주기·회귀 NOT RUN |

## 44개 수용시험 대응표

PASS는 표에 명시한 실제 실행 범위에 한정합니다. BLOCKED는 G0/미완료 통합이 선행 조건이고 해당 실기는 실행하지 않았다는 뜻입니다. NOT RUN은 해당 전체 시나리오를 실행하지 않았다는 뜻입니다. 일부 자동 근거가 있어도 나머지 검증을 통과로 승격하지 않습니다.

| ID | 시험 | 전체 상태 | 실제 근거 및 남은 시험 |
|---|---|---|---|
| AT-01 | 빈 클립보드에서 폴더 메뉴 열기 | BLOCKED | metadata-only의 빈 상태 판정 PASS; native 후보 소스 작성, 실제 Explorer 메뉴 NOT RUN |
| AT-02 | 텍스트만 복사 후 메뉴 열기 | BLOCKED | metadata-only의 텍스트 상태 판정 PASS; native 후보 소스 작성, 실제 Explorer 메뉴 NOT RUN |
| AT-03 | URL/HTML만 복사 후 메뉴 열기 | BLOCKED | HTML/URL metadata-only 판정 PASS; native 후보 소스 작성, 실제 Explorer 메뉴 NOT RUN |
| AT-04 | PNG 파일을 일반 Ctrl+C로 파일 목록만 복사 | BLOCKED | 실제 clipboard CF_HDROP 제외 PASS; native 후보 소스 작성, 실제 Explorer 메뉴 NOT RUN |
| AT-05 | 지원 이미지 데이터를 복사 | BLOCKED | 지원 이미지 형식 판정 PASS; native 후보 소스 작성, 실제 Explorer 메뉴 NOT RUN |
| AT-06 | 이미지+텍스트 형식 함께 제공 | BLOCKED | 실제 이미지+텍스트 공존 판정 PASS; native 후보 소스 작성, 실제 Explorer 메뉴 NOT RUN |
| AT-07 | 이미지→텍스트→빈 상태→이미지를 20회 반복 | BLOCKED | v1.1 독립 메뉴 후보의 20회 탐색기 표시/숨김 실기 NOT RUN |
| AT-08 | 실제 로컬 폴더 빈 공간의 첫 우클릭 메뉴에 독립 명령 표시 확인 | BLOCKED | 위치 변경 승인. native 후보의 요청 위치·조건부 숨김 실제 메뉴 시험 NOT RUN |
| AT-09 | Windows 11 첫 우클릭 메뉴 확인 | BLOCKED | Windows 11 첫 메뉴 확장 미등록 |
| AT-10 | 메뉴 열기/닫기만 반복 | BLOCKED | 형식 확인 API 분리 구현; 실제 메뉴 반복 시험 없음 |
| AT-11 | 그림 파일 1개에서 그림으로 복사 | BLOCKED | 엔진 및 실제 helper copy→native Capture PASS; native 선택 명령 연결 후보 소스 작성, Explorer 실행 실기 NOT RUN |
| AT-12 | 그림 파일 2개·혼합 파일·폴더·TXT 선택 | BLOCKED | native 선택 상태 판정 후보 소스 작성. 직접 COM의 지원 밖 상태 경계 PASS, 실제 메뉴 숨김 NOT RUN |
| AT-13 | 클립보드의 이미지를 저장 | BLOCKED | 실제 helper save의 PNG 생성·클립보드 보존 PASS; caller-site 폴더 해석 후보 소스 작성, 실제 탐색기 폴더 호출·helper 연결 NOT RUN |
| AT-14 | 같은 초에 3번 연속 저장 | PASS (엔진 자동) | save/same-second-existing-file-protected: 같은 초 3개 저장, _2~_4, 기존 sentinel 보존 |
| AT-15 | 병렬 저장과 기존 이름 충돌 | PASS (엔진 자동) | 엔진16개 동시 저장 및 실제 helper4개×8회 병렬 저장 PASS; 기존 sentinel 보존·유효 PNG32개·덮어쓰기/임시파일 없음 |
| AT-16 | 탐색기 A/B 창과 탭에서 서로 다른 폴더 호출 | BLOCKED | caller-site 폴더 해석 후보 소스 작성. 실제 보기·창·탭 식별 NOT RUN |
| AT-17 | 메뉴를 연 뒤 클립보드를 텍스트로 변경하고 실행 | BLOCKED | newer-copy의 텍스트/빈 상태 읽기 PASS; 메뉴를 연 뒤 실행하는 통합 시나리오 미실행 |
| AT-18 | 메뉴를 연 뒤 이미지 A를 B로 바꾸고 실행 | BLOCKED | 실제 helper product-save-current가 현재 이미지B 저장·sequence 보존 PASS; 메뉴를 연 뒤 실행하는 통합 시험 미실행 |
| AT-19 | 저장 스냅샷 확보 뒤 다른 내용을 복사 | PASS (엔진·helper 자동) | snapshot A 확보→실제 다른 helper가 B 복사→엔진으로 A PNG 저장→B와 sequence 보존 PASS. 제품 save 내부를 일시정지한 시험은 아님 |
| AT-20 | PNG 투명/반투명 픽셀 복사→저장 왕복 | PASS (helper 자동) | 실제 helper copy 완전 종료→원본 이동·삭제→save 왕복에서 2×2 기준 이미지의 크기·RGBA·투명 픽셀RGB 정확 일치 PASS |
| AT-21 | JPEG 방향 태그 있는 사진 복사 | PASS (helper 자동) | 실제 helper EXIF6 JPEG copy→native Capture→PNG save에서 2×3 방향·픽셀 PASS; 엔진 방향1~8도 PASS |
| AT-22 | 한글·공백·괄호·비ASCII 파일명/폴더 | PASS (엔진 자동) | save/unicode-path-valid-png + source/read-and-original-protection PASS (한글·공백·괄호·é) |
| AT-23 | helper 완전 종료 후 다른 앱에 붙여넣기 | NOT RUN | 실제 제품 helper와 worker 완전 종료·잔존 자식0 후 시험 프로세스 native Capture PASS; 그림판·Office 등 외부 앱 붙여넣기 미실행 |
| AT-24 | 복사 완료 후 원본 이동·삭제 | NOT RUN | 실제 helper 종료 후 원본 이동·삭제 및 native Capture·PNG 저장 PASS; 외부 앱의 실제 붙여넣기 미실행 |
| AT-25 | 원본 파일 읽기/디코딩 실패 | NOT RUN | 실제 helper 손상 PNG 거절·텍스트/sequence/원본 보존 PASS; 엔진의 실제 읽기 ACL 거부·권한 복원 PASS. helper의 ACL 실패·최종 UI 안내 전체는 미실행 |
| AT-26 | 클립보드 갱신 준비 중 새 사용자 복사 발생 | PASS (helper 자동) | 다른 실제 helper가 새 B를 게시한 뒤 오래된 public copy가 ClipboardChangedException·종료1로 거절되고 B/sequence 보존 PASS. oplock break의 원인 PID·정확한 I/O 단계는 미확정. native Invoke→helper 시작 구간은 이 근거의 범위 밖 |
| AT-27 | 클립보드 잠금·지연 렌더링·공급 앱 멈춤 | NOT RUN | native 잠금·협조적 지연 렌더링 및 실제 helper의 멈춘 합성 공급자 watchdog PASS; helper 자식0·공급자 생존 확인. Explorer 무한 대기 실기는 미실행 |
| AT-28 | 지원 형식에 손상된 PNG/DIB 데이터 제공 | NOT RUN | 실제 helper가 clipboard 손상 PNG·잘린 DIBV5·잘못된 DIB를 거절하고 원시 데이터·text·sequence 보존 PASS. Explorer 통합 및 명세의 Explorer 무충돌 조건 미실행 |
| AT-29 | 안전 상한 바로 아래·경계·초과 입력 | NOT RUN | 실제 16383/16384/16385×1, 9999×5000/10000×5000/10000×5001 BGRA로 허용 4개 PNG 왕복 전체픽셀 일치·초과 2개 무출력 PASS. 128MiB payload/256MiB buffer 전체 경계 종단 시험은 미완료 |
| AT-30 | stride/길이/크기 오버플로와 잘못된 헤더 | PASS (엔진 자동) | malformed stride/dimensions/masks/profile/lengths 및 EXIF offset 검증 PASS |
| AT-31 | 쓰기 권한 없음·디스크 부족 | PASS (엔진 자동) | 실제 대상 ACL 거부(오류5)·128MiB 전용 VHD 실제 디스크 부족(오류112)에서 기존 파일 보존·불완전 PNG/임시파일 없음 PASS. DACL 복원·VHD 분리 확인 |
| AT-32 | 저장/복사 진행 중 취소 | NOT RUN | 기존 엔진 취소와 내부 event 시험 PASS. 새 시험은 프로세스 생성·oplock break 관측 후 취소 요청, 종료3·원본/clipboard 보존·자식0 확인. break 원인 PID가 없어 정확한 처리 단계·public Ctrl+C·최종 UX는 미검증 |
| AT-33 | 저장 후 해당 탭이 닫힘/다른 탭으로 이동 | BLOCKED | 같은 보기·현재 폴더·가시성·전경 루트 재확인 후 선택 구현. 실제 탭 전환·닫힘·포커스 미실행 |
| AT-34 | 홈·검색·ZIP·네트워크 등 비지원 저장 위치 | BLOCKED | 로컬 경로 제한 자동검사 PASS; Shell namespace 메뉴 숨김 미실행 |
| AT-35 | 온라인 전용 그림 파일 | NOT RUN | reparse/offline/recall 속성 검사 구현; 실제 온라인 전용 파일 미실행 |
| AT-36 | Windows 그림판에 붙여넣기 | NOT RUN | 그림판 버전/붙여넣기 NOT RUN |
| AT-37 | 설치된 Word/PowerPoint에 붙여넣기 | NOT RUN | Word/PowerPoint 버전/붙여넣기 NOT RUN |
| AT-38 | 실제 사용하는 메일·메신저 본문에 붙여넣기 | NOT RUN | 메일/메신저 버전/붙여넣기 NOT RUN |
| AT-39 | 메뉴 및 4K 이미지 반복 성능 측정 | NOT RUN | 4K 합성 gradient/alpha 엔진 Save/Read 2회 예열+10회 측정 P50/P95 기록 PASS. 실제 메뉴·helper/clipboard 전체 지연·탐색기 응답성 미실행 |
| AT-40 | 설치·재설치·업데이트·제거 반복 | BLOCKED | unsigned MSIX 제작·구조/408개 입력 해시 검사 PASS. 설치·재설치·업데이트·제거 NOT RUN |
| AT-41 | 일반 사용자 계정 설치/사용 | BLOCKED | package identity 후보 작성, 서명·신뢰 방식 미결정. 일반 사용자 설치 NOT RUN |
| AT-42 | 앱 종료·Windows 로그인 후 프로세스/시작항목 점검 | BLOCKED | 감시기/서비스/시작 등록 구현 없음; 설치 후 로그인 점검 NOT RUN |
| AT-43 | 원본/로그/네트워크 점검 | NOT RUN | 원본 보호·메타데이터 제거 및 손상 원본 실패 시 실제 helper 원시 stdout/stderr의 fixture 경로·텍스트·이미지 정보 비노출 PASS. 전체 설치 로그/네트워크 실측 NOT RUN |
| AT-44 | 기존 복사·붙여넣기·기본 연결·다른 메뉴 회귀 | BLOCKED | 메뉴/기본 연결 미등록; 설치 전후 회귀 NOT RUN |

## 이전 엔진·helper 자동 시험 상세

| 시험 | 결과 |
|---|---|
| limits/dimension-boundary | PASS |
| limits/pixel-boundary | PASS |
| limits/zero-negative-overflow | PASS |
| limits/payload-boundary | PASS |
| limits/exact-buffer | PASS |
| save/unicode-path-valid-png | PASS |
| save/same-second-existing-file-protected | PASS |
| save/parallel-no-overwrite | PASS |
| save/rollback-Created | PASS |
| save/cancel-Created | PASS |
| save/rollback-Written | PASS |
| save/cancel-Written | PASS |
| save/rollback-Flushed | PASS |
| save/cancel-Flushed | PASS |
| save/rollback-BeforeCommit | PASS |
| save/cancel-BeforeCommit | PASS |
| save/cancel-before-create | PASS |
| save/directory-name-collision | PASS |
| save/invalid-image-no-file | PASS |
| source/read-and-original-protection | PASS |
| source/reject-path-and-unsupported | PASS |
| source/reject-device-path-before-reading | PASS |
| path/ancestry-cannot-rename-while-pinned | PASS |
| path/source-cannot-replace-while-pinned | PASS |
| save/directory-pinned-through-commit | PASS |
| save/owned-temp-replacement-blocked | PASS |
| save/cleanup-native-failure-reported | PASS |
| save/read-only-name-collision-preserved | PASS |
| codec/PNG exact RGBA including transparent RGB | PASS |
| codec/indexed PNG palette transparency exact | PASS |
| codec/grayscale PNG converted without tone changes | PASS |
| codec/DIB standard INFO bitfields and V4 alpha | PASS |
| codec/repeated PNG DIBV5 alpha roundtrip | PASS |
| codec/DIBV5 straight alpha exact | PASS |
| codec/DIBV5 bottom-up row order | PASS |
| codec/DIB24 padded rows bottom-up | PASS |
| codec/DIB24 padded rows top-down | PASS |
| codec/DIB32 BI_RGB reserved byte is opaque | PASS |
| codec/BMP24 and V5 file inputs | PASS |
| codec/signature extension mismatch | PASS |
| codec/PNG CRC truncation and trailing data | PASS |
| codec/PNG APNG and high-bit-depth rejected | PASS |
| codec/PNG profile and HDR rejected | PASS |
| codec/PNG oversized dimensions rejected before decode | PASS |
| codec/PNG EXIF orientations 1-8 both byte orders | PASS |
| codec/JPEG EXIF orientations 1-8 | PASS |
| codec/JPEG ICC MPO high-bit CMYK and malformed rejected | PASS |
| codec/EXIF malicious offsets and invalid orientation | PASS |
| codec/output metadata stripped after orientation | PASS |
| codec/DIB malformed stride dimensions masks profile lengths | PASS |
| codec/BMP unsafe offsets and declared lengths | PASS |
| clipboard isolated metadata-only | PASS (Windows CI) |
| clipboard isolated alpha-roundtrip | PASS (Windows CI) |
| clipboard isolated newer-copy | PASS (Windows CI) |
| clipboard isolated preparation-preserves | PASS (Windows CI) |
| clipboard isolated snapshot-independent | PASS (Windows CI) |
| clipboard isolated native-formats | PASS (Windows CI) |
| clipboard isolated helper-exit | PASS (Windows CI) |
| clipboard isolated lock-and-cancel | PASS (Windows CI) |
| clipboard isolated delayed-rendering | PASS (Windows CI) |
| clipboard isolated product-copy-save-alpha | PASS (Windows CI, 실제 helper) |
| clipboard isolated product-jpeg-copy | PASS (Windows CI, 실제 helper) |
| clipboard isolated product-invalid-preserves | PASS (Windows CI, 실제 helper) |
| clipboard isolated product-empty-save | PASS (Windows CI, 실제 helper) |
| clipboard isolated product-parallel-save | PASS (Windows CI, 실제 helper) |
| clipboard isolated product-save-current | PASS (Windows CI, 실제 helper) |
| clipboard isolated product-worker-cancel | PASS (Windows CI, 실제 helper) |
| clipboard isolated product-watchdog | PASS (Windows CI, 실제 helper) |

| 확장 자동 시험 | 결과 |
|---|---|
| clipboard isolated product-snapshot-other-copy | PASS (Windows CI) |
| clipboard isolated product-corrupt-clipboard | PASS (Windows CI) |
| clipboard isolated product-copy-preparation-race | PASS (Windows CI) |
| clipboard isolated product-worker-inflight-cancel | PASS (Windows CI) |
| filesystem/actual-source-read-ACL-denial | PASS (Windows CI) |
| filesystem/actual-destination-write-ACL-denial | PASS (Windows CI) |
| filesystem/owned-VHD-real-disk-full | PASS (Windows CI) |
| limits/actual-pixel-boundaries-roundtrip | PASS (Windows CI) |
| performance/4k-engine-save-read-p50-p95 | PASS (Windows CI) |

## 검증 중 수정한 실패

첫 실행에서 네이티브 rename 문자열 종료 처리가 부족하여 일부 이름 전환에 오류 123이 발생했습니다. NUL 여유 공간을 확보하고 초기화한 뒤 재시험했습니다. 경로 보호를 추가하는 과정에서는 속성 전용 핸들이 이동을 차단하지 않는 문제와 디렉터리 쓰기 공유를 막으면 정상 자식 파일 이름 전환도 차단되는 문제를 발견했습니다. 실제 읽기/목록 핸들로 삭제 공유를 막고 디렉터리 쓰기 공유는 허용하도록 수정했습니다. 해당 초기 로컬51개 실행 시험에 실패는 없었습니다.

첫 빌드는 실행 환경의 누락된 프로필 변수 때문에 NuGet 복원에 실패했고, 명시한 개발 환경으로 재현했습니다. PowerShell 호스트의 직접 native 호출이 출력/종료 코드를 전달하지 않는 문제는 ProcessStartInfo의 명시적 출력 수집으로 수정했으며 최종 빌드 스크립트 실행을 확인했습니다. 이들은 제품 설치 성공 증거가 아닙니다.

## 한계

이전 오류 주입과 별도로 실제 ACL 거부·전용 VHD 디스크 부족을 검증했습니다. 전원 차단은 미실행입니다. 경로 보호 시험은 디렉터리 이동·원본 교체 거부를 확인했으며 실행 도중 드라이브 매핑이나 reparse 설정을 바꾸는 공격까지 입증하지 않습니다. 원본·클립보드·민감 경로를 로깅하는 기능은 만들지 않았으나 네트워크/DLP 실측은 수행하지 않았습니다. [제한사항](KNOWN_LIMITATIONS.md)을 함께 읽어야 합니다.

## 초기 로컬 문서·재현 절차 확인

- `python -m mkdocs build --strict --site-dir artifacts/image-copy-save/site`: PASS.
- `python scripts/check-site.py artifacts/image-copy-save/site`: PASS, 공개16페이지+404, 검색·사이트맵·로컬 링크·비공개 자산 제외 확인.
- 신규 문서의 상대 링크29개: PASS, 누락 없음.
- 첨부 원문과 보존 명세의 바이트 동일성: PASS. SHA-256 `3099ac0266f402131708804fbbc6eb836f62665c40112218c3624ee801f4e92d`.
- 개발용 helper 인수 누락: 종료2 및 사용법 표시. 존재하지 않는 이미지의 copy: 종료1, 단계·오류 코드·clipboardMayHaveChanged=false 출력, 원본 경로는 오류 출력에 없음. 실제 클립보드 게시나 붙여넣기 성공을 의미하지 않습니다.
- git diff --check: PASS. 기존 다른 도구의 작업 변경을 유지하고 신규 ImageCopySave 경로만 추가했습니다. 원격 커밋·배포·설치 등록 없음.

빌드/시험 환경에서 누락된 Windows 프로필 변수를 명시하여 .NET 복원을 실행했습니다. 일반 개발자 PowerShell에서는 기존 사용자 환경을 사용하며, 저장소 SDK를 쓸 때는 README의 -DotNet 경로를 지정합니다. 자체 포함 publish 옵션은 소스로 제공하지만 이번 실행에서는 사용하지 않았습니다.

## 과거 기록: 원격 실행 재검증 — 2026-09-24 후속

이전 오류5를 원격 환경 자체의 한계로 단정하지 않습니다. CreateWindowStation의 명시적 이름은 관리자 전용이라는 계약을 반영해 일반 사용자는 자동 이름, 이미 관리자 권한인 시험 프로세스는 고유 이름을 사용하도록 수정했습니다. 자동 승격은 없습니다. 두 경로 모두 CWF_CREATE_ONLY, 원래 station과 다른 이름, 비대화형 확인, 새 객체의 사용자 DACL을 사용합니다.

이 세션에서는 자동 이름의 기존 객체가 있어 오류183으로 중단했습니다. 기존 객체 재사용이나 사용자 클립보드 변경은 수행하지 않았습니다. 당시 자체 포함 원격 패키지 실행은 **51 PASS, 0 FAIL, 9 NOT RUN**이며, `--require-clipboard` 모드가 종료2를 반환하는 것도 확인했습니다. JSON 실행 시각 2026-09-24T11:01:59.9176704+00:00, 프로세스 관리자 여부 false, 세션1입니다. 관리자 시험·다른 VM에서의 성공은 아직 확인하지 않았습니다.

빌드 스크립트의 -PublishRemoteTests 경로로 재현 가능한 ZIP을 만들고 런타임 라이선스 고지를 포함했습니다. 위치: `artifacts/image-copy-save/ImageCopySave-remote-tests-win-x64.zip`. 이는 시험 실행 프로그램이며 제품 설치 패키지나 배포 완료본이 아닙니다. SHA-256 `BF646A468883FDB0B13CA38D876B0E274371C3B6DCD3F734486AD3E3CDC85D87`. 최신 실행 자료는 `remote-required-results.json`과 `remote-required.log`에 있습니다.

현재 호스트는 관리자 토큰이 아니며 WindowsSandbox.exe·Hyper-V 실행 파일을 확인하지 못했습니다. Windows 기능 설치나 정책 변경 없이 원격 실행 가능한 조건과 명령은 [원격 시험 안내](../../docs/tools/image-copy-save/remote-testing.md)에 정리했습니다. G0·외부 앱 붙여넣기·제품 설치/제거 판정은 변경되지 않았습니다.

## 과거 기록: Codex만 사용하는 조건의 후속 진단

사용자는 별도 PC 조작이 불가능하므로 수동 원격 PC 실행은 해결책에서 제외했다. 현재 프로세스는 대화형 WinSta0·비승격 토큰이다. LOGON_NETCREDENTIALS_ONLY 임시 자식은 기존 Job 소속과 그룹 동일성 검사를 통과하지 못하여 정지 상태에서 종료했다. 자식 코드·station 생성·클립보드 API는 실행하지 않았다. 로컬 증거: artifacts/image-copy-save/logon-probe/bin/Release/net10.0-windows/parent.json. 이 진단을 clipboard 시험 PASS로 계산하지 않는다.

새 build/ci.ps1을 현재 환경에서 실제 실행했다. helper와 시험 프로젝트는 경고0·오류0으로 빌드했고 **51 PASS / 0 FAIL / 9 NOT RUN**을 기록했다. --require-clipboard의 **종료2가 스크립트까지 전파**되는 것을 확인했다. 결과: artifacts/image-copy-save/ci/results.json 및 ci-local-run.log. 이는 CI 실패 처리의 검증이며 GitHub-hosted Windows 실행 성공이 아니다.

build/windows-ci.yml은 비활성 로컬 템플릿이다. 원격 업로드·CI 실행은 NOT RUN이다. 공개 저장소 전송 범위와 별도 승인 필요성은 [Codex 시험 계획](../../docs/tools/image-copy-save/remote-testing.md)에 명시했다. G0·수용시험44개·제품 배포 판정은 그대로 유지한다.

helper-exit이라는 자동 시험 이름은 **시험용 게시 자식의 종료**를 뜻한다. 실제 제품 helper의 전체 수명주기나 그림판·Office 붙여넣기 통과를 의미하지 않는다.

로컬 CI 템플릿의 YAML 구조·실행 브랜치·수집 경로와 PowerShell 구문 검사: PASS. strict 문서 빌드와 공개 사이트 검사는 PASS다. 로그 정리 범위를 스크립트가 소유한 4개 파일로 제한하고 workflow도 같은 4개 파일만 수집하도록 정적 검토를 반영했다. 원격 CI 실행은 여전히 NOT RUN이다.

## 실제 Windows CI 완료 및 원격 정리 — 2026-09-24

사용자 승인으로 공개 저장소의 별도 시험 브랜치에서 실행했습니다. 초기 실행에서 발견한 결함을 수정하여 두 번 재검증했고, 각 실행의 JSON·로그를 로컬에 보존했습니다. main 병합·Release·Pages 배포는 없습니다.

| 실행 ID | 결과 | 의미 |
|---|---|---|
| 36001597145 | 51 PASS / 0 FAIL / 9 NOT RUN | station 생성 후 SetThreadDesktop 오류170. 시험 진입 전 차단 |
| 36002216827 | 58 PASS / 2 FAIL / 0 NOT RUN | 새 프로세스를 private desktop에서 시작하여 격리 해결. native-formats·지연 렌더링 실패 발견 |
| 36002778286 | **60 PASS / 0 FAIL / 0 NOT RUN** | 두 문제 수정 후 전체 성공 |

시험 진입 수정: 기존 STA 스레드의 desktop을 바꾸지 않고 STARTUPINFO.lpDesktop으로 새 case 프로세스를 시작합니다. 모든 case와 자식은 station 이름·비대화형·Test desktop을 확인한 후 clipboard에 접근합니다. 오류170의 특정 COM 창 원인은 직접 관측하지 않았으므로 추정으로 남깁니다.

엔진 수정: PNG를 우선하고 bitmap 계열은 Windows가 원래 게시 형식부터 열거하는 순서를 따릅니다. 자동 합성 DIBV5를 무조건 우선하던 경로를 제거했습니다. 지연 렌더링 시험은 렌더러 호출·이미지 일치·메타데이터 조회의 비렌더링을 확인하고, 명시적으로 새 복사를 발생시켜 stale Copy 거부와 새 내용 보존을 확인합니다. WM_RENDERFORMAT 직후 별도 sequence 증가를 반드시 관측한다는 기존 가정은 제거했습니다.

최종 소스 커밋 식별자: 5b8e3111a4313f03233967b44446f0a5386e38e9. 시험 후 원격 브랜치는 삭제했습니다. 결과 파일: [최종 JSON](../../artifacts/image-copy-save/ci-remote-36002778286/results.json). 각 실행 폴더에는 workflow.log·빌드/시험 로그·메타데이터·SHA-256 manifest가 있습니다. [원격 정리 기록](../../artifacts/image-copy-save/ci-remote-session.json)에는 3개 run과 3개 artifact의 DELETE204/조회404, 시험 브랜치 DELETE204/조회404, workflow 조회404 및 main SHA 불변을 기록했습니다. 공개된 Git 객체나 제삼자 복제본까지 완전히 소거한 것으로 표현하지 않습니다.

자동60개 통과는 제품44개 수용시험 전체 통과가 아닙니다. 44개 표의 상태는 **4 PASS(엔진 범위), 22 BLOCKED, 18 NOT RUN**을 유지하고 새 native 근거만 각 행에 추가했습니다. G0, 일반 사용자 설치, 실제 제품 helper 종료 후 외부 앱 붙여넣기, 설치·재설치·제거는 남아 있습니다.

## 실제 제품 helper 후속 검증 — 2026-09-24

Windows Server 관리자 CI에서 실제 ImageCopySave.Helper.exe의 공개 copy/save 명령과 제한시간 처리, 내부 worker 취소 계약을 시험했습니다. 시험 publisher만 사용하는 기존 helper-exit과 구분합니다. public Ctrl+C, Explorer, 외부 앱 붙여넣기와 제품 설치를 대신하지 않습니다.

| 실행 ID | 실제 결과 | 관측 및 조치 |
|---|---|---|
| 36007153901 | 67 PASS / 1 FAIL | 실제 helper 병렬 저장 실패. 초기 로그에는 세부 오류가 없어 원인 미확정 |
| 36007926703 | 68 PASS | 정제된 오류 단계·nativeCode 수집 추가. 한 번의 성공으로 해결 판정하지 않음 |
| 36008525124 | 67 PASS / 1 FAIL | 8회 반복 중 2회차에서 stage=read, nativeCode=1418 재현. 파일 이름 충돌 단계의 오류가 아님 |
| 36009092514 | **68 PASS / 0 FAIL / 0 NOT RUN** | Capture에 호출별 고유 HWND 적용 후 전체 통과, 실제 helper4개×8회 저장 통과 |

Capture는 고유한 message-only 창 핸들로 클립보드를 열고 메모리 복사를 끝낸 뒤 닫습니다. 디코딩은 잠금 밖에서 수행하며 EmptyClipboard/SetClipboardData를 호출하지 않습니다. [OpenClipboard의 서로 다른 창 간 배제 계약](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openclipboard)을 적용했습니다. NULL 핸들의 내부 경쟁이 Windows에서 어떻게 발생했는지는 직접 관찰하지 않았으므로, 관측한 read1418과 수정 후 반복 통과를 구분해 기록합니다. 오류 무시·읽기 재시도나 저장 덮어쓰기 완화로 통과시키지 않았습니다.

helper 부모와 내부 worker의 station·desktop 일치를 작업 전에 검사합니다. 작업 완료와 결과 출력 실패를 분리하고, 실행 후 제어 오류에는 변경·잔존 worker의 불확실성을 표시합니다. 이 오류 전달 경로의 모든 OS 장애를 주입한 시험은 아닙니다.

실제 helper8개는 alpha 복사/저장과 종료 후 원본 제거, JPEG 방향, 손상 입력·잘못된 내부 context의 보존, 텍스트/빈 저장 거절, 병렬 충돌, 현재 이미지B 저장, 사전 취소 event, 멈춘 합성 공급자를 검증합니다. worker 취소는 사전 signal된 내부 event 시험이며 UI Ctrl+C나 커밋 중간 취소로 계산하지 않습니다. watchdog case 총 소요는 16.469초이며, 내부 관측의 허용 범위14~19초는 제품15초+취소 유예1초에 시작·스케줄 여유를 둔 시험 기준입니다. helper 자식이 모두 종료되고 별도 공급자는 살아 있는지 정리 전에 검사합니다.

최종 커밋 식별자: f415bcb0562003107500bd9db2a00cef7beaccb1. [최종 JSON](../../artifacts/image-copy-save/ci-helper-36009092514/results.json), [실행별 소스 해시·원격 정리 기록](../../artifacts/image-copy-save/ci-helper-session.json)을 보존했습니다. 이번4개 run·artifact와 시험 브랜치는 DELETE204 후 조회404를 확인했고 workflow도 조회404입니다. main SHA는 시작과 동일하며 병합·제품 배포는 없습니다. 공개 Git 객체나 제삼자 복제본의 완전 소거를 보장하지 않습니다.

AT-20·21만 helper 자동 범위 PASS로 변경하여 총 **6 PASS(엔진·helper 범위), 22 BLOCKED, 16 NOT RUN**입니다. G0는 BLOCKED이며, 그림판·Office·메일·메신저 붙여넣기 및 설치·재설치·업데이트·제거는 미실행입니다.

최종 문서 검증: mkdocs strict 빌드 PASS, 공개16페이지+404의 링크·검색·사이트맵·비공개 자산 제외 PASS, 개발 문서 상대 링크47개 누락 없음. 수용시험44행 중복 없음 및6/22/16 집계, CI 업로드23파일의 현재 바이트·SHA-256 일치, 원문 명세 바이트 보존, git diff --check를 확인했습니다. 실행 증거는 artifacts/image-copy-save/helper-final-verification.json에 있습니다. build/build.ps1 및 build/ci.ps1 PowerShell 구문도 오류0입니다. 현재 자체 포함 ZIP 재생성은 이번 helper 단계에서 실행하지 않았습니다.

## 추가 검증: 실제 오류·경계·성능 — 2026-09-25(KST)

| 실행 | 결과 | 관측 |
|---|---|---|
| 36015489668 | 75 PASS / 2 FAIL / 0 NOT RUN | 시험용 ACL 복원 비교 2개 실패 |
| 36016335606 | 75 PASS / 2 FAIL / 0 NOT RUN | ACL 복원 구조·실효 권한 진단 |
| 36017035795 | 77 PASS / 0 FAIL / 0 NOT RUN | 최종 회귀 및 새 시험 모두 통과 |

최종 [JSON](../../artifacts/image-copy-save/ci-extended-36017035795/results.json), 실행별 로그·해시 manifest, [세션·삭제 증거](../../artifacts/image-copy-save/ci-extended-session.json)를 로컬에 보존했습니다. 최초 ACL 복원 실패를 삭제하거나 PASS로 바꾸지 않았습니다. 두 번째 실행에서 원본/복원 ACE의 순서·바이트가 동일하고 실제 접근이 복구됐으며, 차이가 AUTO_INHERITED(0x400)의 0→1에 한정됨을 확인했습니다. [Windows 자동 상속 계약](https://learn.microsoft.com/en-us/windows/win32/secauthz/automatic-propagation-of-inheritable-aces)에 따라 이 변화만 허용하고 DACL null/버전·다른 제어 비트·임시 Deny 제거·실효 접근을 모두 검사하도록 시험 판정을 교정했습니다. exactSddlEqual=false를 그대로 기록하며 보안 설명자가 바이트까지 동일했다고 주장하지 않습니다. 제품 엔진과 ACL 복원 코드는 바꾸지 않았습니다. 원본 보호·사용자 clipboard 미사용 조건을 유지했습니다.

실제 디스크 부족은 새128MiB VHD의 고유 볼륨 ID/label을 확인한 뒤 전용 파일로 채웠습니다. 남은 용량 0바이트에서 4201330바이트 PNG 저장이 오류112로 거절됐고 기존 파일 보존·불완전 파일0·분리 성공을 확인했습니다. 시스템 볼륨은 채우지 않았습니다.

4K 측정은3840×2160, 8비트 straight BGRA gradient/alpha, PNG 266294바이트의 합성 fixture입니다. 예열2회·측정10회이며 모든 픽셀을 매번 비교했습니다. Save에는 encode/flush/commit, Read에는 파일 읽기/decode가 포함됩니다. 검증·삭제·GC는 측정 밖입니다. nearest-rank 기준은 다음과 같습니다.

| 엔진 작업 | P50 (ms) | P95 (ms) |
|---|---:|---:|
| PNG 저장 | 159.0 | 168.7 |
| PNG 읽기 | 27.5 | 28.9 |
| 왕복 | 186.5 | 196.1 |

환경은4 logical processors, AMD64 Family 25 Model 17 Stepping 1, AuthenticAMD, 런타임10.0.12입니다. 실제50M픽셀 허용경계에서도 크기·전체픽셀이 보존됐으나 모든 이미지/메모리 환경의 보장이 아닙니다. 90초 성능시험 제한은 협력적 취소·호출 사이 검사이며 동기WIC의 강제 중단이 아닙니다. helper·메뉴·사용자2초 목표의 합격 근거로 확대하지 않습니다.

AT-19·26·31만 명시한 엔진/helper 범위 PASS로 승격했습니다. 손상 clipboard, 최대 크기, 취소, 성능, 로그 시험의 부분 성공으로 나머지 전체 수용항목을 승격하지 않았습니다. 임시3개 run·artifact·브랜치를 삭제하고 main 불변을 확인했습니다. G0·M2·M3·배포는 여전히 완료되지 않았습니다.
