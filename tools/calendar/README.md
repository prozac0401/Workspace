# Workspace 정적 달력 운영

사용 범위: 1983~2099년을 선택하여 한 해씩 내려받는다. 2026-10-11 후속 요청에서 원격 반영·운영 활성화·최초 수집·배포가 승인되었다. 최초 로컬 검증과 후속 배포 결과는 각각 [기존 기록](../../docs/delivery/calendar-20261011.md), [연도 확장·운영 기록](../../docs/delivery/calendar-publication-20261011.md)에서 구분한다. Secret 값은 사용자가 직접 등록하며 구현·검증 과정에서 읽거나 출력하지 않는다.

## 구조와 재사용

`docs/assets/calendar/`의 날짜 계산·모델·미리보기·ZIP/OOXML 작성기는 전달된 초안을 재사용한다. 사용자 서식·인쇄 상단 정리 요청으로 `xlsx-exporter.mjs`는 공통 서식과 문서 속성, A5부터 인쇄하도록 확장했고 `zip.mjs`는 초안 그대로다. XLSX 외부 패키지나 CDN은 없다. 브라우저 표준 API로 실제 XLSX를 만들며 A:G, 1시트, 날짜 아래 독립 빈 작성셀 3개를 유지한다. 모델의 수동 입력 정규화·출처 보존과 다운로드 직전 최신성 검사를 보완했다.

`server.mjs`의 API proxy와 메모리 캐시는 운영에서 제거했다. 조회 구현은 원래 별도 `lib/holiday-provider.mjs`에 있었으며 배치로 재사용했다. 브라우저는 `data/calendar.json`만 상대 경로로 읽는다. 개인·회사 입력은 브라우저 메모리에만 있고 새로고침·페이지 이탈 때 사라진다. ZIP/XLSX는 이 입력을 서버로 보내지 않고 같은 불변 CalendarModel에서 생성한다.

패키지 버전은 `1.4.0`, Node는 24.x, `package-lock.json`을 사용한다. 런타임 npm 의존성은 없다. SAX만 서버용 vendored 코드이고 버전·해시·라이선스는 `vendor/manifest.json`과 `vendor/sax-LICENSE.md`에 고정한다. 테스트용 Python 라이브러리는 `requirements-test.txt`에 고정한다. 브라우저 재현 도구는 Playwright 1.62.1과 설치된 Edge를 사용했다. 초안 자체 작성 코드에는 별도 LICENSE가 없으므로 제3자 XLSX 라이브러리 라이선스가 있다고 꾸미지 않는다.

공식 휴일 표시명은 공통 모델에서 ‘기독탄신일’을 ‘크리스마스’로 바꾼다. 대체공휴일 이름에도 적용하며 미리보기·XLSX가 같은 규칙을 사용한다. 검증 JSON과 snapshot/sources의 원문·식별자·수집 시각은 보존하고 개인/회사 수동 이름은 바꾸지 않는다.

공개 화면은 연도1983~2099, 내 일정 가로 입력, 접을 수 있는 서식·색상, 미리보기·다운로드로 정리한다. 정상 자료의 세부 현황과 상시 주의사항은 제거하고 미제공/만료/오류/stale/공휴일 없는 모드에서 필요한 선택만 표시한다. 검증·32일 동의·35일 차단은 유지한다. 서식은 검증된 `model.formatting`에 고정되어 미리보기와 다운로드에 함께 반영되고 사이트 다크 모드와 독립된다. 글꼴3종·글자/제목 크기·작성칸 높이와 요소별 색상을 바꿀 수 있다. 상세 범위는 제품 명세를 따른다.

인쇄는1월 제목A5부터 시작하며 기존1~4행의 연간제목·운영 metadata·범례는 제거한다. 날짜 좌표를 보존하려 해당 행은 빈 숨김행으로 남긴다. 출처·수집/생성 시각·모드·fixture 여부는 `docProps/core.xml`에 남고 시트나 인쇄에 나오지 않는다. 기본값의 실제 Excel PDF와 독립 OOXML 검사를 수행하며 높은 글자/작성칸 설정에서는 A4높이 자동으로 한 달이 여러 페이지가 될 수 있다.

