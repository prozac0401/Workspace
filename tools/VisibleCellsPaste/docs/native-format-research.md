# 네이티브 클립보드 날짜 숫자 보완

상태: Biff12 보완 어댑터 구현·순수 시험 통과, 실제 Excel 복사7사례와 날짜 체계 간 UI 붙여넣기·되돌리기 기록 독립 대조 통과 · 2026-09-24

XML Spreadsheet가 날짜를 DateTime 문자열로 제공할 때 동일한 복사 데이터의 Biff12(XLSB ZIP)에서 원시 숫자를 읽도록 구현했다. XML은 전체 차원·자료형·빈칸 위치의 기준이며 네이티브 값은 좌표와 나머지 모든 XML 값을 대조한 뒤 날짜 위치에만 사용한다. 1900/1904 체계나 달력 문자열에서 일수를 계산하지 않는다. 원본 Range, 현재 활성 셀, 임시 붙여넣기는 읽기 경로에 없다.

## 실제 확보한 근거

시험 담당자가 소유한 합성 통합문서에서 실제 UI Ctrl+C를 실행하고 읽기 전용 프로브로 저장했다. 제품은 클립보드를 비우거나 교체하지 않는다. 원래 로컬 덤프는 배포 ZIP에 넣지 않으며 순수 회귀용으로 선정한 합성 표본만 tests/fixtures/native 아래 보관한다.

| 표본 | 실제 복사 입력 | XML | 네이티브 관찰 |
|---|---|---|---|
| native-date, sequence 468 | S1 원시45200, 표시2023-10-01 | 1×1, DateTime | Biff12의 BrtCellRk 값45200; BrtOleSize와 셀 좌표 S1 |
| native-filtered, sequence434 | 필터 A2:A4에서85/78 | 2×1 | BrtOleSize는 원래3행, 셀 테이블은 원점 A2부터2행으로 압축 |
| date-html, sequence366 | 같은 날짜45200 | DateTime | HTML은 표시 문자열만 제공; x:num 원시값 없음 |

Biff12 날짜 표본은 압축 ZIP 7,130바이트이며 xl/workbook.bin, xl/worksheets/sheet1.bin 등으로 구성된다. sheet1.bin의 BrtCellRk는 row0, column18, RK워드0x40e61200이다. RK의 비트 계약대로 복원한 IEEE754 값은45200이다. 날짜 문자열2023-10-01을 변환해서 얻은 값이 아니다. [BrtCellRk](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/db763676-d672-4d4c-98bd-830a59cb2c4c), [RkNumber](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/a2b3ffec-dded-447b-b700-71b60e3c84da)

## 구현 경계

- NativeClipboard는 형식별 HGLOBAL 크기를 할당 전에 확인한다. Preferred DropEffect, XML, 필요할 때만 읽는 Biff12의 합계가32MiB를 넘으면 중단한다.
- 모든 형식은 같은 clipboard sequence와 소유 Excel PID·창·CutCopyMode=copy 증거 아래 읽는다. 지연 렌더링 중 변경되면 제한 횟수만 재시도한다.
- BoundedZip은 파일을 디스크에 풀지 않는다. 중앙/로컬 헤더, 크기, CRC32, 중복 이름, 경로, 영역 중첩, 압축 해제 후 길이를 확인한다. 지원은 단일 디스크의 stored/deflate ZIP이며 암호화·ZIP64·data descriptor 변형은 보수적으로 거절한다. 항목은128개, 선언된 압축 해제 합계도32MiB 이내다.
- XLSB 레코드 타입·가변 길이·버퍼 끝을 확인하고 단일 workbook/worksheet 셀 테이블만 읽는다. 외부 관계를 실행하거나 가져오지 않으며 관계 XML의 DTD를 금지한다. 스타일·매크로·링크는 열거나 실행하지 않는다.
- BrtOleSize의 복사 원점을 사용하고 XML 차원으로 실제 항목 영역을 확정한다. BrtWsDim은 사용 범위이므로 전체 복사 크기나 빈칸 개수를 대신하지 않는다. 필터 복사의 원래 범위 크기와 복사 항목 수는 다를 수 있다.
- 셀 레코드 좌표는 원점 기준으로 직접 대응시킨다. 값 검색·순서 변경·빈칸 제거·현재 원본 재조회로 맞추지 않는다. 중복/역순/범위 밖 셀, 누락된 날짜 숫자, XML과 다른 값/자료형/빈칸은0개 수정으로 중단한다.
- BrtCellRk, BrtCellReal, BrtFmlaNum의 원시 숫자를 읽는다. 수식 토큰의 길이만 검사하며 실행·재계산하지 않는다. 다른 위치의 숫자·문자열·빈 문자열·논리·오류·빈칸도 대조한다. shared string과 rich string의 기초 문자 값은 보존한다.

