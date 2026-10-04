#include "review.h"
#include "engine.h"
#include "watcher.h"
#include <commctrl.h>
#include <algorithm>
#include <map>
#include <vector>

namespace dvm {
namespace {
struct NameOrder {
    bool operator()(const std::wstring& a, const std::wstring& b) const {
        return CompareStringOrdinal(a.c_str(), static_cast<int>(a.size()),
            b.c_str(), static_cast<int>(b.size()), TRUE) == CSTR_LESS_THAN;
    }
};
struct File {
    std::wstring name;
    BY_HANDLE_FILE_INFORMATION snapshot{};
    bool captured = false;
};
struct Group { File root; std::vector<File> copies; };
std::wstring join(const std::wstring& folder, const std::wstring& name) {
    return folder + (folder.back() == L'\\' ? L"" : L"\\") + name;
}
std::wstring native(const std::wstring& path) { return L"\\\\?\\" + path; }
bool capture(const std::wstring& folder, File& file) {
    const HANDLE handle = CreateFileW(native(join(folder, file.name)).c_str(),
        FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return false;
    const bool read = GetFileInformationByHandle(handle, &file.snapshot) != FALSE;
    CloseHandle(handle);
    const DWORD excluded = FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT |
        FILE_ATTRIBUTE_OFFLINE | FILE_ATTRIBUTE_ENCRYPTED | FILE_ATTRIBUTE_TEMPORARY;
    file.captured = read && !(file.snapshot.dwFileAttributes & excluded) &&
        file.snapshot.nNumberOfLinks == 1;
    return file.captured;
}
bool same(const BY_HANDLE_FILE_INFORMATION& a, const BY_HANDLE_FILE_INFORMATION& b) {
    return a.dwVolumeSerialNumber == b.dwVolumeSerialNumber &&
        a.nFileIndexHigh == b.nFileIndexHigh && a.nFileIndexLow == b.nFileIndexLow &&
        a.nFileSizeHigh == b.nFileSizeHigh && a.nFileSizeLow == b.nFileSizeLow &&
        a.dwFileAttributes == b.dwFileAttributes && a.nNumberOfLinks == b.nNumberOfLinks &&
        CompareFileTime(&a.ftCreationTime, &b.ftCreationTime) == 0 &&
        CompareFileTime(&a.ftLastWriteTime, &b.ftLastWriteTime) == 0;
}
bool unchanged(const std::wstring& folder, const File& expected) {
    File current{expected.name};
    return expected.captured && capture(folder, current) && same(expected.snapshot, current.snapshot);
}
bool scan(const std::wstring& folder, std::vector<Group>& groups, DWORD& error) {
    std::map<std::wstring, File, NameOrder> files;
    WIN32_FIND_DATAW data{};
    const HANDLE search = FindFirstFileW(native(join(folder, L"*")).c_str(), &data);
    if (search == INVALID_HANDLE_VALUE) {
        error = GetLastError();
        return error == ERROR_FILE_NOT_FOUND;
    }
    do {
        const DWORD excluded = FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT |
            FILE_ATTRIBUTE_OFFLINE | FILE_ATTRIBUTE_ENCRYPTED | FILE_ATTRIBUTE_TEMPORARY;
        if (!(data.dwFileAttributes & excluded))
            files.emplace(data.cFileName, File{data.cFileName});
    } while (FindNextFileW(search, &data));
    error = GetLastError();
    FindClose(search);
    if (error != ERROR_NO_MORE_FILES) return false;
    std::map<std::wstring, size_t, NameOrder> indexes;
    for (const auto& entry : files) {
        std::wstring inferred;
        if (!duplicateName(entry.first, inferred)) continue;
        const auto original = files.find(inferred);
        if (original == files.end()) continue;
        auto group = indexes.find(original->first);
        if (group == indexes.end()) {
            indexes.emplace(original->first, groups.size());
            groups.push_back(Group{original->second, {}});
            group = indexes.find(original->first);
        }
        groups[group->second].copies.push_back(entry.second);
    }
    for (auto& group : groups) {
        capture(folder, group.root);
        for (auto& file : group.copies) capture(folder, file);
    }
    return true;
}

enum class Choice { Cancel, Process, Skip, SkipRemaining };
constexpr int FilesControl = 201, ProcessControl = 202, SkipControl = 203, SkipRemainingControl = 204;
struct Review {
    const std::wstring& folder;
    const Group& group;
    size_t ordinal, count;
    HWND window = nullptr, list = nullptr, plan = nullptr, process = nullptr;
    HFONT font = nullptr;
    UINT dpi = 96;
    int selected = -1;
    Choice choice = Choice::Cancel;
    bool finished = false;
    int px(int value) const { return MulDiv(value, static_cast<int>(dpi), 96); }
};
std::wstring modified(const File& file) {
    if (!file.captured) return L"정보를 읽을 수 없음";
    FILETIME local{}; SYSTEMTIME time{};
    if (!FileTimeToLocalFileTime(&file.snapshot.ftLastWriteTime, &local) ||
        !FileTimeToSystemTime(&local, &time)) return L"시각을 읽을 수 없음";
    wchar_t text[32]{};
    swprintf_s(text, L"%04u-%02u-%02u %02u:%02u:%02u", time.wYear, time.wMonth,
        time.wDay, time.wHour, time.wMinute, time.wSecond);
    return text;
}
std::vector<size_t> order(const Group& group, size_t selected) {
    std::vector<size_t> indexes;
    for (size_t at = 0; at < group.copies.size(); ++at) if (at != selected) indexes.push_back(at);
    std::sort(indexes.begin(), indexes.end(), [&group](size_t a, size_t b) {
        return NameOrder{}(group.copies[a].name, group.copies[b].name);
    });
    indexes.push_back(selected);
    return indexes;
}
void updatePlan(Review& review) {
    review.selected = ListView_GetNextItem(review.list, -1, LVNI_SELECTED);
    if (review.selected < 0) {
        EnableWindow(review.process, FALSE);
        SetWindowTextW(review.process, L"선택대로 정리");
        SetWindowTextW(review.plan, L"최신으로 유지할 파일을 직접 선택하세요. 번호와 수정 시각으로 최신 파일을 추측하지 않습니다.");
        return;
    }
    if (review.selected == 0) {
        EnableWindow(review.process, TRUE);
        SetWindowTextW(review.process, L"이 그룹 보존");
        SetWindowTextW(review.plan, L"원래 이름의 파일을 선택했습니다. 이 그룹의 모든 파일을 현재 이름 그대로 보존합니다.");
        return;
    }
    SetWindowTextW(review.process, L"선택대로 정리");
    bool captured = review.group.root.captured;
    for (const auto& file : review.group.copies) captured = captured && file.captured;
    EnableWindow(review.process, captured);
    if (!captured) {
        SetWindowTextW(review.plan, L"일부 파일의 정보를 읽을 수 없어 이 그룹을 정리할 수 없습니다. 모든 파일을 보존하세요.");
        return;
    }
    const auto selected = static_cast<size_t>(review.selected - 1);
    std::wstring text = L"선택한 최신 파일: " + review.group.copies[selected].name +
        L"\r\n최종 원래 이름: " + review.group.root.name +
        L"\r\n아래 번호 파일을 순서대로 원래 이름으로 이동합니다. 매 단계에서 직전 파일은 내용이 다르면 _history에 보관하고, 같으면 삭제합니다. 선택한 최신 파일을 마지막에 처리합니다.\r\n";
    size_t step = 0;
    for (const auto index : order(review.group, selected))
        text += std::to_wstring(++step) + L". " + review.group.copies[index].name + L" → " + review.group.root.name + L"\r\n";
    text += L"잠겼거나 확인 이후 변경된 파일이 있으면 중단하고 남은 파일을 보존합니다.";
    SetWindowTextW(review.plan, text.c_str());
}
HWND control(Review& review, const wchar_t* kind, const wchar_t* text, DWORD style,
    int x, int y, int width, int height, int id = 0, DWORD extended = 0) {
    const HWND item = CreateWindowExW(extended, kind, text, WS_CHILD | WS_VISIBLE | style,
        review.px(x), review.px(y), review.px(width), review.px(height), review.window,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(item, WM_SETFONT, reinterpret_cast<WPARAM>(review.font), TRUE);
    return item;
}
void addRow(Review& review, const File& file, bool root) {
    const int row = ListView_GetItemCount(review.list);
    LVITEMW item{}; item.mask = LVIF_TEXT; item.iItem = row;
    item.pszText = const_cast<wchar_t*>(file.name.c_str());
    ListView_InsertItem(review.list, &item);
    std::wstring role = root ? L"원래 이름 (선택하면 보존)" : L"번호 파일";
    ListView_SetItemText(review.list, row, 1, const_cast<wchar_t*>(role.c_str()));
    std::wstring time = modified(file);
    ListView_SetItemText(review.list, row, 2, const_cast<wchar_t*>(time.c_str()));
    const uint64_t bytes = (static_cast<uint64_t>(file.snapshot.nFileSizeHigh) << 32) | file.snapshot.nFileSizeLow;
    std::wstring size = file.captured ? std::to_wstring(bytes) : L"?";
    ListView_SetItemText(review.list, row, 3, const_cast<wchar_t*>(size.c_str()));
}
void finish(Review& review, Choice choice) {
    review.choice = choice; review.finished = true; DestroyWindow(review.window);
}
LRESULT CALLBACK reviewProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    Review* review = reinterpret_cast<Review*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
        review = static_cast<Review*>(create->lpCreateParams);
        review->window = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(review));
    }
    if (!review) return DefWindowProcW(window, message, wparam, lparam);
    switch (message) {
    case WM_CREATE: {
        review->font = CreateFontW(-review->px(15), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH, L"Malgun Gothic");
        const std::wstring heading = L"기존 번호 파일 확인 · " + std::to_wstring(review->ordinal) +
            L" / " + std::to_wstring(review->count) + L" 그룹\n같은 이름 규칙의 파일입니다. 최신 파일을 직접 선택한 후 정리 여부를 결정하세요.";
        control(*review, L"STATIC", heading.c_str(), 0, 20, 16, 740, 52);
        control(*review, L"EDIT", review->folder.c_str(), ES_READONLY | ES_AUTOHSCROLL,
            20, 75, 740, 28, 0, WS_EX_CLIENTEDGE);
        control(*review, L"STATIC", L"수정 시각은 참고 정보입니다. 선택한 파일을 최신으로 유지하며 원래 이름으로 이동합니다.", 0, 20, 112, 740, 25);
        review->list = control(*review, WC_LISTVIEWW, L"", WS_TABSTOP | WS_VSCROLL | WS_HSCROLL |
            LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS, 20, 142, 740, 200, FilesControl, WS_EX_CLIENTEDGE);
        ListView_SetExtendedListViewStyle(review->list, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
        const wchar_t* titles[] = {L"파일 이름", L"구분", L"수정 시각 (로컬)", L"크기 (byte)"};
        const int widths[] = {280, 180, 165, 105};
        for (int at = 0; at < 4; ++at) {
            LVCOLUMNW column{}; column.mask = LVCF_TEXT | LVCF_WIDTH;
            column.pszText = const_cast<wchar_t*>(titles[at]); column.cx = review->px(widths[at]);
            ListView_InsertColumn(review->list, at, &column);
        }
        addRow(*review, review->group.root, true);
        for (const auto& file : review->group.copies) addRow(*review, file, false);
        review->plan = control(*review, L"EDIT", L"", ES_READONLY | ES_MULTILINE | ES_AUTOVSCROLL |
            WS_VSCROLL, 20, 355, 740, 151, 0, WS_EX_CLIENTEDGE);
        review->process = control(*review, L"BUTTON", L"선택대로 정리", WS_TABSTOP | BS_PUSHBUTTON,
            20, 521, 170, 34, ProcessControl);
        control(*review, L"BUTTON", L"이 그룹 보존", WS_TABSTOP | BS_PUSHBUTTON, 202, 521, 155, 34, SkipControl);
        control(*review, L"BUTTON", L"남은 그룹 모두 보존", WS_TABSTOP | BS_PUSHBUTTON, 520, 521, 240, 34, SkipRemainingControl);
        updatePlan(*review);
        return 0;
    }
    case WM_NOTIFY: {
        const auto notification = reinterpret_cast<NMHDR*>(lparam);
        if (notification->idFrom == FilesControl && notification->code == LVN_ITEMCHANGED && review->plan)
            updatePlan(*review);
        return 0;
    }
    case WM_COMMAND:
        switch (LOWORD(wparam)) {
        case ProcessControl:
            if (review->selected >= 0 && IsWindowEnabled(review->process))
                finish(*review, review->selected == 0 ? Choice::Skip : Choice::Process);
            return 0;
        case SkipControl: finish(*review, Choice::Skip); return 0;
        case SkipRemainingControl: finish(*review, Choice::SkipRemaining); return 0;
        case IDCANCEL: finish(*review, Choice::Cancel); return 0;
        }
        break;
    case WM_CLOSE: finish(*review, Choice::Cancel); return 0;
    case WM_DESTROY:
        if (review->font) { DeleteObject(review->font); review->font = nullptr; }
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
Choice ask(HWND parent, Review& review) {
    INITCOMMONCONTROLSEX common{sizeof(common), ICC_LISTVIEW_CLASSES};
    InitCommonControlsEx(&common);
    WNDCLASSW cls{}; cls.lpfnWndProc = reviewProc; cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpszClassName = L"Workspace.DvmExistingReview"; cls.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    cls.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    if (!RegisterClassW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return Choice::Cancel;
    review.dpi = parent ? GetDpiForWindow(parent) : GetDpiForSystem();
    const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU;
    RECT bounds{0, 0, review.px(780), review.px(574)};
    AdjustWindowRectExForDpi(&bounds, style, FALSE, 0, review.dpi);
    const bool wasEnabled = parent && IsWindowEnabled(parent);
    if (wasEnabled) EnableWindow(parent, FALSE);
    const HWND window = CreateWindowExW(0, cls.lpszClassName, L"기존 파일 정리 확인",
        style, CW_USEDEFAULT, CW_USEDEFAULT, bounds.right - bounds.left,
        bounds.bottom - bounds.top, parent, nullptr, cls.hInstance, &review);
    if (window) {
        ShowWindow(window, SW_SHOW); SetForegroundWindow(window); SetFocus(review.list);
        MSG message{};
        while (!review.finished) {
            const BOOL received = GetMessageW(&message, nullptr, 0, 0);
            if (received <= 0) {
                if (received == 0) PostQuitMessage(static_cast<int>(message.wParam));
                break;
            }
            if (!IsDialogMessageW(window, &message)) { TranslateMessage(&message); DispatchMessageW(&message); }
        }
        if (IsWindow(window)) DestroyWindow(window);
    }
    if (wasEnabled && IsWindow(parent)) { EnableWindow(parent, TRUE); SetActiveWindow(parent); }
    return review.choice;
}
bool processGroup(const std::wstring& folder, Group& group, size_t selected,
    const std::function<void(const std::wstring&)>& report) {
    const auto indexes = order(group, selected);
    for (size_t step = 0; step < indexes.size(); ++step) {
        bool stable = unchanged(folder, group.root);
        for (size_t remaining = step; remaining < indexes.size(); ++remaining)
            stable = stable && unchanged(folder, group.copies[indexes[remaining]]);
        if (!stable) {
            report(group.root.name + L": 확인 이후 변경되거나 접근할 수 없는 파일이 있어 남은 파일을 보존했습니다.");
            return false;
        }
        const auto& source = group.copies[indexes[step]];
        Request request; request.newPath = join(folder, source.name); request.logicalName = group.root.name;
        request.folderPair = true; request.requireSnapshot = true; request.expectedSource = source.snapshot;
        request.requireTargetSnapshot = true; request.expectedTarget = group.root.snapshot;
        const Result result = process(request);
        if (!result.ok || result.error || result.rollbackError) {
            std::wstring text = group.root.name + L": " + result.status + L" · 나머지 파일 처리를 중단했습니다.";
            if (!result.oldPath.empty()) text += L" 이전 파일 위치: " + result.oldPath;
            report(text); return false;
        }
        group.root.snapshot = source.snapshot;
        group.root.captured = true;
    }
    report(group.root.name + L": 사용자가 선택한 " + group.copies[selected].name + L"을 원래 이름으로 유지했습니다.");
    return true;
}
}

bool reviewExisting(HWND parent, const std::wstring& folder,
    const std::function<void(const std::wstring&)>& report) {
    if (folder.empty()) return false;
    try {
        std::wstring errorText;
        if (!validateFolder(folder, errorText)) { report(errorText); return false; }
        std::vector<Group> groups; DWORD error = ERROR_SUCCESS;
        if (!scan(folder, groups, error)) {
            report(L"기존 파일 확인을 완료하지 못했습니다. Windows 오류 " + std::to_wstring(error));
            return false;
        }
        for (size_t at = 0; at < groups.size(); ++at) {
            Review review{folder, groups[at], at + 1, groups.size()};
            const Choice choice = ask(parent, review);
            if (choice == Choice::Cancel) return false;
            if (choice == Choice::SkipRemaining) {
                report(L"남은 " + std::to_wstring(groups.size() - at) + L"개 기존 이름 그룹을 사용자 선택에 따라 보존했습니다.");
                return true;
            }
            if (choice == Choice::Skip) report(groups[at].root.name + L": 사용자 선택에 따라 모든 파일을 보존했습니다.");
            else processGroup(folder, groups[at], static_cast<size_t>(review.selected - 1), report);
        }
        return true;
    } catch (...) {
        report(L"기존 파일 확인을 완료하지 못했습니다. 남은 파일을 보존했습니다.");
        return false;
    }
}
}
