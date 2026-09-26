// Included inside the adapter's private namespace after its COM/path helpers.
// No image data is transported here; stdout contains only one bounded result.
struct OwnedHandle
{
    HANDLE value = nullptr;
    ~OwnedHandle() { if (Valid()) CloseHandle(value); }
    bool Valid() const noexcept { return value && value != INVALID_HANDLE_VALUE; }
    HANDLE* Put() noexcept { return &value; }
};

struct StartupAttributes
{
    LPPROC_THREAD_ATTRIBUTE_LIST value = nullptr;
    bool initialized = false;
    ~StartupAttributes()
    {
        if (initialized) DeleteProcThreadAttributeList(value);
        if (value) HeapFree(GetProcessHeap(), 0, value);
    }
    HRESULT Initialize(HANDLE* handles, SIZE_T bytes)
    {
        SIZE_T size = 0;
        InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
        value = static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(HeapAlloc(GetProcessHeap(), 0, size));
        if (!value) return E_OUTOFMEMORY;
        if (!InitializeProcThreadAttributeList(value, 1, 0, &size))
            return HRESULT_FROM_WIN32(GetLastError());
        initialized = true;
        return UpdateProcThreadAttribute(value, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                    handles, bytes, nullptr, nullptr) ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    }
};

struct Completion
{
    HANDLE process = nullptr;
    HANDLE output = nullptr;
    IAgileReference* viewReference = nullptr;
    HWND viewWindow = nullptr;
    HMODULE module = nullptr;
    std::wstring folder;
    ~Completion()
    {
        if (process) CloseHandle(process);
        if (output) CloseHandle(output);
        if (viewReference) viewReference->Release();
        if (module) FreeLibrary(module);
    }
};

void SelectSavedResult(Completion& completion, IFolderView* view, const std::string& bytes)
{
    if (completion.folder.empty() || bytes.empty() || bytes.size() > 131068) return;
    auto line = bytes;
    while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) line.pop_back();
    const auto count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, line.data(),
                                         static_cast<int>(line.size()), nullptr, 0);
    if (count <= 0 || count > 32766) return;
    std::wstring path(static_cast<std::size_t>(count), L'\0');
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, line.data(),
                            static_cast<int>(line.size()), path.data(), count) ||
        !Policy::IsSavedImageInFolder(completion.folder, path)) return;
    SHChangeNotify(SHCNE_CREATE, SHCNF_PATHW | SHCNF_FLUSHNOWAIT, path.c_str(), nullptr);
    if (!view) return;
    ComPtr<IShellView> shellView;
    HWND currentWindow = nullptr;
    if (FAILED(view->QueryInterface(IID_IShellView, reinterpret_cast<void**>(shellView.Put()))) ||
        FAILED(shellView->GetWindow(&currentWindow)) || currentWindow != completion.viewWindow ||
        !IsWindowVisible(currentWindow) || GetAncestor(currentWindow, GA_ROOT) != GetForegroundWindow()) return;
    std::wstring currentFolder;
    if (FAILED(GetViewFolderPath(view, currentFolder)) ||
        !Policy::EqualAsciiInsensitive(currentFolder, completion.folder)) return;
    TaskPidl item;
    if (FAILED(SHParseDisplayName(path.c_str(), nullptr, item.Put(), 0, nullptr))) return;
    // Select only in the exact original view, while it is still visible/current.
    // No SVSI_FOCUSED, activation, navigation, rename or new Explorer window.
    if (IsWindowVisible(currentWindow) && GetAncestor(currentWindow, GA_ROOT) == GetForegroundWindow())
        shellView->SelectItem(ILFindLastID(item.Get()), SVSI_SELECT | SVSI_DESELECTOTHERS | SVSI_ENSUREVISIBLE);
}

DWORD WINAPI CompleteHelper(void* argument) noexcept
{
    auto raw = static_cast<Completion*>(argument);
    HMODULE pinned = raw->module;
    raw->module = nullptr;
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    {
        std::unique_ptr<Completion> completion(raw);
        ComPtr<IFolderView> view;
        // An agile reference owns marshaling cleanup on every outcome, including
        // thread/COM initialization failure, no stdout, helper failure and timeout.
        if (SUCCEEDED(initialized) && completion->viewReference)
            completion->viewReference->Resolve(IID_IFolderView, reinterpret_cast<void**>(view.Put()));
        try
        {
            std::string output;
            const auto started = GetTickCount64();
            bool finished = false, overflow = false;
            while (GetTickCount64() - started < 30000)
            {
                DWORD available = 0;
                if (PeekNamedPipe(completion->output, nullptr, 0, nullptr, &available, nullptr) && available)
                {
                    char buffer[4096];
                    DWORD received = 0;
                    const DWORD requested = available < sizeof(buffer) ? available : static_cast<DWORD>(sizeof(buffer));
                    if (ReadFile(completion->output, buffer, requested, &received, nullptr))
                    {
                        if (output.size() + received > 131072) { overflow = true; break; }
                        output.append(buffer, received);
                        continue;
                    }
                }
                if (WaitForSingleObject(completion->process, 25) == WAIT_OBJECT_0)
                {
                    // One final drain on the next iteration catches data written just before exit.
                    if (finished) break;
                    finished = true;
                }
            }
            DWORD exitCode = 1;
            if (SUCCEEDED(initialized) && finished && !overflow &&
                GetExitCodeProcess(completion->process, &exitCode) && exitCode == 0)
                SelectSavedResult(*completion, view.Get(), output);
        }
        catch (...) { /* Saved file remains successful; helper already displays its path. */ }
    }
    if (SUCCEEDED(initialized)) CoUninitialize();
    FreeLibraryAndExitThread(pinned, 0);
}

DWORD WINAPI ShowLaunchFailure(void* argument) noexcept
{
    const auto pinned = static_cast<HMODULE>(argument);
    // A short, nonmodal native fallback also works when the helper cannot start.
    const int width = 450, height = 96;
    RECT area{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &area, 0);
    HWND window = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
        L"STATIC", L"그림 작업을 시작하지 못했습니다.\n클립보드와 대상 위치를 확인한 뒤 다시 실행해 주세요.",
        WS_POPUP | WS_BORDER | SS_CENTER | SS_CENTERIMAGE,
        area.right - width - 24, area.bottom - height - 24, width, height,
        nullptr, nullptr, moduleHandle, nullptr);
    if (window)
    {
        ShowWindow(window, SW_SHOWNOACTIVATE);
        const UINT_PTR timer = SetTimer(window, 1, 7000, nullptr);
        if (timer)
        {
            MSG message{};
            while (GetMessageW(&message, nullptr, 0, 0) > 0)
            {
                if (message.message == WM_TIMER) break;
                TranslateMessage(&message); DispatchMessageW(&message);
            }
            KillTimer(window, timer);
        }
        DestroyWindow(window);
    }
    FreeLibraryAndExitThread(pinned, 0);
}

HRESULT ReportLaunchFailure(HRESULT status) noexcept
{
    if (SUCCEEDED(status)) return status;
    HMODULE pinned = nullptr;
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
            reinterpret_cast<LPCWSTR>(&moduleHandle), &pinned))
    {
        HANDLE thread = CreateThread(nullptr, 0, ShowLaunchFailure, pinned, 0, nullptr);
        if (thread) CloseHandle(thread);
        else FreeLibrary(pinned);
    }
    return status;
}
