# ADR-0036 · 검증된 정적 JSON으로 달력 통합

상태: 채택, 2026-10-11 후속 요청으로 운영 활성화·최초 수집·배포 승인
날짜: 2026-10-11
결정 담당: 저장소 관리 담당(운영 승인자 미지정)
관련: 사용자 정적 달력 구현 지시, [도구 개발 기준](../policies/tools.md), [문서 작성 규칙](../policies/documentation.md), [달력 명세](../tools/calendar/specification.md)

## 맥락

기존 MkDocs Material과 GitHub Pages를 유지하며 편집 가능한 연간 XLSX를 제공한다. 전달된 초안은 로컬 API proxy와 메모리 캐시를 사용한다. 사용자는 이번 요구에서 상시 서버를 제외하고 정기 KASI 수집과 영속 정상 데이터를 요구했다. 이 부분은 초안의 서버·정기 갱신 제외 범위를 대체한다. 날짜·셀 좌표·수동 입력·보안 계약은 유지한다.

실제 최신 main에는 Workspace 최상위 nav가 없고 네 그룹이 있다. 네 그룹과 기존 URL을 Workspace 아래 보존하고 바로 다음 최상위 nav에 달력을 둔다. CSS로 메뉴를 흉내 내지 않는다. Material instant navigation은 현재 꺼져 있지만 재진입 초기화는 idempotent하게 구현한다.

## 결정

후속 요청에 따라 선택·수집 범위를 1983~2099년으로 확장하고 schemaVersion 2로 명시한다. 올해와 다음 해를 우선 조회한 뒤 나머지 연도를 조회하며, 실제 HTTP 시도 전체에 2,000회 상한을 둔다. 미배포 v1 자료를 운영 자료로 변환하지 않는다. 처음부터 공식 자료가 정상 0건인 선택 연도는 unavailable로 공개하고 해당 연도의 공식 다운로드를 차단한다. 현재 해가 이번 수집에서 성공하고 실제 오류가 없어야 배포할 수 있다. 이전에 있던 자료 소실이나 현재 해 미준비를 정상으로 취급하지 않는다.

기존 브라우저 CalendarModel/renderer/ZIP/XLSX 작성기를 재사용한다. 서버 provider를 배치로 추출하고 UI는 상대 경로 JSON loader로 교체한다. 수동 데이터는 브라우저 밖으로 보내지 않는다. 공식 공휴일은 XML getRestDeInfo의 Y 항목만 사용한다.

단일 `docs.yml`의 의존 job으로 운영 수집·JSON만 저장·특정 SHA 빌드·Pages 배포를 연결한다. `calendar-data` 브랜치의 한 파일만 정상 자료의 영속 저장소로 사용한다. 소스 main 자동 수정, PAT, 별도 Pages workflow는 만들지 않는다. 데이터 쓰기는 읽은 부모 SHA를 확인하는 fast-forward만 사용한다.

## 검토한 대안

브라우저 API 호출은 키 공개·CORS 의존 때문에 제외한다. 상시 서버는 운영 범위 밖이다. runner cache/artifact만으로 이전 자료를 보존하면 만료·실행 초기화에 취약하다. main 데이터 자동 커밋은 문서 작업과 충돌하고 TOKEN 이벤트 연결을 복잡하게 한다. 별도 데이터 브랜치는 Git만으로 영속성과 SHA 고정을 제공한다.

## 영향과 이행

공개 범위는 달력 한 페이지, 명시된 JS/CSS와 계약 검증을 통과한 JSON뿐이다. schema·개발명세·검증·원본 첨부·테스트 fixture·SAX는 공개 사이트에서 제외한다. 24시간/30일 기준을 유지하며 일일 지연 시 stale 동의를 받는다. 회사 설정·담당자·운영 허용량은 미결정이다.

최초 구현에서는 운영 변경을 제외했고 후속 대화에서 원격 반영·활성화·첫 수집·배포가 승인되었다. 사용자가 Secret을 직접 등록했으며 값은 읽거나 출력하지 않는다. Pages workflow 방식/도메인없음, github-pages main제한, reviewer/wait없음, Actions기본read를확인했다. 로컬/PR은 미준비 JSON과 명시적 fixture를 사용하며 운영 빌드는 fixture/미초기화 데이터를 거부한다.

## 실패와 복구

연도별 실패는 이전 정상 snapshotId와 시각을 보존한다. 실제 수집 오류가 있으면 일부 성공 자료는 저장하되 기본 배포는 skip한다. 오류 없이 optional연도의 정상0건만 있으면 위 조건에 따라미준비상태를표시하며배포할수있다. 데이터 저장 후 빌드/배포 실패에도 데이터 SHA는 남는다. 승인된 reuse 경로로 같은 데이터·시각의 문서 재빌드를 수행한다. 현재 해 미준비·30일 초과는 운영 빌드를 중단한다. 상세 초기화·잠금 복구는 [운영 안내](../../tools/calendar/README.md)를 따른다.

## 검증

수집·스키마·동시/중단 쓰기·복구·모델·실제 ZIP/OOXML·독립 파서·실제 Edge·Excel 및 정적 사이트/워크플로 검사를 수행하고 [최초 검증 기록](../delivery/calendar-20261011.md)에 실제 결과와 NOT RUN을 남겼다. 이후범위확장·원격CI·첫KASI수집·배포는 [후속 운영 기록](../delivery/calendar-publication-20261011.md)에서구분한다.
