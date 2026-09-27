# 이미지 도구 · 관리자 무서명 설치 후속

날짜: 2026-09-27 · 책임: 개발·검증 담당 · 상태: 관리자·SYSTEM 등록 경로 PASS, Explorer G0 및 제품 MSI 미완료

관련: [ADR-0022](../design/0022-image-admin-install.md), [앞선 순차 검증](backlog-followup-20260927.md), [G0 기록](../tools/image-copy-save/G0_Menu_Feasibility.md)

## 요청과 반영

사용자는 설치 시 관리자 권한을 받아 미완료 작업을 계속하도록 승인했다. 별도 서명 없는 MSI와 Windows 11 첫 메뉴 조건은 유지하고 설치 권한과 평소 사용 권한을 분리했다. 인증서·개발자 모드·UAC 정책·PowerShell 실행 정책은 변경하지 않았다. 정상 runas 요청 후 실제 상승 여부를 확인했다. 보안 데스크톱 동의를 자동 조작했다고 보고하지 않는다.

## 실제 결과

Windows 11 23H2 x64, 빌드 22631.6199에서 순차 수행했다. 이전 비상승 오류 0x80073D2B는 아래 관리자 경로의 실패가 아니다.

| 시험 | 실제 결과 |
|---|---|
| 최초 관리자 probe | 사전 DISM 조회가 0x80070005로 실패. 상승은 true였으나 등록은 NOT RUN. OS 정책·권한을 바꾸지 않고 공식 WinRT 조회로 교체 |
| 관리자 unsigned sparse 등록 | PASS. AllowUnsigned와 ExternalLocation으로 정확한 시험 identity 등록, 상태 OK |
| 관리자 전체 사용자 제거·재조회 | PASS. 관련 등록·프로비저닝 잔여 0개 |
| 등록을 유지한 Explorer 관찰 | 폴더 배경 우클릭은 구형 메뉴. 기존 구형 메뉴 고정 키가 있었고 새 메뉴를 관찰하지 못함. 제품 메뉴의 표시·숨김은 PASS로 판정하지 않음 |
| 관찰용 임시 등록·창 정리 | PASS. completion signal로 정확한 identity 제거. 새 시험 창만 닫고 기존 Explorer 창·설정을 보존 |
| 첫 PowerShell 사용자 지정 작업 MSI | 설치 1603 / 작업 1722. probe 결과 파일 생성 전 실패. 원인 확정 전이므로 unsigned 등록 거절로 분류하지 않음. MSI·시험 디렉터리·등록 잔여 없음 |
| 컴파일된 WinRT 작업의 SYSTEM 시험 MSI | PASS. SYSTEM=true, StagePackageByUriAsync(AllowUnsigned, ExternalLocationUri)·ProvisionPackageForAllUsersAsync·정확한 제거 성공. MSI 설치 0 / 제거 0 |
| SYSTEM 준비 후 일반 사용자 등록 | PASS. 별도 비상승 프로세스 ELEVATED=false에서 RegisterPackageByFamilyNameAsync 성공. 상태 Staged → Installed 확인 |
| 일반 사용자 연계 시험 후 정리 | PASS. MSI 설치 0 / 제거 0, 제품 등록·프로비저닝·MSI·시험 설치 디렉터리 잔여 없음 |

시험 identity는 ImageCopySave.UnsignedSparseProbe 0.1.1.0 x64다. MSI는 로컬 등록 실행 문맥을 검증하는 **진단용 MSI**이며 외부 staging payload를 참조한다. 자체 포함 제품 MSI나 배포 후보가 아니며 업데이트·중단 복구·제품 메뉴 제거의 합격 근거로 확대하지 않는다.

## 구현과 재현

