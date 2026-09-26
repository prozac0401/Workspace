# 그림 복사·저장 · 로컬 통합 평가 후보

**탐색기 명령과 helper의 호출 상태·결과·비모달 안내를 연결했습니다. 현재 PC의 실제 MSIX 설치가 신뢰 오류로 차단되어 G0는 BLOCKED입니다.** 2026-09-27 기존 허용 인증서 서명은 통과했지만 설치는 `0x800B0109`로 거절됐고 현재 사용자 등록은 0개입니다. [설치 시도 기록](../../docs/delivery/image-copy-save-signing-20260927.md)을 확인하세요. 저장은 실제 폴더 배경의 첫 우클릭 메뉴를 대상으로 하며 이미지가 없을 때 완전히 숨기는 조건은 유지합니다. 일반 사용자용 출시 완료를 뜻하지 않습니다.

- [현재 요구명세 v1.1](../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.1.md) · [메뉴 위치 결정](../../docs/design/0016-image-copy-save-direct-menu.md)
- [원본 요구명세](../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.0.md)
- [G0 판정](G0_Menu_Feasibility.md) · [시험 결과 및 44개 수용시험](TEST_RESULTS.md) · [제한사항](KNOWN_LIMITATIONS.md)
- [설치·제거 상태](installer/README.md)
- [이 PC에서 마지막으로 확인하기](../../docs/tools/image-copy-save/local-verification.md) · [호출 상태·결과 연결 결정](../../docs/design/0017-image-copy-save-invocation.md)
- [원격 클립보드 시험 실행 방법](../../docs/tools/image-copy-save/remote-testing.md)

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

## native 메뉴와 평가 MSIX 빌드

C++ x64 빌드 도구와 Windows 11 SDK가 갖추어진 개발 환경에서 다음 순서로 실행합니다.

```powershell
powershell.exe -NoProfile -NonInteractive -File ./tools/ImageCopySave/build/build-shell.ps1
powershell.exe -NoProfile -NonInteractive -STA -File ./tools/ImageCopySave/build/build-package.ps1 -DotNet dotnet
```

첫 명령은 native DLL과 정책·직접 COM 시험 66개를 빌드/실행합니다. 두 번째 명령은 자체 포함 helper와 DLL을 unsigned full MSIX로 묶고 다시 풀어 내용·해시를 확인합니다. OS 등록·설치·서명·신뢰 변경은 수행하지 않습니다. 상세 의존성, 산출물, 신뢰된 패키지의 설치·제거 절차는 [패키징 안내](installer/README.md)에 있습니다.

GetState는 호출한 보기의 로컬 폴더 문맥과 클립보드 지원 형식만 확인합니다. 실제 첫 메뉴의 표시/숨김·클립보드 갱신·Invoker 문맥은 직접 COM 시험으로 증명하지 않습니다. [native 구현 경계](source/ImageCopySave.Shell/README.md)를 확인하세요.

## 개발용 helper 실행

아래는 엔진 재현용 명령이며 최종 사용자 UX를 대체하지 않습니다. `copy`는 실제 현재 사용자의 클립보드를 바꿉니다. `save`는 지정 폴더에 PNG를 만듭니다. 자동 시험은 별도 window station을 확보한 경우에만 클립보드를 바꾸며, 격리 생성에 실패하면 시험을 건너뛰고 이유를 남깁니다.

```powershell
./artifacts/image-copy-save/engine-evaluation/ImageCopySave.Helper.exe --probe-formats
./artifacts/image-copy-save/engine-evaluation/ImageCopySave.Helper.exe copy "D:\시험\그림.png"
./artifacts/image-copy-save/engine-evaluation/ImageCopySave.Helper.exe save "D:\시험"
```

명령의 형식 조회는 이미지 내용을 읽지 않습니다. 작업은 별도 프로세스로 실행되며 15초 후 취소 요청, 1초 유예 후 응답하지 않는 자기 worker만 종료합니다. Ctrl+C도 먼저 협력 취소를 요청합니다. 강제 종료 시 이미 완료된 커밋 여부가 불확실할 수 있어 무변경을 보장하지 않습니다. 부모와 내부 worker는 같은 window station·desktop인지 확인하며 불일치하면 파일·클립보드 작업 전에 중단합니다.

