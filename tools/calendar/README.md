# Workspace 정적 달력 운영

상태: 로컬 구현·검토 단계. 원격 push, PR, Secret 등록, 설정 변경, 데이터 브랜치 생성, 운영 workflow 실행 및 배포는 이번 실행에 포함하지 않는다.

## 구조와 재사용

`docs/assets/calendar/`의 날짜 계산·모델·미리보기·ZIP/OOXML 작성기는 전달된 초안을 재사용한다. `xlsx-exporter.mjs`와 `zip.mjs`는 초안 그대로다. XLSX 외부 패키지나 CDN은 없다. 브라우저 표준 API로 실제 XLSX를 만들며 A:G, 1시트, 날짜 아래 독립 빈 작성셀 3개를 유지한다. 모델의 수동 입력 정규화·출처 보존과 다운로드 직전 최신성 검사를 보완했다.

`server.mjs`의 API proxy와 메모리 캐시는 운영에서 제거했다. 조회 구현은 원래 별도 `lib/holiday-provider.mjs`에 있었으며 배치로 재사용했다. 브라우저는 `data/calendar.json`만 상대 경로로 읽는다. 개인·회사 입력은 브라우저 메모리에만 있고 새로고침·페이지 이탈 때 사라진다. ZIP/XLSX는 이 입력을 서버로 보내지 않고 같은 불변 CalendarModel에서 생성한다.

패키지 버전은 `1.1.0`, Node는 24.x, `package-lock.json`을 사용한다. 런타임 npm 의존성은 없다. SAX만 서버용 vendored 코드이고 버전·해시·라이선스는 `vendor/manifest.json`과 `vendor/sax-LICENSE.md`에 고정한다. 테스트용 Python 라이브러리는 `requirements-test.txt`에 고정한다. 브라우저 재현 도구는 Playwright 1.62.1과 설치된 Edge를 사용했다. 초안 자체 작성 코드에는 별도 LICENSE가 없으므로 제3자 XLSX 라이브러리 라이선스가 있다고 꾸미지 않는다.

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

`calendar.schema.json`(Draft 2020-12)과 브라우저/배치 공통 `contract.mjs`를 함께 유지한다. `schemaVersion`, KASI 출처, `datasetKind`, `supportedYears`/`targetYears`, `years`별 `status`/`complete`/`lastSuccessfulFetchAt`/`snapshotId`/12개 `monthResults`/`holidays`/`warnings`가 필수다. 허용하지 않은 필드·미래 버전·2MiB 초과 JSON을 거부한다. 원문 응답은 공개 projection에 포함하지 않는다.

지원 대상은 Asia/Seoul 기준 올해와 다음 해다. 실제 준비 여부는 각 연도 상태로 구분한다. UTC ISO 8601 시각을 저장하고 화면·파일은 KST로 표시한다. 날짜는 `YYYY-MM-DD` 그대로 계산한다. 매년 1월 1일 KST에 대상을 전환하며 이전 targetYears만 있는 JSON으로 운영 빌드하지 않는다. 아직 수집되지 않은 새 다음 해를 ready로 가정하지 않는다.

마지막 성공 시각에서 24시간 이상이면 stale 동의가 필요하고 30일 초과는 공식 다운로드를 막는다. 수집 실패로 보존한 자료도 즉시 stale 동의를 요구한다. 일일 스케줄 지연 때문에 24시간 직후 stale이 될 수 있지만 임의로 26시간 등으로 완화하지 않았다. 미리보기·다운로드 직전과 열린 화면 복귀 때 재검사한다. 수집 시각을 갱신한 것처럼 조작하지 않는다.

정상 빈 월은 허용하지만 연간 공식 휴일 0건·불완전 페이지·오류 자료는 ready가 아니다. 같은 날짜의 서로 다른 이름은 보존하고 정확한 중복만 제거한다. 공식 항목과 개인/회사 수동 항목은 별도로 보존한다. 수동 입력 중복 기준은 날짜·NFC 정규화 이름·개인/회사 출처다.

