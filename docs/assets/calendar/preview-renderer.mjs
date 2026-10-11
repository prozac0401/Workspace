import { WEEKDAYS } from './date-core.mjs';
export function renderPreview(container, model) {
  const fragment = document.createDocumentFragment();
  for (const [key, value] of Object.entries(model.formatting)) {
    const property = '--sheet-' + key.replace(/[A-Z]/g, letter => '-' + letter.toLowerCase());
    container.style.setProperty(property, key === 'fontFamily' ? `"${value}"` : typeof value === 'number' ? `${value}pt` : value);
  }
  for (const month of model.months) {
    const section = document.createElement('section'); section.className = 'month';
    const heading = document.createElement('h3'); heading.textContent = `${model.config.year}년 ${month.month}월`;
    heading.style.height = `${Math.max(30, model.formatting.titleSize * 1.5 + 6)}pt`;
    const table = document.createElement('table'); table.setAttribute('aria-label', `${month.month}월 달력`);
    const thead = document.createElement('thead'), header = document.createElement('tr');
    header.style.height = `${Math.max(24, model.formatting.fontSize * 1.6 + 6)}pt`;
    for (const name of WEEKDAYS) { const th = document.createElement('th'); th.scope = 'col'; th.textContent = name; header.append(th); }
    thead.append(header); table.append(thead);
    const tbody = document.createElement('tbody');
    for (let q = 0; q < month.weeks; q++) for (let band = 0; band < 4; band++) {
      const tr = document.createElement('tr'); tr.className = `band-${band}`; tr.style.height = `${band === 0 ? month.weekHeights[q] : model.formatting.writingRowHeight}pt`;
      for (const day of month.slots.slice(q * 7, q * 7 + 7)) {
        const td = document.createElement('td'); td.className = day.styleToken;
        td.dataset.cell = `${String.fromCharCode(64 + day.excelColumn)}${day.excelRow + band}`;
        if (band === 0 && day.date) {
          if (day.lunar) {
            for (const run of day.displayRuns) {
              const span = document.createElement('span');
              span.className = `calendar-${run.kind}`; span.dataset.kind = run.kind;
              span.textContent = run.text; span.style.fontSize = `${run.fontSize}pt`; span.style.color = run.color;
              td.append(span);
            }
          } else td.textContent = day.displayText;
          td.dataset.date = day.date; td.dataset.style = day.styleToken;
          if (day.lunar) td.title = `양력 ${day.date} · 음력 ${day.lunar.year}년 ${day.lunar.isLeapMonth ? '윤' : ''}${day.lunar.month}월 ${day.lunar.day}일`;
        }
        tr.append(td);
      }
      tbody.append(tr);
    }
    table.append(tbody); section.append(heading, table); fragment.append(section);
  }
  container.replaceChildren(fragment);
}
