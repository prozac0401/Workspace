# ADR-0024 · ImageCopySave MSI의 기존 상태 보존 검사

상태: 채택, 0.2.0 실제 보존 시험 32개 PASS·정식 Release 게시


날짜: 2026-09-27  
결정 담당: 도구 개발·검증 담당  
관련 요구사항·정책: [요구명세 v1.2](../tools/image-copy-save/ImageCopySave_Requirements_v1.2.md)의 DEP-06·AT-40, [추가 도구 개발 기준](../policies/tools.md)  
대체 관계: [ADR-0023](0023-image-copy-save-classic-menu.md)의 클래식 등록·관리자 MSI 경계는 유지하고, 실행 코드 없는 MSI만으로 보존을 판단하던 구현을 보완한다.

## 맥락

0.1.1 MSI는 COM 서버 기본값만 충돌 검사했고 같은 이름의 메뉴 키·기존 설치 디렉터리와 외부에서 수정한 제품 파일·등록값을 충분히 구분하지 않았다. 시험 실행기의 사전 검사는 일반 사용자가 MSI를 직접 실행할 때 적용되지 않는다. 이는 소스 검토에서 확인한 보존 보장의 공백이며 실제 사용자 자료 손실을 관찰했다는 뜻이 아니다.

## 결정

MSI의 Binary 테이블에 정적으로 링크한 x64 네이티브 검사 DLL을 포함한다. 별도 .NET·PowerShell·서비스·설치된 실행 파일에 의존하지 않는다. 검사 코드는 파일과 레지스트리를 읽기만 하며, 설치·삭제·롤백은 Windows Installer의 표준 동작이 담당한다.

새 설치는 HKLM과 설치를 실행한 사용자의 HKCU에서 제품의 두 COM 루트·다섯 메뉴 루트를 확인하고, 해당 등록이나 설치 디렉터리가 이미 있으면 중단한다. 다른 사용자의 하이브를 열거나 변경하지 않는다. 유지보수는 MSI 내부의 파일별 SHA256와 Registry 테이블의 값 이름·형식·데이터를 기준으로 현재 상태를 비교한다. 기존 제품의 정상 설치 위치는 Windows Installer에 등록된 파일 구성 요소에서 확인한다. 값 또는 파일이 외부에서 변경됐거나 읽을 수 없으면 중단한다. 누락된 제품 파일·값은 복구할 수 있다. 소유 항목과 이름이 겹치지 않는 파일·값·다른 메뉴·기본 연결은 삭제 대상으로 추가하지 않는다. 재분석 지점을 통해 다른 위치로 우회하는 경로, 하드 링크, 제품 파일에 외부에서 추가한 이름 있는 데이터 스트림도 거절한다.

동일 패키지의 유지보수는 MsiGetActiveDatabase가 제공하는 현재 설치 데이터베이스만 읽는다. 업데이트할 이전 패키지는 빌드 시 감사한 소유 목록을 새 MSI의 ImageGuardPrior·ImageGuardPriorFile·ImageGuardPriorRegistry 테이블에 내장하고, 설치된 ProductCode·PackageCode가 정확히 일치할 때만 사용한다. 목록에는 404개 파일의 상대 경로·컴포넌트 GUID·SHA-256과 23개 등록 값의 루트·키·이름·원래 MSI 형식 문자열을 보존한다. MSI 실행 중 캐시 MSI를 MsiOpenDatabase로 열지 않는다. 제품명·버전 또는 현재 파일이 비슷하다는 이유로 소유권을 추정하지 않으며 알 수 없는 기존 패키지는 보존하고 중단한다.

즉시 검사는 CostFinalize 이후, InstallInitialize와 기존 버전 제거 이전에 실행한다. 지연 검사는 기존 버전 제거 이후이면서 새 패키지의 첫 스크립트 작업 이전에 다시 실행한다. 두 검사에는 사용자 입력으로 생략하는 공개 속성을 두지 않는다. 현재 사용자 SID를 전달하여 시스템 권한 지연 작업에서도 올바른 사용자 등록을 확인한다.

## 설치 API 보완과 감사 목록

