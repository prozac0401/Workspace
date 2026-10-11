# 달력 연도 확장·운영 활성화 기록 · 2026-10-11

최초 로컬 구현은 [79f065c의 검증 기록](calendar-20261011.md)에 보존한다. 이번 후속 작업은 사용자가 요청한 **1983~2099년 선택과 다운로드**, 완료 후 **원격 반영·배포**, **첫 배포 전 실제 공휴일 수집**을 수행한다. 최초의 원격 작업 금지 범위는 이 후속 승인으로 변경되었다. API 키 값은 사용자가 직접 등록했고 에이전트가 읽거나 출력하지 않았다.

## 운영 사전 확인

사용자가 순서대로 확인했고 이후 GitHub API에서 읽기 전용으로 대조했다.

| 항목 | 확인 상태 |
|---|---|
| 저장소/기본 브랜치 | prozac0401/Workspace, public, main |
| 현재 인증의 관리·push 권한 | 있음 |
| Repository Secret | KASI_SERVICE_KEY 이름 존재. 값 미조회 |
| Pages | workflow 방식, HTTPS, custom domain 없음 |
| github-pages 환경 | main 브랜치만 허용, required reviewers/wait timer 없음 |
| Actions | 모든 Actions 허용, 기본 token read, PR 생성·승인 허용 해제 |
| 브랜치 보호/Rulesets | main protected=false, Rulesets 없음. 이번 작업에서 확대/해제하지 않음 |
| 활성화 전 상태 | calendar-data 없음, CALENDAR_ENABLED 없음, 열린 PR 없음 |
| 소스 기준 | 원격 main 28cce1cb0540b4457d6c5ef8b91cf4c18fe5ee2f, 로컬 작업79f065c03e2885d01ea3bbba6a6f89763ac7874d |

## 요구와 변경

1983~2099년을 숫자로 선택하고 한 해씩 `calendar_YYYY.xlsx`를 받는다. 기본 선택은 KST 다음 해이며 버튼에도 선택 연도를 표시한다. 범위 밖 1982/2100은 공식·수동 양쪽 UI에서 막는다. 공통 날짜 계산의1900~2100 검증과 ZIP/OOXML 작성기는 그대로 유지한다. 여러 해를 묶은 파일이나 일괄 ZIP은 요청 범위를 넘어 추가하지 않았다.

schemaVersion2의 지원/조회 대상은117개 연도다. 올해·다음 해를 먼저 처리한 뒤 나머지 연도도12개월과 모든 페이지를 실제 조회한다. 합성 응답 시험에서1,404회의 기본 요청을 전수 확인했다. 전체 실제 HTTP 시도(재시도 포함)는2,000회, 수집 job은45분 상한이다. 공공데이터포털의 개발계정 안내10,000회와 비교하면 정상14.04%, 상한20%이며 이 계정의 실제 승인량과 다른 프로그램 사용량은 미확인이다.

공식자료가 정상0건인 신규 선택 연도는 미제공으로 남긴다. 이 연도는 공식 다운로드가 차단되고 사용자가 명시적으로 수동 모드를 선택해야 한다. 현재 연도가 이번 수집에서 정상이고 실제 오류가 없는 경우에만 이런 미제공 상태를 함께 게시할 수 있다. 현재 연도0건, 기존 완전 자료 소실, HTTP/업무/검증 오류는 보존·배포skip 대상으로 유지한다. 실패를 '휴일 없음'이나 ready로 바꾸지 않는다.

## 로컬 검증

- `npm ci --prefix tools/calendar --ignore-scripts`, `npm test --prefix tools/calendar`:54개 PASS, 실패/skip0. 신규117개 연도/연간0건 구분/공유요청상한/고정범위 연도 경계/영속 배포 조건 검증 포함.
- `node tools/calendar/tests/write-fixture.mjs`, `python tools/calendar/tests/validate-schema.py`:독립 Draft2020-12 검사 PASS.
- `node tools/calendar/tests/make-sample.mjs 1983 artifacts/calendar/range/1983` 및2099동일 실행, 독립 `inspect-xlsx.py`:각365일·1,095개 실제 빈 작성셀·1시트12개월7열·무수식 PASS.
- MkDocs strict, `scripts/check-site.py site`, `scripts/check-calendar-workflow.py`, `git diff --check`:PASS.
- 실제 Edge 155.0.4283.45에서 11그룹 PASS, pageErrors 0. 1983/2026/2027 fixture 다운로드 및 2099 미제공→명시적 수동 확인→다운로드, 1982/2100 차단을 확인했다. 네 파일 모두 독립 openpyxl/OOXML로 365날짜·1,095빈칸과 미리보기 일치를 확인했다. 결과는 `artifacts/calendar/browser/results.json`, `independent-year-results.json`과 연도별 XLSX/preview JSON에 기록했다. 실제 사이트 배포 후 검증은 별도 `artifacts/calendar/live/`에 둔다.
- 기존 Excel16.0 열기·편집·저장·재열기 및12페이지 PDF 근거는 변경 없는 작성기에 재사용한다. 실제 종이 인쇄와 LibreOffice는 이번에도 NOT RUN이다.

모든 로컬 샘플은 fixture이며 실제 공식자료와 구분한다. 1983/2099 샘플과 이후 실제 자료 다운로드를 섞어 배포하지 않는다.

## 실행 순서와 증거

