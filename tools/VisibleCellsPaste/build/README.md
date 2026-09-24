# 제작 및 패키지 검사

빌드에는 Windows의 .NET Framework 4.8 C# 컴파일러와 Windows PowerShell 5.1이 필요합니다. 최종 사용자는 개발 SDK, Python, Node.js를 설치하지 않습니다.

~~~powershell
powershell -NoProfile -File tools/VisibleCellsPaste/build/build.ps1
powershell -NoProfile -File tools/VisibleCellsPaste/build/verify-package.ps1 -ZipPath artifacts/visible-cells-paste/0.1.1/VisibleCellsPaste_0.1.1.zip
~~~

이 스크립트는 레지스트리 또는 Office 보안 설정을 변경하지 않습니다. 소스를 두 아키텍처로 컴파일하고 설치 프로그램, 파일 해시, 한국어 안내 문서를 ZIP으로 만듭니다. 핵심/파서, 네이티브 클립보드 날짜, 대량 스냅샷, 연결 수명 주기, 실제 OLE 객체의 COM 참조 수명, 전역 상태 복구, 쓰기 진입·완료 표시 예외와 설치 경로/매니페스트 검사를 Excel 실행 없이 수행합니다. 설치 시험에는 한글·공백·작은따옴표·%·# 경로에서 실제 DLL을 로드하는 검사가 포함됩니다. 각 시험의 개수와 결과는 제작 폴더의 로그에 기록합니다. 이어서 ZIP 파일 목록/해시/PE 비트 수, COM 식별자, Ribbon 콜백과 프로덕션 오류 주입 필드 제외 여부를 검사합니다. 실행 중 Excel을 닫거나 설치하지 않습니다.

기존 출력은 일괄 삭제하지 않습니다. ZIP에는 명시한 제품 파일만 포함되며 진단 로그, 합성 통합문서, 테스트 실행 파일은 포함하지 않습니다. 날짜/컴파일 메타데이터가 있으므로 동일 소스의 재빌드가 바이트 단위로 같다는 약속은 하지 않습니다.

실제 Excel 자동 로드, 메뉴 클릭, 데이터 보존, 재시작 및 제거 시험의 결과는 docs/test-report.md에서 확인합니다. 빌드 통과는 이 시험의 통과나 조직 승인을 뜻하지 않습니다.

실제 Excel 시험용 실행 파일은 다음 명령으로 별도 생성합니다. 이 명령은 시험 실행 파일만 만들며 Excel을 실행하거나 시험을 자동 실행하지 않습니다. 시험 DLL에는 오류 주입 코드가 있으므로 사용자 ZIP에 포함하지 않습니다.

~~~powershell
powershell -NoProfile -File tools/VisibleCellsPaste/build/Build-ExcelTests.ps1 -Architecture x64
~~~
