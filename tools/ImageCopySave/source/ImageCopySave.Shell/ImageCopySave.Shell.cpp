// Native Shell adapter: image work and nonmodal task UI live in the helper.
// Registration uses an apartment-threaded COM server; no self-registration.
#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <ocidl.h>
#include <shlguid.h>
#include <servprov.h>
#include <shellapi.h>
#include <atomic>
#include <cstring>
#include <cwchar>
#include <new>
#include <memory>
#include <string>
#include <string_view>
#include <vector>
#include "ShellGuids.h"
#include "ShellPolicy.h"

namespace
{
using namespace ImageCopySave;
namespace Policy = ImageCopySave::ShellPolicy;

HMODULE moduleHandle = nullptr;
std::atomic<long> objectCount{0};
std::atomic<long> serverLockCount{0};

enum class CommandKind { Save, Copy };

template<class T> class ComPtr
{
public:
    ComPtr() noexcept = default;
    ~ComPtr() { if (value_) value_->Release(); }
    ComPtr(const ComPtr&) = delete;
    ComPtr& operator=(const ComPtr&) = delete;
    T* operator->() const noexcept { return value_; }
    T* Get() const noexcept { return value_; }
    T** Put() noexcept { return &value_; }
private:
    T* value_ = nullptr;
};

class TaskString
{
public:
    ~TaskString() { CoTaskMemFree(value_); }
    PWSTR* Put() noexcept { return &value_; }
    const wchar_t* Get() const noexcept { return value_; }
private:
    PWSTR value_ = nullptr;
};

class TaskPidl
{
public:
    ~TaskPidl() { CoTaskMemFree(value_); }
    PIDLIST_ABSOLUTE* Put() noexcept { return &value_; }
    PCIDLIST_ABSOLUTE Get() const noexcept { return value_; }
private:
    PIDLIST_ABSOLUTE value_ = nullptr;
};

HRESULT CopyText(const wchar_t* text, PWSTR* result) noexcept
{
    if (!result) return E_POINTER;
    *result = nullptr;
    const auto bytes = (std::wcslen(text) + 1) * sizeof(wchar_t);
    auto copy = static_cast<PWSTR>(CoTaskMemAlloc(bytes));
    if (!copy) return E_OUTOFMEMORY;
    std::memcpy(copy, text, bytes);
    *result = copy;
    return S_OK;
}

bool IsSupportedLocalPath(const std::wstring& path, const bool directory)
{
    if (!Policy::IsOrdinaryAbsolutePath(path)) return false;
    wchar_t root[] = {path[0], L':', L'\\', L'\0'};
    if (GetDriveTypeW(root) != DRIVE_FIXED) return false;
    wchar_t drive[] = {path[0], L':', L'\0'};
    wchar_t device[1024]{};
    if (QueryDosDeviceW(drive, device, static_cast<DWORD>(ARRAYSIZE(device))) == 0 ||
        !Policy::IsPhysicalVolumeDevice(device)) return false;

    // Visit only each ancestor's attributes, from the drive root downward.
    // No directory enumeration, file contents, ACL probe or placeholder opening.
    // Reject a reparse/recall ancestor before asking the OS about its child.
    const std::wstring extended = L"\\\\?\\" + path;
    if (!Policy::AreSupportedAttributes(
            GetFileAttributesW(extended.substr(0, 7).c_str()), true)) return false;
    if (path.size() == 3) return directory;
    for (std::size_t start = 3; start < path.size();)
    {
        const auto separator = path.find(L'\\', start);
        const bool last = separator == std::wstring::npos;
        const auto end = last ? path.size() : separator;
        const auto attributes = GetFileAttributesW(extended.substr(0, end + 4).c_str());
        if (!Policy::AreSupportedAttributes(attributes, last ? directory : true))
            return false;
        if (last) return true;
        start = end + 1;
    }
    return false;
}

HRESULT GetItemPath(IShellItem* item, const bool directory, std::wstring& path)
{
    if (!item) return E_INVALIDARG;
    SFGAOF attributes{};
    const auto result = item->GetAttributes(
        SFGAO_FILESYSTEM | SFGAO_FOLDER | SFGAO_LINK, &attributes);
    if (FAILED(result)) return result;
    if ((attributes & SFGAO_FILESYSTEM) == 0 ||
        (attributes & SFGAO_LINK) != 0 ||
        ((attributes & SFGAO_FOLDER) != 0) != directory)
        return HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    TaskString name;
    const auto nameResult = item->GetDisplayName(SIGDN_FILESYSPATH, name.Put());
    if (FAILED(nameResult)) return nameResult;
    if (!name.Get() || !*name.Get()) return HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    path.assign(name.Get());
    if (!IsSupportedLocalPath(path, directory))
        return HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    return S_OK;
}

HRESULT GetSelectedImagePath(IShellItemArray* selection, std::wstring& path)
{
    if (!selection) return E_INVALIDARG;
    DWORD count = 0;
    auto result = selection->GetCount(&count);
    if (FAILED(result)) return result;
    if (count != 1) return HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    ComPtr<IShellItem> item;
    result = selection->GetItemAt(0, item.Put());
    if (FAILED(result)) return result;
    result = GetItemPath(item.Get(), false, path);
    if (FAILED(result)) return result;
    if (!Policy::IsSupportedImageExtension(path))
        return HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    return S_OK;
}

HRESULT GetFolderView(IUnknown* site, IFolderView** resultView)
{
    if (!resultView) return E_POINTER;
    *resultView = nullptr;
    if (!site) return E_NOINTERFACE;
    ComPtr<IServiceProvider> services;
    auto result = site->QueryInterface(
        IID_IServiceProvider, reinterpret_cast<void**>(services.Put()));
    if (FAILED(result)) return result;
    if (!services.Get()) return E_NOINTERFACE;
    return services->QueryService(
        SID_SFolderView, IID_IFolderView, reinterpret_cast<void**>(resultView));
}

HRESULT GetViewFolderPath(IFolderView* view, std::wstring& path)
{
    if (!view) return E_NOINTERFACE;
    ComPtr<IPersistFolder2> folder;
    auto result = view->GetFolder(IID_IPersistFolder2,
                            reinterpret_cast<void**>(folder.Put()));
    if (FAILED(result)) return result;
    if (!folder.Get()) return E_NOINTERFACE;
    TaskPidl pidl;
    result = folder->GetCurFolder(pidl.Put());
    if (FAILED(result)) return result;
    if (!pidl.Get()) return HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);

