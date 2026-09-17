# Excel RC4 · 간편 설치 실행기 검증

상태: 실행기 검증 완료, 서명 없는 후보 · 날짜: 2026-09-15

## 문제와 변경

실제 사용 PC에서 RC3 설치가 PowerShell `Restricted` 때문에 차단됐다. 사용자는 그룹 정책 두 항목이 `Undefined`임을 확인했고, 프로세스 한정 실행 허용·Setup.ps1 차단 해제·설치 실행으로 동작했다고 보고했다. 이번 RC4는 그 준비를 `Install.cmd`, `Uninstall.cmd`, `Test_Excel.cmd`에 포함한다. [결정과 경계](ADR-0005-Process-scoped-launchers.md)를 따른다.

ZIP을 모두 풀고 `Release/Install.cmd`를 더블클릭하면 된다. PowerShell 명령 입력과 실행 정책 변경 질문은 없고 제품 설치 확인창은 유지한다. 설치 후에는 Excel만 실행한다. 제거는 RC4의 `Uninstall.cmd`를 사용한다.

## 이번에 실행한 Windows 시험

`python -m unittest discover -s tools/ExcelSmartListCompare/tests -p test_launchers.py -v`에서 **6개 테스트 메서드, 20개 시나리오가 통과**했다. Windows PowerShell 5.1의 실제 프로세스와 NTFS 다운로드 표식으로 시험했다. 기존 Excel을 열거나 업무 자료를 설치 시험에 사용하지 않았다.

전체 `python -m unittest discover -s tools/ExcelSmartListCompare/tests -p "test_*.py" -v`에서는 **59개 테스트 메서드가 통과**했다. 기존 Python 참조·정적 검사 53개와 Windows 실행기 검사 6개를 합친 수이며, Excel 실기 59개라는 뜻이 아니다.

문서 환경에서 `python -m mkdocs build --strict`와 `python scripts/check-site.py`도 통과했다. 공개 14개 페이지와 404, 검색·사이트맵의 공개 범위, 로컬 경로·자산을 확인했고 변경 Markdown의 상대 링크 55개도 확인했다. 사이트를 외부에 배포하지는 않았다.

| 구분 | 시나리오 수 | 결과와 범위 |
|---|---:|---|
| Restricted + 인터넷 다운로드 표식 | 3 | 설치·제거·진단 실행기가 자기 Setup.ps1만 차단 해제, 프로세스 RemoteSigned·STA·작업 인자 적용, 0/2/37 종료 코드 전달 |
| 준비 실패 | 2 | Setup.ps1 누락과 차단 해제 오류 주입에서 종료 코드 1, 본체 미실행 |
| 기존 AllSigned | 1 | 실제 AllSigned 프로세스에서 서명 없는 본체 실행 차단, 파일 표식과 정책 보존 |
| 그룹 정책 읽기 모의 | 12 | 세 실행기 각각 Machine/User의 Restricted·AllSigned·RemoteSigned 조합에서 기존 정책 경로 선택, 표식 보존 |
| 실제 Setup.ps1의 중복 실행 잠금 | 2 | 설치·제거 본체가 시험 프로세스 소유 잠금을 확인하고 종료 코드 4로 중단 |

한국어·공백·작은따옴표·`&`·괄호·`$()`·느낌표·백틱이 있는 경로를 사용했다. 정상 실행에서 Setup.ps1 내용은 동일했고, 다른 스크립트와 합성 업무 파일의 다운로드 표식도 보존됐다. 부모 PowerShell의 실행 정책 목록과 프로세스 정책은 전후 동일했고 실행기 내부 환경 변수는 유출되지 않았다.

첫 시험에서는 개발 호스트가 주입한 PowerShell 7 모듈 검색 경로 때문에 Windows PowerShell의 보안 모듈 자동 로드가 실패했다. 시험 자식 프로세스에서만 주입 경로를 제거해 일반 Explorer 시작 환경으로 맞춘 뒤 재실행했다. 제품 실행기에 모듈·보안 설정 우회 코드를 추가하지 않았다. 원시 진단은 로컬 `artifacts`에 보존하고 배포에서 제외한다.

## 기존 검증과의 관계

Excel VBA와 XLAM은 RC3와 동일하다. XLAM SHA-256은 `c6f55886c368294c4e21396366d0cf3c368605e965f3ca2bd153f2e75bc8ae86`이다. Setup.ps1 본체는 설치기 버전만 `0.2.0-rc.4`로 바뀌며 설치 기록 형식과 복구 코드는 그대로다. 실제 Excel 비교·자동 로드·수명주기 기록은 [RC3 보고서](WINDOWS_ROBUSTNESS_REPORT.md)에 귀속된다.

RC4에서 Windows Excel 전체 수명주기·설치 확인창 클릭을 다시 실행하지 않았다. 그룹 정책은 읽기 결과 모의 시험이며 실제 회사 정책을 설정하거나 해제한 시험이 아니다. x86 Office, 다른 회사 PC, AppLocker/WDAC 및 조직 배포 승인은 미검증이다. 사용자 PC에서 성공했다는 보고는 RC3 수동 준비 절차에 관한 것으로 RC4 패키지 현장 검증을 대신하지 않는다.

## 배포와 재현

RC4 설치 ZIP에는 완성 XLAM, 설치·제거·진단 CMD, Setup.ps1, 오프라인 퀵가이드, 이번 보고서와 RC3 실기 기록을 포함한다. 수정 소스 ZIP은 릴리즈 커밋의 저장소 소스이며 실행기와 테스트·문서·패키징 스크립트를 포함한다. `SOURCE_COMMIT.txt`, `BUILD_INFO.json`, `SHA256SUMS.txt`로 소스와 파일을 구분한다. RC3 릴리즈 자산은 교체하지 않는다.

소스를 커밋한 뒤 `scripts/package-excel-launcher-release.py`에 기존 RC3의 Release 폴더와 저장소 `artifacts` 아래 새 출력 폴더를 지정한다. 패키징은 XLAM 기준 해시, ZIP 내 파일 해시, 소스와 스크립트 일치, 오프라인 HTML 로컬 링크를 검사한다. 결과물에는 코드 서명이 없다.