BrtOleSize의 공식 의미는 임베디드 표시 범위다. 위의 복사 원점/필터 압축 대응은 실제 Excel 클립보드 표본과 XML 전체 위치 대조로 검증하는 제품 계약이며, 모든 임의 XLSB 파일의 복사 범위 추론 규칙이라고 주장하지 않는다. BrtOleSize가 없거나 원점·형식이 모호한 네이티브 날짜 입력은 거절한다. [BrtOleSize](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/6f53d11d-d90d-47ce-8acb-944c19006f82), [BrtWsDim](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/81a65821-5dfa-43e1-9f82-92863b836f96)

## BIFF8을 제품 경로로 선택하지 않은 이유

같은 날짜의 Biff8에도 원시45200이 있었다. 그러나 Biff8은 CFB 컨테이너이고 기존 조사에서 필터 복사의 ROW 메타데이터는 원래 행1/3, RK 셀 좌표는 압축 행1/2로 달랐다. DIMENSIONS·SELECTION만으로 빈칸 위치를 정하면 안 된다. 또한 BIFF8의 전통적 행·열 범위보다 현대 Excel의 범위가 크다. 이번 구현은 현대 좌표를 가진 Biff12 하나만 추가했으며 BIFF8이나 TSV로 조용히 우회하지 않는다.

로컬 조사 기록은 artifacts/visible-cells-paste/m0/biff8-structure-research.json이며 CFB 섹터 체인과 레코드 경계를 따라 해석했다. 파일 전체에서 숫자 바이트 패턴을 검색한 결과가 아니다. [MS-XLS DIMENSIONS](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xls/5fd3837c-9f3d-4952-8a85-ad93ddb37ced), [MS-XLS SELECTION](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xls/00131ced-fe32-403b-9be4-d9c234fde7d4)

## 검증 구분

순수 시험 명령은 tests/unit/Run.ps1이며 NativeClipboardTests.cs가 저장된 실제 날짜/필터 표본과 생성한 경계 입력을 검사한다. 결과는 artifacts/visible-cells-paste/unit/native-results.txt에 기록한다. 기존 XML/계획47개도 회귀한다.

네이티브 순수 시험에는 앞·가운데·끝 빈칸, 가로/세로, 정수/소수 시간/백분율/수식 캐시, RK 부호·100배율, 현대 행/열 좌표, 모든 비날짜 타입 대조, 잘못된 레코드·ZIP·CRC·관계·거대 선언·임의 바이트를 포함한다. 이 순수 시험이 실제 Excel UI·파일 간·프로세스 간 붙여넣기 검증을 대신하지 않는다.

추가 실제 시험은 1900/1904의 같은 원시 숫자와 같은 달력 날짜, 날짜+시간+앞뒤빈칸, 가로, 필터, 복사 후 대상 선택, 다른 날짜 체계의 대상 Value2 확인을 포함한다. 완료 여부는 docs/test-report.md와 실제 시험 JSON을 기준으로 구분한다. 본 기록의 초기 표본만으로 모든 Office 버전·비트수에서 검증 완료라고 표시하지 않는다.

## 실제1900/1904 날짜 복사 추가 검증

실제 UI Ctrl+C로 만든 다음7개 표본을 제품 파서와 별도의 Node XLSB 숫자 디코더로 각각 읽고, 합성 파일 생성기의 expected.json 및 숫자 표시 fixture 초기화 값과 자동 대조했다. 둘 다7/7 PASS이다. 별도로 root가 실행한 실제 대상 셀 쓰기·되돌리기의 저장 결과도 아래 기준으로 대조했다.

