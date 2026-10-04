#include "watcher.h"
#include "review.h"
#include "identity.h"
#include <shobjidl.h>
#include <string>
#include <memory>
#include <shellapi.h>
#include <knownfolders.h>
#include <shlobj.h>

namespace {
constexpr UINT ReportMessage = WM_APP + 1;
constexpr UINT StartMessage = WM_APP + 2;
constexpr int PickFolder = 101, StartWatch = 102, StopWatch = 103, FollowFolder = 104;
dvm::Watcher watcher;
HWND folderText = nullptr, startButton = nullptr, stopButton = nullptr, statusText = nullptr, messages = nullptr;
HWND followBox = nullptr;
HFONT font = nullptr;
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
void controls(bool running) {
    EnableWindow(startButton, !running && !selectedFolder.empty());
    EnableWindow(stopButton, running);
    if (followBox) EnableWindow(followBox, !running);
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
        SetWindowTextW(statusText, L"감시 중입니다."); controls(true); EnableWindow(GetDlgItem(window, PickFolder), FALSE);
    } else MessageBoxW(window, error.c_str(), L"감시를 시작하지 못했습니다", MB_OK | MB_ICONWARNING);
}
HWND child(HWND parent, const wchar_t* kind, const wchar_t* text, DWORD style, int x, int y, int width, int height, int id = 0) {
    HWND item = CreateWindowExW(kind == std::wstring(L"EDIT") || kind == std::wstring(L"LISTBOX") ? WS_EX_CLIENTEDGE : 0,
        kind, text, WS_CHILD | WS_VISIBLE | style, x, y, width, height, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(item, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE); return item;
}
LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case WM_CREATE:
        font = CreateFontW(-16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Malgun Gothic");
        child(window, L"STATIC", L"감시할 폴더", 0, 20, 18, 570, 24);
        folderText = child(window, L"EDIT", selectedFolder.c_str(), ES_READONLY | ES_AUTOHSCROLL, 20, 48, 468, 29);
        child(window, L"BUTTON", L"폴더 선택", WS_TABSTOP | BS_PUSHBUTTON, 498, 48, 106, 29, PickFolder);
        followBox = child(window, L"BUTTON", L"Windows의 기본 다운로드 위치를 따릅니다", WS_TABSTOP | BS_AUTOCHECKBOX, 20, 90, 584, 26, FollowFolder);
        SendMessageW(followBox, BM_SETCHECK, followDownloads ? BST_CHECKED : BST_UNCHECKED, 0);
        child(window, L"STATIC", L"새 ‘파일 (1)’, ‘파일 (2)’를 원래 이름의 최신본으로 처리합니다.\n3초 동안 변경되지 않은 파일만 처리하며, 동시 후보는 보존합니다.", 0, 20, 132, 584, 46);
        startButton = child(window, L"BUTTON", L"감시 시작", WS_TABSTOP | BS_DEFPUSHBUTTON, 20, 191, 110, 32, StartWatch);
        stopButton = child(window, L"BUTTON", L"감시 중지", WS_TABSTOP | BS_PUSHBUTTON, 142, 191, 110, 32, StopWatch);
        statusText = child(window, L"STATIC", L"감시가 꺼져 있습니다.", 0, 272, 196, 332, 24);
        messages = child(window, L"LISTBOX", L"", WS_VSCROLL | WS_HSCROLL | LBS_NOINTEGRALHEIGHT, 20, 240, 584, 140);
        child(window, L"STATIC", L"내용이 달라진 이전 파일은 _history에 보관합니다.\n창을 닫으면 감시를 종료합니다.\n기존 파일의 직접 덮어쓰기는 보관할 수 없습니다.", 0, 20, 393, 584, 66);
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders", 0, KEY_NOTIFY, &shellFolders) == ERROR_SUCCESS) {
            locationChanged = CreateEventW(nullptr, FALSE, FALSE, nullptr);
            if (locationChanged && RegNotifyChangeKeyValue(shellFolders, FALSE, REG_NOTIFY_CHANGE_LAST_SET, locationChanged, TRUE) == ERROR_SUCCESS) SetTimer(window, 1, 1000, nullptr);
        }
        controls(false); return 0;
    case WM_COMMAND:
        switch (LOWORD(wparam)) {
        case PickFolder: if (!watcher.running()) chooseFolder(window); return 0;
        case StartWatch: beginWatch(window); return 0;
        case FollowFolder:
            followDownloads = SendMessageW(followBox, BM_GETCHECK, 0, 0) == BST_CHECKED;
            if (followDownloads) { selectedFolder = downloadsFolder(); SetWindowTextW(folderText, selectedFolder.c_str()); }
            saveFolder(); controls(false); return 0;
        case StopWatch:
            watchingRequested = false; watcher.stop(); SetWindowTextW(statusText, L"감시가 꺼져 있습니다."); controls(false);
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
        SendMessageW(messages, LB_SETTOPINDEX, static_cast<WPARAM>(index), 0);
        if (!watcher.running()) { controls(false); EnableWindow(GetDlgItem(window, PickFolder), TRUE); SetWindowTextW(statusText, L"감시가 꺼져 있습니다."); }
        return 0;
    }
    case WM_CLOSE:
        watcher.stop(); DestroyWindow(window); return 0;
    case WM_DESTROY:
        KillTimer(window, 1);
        if (shellFolders) { RegCloseKey(shellFolders); shellFolders = nullptr; }
        if (locationChanged) { CloseHandle(locationChanged); locationChanged = nullptr; }
        if (font) DeleteObject(font); PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    HANDLE single = CreateMutexW(nullptr, TRUE, L"Local\\Workspace.DownloadVersionManager.Watcher.v1");
    if (!single || GetLastError() == ERROR_ALREADY_EXISTS) {
        HWND existing = FindWindowW(L"Workspace.DvmWatcher", nullptr);
        if (existing) { ShowWindow(existing, SW_RESTORE); SetForegroundWindow(existing); }
        if (single) CloseHandle(single); return 0;
    }
    const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    int count = 0; auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    bool minimize = false;
    if (arguments) {
        for (int i = 1; i < count; ++i) { const std::wstring arg = arguments[i]; if (arg == L"--autostart") { autoStart = true; minimize = true; } if (arg == L"--first-run") autoStart = true; }
        LocalFree(arguments);
    }
    loadFolder();
    WNDCLASSW cls{}; cls.lpfnWndProc = windowProc; cls.hInstance = instance; cls.lpszClassName = L"Workspace.DvmWatcher";
    cls.hCursor = LoadCursorW(nullptr, IDC_ARROW); cls.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    RegisterClassW(&cls);
    const std::wstring title = L"DownloadVersionManager " DVM_VERSION;
    HWND window = CreateWindowExW(0, cls.lpszClassName, title.c_str(), WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 644, 532, nullptr, nullptr, instance, nullptr);
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
