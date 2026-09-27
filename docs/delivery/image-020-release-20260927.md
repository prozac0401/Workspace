# 그림 복사·저장 0.2.0 · 보존 보완과 정식 릴리스 작업 기록

날짜: 2026-09-27 · 책임: 도구 개발·검증 담당 · 상태: **사용자 등록 검사 수정 후보 제작·구조 확인 완료, 실제 보존 회귀 실행 미시작(UAC 취소) — 공개 전**

적용: [v1.2 변경 계약](../tools/image-copy-save/ImageCopySave_Requirements_v1.2.md), [보존 설계 ADR-0024](../design/0024-image-msi-preservation.md), [공개 안내 ADR-0025](../design/0025-image-public-guide.md), [도구 정책](../policies/tools.md), [문서 정책](../policies/documentation.md).

사용자는 기존 등록·외부 수정 파일 보존 문제를 해결하고 적용한 뒤 정식 릴리스까지 진행하도록 지시했다. 승인된 배포 형식은 Windows 11 x64용 자체 포함 무서명 MSI이며, 관리자 설치와 일반 사용자 실행을 분리한다. 서명 인증이나 회사 전체의 상용 배포 승인을 받았다는 뜻은 아니다.

## 변경한 범위

MSI 안에 정적으로 링크한 native 검사 DLL과 파일별 SHA-256 소유 목록을 넣었다. PC 전체 HKLM과 설치를 실행한 사용자 HKCU의 두 COM 루트·다섯 메뉴 루트 및 기존 설치 폴더의 충돌을 검사하고, 유지보수에서는 설치된 제품의 캐시 MSI와 비교한다. 파일 본문 변경, 추가 NTFS 스트림, 재분석 지점·하드 링크, 알려진 등록 값·형식 변경은 보존하고 중단하는 대상이다. 추가한 파일이나 알 수 없는 값은 제거 대상으로 추가하지 않는다. 과거 0.1.1의 자동 이행은 검증한 ProductCode·PackageCode·404파일 해시에 고정한다.

읽기 전용 즉시 검사와 지연 검사를 추가했으며 실제 파일·등록 쓰기와 롤백은 Windows Installer가 수행한다. 마지막 검사 이후 임의의 관리자 프로그램이 동시에 바꾸는 자원까지 원자적으로 보존한다고 약속하지 않는다. 초기 업그레이드 제거 순서와 동시 관리자 변경 경계는 ADR-0024를 따른다. 일반 사용자에게 수동 등록·레지스트리 편집·스크립트 실행을 요구하지 않는다.

이미지 엔진·helper·메뉴 런타임은 이번 MSI 보존 보완의 변경 대상이 아니다. 기존 PASS를 새 시험으로 합산하지 않고 아래 범위로 재사용한다. 최종 후보의 404개 런타임 파일을 실제 사용자 확인을 받은 0.1.1의 고정 목록과 대조해 모든 경로·SHA-256이 동일함을 확인했다. 최종 MSI 제작에 사용한 설치 소스 7개의 현재 SHA-256도 빌드 메타데이터와 모두 일치한다.

## 사용자 등록 검사 보완과 재제작 후보

첫 실제 MSI 시험의 HKCU 차단 누락 이후 사용자 문맥 확인을 강화했다. 즉시 작업에서 실행 토큰 SID와 Windows Installer의 UserSID가 일치해야 하며, RegOpenCurrentUser로 연 실제 사용자 등록 경로와 캡처한 SID에 대응하는 Classes hive 경로를 독립적으로 검사한다. 지연 작업에서도 Windows Installer UserSID가 전달한 사용자와 일치하는지 확인한 뒤 같은 사용자 범위를 검사한다. 문맥이나 hive 확인에 실패하면 허용으로 추정하지 않고 중단한다.

정상 HKCU Software\Classes는 운영체제가 관리하는 링크이므로 그 앵커와 아래 제품 소유 경로를 구분한다. 즉시·지연 단계의 사용자 문맥과 검사 루트 진단을 로컬 MSI 로그에 남긴다. 첫 실패의 정확한 Windows Installer 실행 문맥 차이는 아직 실제 재시험으로 입증하지 않았으므로 “SID 불일치가 확정 원인”이라고 단정하지 않는다. 수정 코드를 작성하고 단위검사를 통과한 사실과 실제 MSI에서 누락이 해소됐다는 판정은 별개다.

