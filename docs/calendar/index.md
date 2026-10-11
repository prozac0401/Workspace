---
title: 달력
---

# 편집 가능한 한 해 달력

1983~2099년 중 원하는 연도와 휴일을 확인한 뒤 12개월 미리보기를 만들고 Excel 파일로 내려받으세요. 연도를 바꿔 한 해씩 내려받을 수 있습니다. 한 시트에 1~12월을 세로로 배치하며, 날짜 아래에는 매주 **빈 작성칸 3행**이 있습니다.

<div id="workspace-calendar" class="workspace-calendar" data-workspace-calendar>
  <noscript>달력 미리보기와 파일 만들기를 사용하려면 브라우저의 JavaScript를 켜 주세요.</noscript>
  <div id="mockBanner" class="notice" hidden><strong>검증용 가상 자료</strong> 이 자료는 테스트 fixture입니다. 실제 공식 공휴일 달력으로 사용하지 마세요. 내려받는 파일에도 가상 자료임을 표시합니다.</div>
  <div class="workspace">
    <div class="settings">
      <section class="card" aria-labelledby="calendar-data-heading">
        <h2 id="calendar-data-heading">1. 연도와 자료</h2>
        <label for="year">달력 연도</label>
        <div class="year-control"><input id="year" type="number" min="1983" max="2099" step="1" required inputmode="numeric"><span>년</span></div>
        <p class="hint">공식 자료와 수동 모드 모두 1983~2099년을 선택할 수 있습니다. 기본값은 한국 시각 기준 다음 해이며 선택 범위 안으로 맞춥니다. 연도를 바꾼 뒤 공휴일 자료를 다시 읽어 주세요. 실제 자료가 준비되었는지는 아래에서 확인하세요.</p>
        <button id="load" class="primary" type="button">공휴일 자료 다시 읽기</button>
        <div id="status" class="status" role="status" aria-live="polite">공개 공휴일 자료를 확인하고 있습니다.</div>
        <progress id="progress" hidden aria-label="공개 공휴일 자료 읽는 중"></progress>
        <div id="sourceDetails" class="hint"></div>
        <button id="approveStale" class="secondary" type="button" hidden>이전 자료 경고 확인 후 사용</button>
        <button id="manualMode" class="text-button" type="button">수동 자료만 사용하기</button>
        <details><summary>연도별 자료 준비 상태</summary><ul id="availabilityList" class="holiday-list"><li>아직 확인하지 않았습니다.</li></ul></details>
      </section>
      <section class="card" aria-labelledby="calendar-manual-heading">
        <h2 id="calendar-manual-heading">2. 내 휴일 추가</h2>
        <p class="hint">개인·회사 휴일이나 직접 확인한 임시공휴일을 추가할 수 있습니다. 입력은 이 브라우저에만 머무르며 서버로 보내지 않습니다. 새로고침하거나 페이지를 떠나면 지워집니다. 공식 휴일은 수정·삭제하지 않습니다.</p>
        <form id="holidayForm">
          <label for="holidayDate">날짜</label><input id="holidayDate" type="date" required>
          <label for="holidayName">휴일 이름</label><input id="holidayName" type="text" maxlength="100" placeholder="예: 창립기념일" required aria-describedby="holidayNameHelp">
          <p id="holidayNameHelp" class="hint">앞뒤 공백을 제외한 1~50자, 줄바꿈 없이 입력하세요. 최대 100개를 추가할 수 있습니다.</p>
          <label for="category">구분</label><select id="category"><option value="company">회사 휴일</option><option value="personal">개인 휴일</option></select>
          <button id="saveHoliday" class="secondary" type="submit">휴일 추가</button><button id="cancelEdit" type="button" class="text-button">입력 비우기</button>
        </form>
        <p id="formError" role="alert" class="error"></p><ul id="manualList" class="holiday-list"></ul>
      </section>
    </div>
    <div class="main-column">
      <section class="card review" aria-labelledby="calendar-preview-heading">
        <h2 id="calendar-preview-heading">3. 확인하고 내려받기</h2>
        <p class="hint">A:G 일~토 · 1시트 · 날짜 1행과 빈 작성칸 3행 · A4 세로</p>
        <details><summary id="holidaySummary">휴일 목록 확인</summary><ul id="officialList" class="holiday-list"></ul></details>
        <label id="manualReviewWrap" class="check" hidden><input type="checkbox" id="manualReview"><span>공식 공휴일 미확인을 이해했고 수동 휴일 목록을 검토했습니다.</span></label>
        <div class="actions"><button id="previewButton" class="secondary" type="button" disabled>12개월 미리보기</button><button id="download" class="primary" type="button" disabled>Excel 다운로드</button></div>
        <p id="exportStatus" role="status" aria-live="polite" class="hint">자료를 준비하면 미리보기를 만들 수 있습니다.</p>
      </section>
      <div id="empty" class="empty"><p>연도와 휴일을 확인한 뒤 미리보기를 눌러 주세요.</p><p>파일의 빈 작성칸은 Excel에서 자유롭게 편집할 수 있습니다.</p></div>
      <div class="preview-scroll" tabindex="0" role="region" aria-label="연간 달력 미리보기, 작은 화면에서는 가로로 스크롤"><div id="preview"></div></div>
    </div>
  </div>
</div>

## 자료를 사용할 때

- 공식 출처는 [한국천문연구원 특일 정보](https://www.data.go.kr/data/15012690/openapi.do)의 공휴일 자료입니다. 사이트에 게시된 검증 자료를 읽으며, 버튼을 눌러도 제공기관에 새로 조회하지 않습니다. 1983~2099년 중 아직 공식 자료가 제공되지 않거나 검증되지 않은 연도는 수동 모드를 별도로 선택해야 합니다.
- 마지막 성공 수집 후 **24시간**이 지나면 이전 자료 경고를 확인하고 사용 여부를 선택해야 합니다. **30일 초과 자료**는 공식 달력에 사용할 수 없습니다. 준비되지 않은 연도·자료 오류는 공휴일이 없는 상태와 다릅니다.
- 12개월 조회 완료는 조회 당시의 자료가 완전하다는 뜻입니다. 향후 임시공휴일까지 확정되었다는 뜻은 아닙니다. 정기 수집은 지연되거나 실행되지 않을 수 있으며, 임시공휴일의 즉시 반영을 보장하지 않습니다.
- 미리보기와 다운로드는 같은 자료를 사용합니다. 설정을 바꾸면 미리보기를 다시 만들어 주세요. **이미 내려받은 파일은 자동 갱신되지 않습니다.** 자료·생성 시각은 한국 표준시(KST)로 표시합니다.
- 미리보기는 작은 화면에서 가로로 스크롤할 수 있습니다. 긴 휴일명이 있으면 날짜 행이 늘어나며, 인쇄 결과는 Excel·LibreOffice와 글꼴에 따라 달라질 수 있습니다.
