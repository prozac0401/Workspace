# ADR-0023 · R13 현재 계정의 최소 설치 시험과 기존 설치 원복

상태: 채택 · T11 부분 실행·RC11 파일/등록 복구 · 실행 view의 원래 권한 복구·대표 비교·결과 및 일반 설치 대조 미완료

날짜: 2026-10-04 · 적용: 동일 RC13 후보의 T11 한 흐름

결정 담당: 도구 개발·검증 담당. 2026-10-04 설명한 현재 계정 한 흐름의 실행·원복 범위에 대한 사용자 진행 지시를 확보했다.

관련 요구사항·정책: [최초 명세](../../../docs/tools/excel-list-compare/specification.md)의 REQ-EXCEL-014~017, [R13 명세](../../../docs/tools/excel-list-compare/r13-specification.md)의 R13-02~03, [추가 도구 개발 기준](../../../docs/policies/tools.md), [정책 문서 작성 규칙](../../../docs/policies/documentation.md).

대체·대체됨 관계: [ADR-0021](ADR-0021-R13-focused-wording-evaluation.md)의 보존 가능한 환경에서 T11을 실제 확인한다는 조건은 유지한다. 별도 시험 환경을 먼저 확보하는 실행 제안 대신 승인된 현재 계정 경로를 적용한다. [ADR-0022](ADR-0022-R13-known-statusbar-evaluation.md)의 동일 후보 StatusBar 평가 예외·결정 SHA·원시 native FAIL은 변경하지 않는다. 이 결정은 실제 실행 성공이나 회사 배포 승인이 아니다.

## 맥락

사용자는 별도 Windows/Excel 환경 대신 현재 계정만 사용할 수 있다고 알렸다. 이 답변은 환경 정보이며 기존 제품의 실제 업그레이드·제거·원복이나 신뢰 등록 재생성을 승인한 것으로 해석하지 않는다. 기존 fresh-install 절차는 Upgrade/Repair 발견 시 중단하는 절차였으므로 현재 계정에서 그대로 실행하지 않는다.

그 후 RC11→RC13 임시 업데이트·대표 비교·RC13 엔진 제거·기존 RC11 파일/등록/제품 신뢰 원복의 정확한 범위를 설명했다. 사용자가 자리를 비우는 동안 진행 가능한지 직접 지시했고, 그 설명된 한 흐름의 실행 승인으로 기록했다. 원래 제품만의 신뢰 복원, 필요한 원래 ACL 복원과 시험 소유 창 위치의 조건부 원복을 포함한다. 보안·인증 화면 선택은 사람이 직접 수행한다. 범위를 벗어나는 회사 정책·다른 추가 기능·신뢰 위치 변경은 허용하지 않는다.

2026-10-04 현재 설치의 manifest, 제품·제거 관리 폴더의 Setup 버전, XLAM의 `SLC_ReleaseVersion`을 읽어 모두 `0.2.0-rc.11`임을 확인했다. XLAM SHA-256은 `9b37c2f05318ef4500784978f62c0ea948bd2e703ef3e5590874c0ef89988176`이며 추출한 실행 소스 6개는 RC11 태그와 정규화 대조에서 같았다. RC12의 Main/Report 소스와는 달랐다. 이는 저장된 VBA 소스의 정체 확인이며 매크로 실행·전체 runtime·p-code 검증이 아니다.

이번 RC13 제작·native 기록에서 같은 `9b37…88176` 설치를 R12라고 부른 것은 버전 표기 오류였다. 당시 파일 보존 관찰과 실패·성공 원시 기록은 유지하고 이 후속 정정을 함께 읽는다. 공개 R12 릴리스·RC12 소스 기준과 과거 R12 시험 생략 결정은 정정 대상이 아니다.

준비 당시 기록: 현재 계정 시험 준비로 기존 제품 5파일과 제거 관리 폴더 5파일의 비공개 백업 해시 일치를 확인했다. 선정된 레지스트리 32개 영역과 제품·관리 파일·폴더 및 제품 신뢰 키의 ACL 14개 기록도 비공개로 보존했다. 백업 준비 후 원본 상태 불변을 확인했으며 설치·제거·원복·T11은 모두 NOT_RUN이다. 읽을 수 있는 백업과 해시 일치는 실제 복원 성공을 증명하지 않는다. 후속 실제 결과는 현재 계정 결정과 검증 기록을 따른다.

