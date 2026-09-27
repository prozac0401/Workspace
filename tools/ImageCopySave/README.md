# 그림 복사·저장 · 클래식 메뉴 통합 평가 후보

현재 요구는 **공통 클래식 메뉴**입니다. Windows 11 기본 메뉴에서는 ‘더 많은 옵션 표시’ 뒤에, Windows 10 스타일의 클래식 직접 표시 설정에서는 바로 ‘복사한 그림 저장’과 ‘그림으로 복사’에 접근합니다. 이미지가 없을 때 저장 항목을 완전히 숨기고 상주 감시기를 두지 않는 조건은 유지합니다.

[ADR-0023](../../docs/design/0023-image-copy-save-classic-menu.md)에 따라 native IExplorerCommand·ExplorerCommandHandler의 HKLM 등록을 무서명 관리자 MSI가 관리하는 경로를 구현·검증합니다. 평소 Explorer/helper는 일반 사용자 권한으로 실행합니다. 2026-09-27 후속 중간 실기에서 클래식 직접 표시 모드의 독립 저장·비이미지 및 실제 파일 클립보드 완전 숨김·실제 PNG 저장과 이미지 복사, 무서명 자체 포함 MSI의 설치·Repair·업데이트·제거·설치 실패 롤백·재설치는 확인한 시나리오에서 PASS입니다. 앞선 0.1.0 실제 저장의 설치 helper·Explorer 비상승 실행도 확인했습니다. 현재 0.1.1 설치 상태입니다. 기존 0.1.0 근거에 더해 0.1.1에서도 메뉴 상태 전환, 시험 폴더 A의 실제 8×8 PNG 저장·클립보드 불변과 선택 PNG의 실제 이미지 복사를 별도로 확인했습니다. 두 모드 전체 G0는 **미완료**입니다. [현재 매트릭스](../../docs/tools/image-copy-save/G0_Menu_Feasibility.md)에 수행 범위와 로컬 근거를 구분했습니다.

사용자의 “불필요한 반복테스트는 지양하도록 합니다.” 지시에 따라 고정 20회 반복을 완료 관문에서 제외합니다. 미확인 기능의 대표 1회와 실패·변경에 관련된 재시험만 수행합니다. 이미 확인한 횟수와 결과는 보존하며 나머지 반복은 ‘사용자 지시에 따라 반복 생략’으로 기록하고 제품 실패나 필수 잔여로 처리하지 않습니다. 기본 Windows 11 메뉴 경로와 설정 원상복구는 필수로 유지합니다.

이번 검증에서 사용자가 승인한 임시 메뉴 모드 전환은 종료 후 원상복구합니다. 제품 설치기는 사용자의 메뉴 모드를 바꾸지 않습니다. Windows 11의 클래식 직접 표시를 실제 Windows 10 OS 지원 인증으로 표기하지 않습니다.

- [현재 요구명세 v1.2 변경 계약](../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.2.md) · [현재 메뉴·설치 결정](../../docs/design/0023-image-copy-save-classic-menu.md)
- [v1.0 원본](../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.0.md) · [v1.1 당시 요구](../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.1.md)
- [현재 G0 매트릭스](G0_Menu_Feasibility.md) · [시험 결과 및 44개 수용시험](TEST_RESULTS.md) · [제한사항](KNOWN_LIMITATIONS.md)
- [설치·제거 상태](installer/README.md) · [관리자 설치·일반 사용자 실행 결정](../../docs/design/0022-image-admin-install.md)
- [호출 상태·결과 연결](../../docs/design/0017-image-copy-save-invocation.md) · [현재 사용자 클립보드 시험](../../docs/tools/image-copy-save/current-session-testing.md)

앞선 첫 Windows 11 메뉴 후보의 관리자 unsigned sparse 등록·정리와 SYSTEM 진단 MSI·비상승 사용자 등록은 [당시 기록](../../docs/delivery/image-admin-install-20260927.md)에 보존합니다. 더 이전의 비상승 unsigned sparse 0x80073D2B와 signed full MSIX 신뢰 오류 0x800B0109도 당시 경로의 결과입니다. 이 오류를 새 클래식 경로의 현재 차단으로 재사용하지 않으며, 새 제품 MSI 완료나 상용 출시를 선언하지 않습니다.

