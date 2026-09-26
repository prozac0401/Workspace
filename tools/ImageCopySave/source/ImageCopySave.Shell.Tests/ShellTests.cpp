// Native policy/COM boundary tests only. Never register COM, invoke commands,
// open Explorer, access the live clipboard or create image/business fixtures.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shobjidl.h>
#include <ocidl.h>
#include <shellapi.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>
#include "../ImageCopySave.Shell/ShellGuids.h"
#include "../ImageCopySave.Shell/ShellPolicy.h"

namespace
{
namespace Policy = ImageCopySave::ShellPolicy;
using namespace ImageCopySave;
struct Result { std::string name; bool passed; std::string detail; };
void Require(bool condition, const char* detail)
{ if (!condition) throw std::runtime_error(detail); }
class Runner
{
public:
    template<class Action> void Run(std::string name, Action action)
    {
        try { action(); results.push_back({std::move(name), true, ""}); }
        catch (const std::exception& e) { results.push_back({std::move(name), false, e.what()}); }
        catch (...) { results.push_back({std::move(name), false, "Unexpected exception"}); }
    }
    std::vector<Result> results;
};
template<class T> class ComPtr
{
public:
    ComPtr() noexcept = default;
    explicit ComPtr(T* value) noexcept : value_(value) {}
    ~ComPtr() { Reset(); }
    ComPtr(const ComPtr&) = delete;
    ComPtr& operator=(const ComPtr&) = delete;
    T* Get() const noexcept { return value_; }
    T* operator->() const noexcept { return value_; }
    T** Put() noexcept { Reset(); return &value_; }
    void Reset() noexcept
    { if (value_) { auto old = value_; value_ = nullptr; old->Release(); } }
private:
    T* value_ = nullptr;
};
struct TaskText { ~TaskText() { CoTaskMemFree(value); } PWSTR value = nullptr; };

class Site final : public IUnknown
{
public:
    explicit Site(bool* destroyed = nullptr) noexcept : destroyed_(destroyed) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override
    {
        if (!output) return E_POINTER;
        *output = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown)) return E_NOINTERFACE;
        *output = static_cast<IUnknown*>(this); AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
    ULONG STDMETHODCALLTYPE Release() override
    { const auto remaining = --references_; if (!remaining) delete this; return remaining; }
    ULONG References() const noexcept { return references_.load(); }
private:
    ~Site() { if (destroyed_) *destroyed_ = true; }
    std::atomic<ULONG> references_{1};
    bool* destroyed_;
};
class ShellItem final : public IShellItem
{
public:
    ShellItem(std::wstring path, SFGAOF attributes, HRESULT nameResult = S_OK) :
        path_(std::move(path)), attributes_(attributes), nameResult_(nameResult) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override
    {
        if (!output) return E_POINTER;
        *output = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, IID_IShellItem)) return E_NOINTERFACE;
        *output = static_cast<IShellItem*>(this); AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
    ULONG STDMETHODCALLTYPE Release() override
    { const auto remaining = --references_; if (!remaining) delete this; return remaining; }
    HRESULT STDMETHODCALLTYPE BindToHandler(IBindCtx*, REFGUID, REFIID, void** out) override
    { if (out) *out = nullptr; return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetParent(IShellItem** out) override
    { if (out) *out = nullptr; return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetDisplayName(SIGDN requested, PWSTR* out) override
    {
        if (!out) return E_POINTER;
        *out = nullptr; ++nameCalls;
        if (FAILED(nameResult_)) return nameResult_;
        if (requested != SIGDN_FILESYSPATH) return E_INVALIDARG;
        const auto bytes = (path_.size() + 1) * sizeof(wchar_t);
        *out = static_cast<PWSTR>(CoTaskMemAlloc(bytes));
        if (!*out) return E_OUTOFMEMORY;
        std::memcpy(*out, path_.c_str(), bytes); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetAttributes(SFGAOF requested, SFGAOF* out) override
    { if (!out) return E_POINTER; *out = requested & attributes_; return S_OK; }
    HRESULT STDMETHODCALLTYPE Compare(IShellItem*, SICHINTF, int* order) override
    { if (order) *order = 0; return E_NOTIMPL; }
    unsigned int nameCalls = 0;
private:
    ~ShellItem() = default;
    std::atomic<ULONG> references_{1};
    std::wstring path_;
    SFGAOF attributes_;
    HRESULT nameResult_;
};
class Selection final : public IShellItemArray
{
public:
    Selection(DWORD count, IShellItem* item = nullptr, HRESULT countResult = S_OK,
              HRESULT itemResult = S_OK) noexcept :
        count_(count), item_(item), countResult_(countResult), itemResult_(itemResult)
    { if (item_) item_->AddRef(); }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override
    {
        if (!output) return E_POINTER;
        *output = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, IID_IShellItemArray)) return E_NOINTERFACE;
        *output = static_cast<IShellItemArray*>(this); AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
    ULONG STDMETHODCALLTYPE Release() override
    { const auto remaining = --references_; if (!remaining) delete this; return remaining; }
    HRESULT STDMETHODCALLTYPE BindToHandler(IBindCtx*, REFGUID, REFIID, void** out) override
    { if (out) *out = nullptr; return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetPropertyStore(GETPROPERTYSTOREFLAGS, REFIID, void** out) override
    { if (out) *out = nullptr; return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetPropertyDescriptionList(REFPROPERTYKEY, REFIID, void** out) override
    { if (out) *out = nullptr; return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetAttributes(SIATTRIBFLAGS, SFGAOF, SFGAOF* out) override
    { if (out) *out = 0; return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetCount(DWORD* count) override
    { if (!count) return E_POINTER; *count = count_; return countResult_; }
    HRESULT STDMETHODCALLTYPE GetItemAt(DWORD index, IShellItem** out) override
    {
        ++itemCalls;
        if (!out) return E_POINTER;
        *out = nullptr;
        if (FAILED(itemResult_)) return itemResult_;
        if (index >= count_) return E_INVALIDARG;
        *out = item_; if (item_) item_->AddRef(); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE EnumItems(IEnumShellItems** out) override
    { if (out) *out = nullptr; return E_NOTIMPL; }
    unsigned int itemCalls = 0;
private:
    ~Selection() { if (item_) item_->Release(); }
    std::atomic<ULONG> references_{1};
    DWORD count_;
    IShellItem* item_;
    HRESULT countResult_;
    HRESULT itemResult_;
};

void PolicyTests(Runner& runner)
{
    runner.Run("completion.accepts_only_direct_png_results", [] {
        Require(Policy::IsSavedImageInFolder(L"D:\\한글 폴더 (1)", L"d:\\한글 폴더 (1)\\그림_20260925_120000_2.png"),
                "Valid direct-child result rejected");
        Require(Policy::IsSavedImageInFolder(L"C:\\", L"C:\\그림.png"), "Drive-root result rejected");
    });
    runner.Run("completion.rejects_other_folder_and_nested_results", [] {
        for (auto result : {L"C:\\fixture2\\image.png", L"C:\\fixture\\nested\\image.png",
                           L"D:\\fixture\\image.png", L"C:\\fixture\\..\\image.png",
                           L"C:\\fixture\\image.png:stream", L"C:\\fixture\\image.jpg",
                           L"C:\\fixture\\image.png\nC:\\elsewhere\\other.png", L"C:\\fixture\\.png"})
            Require(!Policy::IsSavedImageInFolder(L"C:\\fixture", result), "Untrusted completion destination accepted");
    });
    runner.Run("completion.rejects_invalid_folder_identity", [] {
        Require(!Policy::IsSavedImageInFolder(L"C:\\fixture\\", L"C:\\fixture\\image.png"), "Trailing separator alias accepted");
        Require(!Policy::IsSavedImageInFolder(L"\\\\server\\share", L"\\\\server\\share\\image.png"), "UNC result accepted");
        Require(!Policy::IsSavedImageInFolder(L"C:\\fixture", std::wstring(L"C:\\fixture\\im") + wchar_t(0) + L"age.png"), "Embedded NUL accepted");
    });
    runner.Run("policy.clipboard_format_flags", [] {
        for (unsigned int bits = 0; bits < 16; ++bits)
        {
            const Policy::ClipboardFormats formats{
                (bits & 1) != 0, (bits & 2) != 0, (bits & 4) != 0, (bits & 8) != 0};
            Require(Policy::HasSupportedImage(formats) == (bits != 0),
                    "Synthetic clipboard format flags misclassified");
        }
    });
    runner.Run("policy.supported_extensions", [] {
        for (auto value : {L"a.png", L"a.PNG", L"a.jpg", L"a.JpEg", L"a.bmp",
                           L"C:\\한글 폴더 (1)\\그림.JPEG", L"a.b.c.png"})
            Require(Policy::IsSupportedImageExtension(value), "Supported extension rejected");
    });
    runner.Run("policy.unsupported_extensions", [] {
        for (auto value : {L"", L"png", L"a.png.exe", L"a.png ", L"a.png.", L"a.webp",
                           L"a.gif", L"a.svg", L"a.tiff", L"a.pdf", L"a.png:stream",
                           L"C:\\folder.png\\file", L"C:\\folder.png\\", L"a.png\\child", L"a.png/child"})
            Require(!Policy::IsSupportedImageExtension(value), "Unsupported extension accepted");
    });
    runner.Run("policy.ordinary_absolute_paths", [] {
        for (auto value : {L"C:\\", L"z:\\a", L"D:\\한글 폴더 (1)\\그림.png",
                           L"C:\\a\\b", L"C:\\a..b\\file", L"C:\\a & b\\x"})
            Require(Policy::IsOrdinaryAbsolutePath(value), "Ordinary absolute path rejected");
    });
    runner.Run("policy.nonordinary_paths", [] {
        for (auto value : {L"", L"C:", L"C:relative", L"relative\\a", L"\\rooted",
                           L"\\\\server\\share", L"\\\\?\\C:\\a", L"\\\\.\\C:\\a",
                           L"C:/a", L"C:\\a/b", L"C:\\a\\", L"C:\\\\a", L"C:\\.\\a",
                           L"C:\\..\\a", L"C:\\a.\\b", L"C:\\a \\b", L"C:\\a:stream",
                           L"1:\\a", L"C:\\a\\..", L"C:\\a\\."})
            Require(!Policy::IsOrdinaryAbsolutePath(value), "Ambiguous path accepted");
    });
    runner.Run("policy.reserved_device_components", [] {
        for (auto component : {L"CON", L"con.png", L"NUL", L"aux.jpg", L"PRN",
                               L"COM1", L"com9.png", L"LPT1", L"lpt9.bmp",
                               L"COM¹", L"COM².png", L"LPT³", L"CONIN$", L"CONOUT$"})
        {
            Require(!Policy::IsOrdinaryAbsolutePath(L"C:\\" + std::wstring(component)),
                    "Reserved device basename accepted");
            Require(!Policy::IsOrdinaryAbsolutePath(L"C:\\" + std::wstring(component) + L"\\a.png"),
                    "Reserved device ancestor accepted");
        }
        for (auto component : {L"COM10", L"LPT10", L"console.png", L"auxiliary.jpg"})
            Require(Policy::IsOrdinaryAbsolutePath(L"C:\\" + std::wstring(component)),
                    "Ordinary basename rejected as device");
    });
    runner.Run("policy.path_reserved_characters", [] {
        for (wchar_t character : std::wstring(L"/:<>\"|?*"))
            Require(!Policy::IsOrdinaryAbsolutePath(L"C:\\a" + std::wstring(1, character) + L"b"),
                    "Reserved path character accepted");
    });
    runner.Run("policy.path_control_characters", [] {
        for (wchar_t character = 0; character < L' '; ++character)
            Require(!Policy::IsOrdinaryAbsolutePath(L"C:\\a" + std::wstring(1, character) + L"b"),
                    "Control path character accepted");
    });
    runner.Run("policy.path_length_boundary", [] {
        std::wstring value = L"C:\\" + std::wstring(Policy::MaximumPathCharacters - 3, L'a');
        Require(Policy::IsOrdinaryAbsolutePath(value), "Maximum syntax length rejected");
        value.push_back(L'a');
        Require(!Policy::IsOrdinaryAbsolutePath(value), "Overlong path accepted");
        // Pure syntax acceptance does not promise OS support for a component this long.
    });
    runner.Run("policy.path_component_boundary", [] {
        std::wstring value = L"C:\\a";
        for (std::size_t i = 1; i < Policy::MaximumPathComponents; ++i) value += L"\\a";
        Require(Policy::IsOrdinaryAbsolutePath(value), "Maximum component count rejected");
        value += L"\\a";
        Require(!Policy::IsOrdinaryAbsolutePath(value), "Excessive component count accepted");
    });
    runner.Run("policy.regular_file_attributes", [] {
        for (std::uint32_t attributes : {0u, 1u, 2u, 0x20u, 0x80u})
            Require(Policy::AreSupportedAttributes(attributes, false), "Ordinary file rejected");
        Require(!Policy::AreSupportedAttributes(Policy::DirectoryAttribute, false), "Directory as file");
    });
    runner.Run("policy.directory_attributes", [] {
        for (std::uint32_t flags : {0u, 1u, 2u, 0x20u})
            Require(Policy::AreSupportedAttributes(Policy::DirectoryAttribute | flags, true),
                    "Ordinary directory rejected");
        Require(!Policy::AreSupportedAttributes(0x80, true), "File accepted as directory");
    });
    runner.Run("policy.blocked_attributes", [] {
        for (std::uint32_t blocked : {0x40u, 0x400u, 0x1000u, 0x40000u, 0x400000u, 0xFFFFFFFFu})
        {
            Require(!Policy::AreSupportedAttributes(blocked, false), "Unsafe file accepted");
            Require(!Policy::AreSupportedAttributes(blocked | Policy::DirectoryAttribute, true),
                    "Unsafe directory accepted");
        }
    });
    runner.Run("policy.physical_volume_identity", [] {
        for (auto value : {L"\\Device\\HarddiskVolume1", L"\\Device\\HarddiskVolume123"})
            Require(Policy::IsPhysicalVolumeDevice(value), "Physical volume rejected");
        for (auto value : {L"", L"\\Device\\HarddiskVolume", L"\\Device\\HarddiskVolume1x",
                           L"\\Device\\HarddiskVolume1\\dir", L"\\??\\C:\\dir",
                           L"\\Device\\Mup\\server\\share", L"\\Device\\VirtualDisk1"})
            Require(!Policy::IsPhysicalVolumeDevice(value), "Alias/nonphysical volume accepted");
    });
    runner.Run("policy.argument_roundtrip", [] {
        const std::vector<std::wstring> values{
            L"", L"plain", L"two words", L"한글 폴더 (1)", L"\"", L"a\"b", L"\\",
            L"C:\\path with space\\", L"a\\\\\"b", L"tail\\\\",
            L"%TEMP% & calc | echo", L"$(example); 'example'", L"line\nbreak"};
        for (const auto& value : values)
        {
            std::wstring line = L"fixture.exe " + Policy::QuoteWindowsArgument(value);
            int count = 0;
            auto arguments = CommandLineToArgvW(line.c_str(), &count);
            Require(arguments != nullptr, "CommandLineToArgvW failed");
            bool matched = count == 2 && value == arguments[1];
            LocalFree(arguments);
            Require(matched, "Quoted argument did not roundtrip as one literal argument");
        }
    });
}

using GetClassObject = HRESULT(STDAPICALLTYPE*)(REFCLSID, REFIID, void**);
using CanUnloadNow = HRESULT(STDAPICALLTYPE*)();
class LoadedModule
{
public:
    explicit LoadedModule(const std::wstring& path) noexcept :
        value(LoadLibraryExW(path.c_str(), nullptr,
              LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32)) {}
    ~LoadedModule() { if (value) FreeLibrary(value); }
    HMODULE value;
};
template<class Function> Function Resolve(HMODULE module, const char* name) noexcept
{
    const FARPROC address = module ? GetProcAddress(module, name) : nullptr;
    static_assert(sizeof(Function) == sizeof(address), "Function pointer size mismatch");
    Function function = nullptr;
    std::memcpy(&function, &address, sizeof(function)); return function;
}
void RequireHidden(IExplorerCommand* command, IShellItemArray* selection, BOOL allowSlow = TRUE)
{
    Require(command != nullptr, "Command construction failed");
    EXPCMDSTATE state = ECS_ENABLED;
    Require(command->GetState(selection, allowSlow, &state) == S_OK, "GetState failed");
    Require(state == ECS_HIDDEN, "Unsupported context not completely hidden");
}
void CommandContractTests(Runner& runner, GetClassObject getClassObject, CanUnloadNow canUnload,
                          REFCLSID clsid, const char* prefix, const wchar_t* title)
{
    auto name = [prefix](const char* suffix) { return std::string(prefix) + suffix; };
    ComPtr<IClassFactory> factory;
    ComPtr<IExplorerCommand> command;
    auto needFactory = [&] { Require(getClassObject && factory.Get(), "Class factory unavailable"); };
    auto needCommand = [&] { Require(command.Get() != nullptr, "Explorer command unavailable"); };
    runner.Run(name(".factory_create"), [&] {
        Require(getClassObject != nullptr, "DllGetClassObject unavailable");
        Require(getClassObject(clsid, IID_IClassFactory,
                    reinterpret_cast<void**>(factory.Put())) == S_OK && factory.Get(), "No factory");
        Require(canUnload && canUnload() == S_FALSE, "Live factory did not pin DLL");
        Require(factory->CreateInstance(nullptr, IID_IExplorerCommand,
                    reinterpret_cast<void**>(command.Put())) == S_OK && command.Get(), "No command");
    });
    runner.Run(name(".factory_interfaces"), [&] {
        needFactory(); ComPtr<IUnknown> unknown; ComPtr<IClassFactory> again;
        Require(factory->QueryInterface(IID_IUnknown,
                    reinterpret_cast<void**>(unknown.Put())) == S_OK, "Factory lacks IUnknown");
        Require(unknown->QueryInterface(IID_IClassFactory,
                    reinterpret_cast<void**>(again.Put())) == S_OK, "Factory QI roundtrip failed");
        Require(factory.Get() == again.Get(), "Factory identity changed");
    });
    runner.Run(name(".factory_unknown_interface"), [&] {
        needFactory(); void* output = reinterpret_cast<void*>(1);
        Require(factory->QueryInterface(IID_IShellItem, &output) == E_NOINTERFACE && !output,
                "Factory accepted unsupported interface");
        Require(factory->QueryInterface(IID_IUnknown, nullptr) == E_POINTER, "Factory null QI output");
    });
    runner.Run(name(".factory_create_unknown_interface"), [&] {
        needFactory(); void* output = reinterpret_cast<void*>(1);
        Require(factory->CreateInstance(nullptr, IID_IShellItem, &output) == E_NOINTERFACE && !output,
                "CreateInstance accepted unsupported interface");
        Require(factory->CreateInstance(nullptr, IID_IExplorerCommand, nullptr) == E_POINTER,
                "CreateInstance null output not rejected");
    });
    runner.Run(name(".factory_no_aggregation"), [&] {
        needFactory(); ComPtr<Site> outer(new Site()); void* output = reinterpret_cast<void*>(1);
        Require(factory->CreateInstance(outer.Get(), IID_IExplorerCommand, &output)
                    == CLASS_E_NOAGGREGATION && !output, "Aggregation accepted");
    });
    runner.Run(name(".command_identity"), [&] {
        needCommand(); ComPtr<IUnknown> direct; ComPtr<IObjectWithSite> withSite; ComPtr<IUnknown> through;
        Require(command->QueryInterface(IID_IUnknown,
                    reinterpret_cast<void**>(direct.Put())) == S_OK, "Command lacks IUnknown");
        Require(command->QueryInterface(IID_IObjectWithSite,
                    reinterpret_cast<void**>(withSite.Put())) == S_OK, "Command lacks site interface");
        Require(withSite->QueryInterface(IID_IUnknown,
                    reinterpret_cast<void**>(through.Put())) == S_OK, "Site QI identity failed");
        Require(direct.Get() == through.Get(), "COM identity differs between interfaces");
    });
    runner.Run(name(".command_unknown_interface"), [&] {
        needCommand(); void* output = reinterpret_cast<void*>(1);
        Require(command->QueryInterface(IID_IShellItem, &output) == E_NOINTERFACE && !output,
                "Command accepted unsupported interface");
    });
    runner.Run(name(".title"), [&] {
        needCommand(); TaskText text;
        Require(command->GetTitle(nullptr, &text.value) == S_OK && text.value &&
                    std::wstring_view(text.value) == title, "Wrong command title");
    });
    runner.Run(name(".flags"), [&] {
        needCommand(); EXPCMDFLAGS flags = ECF_HASSUBCOMMANDS;
        Require(command->GetFlags(&flags) == S_OK && flags == ECF_DEFAULT, "Unexpected command flags");
    });
    runner.Run(name(".canonical_name"), [&] {
        needCommand(); GUID actual{};
        Require(command->GetCanonicalName(&actual) == S_OK && IsEqualGUID(actual, clsid),
                "Canonical identity differs from registered CLSID");
    });
    runner.Run(name(".no_icon_tooltip_subcommands"), [&] {
        needCommand(); TaskText icon; TaskText tooltip; ComPtr<IEnumExplorerCommand> children;
        Require(command->GetIcon(nullptr, &icon.value) == E_NOTIMPL && !icon.value, "Icon contract");
        Require(command->GetToolTip(nullptr, &tooltip.value) == E_NOTIMPL && !tooltip.value, "Tooltip contract");
        Require(command->EnumSubCommands(children.Put()) == E_NOTIMPL && !children.Get(), "Unexpected submenu");
    });
    runner.Run(name(".site_roundtrip"), [&] {
        needCommand(); ComPtr<IObjectWithSite> withSite;
        Require(command->QueryInterface(IID_IObjectWithSite,
                    reinterpret_cast<void**>(withSite.Put())) == S_OK, "No site interface");
        void* missing = reinterpret_cast<void*>(1);
        Require(withSite->GetSite(IID_IUnknown, &missing) == E_NOINTERFACE && !missing, "Unset site not hidden");
        ComPtr<Site> sentinel(new Site()); ComPtr<IUnknown> returned;
        Require(withSite->SetSite(sentinel.Get()) == S_OK, "SetSite failed");
        Require(withSite->GetSite(IID_IUnknown, reinterpret_cast<void**>(returned.Put())) == S_OK &&
                    returned.Get() == sentinel.Get(), "GetSite lost caller identity");
        Require(withSite->SetSite(sentinel.Get()) == S_OK, "Same-site replacement failed");
        void* unsupported = reinterpret_cast<void*>(1);
        Require(withSite->GetSite(IID_IShellItem, &unsupported) == E_NOINTERFACE && !unsupported, "Site QI contract");
        Require(withSite->SetSite(nullptr) == S_OK, "Site could not be cleared");
    });
    runner.Run(name(".site_reference_lifetime"), [&] {
        needFactory(); bool destroyed = false;
        ComPtr<Site> sentinel(new Site(&destroyed)); ComPtr<IObjectWithSite> temporary;
        Require(factory->CreateInstance(nullptr, IID_IObjectWithSite,
                    reinterpret_cast<void**>(temporary.Put())) == S_OK, "Cannot create site object");
        Require(temporary->SetSite(sentinel.Get()) == S_OK && sentinel->References() == 2, "SetSite reference");
        Require(temporary->SetSite(sentinel.Get()) == S_OK && sentinel->References() == 2, "Same-site reference leak");
        sentinel.Reset(); Require(!destroyed, "Site destroyed while command retained it");
        temporary.Reset(); Require(destroyed, "Command destruction did not release site");
    });
    runner.Run(name(".null_outputs"), [&] {
        needCommand();
        Require(command->QueryInterface(IID_IUnknown, nullptr) == E_POINTER, "QI null output");
        Require(command->GetTitle(nullptr, nullptr) == E_POINTER, "Title null output");
        Require(command->GetIcon(nullptr, nullptr) == E_POINTER, "Icon null output");
        Require(command->GetToolTip(nullptr, nullptr) == E_POINTER, "Tooltip null output");
        Require(command->GetCanonicalName(nullptr) == E_POINTER, "Canonical null output");
        Require(command->GetFlags(nullptr) == E_POINTER, "Flags null output");
        Require(command->EnumSubCommands(nullptr) == E_POINTER, "Subcommands null output");
        Require(command->GetState(nullptr, FALSE, nullptr) == E_POINTER, "State null output");
        ComPtr<IObjectWithSite> withSite;
        Require(command->QueryInterface(IID_IObjectWithSite,
                    reinterpret_cast<void**>(withSite.Put())) == S_OK, "No site interface");
        Require(withSite->GetSite(IID_IUnknown, nullptr) == E_POINTER, "Site null output");
    });
    runner.Run(name(".reference_lifetime"), [&] {
        needCommand(); auto added = command->AddRef(); auto released = command->Release();
        Require(added == released + 1, "Unbalanced reference counts");
        factory.Reset(); Require(canUnload && canUnload() == S_FALSE, "Live command did not pin DLL");
        command.Reset(); Require(canUnload() == S_OK, "Released factory/command still pin DLL");
    });
}
void StateBoundaryTests(Runner& runner, GetClassObject getClassObject)
{
    ComPtr<IClassFactory> copyFactory; ComPtr<IClassFactory> saveFactory;
    ComPtr<IExplorerCommand> copy; ComPtr<IExplorerCommand> save;
    if (getClassObject)
    {
        if (SUCCEEDED(getClassObject(CLSID_CopyImage, IID_IClassFactory,
                                    reinterpret_cast<void**>(copyFactory.Put()))))
            copyFactory->CreateInstance(nullptr, IID_IExplorerCommand, reinterpret_cast<void**>(copy.Put()));
        if (SUCCEEDED(getClassObject(CLSID_SaveImage, IID_IClassFactory,
                                    reinterpret_cast<void**>(saveFactory.Put()))))
            saveFactory->CreateInstance(nullptr, IID_IExplorerCommand, reinterpret_cast<void**>(save.Put()));
    }
    runner.Run("state.copy_null_selection", [&] {
        RequireHidden(copy.Get(), nullptr, FALSE); RequireHidden(copy.Get(), nullptr, TRUE);
    });
    runner.Run("state.copy_empty_selection", [&] {
        ComPtr<Selection> selection(new Selection(0));
        RequireHidden(copy.Get(), selection.Get(), FALSE); RequireHidden(copy.Get(), selection.Get(), TRUE);
        Require(selection->itemCalls == 0, "Empty selection read an item");
    });
    runner.Run("state.copy_multiple_selection", [&] {
        ComPtr<Selection> selection(new Selection(2));
        RequireHidden(copy.Get(), selection.Get(), FALSE); RequireHidden(copy.Get(), selection.Get(), TRUE);
        Require(selection->itemCalls == 0, "Multiple selection read an item");
    });
    runner.Run("state.copy_selection_count_failure", [&] {
        ComPtr<Selection> selection(new Selection(1, nullptr, E_FAIL));
        RequireHidden(copy.Get(), selection.Get(), FALSE); RequireHidden(copy.Get(), selection.Get(), TRUE);
        Require(selection->itemCalls == 0, "Failed count read an item");
    });
    runner.Run("state.copy_fast_path_deferred", [&] {
        Require(copy.Get() != nullptr, "No copy command");
        ComPtr<ShellItem> item(new ShellItem(L"C:\\unused.png", SFGAO_FILESYSTEM));
        ComPtr<Selection> selection(new Selection(1, item.Get())); EXPCMDSTATE state = ECS_ENABLED;
        Require(copy->GetState(selection.Get(), FALSE, &state) == E_PENDING && state == ECS_HIDDEN,
                "Slow validation was not deferred with hidden default");
        Require(selection->itemCalls == 0 && item->nameCalls == 0, "Fast path traversed an item");
    });
    runner.Run("state.copy_null_item", [&] {
        ComPtr<Selection> selection(new Selection(1)); RequireHidden(copy.Get(), selection.Get());
    });
    runner.Run("state.copy_item_failure", [&] {
        ComPtr<Selection> selection(new Selection(1, nullptr, S_OK, E_ACCESSDENIED));
        RequireHidden(copy.Get(), selection.Get());
    });
    runner.Run("state.copy_unsupported_item_attributes", [&] {
        for (SFGAOF attributes : {static_cast<SFGAOF>(0),
                 static_cast<SFGAOF>(SFGAO_FILESYSTEM | SFGAO_FOLDER),
                 static_cast<SFGAOF>(SFGAO_FILESYSTEM | SFGAO_LINK)})
        {
            ComPtr<ShellItem> item(new ShellItem(L"C:\\unused.png", attributes));
            ComPtr<Selection> selection(new Selection(1, item.Get()));
            RequireHidden(copy.Get(), selection.Get());
            Require(item->nameCalls == 0, "Unsupported attributes requested filesystem path");
        }
    });
    runner.Run("state.copy_invalid_or_unavailable_path", [&] {
        for (auto value : {L"", L"relative.png", L"\\\\server\\share\\image.png", L"C:\\folder\\..\\image.png"})
        {
            ComPtr<ShellItem> item(new ShellItem(value, SFGAO_FILESYSTEM));
            ComPtr<Selection> selection(new Selection(1, item.Get())); RequireHidden(copy.Get(), selection.Get());
        }
        ComPtr<ShellItem> denied(new ShellItem(L"C:\\unused.png", SFGAO_FILESYSTEM, E_ACCESSDENIED));
        ComPtr<Selection> selection(new Selection(1, denied.Get())); RequireHidden(copy.Get(), selection.Get());
    });
    runner.Run("state.save_without_caller_site", [&] {
        // This save object never receives SetSite. Context fails before all clipboard APIs.
        RequireHidden(save.Get(), nullptr, FALSE); RequireHidden(save.Get(), nullptr, TRUE);
        ComPtr<Selection> unrelated(new Selection(1)); RequireHidden(save.Get(), unrelated.Get());
        Require(unrelated->itemCalls == 0, "Save used selection as caller folder");
    });
}
void DllTests(Runner& runner, const std::wstring& dllPath)
{
    LoadedModule module(dllPath);
    auto getClassObject = Resolve<GetClassObject>(module.value, "DllGetClassObject");
    auto canUnload = Resolve<CanUnloadNow>(module.value, "DllCanUnloadNow");
    runner.Run("module.absolute_load", [&] {
        Require(module.value != nullptr, "Absolute-path LoadLibraryExW failed");
    });
    runner.Run("module.exports", [&] {
        Require(getClassObject && canUnload, "Required COM exports missing");
        Require(!GetProcAddress(module.value, "DllRegisterServer") &&
                !GetProcAddress(module.value, "DllUnregisterServer"), "Unexpected self-registration exports");
    });
    runner.Run("module.initially_unloadable", [&] {
        Require(canUnload && canUnload() == S_OK, "Fresh DLL is pinned");
    });
    runner.Run("factory.unknown_class", [&] {
        Require(getClassObject != nullptr, "DllGetClassObject unavailable"); void* out = reinterpret_cast<void*>(1);
        Require(getClassObject(GUID_NULL, IID_IClassFactory, &out) == CLASS_E_CLASSNOTAVAILABLE && !out,
                "Unknown CLSID accepted");
    });
    runner.Run("factory.null_output", [&] {
        Require(getClassObject != nullptr, "DllGetClassObject unavailable");
        Require(getClassObject(CLSID_SaveImage, IID_IClassFactory, nullptr) == E_POINTER, "Null factory output");
    });
    runner.Run("factory.unsupported_interface", [&] {
        Require(getClassObject != nullptr, "DllGetClassObject unavailable"); void* out = reinterpret_cast<void*>(1);
        Require(getClassObject(CLSID_SaveImage, IID_IShellItem, &out) == E_NOINTERFACE && !out, "Factory interface");
        Require(canUnload && canUnload() == S_OK, "Failed factory lookup leaked object");
    });
    runner.Run("factory.server_lock_balance", [&] {
        Require(getClassObject && canUnload, "COM exports unavailable"); ComPtr<IClassFactory> factory;
        Require(getClassObject(CLSID_CopyImage, IID_IClassFactory,
                    reinterpret_cast<void**>(factory.Put())) == S_OK, "No lock-test factory");
        Require(factory->LockServer(FALSE) == E_UNEXPECTED, "Unmatched unlock accepted");
        Require(factory->LockServer(TRUE) == S_OK, "Server lock failed");
        factory.Reset(); auto pinned = canUnload(); ComPtr<IClassFactory> unlocker;
        Require(getClassObject(CLSID_CopyImage, IID_IClassFactory,
                    reinterpret_cast<void**>(unlocker.Put())) == S_OK && unlocker.Get(), "No unlock factory");
        auto unlocked = unlocker->LockServer(FALSE); unlocker.Reset();
        Require(pinned == S_FALSE && unlocked == S_OK && canUnload() == S_OK, "Server lock lifetime");
    });
    CommandContractTests(runner, getClassObject, canUnload, CLSID_SaveImage, "save", L"복사한 그림 저장");
    CommandContractTests(runner, getClassObject, canUnload, CLSID_CopyImage, "copy", L"그림으로 복사");
    StateBoundaryTests(runner, getClassObject);
    runner.Run("module.finally_unloadable", [&] {
        Require(canUnload && canUnload() == S_OK, "Tests left a COM object/server lock alive");
    });
}
std::string JsonEscape(const std::string& value)
{
    std::string output; constexpr char hex[] = "0123456789abcdef";
    for (unsigned char character : value)
    {
        if (character == '"' || character == '\\')
        { output.push_back('\\'); output.push_back(static_cast<char>(character)); }
        else if (character < 0x20)
        { output += "\\u00"; output.push_back(hex[character >> 4]); output.push_back(hex[character & 15]); }
        else output.push_back(static_cast<char>(character));
    }
    return output;
}
bool WriteReport(const std::wstring& reportPath, const Runner& runner)
{
    std::size_t passed = 0;
    for (const auto& result : runner.results) if (result.passed) ++passed;
    std::string json = "{\n  \"schemaVersion\": 1,\n"
        "  \"scope\": \"native-policy-and-com-boundary-only\",\n"
        "  \"clipboardAccess\": false,\n  \"commandInvoked\": false,\n"
        "  \"comRegistered\": false,\n  \"explorerTested\": false,\n"
        "  \"acceptanceTestStatus\": \"NOT RUN\",\n"
        "  \"total\": " + std::to_string(runner.results.size()) +
        ",\n  \"passed\": " + std::to_string(passed) +
        ",\n  \"failed\": " + std::to_string(runner.results.size() - passed) + ",\n  \"tests\": [\n";
    for (std::size_t index = 0; index < runner.results.size(); ++index)
    {
        const auto& result = runner.results[index];
        json += "    {\"name\": \"" + JsonEscape(result.name) + "\", \"passed\": " +
            (result.passed ? "true" : "false") + ", \"detail\": \"" + JsonEscape(result.detail) + "\"}";
        json += index + 1 == runner.results.size() ? "\n" : ",\n";
    }
    json += "  ]\n}\n";
    // Refuse replacement of previous results. Caller supplies a new owned report path.
    HANDLE file = CreateFileW(reportPath.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    bool ok = json.size() <= MAXDWORD &&
        WriteFile(file, json.data(), static_cast<DWORD>(json.size()), &written, nullptr) &&
        written == json.size() && FlushFileBuffers(file);
    CloseHandle(file); return ok;
}
}
int wmain(int argc, wchar_t* argv[])
{
    std::wstring dllPath; std::wstring reportPath;
    for (int i = 1; i < argc; ++i)
    {
        std::wstring_view option(argv[i]);
        if ((option != L"--dll" && option != L"--report") || i + 1 >= argc)
        {
            std::cerr << "Usage: ImageCopySave.Shell.Tests.exe --dll <absolute DLL> --report <new absolute JSON>\n";
            return 2;
        }
        auto& destination = option == L"--dll" ? dllPath : reportPath;
        if (!destination.empty()) { std::cerr << "Duplicate argument.\n"; return 2; }
        destination = argv[++i];
    }
    if (!Policy::IsOrdinaryAbsolutePath(dllPath) || !Policy::IsOrdinaryAbsolutePath(reportPath) ||
        dllPath == reportPath)
    { std::cerr << "DLL and new report must be distinct ordinary absolute drive paths.\n"; return 2; }
    Runner runner; PolicyTests(runner); DllTests(runner, dllPath);
    std::size_t failed = 0;
    for (const auto& result : runner.results)
    {
        std::cout << (result.passed ? "PASS " : "FAIL ") << result.name;
        if (!result.detail.empty()) std::cout << ": " << result.detail;
        std::cout << "\n"; if (!result.passed) ++failed;
    }
    if (!WriteReport(reportPath, runner))
    {
        std::cerr << "Cannot create new JSON report; parent must exist and report must not exist.\n";
        return 2;
    }
    std::cout << "Native boundary tests: " << runner.results.size() << ", failed: " << failed
              << ". Explorer/clipboard/invocation/installation/AT-01..AT-44: NOT RUN.\n";
    return failed == 0 ? 0 : 1;
}
