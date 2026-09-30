# CI 범위

Windows GitHub-hosted runner에서 MSVC x64 static CRT·Windows SDK CNG Host, 별도 실패 주입 test Host, Node MV3 controller tests, 실제 NTFS host/protocol/concurrency 시험, 새 프로세스 자원 측정, WiX per-user MSI 제작과 구조/행정 추출/파일 SHA-256 검증을 실행합니다.

CI는 확장을 기존 브라우저 profile에 설치하지 않고 스토어 심사·실제 사용자 Chrome/Edge·interactive installer lifecycle을 PASS로 만들지 않습니다. 실제 실기는 별도의 기록과 source/package hash를 필요로 합니다. build 실패는 성공 MSI로 게시하지 않습니다. 자동 release 단계는 없고 stable gate 스크립트는 누락·FAIL·NOT RUN을 차단합니다.

관문 누락·평가 channel 차단과 loopback HTTP 합성 fixture 재현성도 자동 검증합니다. loopback 시험 서버는 시험 안에서 종료하며 제품의 background component가 아닙니다. 동시 요청의 완료 시각 순서 차이를 stable 관문에 별도로 표시합니다.

사용자 업무 문서·개인 profile·다운로드 기록을 읽지 않습니다. 합성 fixture만 생성하며 기본 출력은 `artifacts/download-version-manager`입니다. 정상제품에 실패 주입 기능·tests·로그·개인 데이터는 포함하지 않습니다. 생성 출력은 Git에 추가하지 않습니다.