| 항목 | 재제작 후보와 실제 확인 |
|---|---|
| 제품 MSI | ImageCopySave-0.2.0-x64.msi, 50,537,248 bytes |
| 제품 SHA-256 | FDCD4201BB59E95B3513F2BD6849A80CDD2B7B986FF49297184DBDAED6F17159 |
| 제품 빌드 디렉터리 | artifacts/image-copy-save/msi/20260927T053516844Z-e9869cce2b8343e1a513c57da0dd3852 |
| 롤백 시험 MSI | ImageCopySave-0.2.1-x64-ROLLBACK-TEST.msi, 50,537,264 bytes. 공개 대상 아님 |
| 롤백 SHA-256 | F71BF7B8A98222B79468D42CA0FFC110A3C9563A0E7C07840A4CDCCBF9061885 |
| 롤백 빌드 디렉터리 | artifacts/image-copy-save/msi/20260927T053607328Z-b09fa73902d944d68d72d27d23b30613 |
| 소스·페이로드 | 두 파일의 설치 소스 해시 7개 일치, 자체 포함 404파일 인벤토리 일치 |
| Guard.cpp SHA-256 | DBC3CE9136D537CC29E4B99686D51594823FEF324F4D08652A008AF6CFAF1BE5 |
| native 보호 회귀 | 26 PASS / 0 FAIL. 별도 합성 레지스트리 fixture 생성·정리 확인, 제품 등록 변경·설치 없음 |
| 제품·롤백 MSI 정적 검사 | 둘 다 PASS. 롤백 파일은 AllowRollbackTest를 명시한 검사이며 고의 실패 파일임을 유지 |
| 첫 실패 설치의 복구 Inspect | PASS. 기존 후보 404파일·23등록 값 정확 일치, 알 수 없는 파일/값·현재 사용자 충돌·이름 있는 스트림·재분석 경로 0개 |
| 수정 후보 실제 보존 Suite·최종 설치 | NOT RUN: 관리자 승인 요청이 취소되어 자식 프로세스가 시작되지 않음. Inspect·정적·native PASS를 실제 Suite PASS로 승격하지 않음 |

26개 native 시험은 합성 사용자 등록을 실제로 만들고 정리하므로 registryModified=false로 설명하지 않는다. 기록의 registryFixtureCreated=true, registryFixtureCleaned=true, productRegistrationModified=false, installed=false를 구분한다. 실제 제품 MSI는 여전히 파일·등록 쓰기를 Windows Installer에 맡기는 읽기 전용 검사를 사용한다.

복구 Inspect는 2026-09-27 05:39 UTC에 비상승으로 실행했다. 계획한 후속 순서는 정확히 일치하는 실패 시험 설치만 그 원래 MSI로 제거 → 깨끗한 설치 상태 확인 → 수정한 보존 Suite → 기본 위치 최종 설치다. 후속 Run은 05:40:57 UTC에 정상 UAC를 요청했으나 05:43:00 UTC에 Windows가 취소 결과를 반환했다. ELEVATION_NOT_STARTED이며 자식 프로세스 ID가 없고 제거·설치 단계는 실행되지 않았다. 실제 Suite와 최종 설치는 관리자 승인 후 재개해야 한다. 기록은 artifacts/image-copy-save/msi-preservation-recovery/20260927T054050047Z-c68d56cb99ef448086349c7a2251bb7c/launch.json에 보존한다.


등록 충돌 시험기 자체의 정리 경계도 보완했다. 생성 전 소유 정보를 기록하고 등록 생성·읽기 확인·MSI 호출을 하나의 try/finally에 포함했다. 읽기 확인 실패, 호출 실패, 추가 외부 값 보존, 외부에서 바꾼 시험 값 보존의 합성 HKCU 회귀 4개가 PASS다. 제품 등록과 MSI 설치는 실행하지 않았다. 결과와 실제 시험 소스 해시는 artifacts/image-copy-save/msi-preservation-development/registry-fixtures-result.json에 저장했다. 실행 UTC는 기록하지 않아 추정하지 않았으며 결과 저장 시각과 구분했다. 이 시험기 변경으로 다음 Run은 입력 해시를 다시 고정한다.

## 첫 0.2.0 후보 식별

이 표는 HKCU 충돌 차단 실패가 발견된 **첫 후보**다. 최종 공개 파일의 식별 정보로 사용하지 않는다.