- probe-unsigned-identity.ps1: OrdinaryUser/Administrator 모드, 전체 사용자·프로비저닝 충돌 확인, 정확한 PackageFullName 정리. 기본 모드는 비상승만 허용한다.
- invoke-admin-probe.ps1: 정상 runas와 결과 기록. Explorer 관찰은 최대 900초이며 종료 신호 또는 기한 후 정리한다.
- MsiContextProbe.cs / MsiContextProbe.wxs: Windows 기본 .NET Framework와 WinRT API를 사용하는 컴파일된 진단 작업. MSI의 deferred/non-impersonating SYSTEM 문맥을 실제 검사한다.
- build-msi-context-probe.ps1 / test-msi-context.ps1: 로컬 artifact 입력의 identity·무서명·해시 검사, 진단 MSI 제작, 관리자 설치와 자동 제거. 기존 probe MSI·설치 디렉터리·제품 등록이 있으면 보존하고 시작하지 않는다.
- ClipboardFixture.cs: 합성 텍스트·빈 클립보드를 위한 명시적 동의 시험기. 기존 내용을 읽지 않는다. 이번에는 이미지 상태의 메뉴 관찰까지만 진행했으며 텍스트·빈 상태 20회 검증은 하지 않았다.

구문과 일반/관리자 조회 범위 계약 검사를 별도로 수행한다. 실제 OS 결과와 mock 검사를 구분한다. 제품 코드와 원본 작업 트리의 사용자 수정은 변경하지 않았다.

## 남은 순서

1. 새 Windows 11 메뉴가 사용되는 환경에서 G0: 저장·복사 접근, 이미지→텍스트→빈 상태→이미지 20회, 완전 숨김, 대상 보기·결과 선택·오류 안내 확인.
2. 통과한 SYSTEM 준비와 일반 사용자 등록 경로를 자체 포함 제품 MSI로 통합. 설치·재설치·업데이트·제거·중단 복구·PNG 및 타사 메뉴 보존 검증.
3. 실제 검증 범위에 맞춰 내부 사용 후보 정리. 원격 게시와 상용 배포 승인 없음.

현재 PC에는 구형 메뉴 고정 설정이 있으므로 설정을 보존한 상태에서는 새 메뉴 G0를 완료할 수 없었다. 이를 제품 구현 자체의 불가능성이나 서명 필요성으로 해석하지 않는다. 메뉴 설정 처리 선호를 사용자에게 확인 요청했다. 기존 업무 Explorer를 강제 종료하거나 설정을 임의로 제거하지 않았다.

## 로컬 증거

아래 진단·계정 경로·로그는 공개 사이트에 포함하지 않는다. 경로는 작업 트리 기준이다.

- artifacts/image-copy-save/unsigned-identity-probe/20260927T010802093Z-dd2666f8aa04442590c06641bfcfc7ce: 최초 사전 조회 실패.
- artifacts/image-copy-save/unsigned-identity-probe/20260927T011028985Z-b21ea1bf37214ce9a1197d20aaea5a5d: 관리자 등록·정리 PASS.
- artifacts/image-copy-save/unsigned-identity-probe/20260927T011303803Z-7a11d0cbfbbb40a7be8690b1f5e48094: Explorer 관찰용 등록·정리 PASS.
- artifacts/admin-install-20260927/msi-install.log 및 msi-lifecycle.json: 최초 MSI 작업 실패와 잔여 확인.
- artifacts/admin-install-20260927/msi-system-native: SYSTEM WinRT 등록·정리, MSI 설치·제거 PASS.
- artifacts/admin-install-20260927/msi-user-registration: 비상승 등록 PASS, SYSTEM에서 Installed 확인, MSI·identity 정리 PASS.

공식 API 근거: [unsigned package](https://learn.microsoft.com/en-us/windows/msix/package/unsigned-package), [StagePackageOptions](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.stagepackageoptions), [현재 사용자 등록](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.registerpackagebyfamilynameasync). 공식 unsigned 기능은 시험용이며 이번 결과는 확인한 OS와 실행 경로에 한정한다.

## 최종 검사

재현 빌드 스크립트로 만든 MSI도 무서명(NotSigned) 검사 후 SYSTEM 시험·설치·제거를 통과했다. 진단 MSI 성공 실행은 총 3회이며 제품 MSI의 반복 설치 시험으로 합산하지 않는다. 구문 4개와 조회 범위 계약 4개, 총 8개 PASS. 문서 strict 빌드와 공개 19페이지·404·검색·사이트맵·로컬 링크 및 비공개 자료 제외 검사 PASS. 재현 빌드/실행 근거는 artifacts/image-copy-save/msi-context-probe/fda8f4f7604b4fca8467c41e90d2e00f에 보존한다.