음력 표시 옵션은 기본 끔이며 켜면 날짜 오른쪽에 `(MM.DD)`를 붙인다. 사용자가 확정한 음력 지원은1983~2050년이고 달력 자체는1983~2099년이다. 2051년 이후에는 음력만 비활성화한다. 브라우저나 중국음력 계산을 대용하지 않고 고정된 한국 음력표를 사용한다. 변환표 출처·버전·라이선스·재현 방법은 [음력 자료](LUNAR-DATA.md)를 따른다. 표 생성용 npm 개발 의존성은 lockfile로 고정하며 브라우저·Actions 공휴일 수집에는 필요하지 않다.

## 정기·수동 수집

정기 수집은 **매월 1일 한국 시간 12:17**에 GitHub Actions로 실행한다. 달력 페이지는 진입할 때 공개 JSON을 자동으로 읽고 연도 선택을 반영한다. 프런트엔드에는 자료 다시 읽기 버튼이 없으며, 연도 변경이나 페이지 새로고침은 KASI 수집을 실행하지 않는다.

운영자가 월간 일정 전에 공휴일을 갱신하려면 저장소 쓰기 권한으로 다음을 실행한다.

1. [GitHub Actions → Documentation](https://github.com/prozac0401/Workspace/actions/workflows/docs.yml)을 연다.
2. **Run workflow**, Branch **main**, action **collect**를 선택한다.
3. 이미 초기화된 운영 저장소이므로 **initialize_data는 false(선택 해제)**로 둔다.
4. **Run workflow**를 누르고 수집·저장·빌드·배포 결과를 확인한다. 성공 후 사이트를 새로고침하면 갱신된 자료를 읽는다. 새로고침 전에 필요한 수동 입력 달력은 내려받는다.

`reuse`는 기존 검증 데이터의 SHA와 성공 시각을 그대로 재사용해 사이트만 빌드하며 KASI에 조회하지 않는다. 수집 오류 시 배포 skip과 이전 데이터 보존은 동일하다. 이미 받은 XLSX는 갱신되지 않는다.

## 로컬 확인

저장소 루트에서 실행한다. 실제 키를 읽거나 KASI를 호출하지 않는다.

```powershell
npm ci --prefix tools/calendar --ignore-scripts
npm test --prefix tools/calendar
python -m pip install -r requirements-docs.txt -r tools/calendar/requirements-test.txt
python scripts/check-calendar-workflow.py
python -m mkdocs build --strict
python scripts/check-site.py site
python -m mkdocs serve
```

별도 키·데이터 없이 빌드하면 `uninitialized` JSON을 생성한다. 화면은 공식 자료 미준비를 표시하고 명시적 수동 모드만 허용한다. fixture를 정상 공식 자료처럼 배포하지 않는다. 생성 JSON은 Git에서 제외되며 소스 브랜치에 자동 커밋하지 않는다.

가상 자료의 화면·다운로드를 검토하려면 다음처럼 명시적으로 선택한다. 운영 검증기는 이 자료를 거부한다.

```powershell
node tools/calendar/tests/write-fixture.mjs
$env:CALENDAR_DATA_FILE = 'artifacts/calendar/fixture.json'
python -m mkdocs build --strict
python scripts/check-site.py site
Remove-Item Env:CALENDAR_DATA_FILE
node tools/calendar/tests/make-sample.mjs
python tools/calendar/tests/inspect-xlsx.py
python tools/calendar/tests/validate-schema.py
# 설치된 Playwright 1.62.1 모듈을 사용한다. PATH 외부라면 index.mjs 절대 경로를 지정한다.
# $env:PLAYWRIGHT_MODULE = '.../node_modules/playwright/index.mjs'
# Edge 설치 위치를 자동으로 찾지 못하면 실행 파일을 명시한다.
# $env:CALENDAR_BROWSER_EXECUTABLE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
node tools/calendar/tests/browser-check.mjs
python tools/calendar/tests/inspect-browser-export.py
# Windows와 Excel 설치 환경에서 생성 샘플 사본만 검증한다.
powershell -NoProfile -File tools/calendar/tests/excel-check.ps1
```

`artifacts/calendar/`의 XLSX·PDF·JSON·화면은 검증용이며 사이트와 데이터 브랜치에 들어가지 않는다. 원본 첨부 XLSX는 읽기 전용 비교 자료다. 초안에 포함된 과거 테스트 보고는 이번 실행 결과로 재사용하지 않는다.

## 공개 JSON 계약과 최신성

`calendar.schema.json`(Draft 2020-12)과 브라우저/배치 공통 `contract.mjs`를 함께 유지한다. schemaVersion 2는 1983~2099년 전체 117개 연도를 명시한다. KASI 출처, `datasetKind`, `supportedYears`/`targetYears`, `years`별 `status`/`complete`/`lastSuccessfulFetchAt`/`snapshotId`/12개 `monthResults`/`holidays`/`warnings`가 필수다. 허용하지 않은 필드·미래 버전·2MiB 초과 JSON을 거부한다. 원문 응답은 공개 projection에 포함하지 않는다. schemaVersion 1은 미배포 초안으로만 존재했으며 원격 운영 데이터의 자동 변환은 하지 않는다.

선택·조회 대상은 1983~2099년이다. 제공기관이 이 전체 기간의 공식 자료를 제공한다고 보장하지 않으며 실제 준비 여부는 각 연도 상태로 구분한다. 기본 선택만 Asia/Seoul 기준 다음 해이고 범위 끝에서는 2099년으로 제한한다. UTC ISO 8601 시각을 저장하고 화면·파일은 KST로 표시한다. 날짜는 `YYYY-MM-DD` 그대로 계산한다. 연도가 바뀌어도 고정된 선택 범위는 유지하며 새 현재 연도의 검증된 자료와 최신성을 운영 빌드에서 다시 확인한다.

마지막 성공 시각에서 **32일 이상이면 stale 동의**, **35일 초과는 공식 다운로드 차단**을 적용한다. 2026-10-11 사용자가 월 1회 수집과 이 기준을 선택하여 최초의 24시간/30일 기준을 대체했다. 32일은 가장 긴 월간 간격 31일과 하루의 실행 지연 여유를 포함하며, 경고 이후 35일까지 복구 시간을 둔다. 수집 실패로 보존한 자료는 즉시 stale 동의를 요구한다. 미리보기·다운로드 직전과 열린 화면 복귀 때 재검사하며 성공 시각을 조작하지 않는다. 28/29/30/31일 간격, 정확히32일, 정확히35일과35일초과 경계가 테스트 대상이다.

정상 빈 월은 허용하지만 연간 공식 휴일 0건·불완전 페이지·오류 자료는 ready가 아니다. 같은 날짜의 서로 다른 이름은 보존하고 정확한 중복만 제거한다. 공식 항목과 개인/회사 수동 항목은 별도로 보존한다. 수동 입력 중복 기준은 날짜·NFC 정규화 이름·개인/회사 출처다.

## 영속 저장·실패·복구

`calendar-data` 브랜치의 tree에는 검증된 `calendar.json` 한 파일만 허용한다. `data-store.mjs`는 독립 Git index로 이 파일만 commit하고 일반 fast-forward push를 사용한다. 소스·설정·오류 원문·Secret을 stage하지 않는다. 읽었던 SHA와 원격이 다르면 동시 변경으로 실패하며 강제 덮어쓰기를 하지 않는다. 읽기와 빌드는 특정 40자리 SHA를 고정한다. runner 디스크와 수명이 짧은 candidate artifact는 전달 수단이며, 정상 데이터의 영속 저장소는 Git 브랜치다.

수집은 임시 파일→전체 계약 검증→fsync→원자 rename을 사용한다. 로컬 출력 lock은 같은 출력에 대한 동시 실행을 거부한다. 중단으로 남은 `.lock`은 수집 프로세스가 없는지 확인한 뒤 그 파일만 제거하고, 정상 JSON은 지우지 않는다. 실패한 연도는 이전 snapshotId·성공 시각·월 결과·휴일을 보존한다. 처음부터 없는 연도는 unavailable/error다. 전체 실패는 기존 JSON을 바이트 단위로 보존한다. 실제 수집 오류가 하나라도 있으면 일부 정상 자료는 저장하되 Pages 배포는 skip한다. 예외적으로 처음 조회한 선택 연도의 연간 정상 0건은 `unavailableYears`로 분리한다. 현재 연도가 이번 수집에서 성공했고 실제 오류가 없으면 이 미제공 상태를 그대로 표시하는 사이트는 배포할 수 있다. 이전에 완전했던 연도의 0건 또는 현재 연도의 0건은 이 예외에 포함하지 않는다.

기존 Pages를 유지하는 것과 다음 runner에서 이전 JSON을 확보하는 것은 별개다. 배포는 실패/미준비 때 skip하고, 데이터는 독립 브랜치에서 다시 읽으므로 두 조건을 모두 충족한다. 데이터 저장 후 문서 빌드나 배포가 실패해도 저장 SHA는 남는다. 원인을 고친 뒤 승인된 `reuse` 실행은 같은 정상 데이터와 원래 성공 시각을 읽어 다시 빌드한다. 새 수집 없이 문서만 바꾸는 main push도 `reuse`다. 만료/연도 전환 데이터는 이 경로에서도 차단된다.

첫 데이터 브랜치가 없으면 일반 운영 경로는 초기화 필요 오류로 중단한다. 예외는 승인된 최초 dispatch의 `action=collect`, `initialize_data=true`뿐이다. 이는 117개 연도를 실제 조회·검증한 뒤 정상 연도가 있으면 브랜치를 만든다. 일부 연도가 정상 0건이면 준비된 연도와 미제공 연도를 함께 공개하되 미제공 연도의 공식 다운로드를 막는다. 실제 오류가 있다면 정상 자료만 영속 저장하고 배포를 skip한다. 운영자가 오류/보존 상태를 검토한 뒤 승인된 `reuse`로 현재 해와 준비된 연도를 게시할 수 있다. 현재 해도 없으면 `reuse`는 거부한다. 첫 배포 전에 실제 수집은 필수이며 fixture나 미초기화 자료로 대신하지 않는다.

손상된 저장소를 발견하면 기존 Pages를 유지하고 승인된 정상 과거 SHA의 JSON을 독립 검증한다. 복구 커밋도 현재 tip의 자식으로 만들며 force push는 사용하지 않는다. 데이터가 35일보다 오래됐으면 재수집이 먼저다. 원격 데이터 복구·삭제·초기화는 별도 승인 작업이다.

## 승인 후 운영 활성화 순서

1. 사용자가 저장소 **Settings → Secrets and variables → Actions → Secrets → New repository secret**에서 `KASI_SERVICE_KEY`를 직접 등록한다. 저장소 Secret을 관리할 권한이 필요하다. 값은 채팅·파일·명령 인자에 넣지 않는다.
2. 저장소 관리자가 Pages Source=GitHub Actions, `github-pages` environment의 기본 브랜치 제한, Actions 허용 정책과 브랜치 보호를 검토한다. 데이터 저장 job에만 `contents:write`, 배포 job에만 `pages:write`/`id-token:write`가 필요하다. 실제 설정 변경은 별도 승인한다.
3. 코드 리뷰 후 병합을 별도로 승인한다. `CALENDAR_ENABLED` Actions 변수의 기본값은 미설정이며 운영 job은 실행되지 않는다. 해당 변수를 문자열 `true`로 등록하는 것 또한 운영 활성화이므로 별도 승인한다. 활성화 후 다음 스케줄이 실행될 수 있으므로 초기화와 승인 시점을 조정한다.
4. 기본 브랜치에서 최초 dispatch `collect` + `initialize_data=true` 실행·데이터 브랜치 생성·배포를 별도로 승인한다. 키가 없거나 초기 검증에 실패하면 배포하지 않는다. 이후 초기화 입력은 false를 유지한다.
5. 실행의 source SHA와 data SHA, 공개 JSON의 준비 연도·성공 시각, PC/모바일 메뉴, 새 다운로드를 확인한다. 과거 CI 성공을 새 HEAD의 성공으로 기록하지 않는다.

2026-10-11 후속 요청에서 사용자가 1983~2099 범위와 완료 후 원격 반영·배포, 최초 실제 수집을 승인했다. 해당 실행 결과는 운영 기록을 따른다. 이후 권한 확대·Secret 교체·데이터 강제 복구는 별도 변경 범위다.

## Actions 연결과 운영 한계

기존 `Documentation` 하나에 verify→prepare-data→store-data→build→deploy를 연결한다. PR은 Secret 없는 단위·독립 XLSX·schema·사이트 검사를 수행하고 데이터 쓰기/Pages artifact 업로드/배포를 하지 않는다. `pull_request_target`을 사용하지 않는다. 운영 job은 원본 저장소·기본 브랜치·허용 이벤트·활성화 변수로 제한한다. 하나의 운영 concurrency 그룹을 사용하고 오래된 source SHA는 저장·배포 직전 확인하여 skip한다. 대기 순서가 정확히 보장되는 큐라고 설명하지 않는다.

`GITHUB_TOKEN` push가 다른 push workflow나 Pages 빌드를 일으킬 것이라고 기대하지 않는다. 같은 workflow의 needs와 명시적 데이터 SHA로 이어지며 PAT는 필요하지 않다. candidate artifact는 공개 JSON만 포함하고 1일 후 만료되어도 저장 브랜치에는 영향을 주지 않는다.

수집 일정 `17 3 1 * *`는 **매월 1일 UTC 03:17, 한국 12:17 월 1회**다. 기본 브랜치의 workflow로 실행하며 혼잡 시 지연·누락, 공개 저장소 60일 비활동 시 schedule 비활성화가 가능하다. 정시 수집이나 임시공휴일 즉시 반영을 보장하지 않는다. 실행을 놓쳤거나 긴급 갱신이 필요하면 위의 GitHub 수동 collect 절차를 사용한다.

정상 단일 페이지이면 117년×12개월=1,404회/실행이다. 페이지 추가와 재시도를 포함해 동일 collector의 전체 실제 HTTP 호출은 최대2,000회로 제한하며, 수동 재실행은 별도로 더해야 한다. 올해·다음 해를 먼저 조회하고 나머지 연도를 조회한다. 월당 최대20페이지·호출당3회 시도, 응답1MiB·월1,000건·최대동시3·요청8초·연간60초, 1/2초 backoff와 jitter, Retry-After 최대10초를 적용한다. 수집 job은45분을 상한으로 둔다. 더 긴 Retry-After는 일찍 재시도하지 않고 실패한다. 인증 오류를 무한 재시도하지 않으며 DTD/외부 엔티티를 거부한다.

공공데이터포털 공개 안내는 개발계정 트래픽10,000, 운영계정 증설 신청을 설명하지만 이 계정의 실제 승인량은 미확인이다. 정상1,404회는 안내된10,000회의14.04%, 실행상한2,000회는20%이며 다른 프로그램 호출량도 합산해야 한다. 저장소는 공개로 확인했고 소유자 플랜·현재 Actions 사용량·청구 한도는 미확인이다. 항상 무료라고 보장하지 않으며 유료 자원은 만들지 않는다. 사용자 확인과 읽기 전용 API 조회로 Pages Source=workflow, custom domain 없음, `github-pages` main제한, reviewer/wait 없음, Actions 기본read와GitHubActions허용을 확인했다. 코드·검사기는 설정된 base path를 사용하고 브라우저는 루트 및 `/Workspace/` 경로를 검증한다.

공식 근거(2026-10-11 재확인): [KASI](https://www.data.go.kr/data/15012690/openapi.do), [schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule), [Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets), [GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token), [workflow 연결](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow), [Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
