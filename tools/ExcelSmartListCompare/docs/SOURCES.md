# 구현 근거 — Microsoft 공식 문서

확인일: 2026-09-14. 아래 문서는 API 동작 근거이지 이 패키지의 실제 실행 검증 결과가 아닙니다.

| 주제 | 공식 자료 | 적용 |
|---|---|---|
| 가시 셀 | https://learn.microsoft.com/en-us/office/vba/api/excel.range.specialcells | 가시 셀 Range 취득 및 원래 선택과 교차 |
| 큰 선택 개수 | https://learn.microsoft.com/en-us/office/vba/api/excel.range.countlarge | Count 대신 CountLarge로 사전 점검 |
| 성능 | https://learn.microsoft.com/en-us/office/vba/excel/concepts/excel-performance/excel-tips-for-optimizing-performance-obstructions | Value2 배열 읽기, UsedRange 과대 확장 주의 |
| 취소 | https://learn.microsoft.com/en-us/office/vba/api/excel.application.enablecancelkey | xlErrorHandler로 사용자 중단 처리 |
| 단축키 | https://learn.microsoft.com/en-us/office/vba/api/excel.application.onkey | 재등록/해제가 기존 OnKey 지정에 영향을 주므로 기본 미등록 |
| 임시 메뉴 | https://learn.microsoft.com/en-us/office/vba/api/office.commandbarcontrols.add | Temporary 메뉴 및 고유 태그로 소유권 한정 |
| 팝업 컨트롤 | https://learn.microsoft.com/en-us/office/vba/api/office.commandbarpopup.controls | 팝업 하위 Controls는 CommandBarPopup 타입으로 접근 |
| 숫자 문자열 | https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/str-function | 소수점 마침표 기반 숫자 키 처리 |
| Find 상태 | https://learn.microsoft.com/en-us/office/vba/api/excel.range.find | 사용자의 저장된 Find 설정을 건드리지 않도록 Find 미사용 |
| 추가 기능 등록 | https://learn.microsoft.com/en-us/office/vba/api/excel.addins.add | 추가 기능 목록에 경로 등록 |
| 설치/제거 | https://learn.microsoft.com/en-us/office/vba/api/excel.addin.installed | Installed 속성과 Auto_Add / Auto_Remove |
| 자동화 보안 | https://learn.microsoft.com/en-us/office/vba/api/excel.application.automationsecurity | 설치용 COM Excel에도 사용자 보안 정책 적용 |
| VBA 프로젝트 접근 | https://learn.microsoft.com/en-us/office/vba/library-reference/concepts/security-notes-for-microsoft-office-solution-developers | 승인된 개발 환경에서만 소스 빌드, 설치기의 보안 옵션 변경 금지 |
| 인터넷 매크로 차단 | https://learn.microsoft.com/en-us/microsoft-365-apps/security/internet-macros-blocked | 매크로 차단/조직 배포 정책을 우회하지 않음 |
| 제품 폴더 신뢰 위치 | https://learn.microsoft.com/en-us/microsoft-365-apps/security/trusted-locations | RC2는 명시적 후속 요구에 따라 전용 로컬 폴더만 등록하고 차단 정책을 보존 |
| 신뢰 위치 정책 레지스트리 | https://github.com/microsoft/ActiveDirectoryTierModel/blob/main/config/admx/office16.admx | `allow user locations` 정책 값의 실제 이름 확인 |
| Excel 신뢰 위치 정책 | https://github.com/microsoft/ActiveDirectoryTierModel/blob/main/config/admx/excel16.admx | `alllocationsdisabled`, LocationN의 Path와 AllowSubfolders 확인 |
| RC4 실행 프로세스·인자 | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1 | 2026-09-15 확인. 프로세스 한정 ExecutionPolicy와 `-File`의 인자·종료 코드 전달 |
| RC4 실행 정책 우선순위·차단 해제 | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies | 2026-09-15 확인. 그룹 정책 우선, RemoteSigned와 단일 파일 Unblock-File의 의미 |
