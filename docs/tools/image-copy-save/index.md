# 그림 복사·저장 · 구현 대응 기록

도구 ID: ImageCopySave · 명세 v1.1 · 상태: 개발 평가, G0 BLOCKED
제품 책임: 도구 개발·검증 담당
적용 정책: [추가 도구 개발 기준](../../policies/tools.md), [문서 작성 규칙](../../policies/documentation.md)
관련 ADR: [ADR-0016](../../design/0016-image-copy-save-direct-menu.md), 과거 [ADR-0015](../../design/0015-image-copy-save-g0.md)

## 사용자와 목적

현재 폴더에 클립보드 그림을 저장하고, 선택한 그림 파일을 이미지 자체로 복사합니다. [원본 명세](ImageCopySave_Requirements_v1.0.md)를 그대로 보존하며, 사용자 승인 메뉴 위치 변경은 [v1.1](ImageCopySave_Requirements_v1.1.md)에 반영했습니다. 제품 완료를 이 기록으로 선언하지 않습니다.

## 요구와 현재 경계

| 요구 | 구현·증거 | 남은 조건 |
|---|---|---|
| MNU/G0 | [native IExplorerCommand 후보·근거](G0_Menu_Feasibility.md) | 실제 폴더 배경 첫 메뉴의 동적 숨김과 설치 실증 |
| IMG/SAV | WIC 코덱·안전 상한·원자적 저장, 실제 helper clipboard→PNG 왕복 PASS | 실제 크기/픽셀 경계·ACL·격리 디스크 부족 PASS; Windows 11 통합·전체 payload/buffer 경계 미완료 |
| CLP/CPY | native 즉시 게시·스냅샷·시퀀스 보호 소스 | Windows Server 관리자 CI에서 격리21개(실제 helper12개) PASS; Windows 11 제품 통합은 미검증 |
| DEP/M2/M3 | full MSIX manifest·unsigned 평가 빌드 후보 | 신뢰 서명·일반 사용자 설치와 실제 메뉴, 호출 시점 sequence 전달·결과 선택·안내 UI 미완료 |

## 데이터·실패·동시 실행

원본 이미지는 읽기 전용입니다. 저장은 별도 앱 소유 임시 파일을 만든 후 덮어쓰기 없는 이름 전환을 합니다. 이름 충돌·16개 병렬 저장·취소·실패 정리·원본 보호를 자동 검증했습니다. 정상 정리는 정확한 소유 파일 핸들만 사용하며 강제 종료 잔재의 패턴 일괄 삭제를 하지 않습니다. 외부 전송·기록 저장소·서비스·클립보드 감시 기능은 없습니다.

## 설치·지원·검증

신뢰되는 서명이 적용된 일반 사용자용 설치 패키지는 아직 없습니다. C#/.NET WPF의 명시적 Windows WIC 코덱으로 독립 엔진을 검증했고, native Shell DLL과 full MSIX 구성은 개정 G0 후보로 작성했습니다. 실제 탐색기 통합은 미검증입니다. 실제 실행한 OS 빌드를 제품 지원 인증으로 확대하지 않습니다.

[개발 소스·빌드 안내](../../../tools/ImageCopySave/README.md), [44개 수용시험 및 실제 결과](../../../tools/ImageCopySave/TEST_RESULTS.md), [알려진 제한](../../../tools/ImageCopySave/KNOWN_LIMITATIONS.md), [설치·제거 현황](../../../tools/ImageCopySave/installer/README.md)에 구현과 미실행을 구분했습니다. 이 문서 및 개발 증거는 공개 사이트 대상이 아닙니다.

## 변경 이력

2026-09-24: M0 조사와 허용된 M1 독립 구현 착수. 메뉴 위치 변경·원격 커밋·배포 없음.

2026-09-24 후속: [원격 클립보드 시험](remote-testing.md)의 이름 지정 권한 문제를 수정하고 자체 포함 시험 패키지를 준비했습니다. 이 세션에서는 오류183으로 9개가 계속 NOT RUN입니다.

2026-09-24 CI 후속: 사용자 승인으로 Codex가 Windows 자동시험을 실행해60개 전체 PASS를 확인했습니다. 시험용 원격 브랜치·3개 실행 기록·3개 산출물은 삭제했고 main/배포는 변경하지 않았습니다. G0 BLOCKED는 유지합니다.

2026-09-24 helper 후속: 총68개 PASS, 실제 helper8개 및32회 병렬 저장 검증. read1418 재현 후 고유 opener HWND 적용으로 회귀 통과. 이번 임시4개 실행·산출물·브랜치는 삭제했습니다. AT-20·21을 helper 범위 PASS로 갱신했으며 G0·외부 앱·설치 검증은 완료하지 않았습니다.

2026-09-25(KST) 추가 검증: 총77개 PASS, 실제 ACL·전용 VHD 디스크 부족·큰 이미지 경계·엔진4K 측정 추가. AT-19·26·31을 명시한 범위로 승격하여9 PASS/22 BLOCKED/13 NOT RUN입니다. 이번3개 임시 실행·artifact·브랜치도 정리했으며 제품 배포 판정은 변경하지 않았습니다.

2026-09-25 위치 변경: 사용자 승인으로 v1.1과 ADR-0016를 작성하고 native DLL·직접 COM 시험 및 unsigned full MSIX 빌드를 추가했습니다. 실제 G0·M2 통합·M3 수명주기 완료와 구분합니다.