    ComPtr<IShellItem> item;
    result = SHCreateItemFromIDList(pidl.Get(), IID_IShellItem,
                                   reinterpret_cast<void**>(item.Put()));
    if (FAILED(result)) return result;
    // Filesystem identity must come from the invoking view's folder PIDL.
    // Never use a selected folder, ShellWindows, process CWD or active window.
    return GetItemPath(item.Get(), true, path);
}

HRESULT GetCallerFolderPath(IUnknown* site, std::wstring& path)
{
    ComPtr<IFolderView> view;
    const auto result = GetFolderView(site, view.Put());
    return FAILED(result) ? result : GetViewFolderPath(view.Get(), path);
}

bool ClipboardHasSupportedImage() noexcept
{
    const DWORD before = GetClipboardSequenceNumber();
    if (!before) return false;
    const UINT png = RegisterClipboardFormatW(L"PNG");
    if (!png) return false;
    const Policy::ClipboardFormats formats{
        IsClipboardFormatAvailable(png) != FALSE,
        IsClipboardFormatAvailable(CF_DIBV5) != FALSE,
        IsClipboardFormatAvailable(CF_DIB) != FALSE,
        IsClipboardFormatAvailable(CF_BITMAP) != FALSE
    };
    // A changed clipboard makes this state evaluation uncertain. Reopening the
    // menu reevaluates it. No OpenClipboard/GetClipboardData/delayed rendering.
    return before == GetClipboardSequenceNumber() && Policy::HasSupportedImage(formats);
}

HRESULT ReadUserObjectName(HANDLE object, std::wstring& name)
{
    if (!object) return E_INVALIDARG;
    DWORD bytes = 0;
    SetLastError(ERROR_SUCCESS);
    const BOOL first = GetUserObjectInformationW(object, UOI_NAME, nullptr, 0, &bytes);
    const DWORD firstError = GetLastError();
    if (first || firstError != ERROR_INSUFFICIENT_BUFFER)
        return firstError ? HRESULT_FROM_WIN32(firstError) : E_FAIL;
    if (bytes < 2 * sizeof(wchar_t) || bytes > 32768 * sizeof(wchar_t) ||
        bytes % sizeof(wchar_t) != 0) return E_FAIL;
    std::vector<wchar_t> buffer(bytes / sizeof(wchar_t), L'\0');
    DWORD returnedBytes = 0;
    if (!GetUserObjectInformationW(object, UOI_NAME, buffer.data(), bytes, &returnedBytes))
    {
        const DWORD error = GetLastError();
        return error ? HRESULT_FROM_WIN32(error) : E_FAIL;
    }
    if (returnedBytes == 0 || returnedBytes > bytes) return E_FAIL;
    const std::wstring_view value(buffer.data(), buffer.size());
    const auto terminator = value.find(L'\0');
    if (terminator == 0 || terminator == std::wstring_view::npos) return E_FAIL;
    const auto objectName = value.substr(0, terminator);
    if (objectName.find_first_of(L"\\/") != std::wstring_view::npos) return E_FAIL;
    name.assign(objectName);
    return S_OK;
}

