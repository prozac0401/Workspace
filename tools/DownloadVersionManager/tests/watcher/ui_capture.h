#pragma once
#include <windows.h>
#include <fstream>
#include <filesystem>
#include <string>
#include <vector>
// Render the actual HWND client and native child controls to a private BMP.
// This is an offscreen native render, not a claim of interactive desktop testing.
inline bool captureNative(HWND window, const std::wstring& path, bool visibleCapture = false) {
    const bool wasVisible=IsWindowVisible(window)!=FALSE;
    if (visibleCapture) { ShowWindow(window,SW_SHOWNOACTIVATE);UpdateWindow(window);EnumChildWindows(window,[](HWND item,LPARAM)->BOOL {UpdateWindow(item);return TRUE;},0);}
    RECT area{};GetClientRect(window,&area);if (area.right<=0||area.bottom<=0) return false;
    HDC screen=GetDC(window),dc=CreateCompatibleDC(screen);HBITMAP bitmap=CreateCompatibleBitmap(screen,area.right,area.bottom);const auto old=SelectObject(dc,bitmap);
        SendMessageW(window,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(dc),PRF_CLIENT|PRF_ERASEBKGND);
    struct Capture { HWND parent; HDC dc; } context{window,dc};
    EnumChildWindows(window,[](HWND item,LPARAM value)->BOOL {
        auto& context=*reinterpret_cast<Capture*>(value);if (GetParent(item)!=context.parent || !(GetWindowLongPtrW(item,GWL_STYLE)&WS_VISIBLE)) return TRUE;
        RECT bounds{};GetWindowRect(item,&bounds);MapWindowPoints(nullptr,context.parent,reinterpret_cast<POINT*>(&bounds),2);
        const int saved=SaveDC(context.dc);SetViewportOrgEx(context.dc,bounds.left,bounds.top,nullptr);
        SendMessageW(item,WM_PRINT,reinterpret_cast<WPARAM>(context.dc),PRF_CLIENT|PRF_NONCLIENT|PRF_ERASEBKGND|PRF_CHILDREN);
        RestoreDC(context.dc,saved);return TRUE;
    },reinterpret_cast<LPARAM>(&context));
    if (visibleCapture) BitBlt(dc,0,0,area.right,area.bottom,screen,0,0,SRCCOPY);
    if (visibleCapture && !wasVisible) ShowWindow(window,SW_HIDE);
    SelectObject(dc,old);BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=area.right;info.bmiHeader.biHeight=-area.bottom;
    info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
    std::vector<BYTE> pixels(static_cast<size_t>(area.right)*area.bottom*4);
    const bool read=GetDIBits(screen,bitmap,0,static_cast<UINT>(area.bottom),pixels.data(),&info,DIB_RGB_COLORS)!=0;
    DeleteObject(bitmap);DeleteDC(dc);ReleaseDC(window,screen);if (!read) return false;
    BITMAPFILEHEADER header{};header.bfType=0x4D42;header.bfOffBits=sizeof(header)+sizeof(BITMAPINFOHEADER);header.bfSize=header.bfOffBits+static_cast<DWORD>(pixels.size());
    std::ofstream output(std::filesystem::path(path),std::ios::binary);output.write(reinterpret_cast<const char*>(&header),sizeof(header));
    output.write(reinterpret_cast<const char*>(&info.bmiHeader),sizeof(BITMAPINFOHEADER));output.write(reinterpret_cast<const char*>(pixels.data()),static_cast<std::streamsize>(pixels.size()));return output.good();
}