| 항목 | 기록 |
|---|---|
| 파일 | ImageCopySave-0.2.0-x64.msi |
| 크기 | 50,529,056 bytes |
| SHA-256 | DE666CC6115E0A459EFD1F75EBE6760EA58DA09E10E02CC669470E69AD41B092 |
| ProductCode | {589202C2-9A92-0BAE-E0A7-AEF17B34DF91} |
| 로컬 빌드 디렉터리 | artifacts/image-copy-save/msi/20260927T051022819Z-5960212b27ee44459203e8df016d0d77 |
| 정적 패키지 검사 | PASS: 무서명·PC 전체 x64·자체 포함 404파일·내장 CAB 1개·COM 2개/메뉴 5개·실행형 검사 CA 2개·Explorer 자동 종료 비활성 |
| native 보호 회귀 | 24 PASS / 0 FAIL. 실제 MSI 설치·등록 시험과 구분 |
| 시험 자료 보존 도우미 | 합성 primitive 6개 PASS. 실제 MSI 충돌 검증과 구분 |

별도 고의 실패 파일 ImageCopySave-0.2.1-x64-ROLLBACK-TEST.msi는 50,529,072 bytes, SHA-256 E25155D3360CB07AEC20A4D19CB57B8F5DB27A52218E08276F2DE31AA96DBFD5다. 같은 설치 소스 해시·페이로드로 제작하고 허용 옵션을 지정한 정적 검사는 PASS다. 이 파일은 공개 자산이 아니며 첫 후보와 같은 보호 코드이므로 수정 후 롤백 검증의 근거로 사용할 수 없다.

## 실제 첫 순차 실행 결과

| 단계 | 결과 | 실제 의미 |
|---|---|---|
| 0.1.1 → 첫 0.2.0 업그레이드 | PASS, msiexec 0 | 일반 설치 위치에서 새 제품·등록 확인, 합성 PNG 해시 유지 |
| 첫 0.2.0 제거 | PASS, msiexec 0 | 제품 설치 상태 false, 제품 등록 0개, 합성 PNG 해시 유지 |
| HKLM 기존 루트 0~6 충돌 | 7 PASS, 각 msiexec 1603 | 동일 이름의 COM·메뉴 합성 등록에서 설치 거절 확인 |
| HKCU 기존 루트 0 충돌 | FAIL, msiexec 0 | 예상한 보호 거절이 발생하지 않아 시험 전용 폴더에 첫 후보가 설치됨 |
| 이후 보존 회귀·새 롤백 시험 | NOT RUN | 첫 실패에서 중단. 미실행 항목을 PASS로 계산하지 않음 |

업그레이드·제거에서 재부팅 요구와 Explorer 재시작은 없었다. HKCU 실패는 기존 사용자 등록 충돌을 놓친 **차단 누락**이다. 이를 실제 사용자 업무 자료 손실을 관찰한 것으로 설명하지 않는다. 시험기는 STOPPED_FOR_REVIEW_NO_AUTOMATIC_PRODUCT_REMOVAL로 중단했고, 당시 전용 시험 폴더에 남은 제품 상태를 기록했다. 현재 설치 상태는 후속 정리·재실행 결과로 별도 확인해야 하며 자동 정리 완료로 표시하지 않는다.

첫 후보 이후 사용자 문맥 검사를 보완하고 위 새 후보를 제작했다. 첫 후보의 구조·native PASS는 실제 HKCU 통합 실패를 취소하지 않으며, 위 새 후보의 실제 회귀가 통과하기 전에는 최종 보존 인수를 대신하지 않는다.

## 재사용하는 기존 런타임 근거

- 엔진/helper 최신 현재 사용자 시험 85 PASS / 1 NOT RUN(일회용 CI 전용 디스크 부족), 실제 클립보드 23개 PASS, native 정책·직접 COM 66개 PASS를 당시 소스·환경의 결과로 유지한다.
- 그림판의 helper 종료 후 붙여넣기와 그림판 복사 → PNG 저장 대표 결과를 유지한다. 모든 외부 앱·투명도 보장을 뜻하지 않는다.
- 클래식 직접 표시 상태 전환 15회·46관찰과 0.1.1 대표 PNG 복사·저장을 유지한다. 16~20회는 사용자 지시에 따라 생략했으며 필수 잔여가 아니다.
- Windows 11 기본 메뉴 경로의 두 기능은 사용자가 “기본 메뉴 경로에서 두 기능 모두 정상”이라고 직접 확인했다. 사용자 확인 PASS이며 자동화·모든 조건별 숨김·창/탭 검증으로 확대하지 않는다.
- [0.1.1 당시 MSI 수명주기](image-classic-msi-20260927.md)는 당시 후보의 PASS다. 새 보호 기능의 전체 실기로 합산하지 않는다.

