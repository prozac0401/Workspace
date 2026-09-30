# DownloadVersionManager · 최초 제품 명세

도구 ID: DownloadVersionManager · 제품 버전: 0.1.0 · 상태: 구현·평가, stable 인수 미완료  
원본 요구: 2026-09-30 사용자의 DownloadVersionManager 개발·시험·패키징·조건부 릴리즈 지시(0–33절). 조직 배포 설정·스토어 게시 계정·서명 주체는 미결정.  
정책: [추가 도구 개발 기준](../../policies/tools.md), [문서 작성 규칙](../../policies/documentation.md) · [ADR-0026](../../design/0026-download-version-manager.md)

## 목적과 데이터 경계

확정 목표는 Chrome/Edge를 통해 가장 최근에 다운로드한 신규 파일 자체가 원래 logical filename을 갖도록 하는 것이다. byte-for-byte 다른 이전 내용만 해당 parent의 `_history`에 보존하며 idle Windows native process는 0개여야 한다. 현재 구현은 동일 target을 안전하게 직렬화하지만 동시 완료의 최종본을 mutex 처리 순서로 정한다. 브라우저 전체 완료 시각 순서를 보장하지 못하는 차이는 아래 지원 제한과 검증 기록에 남기며 목표를 충족했다고 확대하지 않는다.

Host가 읽는 대상은 요청의 신규 파일과 같은 parent의 기존 target 기본 데이터 스트림 둘뿐이다. 쓸 수 있는 대상은 이 두 객체의 이름·시간, 새 History directory와 충돌 없는 이전 객체의 이름이다. parent ancestor는 reparse 검사와 이름 이동 차단을 위해 핸들로 확보하되 자식들을 열거하지 않는다. 기존 사용자 History·다른 문서·폴더·브라우저 profile 설정은 소유하지 않는다.

| 요구 ID | 확정 행동 | 완료 기준·시험 |
|---|---|---|
| REQ-DVM-001 | 원래 이름은 onDeterminingFilename에서 기억 | 원래 `(1)`/`(2)` 이름 시험, suffix에서 역추론 없음 |
| REQ-DVM-002 | MV3 event + sendNativeMessage one-shot | keepalive/port/watcher/service/tray/polling 없음, 실제 idle 0 |
| REQ-DVM-003 | 크기 먼저, 같으면 64 KiB streaming SHA-256 | 크기 다름 hashBytes 0, 같음 2×길이, empty/큰 파일 |
| REQ-DVM-004 | 동일 내용도 신규 객체가 이름 승계 | file ID·creation/write time가 신규 객체와 일치, History 생성 없음 |
| REQ-DVM-005 | 다르면 이전 객체만 History 이동 | timestamp 로컬 시각, 확장자 유지, `_001` 충돌·사용자 파일 보존 |
| REQ-DVM-006 | 이동 실패 rollback, 두 객체 모두 유실 금지 | 실제 잠금/ACL, rename/rollback 실패 주입, 강제 중단 보존 |
| REQ-DVM-007 | 대상별 프로세스 간 직렬화 | 동일 target 2/8/16개·서로 다른 target·Chrome/Edge 역할 시뮬레이션 |
| REQ-DVM-008 | Native Messaging 입력·origin·경로 경계 | 64 KiB frame 상한, future protocol·malformed/duplicate JSON·장치/ADS/traversal 거절 |
| REQ-DVM-009 | metadata 최소·suspend 복원·종료 후 정리 | storage.local ID/name/at/stage만, 성공/실패/중단 cleanup, 7일 stale |
| REQ-DVM-010 | 정상 성공 조용히, 필요한 오류만 짧게 | 잠금·복구 실패/불확실 단계 구분, stack trace 없음 |
| REQ-DVM-011 | 제품 버전 하나와 protocol 별도 | Extension/Host/MSI 0.1.0, protocolVersion 1 |
| REQ-DVM-012 | 단일 설치 asset, 공식 Chrome/Edge 배포 | MSI 하나, 실제 extension 활성화·handshake; 개발용 load는 평가 fallback |
| REQ-DVM-013 | 사용자별 설치·제거·History 보존 | HKCU, LocalAppData, lifecycle·외부 파일/등록 보호 |
| REQ-DVM-014 | 실제 Chrome와 Edge 대표 E2E | first/same/changed/locked, 계약 filename·worker suspension |
| REQ-DVM-015 | resource 실측·실제 process 종료 | 크기/startup/peak/lifetime/10·100 MiB·idle |
| REQ-DVM-016 | 릴리즈 관문과 공개 검증 | 모든 필수 gate PASS·SHA256 후 stable, 게시 후 asset/문서 HTTP 재검증 |

## 보존·취소·복구

확장은 브라우저의 `uniquify` 충돌 방식을 제안해 먼저 새 다운로드를 보존한다. 사용자가 브라우저 다운로드를 취소·중단하면 Host를 호출하지 않는다. 파일 변경은 현재 완료한 download ID와 그 parent로 한정한다. 기존 suffix 파일 일괄 정리·다른 경로 임의 작업·restore UI는 없다.

Host는 두 객체를 읽기/DELETE access로 열고 write/delete sharing을 거절해 처리 중 변경을 막는다. 같은 target의 named mutex를 30초까지 대기한다. 기존 객체를 먼저 History 또는 동일내용의 임시 이름으로 이동한 뒤 신규를 원래 이름으로 이동한다. 두 번째 이동 실패는 같은 이전 핸들을 원래 이름으로 복구한다. 복구 실패는 위치와 오류를 응답하고 강제로 덮어쓰지 않는다.

원본 변경 도구의 미리보기·취소·복구 정책은 이 제품의 사용 전 동작 설명/평가 활성화, 한 이벤트의 고정 범위, browser cancel, 잠금·rollback·최소 오류 상태로 구체화한다. 자동 다운로드 정리의 특성상 건별 확인·정상 성공 장기 감사 로그는 두지 않는 예외를 ADR에 채택한다. 사용자는 브라우저에서 확장을 비활성화해 이후 자동 처리를 중단할 수 있다. 시작한 짧은 파일 이동의 중간 취소 UI는 제공하지 않는다.

## 지원 후보와 관문

Windows 11 x64, 고정 로컬 NTFS, 현재 Chrome/Edge가 검증 대상이다. Windows 10/ARM64/모든 조직 정책/네트워크/클라우드/대소문자 구분 NTFS를 인증하지 않는다. 같은 이름의 여러 완료 요청은 파괴적으로 겹치지 않고 mutex 처리 순서가 최종 순서다. 브라우저 전체 완료 시각의 영구 high-water 기록은 v0.1에 없으며 엄격한 완료 시각 순서 보장은 별도 제한이다.

스토어 미게시로 개발용 확장 활성화가 필요한 MSI는 완전 자동 단일 설치 요구를 충족하지 않는다. stable `download-version-manager-v0.1.0` 태그·릴리즈를 차단한다. 실제 수행과 미실행의 대응은 [시험 기록](../../../tools/DownloadVersionManager/TEST_RESULTS.md), [배포 기록](../../delivery/download-version-manager-evaluation-20260930.md)에서 관리한다.