## 구현 범위

Windows 내장 WIC 코덱을 쓰는 PNG/JPEG/BMP 읽기, EXIF 방향 정규화, 투명도 보존 PNG 인코딩, 안전 상한, 클립보드 스냅샷·즉시 이미지 게시, 충돌 없는 PNG 저장을 분리했습니다. 읽을 때 원본을 변경하지 않고, 저장할 때 클립보드를 교체하지 않습니다. 지원하는 세부 이미지 형식은 제한사항을 확인하세요.

저장 엔진은 앱 소유 임시 파일에 쓰고 flush한 후 파일 핸들로 덮어쓰기 없이 이름을 바꿉니다. 정상 오류·협력 취소 시 해당 핸들만 정리합니다. 강제 종료·전원 차단 시 임시 파일 잔재가 가능하며, 이름 패턴으로 일괄 삭제하지 않습니다.

## 빌드와 자동 시험

Windows x64, .NET SDK 10.0.401 또는 global.json이 허용하는 패치가 필요합니다. 이 개발자 요구는 향후 일반 사용자 설치 요구가 아닙니다. SDK8만 있는 환경에서는 빌드되지 않습니다.

저장소 루트의 PowerShell에서 실행합니다.

```powershell
./tools/ImageCopySave/build/build.ps1 -DotNet ./.tools/dotnet/dotnet.exe
# 일반 설치된 SDK10을 쓰는 경우
./tools/ImageCopySave/build/build.ps1
```

빌드 스크립트는 helper 빌드와 시험을 실행하고 `artifacts/image-copy-save/automated-results.json`에 실제 결과를 기록합니다. 환경 때문에 미실행된 시험은 NOT RUN이며 빌드 성공이 제품 출시 가능을 의미하지 않습니다.

개발용 자체 포함 실행 파일을 만들려면 `-PublishEvaluation`을 추가합니다. 출력은 `artifacts/image-copy-save/engine-evaluation`이며 사용자용 설치 패키지가 아닙니다. 원격 게시나 OS 메뉴 등록을 하지 않습니다.

## native 빌드와 이전 MSIX 평가 도구

