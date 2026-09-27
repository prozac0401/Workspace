# 현재 사용자 클립보드에서 그림 도구 시험하기

- 도구: ImageCopySave 시험 실행기
- 상태: 2026-09-27 사용자가 승인한 순차 실환경 시험 모드의 실행 안내. 구현 자체를 시험 통과로 간주하지 않는다.
- 적용 정책: [추가 도구 개발 기준](../../policies/tools.md), [정책 문서 작성 규칙](../../policies/documentation.md)
- 요구 근거: [v1.1 명세](ImageCopySave_Requirements_v1.1.md), [기존 격리 시험](remote-testing.md), [ADR-0020](../../design/0020-image-current-session-tests.md)
- 공개 범위: 개발·검증용 원본. 공개 사이트의 일반 사용 안내가 아니다.

## 목적과 실행 범위

기본 실행은 새 비대화형 WindowStation을 만드는 기존 격리 시험이다. 현재 PC에서 그 생성이 native 183으로 막혀도 자동으로 사용자 클립보드로 전환하지 않는다. 사용자가 실환경 시험을 선택한 경우에만 아래 두 옵션을 함께 전달한다.

이 모드는 현재 Windows 세션의 보이는 WinSta0\Default에서 기존 23개 클립보드 시나리오와 실제 제품 helper를 실행한다. 제품의 문맥 불일치 방어 시험도 같은 실제 문맥을 기준으로 계속 실행한다. 새 옵션이 제품 동작이나 사용 시 권한을 바꾸지는 않는다.

시험은 기존 클립보드를 합성 이미지·텍스트·빈 상태·손상된 합성 데이터로 덮어쓴다. 원래 내용을 읽어 백업하거나 시험 후 복원하지 않는다. 다른 프로그램의 임의 형식을 완전히 복원한다고 약속하지 않는다. 시험 중 다른 복사 작업을 하지 않는다. Windows 클립보드 기록·동기화와 다른 앱의 설정은 바꾸지 않는다.

## 안전한 모드 계약 확인

먼저 아래 명령으로 인수 처리와 중복 실행 차단을 확인한다. 이 전용 모드는 클립보드 API를 호출하거나 제품 helper를 시작하지 않는다. 실제 기능시험의 통과 근거가 되지는 않는다.

~~~powershell
./tools/ImageCopySave/build/build.ps1 -DotNet ./.tools/dotnet/dotnet.exe -ModeContractTests
~~~

이미 빌드된 실행 파일에서는 다음처럼 실행할 수 있다.

~~~powershell
$tests = './tools/ImageCopySave/source/ImageCopySave.Tests/bin/Release/net10.0-windows/ImageCopySave.Tests.exe'
& $tests --mode-contract-tests --report ./artifacts/image-copy-save/clipboard-mode-contract-results.json
& $tests --list-clipboard-cases
~~~

계약 검사에는 기본 격리, 옵션 한쪽 누락·중복·잘못된 조합 거절, 단일 시나리오 검증, WinSta0/Default 문맥 판정, 활성 조정자 없는 worker 거절, 동일 세션의 두 번째 조정자 거절이 포함된다. 계약 검사와 실제 클립보드 실행 옵션은 함께 사용할 수 없다.

## 단일 시나리오부터 순차 실행

다음 명령은 실제 사용자 클립보드를 덮어쓰는 명시적 실행이다.

~~~powershell
./tools/ImageCopySave/build/build.ps1 -DotNet ./.tools/dotnet/dotnet.exe -UseCurrentClipboard -AcknowledgeClipboardOverwrite -ClipboardCase alpha-roundtrip
~~~

단일 시나리오가 끝난 뒤 전체 시험을 실행한다. 결과 파일을 실행별 경로로 보존하려면 빌드된 실행 파일을 직접 사용한다.