작업 브랜치 push→PR→해당 HEAD의 검사→main 반영 순서로 진행한다. 기존 문서의 main 자동 배포는 활성화 변수와 검증된 데이터가 없으면 건너뛴다. 승인 범위에서 `CALENDAR_ENABLED=true`를 등록하고 `main`의 dispatch를 `collect`, `initialize_data=true`로 실행한다. 첫 데이터 브랜치는 실제 검증 자료만으로 생성하고, 같은 workflow의 고정 SHA 빌드·Pages 배포로 이어진다. 첫 수집이 실패하면 최초 배포를 하지 않는다.

실제 PR URL, 검사/배포 source SHA·data SHA·run URL, 연도별 준비 상태, 공개 JSON·메뉴·다운로드 확인 결과는 완료 시 해당 PR 설명과 로컬 `artifacts/calendar/publication-result.json`에 기록한다. 실행 전 계획을 실제 성공으로 취급하지 않는다. 이 문서의 최초 작성 시점은 운영 실행 전이며 최종 결과는 이 실행 증거를 따른다.

## 최초 배포 결과와 월간 운영 변경

[PR #24](https://github.com/prozac0401/Workspace/pull/24)를 main `7358f5262fd42dc327dce0a30081456ee953ad97`로 병합하고 [최초 실제 수집·배포](https://github.com/prozac0401/Workspace/actions/runs/38106812300)를 완료했다. 데이터 SHA는 `0256ebe3e3c97bfd82351401372957d14909590f`이며 2004~2028년25개 연도 ready, 1983~2003년·2029~2099년92개 연도 unavailable, 실제 수집 오류0이다. 실제 Edge9그룹과 다운로드4개 독립 검사가 통과했다. 처음 기록한 일일 수집·24시간/30일 정책의 실행 근거는 위의 기록으로 보존한다.

이후 사용자가 월 1회 Actions 수집과 GitHub를 통한 수동 수집, 프런트의 ‘공휴일 자료 다시 읽기’ 제거를 요청했다. 최신성 질문에 **32일 후 경고·35일 초과 차단**을 명시적으로 선택했다. 변경은 매월1일KST12:17 cron, 버튼 제거와 연도 선택 자동 반영, 관련 상태 문구·경계 시험·운영 안내에 한정한다. XLSX 작성기와 데이터 수집·검증·영속 저장 방식은 유지한다.

완료 근거는 월간 cron/수동 입력 검사, 최신성 경계 단위시험, 연도 입력/변경/취소/미준비/늦은 응답의 실제 브라우저 확인, MkDocs strict와 공개 링크 검사다. 배포는 기존 공식 데이터 SHA를 재사용하며 이 UI·정책 변경 때문에 KASI를 다시 수집하지 않는다. 최초 운영 자료와 성공 시각이 그대로 게시되는지 확인한다. 실제 명령·결과·새 소스 SHA·원격 CI·배포 결과는 이 후속 PR과 로컬 `artifacts/calendar/monthly-publication-result.json`에 남긴다. 변경 없는 XLSX의 네이티브 Excel·인쇄·전체 도구 설치 검사는 반복하지 않는다.

로컬 실행: `npm ci --prefix tools/calendar --ignore-scripts`, `npm test --prefix tools/calendar`는 **55/55 PASS, 실패·skip0**이다. `python scripts/check-calendar-workflow.py`, `CALENDAR_PRODUCTION=1` 및 기존 공식 JSON을 지정한 `python -m mkdocs build --strict`, `python scripts/check-site.py site --production`, `git diff --check`도 PASS다. 실제 Edge155.0.4283.45에서 `node tools/calendar/tests/browser-check.mjs`는 **14그룹 PASS, pageErrors0**이며 `artifacts/calendar/browser-monthly-refresh/results.json`에 기록했다. 이 로컬 검증 기준은 main7358f526과 이 후속 작업 변경이며 원격 CI는 커밋 후 해당 HEAD로 별도 확인한다.

브라우저 첫 실행에서는 한 입력 안에서2027→20→2027로 되돌린 뒤 Enter를 누르면 native change가 생략되어 준비 상태로 돌아오지 않는 결함을 재현했다. 조건부 blur 확정 처리로 수정하고 Enter/Tab, 정상 전환과 수동 목록 폐기 취소를 다시 검증했다. 최초 실패는 `same-year-return-first-failure.json`에 보존하고 최종 PASS와 구분한다. 기존 일일 예약이 전환 중 실행되지 않도록 CALENDAR_ENABLED를 잠시 false로 두었으며, 월간 workflow가 main에 반영되면 true로 복원하고 기존 데이터 reuse로 배포한다.

[월간 변경 PR #25](https://github.com/prozac0401/Workspace/pull/25)의 HEAD `dc4b159bf001078a8f9fe9cf6d341973931ae7db`는 문서·Windows CI가 통과했고 main `609d572d1e36c1cb911d22c5744f556967346cb3`로 병합됐다. CALENDAR_ENABLED를 true로 복원한 뒤 [reuse 실행38108077377](https://github.com/prozac0401/Workspace/actions/runs/38108077377)은 verify/prepare-data/build 성공과 store-data 생략을 확인했지만 deploy도 생략됐다. workflow 전체의 success만으로 배포 성공이라고 기록하지 않는다. 기존 문서 재빌드 경로의 암묵적 success 조건이 생략된 선행 job의 영향을 받아 발생한 결함이다.

배포 조건에 명시적 `!cancelled()`와 `needs.build.result == 'success'`를 추가해 성공한 운영 빌드만 이어받고 취소·실패는 계속 차단한다. 기존 저장소/활성화/기본브랜치/이벤트 조건, 권한과 최신 source SHA 확인은 유지한다. workflow 검사기에 이 두 조건을 회귀 검사로 추가하고 실제 main push의 reuse 배포로 완료를 확인한다. 기존 수집·XLSX·UI 코드는 이 복구에서 수정하지 않는다.
