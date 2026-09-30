# 설계 결정 목록

- [ADR-0026 · 다운로드 이벤트와 단발 Native Host](0026-download-version-manager.md) — 신규 객체 이름 승계, 변경 내용 History, 무상주·per-user MSI와 스토어 배포 관문

| ID | 결정 | 상태 |
|---|---|---|
| [ADR-0001](0001-engine.md) | 고정 메타데이터와 복원 가능한 최소 개입 엔진 | 구현에 채택 |
| [ADR-0002](0002-distribution.md) | 사용자별 MSI, 자체 포함 .NET, Explorer 클래식 메뉴 | 구현에 채택 |
| [ADR-0003](0003-documentation.md) | Markdown 원본과 GitHub Pages 문서 | 구현에 채택 |
| [ADR-0004](0004-public-handbook.md) | GitHub Pages를 업무 운영 정책·FolderState 사용법으로 제한 | 구현에 채택 |
| [ADR-0005](0005-explorer-refresh.md) | Explorer 아이콘 갱신과 내용별 Portable 아이콘 경로 | 구현에 채택 |
| [ADR-0006](0006-public-tool-downloads.md) | 두 도구의 공개 안내와 버전별 설치 파일 다운로드 | 구현에 채택 |
| [ADR-0007](0007-folderstate-usability.md) | 확인한 폴더에 적용하고 아이콘 저장 위치를 독립 변경 | 구현에 채택 |
| [ADR-0008](0008-bookmark-public-guide.md) | 업무 책갈피 0.2.0의 공개 사용 안내와 버전별 설치 파일 링크 | 구현에 채택 |
| [ADR-0012](0012-visible-cells-paste-public-guide.md) | 보이는 칸 붙여넣기 사용 안내와 버전별 릴리스 | 구현에 채택 |

“구현에 채택”은 회사 정책이나 상용 출시 승인을 뜻하지 않습니다. 후속 변경은 새 ADR로 대체 관계를 남깁니다.

## 로컬 이미지 후보에서 이어받은 결정

- [ADR-0015 · 최초 G0 조사](0015-image-copy-save-g0.md)
- [ADR-0016 · 독립 메뉴 배치](0016-image-copy-save-direct-menu.md)
- [ADR-0017 · Explorer 호출과 helper 결과 연결](0017-image-copy-save-invocation.md)

## 로컬 내보내기 후속 결정

- [ADR-0018 · 원본 Undo를 보존하는 출력 생성 분리](0018-excel-selection-export-undo.md)

- [ADR-0019 · 공개 payload를 재사용하는 단일 설치 EXE](0019-visible-cells-paste-single-installer.md)

- [ADR-0020 · 명시적으로 선택하는 현재 사용자 클립보드 시험](0020-image-current-session-tests.md)

- [ADR-0021 · 이미지 도구 무서명 MSI와 설치 관문](0021-image-unsigned-msi.md)

- [ADR-0022 · 관리자 설치와 일반 사용자 실행](0022-image-admin-install.md)

- [ADR-0023 · 공통 클래식 메뉴와 무서명 관리자 MSI](0023-image-copy-save-classic-menu.md) — 클래식 0.1.1 저장·복사와 MSI 시나리오 실증, 정량 반복 관문 제외, 설정 복원 PASS, 기본 메뉴 경로·안정성 원인 미확정

- [ADR-0024 · MSI의 기존 상태 보존 검사](0024-image-msi-preservation.md) — 기존 등록·외부 변경 검사, 알려진 0.1.1 이행, 표준 MSI 롤백

- [ADR-0025 · 그림 복사·저장의 공개 설치·사용 안내](0025-image-public-guide.md) — 정식 릴리스 요청에 따른 공개 범위 채택, 최종 MSI 검증·실제 게시 결과는 별도 기록