## 승인된 실행과 변경 범위

승인된 현재 계정의 다음 한 흐름만 실행한다. 동결한 소스 입력 7개의 SHA와 RC13 후보 SHA `484419befa0cd763635b1f9592cff43bd13e657e19d5a693d76a78fa071ed14e`를 그대로 사용한다. 후보를 다시 빌드하지 않는다.

1. 업무 통합문서가 저장되고 Excel이 모두 닫힌 상태인지 확인한다. 비공개 입력·백업·제품 manifest·파일·등록·ACL을 시작 전 기준과 다시 대조한다. 출처 불명 파일이나 외부 변경이 발견되면 시작하지 않는다.
2. 비공개 엔진 입력으로 **RC11→RC13 Upgrade**를 실행한다. 사용자에게 제품 파일 5개와 해당 제품 자동 로드·추가 기능 등록의 교체 범위를 보여 준다. 기존의 정확한 제품 신뢰 등록은 재사용한다. 회사 정책·영구 매크로 보안·다른 신뢰 위치는 바꾸지 않는다.
3. 정상 Excel 시작에서 설치 경로의 동일 후보 자동 로드·메뉴를 확인한다. 전용 합성 원본으로 Alpha/Beta/Beta와 Alpha/Beta/Gamma를 대표 비교한다. 각 목록 3개, Beta 개수 차이와 Gamma 둘째만 있는 차이 2행, 제외 0개를 실제 결과에서 확인한다. 원본 값·서식·저장 내용과 기존 비교 설정·다른 추가 기능은 보존한다. 이미 완료한 새 안내·Replace·전체 GUI 시험은 반복하지 않는다.
4. 시험 소유 결과와 원본만 정상 닫고 소유 Excel의 자연 종료를 확인한다. 엔진의 Uninstall로 RC13 제품 파일·해당 제품 OPEN/Manager·소유한 제품 신뢰 등록 제거를 확인한다. 기존 제거 관리 폴더 5파일과 Windows 앱 제거 등록은 유지한다. **`unins000.exe`는 실행하지 않는다.** 최종 EXE 설치·제거를 수행한 것으로 기록하지 않는다.
5. 외부 변경이 없다는 재대조와 사용자 확인 범위 안에서 백업한 기존 RC11 제품 5파일을 원래 바이트·기록된 속성·시각·ACL에 맞춰 복원한다. 기존 제품 OPEN/Manager의 값·자료형·부재와 정확한 제품 신뢰 등록도 시작 전 기준으로 복원해야 한다. 관리 폴더와 Windows 제거 등록은 변경하지 않고 보존을 확인한다. 파일·선정 등록·설정·ACL 및 소유 정리를 실제 대조한 뒤에만 원복 완료로 판정한다.

일반 Excel 시작이 `Options.Pos`를 바꾼 경우에도 전체 Options 키를 덮어쓰지 않는다. 모든 Excel의 종료를 확인한 뒤 현재 자료형·값이 기록한 시험 최종값과 여전히 같을 때만 시작 전 자료형·값·부재로 복구한다. 다른 Options 값이나 외부 변경이 있으면 중단한다. 선정 ACL 14개를 최종 대조하며, 복원 대상 제품 폴더·제품 5파일·제품 신뢰 키에 필요한 원래 ACL만 복원한다. 관리 파일·다른 보안 ACL은 바꾸지 않는다.

보안·신뢰 확인 화면은 사람이 선택한다. 제거 후 제품 신뢰 등록을 되살리는 행동도 매크로 실행 신뢰를 다시 등록하는 보안 행동이다. 이번 진행 지시는 일반 파일 복원에 더해 설명한 정확한 기존 제품 신뢰 복원도 포함한다. 제품 폴더만 허용하고 하위 폴더를 포함하지 않는 기존 범위를 그대로 복원한다. 정책·보안 화면을 자동으로 승인하거나 우회하지 않는다.

## 검토한 대안

- 별도 Windows/Excel 환경: 기존 설치 변경이 줄지만 현재 사용자가 이용할 수 없다. 그 경로의 준비물과 NOT_RUN 기록은 보존한다.
- 현재 계정에서 제거 없이 후보 직접 열기: 이미 확인한 격리 native를 반복할 뿐 실제 Upgrade·정상 자동 로드·제거 조건을 확인하지 못한다.
- 기존 RC11 설치 프로그램 재실행으로 복구: 설치 시각·신뢰 소유 토큰 등이 달라질 수 있어 정확한 시작 전 상태 복원과 같지 않다. RC13이 남은 상태에서 더 오래된 installer는 downgrade를 거절한다.
- Windows 앱 제거 프로그램 실행: 관리 파일과 앱 등록까지 제거하므로 제안하는 엔진 T11의 필요한 범위를 넘는다.