HRESULT GetCallerDesktop(std::wstring& identity)
{
    // Borrow these handles; never close or change the caller's station/desktop.
    const HWINSTA station = GetProcessWindowStation();
    const HDESK desktop = GetThreadDesktop(GetCurrentThreadId());
    if (!station || !desktop) return E_FAIL;
    std::wstring stationName, desktopName;
    auto result = ReadUserObjectName(station, stationName);
    if (FAILED(result)) return result;
    result = ReadUserObjectName(desktop, desktopName);
    if (FAILED(result)) return result;
    if (station != GetProcessWindowStation() ||
        desktop != GetThreadDesktop(GetCurrentThreadId())) return E_FAIL;
    identity = stationName + L"\\" + desktopName;
    if (identity.size() >= 32767) return E_FAIL;
    return S_OK;
}

#include "ShellCompletion.h"

HRESULT LaunchHelper(const CommandKind kind, const std::wstring& path,
                     const DWORD sequence, IFolderView* view)
{
    std::vector<wchar_t> modulePath(32768, L'\0');
    const DWORD length = GetModuleFileNameW(
        moduleHandle, modulePath.data(), static_cast<DWORD>(modulePath.size()));
    if (length == 0) return HRESULT_FROM_WIN32(GetLastError());
    if (length >= modulePath.size())
        return HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE);
    const std::wstring location(modulePath.data(), length);
    const auto separator = location.find_last_of(L'\\');
    if (separator == std::wstring::npos) return E_UNEXPECTED;
    const std::wstring directory = location.substr(0, separator);
    const std::wstring helper = directory + L"\\ImageCopySave.Helper.exe";
    if (!IsSupportedLocalPath(helper, false))
        return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
    ComPtr<IShellView> shellView;
    HWND viewWindow = nullptr;
    if (view &&
        SUCCEEDED(view->QueryInterface(IID_IShellView, reinterpret_cast<void**>(shellView.Put()))))
        shellView->GetWindow(&viewWindow);
    const HWND parent = viewWindow ? GetAncestor(viewWindow, GA_ROOT) : nullptr;
    const std::wstring command = Policy::QuoteWindowsArgument(helper) +
        (kind == CommandKind::Save ? L" --shell save " : L" --shell copy ") +
        Policy::QuoteWindowsArgument(path) + L" " + std::to_wstring(sequence) + L" " +
        std::to_wstring(reinterpret_cast<ULONG_PTR>(parent));
    if (command.size() >= 32767)
        return HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE);
    std::vector<wchar_t> writableCommand(command.begin(), command.end());
    writableCommand.push_back(L'\0');
    std::wstring desktopIdentity;
    const auto desktopResult = GetCallerDesktop(desktopIdentity);
    if (FAILED(desktopResult)) return desktopResult;
    auto completion = std::make_unique<Completion>();
    completion->folder = kind == CommandKind::Save ? path : L"";
    completion->viewWindow = viewWindow;
    if (kind == CommandKind::Save && view)
        RoGetAgileReference(AGILEREFERENCE_DEFAULT, IID_IFolderView, view, &completion->viewReference);
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    OwnedHandle writePipe, nullInput, nullError;
    if (!CreatePipe(&completion->output, writePipe.Put(), &security, 131072) ||
        !SetHandleInformation(completion->output, HANDLE_FLAG_INHERIT, 0))
        return HRESULT_FROM_WIN32(GetLastError());
    nullInput.value = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                 &security, OPEN_EXISTING, 0, nullptr);
    nullError.value = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                 &security, OPEN_EXISTING, 0, nullptr);
    if (!nullInput.Valid() || !nullError.Valid()) return HRESULT_FROM_WIN32(GetLastError());
    StartupAttributes attributes;
    HANDLE inherited[] = {writePipe.value, nullInput.value, nullError.value};
    const auto attributeResult = attributes.Initialize(inherited, sizeof(inherited));
    if (FAILED(attributeResult)) return attributeResult;
    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    // An explicit identity prevents fallback to a different station/desktop.
    startup.StartupInfo.lpDesktop = desktopIdentity.data();
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdOutput = writePipe.value;
    startup.StartupInfo.hStdInput = nullInput.value;
    startup.StartupInfo.hStdError = nullError.value;
    startup.lpAttributeList = attributes.value;
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(helper.c_str(), writableCommand.data(), nullptr, nullptr,
                        TRUE, CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT, nullptr, directory.c_str(),
                        &startup.StartupInfo, &process))
        return HRESULT_FROM_WIN32(GetLastError());
    CloseHandle(process.hThread);
    completion->process = process.hProcess;
    // The helper owns task feedback even if selection monitoring cannot start.
    // Pin our module until the monitor thread has released its COM proxy.
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
            reinterpret_cast<LPCWSTR>(&moduleHandle), &completion->module))
    {
        HANDLE thread = CreateThread(nullptr, 0, CompleteHelper, completion.get(), 0, nullptr);
        if (thread) { completion.release(); CloseHandle(thread); }
    }
    return S_OK;
}