## 다음 단계

G0에서 개정 위치·동적 숨김·첫 메뉴·일반 사용자 설치를 실제 증명해야 M2 제품 통합과 M3 설치 수명주기를 완료할 수 있습니다. Invoke 시퀀스 전달, 같은 보기 선택, 비모달 진행·취소·오류 안내는 구현했으나 실제 Explorer에서의 통합 검증은 남아 있습니다. 신뢰되는 서명과 일반 사용자 설치, 외부 앱 붙여넣기를 [PC 확인 절차](../../docs/tools/image-copy-save/local-verification.md)로 검증해야 합니다. unsigned MSIX 생성은 설치·제거 합격을 의미하지 않습니다. 새 Git 작업 트리·원격 CI·제품 게시 없이 현재 로컬 작업 폴더에서 진행했습니다. 아래 CI 내용은 이전 실행 이력입니다.

최신 로컬 시험은 엔진/helper **62 PASS / 24 NOT RUN / 0 FAIL**, native **66 PASS / 0 FAIL**입니다. 격리 클립보드 23개는 station 생성 오류로, 전용 VHD 디스크 부족 1개는 로컬 실행 제외로 남았습니다. 사용자 클립보드는 변경하지 않았습니다. WPF 안내 화면 3종은 비표시 렌더링으로 확인했습니다. [이번 인계 기록](../../docs/delivery/image-copy-save-local-20260925.md)에 최종 산출물과 직접 확인할 단계를 모았습니다.

## Windows CI 검증 현황

2026-09-24~25(KST) 승인된 임시 Windows CI에서 **77 PASS / 0 FAIL / 0 NOT RUN**을 확인했습니다. 격리 clipboard21개 중 실제 제품 helper12개를 포함합니다. 새 시험은 다른 helper의 복사 뒤 스냅샷 저장·새 내용 보존, 오래된 copy 거부, 손상 clipboard, 내부 취소, 실제 ACL 거부·전용 VHD 디스크 부족, 실제 크기 경계, 4K 엔진 P50/P95입니다.

oplock 이벤트는 원인 PID를 제공하지 않아 취소의 정확한 helper 처리 단계는 확정하지 않습니다. 실제 helper4개×8회 병렬 저장과 기존 투명도·원본 보호 회귀도 포함합니다. [검증 기록](TEST_RESULTS.md)에 실패 이력과 부분 검증 범위를 기록했습니다.

이 77개 시험 단계의 임시 3개 실행 기록·artifact·시험 브랜치는 삭제했고 main은 그대로입니다. G0·Windows 11 일반 사용자·외부 앱 붙여넣기·설치/제거 검증은 남아 있습니다.

확장 시험은 새 시험용 파일의 ACL을 잠시 바꾸고 복원하며, 최대50M픽셀 입력을 순차 처리합니다. 큰 이미지 시험은3GiB 메모리 여유가 없으면 NOT RUN입니다. 실제 디스크 부족은 명시적으로 허용된 일회용 GitHub-hosted Windows 관리자 CI에서만 새128MiB VHD를 만들고 실행하며 로컬/시스템 디스크로 대체하지 않습니다. 자세한 재현 조건은 [자동시험 안내](../../docs/tools/image-copy-save/remote-testing.md)를 참조하세요.

2026-09-25 메뉴 후보 후속: native 정책·직접 COM **63개 PASS**를 Windows CI와 로컬 Windows 11에서 각각 확인했습니다. unsigned full MSIX 생성·해제·408개 입력 파일 해시 검사도 PASS입니다. 실제 메뉴·Invoke·서명·설치는 NOT RUN이며 기존77개 엔진/helper 시험은 이번에 재실행하지 않았습니다. 이번 임시2개 실행·artifact·브랜치를 삭제하고 main 불변을 확인했습니다.