| 저장 표본 | sequence | 확인한 자료형·원시값 | 결과 |
|---|---:|---|---|
| 1900-vertical, A2:A8 | 670 | Empty,45200,0.5,0.125,Empty,45500.75,Empty | PASS |
| 1904-vertical, A2:A8 | 704 | 위와 동일한 원시값과 빈칸 위치 | PASS |
| 1900-filtered, B13:B16 | 738 | 45200,Empty,45203; 필터 제외45201은 없음 | PASS |
| 1904-filtered, B13:B16 | 772 | 위와 동일한3항목 | PASS |
| 1900-leap, N1:N3 | 806 | 59,60,61 | PASS |
| 1900-horizontal, H1:J1 | 840 | 45200,0.5,0.125; 왼쪽→오른쪽 순서 | PASS |
| numeric-display, Q1 | 908 | 표시00085, 실제Number85 | PASS |

1900/1904 세로 표본의 XML 날짜 표현은 각각2023-10-01과2027-10-02처럼 달랐지만 네이티브 숫자는 두 경우 모두45200이었다. 시간0.5도 XML에서1899-12-31/1904-01-01로 다르게 표현됐으나 원시 숫자는 동일했다. 제품은 여기에1462를 더하거나 빼지 않았다.

필터 표본의 BrtOleSize는 원래 B13:B16(4행)을 나타내고 BrtWsDim/셀 테이블은 B13부터3행이다. 빈칸은 가운데1개로 유지됐다. 1900-02-29라는 Excel XML 표시 문자열도 .NET 날짜로 해석하지 않고 네이티브 숫자60으로 읽었다.

기계 판정·각 형식의 SHA256·셀별 원시 레코드 좌표·제품 출력은 [독립 날짜 검증 JSON](../../../artifacts/visible-cells-paste/release-validation/date-capture/independent-date-review.json)에 기록했다. 각 캡처 실행 로그의 모든 sequence가 동일하고 CutCopyMode=1이 확인된 것도 대조했다. 원본 업무 파일·실시간 Excel·실시간 클립보드에 접근하지 않고 저장된 합성 표본만 분석했다.

1900 원본의 가로3항목을 Date1904=True인 대상의 보이는 E2/E5/E8에 실제 우클릭 메뉴로 붙여넣었다. [붙여넣기 결과](../../../artifacts/visible-cells-paste/release-validation/date-capture/cross-date-system-ui-paste.json)에서45200/0.5/0.125가 그대로 들어가고, 숨긴 E3/E4/E6/E7의102/103/105/106과 전체 숫자 표시 형식0.0000이 유지됐다. [되돌리기 결과](../../../artifacts/visible-cells-paste/release-validation/date-capture/cross-date-system-ui-undo.json)는 E2:E8이 초기값101~107로 복구되고 날짜 체계·숨김·표시 형식이 유지된 것을 보여 준다. 초기값 근거는 DateFlowProbe.cs의 target 명령이며, 제품 진단은 success 후 undone을 보고했다. 이 독립 대조는 해당 실제 UI 시험의 저장 로그를 읽은 것으로, UI 조작을 새로 수행한 것은 아니다.

## 공식 해석 근거

- [MS-XLSB Record](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/7bf1de78-9cda-4002-8411-086f79cd4b60): 레코드 타입1~2바이트와 길이1~4바이트.
- [Cell Table](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/33035e84-cb66-4323-a8bc-d45e287bd7ec), [BrtRowHdr](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/b68fcd32-e1bc-4c2f-8a39-26ff10c646f5): 행/열과 셀 레코드의 문맥.
- [BrtCellReal](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/d4e5dd6f-d334-4681-9f32-d3d213675df2), [BrtFmlaNum](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/a4d1d5aa-dfd9-4955-b4b0-c3a2ed1a3d63): 숫자 및 수식의 최근 계산 결과.
- [CellParsedFormula](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/1ec6e2a4-7b5b-4fe6-a832-7d0234d85b06): 실행하지 않는 수식 토큰·추가 데이터의 길이.
- [RichStr](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/cbb5d08d-ea55-4184-aff0-2ea8967f918e): 문자열·서식·발음 정보 경계.
