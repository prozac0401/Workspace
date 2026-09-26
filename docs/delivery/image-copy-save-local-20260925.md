# 그림 복사·저장 · 로컬 통합 후보 인계

도구 ID: ImageCopySave · 버전: 0.1.1.0 평가 후보 · 기록일: 2026-09-25  
상태: **로컬 빌드·패키지 검사 완료, G0/실사용 검증 전**  
책임: 도구 개발·검증 담당  
적용: [도구 정책](../policies/tools.md), [문서 정책](../policies/documentation.md)  
요구·결정: [v1.1](../tools/image-copy-save/ImageCopySave_Requirements_v1.1.md), [ADR-0017](../design/0017-image-copy-save-invocation.md)

## 완료한 작업

현재 작업 폴더에서 탐색기 호출 기준값을 helper/worker까지 전달하고, 저장 결과를 호출한 보기로 연결했다. 시작이 지연되는 동안 클립보드가 바뀌면 오래된 명령을 중단한다. 별도 worker의 이미지 처리·제한시간·취소를 유지하며, 콘솔 없는 진행·취소·성공·오류 안내를 추가했다. 결과 전달 실패가 이미 완료한 저장을 실패로 바꾸지 않도록 처리했다.

같은 보기 선택은 호출 폴더의 직접 하위 PNG만 허용하고 보기 HWND·현재 폴더·가시성·전경 루트를 재확인한다. 다른 창을 탐색해 저장 위치를 추측하거나 새 창을 열지 않는다. 실제 창·탭에서의 동작은 아직 확인하지 않았다.

MSVC/SDK는 공식 다운로드의 해시·서명을 검사하여 `.tools/image-copy-save-native` 안에 준비했다. 새 Git 작업 트리, 원격 CI, 원격 게시, 시스템 개발 도구 설치는 수행하지 않았다. 다른 도구의 기존 변경사항도 수정하지 않았다.

## 실제 검증

| 항목 | 결과 | 범위와 제한 |
|---|---|---|
| 엔진/helper Release 빌드 | PASS, 경고0·오류0 | SDK10.0.401 |
| 엔진/helper 자동시험 | **62 PASS / 0 FAIL / 24 NOT RUN** | 총86개. private clipboard23개는 생성 오류183, 전용 VHD1개는 로컬 실행 제외 |
| native DLL/시험 로컬 빌드 | PASS | MSVC19.41.34123, SDK10.0.26100.0, x64 static CRT, 경고 오류 처리 |
| native 정책·직접 COM | **66 PASS / 0 FAIL** | 실제 Invoke·Explorer·클립보드·설치 없음 |
| WPF 안내 3종 | 렌더·육안 PASS | 창을 띄우지 않아 실제 포커스/취소 입력의 증거가 아님 |
| MSIX 생성·해제·내용 대조 | PASS | 자체 포함 helper/native, 입력408개 해시 일치, unsigned |
| 설치용 스크립트 검사 | PASS | PS5 구문, manifest 검사, unsigned/다른 Publisher/다른 cert 거절, 설치 없음 확인 |
| 문서 strict 빌드·공개 링크 검사 | PASS | 공개16페이지+404, 비공개 자료 제외·로컬 경로/자산 확인 |
| 실제 Explorer G0·앱 붙여넣기·수명주기 | **NOT RUN** | 사용자 실기 필요 |

최신 로컬 일괄 빌드의 증거는 `artifacts/image-copy-save/automated-results.json`, `native-shell/shell-results.json`, `native-shell/build-metadata.json`, `native-toolchain-verification.json`, `package-evaluation/package-result.json`, `packaging-local-preflight.json`, `local-final-build.log`이다. helper 개발 단계의 같은62/86개 결과는 `helper-finish-results.json`에 보존한다. 패키지에 들어간 자체 포함 helper의 비표시 렌더링도 종료0으로 확인했다. 인증서 상세와 로컬 진단은 공개 사이트에 넣지 않는다. 이전 CI의77/63개 PASS는 이전 소스의 별도 이력이다.

## 패키지와 다음 단계

패키지는 `artifacts/image-copy-save/package-evaluation`에 생성했다. 인계용 [unsigned MSIX](../../artifacts/image-copy-save/delivery-0.1.1/ImageCopySave-0.1.1-unsigned.msix)는 동일 바이트 복사본이다. 크기64,318,517bytes, SHA256은 `14343A24A46047ABF9F87D4C12427315D798049B75DAAD2CDCBBBE87FDAE3A10`이다. 평가 identity는 `ImageCopySave.Evaluation`, 버전은 `0.1.1.0`이며 파일 제품명·버전도 일치한다. 관리코드 게시 전후 소스 해시 일치, native 시험 대상 DLL/소스 해시 일치, 패키지 내408개 입력 파일 일치를 확인했다.

local candidate Publisher는 기존 코드서명 인증서와 일치하도록 준비했지만, 인증서 사용과 현재 사용자 설치 확인을 요청한 상태이며 실제 서명·설치는 아직 수행 전이다. 자체 발급 인증서가 이 PC에서 신뢰된다는 검사 결과를 다른 PC의 신뢰나 상용 배포 승인으로 확대하지 않는다. 사용자 요청 없이 새 인증서를 신뢰시키거나 개발자 모드를 켜지 않는다.

1. 기존 인증서를 사용하는 서명·현재 사용자 설치의 확인을 받는다. 신뢰 저장소·개발자 모드를 바꾸지 않는다.
2. [PC 확인 안내](../tools/image-copy-save/local-verification.md)에 따라 첫 메뉴·이미지 없음 완전 숨김, 창/탭·붙여넣기·제거/재설치를 실제 확인한다.
3. 실기 결과와 앱 버전을 시험표에 반영한 뒤 G0·배포 가능 여부를 판정한다. 미실행 항목을 완료로 바꾸지 않는다.

소스·빌드·문서 정리는 이번 범위에서 진행했으나, 위 실기와 설치 조건을 확인하기 전에는 **제품 출시 완료로 판정하지 않는다**. 현재 패키지는 평가용이며 공개 사이트나 Release에 게시하지 않았다.
