#include "watcher.h"
#include "review.h"
#include "identity.h"
#include "ui.h"
#include <commctrl.h>
#include <algorithm>
#include <shobjidl.h>
#include <string>
#include <memory>
#include <map>
#include <shellapi.h>
#include <knownfolders.h>
#include <shlobj.h>

namespace {
constexpr UINT ReportMessage = WM_APP + 1;
constexpr UINT StartMessage = WM_APP + 2;
constexpr UINT TrayMessage = WM_APP + 3;
constexpr UINT TrayIconId = 1;
constexpr int ApplicationIconId = 101;
constexpr int TrayOpen = 105, TrayExit = 106;
UINT taskbarCreatedMessage = 0;
bool trayAvailable = false, shuttingDown = false;
#ifdef DVM_TESTING
auto trayNotify = Shell_NotifyIconW;
#endif
constexpr int PickFolder = 101, StartWatch = 102, StopWatch = 103, FollowFolder = 104;
dvm::Watcher watcher;
HWND folderText = nullptr, startButton = nullptr, stopButton = nullptr, statusText = nullptr, messages = nullptr;
HWND followBox = nullptr;
HFONT font = nullptr, titleFont = nullptr, sectionFont = nullptr;
UINT windowDpi = 96;
HWND brandText = nullptr, introText = nullptr, stateHint = nullptr, folderHeading = nullptr;
HWND logHeading = nullptr, logHint = nullptr, emptyText = nullptr, footerText = nullptr;

std::wstring selectedFolder;
bool followDownloads = true, autoStart = false, settingsUnsupported = false, watchingRequested = false;
HKEY shellFolders = nullptr;
HANDLE locationChanged = nullptr;
constexpr const wchar_t* SettingsKey = L"Software\\Workspace\\DownloadVersionManager\\Watcher";

std::wstring registryText(const wchar_t* key, const wchar_t* name) {
    wchar_t value[32768]{}; DWORD length = sizeof(value);
    return RegGetValueW(HKEY_CURRENT_USER, key, name, RRF_RT_REG_SZ, nullptr, value, &length) == ERROR_SUCCESS ? std::wstring(value) : L"";
}
DWORD registryNumber(const wchar_t* key, const wchar_t* name, DWORD fallback) {
    DWORD value = fallback, length = sizeof(value);
    return RegGetValueW(HKEY_CURRENT_USER, key, name, RRF_RT_REG_DWORD, nullptr, &value, &length) == ERROR_SUCCESS ? value : fallback;
}
std::wstring downloadsFolder() {
    PWSTR path = nullptr; std::wstring folder;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr, &path))) { folder = path; CoTaskMemFree(path); }
    return folder;
}

