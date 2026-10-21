# 보이는 칸 붙여넣기 · 0.2.1-rc.1 시작 셀 확장 검증·배포 기록

기록일: 2026-10-21 · 버전: 0.2.1-rc.1 · MSI ProductVersion: 0.2.1<br>
상태: 시작 셀 확장·MSI 제작·집중 설치 검증 완료 · CI·게시 확인 전<br>
제품 책임: 도구 개발·검증 담당<br>
관련 문서: [원본 명세](../tools/visible-cells-paste/original-specification.md), [현재 대응표](../tools/visible-cells-paste/acceptance.md), [ADR-0039](../design/0039-visible-cells-paste-anchor.md), [이전 0.2.0-rc.1 게시·검증](visible-cells-paste-msi-020rc1-20261021.md)

## 요청과 변경 범위

사용자는 대상 한 셀을 왼쪽 위 시작점으로 고르면 복사한 원본의 보이는 행 수·열 수만큼 자동으로 붙여넣도록 요청했다. 숨김·필터 행과 숨긴 열을 건너뛰고 행·열 모양과 빈칸 위치를 유지한다. 명시적 사각형 선택은 기존 경계를 유지하며 한 행→한 열 변환은 명시적 한 열 선택에만 적용한다.

새 명령이나 모드를 추가하지 않는다. 전체 대상의 검사·백업·쓰기·복구·Undo에 확정 주소를 사용하고 원래 사용자 선택은 따로 보존한다. 원본 명세와 0.2.0-rc.1의 게시·실패·미실행 이력은 그대로 둔다. 변경 경로의 집중 자동·실제 Excel 검사와 새 버전 제작 확인으로 판정하며 무관한 전체 GUI·설치·실패 주입을 반복하지 않는다.

## 현재 실행 결과

| 범위 | 판정 | 근거·제한 |
|---|---|---|
| 시작 셀 확장·경계·명시적 선택 집중 검사 | PASS | core62 PASS·0 FAIL. 실제 Excel·클립보드 실행과 구분 |
| 실제 Excel의 시작 셀·숨김·Undo·복구 | 최종 PASS | Excel16.0 Build20430 x64, 34 PASS·0 FAIL, 종료0·success=true. 합성 타입 스냅샷을 전달한 엔진 시험이며 실제 Ctrl+C·메뉴 UI와 구분. 최초23 PASS·7 FAIL과 중간32 PASS는 아래 별도 이력 |
| 새 버전 전체 제품 제작·자동 검사 | PASS | 343회: core62·native48·snapshot15·lifecycle46·COM x64 36·COM x86 36·global20·presentation41·Setup39. 위 집중 코어62와 중복 합산하지 않음 |
| x86/x64 MSI 제작·정적 검사·해시 | PASS | ProductVersion0.2.1·AssemblyVersion0.2.1.0, 패키지16파일과 MSI 각각10파일·등록30개 확인. native guard 각각14 PASS·0 FAIL. 두 MSI 모두 서명 없음 |
| 새 MSI 집중 설치 검증12개 | PASS | 최종 x64 MSI로 일반 Explorer·일반 사용자 설치0, 파일10개 해시·HKCU등록30개·Assembly0.2.1.0, Excel 자동 로드/정상 종료2회, 제거0·제품 상태-1·소유 파일/등록 부재·추가 파일 보존 확인. 이전 MSI25개와 별도 |
| 문서 strict·생성 링크·그림 | PASS | 최종 문서 동결 후 MkDocs strict 종료0(5.84초), check-site 종료0: 공개22페이지·이전주소2개·404·검색/사이트맵·비공개 제외·로컬 링크·자산 확인. 상대링크·변경 SVG XML·diffcheck는 아래 validation.json에 기록 |
| CI·MSI 게시·다운로드·Pages | 확인 전 | 이전 0.2.0-rc.1 게시 성공을 새 버전의 성공으로 승계하지 않음 |
| 실제 클립보드·Ctrl+C/우클릭 | 이전 미해결·이번 NOT RUN | 이전 정상 Explorer 조사도 소유권 전제에서 내용 읽기·Paste 호출 전에 FAIL. UI 전체 경로는 NOT RUN |
| 늦은 설치 실패의 내부 등록 롤백 | 이전 FAIL 유지 | 0.2.0-rc.1에서 일반 Explorer에서도 접근 거부·제품 상태 잔존 재현. 공식 제거 성공과 별도 |
| Office32 실제 실행·새 PC·전체 공존 | 이전 NOT RUN 유지 | 제작·자동 검사로 실제 환경 검증을 대신하지 않음 |

## 실제 Excel 수정·검증 이력