## 실패와 복구

제품 밖 경로·불명 소유권·reparse point·해시 불일치·새 외부 변경·정책 차단·사용자 Excel 발견 시 중단하고 현재 상태를 보존한다. 관찰하지 않은 값을 삭제하거나 전체 registry를 가져오지 않는다. 업무 파일을 저장·닫거나 Excel을 강제 종료하지 않는다.

Upgrade 자체의 실패 rollback과, 성공한 Upgrade 이후 제거·기존 RC11 원복은 다른 동작이다. 엔진은 성공한 설치를 제거할 때 이전 RC11을 자동 복원하지 않는다. 외부에서 달라진 파일·등록을 백업으로 덮어쓰지 않는다. 기대한 시험 소유 변경과 실제 현재값이 일치하는 항목에만 좁은 복구를 제안하고 미복원 항목은 별도로 남긴다.

준비 당시 기록: 읽기 검토에서 논리적으로 원복 불가능한 사유는 발견하지 못했으나 실제 복원은 검증되지 않았다. 백업·계획 완성으로 안전한 실행이나 실제 복구 PASS를 미리 주장하지 않는다. 제품 보존·보안·소유 정리 실패는 StatusBar 예외에 포함하지 않는다. 후속 실제 결과는 현재 계정 결정과 검증 기록을 따른다.

## 2026-10-04 현재 계정의 부분 T11과 제품 복구

승인된 동일 후보·동결 7입력으로 공식 Install.cmd를 한 번 실행해 RC11→RC13 Upgrade를 확인했다. 설치 엔진은 exit 0·InstallCommitted였다. 첫 실행 기록의 root 검증은 manifest 해시의 대소문자 대조 때문에 FAIL이었고 원문을 보존했다. 별도 읽기 대조가 실제 설치 바이트·manifest·등록·관리 파일·ACL 보존을 확인했으며 설치를 반복하지 않았다.

정상 Excel 시작에서 설치된 동일 RC13의 자동 로드를 확인하고 전용 합성 원본을 준비했다. 첫 화면 관찰이 Windows 잠금 화면이어서 UI 입력은 0회였고 목록 담기·대표 비교·결과 관찰은 실행하지 않았다. NOT_RUN_INCOMPLETE·observedFlowComplete=false·비어 있는 productActions와 원시 기록을 유지한다. 시험 소유 Excel은 cleanupErrors 없이 자연 종료했고 남은 Excel은 없었다. 후보 SHA와 제품·관리 파일은 그대로였다. 이미 완료한 새 안내·Replace 흐름이나 전체 GUI를 반복하지 않았다.

정리 후 선정 상태에서는 Options.Pos와 제품 밖 Trusted Documents.LastPurgeTime DWORD가 달라졌다. 두 값은 HKCU 32/64 대조에 같은 영역의 alias로 나타났다. LastPurgeTime의 원인은 미확정이며 제품 회귀나 Office 자동 정리로 단정하지 않는다. 최초 Pos 복구 guard는 이 외부 차이를 발견해 쓰기 없이 FAIL로 중단했다. 별도 독립 검토를 거친 좁은 복구가 관찰된 LastPurgeTime을 그대로 두고 승인된 시험 소유 Pos만 원래 typed 값으로 복원했다. Pos 기록의 nonProductRegistryWritesExecuted=false는 명칭이 넓어 실제 승인된 Pos 쓰기를 제외한 무소유 영역 쓰기 없음으로 별도 정정했다. 원시 기록은 수정하지 않았다.

