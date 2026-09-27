# ADR-0022 · 이미지 도구의 관리자 설치와 일반 사용자 실행

상태: 사용자 요구 채택, 관리자·SYSTEM 등록 경로 실증, 제품 MSI 통합 미완료

날짜: 2026-09-27 · 결정 담당: 사용자 요청에 따른 개발·검증 담당

관련: [도구 정책](../policies/tools.md), [요구명세 v1.1](../tools/image-copy-save/ImageCopySave_Requirements_v1.1.md), [ADR-0021](0021-image-unsigned-msi.md)

## 맥락

일반 사용자 세션에서 unsigned sparse identity 등록이 0x80073D2B로 차단됐다. 사용자는 설치할 때 관리자 권한을 받도록 변경하고 미완료 업무를 계속하도록 지시했다. 앞선 일반 사용자 설치의 실패 기록은 보존한다.

## 결정

별도 서명 없는 MSI 목표와 Windows 11 첫 메뉴·조건부 숨김은 유지한다. DEP-02의 관리자 권한 없는 설치 목표를 대체하여 설치·업데이트·제거 시 정상 Windows UAC를 통해 관리자 권한을 요청할 수 있게 한다. 평소 그림 복사·저장과 Explorer/helper 실행은 일반 사용자 권한을 유지한다. AT-41은 관리자 승인 설치와 일반 사용자 실행을 구분해 검증한다. 최초 명세는 보존한다.

자체 서명·공인 서명·인증서 신뢰 등록·개발자 모드·UAC 정책 변경은 도입하지 않는다. 사용자 승인 요청은 정상 runas 경로로만 한다. 도구가 접근할 수 없는 보안 데스크톱의 동의·암호 입력은 자동화했다고 보고하지 않는다.

## 검토한 대안

일반 사용자 무서명 등록은 현재 PC에서 차단됐다. 자체·사내 서명은 신뢰 설정이 필요하며 사용자가 선택하지 않았다. 관리자 무서명 설치는 공식 문서상 시험용 기능이므로 실제 등록·정리·메뉴·MSI 수명주기 검증을 통과해야 하며 내부 사용 승인이 광범위 배포 지원을 뜻하지 않는다.

## 영향과 이행

먼저 기존 probe에 명시적인 Administrator 모드를 추가하여 모든 사용자의 관련 패키지와 프로비저닝 충돌을 검사한다. 임시 등록을 시도한 뒤 정확한 시험 identity만 제거하고 전체 범위의 잔여 등록을 확인한다. 이 선행 시험이 성공해야 MSI 및 Explorer G0 구현·검증을 진행한다. 권한 상승 자체가 등록 성공이나 메뉴 지원을 증명하지 않는다.

## 실패와 복구

기존 등록이 있으면 시작하지 않는다. UAC 취소·실행 차단·등록 거부를 구분해 기록한다. 등록 후 오류가 있어도 finally에서 이번 실행의 정확한 PackageFullName만 정리한다. 강제 종료·전원 차단 시 자동 정리를 보장하지 않으며 다음 실행은 잔여 등록을 자동 인수하지 않는다.

## 검증

2026-09-27 관리자 unsigned sparse 등록·정리와 진단 MSI의 SYSTEM 준비·프로비저닝·정리가 통과했다. SYSTEM 준비 후 별도 일반 사용자 등록도 상승 없이 통과했다. 진단 MSI 세 번의 설치·제거 종료 코드는 모두 0이었다. 현재 PC는 구형 메뉴 고정 설정이 있어 새 메뉴 G0는 미완료이며 제품 MSI는 아직 통합하지 않았다. [실행 기록](../delivery/image-admin-install-20260927.md)을 따른다.

구문·일반 사용자와 관리자 조회 범위 계약, 실제 상승 여부, 등록 HRESULT, 전체 사용자·프로비저닝 정리를 기록한다. 실제 Explorer G0, 비상승 helper, MSI 설치·업데이트·제거·중단 복구, 사용자 PNG 보존은 별도 인수 항목이다.

근거: [Microsoft unsigned package](https://learn.microsoft.com/en-us/windows/msix/package/unsigned-package), [Remove-AppxPackage AllUsers](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage)
