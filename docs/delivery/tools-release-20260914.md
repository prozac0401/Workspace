# FolderState와 Excel 도구 · 별도 릴리즈 기록

날짜: 2026-09-14 · 상태: 두 도구의 설치 가능한 평가용 배포 후보

같은 Workspace 저장소에서 소스와 패키지 버전을 분리했다. 코드 서명과 조직의 상용 배포 승인을 뜻하지 않는다. 일반 사용자 Windows 11 x64에서 실제 실행했다.

## FolderState 0.1.0 RC1

엔진·WPF·MSI 소스는 기존 검증본과 같다. 엔진 27/27, WPF smoke, 자체 포함 MSI 빌드, 패키지 검사와 실제 설치·복구·제거 12/12가 통과했다. 후속 잠금 해제 후 설치본 WPF에서 진행 중 → 완료 → 아이콘 복구 → 초기화를 직접 클릭하고 촬영했다. 합성 업무 파일의 해시가 유지됐고 초기화 후 제품 메타데이터가 제거됐다.

MSI: FolderState-0.1.0-win-x64.msi. SHA-256: `b96eb391ce3bbb3fb8a1ea2d025690cc9617d299a87064e8c272f02529f8fc67`.

설치창은 자동화 도구가 msiexec.exe 접근을 차단해 캡처·버튼 검증하지 못했다. 실제 명령줄 MSI 설치/복구/제거와 구분했다. Explorer 우클릭의 실제 클릭, 다른 Windows/SMB/동기화 환경은 이번 후속 시험 범위에 포함하지 않았다.

[FolderState 평가용 릴리즈](https://github.com/prozac0401/Workspace/releases/tag/folderstate-v0.1.0-rc.1)에 MSI, 해시, 실제 캡처 오프라인 퀵가이드와 검증 요약을 제공한다. 초기 릴리즈 기준 소스는 98a9f7c77ed18461b551914713b2b9287486bf80이며 후속 안내는 현재 커밋을 따른다.

## Excel Smart List Compare 0.2.0 RC1

실제 XLAM 빌드·기능·설치 수명주기를 완료했다. 최종 XLAM SHA-256은 `c6f55886c368294c4e21396366d0cf3c368605e965f3ca2bd153f2e75bc8ae86`이다. COM 빌드/등록/재열기 문제, XLAM 저장 순서, 설치 기록·실패 복구, Esc 입력 차단과 .cmd 종료 코드 문제를 수정했다.

저장된 XLAM의 내장 19개, COM 기능 7개, 일반 명령 14개, 경고/오류 복구 5개, 설치 안전장치 11개와 실제 도구 모음/Esc 입력을 각각 실행했다. 설치 → 정상 시작 → 재시작 → 재설치 → 메뉴 중복 없음 → 제거 → 재시작 → 반복 제거를 수행했다. 상세 통과·이전 후보 한정 통과·미실행은 [Excel 실제 보고서](../../tools/ExcelSmartListCompare/docs/WINDOWS_E2E_REPORT.md)에 구분한다.

[Excel 평가용 릴리즈](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.0-rc.1)는 FolderState와 별도 태그·자산으로 제공한다. 사용자용 Release ZIP과 수정 소스 ZIP을 분리한다. 예전의 BLOCKED_POLICY 소스만 있던 draft를 최종 설치 가능 후보로 갱신한다. x86·다른 Office·모든 상한 경계·대규모 최악 출력·Undo·조직 서명은 미검증/미승인이다.

## 복원과 공개 범위

21:22 KST 감사에서 두 도구 모두 미설치로 복원됐다. Excel 프로세스 0개, 제품 메뉴·등록 없음, 보안/정책/타 추가 기능 및 OPEN 값 14개 범주가 시작 전과 같았다. AccessVBOM 임시 허용은 원래 값 없음 상태로 원복했다. 원래 업무 파일·기존 Excel·다른 추가 기능을 변경하지 않았다.

패키지·해시·실제 캡처 안내·식별자 없는 검증만 공개한다. 원시 계정 SID·레지스트리·MSI 진단·사용자 자료는 로컬 artifacts에 둔다. Python, CI, 정적 검사를 실제 Excel 또는 화면 클릭 통과로 대체하지 않는다.