동결 Uninstall.cmd의 공식 엔진 제거는 exit 0이었다. 후보 제품 파일·해당 OPEN·제품 신뢰 항목의 부재와 원래 관리 파일·Windows 앱 제거 등록 보존을 확인했다. unins000.exe는 실행하지 않았다. 이어 첫 제품 복구는 빈 제품 폴더를 만든 뒤 권한 exact 대조 실패로 중단했다. 이때 원래 제품 파일·등록 쓰기는 없었다. owner/group·DACL control은 같았지만 ACE 내용·순서가 달랐다. [SetNamedSecurityInfo의 상속 전파](https://learn.microsoft.com/en-us/windows/win32/secauthz/automatic-propagation-of-inheritable-aces)와 부합하는 추론이며 원래 기록의 실패를 지우지 않는다.

실패가 만든 빈 폴더의 identity·현재 SDDL·전체 선정 상태를 고정하고 SetFileSecurityW로 원래 owner/group/DACL을 전달했다. [이 API는 obsolete](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-setfilesecurityw)이며 일반 제품 설치 변경에 적용하지 않았다. 성공 반환 뒤 owner/group·전체 ACE 순서는 원래와 같았지만 자동 상속 AI 표시가 없어 exact SDDL 복원은 다시 FAIL이었다. [AI는 자동 상속 지원 표시](https://learn.microsoft.com/en-us/windows/win32/secauthz/security-descriptor-control)이므로 의미 없는 문자열 차이라고 단정하지 않는다. 두 번째 실패와 실제 차이를 보존했다. 파일·제품 등록은 이 시도에서도 쓰지 않았다.

이어 관찰된 단일 AI 표시 차이를 그대로 두고 원래 제품 5파일을 exclusive 생성으로 복구했다. 이 단계는 제품 폴더 ACL을 더 쓰지 않았다. actual SDDL을 숨기거나 원래 ACL 기록을 고치지 않았으며, owner/group·전체 ACE가 원래와 같고 AI 표시만 다르다는 guard를 고정했다. 파일의 바이트·기록 속성·시각 복원은 완료했지만, 제품 신뢰 키 생성 호출 뒤 Python 레지스트리 핸들 객체 구성 오류로 중단했다. 빈 제품 신뢰 키가 생성돼 있었고 Path·OPEN은 없었다. 원시 registryWritesExecuted=false가 이 빈 키 생성을 집계하지 못한 점을 실제 상태 대조와 별도 정정으로 보존했다.

최종 등록 복구는 이미 생성된 동일한 빈 키의 수정 시각·원래 ACL·전체 선정 상태를 다시 고정했다. 파일·ACL을 더 쓰거나 키를 생성·삭제하지 않고 winreg.OpenKey로 기존 키를 열어 원래 자료형의 소유 식별자·제품 ID·설명·하위 폴더 제한 4값을 쓰고, 제품 신뢰 Path와 원래 OPEN을 마지막에 복원했다. 각 단계의 실제 snapshot과 자료형을 대조했다. 최종 제품·관리 10파일의 바이트·기록 속성·시각과 원래 OPEN·제품 신뢰·다른 선정 영역을 확인했다. ACL 14개 중 13개는 원래 SDDL과 같고 제품 폴더 1개만 기록한 AI 차이를 유지했다. 다른 ACL 차이는 허용하지 않았다.

등록 복구 단계의 결과는 ORIGINAL_BYTES_REGISTRATION_RESTORED_WITH_OBSERVED_DIFFERENCES였다. exactAclRestored=false·exactOriginalProductRestored=false·exactSelectedStateRestored=false다. LastPurgeTime은 관찰값을 쓰지 않고 보존했다. 파일·등록 복구 완료를 정확한 제품·선정 보안 상태 전체의 원복이나 T11 PASS로 확대하지 않는다. AI 표시 차이를 평가 출시 조건으로 수용하는 결정을 내리지 않았다. 대표 비교·결과와 보존 미완료가 남아 T11은 PARTIAL / NOT_RUN_INCOMPLETE이며 StatusBar 예외가 이를 수용한 근거는 아니다. 최종 wrapper 실제 설치·포장·병합·태그·Release는 NOT_RUN, fullAcceptancePassed=false·stablePublishAllowed=false를 유지한다.

후속 복구 후보 진단은 비공개 출력 아래 새 빈 디렉터리 2개에만 한정했다. 같은 원래 descriptor에서 AI만 없는 시작 상태를 재현하고 `SetNamedSecurityInfo(info4)`와 독점 handle의 `SetSecurityInfo(info4)`를 비교했다. 두 API는 반환 0이었고 AI는 생겼지만 owner/group이 같은 상태에서 ACE가 5개에서 4개로 바뀌어 전체 원래 descriptor exact는 모두 false였다. 진단 완료는 복구 성공이 아니며 두 후보를 실제 제품에 적용하지 않았다. 설치 파일·등록·선정 상태와 현재 관찰 ACL 14개, 시험 부모 ACL의 불변을 대조했다. 제품·등록 쓰기·Excel 실행·설치·UI 입력은 없었다. 다른 시험 부모에서의 결과이므로 원래 실제 경로의 내부 원인 확정이나 복구 불가능 판정으로 확대하지 않는다. 동결 진단 소스 SHA는 `3525dc319c0b8d3e4d2c281eeac1568b27dd18108573b19b3f5d6d4505c15ef7`, 원시 기록 SHA는 `4fb338a639fb74acf88508af67144860be8ac5409807e4f8f552dfb12f291683`이다. 이 결과로 T11 또는 출시 조건을 완화하지 않는다.

## 2026-10-04 현재 실행 view의 ACL 복구와 남은 환경 대조

후속 빈 폴더 시험에서는 원래 전체 descriptor에 `SE_DACL_AUTO_INHERIT_REQ`(AR)만 메모리에서 추가하고 `SetFileSecurityW(info7)`를 적용했다. 원래 owner/group·ACE 5개·AI가 모두 정확히 일치했고 AR는 남지 않았다. 별도 원래 제품 5파일을 복사한 시험에서도 디렉터리만 한 번 적용한 뒤 파일의 바이트·기록 속성·생성/최종 쓰기 시각·identity·원시 ACL의 전후 동일성을 확인했다. 적용 후 자식 setter로 차이를 보정하지 않았다. 두 시험의 실제 설치 선정 상태·관찰 ACL 14개·시험 부모는 불변이었다. 빈 폴더 소스/원시 SHA는 `765fc8a4fbffaf20dcdd65ae0dddf9ccdd5182a0b5c9fb1ea68d198353b128d0` / `2ca5c7b7333747c6ac4c8463301966380eb8a41438765a209b6152a3d91f9318`, 5파일 시험은 `fb5f667cd98f7645c7b42a2c590e35d984349c8901b358b1ac6d2240e4d1a70f` / `c5e3d31a8d876d5547263f85172c1b45c7159a21ac192b53c57a9e23fe1151ce`다. 이 AR 요청은 [공식 control API](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-setsecuritydescriptorcontrol)를 사용한 원래 객체 복구 진단이며 제품 설치 엔진 변경이 아니다.

실제 대상의 첫 적용 시도는 `GetFinalPathNameByHandleW` 반환 경로와 논리 경로의 차이를 발견해 setter 전 `FAIL / NOT_RUN`으로 중단했다. 권한·파일·등록 쓰기는 없었고 실패 기록은 보존했다. 반환 경로는 Codex 패키지 LocalCache 아래였다. 별도 읽기 대조로 논리/물리 디렉터리와 원래 5파일의 device/inode·handle volume/file index·final path·바이트·기록 metadata·원시 ACL 전체가 같은 것을 확인했다. 원래 소유 directory identity와 두 부모 ACL도 고정했다. 매핑 원시 SHA는 `949501fbdf6f0e5ec182dff8523dbcdce5fcfc534132e52f348ae09c1f0318e7`이다.

이 동일 소유 객체에 한정한 새 복구 helper는 정확한 매핑·소유 identity·파일 10개·선정 32영역·권한 14개·부모 2개·Excel 없음·설치 mutex를 다시 대조한 뒤 논리 제품 경로의 descriptor를 한 번 적용했다. API BOOL 1/error 0, 전체 원래 directory SDDL과 자식 5파일 ACL, 원래 ACL 14개 모두 exact를 실제 확인했다. 파일·등록·부모·명시적 자식 setter는 실행하지 않았다. 자동 상속의 자식 영향은 setter 부재만으로 주장하지 않고 실제 자식 권한과 파일 전후 대조로 확인했다. 제품·관리 10파일의 바이트·기록 metadata, 제품 등록·두 부모·제품 5파일 identity는 보존됐다. 실제 복구 소스 SHA는 `e3bf8eee3407d110c16ccadd945e4817a65a07c949f14bd2f31f438ccdd565b7`, 원시 SHA는 `a41c42383356f027044fcd9d35a0166d4f6fedf6d94c05b31b2b3b1701d22bb4`다.

이 성공은 현재 실행 view에서 관찰한 소유 객체의 복구다. [MSIX 문서의 private-first/fallback 동작](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)과 부합하지만, 최초 RC11 백업·Upgrade 때의 물리 경로까지 같은 것을 증명하지 않는다. 일반 Windows/Excel이 보는 제품 파일·OPEN·신뢰 등록의 연결도 아직 확인하지 못했다. `GetCurrentPackageFullName`이 package identity 없음으로 반환한 같은 Python에서도 LocalCache final path가 관찰돼, 이 API 하나만으로 일반 실행 view를 확정하지 않았다. OPEN/신뢰 경로를 물리 경로로 바꾸거나 실제 AppData를 추가로 수정하지 않았다.

LastPurgeTime의 관찰값은 그대로이며 `exactSelectedStateRestored=false`, `initialBackupPhysicalViewConfirmed=false`, `nativeUnpackagedInstallationVerified=false`다. 원래 AI 차이가 남았다는 판단은 위 후속 실제 복구로 갱신하되, 과거 실패·원인 미확정·현재 환경 한계를 보존한다. 대표 비교·결과는 계속 미실행이고 T11은 PARTIAL / NOT_RUN_INCOMPLETE다. 새 Upgrade·Excel 실행·최종 EXE 설치·포장·병합·태그·Release는 이 복구에서 수행하지 않았다. StatusBar 예외·전체 인수 및 안정판 금지는 변경하지 않았다.

다음 최소 확인은 사람이 시작 메뉴에서 연 일반 PowerShell의 읽기 전용 대조다. 제품/관리의 알려진 10파일·handle 실제 경로·원래 권한 14개·선정 32영역을 새 비공개 기록에 읽고 전후 불변을 확인한다. 설치·Excel 시작·파일/등록/보안 변경은 없다. 일반 설치 view와 현재 관찰 view의 차이가 있으면 새 시험을 시작하지 않고 원래 백업·실제 값과 관계를 분석한다. 동일성이 확인된 뒤에만 최신 계속 지시 범위에서 같은 후보의 미완료 T11 재개 계획·새 시작 기준·원복 guard를 별도로 고정한다. 과거 한 흐름 기록을 수정·재사용하거나 사람이 재시도를 금지한 것으로 확대하지 않는다.

원시 백업·ACL·registry 값·사용자 경로·화면·진단은 artifacts에 비공개로 보존한다. 공개 기록에는 이 요약만 싣는다.

## 검증과 출하 판단

T11은 실제 설치 후보·정상 자동 로드·대표 비교·결과 관찰·원본/설정/다른 추가 기능/보안 보존·제거·기존 제품 원복·소유 결과 정리·자연 종료의 12조건을 각각 실제 증거와 연결한다. `scope=T11-install-compare-result-remove`, `flowCount=1`, 동일 후보와 7입력 SHA를 기록한다. 준비용 NOT_RUN 체크리스트를 PASS로 편집하지 않는다.

현재 계정 T11은 PARTIAL / NOT_RUN_INCOMPLETE다. 공식 엔진 Upgrade·정상 자동 로드와 엔진 제거는 확인했으나, Windows 잠금 화면에서 중단해 대표 비교·결과는 실행하지 않았다. 현재 실행 view에서 관찰한 RC11 파일·등록·제품 신뢰와 원래 ACL 14개 복구를 실제 확인했다. 제품·관리 10파일의 바이트·기록 속성·생성/최종 쓰기 시각과 부모 2개 권한도 보존됐다. 제품 폴더 handle의 실제 경로는 Codex 패키지의 LocalCache 아래였고, 같은 소유 객체·5파일의 논리/물리 identity·원시 권한·내용 일치를 고정했다. 최초 백업의 물리 경로와 일반 Windows/Excel의 설치·등록 view 연결은 아직 미확인이다. 제품 밖 LastPurgeTime의 원인 미확정 관찰값도 쓰지 않고 보존했다. 전체 선정 상태 원복·일반 Excel 설치 복구·T11 PASS로 확대하지 않는다. 최종 EXE 실제 설치·포장·병합·태그·Release는 미실행이며 공개 다운로드는 R12로 유지한다. 이 부분 실행은 기존 실패를 지우거나 T11 게이트를 완화한 결정이 아니다.

비공개 백업·registry 값·소유 토큰·사용자 경로·ACL·화면·원시 로그는 공개 문서·패키지에 넣지 않는다.
