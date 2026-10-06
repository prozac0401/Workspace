# DownloadVersionManager 0.2.1 정식 Release·Pages 게시

날짜: 2026-10-06 한국시간 · 기준 원격: `c866435e278d84d4a110b5c3b23101e6dab53628`

## 요청과 변경

사용자가 최신 DVM 내용으로 Workspace GitHub Pages를 갱신하고, 검증된 정상 0.2.1 MSI의 정식 GitHub Release 게시까지 명시 승인했습니다. 기존 검증 source·설치 제작 입력·시험 source·요구/설계/검증 기록을 소스 커밋에 보존합니다. 원래 사용자 작업은 별도 checkout에 그대로 유지합니다.

공개 안내·첫 화면·교육 업무 안내를 0.2.1의 설치 승인/일반 권한 실행, 실패 복구, 트레이 열기·종료, 수정 시각 History 이름, 읽기 전용 보존과 지원 범위에 맞춥니다. 공개 안내 20개·이전 주소 이동 2개·허용 자산을 유지하고 메뉴 이름에서 이전 시험용 표시를 바꿉니다. 원시 로그·개인 경로·SID·백업·실패 주입 MSI는 공개하지 않습니다.

## 배포할 고정 파일과 소스

태그는 `download-version-manager-v0.2.1`, 정식 Release는 `prerelease=false`입니다. 정상 MSI와 `SHA256SUMS.txt` 두 파일만 배포합니다. 이미 실제 검증한 정상 MSI를 그대로 재사용하며 앱·MSI 재빌드나 제품 수동 시험은 반복하지 않습니다. CI의 재빌드 artifact를 이번 자산으로 대체하지 않습니다.

- MSI: `DownloadVersionManager-Watcher-0.2.1-x64.msi`, 380,928 bytes, SHA-256 `0feea2fc119bad780da9dcb57d2a0303ef0e2e0c6f6a20a746fd3ab3f86a0ef5`
- EXE: SHA-256 `3cddb6e185c7f1741cce6bb9b5b91f9afb3898a7a983598cfdc976e1be592abd`
- 소스: 배포 작업본에서 정상 패키지 제작 입력 20개의 Windows 작업 파일 지문이 기존 기록과 일치합니다. Git의 표준 텍스트 줄바꿈 정규화와 패키지의 Windows 입력 파일 해시는 구분합니다.

[정상 MSI](https://github.com/prozac0401/Workspace/releases/download/download-version-manager-v0.2.1/DownloadVersionManager-Watcher-0.2.1-x64.msi) · [Release](https://github.com/prozac0401/Workspace/releases/tag/download-version-manager-v0.2.1) · [체크섬](https://github.com/prozac0401/Workspace/releases/download/download-version-manager-v0.2.1/SHA256SUMS.txt) · [공개 안내](https://prozac0401.github.io/Workspace/tools/download-version-manager/)

## 재사용한 실제 검증과 한계

2026-10-06 Windows 11 x64 한 PC에서 설치 시작 전·진행 중 취소, 정상 MSI와 프로그램·설정이 같은 시험 MSI의 후반 실패 뒤 자동 원상복귀, 정상 재설치·일반 권한 실행·종료·제거를 통과했습니다. 실패 후 별도 제거·수동 정리 전에 전후 상태 일치를 확인했으며 원래 설치 위치·사용자 설정으로 최종 설치를 마무리했습니다. 업무 자료 보존은 측정한 직하 항목의 metadata 범위이며 내용을 전수 읽은 판정으로 확대하지 않습니다.

과거 FAIL·NOT RUN과 초기 0.2.0 후보/최종 공개 파일의 차이는 보존합니다. 다른 PC·모든 실패 지점·다음 로그인·동작 중 다운로드 위치 변경·조직 도입 승인으로 확대하지 않습니다. 코드 서명은 없습니다.

## 게시 확인

문서 strict 빌드·공개 경로/자산·검색/사이트맵·로컬 연결·diff 검사와 독립 문구 검토가 완료되면 이 소스 커밋을 PR로 검토합니다. GitHub 자동 검사 성공 뒤 태그·Release 자산을 게시하고 실제 다운로드의 SHA-256을 대조합니다. Pages 배포 성공과 실제 공개 페이지 내용·링크를 확인해야 게시 완료로 판단합니다. 실제 커밋·Actions·Release·Pages 결과는 이 변경 PR 본문에 기록하며 게시 전 계획과 완료된 결과를 구분합니다.
