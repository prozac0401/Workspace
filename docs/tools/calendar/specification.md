# 정적 달력 · 제품 명세

도구 ID: Calendar · 버전: 1.3.0 · 상태: 월간 수집·자동 연도 선택으로 운영 방식 변경
제품 책임: 저장소 관리 담당(운영 담당자 미결정)
적용: [개발 기준](../../policies/tools.md), [문서 규칙](../../policies/documentation.md), [ADR-0036](../../design/0036-static-calendar.md)

## 사용자와 목적

기존 Workspace에서 다음 해 달력을 준비하는 사용자에게 연도·공식/수동 휴일 설정, 12개월 미리보기와 편집 가능한 XLSX를 제공한다. 원본 초안 명세의 달력 계산·인쇄·입력 계약을 유지하고 서버 proxy/메모리 캐시를 Actions와 정적 JSON으로 대체한다. 첨부 XLSX는 형식 참고이며 최신 명세의 A:G·무수식 계약을 우선한다.

## 요구사항과 대응

| ID | 요구 행동·완료 기준 | 구현·근거 |
|---|---|---|
| CAL-01 | Workspace 다음 달력 최상위 메뉴, 모바일·다크·키보드, base path | mkdocs nav, scoped CSS, boot, browser-check |
| CAL-02 | 1983~2099년 선택·조회 대상과 실제 가용 연도 구분, 기본은 KST다음해 | schemaVersion2 contract targetYears/years, client/browser 경계 tests |
| CAL-03 | 수집 오류·미제공 차단, 32일 이상 stale 동의·35일 초과 차단 | contract/client/model과 월간 간격·경계 시험 |
| CAL-04 | 수동 실제 ISO날짜, 이름trim/NFC1~50자·줄바꿈/제어문자 거부,100개, 날짜/이름/개인·회사 중복 거부 | core tests; 공식 항목 수정/삭제 UI 없음 |
| CAL-05 | 설정·preview·export 동일 불변 model, 오래된 응답/내보내기 배제 | core/client/browser race tests |
| CAL-06 | calendar_YYYY.xlsx, 1시트 YYYY년 달력, A:G 일~토, 주당 날짜1+실제 빈3행 | 독립 calendar/openpyxl/ZIP 검사, Excel 사본 검사 |
| CAL-07 | 4/5/6주, 인접월 중복 없음, 공식 우선/이름정렬/출처보존 | 1900~2100 전 날짜 및 윤년 경계 검사 |
| CAL-08 | A4세로,너비1/높이자동,월앞나눔,긴이름보존·초과오류,무수식/무외부연결 | exporter/OOXML/Excel PDF |
| CAL-09 | XML 12개월/전페이지 resultCode·필수필드·rawCount 검증,연간0건은미준비 | provider/collector tests; 미제공 optional연도와 현재해/기존자료 소실을 구분 |
| CAL-10 | 제한timeout/retry/Retry-After/크기/페이지, 전체실제HTTP2,000회상한,비밀키출력금지,DTD차단 | provider tests, 고정 endpoint·환경변수만 소비 |
| CAL-11 | 원자쓰기·연도별 보존·영속 JSON branch·SHA고정·배포skip | collector/persistence tests, docs.yml |
| CAL-12 | PR 무Secret·무배포,운영 활성화/기본브랜치/이벤트 제한·최소권한 | workflow checker, 독립 코드 리뷰 |
| CAL-13 | 매월 1일 KST12:17 수집, 수동 수집은 GitHub Actions, 프런트 자료 다시 읽기 버튼 제거·연도 선택 자동 반영 | docs.yml, app/browser, 운영 README |

## 좌표·출처·입력 계약

A1:G1 연간 제목, A2:G2 출처·수집/생성 시각·모드, A3:G3 범례·갱신 안내,4행 구분. 월 시작 s=5, 요일 s+1, 날짜 s+2+4q, 작성 r+1~r+3, 다음 월 s+3+4w, w=ceil((offset+days)/7). 제목 외 병합 없음. 2027년1월1일 F7, 작성 F8:F10,1월31일 A27,2월제목32행. 인쇄 마지막 구분행 제외.

공식/일요일 빨강,토요일 파랑,평일 수동 보라. 같은 이름은 표시만 정리하고 model.sources에는 각 출처를 유지한다. 날짜행 이름은 자르지 않으며409pt 초과 시 명시적 오류다. 수식 모양 이름도 inline string이다. 시트 보호·매크로·수식·외부링크·데이터연결은 없다.

## 경계·실패·운영

2026-10-11 배포 후 요청으로 정기 수집은 일일에서 월 1회로 변경한다. 수동 수집은 GitHub Actions의 collect 실행으로 진행하며 프런트엔드는 공개 JSON을 자동으로 읽고 선택 연도를 반영한다. 사용자가 32일 이상 경고·35일 초과 차단을 선택했다. 가장 긴 월간 간격 31일과 하루의 지연 여유를 포함하며, 수집 실패로 보존한 자료는 경과 시간과 관계없이 명시적 동의를 요구한다. 새로고침 또는 연도 선택은 KASI 수집을 실행하지 않는다.

2026-10-11 후속 요청에서 사용자가 1983~2099년 선택과 완료 후 원격 반영·최초 실수집·배포를 승인했다. 이 범위가 최초의 올해/다음 해 공식 조회 범위를 대체한다. 117개 연도의 자료 제공을 보장하지 않으며 미제공 연도는 명시적 수동 모드만 허용한다. 정상 0건의 선택 연도가 있더라도 현재 해 수집 성공과 실제 오류 없음이 확인되면 준비/미준비 상태를 함께 게시한다. 기존 완전 자료가 0건으로 바뀌거나 현재 해 0건, HTTP·업무·검증 오류가 있으면 이 예외에 포함하지 않고 배포를 건너뛴다. 기존 XLSX 형식과 수동 입력·날짜 계산 규칙은 유지한다.

상시 서버·계정·저장·개인 일정 전송·기존 파일 재업로드는 없다. 공식 자료 원문과 오류 객체를 로그/브라우저/커밋으로 보내지 않는다. 12개월 완료는 향후 임시공휴일 확정과 다르며 다운로드 파일은 자동 갱신되지 않는다. 연도 변경은 수동목록 폐기를 확인하고 빈 수동 모드는 별도 재확인한다.

버전 schema와 영속 복구, 설치 없는 사용, 환경변수·권한·활성화 순서는 [운영 안내](../../../tools/calendar/README.md), 실제 결과·미실행은 [검증 기록](../../delivery/calendar-20261011.md)을 따른다. 최초 원본 명세 텍스트는 `original-specification.txt`로 보존하며 공개 사이트에 싣지 않는다.