class ExplorerCommand final : public IExplorerCommand, public IObjectWithSite
{
public:
    explicit ExplorerCommand(const CommandKind kind) noexcept : kind_(kind)
    { objectCount.fetch_add(1, std::memory_order_relaxed); }

    IFACEMETHODIMP QueryInterface(REFIID iid, void** result) override
    {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_IExplorerCommand))
            *result = static_cast<IExplorerCommand*>(this);
        else if (IsEqualIID(iid, IID_IObjectWithSite))
            *result = static_cast<IObjectWithSite*>(this);
        else return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    IFACEMETHODIMP_(ULONG) AddRef() override
    { return references_.fetch_add(1, std::memory_order_relaxed) + 1; }
    IFACEMETHODIMP_(ULONG) Release() override
    {
        const ULONG remaining = references_.fetch_sub(1, std::memory_order_acq_rel) - 1;
        if (!remaining) delete this;
        return remaining;
    }

    IFACEMETHODIMP GetTitle(IShellItemArray*, PWSTR* title) override
    {
        return CopyText(kind_ == CommandKind::Save
            ? L"복사한 그림 저장" : L"그림으로 복사", title);
    }
    IFACEMETHODIMP GetIcon(IShellItemArray*, PWSTR* icon) override
    {
        if (!icon) return E_POINTER;
        *icon = nullptr;
        return E_NOTIMPL;
    }
    IFACEMETHODIMP GetToolTip(IShellItemArray*, PWSTR* tooltip) override
    {
        if (!tooltip) return E_POINTER;
        *tooltip = nullptr;
        return E_NOTIMPL;
    }
    IFACEMETHODIMP GetCanonicalName(GUID* name) override
    {
        if (!name) return E_POINTER;
        *name = kind_ == CommandKind::Save ? CLSID_SaveImage : CLSID_CopyImage;
        return S_OK;
    }
    IFACEMETHODIMP GetState(IShellItemArray* selection, BOOL okToBeSlow,
                           EXPCMDSTATE* state) override
    {
        if (!state) return E_POINTER;
        *state = ECS_HIDDEN;
        try
        {
            // Cheap, conclusive exclusions are safe in either call mode.
            // Do not ask a Shell provider for paths/folder interfaces or touch
            // drive/ancestor metadata until Explorer permits slow evaluation.
            if (kind_ == CommandKind::Save)
            {
                if (!site_) return S_OK;
            }
            else
            {
                if (!selection) return S_OK;
                DWORD count = 0;
                if (FAILED(selection->GetCount(&count)) || count != 1) return S_OK;
            }
            if (!okToBeSlow) return E_PENDING;

            std::wstring path;
            const auto result = kind_ == CommandKind::Save
                ? GetCallerFolderPath(site_, path)
                : GetSelectedImagePath(selection, path);
            if (SUCCEEDED(result) &&
                (kind_ == CommandKind::Copy || ClipboardHasSupportedImage()))
                *state = ECS_ENABLED;
        }
        catch (...) { /* Uncertain context remains completely hidden. */ }
        return S_OK;
    }
    IFACEMETHODIMP Invoke(IShellItemArray* selection, IBindCtx*) override
    {
        try
        {
            // Capture before path resolution or process cold start. The worker
            // verifies this baseline under its clipboard lock before reading or publishing.
            const DWORD sequence = GetClipboardSequenceNumber();
            if (!sequence) return ReportLaunchFailure(HRESULT_FROM_WIN32(ERROR_RETRY));
            ComPtr<IFolderView> callerView;
            const auto viewResult = GetFolderView(site_, callerView.Put());
            if (kind_ == CommandKind::Save && FAILED(viewResult)) return ReportLaunchFailure(viewResult);
            // Do not trust a GetState cache: resolve the invocation's supplied
            // selection or the original caller-site folder again.
            std::wstring path;
            const auto result = kind_ == CommandKind::Save
                ? GetViewFolderPath(callerView.Get(), path)
                : GetSelectedImagePath(selection, path);
            if (FAILED(result)) return ReportLaunchFailure(result);
            if (kind_ == CommandKind::Save && !ClipboardHasSupportedImage())
                return ReportLaunchFailure(HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED));
            return ReportLaunchFailure(LaunchHelper(kind_, path, sequence, callerView.Get()));
        }
        catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
        catch (...) { return E_FAIL; }
    }
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override
    {
        if (!flags) return E_POINTER;
        *flags = ECF_DEFAULT;
        return S_OK;
    }
    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** commands) override
    {
        if (!commands) return E_POINTER;
        *commands = nullptr;
        return E_NOTIMPL;
    }
    IFACEMETHODIMP SetSite(IUnknown* site) override
    {
        if (site) site->AddRef();
        IUnknown* previous = site_;
        site_ = site;
        if (previous) previous->Release();
        return S_OK;
    }
    IFACEMETHODIMP GetSite(REFIID iid, void** site) override
    {
        if (!site) return E_POINTER;
        *site = nullptr;
        return site_ ? site_->QueryInterface(iid, site) : E_NOINTERFACE;
    }
