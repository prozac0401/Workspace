import { zipStore } from './zip.mjs';
import { WEEKDAYS } from './date-core.mjs';
const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const relns = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const esc = s => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
const colorMap = { black: 'FF17202A', red: 'FF9C2436', blue: 'FF2158A6', purple: 'FF70308C', outside: 'FF17202A', white: 'FFFFFFFF' };
// Literal strings that look like OOXML escapes must stay literal in Excel.
const excelText = s => esc(String(s).replace(/_x[0-9a-f]{4}_/gi, token => '_x005F_' + token.slice(1)));
export function workbookParts(model) {
  if (!Object.isFrozen(model) || model.months.length !== 12) throw new Error('고정된 미리보기 모델이 필요합니다.');
  const styles = [], styleMap = new Map(), borders = [], borderMap = new Map();
  const fontNames = Object.keys(colorMap);
  function borderId(left, right, top, bottom) {
    const key = [left, right, top, bottom].join(',');
    if (!borderMap.has(key)) {
      borderMap.set(key, borders.length);
      const side = (name, style) => style ? `<${name} style="${style}"><color rgb="FFBAC3CC"/></${name}>` : `<${name}/>`;
      borders.push(`<border>${side('left', left)}${side('right', right)}${side('top', top)}${side('bottom', bottom)}<diagonal/></border>`);
    }
    return borderMap.get(key);
  }
  const none = borderId('', '', '', '');
  function styleId({ color = 'black', fill = 0, border = none, title = false, center = false } = {}) {
    const font = title ? 6 : fontNames.indexOf(color);
    const key = [font, fill, border, center].join(',');
    if (!styleMap.has(key)) {
      styleMap.set(key, styles.length);
      styles.push(`<xf numFmtId="0" fontId="${font}" fillId="${fill}" borderId="${border}" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="${center ? 'center' : 'left'}" vertical="top" wrapText="1"/></xf>`);
    }
    return styleMap.get(key);
  }
  styleId();
  const cell = (r, c, value, style) => `<c r="${String.fromCharCode(64 + c)}${r}" s="${style}"${value === null ? '/>' : ` t="inlineStr"><is><t xml:space="preserve">${excelText(value)}</t></is></c>`}`;
  const rows = [], merges = ['A1:G1', 'A2:G2', 'A3:G3'];
  const row = (r, height, cells = '') => rows.push(`<row r="${r}" ht="${height}" customHeight="1">${cells}</row>`);
  row(1, 34, cell(1, 1, model.title, styleId({ title: true, fill: 3 })));
  row(2, 46, cell(2, 1, model.metadataText, styleId({ fill: 4 })));
  row(3, 42, cell(3, 1, model.legendText, styleId()));
  row(4, 10);
  for (const month of model.months) {
    const s = month.startRow;
    merges.push(`A${s}:G${s}`);
    row(s, 30, cell(s, 1, `${model.config.year}년 ${month.month}월`, styleId({ title: true, fill: 3 })));
    row(s + 1, 24, WEEKDAYS.map((name, i) => cell(s + 1, i + 1, name, styleId({ color: i === 0 ? 'red' : i === 6 ? 'blue' : 'black', fill: 4, center: true }))).join(''));
    for (let q = 0; q < month.weeks; q++) {
      for (let band = 0; band < 4; band++) {
        const r = s + 2 + q * 4 + band;
        const cells = month.slots.slice(q * 7, q * 7 + 7).map((day, i) => {
          const border = borderId(i === 0 ? 'medium' : 'thin', i === 6 ? 'medium' : 'thin', band === 0 ? 'medium' : 'thin', band === 3 ? 'medium' : 'thin');
          return cell(r, i + 1, band === 0 && day.date ? day.displayText : null, styleId({ color: band === 0 ? day.styleToken : 'black', fill: day.date ? 0 : 2, border }));
        }).join('');
        row(r, band === 0 ? month.weekHeights[q] : 22, cells);
      }
    }
    if (month.month < 12) row(month.endRow + 1, 10);
  }
  const sheet = declaration + `<worksheet xmlns="${ns}"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:G${model.endRow}"/><sheetViews><sheetView showGridLines="0" workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="22"/><cols><col min="1" max="7" width="18" customWidth="1"/></cols><sheetData>${rows.join('')}</sheetData><mergeCells count="${merges.length}">${merges.map(ref => `<mergeCell ref="${ref}"/>`).join('')}</mergeCells><printOptions gridLines="0"/><pageMargins left="0.25" right="0.25" top="0.35" bottom="0.35" header="0.15" footer="0.15"/><pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="0"/><rowBreaks count="11" manualBreakCount="11">${model.months.slice(1).map(m => `<brk id="${m.startRow - 1}" min="0" max="16383" man="1"/>`).join('')}</rowBreaks></worksheet>`;
  const fonts = fontNames.map(name => `<font><sz val="10"/><color rgb="${colorMap[name]}"/><name val="맑은 고딕"/><family val="2"/><charset val="129"/></font>`);
  fonts.push('<font><b/><sz val="16"/><color rgb="FFFFFFFF"/><name val="맑은 고딕"/><family val="2"/><charset val="129"/></font>');
  const styleXml = declaration + `<styleSheet xmlns="${ns}"><fonts count="${fonts.length}">${fonts.join('')}</fonts><fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF0F2F4"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF213E46"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE8F0F1"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="${borders.length}">${borders.join('')}</borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="${styles.length}">${styles.join('')}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
  return {
    '[Content_Types].xml': declaration + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': declaration + `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${relns}/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
    'xl/workbook.xml': declaration + `<workbook xmlns="${ns}" xmlns:r="${relns}"><bookViews><workbookView/></bookViews><sheets><sheet name="${esc(model.title)}" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm.Print_Area" localSheetId="0">'${esc(model.title)}'!$A$1:$G$${model.endRow}</definedName></definedNames></workbook>`,
    'xl/_rels/workbook.xml.rels': declaration + `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${relns}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="${relns}/styles" Target="styles.xml"/></Relationships>`,
    'xl/worksheets/sheet1.xml': sheet,
    'xl/styles.xml': styleXml,
  };
}
export const exportXlsx = model => zipStore(workbookParts(model));
export function downloadXlsx(model) {
  const bytes = exportXlsx(model);
  const url = URL.createObjectURL(new Blob([bytes], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
  const a = document.createElement('a'); a.href = url; a.download = `calendar_${model.config.year}.xlsx`; document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
  return bytes.length;
}
