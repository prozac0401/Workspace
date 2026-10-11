---
title: 달력
---

# 나만의 한 해 달력

연도와 일정을 정하고, 원하는 서식으로 Excel 달력을 내려받으세요.

<div id="workspace-calendar" class="workspace-calendar" data-workspace-calendar>
  <noscript>달력 미리보기와 파일 만들기를 사용하려면 브라우저의 JavaScript를 켜 주세요.</noscript>
  <div id="mockBanner" class="notice" hidden><strong>검증용 가상 자료</strong> 실제 공휴일 자료가 아닙니다.</div>
  <div class="workspace">
    <div class="settings">
      <section class="card year-card" aria-labelledby="calendar-data-heading">
        <h2 id="calendar-data-heading">달력 연도</h2>
        <label class="visually-hidden" for="year">달력 연도</label>
        <div class="year-control"><input id="year" type="number" min="1983" max="2099" step="1" required inputmode="numeric" aria-describedby="yearHelp"><span>년</span><span id="yearHelp" class="hint">1983~2099년</span></div>
        <label class="lunar-option" for="showLunar"><input id="showLunar" type="checkbox" aria-describedby="lunarRangeHelp"><span>음력 날짜 표시 (MM.DD)</span></label>
        <p id="lunarRangeHelp" class="hint" hidden>음력은 1983~2050년까지 표시할 수 있습니다.</p>
        <div id="status" class="status" role="status" aria-live="polite" hidden></div>
        <button id="approveStale" class="secondary" type="button" hidden>이전 공휴일 자료 사용</button>
        <button id="manualMode" class="text-button" type="button" hidden>공휴일 없이 내 일정만 사용</button>
      </section>
      <section class="card" aria-labelledby="calendar-manual-heading">
        <h2 id="calendar-manual-heading">내 일정 추가</h2>
        <form id="holidayForm">
          <div class="schedule-scroll" tabindex="0" role="region" aria-label="내 일정 입력">
            <div class="schedule-row">
              <div><label for="holidayDate">날짜</label><input id="holidayDate" type="date" required></div>
              <div><label for="holidayName">일정 이름</label><input id="holidayName" type="text" maxlength="100" placeholder="예: 가족 여행" required></div>
              <div><label for="category">구분</label><select id="category"><option value="personal">개인</option><option value="company">회사</option></select></div>
              <button id="saveHoliday" class="secondary" type="submit">추가</button>
            </div>
          </div>
          <button id="cancelEdit" type="button" class="text-button">입력 비우기</button>
        </form>
        <p id="formError" role="alert" class="error"></p><ul id="manualList" class="holiday-list"></ul>
      </section>
      <section class="card formatting-card" aria-label="달력 서식">
        <details>
          <summary>서식과 색상</summary>
          <form id="formattingForm">
            <div class="format-grid">
              <div><label for="format-fontFamily">글꼴</label><select id="format-fontFamily" data-formatting="fontFamily"><option>맑은 고딕</option><option>Arial</option><option>바탕</option></select></div>
              <div><label for="format-titleSize">월 제목 크기 (pt)</label><input id="format-titleSize" data-formatting="titleSize" type="number" min="14" max="24" step="1" required></div>
              <div><label for="format-fontSize">날짜·일정 크기 (pt)</label><input id="format-fontSize" data-formatting="fontSize" type="number" min="8" max="16" step="1" required></div>
              <div><label for="format-writingRowHeight">작성칸 높이 (pt)</label><input id="format-writingRowHeight" data-formatting="writingRowHeight" type="number" min="16" max="32" step="1" required></div>
            </div>
            <div class="color-grid">
              <label for="format-titleColor"><span>월 제목 글자</span><input id="format-titleColor" data-formatting="titleColor" type="color"></label>
              <label for="format-titleBackground"><span>월 제목 배경</span><input id="format-titleBackground" data-formatting="titleBackground" type="color"></label>
              <label for="format-textColor"><span>평일·작성칸 글자</span><input id="format-textColor" data-formatting="textColor" type="color"></label>
              <label for="format-holidayColor"><span>일요일·공휴일</span><input id="format-holidayColor" data-formatting="holidayColor" type="color"></label>
              <label for="format-saturdayColor"><span>토요일</span><input id="format-saturdayColor" data-formatting="saturdayColor" type="color"></label>
              <label for="format-manualColor"><span>내 일정</span><input id="format-manualColor" data-formatting="manualColor" type="color"></label>
              <label for="format-weekdayBackground"><span>요일 배경</span><input id="format-weekdayBackground" data-formatting="weekdayBackground" type="color"></label>
              <label for="format-background"><span>날짜·작성칸 배경</span><input id="format-background" data-formatting="background" type="color"></label>
              <label for="format-outsideBackground"><span>날짜 없는 칸 배경</span><input id="format-outsideBackground" data-formatting="outsideBackground" type="color"></label>
              <label for="format-borderColor"><span>테두리</span><input id="format-borderColor" data-formatting="borderColor" type="color"></label>
            </div>
            <button id="resetFormatting" class="text-button" type="button">기본 서식으로 되돌리기</button>
          </form>
        </details>
      </section>
    </div>
    <div class="main-column">
      <section class="card review" aria-labelledby="calendar-preview-heading">
        <h2 id="calendar-preview-heading">미리보기와 다운로드</h2>
        <label id="manualReviewWrap" class="check" hidden><input type="checkbox" id="manualReview"><span>공휴일 없이 내 일정만 넣어 만듭니다.</span></label>
        <div class="actions"><button id="previewButton" class="secondary" type="button" disabled>12개월 미리보기</button><button id="download" class="primary" type="button" disabled>Excel 다운로드</button></div>
        <p id="exportStatus" role="status" aria-live="polite" class="hint"></p>
      </section>
      <div id="empty" class="empty"><p>미리보기에서 달력을 확인하세요.</p></div>
      <div class="preview-scroll" tabindex="0" role="region" aria-label="연간 달력 미리보기, 작은 화면에서는 가로로 스크롤"><div id="preview"></div></div>
    </div>
  </div>
</div>
