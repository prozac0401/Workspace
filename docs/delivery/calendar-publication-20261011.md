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

월간 변경과 재사용 배포 복구는 [PR #26](https://github.com/prozac0401/Workspace/pull/26), main `cc3f9e3f3975f9534fc28fded51b6ebc6a6d0506`, [실제 배포38108452661](https://github.com/prozac0401/Workspace/actions/runs/38108452661)에서 완료했다. store-data 생략·build/deploy 성공, 실제 브라우저의 버튼 제거·자동 연도 전환·다운로드와 기존 데이터 hash/시각 보존을 확인했다. 기록은 `artifacts/calendar/monthly-publication-result.json`이다.

## 공식 휴일 표시명 변경

사용자가 ‘기독탄신일’을 ‘크리스마스’로 표시하는 로직을 요청했다. 공식 항목의 해당 문자열만 공통 모델에서 변환하며 대체공휴일의 괄호 안 이름도 포함한다. 공식 목록과 preview/XLSX에 같은 표시를 적용하고 원본 JSON·snapshot·sources·수집 시각, 수동 입력은 보존한다. 날짜 행의 표시 중복은 변환 후 정리하고 모든 출처를 유지한다. 완료 근거는 관련 모델/OOXML 단위시험, 기존 공식 데이터로 strict 빌드·공개 링크 검사, 실제 2027년 공식 목록/미리보기/XLSX의 두 날짜 표시 확인이다. 변경 없는 날짜 계산·네이티브 Excel/인쇄·설치 검사는 반복하지 않는다. 명령·결과·source/data SHA와 배포 후 확인은 후속 PR 및 `artifacts/calendar/christmas-publication-result.json`에 남긴다.

위 표시명 변경의 로컬 모델13개·실제JSON strict/check-site와 실제Edge·독립OOXML 두셀 검증은 통과했다. `artifacts/calendar/christmas-label/local-2026-10-11T03-43-01-975Z`에 결과를 남겼으며, 원격 반영 전 사용자의 다음 화면·인쇄 요청이 도착하여 같은 작업 범위를 확장한다. 이 중간 성공을 확장 변경 전체의 성공으로 사용하지 않는다.

## 화면·인쇄·서식 후속 요구

사용자는1월 상단의 불필요한 인쇄 헤더와 사용자에게 필요 없는 세부 설명을 제거하고, 연도 안내는1983~2099년으로만 줄이며 자료 읽기·연도별 현황·상시 주의사항을 없애도록 요청했다. ‘내 휴일 추가’는 ‘내 일정 추가’로 바꾸고 날짜·이름·구분·추가를 한 가로 행으로 제공한다. 미리보기의 사이트 테마 색상과 XLSX색 차이를 없애고 각 요소의 서식·색상을 사용자 설정으로 제공한다.

구현은 정상 상태의 운영 상세 제거, 상황별 오류/동의만 유지, 반응형 가로 입력, 공통 불변 서식, 테마와 독립인 달력 미리보기, A5부터 인쇄와 운영 metadata의 문서 속성 이동에 한정한다. 기존 달력 날짜좌표·빈 작성3행·공식원문·월간수집·32일/35일·데이터 branch는 보존한다. 사용자 최신 요구가 기존 상단metadata/항상출처 표시와 초안작성기 무수정 선택을 대체한다. 새공개자산은 formatting.mjs만 허용목록과 검사기에 함께 추가한다.

충분한 완료 근거는 관련 모델/서식/OOXML 시험과 독립파서, 실제브라우저의 가로배치·간소화·서식무효화·테마다크/라이트색상일치·설정다운로드, 실제Excel 사본의 PDF1월상단·기본12개월인쇄, strict빌드·공개링크·현재HEAD CI와배포확인이다. 출력이 바뀌었으므로 이번에는 Excel PDF검사를 다시 수행한다. 실제종이인쇄·LibreOffice·다른도구설치검사는 NOT RUN 범위다. 실제 결과는 아래에 기록하고 작업산출물은 `artifacts/calendar/customization/`, 최종 원격 증거는 `customization-publication-result.json`에 둔다. 운영JSON은 동일SHA를 재사용하며 KASI추가수집은 하지 않는다.

중간 로컬 결과: `node --test tools/calendar/tests/core.test.mjs`15/15 PASS. `tools/calendar/tests/inspect-xlsx.py`는 `artifacts/calendar/formatting/{default,custom}`의 각365날짜·1,095빈셀·A5인쇄·12제목병합·문서속성·서식 PASS다. `node tools/calendar/tests/browser-check.mjs`15그룹과 실제공식JSON 별도4그룹은 Edge155에서 PASS/pageErrors0이다. `artifacts/calendar/browser-compact-formatting/results.json`, `compact-formatting/local-2026-10-11T03-54-23-064Z/results.json` 및 독립서식 XLSX결과에 기록했다. 공개 JSON hash는 그대로다. 이후 음력 요청과 renderer 높이 보정을 최종 작은 범위에서 추가 확인한다.

`powershell -NoProfile -File tools/calendar/tests/excel-check.ps1 -OutputDirectory artifacts/calendar/formatting/default`는 Excel16.0/build20430에서 열기·A5인쇄·숨김빈1~4행·편집/저장/재열기·PDF출력 PASS다. PDF독립검사는12페이지 모두 월 제목부터 시작하며 불필요한 metadata가 없는 것을 확인했고1월/12월을PNG로 렌더링하여 육안 확인했다. 파일은 `formatting/default/excel-results.json`, `pdf-inspection.json`, `excel-print.pdf`다. 실제종이출력은 하지 않았다.

검증 도구 초기 실패도 구분한다. Windows PowerShell5.1의 UTF-8 한글 리터럴 읽기 오류는 테스트에서 Unicode 문자코드로 비교하도록 고쳤다. PDF text 추출의 내부 쓰기 순서를 시각 순서로 오인한 assertion은 pdfplumber의 페이지 좌표순서로 검증하도록 고쳤다. 브라우저에서는 폭0인 보이지 않는 테두리의 상속색을 비교한 기대값을 실제 표시되는 테두리만 비교하도록 수정했다. 각각 수정 후 위 검사가 통과했으며 제품 실패를 성공으로 바꿔 기록하지 않는다.

## 음력 표시 선택 추가

사용자는 날짜 오른쪽 `(MM.DD)` 음력 표시를 선택적으로 추가하도록 요청했다. 한국음력표와 계산결과를 조사한 뒤, 확인 가능한 표가2050년까지이며 이후 계산에는하루차이가있다는 선택지를 안내했고 사용자는 **음력은1983~2050년만 제공**을 확정했다. 달력1983~2099 범위는 유지한다. 기본off,범위밖비활성화,불변모델의동일값을미리보기와XLSX에표시하고작성칸은계속비운다. 수집 API나Secret 사용범위를늘리지않는다. 표/조회모듈두개만추가공개하고generation·license·전수검사를저장소에보존한다.

추가완료근거는 정적표재현·1983~2050 전체일자비교·윤월/연도경계·옵션무효화, 실제브라우저의defaultoff/on/off·2050허용·2051/2099비활성·날짜텍스트와독립XLSX일치이다. 기본off의Excel인쇄결과는앞단검사를재사용한다. 음력on은별도샘플에서날짜행에만추가되는지확인하고필요한실제출력검증만추가한다. 최종PR/소스SHA·배포·미실행은최종증거에명시한다.

최종 로컬 실행: `npm ci --prefix tools/calendar --ignore-scripts`와 `npm test --prefix tools/calendar` **64/64 PASS(실패/skip0)**, 음력 생성물 재현·24,837일 참조표 비교·윤월/2033/시간대 검사 포함이다. 실제 기존KASI 설날·추석50개 기준 날짜도 일치했다(`lunar-research/official-festival-anchors.json`). 참조 패키지와의 전수 일치를 KASI API전수검증이라고 해석하지 않는다. 기본·사용자 서식과 음력 fixture독립검사도 PASS다.

최종 productionJSON 빌드: `CALENDAR_DATA_FILE=artifacts/calendar/first-official-dataset.json`, `CALENDAR_PRODUCTION=1`에서 `python -m mkdocs build --strict` 및 `python scripts/check-site.py site --production` PASS(22공개페이지+2redirect+404). workflow검사와diff검사 PASS. 로컬 기준은 main`cc3f9e3f3975f9534fc28fded51b6ebc6a6d0506`에서 시작한 이번작업이며 최종커밋과원격CI는후속PR에서고정한다.

실제 Edge 최종4그룹은 음력defaultoff/on/off, 1983/2050 허용·2051해제/차단·2099양력 유지, 제목/요일높이·사용자서식·테마다크/라이트색상 보존을 확인했다. `artifacts/calendar/lunar/local-2026-10-11T04-03-32-650Z/results.json`에 PASS/pageErrors0이며 실제공식2027+음력+사용자서식 XLSX의 독립파서도 **미리보기1,764셀/365날짜/1,095빈작성셀 전수 PASS**다. 최신`browser-xlsx-inspection.json`으로 앞선 custom전셀미실행 제한을 해소했다. 처음 예상한2027설날2/6은실제기준2/7과달라하네스기대값을수정했고 2/6=12.30,2/7=01.01둘다검증했다. 첫 실패는별도결과폴더에보존했다.

음력on fixture에도 `powershell -NoProfile -File tools/calendar/tests/excel-check.ps1 -OutputDirectory artifacts/calendar/lunar/fixture`를 실행해 Excel16.0/build20430 열기·A5인쇄·편집저장재열기·PDF출력 PASS다. PDF12페이지가각월제목으로시작하고1월1일의`1 (11.24)` 표시·빈작성3행을텍스트/좌표검사와PNG육안으로확인했다. 실제종이출력과LibreOffice는NOT RUN이다. 개인원본파일·원래checkout사용자수정·Secret은변경하지않았다.

## 음력 부분서식 후속 요청

앞선 작업은 PR #27·main `426ab0297bc2758fae453a593fdc71bd85511d36`·배포 38110670958에서 완료됐으며 소스·데이터·실제 배포 검사는 `artifacts/calendar/customization-publication-result.json`에 보존했다. 사용자는 이후 음력을 양력보다 작은 회색으로 표시하고 크기·색상을 독립 설정하며 미리보기와 엑셀을 일치시키도록 요청했다.

이번 범위는 기본 7pt/#777777, 음력 전용 크기 6~16pt와 색상 필드, 공통 불변 `displayRuns`와 OOXML 부분 서식이다. 양력·휴일 색, 전체 문자열·입력 안전·작성 빈 3행·음력 해제·정적 자료·인쇄 좌표는 유지한다. 작업은 깨끗한 관리 worktree에서 main 426ab029 기반 `codex/calendar-lunar-style`로 격리하며 원래 D:/Github_REPOS/Workspace의 사용자 수정은 변경하지 않는다.

완료 근거는 관련 모델·부분 서식·경계 단위시험, 실제 브라우저의 기본·custom·off·reset·다크 모드 일치와 다운로드, 독립 ZIP/XML 파서의 모든 date run 크기·색상 및 빈 작성셀, 실제 Excel Characters 부분 서식과 저장·재열기다. 기존 날짜 변환·공휴일 수집·전체 인쇄 PDF·설치시험은 재사용하고 반복하지 않는다. strict 사이트 빌드·공개 링크와 커밋 CI·배포 후 같은 범위의 검사를 수행한다. 실제 결과·미실행과 source/data SHA는 PR 및 `artifacts/calendar/lunar-style/`에 기록한다.

로컬 검증 기준은 위 main HEAD와 이번 변경이다. `node --test tools/calendar/tests/core.test.mjs`는 **19/19 PASS**다. `CALENDAR_DATA_FILE=artifacts/calendar/first-official-dataset.json`, `CALENDAR_PRODUCTION=1`로 `python -m mkdocs build --strict`와 `python scripts/check-site.py site --production`을 실행해 **PASS**다. 실제 공개 JSON의 기존 수집 시각과 SHA256 `eadb9a96020bebe8b55ef36f7b389f7a356bb09869e090041e326fe48e22c146`을 사용했다.

`CALENDAR_LUNAR_STYLE_READY=1 CALENDAR_LUNAR_STYLE_TARGET=local node artifacts/calendar/lunar-style/style-check.mjs`의 실제 Edge 155 결과는 **3그룹 PASS**, pageErrors 0이다. 기본 음력 7pt/#777777, 사용자 음력 12pt/#2A6F7B, 해제·기본값 복원·다운로드 무효화·다크 모드 보존을 확인했다. 각 variant에 `python tools/calendar/tests/inspect-browser-export.py --base <variant-directory> --years`를 실행한 독립 검사도 **1,764셀·365일·1,095개 빈 작성셀 PASS**다. ON은 365개 부분 서식 날짜 셀, OFF는 0개이며 양력·휴일 서식을 보존한다. 결과와 실제 공식 자료 다운로드는 `artifacts/calendar/lunar-style/local-2026-10-11T04-29-27-084Z/`에 있다. 첫 파서 실행은 CSS fallback 목록 전체를 단일 XLSX 글꼴명과 비교한 검사기 오류로 실패했다. 첫 글꼴명을 비교하도록 고친 뒤 동일 캡처로 재검사했으며 첫 실패를 `first-parser-failure.json`에 보존했다.

fixture 기본 10/7pt와 큰 음력 8/16pt 파일은 `python tools/calendar/tests/inspect-xlsx.py <sample.xlsx>`로 모든 rich text·빈 작성셀 검사를 통과했다. `powershell -NoProfile -ExecutionPolicy Bypass -File artifacts/calendar/lunar-style/excel-runs-check.ps1`은 실제 Excel 16.0/build 20430에서 두 fixture의 각 365일·739개 텍스트 조각의 글꼴·크기·색상을 전수 확인했다. 작성칸 편집·저장·재열기 후 같은 전수 검사도 **PASS**다. 결과는 `artifacts/calendar/lunar-style/excel-runs-results.json`이다. 이 fixture는 운영 자료로 배포하지 않는다. 이번 변경의 전체 PDF·실물 인쇄·LibreOffice는 **NOT RUN**이며 기존 인쇄 검증을 재사용했다. 인쇄 설정은 바꾸지 않았다.

## 입력 정렬과 미리보기 너비 후속 요청

PR #28은 main `8ef6fc5b22a58fede886e8967a900d2aa9e093f2`, 배포 38111990105에서 완료했고 실제 검증은 `artifacts/calendar/lunar-style/publication-result.json`에 보존했다. 이번 요청은 컨트롤 텍스트 중앙 정렬, 범위 문구 `(범위 : 1983~2099)`, 일정 입력행 높이 통일, 미리보기 오른쪽 테두리까지 초기 화면에 표시하는 것이다. 같은 관리 worktree의 깨끗한 main에서 `codex/calendar-control-layout`로 작업하며 원래 checkout의 사용자 수정은 보존한다.

원인은 달력의 최소 너비 780px와 입력 요소별 기본 줄 높이·padding 차이다. 기존 배포를 Edge에서 측정했을 때 일정 date/name/select/button 높이는 각각 53.75/51.75/48/53.75px였고, 모바일 미리보기는 358px 영역에 780px 달력을 표시했다. 수정은 scoped CSS 중앙 정렬과 일정 입력 높이 2.7rem, 기존 780px 달력 종이를 영역 너비에 맞춰 비례 축소하는 ResizeObserver다. 이탈 시 observer를 해제하며 XLSX 서식·공휴일 수집·데이터 계약은 변경하지 않는다.

완료 판단은 실제 브라우저의 PC·사용자 화면에 해당하는 772px 내용 폭·모바일 390px·창 크기 변경, 입력 높이/정렬과 달력 12개월 테두리 포함 여부, 일정 추가와 내부 재진입 확인이다. strict build와 공개 링크 검사 및 현재 HEAD CI도 수행한다. 전체 모델·수집기·Excel·인쇄 시험은 변경 대상이 아니므로 기존 결과를 재사용한다. 증거는 `artifacts/calendar/control-layout/` 및 PR에 남긴다.

위 main HEAD와 로컬 변경에서 `node --check docs/assets/calendar/app.mjs`, `git diff --check`, 실제 검증 JSON을 사용한 `python -m mkdocs build --strict`와 `python scripts/check-site.py site --production`이 **PASS**다. `CALENDAR_CONTROL_LAYOUT_READY=1`, `CALENDAR_CONTROL_LAYOUT_TARGET=local`로 `node artifacts/calendar/control-layout/layout-check.mjs`를 실행한 Edge 155 검사도 **2그룹 PASS**, pageErrors 0이다. 일정 입력 4개는 각각 높이 54px와 같은 상·하단 좌표이고, 1440px 창·772px 내용 영역·390px 모바일·재확대에서 12개월의 오른쪽 테두리가 처음부터 영역 안에 있다. 원래 텍스트·글자 서식, 내부 페이지 재진입, 일정 1회 추가 및 다운로드 활성화도 확인했다. 결과와 육안 확인한 화면은 `artifacts/calendar/control-layout/local-2026-10-11T04-44-58-453Z/`에 있다.

첫 두 하네스 실행은 축소 후 전체 높이를 역산한 차이를 2px 미만으로 요구하여 실패했다. 실제 차이는 2.416px(0.27%)의 브라우저 반올림이었고 경계 넘침·텍스트 변경·잘림은 없었다. 이 과도한 기대를 제거하고 테두리의 실제 화면 좌표·모든 날짜 텍스트와 글자 서식 보존으로 검사했다. 첫 실패 결과도 같은 산출물 폴더 아래 보존한다. 이번에는 Excel·전체 인쇄·무관한 전체 브라우저 suite를 **NOT RUN**으로 남기며 앞선 증거를 재사용한다. 원격 CI와 배포 결과는 최종 PR 및 별도 publication-result.json에 정확한 HEAD로 기록한다.