실제 시험 폴더에 설치된 첫 0.2.0 제거가 1603으로 중단돼 조회 API를 따로 확인했다. 이 PC에서는 Custom Action 밖에서도 MsiGetComponentPathExW가 404개 파일 모두 UNKNOWN(-1)과 빈 경로를 반환했다. 같은 제품·컴포넌트의 MsiQueryComponentStateW는 명시적 MACHINE 문맥에서 LOCAL(3), MsiGetComponentPathW는 LOCAL(3)과 정확한 경로를 반환했다. 관계없는 제품 세 개에서도 같은 Ex/기존 API 차이를 확인했으며, 특정 시험 폴더 길이·CA 문맥만의 원인으로 단정하지 않는다. 운영체제 내부 원인은 미확정이다. 수정 코드는 제품의 PC 전체 설치를 먼저 확인하고, 각 컴포넌트의 명시적 MACHINE 등록 상태와 기존 경로 API 결과·문자열 경계·상대 경로·공통 설치 루트를 함께 검사한다.

별개로 MsiOpenDatabase는 Microsoft가 Custom Action에서 금지한 함수다. 따라서 캐시 MSI를 설치 도중 여는 설계를 제거하고, [빌드 전용 추출기](../../tools/ImageCopySave/installer/export-ownership-baseline.ps1)가 명시한 MSI 해시와 PASS 빌드 목록을 확인한 뒤 읽기 전용으로 감사 목록을 만든다. 파일별 경로·크기와 MSI의 컴포넌트 GUID/key path 관계를 대조하고, 정확한 제품 등록 23개 이외나 문자열 이외 형식·전체 키 삭제 행을 거절한다. 목록에는 로컬 절대 경로나 사용자 SID를 기록하지 않는다. [금지 함수 목록](https://learn.microsoft.com/en-us/windows/win32/msi/functions-not-for-use-in-custom-actions), [현재 설치 DB 읽기](https://learn.microsoft.com/en-us/windows/win32/api/msiquery/nf-msiquery-msigetactivedatabase)를 따른다.

제거 자체가 구형 guard에서 막힌 로컬 시험 설치는 동일 ProductCode·새 PackageCode의 제한된 small update로 수정 guard를 먼저 적용하는 복구 후보를 별도로 만든다. 이 예외는 감사한 과거 ProductCode·PackageCode의 내장 목록과 명시적인 로컬 복구 빌드에서만 허용하며, REINSTALL=ALL·REINSTALLMODE의 v·REMOVE 없음 및 전체 보존 검사를 요구한다. 외부 변경 비교나 guard를 생략하지 않는다. 임의 maintenance transform 추가, 캐시 MSI 직접 편집, 등록/파일 직접 삭제로 복구하지 않는다. Windows Installer의 [small update](https://learn.microsoft.com/en-us/windows/win32/msi/small-updates)와 [재설치 갱신](https://learn.microsoft.com/en-us/windows/win32/msi/applying-small-updates-by-reinstalling-the-product) 경로를 사용하며, 복구 후보의 실제 통과는 별도 기록으로 확인한다.

## 검토한 대안

- 시험 스크립트에서만 확인: 직접 MSI 실행을 보호하지 못한다.
- 기존 파일을 무조건 백업하고 계속 진행: 변경한 파일·등록을 제품 소유로 추정하고 사용 중인 외부 변경을 교체하게 된다.
- 모든 파일·키를 영구 보존: 정상 제거·업데이트와 중복 등록 방지 계약에 맞지 않는다.
- 상주 감시·잠금 서비스: 무상주 계약을 깨고 운영 복잡도를 늘린다.

## 영향과 이행

무서명 자체 포함 MSI, 관리자 설치·업데이트·제거, 평상시 일반 사용자 실행 계약은 유지한다. 충돌 시 경로를 포함한 설치 오류를 제공한다. 파일·등록값을 임의로 삭제하는 강제 설치 옵션은 제공하지 않는다. 변경한 자료를 사용자가 확인하고 안전하게 보존·정리한 다음 재시도하거나 지원을 요청한다. 정식 배포 여부는 최종 패키지의 실제 검증 기록에서 판정한다.

## 실패와 복구

검사 실패 시 변경 작업 전에 중단한다. 검사 후 표준 설치 작업이 실패하면 MSI 트랜잭션으로 롤백한다. 기존 버전 제거를 InstallInitialize 이후에 두어 업데이트 실패 시 이전 설치를 복구할 수 있게 한다.

검사는 시작 전에 존재하는 외부 변경과 두 검사 사이에 발생한 변경을 탐지하는 방어다. 관리자 권한의 다른 프로그램이 마지막 검사 이후 같은 파일·레지스트리를 동시에 바꾸는 상황까지 원자적으로 보호한다고 약속하지 않는다. MSI의 파일·레지스트리 쓰기와 별도 검사 사이에 범용 원자 연산은 없으며, 파일을 외부 쓰기 불가로 잠그면 MSI 자체 쓰기도 막힌다. 설치 중 해당 설치 폴더·등록을 수정하지 않는 Windows 관리 경계를 전제로 한다. Windows Installer가 직렬화하는 제품 설치와 임의 외부 관리자 편집을 구분해 기록한다.

## 검증

필수 확인: 새 설치의 디렉터리·HKLM/HKCU 일곱 등록 충돌, 외부 변경 파일·값·형식의 복구/업데이트/제거 차단, 누락 파일 복구, 알 수 없는 추가 파일·값 보존, 기본 연결·타사 메뉴 보존, 새 설치 실패와 업데이트 실패 롤백, 정상 설치·업데이트·제거·재설치. 단위 검사와 실제 MSI 결과를 구분하며 미실행을 PASS로 바꾸지 않는다.

2026-09-27 최종 공개 MSI(82A72EB85F41D6DF29BC94EE57215991BA41BEF542717D81CCC0C850C5F5134B)의 외부 전체 보존 Suite는 **32 PASS / 0 FAIL / 0 NOT RUN**이다. HKLM·HKCU 각각 일곱 루트와 기존 디렉터리·파일 충돌 16개, 새 설치 실패 롤백·정상 시험 설치 2개, 이전 설치의 외부 수정 차단·알 수 없는 자료 보존·업데이트 실패 롤백 4개, 복구 5개, 제거 5개를 확인했다. 복구·제거 검사는 추가 데이터 스트림·수정 파일·등록 데이터/형식 변경 차단과 누락 파일 복구 또는 알 수 없는 자료 보존을 포함한다. 실제 DEP-06·AT-40의 검증 범위는 이 32개 사례이며 임의의 모든 외부 변경·동시 편집을 시험했다는 뜻은 아니다.

합성 등록 정리와 업무 자료 역할의 fixture 보존을 확인했고, 같은 MSI의 기본 위치 최종 설치는 msiexec 0으로 PASS했다. 새 Suite와 최종 설치는 재시작 요구·Explorer 강제 재시작이 없었다. native 39 PASS와 정적 패키지 PASS는 실제 Suite와 별도 근거로 유지한다. 앞선 앱 호스트의 HKCU 쓰기 격리로 MSI가 시험 fixture를 읽지 못한 실패는 외부 호스트에서 진단·재검증했으며, 해당 이력을 삭제하거나 최초 실행의 PASS로 바꾸지 않는다.

[0.2.0 정식 Release](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.0)는 2026-09-27 09:58:56 UTC에 게시했고 공개 MSI·체크섬이 검증 후보와 일치했다. 최종 기본 설치본의 클래식 직접 메뉴 대표 복사·저장도 PASS지만, 기본 메뉴 두 기능의 기존 사용자 직접 확인과 별도 결과다. 저장 후 최종 행 선택은 NOT_CONFIRMED이며 전체 GUI·다른 OS/앱 지원으로 확대하지 않는다. 실제 결과·후보 식별·복구 이력과 Pages 안내 배포 상태는 [릴리스 작업 기록](../delivery/image-020-release-20260927.md)을 따른다.

공식 근거: [Microsoft의 RemoveExistingProducts 순서](https://learn.microsoft.com/en-us/windows/win32/msi/removeexistingproducts-action), [ICE63](https://learn.microsoft.com/en-us/windows/win32/msi/ice63), [사용자 지정 작업의 실행 순서](https://learn.microsoft.com/en-us/windows/win32/msi/sequencing-custom-actions), [지연 작업의 보안 문맥](https://learn.microsoft.com/en-us/windows/win32/msi/custom-action-security). 실제 보존 동작은 이 문서의 인용만으로 입증하지 않고 패키지 시험으로 확인한다.