첫 실행은 `artifacts/visible-cells-paste/excel-e2e/anchor-021/RectangleTests.txt`의 23 PASS·7 FAIL, 종료1이다. 같은 위치의 `axis-observation.json`에서 여러 행·열의 EntireRow/EntireColumn.Hidden이 첫 축의 false를 반환하는 반면 숨긴 단일 축은 true인 차이를 확인했다. 이 반환값을 전체 구간의 가시 상태로 사용한 탐색을 수정했다.

첫 보이는 열을 단일 열 Hidden으로 확인하고, 다중 칸은 보이는 행·열 위의 좁은 범위에 SpecialCells와 Intersect를 적용해 가시 셀 수로 찾도록 바꿨다. `anchor-021-fix1/RectangleTests.txt`는 32 PASS·0 FAIL, 결과 JSON은 종료0이다. 이 통과로 최초 실패 기록을 바꾸지 않는다.

이후 한 칸의 SpecialCells가 UsedRange로 넓어질 수 있는 경계를 피하도록 단일 축은 Hidden 직접 조회, 물리 대상1칸은 target 자체 검사로 구분했다. 빈 UsedRange 밖2사례를 추가한 최종 `artifacts/visible-cells-paste/excel-e2e/anchor-021-final/RectangleTests.txt`는 34 PASS·0 FAIL이며 같은 위치의 `result.json`에서 종료0·success=true를 확인했다. 초기30개·수정32개·최종34개의 수치는 서로 다른 실행 범위이며 성공 횟수로 합산하지 않는다.

## 최종 MSI 집중 설치 검증

일반 Explorer에서 일반 사용자로 실행했으며 사전 검사에서 기존 제품 등록과 Excel 프로세스가 없음을 확인했다. 최종 x64 MSI의 설치 종료0, 설치한 파일10개 해시·HKCU등록30개·AssemblyVersion0.2.1.0을 확인했다. Excel16.0 Build20430에서 시작·재시작 각각 자동 연결과 정상 종료를 확인한 뒤 표준 제거 종료0, 소유 파일·등록 부재, ProductState=-1, 외부 파일 역할의 합성 자료 보존을 확인했다. 종료 후 Excel 프로세스는0개다.

근거는 `artifacts/visible-cells-paste/0.2.1-rc.1/focused-msi/desktop-20261021-042151-54f5002a-result.json`과 `runs/20261021-042153-589a6103/`의 `summary.json`, `results.json`, `installed-excel-probe.log`다. 결과는12 PASS·0 FAIL이다. 이 검사는 시작·제거와 새 설치 메타데이터에 집중했으며 과거 전체 복구·외부 변경·실패 주입을 다시 통과했다는 뜻은 아니다.

## 산출물과 기록 경계

기존 0.2.0-rc.1은 공개 자산을 그대로 유지한다. 새 MSI는 `artifacts/visible-cells-paste/0.2.1-rc.1/msi/20261021-041957-50c2751a`에 제작했다. 아래는 최종 로컬 파일의 해시이며 아직 원격 게시·다운로드를 확인하지 않았다. x64 MSI는315,392바이트, x86 MSI는282,624바이트이며 코드 서명이 없다.

| 파일 | 로컬 SHA-256 | 원격 다운로드 대조 |
|---|---|---|
| VisibleCellsPaste-0.2.1-rc.1-x64.msi | `b0b5866e093f9ccdee474d318e3239bc770eb4069414087f71a4b120b7712e6c` | 확인 전 |
| VisibleCellsPaste-0.2.1-rc.1-x86.msi | `6c32f5c5779d656d7f2f15337bc3120e352a7ef1d17080167b21bee03f63d7be` | 확인 전 |
| SHA256SUMS.txt | `f16a90c89c530d398364e63343d0e3a19abfdddbd2e4976c41e90a49a18a8337` | 확인 전 |

제작·정적 검사 근거는 같은 위치의 `build-results.json`과 MSI별 manifest다. CI·태그·게시 시각·다운로드 대조는 실제 결과가 확보된 뒤 기록한다. 로컬 제작·설치 검증 성공을 사전 공개 완료로 표시하지 않는다.

새 동봉 문서는 0.2.1-rc.1 계약을 반영한 제작 전 스냅샷으로 동결했다. 이후 결과는 패키지 밖 이 기록에 남겨 결과 문구만을 위한 재제작·재설치를 피한다. 공개 안내에는 시작 셀과 명시적 영역의 사용법을 설명하고 실제 검증·실패·미실행 수치는 제외 기록과 릴리스 노트에 둔다.

문서 근거는 `artifacts/visible-cells-paste/anchor-docs-20261021/validation.json`이다. 기존 다운로드·사용 그림2개의 JSON과 가로/모바일 SVG4개만 바꿨으며 공개 자산·메뉴를 늘리지 않았다. 최초 명세는 변경하지 않았다.