~~~powershell
$tests = './tools/ImageCopySave/source/ImageCopySave.Tests/bin/Release/net10.0-windows/ImageCopySave.Tests.exe'
$helper = (Resolve-Path './tools/ImageCopySave/source/ImageCopySave.Helper/bin/Release/net10.0-windows/ImageCopySave.Helper.exe').Path
& $tests --use-current-clipboard --acknowledge-clipboard-overwrite --clipboard-case alpha-roundtrip --helper $helper --report ./artifacts/image-copy-save/current-session-alpha.json
& $tests --use-current-clipboard --acknowledge-clipboard-overwrite --helper $helper --report ./artifacts/image-copy-save/current-session-full.json
~~~

-ClipboardCase / --clipboard-case는 지정된 클립보드 시나리오 한 개만 실행한다. 현재 사용자 옵션이 없으면 단일 시나리오도 기존 격리 경로에서 실행한다. 옵션 두 개 중 하나라도 없으면 사용법 오류(exit 64)로 끝나며 시험을 시작하지 않는다.

## 동시 실행·중단 처리

조정자는 현재 Windows 세션의 이름 있는 mutex Local\ImageCopySave.Tests.CurrentClipboard를 시험 종료까지 보유한다. 두 번째 조정자는 기다리거나 격리 모드로 바꾸지 않고 NOT RUN으로 끝난다. 내부 worker는 실행별 토큰과 살아 있는 조정자의 mutex를 확인하고, 매 프로세스에서 실제 station과 desktop을 검증한 후에만 클립보드에 접근한다. 조정자의 프로세스 job은 시험 worker와 그 자식 프로세스만 소유하며 중단 시 해당 트리를 종료한다. 정리 시 직접 자식의 종료뿐 아니라 job의 ActiveProcesses가 0인지 최대 5초 동안 확인한다. 종료·확인·핸들 정리 중 문제가 생기면 가능한 정리를 모두 시도하고 현재 시험을 실패로 기록한다. 조정자가 정리 완료를 확인하지 못하면 이후 클립보드 시나리오는 NOT RUN으로 건너뛰어 앞선 worker와 겹치지 않게 한다.

시나리오는 순차 진행한다. 기존 product-parallel-save 시나리오 내부의 합성 병렬 저장은 충돌 시험이므로 유지한다. 이 mutex는 사용자나 다른 앱의 복사를 막지 않는다. 외부 복사 간섭으로 실패하면 그대로 기록하며 성공으로 바꾸지 않는다. 중단·실패 후에도 이전 클립보드를 자동 복원하지 않는다.

## 결과 해석

보고서는 시험 이름을 “clipboard current-session …”으로 구분하고 clipboardContext, clipboardOverwriteAcknowledged, clipboardRestoreAttempted, clipboardCoordinator, testScope, selectedClipboardCase를 기록한다. 현재 사용자 모드와 단일 시나리오는 미실행 항목이 있으면 성공 종료하지 않는다. 실패 exit 1, 전제 미충족 exit 2, 사용법 오류 exit 64를 구분한다.

testScope=single-clipboard-case 결과는 전체 시험 결과가 아니다. mode-contracts-no-clipboard-access는 모드 정책만 확인한다. 기본 격리 시험 기록과 현 사용자 시험 기록을 별도 파일로 보존한다. current-session 모드의 이미지 불일치 메시지에는 외부 앱에서 들어왔을 수 있는 실제 픽셀 바이트를 기록하지 않는다.

전체 자동시험에 포함된 실제 디스크 부족 시험은 기존 GitHub-hosted 전용 전제를 유지한다. 로컬에서는 이를 NOT RUN으로 남길 수 있으며 환경변수를 가장하지 않는다. 실제 탐색기 첫 메뉴, 외부 앱 붙여넣기, MSI 설치 수명주기는 이 시험 실행기로 통과 처리하지 않는다. native183 복구 완료 여부와도 구분한다.

2026-09-27: 사용자 승인에 따라 명시적인 현 사용자 클립보드 시험 모드와 실행 안내를 추가했다. 실행 결과는 실행별 JSON 및 별도의 검증 기록을 기준으로 한다.
