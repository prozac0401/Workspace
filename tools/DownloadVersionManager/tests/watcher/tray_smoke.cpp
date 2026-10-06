// Focused lifetime checks use the real app HWND and watcher with a deterministic
// Shell notification mock. No DVM settings or installed application are touched.
#define wWinMain DvmUnusedWinMain
#include "../../source/app.cpp"
#undef wWinMain
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
namespace fs = std::filesystem;
constexpr wchar_t TestClass[] = L"DvmTrayLifetimeTest";
constexpr UINT_PTR MenuCancelTimer = 2;
struct ShellMock {
    bool present = false, allowAdd = true, allowModify = true, duplicate = false;
    unsigned adds = 0, modifies = 0, deletes = 0, versions = 0;
    HWND owner = nullptr;
    NOTIFYICONDATAW last{};
} shell;
BOOL WINAPI mockNotify(DWORD action, PNOTIFYICONDATAW icon) {
    shell.last = *icon;
    if (action == NIM_ADD) {
        ++shell.adds;
        if (!shell.allowAdd) return FALSE;
        if (shell.present) { shell.duplicate = true; return FALSE; }
        shell.present = true; shell.owner = icon->hWnd; return TRUE;
    }
    if (action == NIM_MODIFY) {
        ++shell.modifies;
        return shell.allowModify && shell.present && shell.owner == icon->hWnd ? TRUE : FALSE;
    }
    if (action == NIM_DELETE) {
        ++shell.deletes; shell.present = false; shell.owner = nullptr; return TRUE;
    }
    if (action == NIM_SETVERSION) ++shell.versions;
    return FALSE;
}
struct RealShellProof {
    unsigned adds = 0, modifies = 0, deletes = 0;
    BOOL added = FALSE, modified = FALSE, deleted = FALSE;
} realShell;
BOOL WINAPI recordRealNotify(DWORD action, PNOTIFYICONDATAW icon) {
    const BOOL result = Shell_NotifyIconW(action, icon);
    if (action == NIM_ADD) { ++realShell.adds; realShell.added = result; }
    if (action == NIM_MODIFY) { ++realShell.modifies; realShell.modified = result; }
    if (action == NIM_DELETE) { ++realShell.deletes; realShell.deleted = result; }
    return result;
}
bool menuSeen = false, menuCorrect = false; HMENU observedMenu = nullptr;
LRESULT CALLBACK testWindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_INITMENUPOPUP) {
        const auto menu = reinterpret_cast<HMENU>(wparam);
        wchar_t open[32]{}, exit[32]{};
        GetMenuStringW(menu, 0, open, 32, MF_BYPOSITION);
        GetMenuStringW(menu, 1, exit, 32, MF_BYPOSITION);
        menuSeen = true; observedMenu = menu;
        menuCorrect = GetMenuItemCount(menu) == 2 && GetMenuItemID(menu, 0) == TrayOpen &&
            GetMenuItemID(menu, 1) == TrayExit && std::wstring(open) == L"열기" && std::wstring(exit) == L"종료";
        PostMessageW(window, WM_CANCELMODE, 0, 0);
    }
    if (message == WM_TIMER && wparam == MenuCancelTimer) {
        KillTimer(window, MenuCancelTimer); EndMenu(); return 0;
    }
    return windowProc(window, message, wparam, lparam);
}
void pump() {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        if (message.message == WM_QUIT) continue;
        if (message.message == ReportMessage && !IsWindow(message.hwnd)) {
            delete reinterpret_cast<std::wstring*>(message.lParam); continue;
        }
        TranslateMessage(&message); DispatchMessageW(&message);
    }
}
void waitFor(DWORD milliseconds) {
    const auto until = GetTickCount64() + milliseconds;
    do { pump(); Sleep(20); } while (GetTickCount64() < until);
    pump();
}
std::wstring windowText(HWND item) {
    std::wstring text(static_cast<size_t>(GetWindowTextLengthW(item)) + 1, L'\0');
    GetWindowTextW(item, text.data(), static_cast<int>(text.size()));
    text.resize(wcslen(text.c_str())); return text;
}
std::vector<std::wstring> records() {
    std::vector<std::wstring> result;
    const auto count = SendMessageW(messages, LB_GETCOUNT, 0, 0);
    for (LRESULT row = 0; row < count; ++row) {
        const auto length = SendMessageW(messages, LB_GETTEXTLEN, static_cast<WPARAM>(row), 0);
        if (length < 0) continue;
        std::wstring value(static_cast<size_t>(length) + 1, L'\0');
        SendMessageW(messages, LB_GETTEXT, static_cast<WPARAM>(row), reinterpret_cast<LPARAM>(value.data()));
        value.resize(static_cast<size_t>(length)); result.push_back(value);
    }
    return result;
}
bool hasRecord(const std::wstring& part) {
    for (const auto& row : records()) if (row.find(part) != std::wstring::npos) return true;
    return false;
}
void writeFixture(const fs::path& path, const std::string& text) {
    std::ofstream output(path, std::ios::binary); output << text;
    if (!output) throw std::runtime_error("fixture write");
}
std::string readFixture(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(input), {});
}
DWORD handleCount() { DWORD count = 0; GetProcessHandleCount(GetCurrentProcess(), &count); return count; }
unsigned childCount(HWND window) {
    unsigned count = 0;
    EnumChildWindows(window, [](HWND, LPARAM value)->BOOL { ++*reinterpret_cast<unsigned*>(value); return TRUE; }, reinterpret_cast<LPARAM>(&count));
    return count;
}
unsigned appWindowCount() {
    unsigned count = 0;
    EnumWindows([](HWND window, LPARAM value)->BOOL {
        wchar_t name[64]{}; GetClassNameW(window, name, 64); DWORD process = 0; GetWindowThreadProcessId(window, &process);
        if (process == GetCurrentProcessId() && std::wstring(name) == TestClass) ++*reinterpret_cast<unsigned*>(value);
        return TRUE;
    }, reinterpret_cast<LPARAM>(&count));
    return count;
}
HWND createWindow() {
    shuttingDown = false; trayAvailable = false;
    HWND window = CreateWindowExW(0, TestClass, L"DVM isolated tray lifetime test", WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        40, 40, 940, 840, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!window) throw std::runtime_error("synthetic window create");
    ShowWindow(window, SW_SHOW); pump(); return window;
}
void startFixtureWatcher(HWND window) {
    std::wstring error;
    if (!watcher.start(selectedFolder, [window](const std::wstring& row) { addMessage(window, row); }, error))
        throw std::runtime_error("fixture watcher start");
    watchingRequested = true; controls(true); EnableWindow(GetDlgItem(window, PickFolder), FALSE);
    SetWindowTextW(statusText, L"감시 중"); SetWindowTextW(stateHint, L"새 파일을 기다리고 있습니다.");
}
bool cleaned(HWND window) {
    return !IsWindow(window) && !watcher.running() && shuttingDown && !trayAvailable &&
        shellFolders == nullptr && locationChanged == nullptr && font == nullptr && titleFont == nullptr && sectionFont == nullptr;
}
bool inspectMenu(HWND window, LPARAM notification) {
    menuSeen = false; menuCorrect = false; observedMenu = nullptr;
    SetTimer(window, MenuCancelTimer, 500, nullptr);
    SendMessageW(window, TrayMessage, TrayIconId, notification);
    KillTimer(window, MenuCancelTimer); pump();
    return menuSeen && menuCorrect && observedMenu && !IsMenu(observedMenu);
}
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) { std::cerr << "Usage: tray-smoke.exe <fresh-fixture-directory>\n"; return 2; }
    const auto fixture = fs::absolute(argv[1]);
    if (fs::exists(fixture)) { std::cerr << "Use a fresh fixture directory.\n"; return 2; }
    fs::create_directories(fixture / L"watched");
    const auto folder = fixture / L"watched";
    selectedFolder = folder.wstring(); followDownloads = false; trayNotify = mockNotify;
    INITCOMMONCONTROLSEX common{sizeof(common), ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES}; InitCommonControlsEx(&common);
    WNDCLASSW kind{}; kind.lpfnWndProc = testWindowProc; kind.hInstance = GetModuleHandleW(nullptr); kind.lpszClassName = TestClass;
    RegisterClassW(&kind);
    unsigned passed = 0, failed = 0; std::vector<std::string> outcomes;
    const auto check = [&](const char* name, bool okay) {
        std::cout << (okay ? "PASS " : "FAIL ") << name << '\n'; okay ? ++passed : ++failed;
        outcomes.push_back(std::string("{\"name\":\"") + name + "\",\"passed\":" + (okay ? "true" : "false") + "}");
    };
    HWND window = nullptr;
    try {
        writeFixture(folder / L"hidden.bin", "old-hidden-content");
        window = createWindow();
        check("initial mock tray registration and classic callback contract", trayAvailable && shell.present && shell.adds == 1 &&
            shell.last.hWnd == window && shell.last.uID == TrayIconId && shell.last.uCallbackMessage == TrayMessage &&
            shell.last.uFlags == (NIF_MESSAGE | NIF_ICON | NIF_TIP) && shell.last.hIcon &&
            std::wstring(shell.last.szTip) == L"DownloadVersionManager" && shell.versions == 0 && taskbarCreatedMessage != 0);
        // SetForegroundWindow initializes asynchronous Windows foreground resources.
        // Settle those once so the following repeat check measures retained growth.
        restoreWindow(window); waitFor(1000);
        startFixtureWatcher(window);
        SendMessageW(window, ReportMessage, 0, reinterpret_cast<LPARAM>(new std::wstring(L"retained test log")));
        const auto originalLog = records(); const auto state = windowText(statusText), folderValue = windowText(folderText);
        // Windows maps both the title-bar X and Alt+F4 to SC_CLOSE/WM_CLOSE.
        SendMessageW(window, WM_SYSCOMMAND, SC_CLOSE, 0); pump();
        check("SC_CLOSE title-X and Alt-F4 route hides while watcher remains active", IsWindow(window) && !IsWindowVisible(window) &&
            watcher.running() && watchingRequested && selectedFolder == folder.wstring() && shell.present && !shuttingDown);
        SendMessageW(window, WM_COMMAND, TrayOpen, 0); waitFor(300);
        const auto children = childCount(window); const auto handles = handleCount();
        const auto gdi = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS), users = GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS);
        bool repeated = true; DWORD firstHandles = 0, firstGdi = 0, firstUsers = 0, lastHandles = 0, lastGdi = 0, lastUsers = 0;
        for (unsigned cycle = 0; cycle < 12; ++cycle) {
            SendMessageW(window, WM_CLOSE, 0, 0);
            repeated = repeated && !IsWindowVisible(window) && watcher.running();
            if (cycle % 2) SendMessageW(window, WM_COMMAND, TrayOpen, 0);
            else SendMessageW(window, TrayMessage, TrayIconId, WM_LBUTTONDBLCLK);
            pump(); repeated = repeated && IsWindowVisible(window) && !IsIconic(window) && watcher.running();
            const auto currentHandles = handleCount(), currentGdi = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS), currentUsers = GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS);
            auto& peakHandles = cycle < 6 ? firstHandles : lastHandles; auto& peakGdi = cycle < 6 ? firstGdi : lastGdi; auto& peakUsers = cycle < 6 ? firstUsers : lastUsers;
            peakHandles = (std::max)(peakHandles, currentHandles); peakGdi = (std::max)(peakGdi, currentGdi); peakUsers = (std::max)(peakUsers, currentUsers);
        }
        std::cout << "RESOURCE settled repeat handles=" << handles << "->" << handleCount() << " GDI=" << gdi << "->" << GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) << " USER=" << users << "->" << GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS) << "; first-six/last-six peak handles=" << firstHandles << "/" << lastHandles << " GDI=" << firstGdi << "/" << lastGdi << " USER=" << firstUsers << "/" << lastUsers << '\n';
        check("repeat hide and open keeps one HWND tray registration resources and UI state", repeated && appWindowCount() == 1 &&
            childCount(window) == children && shell.adds == 1 && shell.present && !shell.duplicate && records() == originalLog &&
            windowText(statusText) == state && windowText(folderText) == folderValue && lastHandles <= firstHandles &&
            lastGdi <= firstGdi && lastUsers <= firstUsers);
        SendMessageW(window, WM_CLOSE, 0, 0);
        writeFixture(folder / L"hidden (1).bin", "new-hidden-content");
        const auto deadline = GetTickCount64() + 6000;
        while ((fs::exists(folder / L"hidden (1).bin") || !hasRecord(L"hidden (1).bin")) && GetTickCount64() < deadline) waitFor(50);
        pump(); bool archived = false;
        if (fs::exists(folder / L"_history")) for (const auto& item : fs::directory_iterator(folder / L"_history"))
            if (item.path().filename().wstring().rfind(L"hidden_", 0) == 0 && readFixture(item.path()) == "old-hidden-content") archived = true;
        check("hidden real folder notification replaces incoming archives old bytes and records result", !IsWindowVisible(window) &&
            watcher.running() && !fs::exists(folder / L"hidden (1).bin") && readFixture(folder / L"hidden.bin") == "new-hidden-content" &&
            archived && hasRecord(L"hidden (1).bin") && hasRecord(L"retained test log"));
        SendMessageW(window, TrayMessage, TrayIconId, WM_LBUTTONDBLCLK); pump();
        check("double-click restores same running window and full retained log", IsWindowVisible(window) && !IsIconic(window) &&
            watcher.running() && appWindowCount() == 1 && hasRecord(L"hidden (1).bin") && hasRecord(L"retained test log"));
        const bool rightMenu = inspectMenu(window, WM_RBUTTONUP), contextMenu = inspectMenu(window, WM_CONTEXTMENU);
        check("right-click and context callback show only Open and Exit and release menus", rightMenu && contextMenu &&
            watcher.running());
        ShowWindow(window, SW_MINIMIZE); pump();
        const bool minimized = IsWindowVisible(window) && IsIconic(window) && watcher.running();
        SendMessageW(window, WM_CLOSE, 0, 0); const bool hiddenMinimized = !IsWindowVisible(window) && watcher.running();
        SendMessageW(window, WM_COMMAND, TrayOpen, 0); pump();
        check("minimize remains ordinary minimize and tray Open restores minimized or hidden window", minimized && hiddenMinimized &&
            IsWindowVisible(window) && !IsIconic(window) && watcher.running());
        ShowWindow(window, SW_MAXIMIZE); pump(); const bool maximized = IsZoomed(window) != FALSE;
        SendMessageW(window, WM_CLOSE, 0, 0); SendMessageW(window, WM_COMMAND, TrayOpen, 0); pump();
        check("maximized window remains maximized across hide and Open", maximized && IsWindowVisible(window) && IsZoomed(window) && watcher.running());
        ShowWindow(window, SW_RESTORE); pump();
        SendMessageW(window, WM_CLOSE, 0, 0); SendMessageW(window, WM_COMMAND, StopWatch, 0); pump();
        writeFixture(folder / L"stopped.bin", "old-stopped"); writeFixture(folder / L"stopped (1).bin", "new-stopped");
        waitFor(3400);
        check("hidden stopped watcher does not process new file events", !IsWindowVisible(window) && !watcher.running() && !watchingRequested &&
            readFixture(folder / L"stopped.bin") == "old-stopped" && readFixture(folder / L"stopped (1).bin") == "new-stopped");
        const auto idleState = windowText(statusText); const auto idleLog = records(); const auto idleHandles = handleCount();
        SendMessageW(window, WM_COMMAND, TrayOpen, 0); SendMessageW(window, WM_CLOSE, 0, 0);
        SendMessageW(window, TrayMessage, TrayIconId, WM_LBUTTONDBLCLK); pump();
        check("stopped close and reopen retains stopped state controls path and log", IsWindowVisible(window) && !watcher.running() &&
            !watchingRequested && IsWindowEnabled(startButton) && !IsWindowEnabled(stopButton) && records() == idleLog &&
            windowText(statusText) == idleState && selectedFolder == folder.wstring() && handleCount() <= idleHandles);
        const auto exitIdleHandles = handleCount(); startFixtureWatcher(window);
        shell.present = false; const auto staleAdds = shell.adds;
        SendMessageW(window, WM_CLOSE, 0, 0);
        check("lost icon modify failure retries add before hiding", !IsWindowVisible(window) && watcher.running() && trayAvailable &&
            shell.present && shell.adds == staleAdds + 1 && !shell.duplicate);
        shell.present = false; shell.allowAdd = false;
        SendMessageW(window, WM_CLOSE, 0, 0); pump();
        check("tray add failure keeps recovery window visible and preserves running state", IsWindowVisible(window) && !trayAvailable &&
            watcher.running() && hasRecord(L"트레이 아이콘을 등록하지 못했습니다") && selectedFolder == folder.wstring());
        shell.allowAdd = true; SendMessageW(window, WM_CLOSE, 0, 0);
        check("next close retries registration and hides without restarting watcher", !IsWindowVisible(window) && trayAvailable && shell.present && watcher.running());
        const auto taskbarMessage = taskbarCreatedMessage; taskbarCreatedMessage = 0;
        SendMessageW(window, WM_CLOSE, 0, 0); pump();
        check("missing Explorer restart message registration keeps recovery window visible", IsWindowVisible(window) && watcher.running());
        taskbarCreatedMessage = taskbarMessage; SendMessageW(window, WM_CLOSE, 0, 0);
        shell.present = false; const auto restartAdds = shell.adds;
        SendMessageW(window, taskbarCreatedMessage, 0, 0);
        check("mock Explorer restart re-registers one icon while retaining hidden watcher", !IsWindowVisible(window) && watcher.running() &&
            trayAvailable && shell.present && shell.adds == restartAdds + 1 && !shell.duplicate);
        shell.present = false; shell.allowAdd = false;
        SendMessageW(window, taskbarCreatedMessage, 0, 0); pump();
        check("mock Explorer restart registration failure restores recovery window", IsWindowVisible(window) && watcher.running() && !trayAvailable);
        shell.allowAdd = true; SendMessageW(window, WM_CLOSE, 0, 0);
        const auto query = SendMessageW(window, WM_QUERYENDSESSION, 0, ENDSESSION_LOGOFF);
        SendMessageW(window, WM_ENDSESSION, FALSE, ENDSESSION_LOGOFF);
        check("query and canceled Windows session end preserve hidden watcher", query == TRUE && IsWindow(window) &&
            !IsWindowVisible(window) && watcher.running() && !shuttingDown);
        writeFixture(folder / L"exit.bin", "old-exit"); writeFixture(folder / L"exit (1).bin", "new-exit");
        const auto exitDeletes = shell.deletes;
        addMessage(window, L"queued report before explicit Exit");
        const auto beforeExit = GetTickCount64(); SendMessageW(window, WM_COMMAND, TrayExit, 0);
        MSG pending{}; const bool reportDrained = !PeekMessageW(&pending, window, ReportMessage, ReportMessage, PM_NOREMOVE);
        pump();
        std::cout << "RESOURCE final idle-before-restart=" << exitIdleHandles << " after-exit=" << handleCount() << " queued-report-drained=" << reportDrained << '\n';
        check("explicit tray Exit joins watcher deletes icon closes native resources and preserves pending files", cleaned(window) && reportDrained &&
            !shell.present && shell.deletes == exitDeletes + 1 && appWindowCount() == 0 && handleCount() <= exitIdleHandles &&
            GetTickCount64() - beforeExit < 3000 && readFixture(folder / L"exit.bin") == "old-exit" &&
            readFixture(folder / L"exit (1).bin") == "new-exit");
        window = nullptr;
        shell = ShellMock{}; shell.allowAdd = false; window = createWindow();
        SendMessageW(window, WM_CLOSE, 0, 0); pump();
        check("initial mock tray failure and close remain visible with no hidden inaccessible process", IsWindowVisible(window) &&
            !trayAvailable && !shell.present && !watcher.running() && hasRecord(L"트레이 아이콘을 등록하지 못했습니다"));
        shell.allowAdd = true; SendMessageW(window, WM_CLOSE, 0, 0); startFixtureWatcher(window);
        SendMessageW(window, WM_ENDSESSION, TRUE, ENDSESSION_LOGOFF); pump();
        check("confirmed Windows session end shuts down hidden watcher and native resources", cleaned(window) && !shell.present && appWindowCount() == 0);
        window = nullptr;
        // API registration is separate evidence from physical Explorer icon presentation.
        realShell = RealShellProof{}; trayNotify = recordRealNotify; window = createWindow();
        if (trayAvailable) {
            SendMessageW(window, WM_CLOSE, 0, 0); const bool hidden = !IsWindowVisible(window) && trayAvailable;
            SendMessageW(window, TrayMessage, TrayIconId, WM_LBUTTONDBLCLK);
            const bool restored = IsWindowVisible(window) && !IsIconic(window);
            SendMessageW(window, WM_COMMAND, TrayExit, 0); pump();
            check("actual Shell notification API add modify hide open and cleanup", hidden && restored && cleaned(window) &&
                realShell.adds == 1 && realShell.added && realShell.modifies == 1 && realShell.modified &&
                realShell.deletes == 1 && realShell.deleted);
        } else {
            std::cout << "NOT RUN actual Shell notification API: registration unavailable in this desktop session\n";
            SendMessageW(window, WM_COMMAND, TrayExit, 0); pump();
        }
        window = nullptr;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; ++failed;
        if (window && IsWindow(window)) { closeApp(window); pump(); } else watcher.stop();
    }
    std::ofstream report(fixture / L"tray-results.json");
    report << "{\"passed\":" << passed << ",\"failed\":" << failed << ",\"boundaries\":\"real HWND and watcher; deterministic shell failures and Explorer broadcast; actual shell registration API when available; physical icon, real Explorer restart, actual Windows logoff, exit during engine rename, production singleton and installer NOT RUN\",\"cases\":[";
    for (size_t at = 0; at < outcomes.size(); ++at) report << (at ? "," : "") << outcomes[at];
    report << "]}\n";
    std::cout << "BOUNDARY real HWND, menu and watcher events; mocked shell failures and Explorer restart; real Shell notification API separately checked. Physical icon, actual Explorer restart/logoff, exit during engine rename, production singleton and installer NOT RUN.\n";
    return failed ? 1 : 0;
}
