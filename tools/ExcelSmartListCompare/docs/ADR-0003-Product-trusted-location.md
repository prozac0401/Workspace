# ADR-0003 · 설치 폴더의 신뢰 위치 자동 등록

상태: 채택 · 날짜: 2026-09-14 · 결정 담당: 사용자 요청에 따른 제품 설치 변경

관련 요구: 설치 명령에서 제품 디렉터리를 자동 등록해 반복 매크로 알림을 줄여 달라는 후속 요청. [추가 도구 개발 기준](../../../docs/policies/tools.md), [ADR-0002](ADR-0002-Excel-native-lifecycle.md)를 따른다. 조직 전체의 보안 정책 승인과는 별개다.

## 맥락

원본 E2E 명세와 RC1은 보안 설정 자동 변경을 금지했다. 이후 사용자가 제품 설치 폴더의 신뢰 위치 자동 등록을 명시적으로 요청했다. 원본 명세는 보존하고, 이 제품의 로컬 폴더 한 곳에 한해 후속 요구를 반영한다.

## 결정

RC2의 Install.cmd는 `%LOCALAPPDATA%\ExcelSmartListCompare`를 현재 사용자 Excel의 신뢰 위치로 등록한다. 새 항목의 `AllowSubfolders`는 DWORD 0이다. 이 폴더의 파일은 매크로 등 활성 콘텐츠를 실행할 수 있으므로 제품 파일만 보관하도록 설치 확인창과 안내에 표시한다. 네트워크 경로, 리디렉션된 제품 폴더, 다른 파일이 이미 들어 있는 새 신뢰 폴더는 거절한다. 업무 폴더와 상위 폴더는 등록하지 않는다.

HKCU의 `Software\Microsoft\Office\<버전>\Excel\Security\Trusted Locations\LocationN`에 제품 ID와 설치별 소유 토큰을 둔다. 동일 경로의 기존 사용자 항목은 빌려 사용하며 소유권을 주장하지 않는다. 재설치는 변경되지 않은 자기 항목을 재사용한다. 외부에서 수정한 자기 항목은 덮어쓰지 않고 중단한다. 제거할 때도 외부 수정·알 수 없는 값·하위 키가 발견되면 보존하고 경고한다.

`alllocationsdisabled=1` 또는 `allow user locations=0`이면 등록을 중단하고 종료 코드 6을 반환한다. HKCU/HKLM의 Office 설정, Group Policy 및 Cloud Policy 경로를 읽는다. 정책, 모든 매크로 허용, AccessVBOM, PowerShell 실행 정책, 다른 추가 기능은 변경하지 않는다. 다른 정책 조합이나 MDM 적용은 별도 인수 범위다.

## 검토한 대안

수동 신뢰 위치 등록은 매 PC에서 반복 작업이 필요하다. 모든 매크로 허용은 이 제품 외의 파일까지 영향을 준다. 디지털 서명과 중앙 배포는 조직 배포의 별도 과제로 유지하며, 현재 패키지를 서명된 상용 승인본으로 표시하지 않는다.

## 실패와 복구

설치 기록을 먼저 원자적으로 교체한 뒤 신뢰 키를 만든다. RegCreateKeyEx의 생성 결과로 동시 생성된 외부 키를 구분한다. 소유 토큰을 먼저 쓰고 신뢰를 활성화하는 Path를 마지막에 쓴다. 처리 가능한 실패에서는 새 자기 항목과 변경 파일을 복구한다. 재설치 이전 항목은 롤백에서 삭제하지 않는다. 자기 설치로 만든 빈 신뢰 위치/Security 부모 키만 정리한다.

소유 토큰 이후의 중단 단계는 소유 기록을 사용해 제거할 수 있다. 키 생성 직후 토큰 기록 전 강제 종료는 비활성 빈 키를 남길 수 있다. 전원 단절의 모든 시점을 원자적으로 복구한다고 보장하지 않는다. 외부 변경이 있는 경우 자동 삭제보다 보존을 우선한다.

RC1의 소유 기록은 신뢰 위치 필드 없이 읽어 업그레이드한다. 제품 버전과 Excel 버전이 PowerShell의 대소문자 비구분 변수 이름으로 섞이던 기록 오류도 수정했다. VBA 엔진과 XLAM은 RC1에서 검증한 것과 동일하다.

## 검증과 근거

[RC2 실제 검증 보고서](WINDOWS_TRUST_LOCATION_REPORT.md)에 실기와 격리 레지스트리 시험을 구분한다. 정책 이름은 Microsoft의 [Excel ADMX](https://github.com/microsoft/ActiveDirectoryTierModel/blob/main/config/admx/excel16.admx)와 [Office ADMX](https://github.com/microsoft/ActiveDirectoryTierModel/blob/main/config/admx/office16.admx)에서 확인했다. 신뢰 위치의 효력과 정책 제한은 [Microsoft 신뢰 위치 문서](https://learn.microsoft.com/en-us/microsoft-365-apps/security/trusted-locations)를 따른다.