private:
    ~ExplorerCommand()
    {
        if (site_) site_->Release();
        objectCount.fetch_sub(1, std::memory_order_relaxed);
    }
    std::atomic<ULONG> references_{1};
    const CommandKind kind_;
    IUnknown* site_ = nullptr; // Accessed in the registered COM apartment.
};

class ClassFactory final : public IClassFactory
{
public:
    explicit ClassFactory(const CommandKind kind) noexcept : kind_(kind)
    { objectCount.fetch_add(1, std::memory_order_relaxed); }
    IFACEMETHODIMP QueryInterface(REFIID iid, void** result) override
    {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, IID_IClassFactory))
            return E_NOINTERFACE;
        *result = static_cast<IClassFactory*>(this);
        AddRef();
        return S_OK;
    }
    IFACEMETHODIMP_(ULONG) AddRef() override
    { return references_.fetch_add(1, std::memory_order_relaxed) + 1; }
    IFACEMETHODIMP_(ULONG) Release() override
    {
        const ULONG remaining = references_.fetch_sub(1, std::memory_order_acq_rel) - 1;
        if (!remaining) delete this;
        return remaining;
    }
    IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** result) override
    {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        auto command = new (std::nothrow) ExplorerCommand(kind_);
        if (!command) return E_OUTOFMEMORY;
        const auto status = command->QueryInterface(iid, result);
        command->Release();
        return status;
    }
    IFACEMETHODIMP LockServer(BOOL lock) override
    {
        if (lock)
        {
            serverLockCount.fetch_add(1, std::memory_order_relaxed);
            return S_OK;
        }
        long previous = serverLockCount.load(std::memory_order_relaxed);
        while (previous > 0)
            if (serverLockCount.compare_exchange_weak(
                    previous, previous - 1, std::memory_order_relaxed))
                return S_OK;
        return E_UNEXPECTED;
    }
private:
    ~ClassFactory() { objectCount.fetch_sub(1, std::memory_order_relaxed); }
    std::atomic<ULONG> references_{1};
    const CommandKind kind_;
};
}

extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH) moduleHandle = instance;
    return TRUE;
}

extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** result)
{
    if (!result) return E_POINTER;
    *result = nullptr;
    CommandKind kind;
    if (IsEqualCLSID(clsid, ImageCopySave::CLSID_SaveImage)) kind = CommandKind::Save;
    else if (IsEqualCLSID(clsid, ImageCopySave::CLSID_CopyImage)) kind = CommandKind::Copy;
    else return CLASS_E_CLASSNOTAVAILABLE;
    auto factory = new (std::nothrow) ClassFactory(kind);
    if (!factory) return E_OUTOFMEMORY;
    const auto status = factory->QueryInterface(iid, result);
    factory->Release();
    return status;
}

extern "C" HRESULT __stdcall DllCanUnloadNow()
{
    return objectCount.load(std::memory_order_acquire) == 0 &&
           serverLockCount.load(std::memory_order_acquire) == 0 ? S_OK : S_FALSE;
}
