// Exercise the actual UI without loading/saving settings or starting a watcher.
#define wWinMain DvmUnusedWinMain
#include "../../source/app.cpp"
#undef wWinMain
#include "ui_capture.h"
#include <iostream>
#include <filesystem>

bool geometry(HWND window) {
    RECT client{},log{},empty{},footer{};GetClientRect(window,&client);
    const auto box=[&](HWND item,RECT& area) {GetWindowRect(item,&area);MapWindowPoints(nullptr,window,reinterpret_cast<POINT*>(&area),2);};
    box(messages,log);box(emptyText,empty);box(footerText,footer);
    bool okay=log.left>=0&&log.top>0&&log.right<=client.right&&log.bottom<footer.top&&log.bottom-log.top>=dvm::ui::px(80,windowDpi);
    for (HWND item : {brandText,introText,statusText,stateHint,folderHeading,folderText,startButton,stopButton,followBox,logHeading,logHint,footerText,GetDlgItem(window,PickFolder)}) {
        RECT bounds{};box(item,bounds);okay=okay&&bounds.left>=0&&bounds.top>=0&&bounds.right<=client.right&&bounds.bottom<=client.bottom&&bounds.right>bounds.left&&bounds.bottom>bounds.top;
    }
    return okay&&empty.bottom<=log.bottom;
}
// These synthetic layout renders need their requested canvas even when the
// CI virtual desktop is smaller. Delegate all product behavior to windowProc;
// enlarge only this test window's maximum tracking size after observing a clamp.
SIZE offscreenCanvas{};
LRESULT CALLBACK testWindowProc(HWND window,UINT message,WPARAM wparam,LPARAM lparam) {
    const auto result=windowProc(window,message,wparam,lparam);
    if (message==WM_GETMINMAXINFO && offscreenCanvas.cx>0) {
        auto info=reinterpret_cast<MINMAXINFO*>(lparam);
        info->ptMaxTrackSize.x=(std::max)(info->ptMaxTrackSize.x,offscreenCanvas.cx);
        info->ptMaxTrackSize.y=(std::max)(info->ptMaxTrackSize.y,offscreenCanvas.cy);
    }
    return result;
}
bool clientSize(HWND window,int width,int height) {
    const int requestedWidth=dvm::ui::px(width,windowDpi),requestedHeight=dvm::ui::px(height,windowDpi);
    RECT bounds{0,0,requestedWidth,requestedHeight};
    // A synthetic WM_DPICHANGED changes layout DPI, not the real HWND frame DPI.
    const auto nativeDpi=GetDpiForWindow(window);
    const auto style=static_cast<DWORD>(GetWindowLongPtrW(window,GWL_STYLE));
    const auto exstyle=static_cast<DWORD>(GetWindowLongPtrW(window,GWL_EXSTYLE));
    if (!AdjustWindowRectExForDpi(&bounds,style,GetMenu(window)!=nullptr,exstyle,nativeDpi?nativeDpi:96)) return false;
    const int outerWidth=bounds.right-bounds.left,outerHeight=bounds.bottom-bounds.top;
    offscreenCanvas={};
    bool resized=SetWindowPos(window,nullptr,0,0,outerWidth,outerHeight,SWP_NOMOVE|SWP_NOZORDER)!=FALSE;
    RECT actual{};GetClientRect(window,&actual);
    std::cout<<"layout canvas dpi="<<windowDpi<<" nativeDpi="<<GetDpiForWindow(window)
             <<" requested="<<requestedWidth<<"x"<<requestedHeight<<" defaultActual="<<actual.right<<"x"<<actual.bottom
             <<" desktopMaxTrack="<<GetSystemMetrics(SM_CXMAXTRACK)<<"x"<<GetSystemMetrics(SM_CYMAXTRACK)<<"\n";
    if (actual.right!=requestedWidth || actual.bottom!=requestedHeight) {
        offscreenCanvas={outerWidth,outerHeight};
        resized=SetWindowPos(window,nullptr,0,0,outerWidth,outerHeight,SWP_NOMOVE|SWP_NOZORDER)!=FALSE;
        GetClientRect(window,&actual);
        std::cout<<"test offscreen canvas actual="<<actual.right<<"x"<<actual.bottom<<"\n";
    }
    return resized && actual.right==requestedWidth && actual.bottom==requestedHeight;
}
int wmain(int argc,wchar_t** argv) {
    if (argc!=2 && argc!=3) return 2;std::filesystem::create_directories(argv[1]);const std::wstring root=argv[1];
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HANDLE context=INVALID_HANDLE_VALUE;ULONG_PTR cookie=0;
    if (argc==3) {ACTCTXW info{sizeof(info)};info.dwFlags=ACTCTX_FLAG_RESOURCE_NAME_VALID;info.lpSource=argv[2];info.lpResourceName=MAKEINTRESOURCEW(1);
        context=CreateActCtxW(&info);if (context==INVALID_HANDLE_VALUE||!ActivateActCtx(context,&cookie)) return 2;}
    INITCOMMONCONTROLSEX common{sizeof(common),ICC_STANDARD_CLASSES|ICC_LISTVIEW_CLASSES};InitCommonControlsEx(&common);
    selectedFolder=L"C:\\DVM UX test\\Downloads";followDownloads=true;
    WNDCLASSW kind{};kind.lpfnWndProc=testWindowProc;kind.hInstance=GetModuleHandleW(nullptr);kind.lpszClassName=L"DvmUxTest";RegisterClassW(&kind);
    HWND window=CreateWindowExW(0,kind.lpszClassName,L"DVM synthetic UX",WS_OVERLAPPEDWINDOW,0,0,940,840,nullptr,nullptr,kind.hInstance,nullptr);if (!window) return 2;
    int failed=0;const auto check=[&](const char* name,bool okay) {std::cout<<(okay?"PASS ":"FAIL ")<<name<<"\n";if (!okay) ++failed;};
    const bool normalSize=clientSize(window,900,800);check("main normal geometry and native render",normalSize&&geometry(window)&&captureNative(window,root+L"\\main-native-normal.bmp"));
    captureNative(window,root+L"\\main-desktop-capture.bmp",true);
    const bool minimumSize=clientSize(window,720,640);check("main minimum compact geometry and native render",minimumSize&&geometry(window)&&captureNative(window,root+L"\\main-native-min.bmp"));
    RECT scaled{0,0,dvm::ui::px(900,144)+24,dvm::ui::px(800,144)+60};
    SendMessageW(window,WM_DPICHANGED,MAKEWPARAM(144,144),reinterpret_cast<LPARAM>(&scaled));
    const bool scaledSize=clientSize(window,900,800),scaledDpi=windowDpi==144,scaledGeometry=geometry(window);
    const bool scaledRender=captureNative(window,root+L"\\main-native-144dpi.bmp");
    std::cout<<"simulated DPI predicates size="<<scaledSize<<" dpi="<<scaledDpi<<" geometry="<<scaledGeometry<<" render="<<scaledRender<<"\n";
    check("main simulated 150-percent DPI geometry and native render",scaledSize&&scaledDpi&&scaledGeometry&&scaledRender);
    RECT normal{0,0,924,860};SendMessageW(window,WM_DPICHANGED,MAKEWPARAM(96,96),reinterpret_cast<LPARAM>(&normal));clientSize(window,900,800);
    wchar_t actualPath[512]{};GetWindowTextW(folderText,actualPath,512);
    check("selected folder path retained in native readonly field",std::wstring(actualPath)==selectedFolder&&(GetWindowLongPtrW(folderText,GWL_STYLE)&ES_READONLY));
    controls(false);const bool idle=IsWindowEnabled(startButton)&&!IsWindowEnabled(stopButton)&&IsWindowEnabled(followBox);
    controls(true);const bool running=!IsWindowEnabled(startButton)&&IsWindowEnabled(stopButton)&&!IsWindowEnabled(followBox);controls(false);
    check("watch state enables existing actions without starting watcher",idle&&running&&!watcher.running());
    check("native keyboard tab order and access-key labels",GetNextDlgTabItem(window,nullptr,FALSE)==startButton&&(GetWindowLongPtrW(folderText,GWL_STYLE)&WS_TABSTOP)&&(GetWindowLongPtrW(messages,GWL_STYLE)&WS_TABSTOP));
    for (int i=0;i<205;++i) SendMessageW(window,ReportMessage,0,reinterpret_cast<LPARAM>(new std::wstring(L"검증 기록 "+std::to_wstring(i))));
    wchar_t first[256]{};SendMessageW(messages,LB_GETTEXT,0,reinterpret_cast<LPARAM>(first));
    check("existing 200-record limit and empty-state transition",SendMessageW(messages,LB_GETCOUNT,0,0)==200&&std::wstring(first)==L"검증 기록 5"&&!(GetWindowLongPtrW(emptyText,GWL_STYLE)&WS_VISIBLE));
    SendMessageW(window,ReportMessage,0,reinterpret_cast<LPARAM>(new std::wstring(L"읽기 전용 보호: 파일 보존 (permission_denied, 오류 5) · "+std::wstring(160,L'가')+L".txt")));
    check("resized long record keeps horizontal range and native render",SendMessageW(messages,LB_GETHORIZONTALEXTENT,0,0)>900&&captureNative(window,root+L"\\main-native-records.bmp"));
    DestroyWindow(window);if (cookie) DeactivateActCtx(0,cookie);if (context!=INVALID_HANDLE_VALUE) ReleaseActCtx(context);return failed?1:0;
}
