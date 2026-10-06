// Exercise the actual log handler in a hidden, synthetic application window.
#define wWinMain DvmUnusedWinMain
#include "../../source/app.cpp"
#undef wWinMain
#include "engine.h"
#include <iostream>

int wmain() {
    INITCOMMONCONTROLSEX common{sizeof(common),ICC_LISTVIEW_CLASSES};InitCommonControlsEx(&common);
    WNDCLASSW kind{};kind.lpfnWndProc=windowProc;kind.hInstance=GetModuleHandleW(nullptr);kind.lpszClassName=L"DvmLogTest";RegisterClassW(&kind);
    HWND window=CreateWindowExW(0,kind.lpszClassName,L"synthetic log",WS_OVERLAPPEDWINDOW,0,0,940,840,nullptr,nullptr,kind.hInstance,nullptr);
    if (!window || !messages) return 2;
    dvm::Result result;result.status=L"permission_denied";result.error=ERROR_ACCESS_DENIED;result.readOnlyProtected=true;
    const std::wstring shortName=L"report (1).txt";
    const std::wstring longName=std::wstring(100,L'가')+L" (1).txt";
    const auto shortMessage=dvm::resultMessage(shortName,result),longMessage=dvm::resultMessage(longName,result);
    HDC dc=GetDC(messages);HGDIOBJ old=SelectObject(dc,font);SIZE shortSize{},longSize{},prefixSize{};
    GetTextExtentPoint32W(dc,shortMessage.c_str(),static_cast<int>(shortMessage.size()),&shortSize);
    GetTextExtentPoint32W(dc,longMessage.c_str(),static_cast<int>(longMessage.size()),&longSize);
    const auto prefix=longMessage.substr(0,longMessage.find(L" · ")+3);
    GetTextExtentPoint32W(dc,prefix.c_str(),static_cast<int>(prefix.size()),&prefixSize);SelectObject(dc,old);ReleaseDC(messages,dc);
    SendMessageW(window,ReportMessage,0,reinterpret_cast<LPARAM>(new std::wstring(shortMessage)));
    SendMessageW(window,ReportMessage,0,reinterpret_cast<LPARAM>(new std::wstring(longMessage)));
    result.readOnlyProtected=false;const auto general=dvm::resultMessage(L"report (2).txt",result);
    SendMessageW(window,ReportMessage,0,reinterpret_cast<LPARAM>(new std::wstring(general)));
    SendMessageW(messages,LB_SETTOPINDEX,0,0);
    RECT client{};GetClientRect(messages,&client);const auto extent=SendMessageW(messages,LB_GETHORIZONTALEXTENT,0,0);
    SCROLLINFO scroll{};scroll.cbSize=sizeof(scroll);scroll.fMask=SIF_RANGE|SIF_PAGE;const BOOL scrollOkay=GetScrollInfo(messages,SB_HORZ,&scroll);
    wchar_t text[512]{};SendMessageW(messages,LB_GETTEXT,1,reinterpret_cast<LPARAM>(text));
    const bool stored=std::wstring(text)==longMessage;
    const bool okay=shortSize.cx<client.right && prefixSize.cx<client.right && stored && extent>=longSize.cx && scrollOkay && scroll.nMax>client.right;
    std::cout<<"client="<<client.right<<" short="<<shortSize.cx<<" prefix="<<prefixSize.cx<<" long="<<longSize.cx<<" extent="<<extent<<" range="<<scroll.nMax<<" stored="<<stored<<"\n";
    std::cout<<(okay?"PASS":"FAIL")<<" actual resizable log: short message, long-name cause/status/error, stored full name and horizontal range\n";
    DestroyWindow(window);return okay?0:1;
}
