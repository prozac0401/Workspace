#pragma once
#include <windows.h>
#include <uxtheme.h>
#include <string>
#pragma comment(lib, "uxtheme.lib")

namespace dvm::ui {
constexpr COLORREF Background = RGB(244,247,251), Surface = RGB(255,255,255);
constexpr COLORREF Text = RGB(23,32,50), Muted = RGB(99,112,133), Border = RGB(221,229,239);
constexpr COLORREF Accent = RGB(37,99,235), AccentSoft = RGB(235,242,255), Success = RGB(20,126,90);
inline int px(int value, UINT dpi) { return MulDiv(value, static_cast<int>(dpi), 96); }
inline bool highContrast() { HIGHCONTRASTW state{sizeof(state),0,nullptr}; return SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(state),&state,0) && (state.dwFlags & HCF_HIGHCONTRASTON); }
inline COLORREF color(COLORREF value) {
    if (!highContrast()) return value;
    if (value == Background || value == Surface || value == AccentSoft) return GetSysColor(COLOR_WINDOW);
    if (value == Accent) return GetSysColor(COLOR_HIGHLIGHT);
    if (value == Muted) return GetSysColor(COLOR_GRAYTEXT);
    return GetSysColor(COLOR_WINDOWTEXT);
}
inline HFONT makeFont(int dip, UINT dpi, int weight = FW_NORMAL) {
    return CreateFontW(-px(dip,dpi),0,0,0,weight,FALSE,FALSE,FALSE,DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
}
inline void fill(HDC dc, const RECT& area, COLORREF value) { HBRUSH brush=CreateSolidBrush(color(value)); FillRect(dc,&area,brush); DeleteObject(brush); }
inline HBRUSH surfaceBrush() { static HBRUSH brush=CreateSolidBrush(color(Surface)); return brush; }
inline HBRUSH backgroundBrush() { static HBRUSH brush=CreateSolidBrush(color(Background)); return brush; }
inline void card(HDC dc, const RECT& area, UINT dpi) {
    HBRUSH brush=CreateSolidBrush(color(Surface)); HPEN pen=CreatePen(PS_SOLID,1,color(Border));
    const auto oldBrush=SelectObject(dc,brush), oldPen=SelectObject(dc,pen);
    RoundRect(dc,area.left,area.top,area.right,area.bottom,px(16,dpi),px(16,dpi));
    SelectObject(dc,oldPen);SelectObject(dc,oldBrush);DeleteObject(pen);DeleteObject(brush);
}
inline void text(HDC dc, const std::wstring& value, RECT area, HFONT font, COLORREF ink,
    UINT flags = DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX) {
    const auto old=SelectObject(dc,font);SetBkMode(dc,TRANSPARENT);SetTextColor(dc,color(ink));
    DrawTextW(dc,value.c_str(),static_cast<int>(value.size()),&area,flags);SelectObject(dc,old);
}
inline void theme(HWND window) { SetWindowTheme(window,L"Explorer",nullptr); }
inline void button(const DRAWITEMSTRUCT& item, HFONT font, UINT dpi, bool primary = false) {
    const bool disabled=(item.itemState & ODS_DISABLED)!=0, pressed=(item.itemState & ODS_SELECTED)!=0;
    COLORREF background=primary && !disabled ? Accent : Surface;
    if (pressed && !disabled) background=primary? RGB(29,78,216):AccentSoft;
    HBRUSH brush=CreateSolidBrush(color(background)); HPEN pen=CreatePen(PS_SOLID,1,color(primary && !disabled ? background : Border));
    const auto oldBrush=SelectObject(item.hDC,brush), oldPen=SelectObject(item.hDC,pen);
    RoundRect(item.hDC,item.rcItem.left,item.rcItem.top,item.rcItem.right,item.rcItem.bottom,px(10,dpi),px(10,dpi));
    SelectObject(item.hDC,oldPen);SelectObject(item.hDC,oldBrush);DeleteObject(pen);DeleteObject(brush);
    wchar_t label[256]{};GetWindowTextW(item.hwndItem,label,256);
    RECT area=item.rcItem;if (pressed) OffsetRect(&area,0,1);
    const auto old=SelectObject(item.hDC,font);SetBkMode(item.hDC,TRANSPARENT);
    SetTextColor(item.hDC,disabled?color(Muted):(primary?(highContrast()?GetSysColor(COLOR_HIGHLIGHTTEXT):Surface):color(Text)));
    DrawTextW(item.hDC,label,-1,&area,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
    SelectObject(item.hDC,old);
    if ((item.itemState & ODS_FOCUS) && !(item.itemState & ODS_NOFOCUSRECT)) { RECT focus=item.rcItem;InflateRect(&focus,-px(5,dpi),-px(5,dpi));DrawFocusRect(item.hDC,&focus); }
}
}
