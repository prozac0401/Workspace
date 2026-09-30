# DownloadVersionManager · 0.1.0 평가판

같은 파일을 다시 받을 때 늘어나는 `보고서 (1).xlsx`, `보고서 (2).xlsx`를 현재 다운로드 이벤트에서 처리합니다. 최신 다운로드 파일 자체가 `보고서.xlsx`를 승계합니다. 같은 내용이면 이전 파일을 제거하고, 내용이 다를 때만 이전 파일을 `_history`에 보관합니다.

**스토어 배포와 통합 설치 관문을 통과하지 않은 평가판입니다. MSI에 확장 파일을 넣었다는 사실을 확장 활성화 완료로 판단하지 않습니다.** 실제 시험 결과는 [TEST_RESULTS](TEST_RESULTS.md), 남은 제한은 [KNOWN_LIMITATIONS](KNOWN_LIMITATIONS.md)를 확인하세요.

## 사용 흐름

Chrome/Edge의 Manifest V3 확장이 원래 이름을 다운로드 결정 이벤트에서 기억하고 `uniquify`를 제안합니다. 완료 이벤트에서 실제 저장 경로를 확인해 Native Messaging으로 Host를 한 번 실행합니다. Host는 작업 결과 하나를 반환하고 종료합니다. 정상 성공은 조용히 처리합니다.

| 기존·신규 내용 | 결과 |
|---|---|
| 동일한 바이트 | 신규 파일이 원래 이름을 승계. History 생성 없음 |
| 다른 바이트 | 이전 파일을 `_history/보고서_YYYYMMDD_HHMMSS.xlsx`로 이동. 신규 파일이 원래 이름을 승계 |
| 기존 파일 없음 | 신규 파일을 원래 이름으로 이동 |
| 파일 잠김·권한 부족 | 안전하게 바꿀 수 없으면 중단. 남아 있는 파일 확인 안내 |

크기를 먼저 비교하고 같을 때만 64 KiB 버퍼로 SHA-256을 계산합니다. Office/PDF 의미를 해석하지 않습니다. 신규 파일 ID와 파일 시간을 유지하는 이름 이동을 사용합니다. 내용이 다른 이전 파일의 timestamp는 History로 옮기는 로컬 시각입니다. 같은 초에는 `_001`, `_002`를 붙이고 확장자는 유지합니다.

## 설치·제거

평가용 설치 파일은 `DownloadVersionManager-0.1.0-x64.msi` 하나입니다. 외부 런타임이나 관리자 권한 없이 `%LOCALAPPDATA%\Programs\DownloadVersionManager`와 HKCU Chrome/Edge NativeMessagingHosts에 설치하도록 구성했습니다. 실행 파일은 서명하지 않았습니다.

설치 후 시작 메뉴의 **DownloadVersionManager 설치 마무리**에서 공식 개발용 확장 불러오기를 따라 `extension` 폴더를 선택합니다. 각 브라우저의 확장에서 **설치 연결 확인**을 누릅니다. 스토어 검토·게시 전의 평가용 fallback이며 일반 PC에서 완전 자동 단일 설치 요구를 충족하지 않습니다. 기업 정책을 변경하거나 보안을 우회하지 않습니다.

제거는 Windows의 설치된 앱에서 진행하고 확장은 각 브라우저에서 제거합니다. 프로그램 파일과 자기 Native Host 등록만 제거합니다. 다운로드 파일과 History는 사용자 데이터이며 설치 소유 자원이 아닙니다. 브라우저를 강제로 종료하거나 Explorer를 재시작하지 않습니다.

## 실패와 복구

기존 파일과 신규 파일을 모두 잃지 않도록 기존 객체를 먼저 안전한 이름으로 이동한 뒤 신규 객체를 이동합니다. 두 번째 이동이 실패하면 이전 파일의 원래 이름 복구를 시도합니다. 복구도 실패하면 이전 파일이 보관된 정확한 위치와 신규 파일 위치를 응답합니다. 잠긴 파일이나 앱을 강제 종료하지 않고 자동 재시도하지 않습니다.

같은 내용의 이전 객체도 신규 이동 전에 임시 이름으로 안전하게 보관합니다. 정상 완료에서 이를 삭제합니다. 강제 종료·전원 장애로 `_history`나 `.dvm-<random>.pending`에 이전 객체가 남을 수 있습니다. 파일을 직접 확인해 복구하세요. 이름 패턴으로 잔재를 일괄 삭제하지 않습니다.

## 자원과 개인정보

Native Host는 요청 한 번만 처리합니다. startup·서비스·tray·watcher·polling·자동 업데이트 daemon이 없습니다. 다운로드를 처리하지 않는 동안 제품 native process 목표는 0개입니다. 확장에도 keepalive나 장기 native connection이 없습니다.

파일 내용·hash·telemetry를 외부로 보내거나 장기 보관하지 않습니다. 다운로드 ID별 원래 이름·시각·처리 단계만 브라우저 로컬 storage에 임시 보관합니다. 처리 후 지우고 7일 지난 metadata는 다음 이벤트에서 정리합니다. 오류는 경로 없는 최근 상태 하나만 남깁니다. 정상 성공 로그는 만들지 않습니다.

## 개발

```powershell
./tools/DownloadVersionManager/build/build.ps1
# 같은 전체 제작 경로 (PowerShell을 실행할 수 없는 환경)
python tools/DownloadVersionManager/build/build.py --msvc <MSVC-root> --sdk <SDK-root> --wix <wix.exe>
```

Windows x64 MSVC·Windows SDK·WiX 4·Python 3.12+·Node 22+가 제작용으로 필요합니다. 최종 사용자에게는 필요하지 않습니다. 상위 빌드는 production/test Host 분리, host/extension/protocol 시험, 자원 측정, MSI 생성·행정 추출·구조/파일 hash 검사와 SHA256SUMS 생성을 연결합니다. 실제 브라우저와 installer lifecycle은 별도 실기 관문입니다.

구조: `source` Host, `extension` 공통 MV3, `tests/host`, `tests/extension`, `tests/integration`, `build`, `installer`. [명세](../../docs/tools/download-version-manager/specification.md) · [ADR-0026](../../docs/design/0026-download-version-manager.md) · [제작·CI 범위](CI_SCOPE.md) · [변경 이력](CHANGELOG.md).