## 영속 저장·실패·복구

`calendar-data` 브랜치의 tree에는 검증된 `calendar.json` 한 파일만 허용한다. `data-store.mjs`는 독립 Git index로 이 파일만 commit하고 일반 fast-forward push를 사용한다. 소스·설정·오류 원문·Secret을 stage하지 않는다. 읽었던 SHA와 원격이 다르면 동시 변경으로 실패하며 강제 덮어쓰기를 하지 않는다. 읽기와 빌드는 특정 40자리 SHA를 고정한다. runner 디스크와 수명이 짧은 candidate artifact는 전달 수단이며, 정상 데이터의 영속 저장소는 Git 브랜치다.

수집은 임시 파일→전체 계약 검증→fsync→원자 rename을 사용한다. 로컬 출력 lock은 같은 출력에 대한 동시 실행을 거부한다. 중단으로 남은 `.lock`은 수집 프로세스가 없는지 확인한 뒤 그 파일만 제거하고, 정상 JSON은 지우지 않는다. 실패한 연도는 이전 snapshotId·성공 시각·월 결과·휴일을 보존한다. 처음부터 없는 연도는 unavailable/error다. 전체 실패는 기존 JSON을 바이트 단위로 보존한다. 일부 성공이면 정상 연도와 보존한 이전 연도를 함께 저장하지만 기본 Pages 배포는 skip한다.

기존 Pages를 유지하는 것과 다음 runner에서 이전 JSON을 확보하는 것은 별개다. 배포는 실패/미준비 때 skip하고, 데이터는 독립 브랜치에서 다시 읽으므로 두 조건을 모두 충족한다. 데이터 저장 후 문서 빌드나 배포가 실패해도 저장 SHA는 남는다. 원인을 고친 뒤 승인된 `reuse` 실행은 같은 정상 데이터와 원래 성공 시각을 읽어 다시 빌드한다. 새 수집 없이 문서만 바꾸는 main push도 `reuse`다. 만료/연도 전환 데이터는 이 경로에서도 차단된다.

첫 데이터 브랜치가 없으면 일반 운영 경로는 초기화 필요 오류로 중단한다. 예외는 승인된 최초 dispatch의 `action=collect`, `initialize_data=true`뿐이다. 이는 자료를 실제 수집·검증한 뒤 브랜치를 만든다. 초기화 중 다음 해가 미공개면 현재 해만 저장하고 배포를 skip한다. 운영자가 상태를 검토하고 별도로 `reuse`를 승인하면 현재 해를 사용하고 다음 해 미준비가 드러나는 사이트를 빌드할 수 있다. 현재 해도 없으면 `reuse`는 거부한다.

손상된 저장소를 발견하면 기존 Pages를 유지하고 승인된 정상 과거 SHA의 JSON을 독립 검증한다. 복구 커밋도 현재 tip의 자식으로 만들며 force push는 사용하지 않는다. 데이터가 30일보다 오래됐으면 재수집이 먼저다. 원격 데이터 복구·삭제·초기화는 별도 승인 작업이다.

## 승인 후 운영 활성화 순서

