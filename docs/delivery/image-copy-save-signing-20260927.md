# ImageCopySave 서명·설치 시도 · 2026-09-27

상태: 서명 완료, 현재 PC 설치 신뢰 차단 · 책임: 개발·검증 담당

사용자가 허용한 기존 CurrentUser/My 코드서명 인증서를 사용했다. 인증서 생성·가져오기·신뢰 저장소 변경·개인키 내보내기·개발자 모드 변경은 수행하지 않았다. 현재 PC는 Windows 11 Pro 23H2 x64, 22631.6199이며 일반 사용자 세션에서 실행했다.

## 실제 결과

| 단계 | 판정 | 증거 범위 |
|---|---|---|
| 원본 확인 | PASS | unsigned 0.1.1.0, 64,318,517 bytes, SHA-256 `14343a24a46047abf9f87d4c12427315d798049b75daad2cdcbbbe87fdae3a10` |
| 기존 인증서 확인 | PASS | Publisher와 Subject 정확히 일치, 유효기간 내, 코드서명 EKU·개인키 있음 |
| 새 사본 서명 | PASS | signed 0.1.1.0, 64,335,585 bytes, SHA-256 `263bfb40780bd536034a8bf78e50a58bb57f683a998d03f9bd35b970cbcc5ae9` |
| SignTool `/pa /all /v` | PASS | 1개 서명 검증, 경고0·오류0, 외부 타임스탬프 없음 |
| 현재 사용자 Add-AppxPackage | FAIL / 차단 | `0x800B0109`: 신뢰되지 않는 루트 인증서에서 인증서 체인 종료 |
| 실패 후 현재 사용자 등록 | PASS | ImageCopySave.Evaluation 패키지 0개 |
| 실제 Explorer G0·재설치·업데이트·제거 | BLOCKED / NOT RUN | 최초 설치가 성립하지 않음 |

서명 사본은 작업 트리 `artifacts/image-copy-save/signed-20260927/ImageCopySave-0.1.1-signed.msix`에 보존했다. 원본 unsigned MSIX는 변경하지 않았다. 평가용이며 공개/상용 승인 설치본이 아니다.

읽기 전용으로 같은 인증서 지문만 조회했다. CurrentUser/My와 CurrentUser/Root에는 존재했고 LocalMachine/My·Root·TrustedPeople 및 CurrentUser/TrustedPeople에는 없었다. 이 관측과 배포 오류를 기록하며, 일반 SignTool 검증 성공을 MSIX 설치 허용으로 확대 해석하지 않는다. 저장소에 인증서를 추가하거나 OS 판정을 우회하지 않았다.

## 다음 조건과 한계

현재 허용 범위에서 앱 패키지의 신뢰 조건을 해결할 수 없으므로 설치 의존 실기를 중단했다. PC 관리 주체가 허용하는 서명·배포 조건이 별도로 마련된 뒤 같은 identity의 실제 설치부터 다시 확인해야 한다. 기존 ‘새로 만들기’ 내부 배치를 다시 요구하거나 고정 메뉴·수동 COM 등록으로 대체하지 않는다.

이미지 엔진의 설치 독립 시험은 별도 T03 범위다. 이번 서명·설치 시도는 44개 수용시험이나 G0를 PASS로 바꾸지 않는다. 실제 원본 PNG 생성/복사, Explorer 표시·숨김, 외부 앱 붙여넣기는 실행하지 않았다.

검증 명령은 `tools/ImageCopySave/installer/sign-package.ps1`과 `manage-install.ps1`의 기존 안전 검사를 사용했다. 인증서 조회·서명 로그·설치 실패/후속 조회·해시의 원본 증거는 로컬 `artifacts/audit/backlog-20260926/t04-*`에만 보존한다. 진단·인증서 세부정보를 공개 사이트에 싣지 않는다.

## T03 설치 독립 시험의 사전 조건

현재 작업 트리의 엔진/helper/시험 프로젝트를 SDK 10.0.401로 Release 빌드했다. 경고0·오류0이다. 일반 사용자 실행 컨텍스트에서도 새 private window station을 확보할 수 있는지 `metadata-only` 사전 사례 하나만 실행했다.

최초 실행은 프로세스 시작의 접근 거부로 시험에 진입하지 않았다. 같은 바이너리를 보안 설정 변경 없이 재시도하자 실행은 됐지만, `CreateWindowStation`의 fresh OS-named station 생성이 native 오류183으로 거절됐다. worker 종료77, `NOT RUN`이다. 기존 객체를 재사용하거나 사용자 클립보드로 대체하지 않았다. 나머지 격리 사례도 같은 선행 조건을 요구하므로 반복 실행하지 않았으며, 기존 62 PASS/24 NOT RUN을 새 실행 결과로 계산하지 않는다.

로컬 증거는 작업 트리 `artifacts/image-copy-save/isolation-20260927`의 `build.log`, `preflight.json`, `metadata-only/result.txt` 및 감사 폴더의 `t03-preflight-first-status.json`이다. 첫 접근 거부와 이후 격리 오류는 서로 다른 단계이며 원인을 단정하지 않는다. 제품 소스 변경·상승 실행·외부 CI 실행은 없었다. T03의 추가 클립보드 자동 시험과 T04의 설치 의존 실기는 각각 차단 상태로 남는다.
