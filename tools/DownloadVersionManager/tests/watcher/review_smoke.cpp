#include "review.h"
#include <commctrl.h>
#include <filesystem>
#include <iostream>
#include <thread>
#include <vector>

namespace {
std::wstring joined(const std::wstring& folder, const std::wstring& name) { return folder + L"\\" + name; }
bool write(const std::wstring& path, const std::string& text) {
    const HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    const bool okay = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) != FALSE && written == text.size();
    CloseHandle(file); return okay;
}
std::string read(const std::wstring& path) {
    const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return {};
    char text[256]{}; DWORD count = 0;
    const bool okay = ReadFile(file, text, sizeof(text), &count, nullptr) != FALSE;
    CloseHandle(file); return okay ? std::string(text, count) : std::string{};
}
BY_HANDLE_FILE_INFORMATION information(const std::wstring& path) {
    BY_HANDLE_FILE_INFORMATION result{};
    const HANDLE file = CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) { GetFileInformationByHandle(file, &result); CloseHandle(file); }
    return result;
}
bool object(const BY_HANDLE_FILE_INFORMATION& a, const BY_HANDLE_FILE_INFORMATION& b) {
    return a.dwVolumeSerialNumber == b.dwVolumeSerialNumber &&
        a.nFileIndexHigh == b.nFileIndexHigh && a.nFileIndexLow == b.nFileIndexLow;
}
bool snapshot(const BY_HANDLE_FILE_INFORMATION& a, const BY_HANDLE_FILE_INFORMATION& b) {
    return object(a, b) && a.nFileSizeLow == b.nFileSizeLow && a.nFileSizeHigh == b.nFileSizeHigh &&
        CompareFileTime(&a.ftCreationTime, &b.ftCreationTime) == 0 &&
        CompareFileTime(&a.ftLastWriteTime, &b.ftLastWriteTime) == 0;
}
HWND reviewWindow() {
    HWND result = nullptr;
    EnumWindows([](HWND window, LPARAM value) -> BOOL {
        DWORD process = 0; GetWindowThreadProcessId(window, &process);
        wchar_t name[64]{}; GetClassNameW(window, name, 64);
        if (process != GetCurrentProcessId() || std::wstring(name) != L"Workspace.DvmExistingReview") return TRUE;
        *reinterpret_cast<HWND*>(value) = window; return FALSE;
    }, reinterpret_cast<LPARAM>(&result));
    return result;
}
void select(HWND list, int row) {
    LVITEMW item{}; item.state = LVIS_SELECTED | LVIS_FOCUSED; item.stateMask = item.state;
    SendMessageW(list, LVM_SETITEMSTATE, static_cast<WPARAM>(row), reinterpret_cast<LPARAM>(&item));
}
BOOL CALLBACK planText(HWND child, LPARAM value) {
    const auto text = reinterpret_cast<std::wstring*>(value);
    if ((GetWindowLongPtrW(child, GWL_STYLE) & ES_MULTILINE) == 0) return TRUE;
    wchar_t type[32]{}; GetClassNameW(child, type, 32);
    if (std::wstring(type) != L"Edit") return TRUE;
    std::vector<wchar_t> buffer(static_cast<size_t>(GetWindowTextLengthW(child)) + 1);
    GetWindowTextW(child, buffer.data(), static_cast<int>(buffer.size()));
    *text = buffer.data(); return FALSE;
}
enum class Flow { CloseWithoutConsent, Skip, SelectLatest, ChangedRoot };
std::string utf8(const std::wstring& text) {
    const auto count = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    std::string result(static_cast<size_t>(count), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), result.data(), count, nullptr, nullptr);
    return result;
}
bool run(const std::wstring& base, const wchar_t* name, Flow flow) {
    const auto folder = joined(base, name);
    if (!CreateDirectoryW(folder.c_str(), nullptr)) return false;
    const auto root = joined(folder, L"report.txt"), first = joined(folder, L"report (1).txt"), second = joined(folder, L"report (2).txt");
    if (!write(root, "old") || !write(first, "chosen latest") || !write(second, "other previous")) return false;
    const auto original = information(root), chosen = information(first), other = information(second);
    bool uiOkay = false;
    std::thread input([&] {
        HWND window = nullptr;
        for (int attempt = 0; attempt < 500; ++attempt) {
            window = reviewWindow();
            if (window && GetDlgItem(window, 202)) break;
            Sleep(10);
        }
        if (!window) return;
        const HWND list = GetDlgItem(window, 201), process = GetDlgItem(window, 202);
        uiOkay = list && process && !IsWindowEnabled(process) &&
            SendMessageW(list, LVM_GETNEXTITEM, static_cast<WPARAM>(-1), LVNI_SELECTED) == -1 &&
            read(root) == "old" && read(first) == "chosen latest" && read(second) == "other previous";
        if (flow == Flow::CloseWithoutConsent || !uiOkay) { SendMessageW(window, WM_CLOSE, 0, 0); return; }
        if (flow == Flow::Skip) { SendMessageW(window, WM_COMMAND, 203, 0); return; }
        select(list, 1);
        std::wstring plan; EnumChildWindows(window, planText, reinterpret_cast<LPARAM>(&plan));
        uiOkay = uiOkay && IsWindowEnabled(process) &&
            plan.find(L"1. report (2).txt") != std::wstring::npos &&
            plan.find(L"2. report (1).txt") != std::wstring::npos;
        if (flow == Flow::ChangedRoot) uiOkay = uiOkay && write(root, "externally changed root");
        SendMessageW(window, WM_COMMAND, uiOkay ? 202 : 203, 0);
    });
    std::vector<std::wstring> messages;
    const bool complete = dvm::reviewExisting(nullptr, folder, [&messages](const std::wstring& text) { messages.push_back(text); });
    input.join();
    bool okay = uiOkay;
    if (flow == Flow::SelectLatest) {
        okay = okay && complete && object(information(root), chosen) && snapshot(information(root), chosen) &&
            read(root) == "chosen latest" && GetFileAttributesW(first.c_str()) == INVALID_FILE_ATTRIBUTES &&
            GetFileAttributesW(second.c_str()) == INVALID_FILE_ATTRIBUTES;
        std::vector<std::string> history;
        const auto location = std::filesystem::path(joined(folder, L"_history"));
        if (std::filesystem::is_directory(location))
            for (const auto& entry : std::filesystem::directory_iterator(location)) history.push_back(read(entry.path().wstring()));
        okay = okay && history.size() == 2 &&
            ((history[0] == "old" && history[1] == "other previous") || (history[1] == "old" && history[0] == "other previous"));
    } else {
        const bool changed = flow == Flow::ChangedRoot;
        okay = okay && complete == (flow != Flow::CloseWithoutConsent) &&
            (changed ? read(root) == "externally changed root" : snapshot(information(root), original)) &&
            snapshot(information(first), chosen) && snapshot(information(second), other) &&
            GetFileAttributesW(joined(folder, L"_history").c_str()) == INVALID_FILE_ATTRIBUTES;
        if (changed) okay = okay && !messages.empty() && messages.back().find(L"변경") != std::wstring::npos;
    }
    std::cout << (okay ? "PASS " : "FAIL ") << utf8(name) << "\n";
    for (const auto& message : messages) std::cout << "  " << utf8(message) << "\n";
    return okay;
}
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 2 || GetFileAttributesW(argv[1]) == INVALID_FILE_ATTRIBUTES) return 2;
    const std::wstring base = argv[1];
    bool okay = run(base, L"no-consent", Flow::CloseWithoutConsent);
    okay = run(base, L"skip", Flow::Skip) && okay;
    okay = run(base, L"chosen-latest", Flow::SelectLatest) && okay;
    okay = run(base, L"changed-after-display", Flow::ChangedRoot) && okay;
    return okay ? 0 : 1;
}
