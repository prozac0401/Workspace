# ADR-0004 · 실제 설치 경로 검증

상태: 구현에 채택 · 날짜: 2026-09-15 · 관련: [도구 개발 기준](../../../docs/policies/tools.md), [신뢰 위치 설계](ADR-0003-Product-trusted-location.md)

## 문제

실제 Windows 시험에서 같은 SID·세션이어도 실행 호스트의 AppData/HKCU 보기와 일반 데스크톱 Excel의 보기가 달랐다. 호스트 안의 설치는 성공하고 그 호스트에서 연 Excel은 로드했지만, 일반 COM Excel은 해당 XLAM을 찾지 못했다. 파일 핸들의 최종 경로와 일반 사용자 데스크톱에서의 별도 읽기로 차이를 확인했다.

## 결정

설치기는 복사한 XLAM과 교체 직전의 고유 임시 설치 기록을 `GetFinalPathNameByHandle`로 확인한다. 예상 절대 경로와 다르면 코드 6으로 중단하고 파일·자기 OPEN 값·자기 신뢰 위치를 기존 값으로 되돌린다. 새 설치 폴더가 비었으면 비재귀 삭제한다. 외부 파일은 보존한다. 사용자는 일반 Windows 파일 탐색기에서 Install.cmd를 실행한다.

임시 기록도 검사하는 이유는 기존 실제 파일의 읽기는 가능하지만 새 쓰기만 리디렉션되는 경우를 감지하기 위해서다. 경로 별칭·리디렉션된 설치 위치는 지원하지 않는다. 보안 설정이나 리디렉션 규칙을 바꾸지 않는다.

## 검증과 한계

실제 리디렉션 환경에서 코드 6과 기존 RC2 파일 해시 보존을 확인했다. 일반 사용자 환경에서 RC3 Install.cmd와 Excel 자동 시작을 별도로 실행했다. 상세 결과는 [실제 검증 보고서](WINDOWS_ROBUSTNESS_REPORT.md)를 따른다. 이 검사는 모든 레지스트리 가상화 형태를 탐지한다는 보장이 아니므로 정상 재시작 검증도 필요하다.

Microsoft의 [패키지 데스크톱 앱 실행 환경 설명](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)은 파일·레지스트리 리디렉션의 배경 자료다. 시험 환경의 판정은 로컬 파일 핸들과 실제 Excel 실행에 근거했다.