기존 UI 자동화는 창 활성화 오류로 중단한 이력이 있다. 과거 일시적인 Explorer 응답 없음은 자체 회복했으나 원인은 미확정이다. 새 자료 없이 제품 무관이나 자동화만의 문제로 결론내리지 않는다.

## 최종 인수·게시 전 채울 항목

1. 위에 식별한 수정 후보의 HKCU 실패 수정과 실제 MSI 보존 회귀 재검증.
2. 새 설치 충돌, 외부 수정 파일·값·추가 스트림의 복구/업데이트/제거 차단, 누락 파일 복구, 알 수 없는 추가 파일·값·타사 메뉴·기본 연결 보존, 정상 수명주기와 새 설치/업데이트 실패 롤백 결과.
3. 최종 설치 패키지의 대표 복사·저장을 확인하고 기존 사용자 확인과 런타임 결과를 재사용한다. 조건별 메뉴·창/탭·오류/취소의 미관찰 항목은 실제 NOT RUN 범위로 기록한다. 원래 AT 목록 전체를 이번 MSI 보존 수정의 새 반복 관문으로 만들지 않으며, 추가 후속 확인은 답변 도착 전 PASS로 기록하지 않는다.
4. 공개용 릴리스 설명과 지원 제한 확정, 최종 자산의 해시 대조, 태그/소스 커밋·Release URL·draft/prerelease 상태·게시 시각.
5. 최종 공개 안내의 배포 준비 문구 교체, MkDocs strict·공개 목록 검사·Pages Actions·실제 공개 URL/검색/자산 확인.

Windows 10·ARM64·네트워크/가상 위치와 모든 Office·메일·메신저를 이번 Windows 11 로컬 지원 결과에 포함하지 않는다. 새 MSI 보존 회귀가 미완료인 상태를 제한사항 문구만으로 통과 처리하지 않는다. 기존 사용자 확인과 실제 런타임 근거를 보존하며, 확인하지 않은 GUI 항목을 전체 G0·44개 AT 완료로 표기하지 않는다.

## 로컬 증거와 공개 경계

원시 MSI 로그·사용자 SID·개인 경로·설치 상태 덤프는 공개 자산이나 Pages에 포함하지 않는다. 아래는 개발 검증자가 같은 작업본에서 찾을 상대 경로다.

- 재제작 후보: 위 두 새 빌드 디렉터리의 build-metadata.json, guard/build-metadata.json, 패키지 검사 출력.
- 복구 사전 확인: artifacts/image-copy-save/msi-preservation-recovery/20260927T053939025Z-f32a6f10489d479b913ccca6cad77586/inspection.json.
- 첫 후보: 첫 후보 빌드 디렉터리의 build-metadata.json, guard/build-metadata.json, 패키지 검사 출력.
- 업그레이드: artifacts/image-copy-save/msi-lifecycle/20260927T052035232Z-b48b0bdc9faf4a769b846f7883c4b56f/result.json.
- 제거: artifacts/image-copy-save/msi-lifecycle/20260927T052144635Z-e492c8c85dcf455b983b259f825c749c/result.json.
- 첫 보존 회귀: artifacts/image-copy-save/msi-preservation/20260927T052216347Z-8954dc8580064f7f835ca261a92af07a/result.json 및 사례별 MSI 로그.
- 첫 후보 롤백 파일 구조: artifacts/image-copy-save/msi/20260927T051434216Z-732db584d2a54f4b90f7e965e82890f3/verification.json.
- 재제작 후보 롤백 파일 구조: artifacts/image-copy-save/msi/20260927T053607328Z-b09fa73902d944d68d72d27d23b30613/verification.json.
- 공개 안내 초안 검사: artifacts/image-public-guide-20260927/site. MkDocs strict 및 공개 20페이지+404·검색·사이트맵·로컬 링크 검사는 PASS이며 제품 인수를 뜻하지 않는다.

공개 범위에는 사용자 [설치·사용 안내](../tools/image-copy-save/guide.md)만 추가한다. 최종 배포용 설명은 로컬 artifacts/release-readiness-20260927/image-020-release-draft/에 준비하며 게시 전 검토 문구·미확정 필드는 제거하거나 실제 결과로 채운다.