1. 사용자가 저장소 **Settings → Secrets and variables → Actions → Secrets → New repository secret**에서 `KASI_SERVICE_KEY`를 직접 등록한다. 저장소 Secret을 관리할 권한이 필요하다. 값은 채팅·파일·명령 인자에 넣지 않는다.
2. 저장소 관리자가 Pages Source=GitHub Actions, `github-pages` environment의 기본 브랜치 제한, Actions 허용 정책과 브랜치 보호를 검토한다. 데이터 저장 job에만 `contents:write`, 배포 job에만 `pages:write`/`id-token:write`가 필요하다. 실제 설정 변경은 별도 승인한다.
3. 코드 리뷰 후 병합을 별도로 승인한다. `CALENDAR_ENABLED` Actions 변수의 기본값은 미설정이며 운영 job은 실행되지 않는다. 해당 변수를 문자열 `true`로 등록하는 것 또한 운영 활성화이므로 별도 승인한다. 활성화 후 다음 스케줄이 실행될 수 있으므로 초기화와 승인 시점을 조정한다.
4. 기본 브랜치에서 최초 dispatch `collect` + `initialize_data=true` 실행·데이터 브랜치 생성·배포를 별도로 승인한다. 키가 없거나 초기 검증에 실패하면 배포하지 않는다. 이후 초기화 입력은 false를 유지한다.
5. 실행의 source SHA와 data SHA, 공개 JSON의 준비 연도·성공 시각, PC/모바일 메뉴, 새 다운로드를 확인한다. 과거 CI 성공을 새 HEAD의 성공으로 기록하지 않는다.

이번 변경은 1~5 어느 운영 동작도 실행하지 않는다. 원격 push/PR 생성도 별도 요청이 필요하다.

## Actions 연결과 운영 한계

기존 `Documentation` 하나에 verify→prepare-data→store-data→build→deploy를 연결한다. PR은 Secret 없는 단위·독립 XLSX·schema·사이트 검사를 수행하고 데이터 쓰기/Pages artifact 업로드/배포를 하지 않는다. `pull_request_target`을 사용하지 않는다. 운영 job은 원본 저장소·기본 브랜치·허용 이벤트·활성화 변수로 제한한다. 하나의 운영 concurrency 그룹을 사용하고 오래된 source SHA는 저장·배포 직전 확인하여 skip한다. 대기 순서가 정확히 보장되는 큐라고 설명하지 않는다.

`GITHUB_TOKEN` push가 다른 push workflow나 Pages 빌드를 일으킬 것이라고 기대하지 않는다. 같은 workflow의 needs와 명시적 데이터 SHA로 이어지며 PAT는 필요하지 않다. candidate artifact는 공개 JSON만 포함하고 1일 후 만료되어도 저장 브랜치에는 영향을 주지 않는다.

수집 일정 `17 3 * * *`는 UTC 03:17, 한국 12:17 하루 1회다. 기본 브랜치의 workflow로 실행하며 혼잡 시 지연·누락, 공개 저장소 60일 비활동 시 schedule 비활성화가 가능하다. 정시 수집이나 임시공휴일 즉시 반영을 보장하지 않는다.

정상 2년×12개월 최소 24회/실행. 월당 최대20페이지·호출당3회 시도라 절대 상한은1,440회/실행이며 수동 재실행을 더해야 한다. 응답1MiB·월1,000건·최대동시3·요청8초·연간60초, 1/2초 backoff와 jitter, Retry-After 최대10초를 적용한다. 더 긴 Retry-After는 일찍 재시도하지 않고 실패한다. 인증/업무 오류는 재시도하지 않는다. DTD/외부 엔티티를 거부한다.

공공데이터포털 공개 안내는 개발계정 트래픽10,000, 운영계정 증설 신청을 설명하지만 이 계정의 실제 승인량은 미확인이다. 저장소는 공개로 확인했고 GitHub 표준 공개 runner/Pages 조건을 확인했지만 소유자 플랜·현재 Actions 사용량·청구 한도는 미확인이다. 항상 무료라고 보장하지 않으며 유료 자원은 만들지 않는다. site_url은 `/Workspace/`지만 실제 Pages 관리 화면의 커스텀 도메인 설정은 접근 제한으로 미확인이다. 코드·검사기는 설정된 base path를 사용하고 브라우저는 루트 및 `/Workspace/` 경로를 검증한다.

공식 근거(2026-10-11 재확인): [KASI](https://www.data.go.kr/data/15012690/openapi.do), [schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule), [Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets), [GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token), [workflow 연결](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow), [Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
