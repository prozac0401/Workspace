import { zipStore } from './zip.mjs';
import { WEEKDAYS } from './date-core.mjs';
const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const relns = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const esc = s => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
// Literal strings that look like OOXML escapes must stay literal in Excel.
const excelText = s => esc(String(s).replace(/_x[0-9a-f]{4}_/gi, token => '_x005F_' + token.slice(1)));
export function workbookParts(model) {
  if (!Object.isFrozen(model) || model.months.length !== 12) throw new Error('고정된 미리보기 모델이 필요합니다.');
  const format = model.formatting;
  const argb = color => 'FF' + color.slice(1);
  const colorMap = { black: argb(format.textColor), red: argb(format.holidayColor), blue: argb(format.saturdayColor), purple: argb(format.manualColor), outside: argb(format.textColor), white: argb(format.titleColor) };
  const styles = [], styleMap = new Map(), borders = [], borderMap = new Map();
  const fontNames = Object.keys(colorMap);
  function borderId(left, right, top, bottom) {
    const key = [left, right, top, bottom].join(',');
    if (!borderMap.has(key)) {
      borderMap.set(key, borders.length);
      const side = (name, style) => style ? `<${name} style="${style}"><color rgb="${argb(format.borderColor)}"/></${name}>` : `<${name}/>`;
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
  const rows = [], merges = [];
  const row = (r, height, cells = '') => rows.push(`<row r="${r}" ht="${height}" customHeight="1">${cells}</row>`);
  for (let r = 1; r <= 4; r++) rows.push(`<row r="${r}" hidden="1" ht="0" customHeight="1"/>`);
  for (const month of model.months) {
    const s = month.startRow;
    merges.push(`A${s}:G${s}`);
    row(s, Math.max(30, format.titleSize * 1.5 + 6), cell(s, 1, `${model.config.year}년 ${month.month}월`, styleId({ title: true, fill: 3 })));
    row(s + 1, Math.max(24, format.fontSize * 1.6 + 6), WEEKDAYS.map((name, i) => cell(s + 1, i + 1, name, styleId({ color: i === 0 ? 'red' : i === 6 ? 'blue' : 'black', fill: 4, center: true }))).join(''));
    for (let q = 0; q < month.weeks; q++) {
      for (let band = 0; band < 4; band++) {
        const r = s + 2 + q * 4 + band;
        const cells = month.slots.slice(q * 7, q * 7 + 7).map((day, i) => {
          const border = borderId(i === 0 ? 'medium' : 'thin', i === 6 ? 'medium' : 'thin', band === 0 ? 'medium' : 'thin', band === 3 ? 'medium' : 'thin');
          return cell(r, i + 1, band === 0 && day.date ? day.displayText : null, styleId({ color: band === 0 ? day.styleToken : 'black', fill: day.date ? 5 : 2, border }));
        }).join('');
        row(r, band === 0 ? month.weekHeights[q] : format.writingRowHeight, cells);
      }
    }
    if (month.month < 12) row(month.endRow + 1, 10);
  }
  const sheet = declaration + `<worksheet xmlns="${ns}"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A5:G${model.endRow}"/><sheetViews><sheetView showGridLines="0" workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="${format.writingRowHeight}"/><cols><col min="1" max="7" width="18" customWidth="1"/></cols><sheetData>${rows.join('')}</sheetData><mergeCells count="${merges.length}">${merges.map(ref => `<mergeCell ref="${ref}"/>`).join('')}</mergeCells><printOptions gridLines="0"/><pageMargins left="0.25" right="0.25" top="0.35" bottom="0.35" header="0.15" footer="0.15"/><pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="0"/><rowBreaks count="11" manualBreakCount="11">${model.months.slice(1).map(m => `<brk id="${m.startRow - 1}" min="0" max="16383" man="1"/>`).join('')}</rowBreaks></worksheet>`;
  const fontDetails = `<name val="${esc(format.fontFamily)}"/><family val="${format.fontFamily === '바탕' ? 1 : 2}"/><charset val="${format.fontFamily === 'Arial' ? 0 : 129}"/>`;
  const fonts = fontNames.map(name => `<font><sz val="${format.fontSize}"/><color rgb="${colorMap[name]}"/>${fontDetails}</font>`);
  fonts.push(`<font><b/><sz val="${format.titleSize}"/><color rgb="${argb(format.titleColor)}"/>${fontDetails}</font>`);
  const solidFill = color => `<fill><patternFill patternType="solid"><fgColor rgb="${argb(color)}"/><bgColor indexed="64"/></patternFill></fill>`;
  const styleXml = declaration + `<styleSheet xmlns="${ns}"><fonts count="${fonts.length}">${fonts.join('')}</fonts><fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>${[format.outsideBackground, format.titleBackground, format.weekdayBackground, format.background].map(solidFill).join('')}</fills><borders count="${borders.length}">${borders.join('')}</borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="${styles.length}">${styles.join('')}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
  return {
    '[Content_Types].xml': declaration + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>',
    '_rels/.rels': declaration + `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${relns}/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>`,
    'docProps/core.xml': declaration + `<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${esc(model.title)}</dc:title><dc:description>${esc(model.metadataText + '\n' + model.legendText)}</dc:description><dcterms:created xsi:type="dcterms:W3CDTF">${esc(model.generatedAt)}</dcterms:created></cp:coreProperties>`,
    'xl/workbook.xml': declaration + `<workbook xmlns="${ns}" xmlns:r="${relns}"><bookViews><workbookView/></bookViews><sheets><sheet name="${esc(model.title)}" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm.Print_Area" localSheetId="0">'${esc(model.title)}'!$A$5:$G$${model.endRow}</definedName></definedNames></workbook>`,
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