C++ x64 빌드 도구와 Windows SDK가 갖추어진 개발 환경에서 native DLL을 빌드합니다. 아래 두 번째 명령의 full MSIX는 이전 첫 메뉴 후보의 평가 도구이며 새 클래식 제품 MSI의 설치 의존성이 아닙니다. 새 MSI의 빌드·설치 절차와 실제 상태는 [설치 안내](installer/README.md)에 기록합니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File ./tools/ImageCopySave/build/build-shell.ps1
powershell.exe -NoProfile -NonInteractive -STA -File ./tools/ImageCopySave/build/build-package.ps1 -DotNet dotnet
```

첫 명령은 native DLL과 정책·직접 COM 시험 66개를 빌드/실행합니다. 두 번째 명령은 자체 포함 helper와 DLL을 unsigned full MSIX로 묶고 다시 풀어 내용·해시를 확인합니다. OS 등록·설치·서명·신뢰 변경은 수행하지 않습니다. 상세 의존성, 산출물, 신뢰된 패키지의 설치·제거 절차는 [패키징 안내](installer/README.md)에 있습니다.

GetState는 호출한 보기의 로컬 폴더 문맥과 클립보드 지원 형식만 확인합니다. 실제 클래식 메뉴 두 진입 모드의 표시/숨김·클립보드 갱신·Invoker 문맥은 직접 COM 시험으로 증명하지 않습니다. [native 구현 경계](source/ImageCopySave.Shell/README.md)를 확인하세요.

## 개발용 helper 실행

아래는 엔진 재현용 명령이며 최종 사용자 UX를 대체하지 않습니다. `copy`는 실제 현재 사용자의 클립보드를 바꿉니다. `save`는 지정 폴더에 PNG를 만듭니다. 기본 격리 시험은 별도 window station 생성 실패 시 이유를 남기고 건너뛰며 자동 전환하지 않습니다. 명시적인 두 동의 옵션으로 현재 사용자 클립보드 시험을 별도 실행할 수 있습니다.

```powershell
./artifacts/image-copy-save/engine-evaluation/ImageCopySave.Helper.exe --probe-formats
./artifacts/image-copy-save/engine-evaluation/ImageCopySave.Helper.exe copy "D:\시험\그림.png"
./artifacts/image-copy-save/engine-evaluation/ImageCopySave.Helper.exe save "D:\시험"
```

명령의 형식 조회는 이미지 내용을 읽지 않습니다. 작업은 별도 프로세스로 실행되며 15초 후 취소 요청, 1초 유예 후 응답하지 않는 자기 worker만 종료합니다. Ctrl+C도 먼저 협력 취소를 요청합니다. 강제 종료 시 이미 완료된 커밋 여부가 불확실할 수 있어 무변경을 보장하지 않습니다. 부모와 내부 worker는 같은 window station·desktop인지 확인하며 불일치하면 파일·클립보드 작업 전에 중단합니다.

## 다음 단계

개정 G0의 남은 시험은 기본 새 메뉴의 ‘더 많은 옵션 표시’ 경로와 미확인 기능의 대표 사례, 복수 창·탭 문맥·피드백 전체입니다. 클래식 전환은 15회·46개 관찰 행 모두 PASS이며 1~8회는 0.1.0, 9~15회는 0.1.1에서 수행했습니다. 02:53 UTC에는 새 시험 Explorer 창에서 기존 창 활성화 실패 이후 관찰을 이어갔고 그 시점의 기존 창·Explorer 프로세스를 보존했습니다. 16~20회는 사용자 지시에 따라 반복 생략합니다. 실행한 버전별 범위를 구분하며 payload 동일성으로 실기를 대신하지 않습니다. 이 모드에서 확인한 합성 8×8 PNG 저장·클립보드 불변, PNG 실제 이미지 복사, Explorer Ctrl+C의 파일 클립보드에서 저장 숨김·일반 Paste 유지를 그 범위의 근거로 유지합니다.

제품 MSI 0.1.0 설치·손상 DLL Repair, 0.1.0→0.1.1 업데이트, 제거·깨끗한 상태의 의도된 설치 실패 롤백·0.1.1 재설치는 PASS입니다. 실패 주입 단계의 예상 exit 1603 뒤 제품 설치·등록이 남지 않았으며 나머지는 exit 0이었습니다. 모든 단계에 재부팅 요구와 Explorer 재시작이 없었고 합성 보존 PNG 해시를 유지했습니다. MSI 전체 절차 후 합성 시험 원본 3개의 SHA-256도 불변입니다. 현재 0.1.1 설치 상태이며 임의 외부 파일·타사 메뉴 보존 전체와 최종 정리는 남아 있습니다. 후속 승인된 모드 시험에서 HKCU override를 백업·이동하고 03:05 UTC에 Explorer를 한 차례 수동 재시작했으며 Workspace 창 경로를 복원했습니다. 이 재시작은 제품 설치기의 동작이 아닙니다. 기본 새 메뉴의 ‘더 많은 옵션 표시’ 경로는 여전히 미확인입니다. 03:11 중간 복원과 03:21 재진입 후 03:27:33 UTC에 원본 키·값·Owner·Group·DACL 보존, 백업 키 제거와 journal RESTORED를 확인해 최종 설정 복원은 PASS입니다.

재시작 후 두 번째 배경 우클릭에서 실제 Explorer ‘응답 없음’을 관찰했고 이후 자체 회복했습니다. 단일 최소덤프의 95개 스레드에서 제품 DLL 프레임 0개와 메뉴 메시지 대기를 관찰했지만 단일 시점·심볼 제약 때문에 원인은 미확정입니다. 제품 무관이나 자동화만의 문제로 단정하지 않습니다. 물리 우클릭 비교 결과를 확보하지 못해 해당 요청과 추가 재시도는 중단했습니다. 진단과 복원의 로컬 근거는 [G0 기록](../../docs/tools/image-copy-save/G0_Menu_Feasibility.md)에 연결했습니다.

최초 업그레이드 요청의 UAC 취소는 이후 실제 업데이트 PASS와 구분합니다. 그 실제 업데이트 뒤 시험 실행기가 UTF-8·빈 JSON 키가 있는 결과를 읽다가 중단된 이력을 보존했고, Dictionary 처리 수정과 실제 결과 읽기 회귀 PASS 후 나머지 3단계를 재승인하여 완료했습니다. 제품 업데이트 실패로 오기하지 않습니다. M2·M3 또는 제품 배포 가능 상태는 전체 인수 전이며 아래 로컬/CI 결과는 이전 후보의 실행 이력입니다.

2026-09-25 당시 로컬 시험은 엔진/helper **62 PASS / 24 NOT RUN / 0 FAIL**, native **66 PASS / 0 FAIL**입니다. 격리 클립보드 23개는 station 생성 오류로, 전용 VHD 디스크 부족 1개는 로컬 실행 제외로 남았습니다. 사용자 클립보드는 변경하지 않았습니다. WPF 안내 화면 3종은 비표시 렌더링으로 확인했습니다. [이번 인계 기록](../../docs/delivery/image-copy-save-local-20260925.md)에 최종 산출물과 직접 확인할 단계를 모았습니다.

## Windows CI 검증 현황

2026-09-24~25(KST) 승인된 임시 Windows CI에서 **77 PASS / 0 FAIL / 0 NOT RUN**을 확인했습니다. 격리 clipboard21개 중 실제 제품 helper12개를 포함합니다. 새 시험은 다른 helper의 복사 뒤 스냅샷 저장·새 내용 보존, 오래된 copy 거부, 손상 clipboard, 내부 취소, 실제 ACL 거부·전용 VHD 디스크 부족, 실제 크기 경계, 4K 엔진 P50/P95입니다.

oplock 이벤트는 원인 PID를 제공하지 않아 취소의 정확한 helper 처리 단계는 확정하지 않습니다. 실제 helper4개×8회 병렬 저장과 기존 투명도·원본 보호 회귀도 포함합니다. [검증 기록](TEST_RESULTS.md)에 실패 이력과 부분 검증 범위를 기록했습니다.

이 77개 시험 단계의 임시 3개 실행 기록·artifact·시험 브랜치는 삭제했고 main은 그대로입니다. G0·Windows 11 일반 사용자·외부 앱 붙여넣기·설치/제거 검증은 남아 있습니다.

확장 시험은 새 시험용 파일의 ACL을 잠시 바꾸고 복원하며, 최대50M픽셀 입력을 순차 처리합니다. 큰 이미지 시험은3GiB 메모리 여유가 없으면 NOT RUN입니다. 실제 디스크 부족은 명시적으로 허용된 일회용 GitHub-hosted Windows 관리자 CI에서만 새128MiB VHD를 만들고 실행하며 로컬/시스템 디스크로 대체하지 않습니다. 자세한 재현 조건은 [자동시험 안내](../../docs/tools/image-copy-save/remote-testing.md)를 참조하세요.

2026-09-25 메뉴 후보 후속: native 정책·직접 COM **63개 PASS**를 Windows CI와 로컬 Windows 11에서 각각 확인했습니다. unsigned full MSIX 생성·해제·408개 입력 파일 해시 검사도 PASS입니다. 실제 메뉴·Invoke·서명·설치는 NOT RUN이며 기존77개 엔진/helper 시험은 이번에 재실행하지 않았습니다. 이번 임시2개 실행·artifact·브랜치를 삭제하고 main 불변을 확인했습니다.
