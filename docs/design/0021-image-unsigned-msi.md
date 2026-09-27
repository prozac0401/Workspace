# ADR-0021 · 이미지 도구의 무서명 MSI 목표와 설치 검증 관문

상태: 배포 요구 채택, 구현 경로 차단 · 날짜: 2026-09-27 · 결정 담당: 사용자 요청에 따른 개발·검증 담당

관련: [도구 정책](../policies/tools.md), [요구명세 v1.1](../tools/image-copy-save/ImageCopySave_Requirements_v1.1.md), [독립 메뉴 결정](0016-image-copy-save-direct-menu.md). 최초 명세는 원본으로 보존한다.

## 맥락과 결정

사용자는 다른 MSI와 마찬가지로 이미지 도구도 별도 서명 없이 MSI로 패키징하도록 요청했다. Windows 11 첫 컨텍스트 메뉴의 독립 명령, 이미지가 없을 때 완전 숨김, 일반 사용자 설치 요구는 유지한다. 기존 MSIX 인증서 신뢰 해결을 이번 필수 작업으로 요구하지 않는다.

MSI 제작 전에 문서화된 API로 무서명 package identity 등록이 성립하는지 최소 실증한다. MSI 파일 형식 변경만으로 Explorer 등록 요구가 충족됐다고 판단하지 않는다. 서명된 MSIX를 내부에 숨겨 포장하거나, 개발자 모드·신뢰 저장소·보안 정책을 바꾸거나, 클래식 메뉴로 임의 전환하지 않는다.

## 검증과 결과

Windows 11 Pro 23H2 22631.6199의 비상승 사용자 세션에서 unsigned sparse identity를 만들고 Add-AppxPackage의 ExternalLocation 및 AllowUnsigned 옵션으로 시험했다. Windows가 실행 가능한 활성화를 포함한 무서명 패키지라는 이유로 0x80073D2B를 반환했다. 이후 ImageCopySave 등록 0개를 확인했다. [실증 근거와 공식 API 조건](../tools/image-copy-save/unsigned-msi-feasibility.md).

## 영향과 이행

현재 후보는 R01 BLOCKED다. 이에 의존하는 실제 Explorer G0, 최종 MSI 설치 수명주기와 배포 인수는 NOT_RUN으로 남긴다. 설치 독립 이미지 엔진/helper 시험 및 다른 도구의 후속 업무는 계속한다. 이 결과는 시험한 OS와 후보 방식의 판정이며 모든 미래 구현의 불가능성을 주장하지 않는다.

## 실패와 복구

probe는 원래 제품과 구분되는 고정 평가 identity만 사용한다. 기존 ImageCopySave 등록이 있으면 시작하지 않고, 이번 실행의 정확한 PackageFullName만 제거한다. 원시 로그는 로컬 artifacts에 보존한다. 무서명 MSI·일반 사용자·첫 메뉴 중 어느 요구를 변경할지는 이번 일괄 실행으로 자동 결정하지 않는다.