void addMessage(HWND window, const std::wstring& text) {
    auto message = std::make_unique<std::wstring>(text);
    if (PostMessageW(window, ReportMessage, 0, reinterpret_cast<LPARAM>(message.get()))) message.release();
}
HICON applicationIcon(int size) {
    // Own one icon per pixel size until process shutdown; LR_SHARED ignores size in its cache.
    struct Icons {
        std::map<int, HICON> bySize;
        ~Icons() { for (const auto& entry : bySize) DestroyIcon(entry.second); }
    };
    static Icons icons;
    const auto found = icons.bySize.find(size);
    if (found != icons.bySize.end()) return found->second;
    const auto icon = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(ApplicationIconId),
        IMAGE_ICON, size, size, 0));
    if (icon) { icons.bySize.emplace(size, icon); return icon; }
    return LoadIconW(nullptr, IDI_APPLICATION);
}
void setWindowIcons(HWND window) {
    SendMessageW(window, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(applicationIcon(GetSystemMetricsForDpi(SM_CXICON, windowDpi))));
    SendMessageW(window, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(applicationIcon(GetSystemMetricsForDpi(SM_CXSMICON, windowDpi))));
}
BOOL notifyTray(DWORD action, NOTIFYICONDATAW& icon) {
#ifdef DVM_TESTING
    return trayNotify(action, &icon);
#else
    return Shell_NotifyIconW(action, &icon);
#endif
}
NOTIFYICONDATAW trayIcon(HWND window) {
    NOTIFYICONDATAW icon{}; icon.cbSize = sizeof(icon); icon.hWnd = window; icon.uID = TrayIconId;
    icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; icon.uCallbackMessage = TrayMessage;
    icon.hIcon = applicationIcon(GetSystemMetricsForDpi(SM_CXSMICON, windowDpi));
    wcscpy_s(icon.szTip, L"DownloadVersionManager");
    return icon;
}
void restoreWindow(HWND window) {
    ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW); SetForegroundWindow(window);
}
bool ensureTray(HWND window) {
    if (!taskbarCreatedMessage) {
        addMessage(window, L"트레이 복구 알림을 등록하지 못했습니다. 창을 열어 둡니다.");
        return false;
    }
    auto icon = trayIcon(window);
    // Recheck the existing icon before hiding; Explorer may have removed it.
    if (trayAvailable && notifyTray(NIM_MODIFY, icon)) return true;
    trayAvailable = notifyTray(NIM_ADD, icon) != FALSE;
    if (!trayAvailable)
        addMessage(window, L"트레이 아이콘을 등록하지 못했습니다. 창을 열어 둡니다. 다시 닫으면 재시도합니다.");
    return trayAvailable;
}
void closeApp(HWND window) {
    if (shuttingDown) return;
    shuttingDown = true;
    watcher.stop(); // Join the worker before removing its report window.
    DestroyWindow(window);
}
void trayMenu(HWND window) {
    HMENU menu = CreatePopupMenu(); if (!menu) { restoreWindow(window); return; }
    AppendMenuW(menu, MF_STRING, TrayOpen, L"열기");
    AppendMenuW(menu, MF_STRING, TrayExit, L"종료");
    POINT point{}; GetCursorPos(&point); SetForegroundWindow(window);
    const auto command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, window, nullptr);
    DestroyMenu(menu);
    PostMessageW(window, WM_NULL, 0, 0);
    if (command) SendMessageW(window, WM_COMMAND, command, 0);
}
void controls(bool running) {
    EnableWindow(startButton, !running && !selectedFolder.empty());
    EnableWindow(stopButton, running);
    if (followBox) EnableWindow(followBox, !running);
    if (startButton) InvalidateRect(GetParent(startButton), nullptr, FALSE);
}
void loadFolder() {
    const auto schema = registryNumber(SettingsKey, L"SettingsVersion", 0);
    if (schema > 1) { settingsUnsupported = true; autoStart = false; return; }
    const auto key = schema == 1 ? SettingsKey : L"Software\\Workspace\\DownloadVersionManager\\Watcher\\InstallDefaults";
    followDownloads = registryNumber(key, L"FollowDownloads", 1) != 0;
    selectedFolder = followDownloads ? downloadsFolder() : registryText(key, L"Folder");
    while (selectedFolder.size() > 3 && selectedFolder.back() == L'\\') selectedFolder.pop_back();
}
void saveFolder() {
    if (settingsUnsupported) return;
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, SettingsKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        const DWORD schema = 1;
        const DWORD follow = followDownloads ? 1 : 0;
        RegSetValueExW(key, L"SettingsVersion", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&schema), sizeof(schema));
        RegSetValueExW(key, L"FollowDownloads", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&follow), sizeof(follow));
        RegSetValueExW(key, L"Folder", 0, REG_SZ, reinterpret_cast<const BYTE*>(selectedFolder.c_str()), static_cast<DWORD>((selectedFolder.size()+1)*sizeof(wchar_t)));
        RegCloseKey(key);
    }
}
void chooseFolder(HWND window) {
    IFileDialog* dialog = nullptr;
    if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return;
    DWORD options = 0; dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
    dialog->SetTitle(L"감시할 폴더 한 곳을 선택하세요");
    if (SUCCEEDED(dialog->Show(window))) {
        IShellItem* item = nullptr;
        if (SUCCEEDED(dialog->GetResult(&item))) {
            PWSTR path = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
                selectedFolder = path; CoTaskMemFree(path); followDownloads = false;
                SendMessageW(followBox, BM_SETCHECK, BST_UNCHECKED, 0);
                SetWindowTextW(folderText, selectedFolder.c_str()); saveFolder(); controls(watcher.running());
            }
            item->Release();
        }
    }
    dialog->Release();
}
void beginWatch(HWND window) {
    if (settingsUnsupported) { MessageBoxW(window, L"더 새로운 버전의 설정입니다. 설정을 보존했습니다. 최신 프로그램을 사용해 주세요.", L"감시를 시작하지 못했습니다", MB_OK | MB_ICONWARNING); return; }
    std::wstring error;
    if (!dvm::validateFolder(selectedFolder, error)) { MessageBoxW(window, error.c_str(), L"감시할 폴더를 확인해 주세요", MB_OK | MB_ICONWARNING); return; }
    if (registryText(SettingsKey, L"InitialReviewFolder") != selectedFolder) {
        ShowWindow(window, SW_RESTORE);
        if (!dvm::reviewExisting(window, selectedFolder, [window](const std::wstring& text) { addMessage(window, text); })) return;
        HKEY key = nullptr;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, SettingsKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
            RegSetValueExW(key, L"InitialReviewFolder", 0, REG_SZ, reinterpret_cast<const BYTE*>(selectedFolder.c_str()), static_cast<DWORD>((selectedFolder.size()+1)*sizeof(wchar_t))); RegCloseKey(key);
        }
    }
    saveFolder();
    if (watcher.start(selectedFolder, [window](const std::wstring& text) { addMessage(window, text); }, error)) {
        watchingRequested = true;
        SetWindowTextW(statusText, L"감시 중"); SetWindowTextW(stateHint,L"새 파일을 기다리고 있습니다."); controls(true); EnableWindow(GetDlgItem(window, PickFolder), FALSE);
    } else MessageBoxW(window, error.c_str(), L"감시를 시작하지 못했습니다", MB_OK | MB_ICONWARNING);
}
HWND child(HWND parent, const wchar_t* kind, const wchar_t* text, DWORD style, int id = 0) {
    HWND item = CreateWindowExW(kind == std::wstring(L"EDIT") || kind == std::wstring(L"LISTBOX") ? WS_EX_CLIENTEDGE : 0,
        kind, text, WS_CHILD | WS_VISIBLE | style, 0, 0, 1, 1, parent,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(item, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE); dvm::ui::theme(item); return item;
}
void fonts(HWND window) {
    if (font) DeleteObject(font); if (titleFont) DeleteObject(titleFont); if (sectionFont) DeleteObject(sectionFont);
    font=dvm::ui::makeFont(16,windowDpi);titleFont=dvm::ui::makeFont(26,windowDpi,FW_SEMIBOLD);sectionFont=dvm::ui::makeFont(18,windowDpi,FW_SEMIBOLD);
    EnumChildWindows(window, [](HWND item, LPARAM value)->BOOL { SendMessageW(item,WM_SETFONT,static_cast<WPARAM>(value),TRUE);return TRUE; },reinterpret_cast<LPARAM>(font));
    for (HWND item : {brandText,statusText,folderHeading,logHeading}) if (item) SendMessageW(item,WM_SETFONT,reinterpret_cast<WPARAM>(sectionFont),TRUE);
    if (brandText) SendMessageW(brandText,WM_SETFONT,reinterpret_cast<WPARAM>(titleFont),TRUE);
}
void logExtent() {
    if (!messages || !font) return;
    int extent=0;HDC dc=GetDC(messages);if (!dc) return;const auto old=SelectObject(dc,font);
    const auto count=SendMessageW(messages,LB_GETCOUNT,0,0);
    for (LRESULT i=0;i<count;++i) {
        const auto length=SendMessageW(messages,LB_GETTEXTLEN,static_cast<WPARAM>(i),0);if (length<0) continue;
        std::wstring value(static_cast<size_t>(length)+1,L'\0');SendMessageW(messages,LB_GETTEXT,static_cast<WPARAM>(i),reinterpret_cast<LPARAM>(value.data()));SIZE size{};
        if (GetTextExtentPoint32W(dc,value.c_str(),static_cast<int>(length),&size) && size.cx+ dvm::ui::px(12,windowDpi)>extent) extent=size.cx+dvm::ui::px(12,windowDpi);
    }
    SelectObject(dc,old);ReleaseDC(messages,dc);SendMessageW(messages,LB_SETHORIZONTALEXTENT,static_cast<WPARAM>(extent),0);
}
void layout(HWND window) {
    using dvm::ui::px;RECT client{};GetClientRect(window,&client);
    const int width=MulDiv(client.right,96,static_cast<int>(windowDpi)),height=MulDiv(client.bottom,96,static_cast<int>(windowDpi));
    const auto place=[&](HWND item,int x,int y,int w,int h) { if (item) MoveWindow(item,px(x,windowDpi),px(y,windowDpi),px(w,windowDpi),px(h,windowDpi),TRUE); };
    const bool compact=height<720;
    place(brandText,92,compact?15:27,width-120,36);place(introText,92,compact?53:67,width-120,26);
    place(statusText,48,compact?108:133,width-380,30);place(stateHint,48,compact?144:171,width-380,28);
    place(startButton,width-320,compact?115:146,148,44);place(stopButton,width-160,compact?115:146,112,44);
    place(folderHeading,48,compact?210:252,width-96,30);place(folderText,48,compact?248:295,width-260,36);
    place(GetDlgItem(window,PickFolder),width-196,compact?248:295,148,36);place(followBox,48,compact?292:344,width-96,30);
    place(logHeading,48,compact?364:428,width-96,30);place(logHint,48,compact?399:465,width-96,24);
    const int logTop=compact?430:502;
    place(messages,44,logTop,width-88,(height-126)-logTop);place(emptyText,68,logTop+12,width-136,54);
    place(footerText,28,height-90,width-56,80);
    InvalidateRect(window,nullptr,FALSE);
}
void paintCanvas(HWND window,HDC dc) {
    using namespace dvm::ui;RECT client{};GetClientRect(window,&client);fill(dc,client,Background);
    const int width=MulDiv(client.right,96,static_cast<int>(windowDpi)),height=MulDiv(client.bottom,96,static_cast<int>(windowDpi));
    const bool compact=height<720;
    for (const auto bounds : {RECT{24,compact?96:112,width-24,compact?180:220},RECT{24,compact?196:236,width-24,compact?332:396},RECT{24,compact?348:412,width-24,height-106}}) {
        RECT area{px(bounds.left,windowDpi),px(bounds.top,windowDpi),px(bounds.right,windowDpi),px(bounds.bottom,windowDpi)};card(dc,area,windowDpi);
    }
    RECT mark{px(28,windowDpi),px(compact?20:32,windowDpi),px(76,windowDpi),px(compact?68:80,windowDpi)};fill(dc,mark,Accent);
    const auto old=SelectObject(dc,sectionFont);SetBkMode(dc,TRANSPARENT);SetTextColor(dc,highContrast()?GetSysColor(COLOR_HIGHLIGHTTEXT):Surface);
    DrawTextW(dc,L"DV",-1,&mark,DT_CENTER|DT_VCENTER|DT_SINGLELINE);SelectObject(dc,old);
}
LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (taskbarCreatedMessage && message == taskbarCreatedMessage) {
        trayAvailable = false;
        if (!shuttingDown && !ensureTray(window)) restoreWindow(window);
        return 0;
    }
    switch (message) {
    case WM_CREATE:
        windowDpi=GetDpiForWindow(window);if (!windowDpi) windowDpi=96;setWindowIcons(window);fonts(window);
        brandText=child(window,L"STATIC",L"DownloadVersionManager",SS_LEFT);
        introText=child(window,L"STATIC",L"다운로드 파일을 정리하고 이전 버전을 보관합니다.  ·  " DVM_VERSION,SS_LEFT);
        statusText=child(window,L"STATIC",L"감시 대기 중",SS_LEFT);
        stateHint=child(window,L"STATIC",L"시작하면 새 파일을 감시합니다.",SS_LEFT);
        startButton=child(window,L"BUTTON",L"감시 시작(&S)",WS_TABSTOP|BS_OWNERDRAW,StartWatch);
        stopButton=child(window,L"BUTTON",L"감시 중지(&T)",WS_TABSTOP|BS_OWNERDRAW,StopWatch);
        folderHeading=child(window,L"STATIC",L"감시할 폴더",SS_LEFT);
        folderText=child(window,L"EDIT",selectedFolder.c_str(),WS_TABSTOP|ES_READONLY|ES_AUTOHSCROLL);
        child(window,L"BUTTON",L"폴더 선택(&F)",WS_TABSTOP|BS_OWNERDRAW,PickFolder);
        followBox=child(window,L"BUTTON",L"Windows의 기본 다운로드 위치를 따릅니다(&D)",WS_TABSTOP|BS_AUTOCHECKBOX,FollowFolder);
        SendMessageW(followBox,BM_SETCHECK,followDownloads?BST_CHECKED:BST_UNCHECKED,0);
        logHeading=child(window,L"STATIC",L"처리 기록",SS_LEFT);
        logHint=child(window,L"STATIC",L"3초 동안 변경되지 않은 새 파일을 처리합니다. 동시 후보는 보존합니다.",SS_LEFT);
        messages=child(window,L"LISTBOX",L"",WS_TABSTOP|WS_VSCROLL|WS_HSCROLL|LBS_NOINTEGRALHEIGHT);
        emptyText=child(window,L"STATIC",L"아직 처리 기록이 없습니다.\n감시를 시작하면 이곳에 결과가 표시됩니다.",SS_LEFT);
        footerText=child(window,L"STATIC",L"번호가 붙은 새 파일을 정리하고, 이전 내용은 수정 시각을 이름에 붙여 _history에 보관합니다.\n직접 덮어쓴 이전 내용은 보관할 수 없습니다. 창을 닫아도 감시는 유지됩니다. 종료하려면 트레이의 종료를 선택하세요.",SS_LEFT);
        fonts(window);layout(window);
        if (RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders",0,KEY_NOTIFY,&shellFolders)==ERROR_SUCCESS) {
            locationChanged=CreateEventW(nullptr,FALSE,FALSE,nullptr);
            if (locationChanged && RegNotifyChangeKeyValue(shellFolders,FALSE,REG_NOTIFY_CHANGE_LAST_SET,locationChanged,TRUE)==ERROR_SUCCESS) SetTimer(window,1,1000,nullptr);
        }
        taskbarCreatedMessage = RegisterWindowMessageW(L"TaskbarCreated");
        ensureTray(window);
        controls(false);return 0;
    case WM_GETMINMAXINFO: {
        RECT bounds{0,0,dvm::ui::px(720,windowDpi),dvm::ui::px(640,windowDpi)};
        AdjustWindowRectExForDpi(&bounds,static_cast<DWORD>(GetWindowLongPtrW(window,GWL_STYLE)),FALSE,0,windowDpi);
        auto info=reinterpret_cast<MINMAXINFO*>(lparam);info->ptMinTrackSize={bounds.right-bounds.left,bounds.bottom-bounds.top};
        MONITORINFO monitor{sizeof(monitor)};if (GetMonitorInfoW(MonitorFromWindow(window,MONITOR_DEFAULTTONEAREST),&monitor)) {
            info->ptMinTrackSize.x=(std::min)(info->ptMinTrackSize.x,monitor.rcWork.right-monitor.rcWork.left);
            info->ptMinTrackSize.y=(std::min)(info->ptMinTrackSize.y,monitor.rcWork.bottom-monitor.rcWork.top);
        }return 0;
    }
    case WM_SIZE: if (wparam!=SIZE_MINIMIZED) layout(window);return 0;
    case WM_DPICHANGED: {
        windowDpi=HIWORD(wparam);setWindowIcons(window);
        if (trayAvailable && !ensureTray(window)) restoreWindow(window);
        fonts(window);auto bounds=reinterpret_cast<RECT*>(lparam);
        SetWindowPos(window,nullptr,bounds->left,bounds->top,bounds->right-bounds->left,bounds->bottom-bounds->top,SWP_NOZORDER|SWP_NOACTIVATE);layout(window);logExtent();return 0;
    }
    case WM_ERASEBKGND:return 1;
    case WM_PAINT: {
        PAINTSTRUCT paint{};HDC dc=BeginPaint(window,&paint);RECT area{};GetClientRect(window,&area);
        HDC buffer=CreateCompatibleDC(dc);HBITMAP bitmap=CreateCompatibleBitmap(dc,area.right,area.bottom);auto old=SelectObject(buffer,bitmap);
        paintCanvas(window,buffer);BitBlt(dc,0,0,area.right,area.bottom,buffer,0,0,SRCCOPY);SelectObject(buffer,old);DeleteObject(bitmap);DeleteDC(buffer);EndPaint(window,&paint);return 0;
    }
    case WM_PRINTCLIENT:paintCanvas(window,reinterpret_cast<HDC>(wparam));return 0;
    case WM_DRAWITEM: {
        const auto item=reinterpret_cast<DRAWITEMSTRUCT*>(lparam);if (item && item->CtlType==ODT_BUTTON) { dvm::ui::button(*item,font,windowDpi,item->CtlID==StartWatch);return TRUE; }break;
    }
    case WM_CTLCOLORSTATIC:case WM_CTLCOLOREDIT:case WM_CTLCOLORLISTBOX: {
        HDC dc=reinterpret_cast<HDC>(wparam);HWND item=reinterpret_cast<HWND>(lparam);SetBkMode(dc,TRANSPARENT);
        SetTextColor(dc,dvm::ui::color(item==introText||item==stateHint||item==logHint||item==emptyText||item==footerText?dvm::ui::Muted:dvm::ui::Text));
        const bool background=item==brandText||item==introText||item==footerText;SetBkColor(dc,dvm::ui::color(background?dvm::ui::Background:dvm::ui::Surface));
        return reinterpret_cast<LRESULT>(background?dvm::ui::backgroundBrush():dvm::ui::surfaceBrush());
    }
    case WM_COMMAND:
        switch (LOWORD(wparam)) {
        case TrayOpen: restoreWindow(window); return 0;
        case TrayExit: closeApp(window); return 0;
        case PickFolder: if (!watcher.running()) chooseFolder(window); return 0;
        case StartWatch: beginWatch(window); return 0;
        case FollowFolder:
            followDownloads = SendMessageW(followBox, BM_GETCHECK, 0, 0) == BST_CHECKED;
            if (followDownloads) { selectedFolder = downloadsFolder(); SetWindowTextW(folderText, selectedFolder.c_str()); }
            saveFolder(); controls(false); return 0;
        case StopWatch:
            watchingRequested = false; watcher.stop(); SetWindowTextW(statusText, L"감시 대기 중"); SetWindowTextW(stateHint,L"시작하면 새 파일을 감시합니다."); controls(false);
            EnableWindow(GetDlgItem(window, PickFolder), TRUE); return 0;
        } break;
    case StartMessage: beginWatch(window); return 0;
    case WM_TIMER:
        if (wparam == 1 && locationChanged && WaitForSingleObject(locationChanged, 0) == WAIT_OBJECT_0) {
            RegNotifyChangeKeyValue(shellFolders, FALSE, REG_NOTIFY_CHANGE_LAST_SET, locationChanged, TRUE);
            if (followDownloads) {
                const auto current = downloadsFolder();
                if (!current.empty() && current != selectedFolder) {
                    const bool restart = watchingRequested; watcher.stop(); selectedFolder = current;
                    SetWindowTextW(folderText, selectedFolder.c_str()); saveFolder();
                    addMessage(window, L"Windows 다운로드 위치 변경을 적용했습니다."); controls(false);
                    EnableWindow(GetDlgItem(window, PickFolder), TRUE);
                    if (restart) beginWatch(window);
                }
            }
        }
        return 0;
    case ReportMessage: {
        std::unique_ptr<std::wstring> text(reinterpret_cast<std::wstring*>(lparam));
        if (SendMessageW(messages, LB_GETCOUNT, 0, 0) >= 200) SendMessageW(messages, LB_DELETESTRING, 0, 0);
        const auto index = SendMessageW(messages, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(text->c_str()));
        ShowWindow(emptyText,SW_HIDE);
        const auto heading=L"처리 기록  ·  "+std::to_wstring(SendMessageW(messages,LB_GETCOUNT,0,0))+L"건";SetWindowTextW(logHeading,heading.c_str());
        // WS_HSCROLL needs a measured extent so long filenames remain reachable.
        if (HDC dc = GetDC(messages)) {
            const auto previous = SelectObject(dc, font); SIZE width{};
            if (GetTextExtentPoint32W(dc, text->c_str(), static_cast<int>(text->size()), &width) &&
                width.cx + 8 > SendMessageW(messages, LB_GETHORIZONTALEXTENT, 0, 0))
                SendMessageW(messages, LB_SETHORIZONTALEXTENT, static_cast<WPARAM>(width.cx + 8), 0);
            SelectObject(dc, previous); ReleaseDC(messages, dc);
        }
        SendMessageW(messages, LB_SETTOPINDEX, static_cast<WPARAM>(index), 0);
        if (!watcher.running()) { controls(false); EnableWindow(GetDlgItem(window, PickFolder), TRUE); SetWindowTextW(statusText, L"감시 대기 중"); SetWindowTextW(stateHint,L"시작하면 새 파일을 감시합니다."); }
        return 0;
    }
    case TrayMessage:
        if (wparam == TrayIconId) {
            if (lparam == WM_LBUTTONDBLCLK) restoreWindow(window);
            else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) trayMenu(window);
        }
        return 0;
    case WM_QUERYENDSESSION: return TRUE;
    case WM_ENDSESSION:
        if (wparam) closeApp(window);
        return 0;
    case WM_CLOSE:
        if (ensureTray(window)) ShowWindow(window, SW_HIDE);
        else restoreWindow(window);
        return 0;
    case WM_DESTROY: {
        shuttingDown = true; watcher.stop();
        MSG pending{};
        while (PeekMessageW(&pending, window, ReportMessage, ReportMessage, PM_REMOVE))
            delete reinterpret_cast<std::wstring*>(pending.lParam);
        auto icon = trayIcon(window); notifyTray(NIM_DELETE, icon); trayAvailable = false;
        KillTimer(window, 1);
        if (shellFolders) { RegCloseKey(shellFolders); shellFolders = nullptr; }
        if (locationChanged) { CloseHandle(locationChanged); locationChanged = nullptr; }
        if (font) DeleteObject(font); if (titleFont) DeleteObject(titleFont); if (sectionFont) DeleteObject(sectionFont);
        font=nullptr;titleFont=nullptr;sectionFont=nullptr;PostQuitMessage(0);return 0;
    }
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    HANDLE single = CreateMutexW(nullptr, TRUE, L"Local\\Workspace.DownloadVersionManager.Watcher.v1");
    if (!single || GetLastError() == ERROR_ALREADY_EXISTS) {
        HWND existing = FindWindowW(L"Workspace.DvmWatcher", nullptr);
        if (existing) restoreWindow(existing);
        if (single) CloseHandle(single); return 0;
    }
    const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    int count = 0; auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    bool minimize = false;
    if (arguments) {
        for (int i = 1; i < count; ++i) { const std::wstring arg = arguments[i]; if (arg == L"--autostart") { autoStart = true; minimize = true; } if (arg == L"--first-run") autoStart = true; }
        LocalFree(arguments);
    }
    INITCOMMONCONTROLSEX common{sizeof(common),ICC_STANDARD_CLASSES|ICC_LISTVIEW_CLASSES};InitCommonControlsEx(&common);
    loadFolder();
    WNDCLASSW cls{}; cls.lpfnWndProc = windowProc; cls.hInstance = instance; cls.lpszClassName = L"Workspace.DvmWatcher";
    cls.hIcon = applicationIcon(GetSystemMetrics(SM_CXICON));
    cls.hCursor = LoadCursorW(nullptr, IDC_ARROW); cls.hbrBackground = dvm::ui::backgroundBrush();
    RegisterClassW(&cls);
    const std::wstring title = L"DownloadVersionManager " DVM_VERSION;
    const auto dpi=GetDpiForSystem();RECT bounds{0,0,dvm::ui::px(900,dpi),dvm::ui::px(800,dpi)};
    AdjustWindowRectExForDpi(&bounds,WS_OVERLAPPEDWINDOW,FALSE,0,dpi);
    RECT work{};SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0);
    const int width=(std::min)(static_cast<int>(bounds.right-bounds.left),static_cast<int>(work.right-work.left)-dvm::ui::px(24,dpi));
    const int height=(std::min)(static_cast<int>(bounds.bottom-bounds.top),static_cast<int>(work.bottom-work.top)-dvm::ui::px(24,dpi));
    HWND window = CreateWindowExW(0,cls.lpszClassName,title.c_str(),WS_OVERLAPPEDWINDOW|WS_CLIPCHILDREN,
        work.left+(work.right-work.left-width)/2,work.top+(work.bottom-work.top-height)/2,width,height,nullptr,nullptr,instance,nullptr);
    if (window) {
        ShowWindow(window, minimize ? SW_SHOWMINIMIZED : show);
        if (autoStart) PostMessageW(window, StartMessage, 0, 0);
        MSG message{};
        while (GetMessageW(&message, nullptr, 0, 0) > 0) { if (!IsDialogMessageW(window, &message)) { TranslateMessage(&message); DispatchMessageW(&message); } }
        while (PeekMessageW(&message, nullptr, ReportMessage, ReportMessage, PM_REMOVE)) delete reinterpret_cast<std::wstring*>(message.lParam);
    }
    if (SUCCEEDED(com)) CoUninitialize();
    ReleaseMutex(single); CloseHandle(single); return window ? 0 : 1;
}
