# 보이는 칸 붙여넣기 · 단일 설치 파일 후보

기록일: 2026-09-27 · 책임: 개발·검증 담당 · 상태: 패키징·자동 설치 검증 완료, 실제 Excel 검증 대기

관련 문서: [ADR-0019](../design/0019-visible-cells-paste-single-installer.md), [사용·재현 안내](../../tools/VisibleCellsPaste/docs/single-installer.md), [백로그](WORKSPACE_Tool_Backlog_20260926.md)

## 산출물

| 항목 | 확인값 |
|---|---|
| 단일 EXE | VisibleCellsPaste-0.1.1-Setup.exe · 177,664 bytes |
| EXE SHA-256 | `bd55f32f3a9d467ed288696c8e80dd7f5e9eb97a280ba12a25fe622a5d26b464` |
| 제품/wrapper 버전 | 0.1.1 / 0.1.1.1 |
| 포함한 공개 ZIP | 165,320 bytes · SHA-256 `9555bf97c0d8ea0219a0692e6b1aad5594864a34af9cbf119c07fa7edbb20fa0` |
| 설치된 x64 DLL | SHA-256 `7080305afd5a08b2184fbedf9ed3942502184213d096c33864ab3ce1c2ab0329` |
| 서명·게시 | 서명 없음, 로컬 평가 후보, 공개 게시 없음 |

산출물은 작업 트리의 `artifacts/visible-cells-paste/single-0.1.1`에 있다. 소스와 입력 ZIP·산출물 해시를 single-installer-manifest.json에 기록했다. 로컬의 같은 이름 ZIP은 153,008 bytes·SHA-256 `da11aacdaf2240c674903f7a6594160df8dc85d36da655e23ed2ca045641c9fd`로 공개본과 달라 사용하지 않았다. 공개 자산을 직접 다운로드해 자산 메타데이터의 해시와 대조했다.

## 실행한 검증

| 범위 | 결과 |
|---|---|
| 공개 ZIP 정적 검사 | PASS · 17개 명시 inventory·16개 내부 해시·x86/x64 PE·COM/Ribbon·시험용 오류 주입 제외 확인 |
| 새 wrapper 회귀 | PASS · 24개: 인자 제한, 경로 이탈/중복/크기 거절, 추출·자기 파일 정리·미지 파일 보존, 실제 Windows child 프로세스에서 한글·공백·따옴표·빈 인자·끝 역슬래시 보존 |
| 기존 ZIP→단일 EXE 전환 | PASS · 기존 schema1 installation.xml·동일 DLL 바이트·단일 제거 등록 유지 |
| 잠금 실패와 후속 복구 | PASS · 실패 종료, 기존 DLL·매니페스트 바이트 유지, 잠금 해제 후 재설치 |
| 사용자 변경 보존 | PASS · 시험이 새로 설치한 LoadBehavior=0과 미지 레지스트리 값 보존. 기존 사용자 보안/비활성화 설정은 변경하지 않음 |
| 제거·반복 제거 | PASS · 소유 DLL/manifest 제거, 미지 파일·등록 보존, 반복 제거 안전 |
| 설치 수명주기 합계 | PASS · 19개. 한글·공백·작은따옴표를 포함한 전용 시험 경로, Office 설정·타 추가 기능 지문 동일 |
| 기본 경로의 실제 EXE 실행 | PARTIAL · 설치 안내 화면에서 실행, 기본 경로의 schema1 매니페스트와 공개 DLL 확인. 완료 대화상자 처리는 아래 도구 문제로 대기 |
| 새 EXE로 설치한 뒤 실제 메뉴·붙여넣기·Undo·정상 종료 | NOT_RUN · 완료 창 정리 후 이어서 확인해야 함 |

초기 wrapper 시험은 정상적으로 발생한 InvalidDataException을 시험 helper가 허용된 거절로 분류하지 않아 실패했다. helper의 예상 예외 판정을 수정한 재실행은 24개 모두 통과했다. 제품 설치 전의 시험 실패이며 숨기거나 최초 실행을 PASS로 바꾸지 않는다.

## 현재 중단 지점과 이어갈 순서

실제 설치 완료 창에 대해 UI 도구가 `window id … no longer belongs to Microsoft.VisualStudio.Installer; current owner is Microsoft.VisualStudio.Installer` 오류를 반환했다. 창 목록을 다시 받아도 같은 오류여서 화면 내용을 읽거나 확인 버튼을 조작하지 못했다. 사용자에게 결과 확인과 창 닫기를 요청했다. 설치 프로세스를 강제 종료하거나 다른 설치/Excel 시험을 겹쳐 실행하지 않았다.

창이 닫힌 뒤 기본 설치 DLL·프로세스 상태 확인 → 정상 Excel 시작과 실제 메뉴 → 합성 자료 복사·붙여넣기·즉시 Undo → UI 종료와 프로세스 부재 → 재시작·제거 후 메뉴 부재를 수행한다. 이 기록만으로 T05 전체 완료나 T12 공존 통과를 선언하지 않는다. x86 Office·새 프로필·재부팅·등록 ACL/전원 차단은 미실행이다.

상세 자동 검사·설치 증거는 `artifacts/visible-cells-paste/single-lifecycle-2203bd556c81406dbdd709ee8b39959f`와 `single-0.1.1`에, UI 장애 기록과 공개 ZIP은 로컬 감사 디렉터리에 보관한다. 개인 경로·원시 로그는 공개 사이트에 포함하지 않는다.
