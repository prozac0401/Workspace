import { WEEKDAYS } from './date-core.mjs';
export function renderPreview(container, model) {
  const fragment = document.createDocumentFragment();
  const metadata = document.createElement('p'); metadata.className = 'preview-metadata'; metadata.textContent = `${model.metadataText}\n${model.legendText}`; fragment.append(metadata);
  for (const month of model.months) {
    const section = document.createElement('section'); section.className = 'month';
    const heading = document.createElement('h3'); heading.textContent = `${model.config.year}년 ${month.month}월`;
    const caption = document.createElement('span'); caption.textContent = ` ${month.weeks}주`; heading.append(caption);
    const table = document.createElement('table'); table.setAttribute('aria-label', `${month.month}월 달력`);
    const thead = document.createElement('thead'), header = document.createElement('tr');
    for (const name of WEEKDAYS) { const th = document.createElement('th'); th.scope = 'col'; th.textContent = name; header.append(th); }
    thead.append(header); table.append(thead);
    const tbody = document.createElement('tbody');
    for (let q = 0; q < month.weeks; q++) for (let band = 0; band < 4; band++) {
      const tr = document.createElement('tr'); tr.className = `band-${band}`; tr.style.height = `${band === 0 ? month.weekHeights[q] : 22}pt`;
      for (const day of month.slots.slice(q * 7, q * 7 + 7)) {
        const td = document.createElement('td'); td.className = day.styleToken;
        td.dataset.cell = `${String.fromCharCode(64 + day.excelColumn)}${day.excelRow + band}`;
        if (band === 0 && day.date) { td.textContent = day.displayText; td.dataset.date = day.date; td.dataset.style = day.styleToken; }
        tr.append(td);
      }
      tbody.append(tr);
    }
    table.append(tbody); section.append(heading, table); fragment.append(section);
  }
  container.replaceChildren(fragment);
}
