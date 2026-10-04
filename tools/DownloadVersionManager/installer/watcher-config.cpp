#include <windows.h>
#include <msiquery.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <string>

namespace {
std::wstring property(MSIHANDLE session, const wchar_t* name) {
    DWORD length = 0;
    wchar_t empty = L'\0';
    const UINT initial = MsiGetPropertyW(session, name, &empty, &length);
    if (initial != ERROR_MORE_DATA && initial != ERROR_SUCCESS) return {};
    std::wstring value(static_cast<size_t>(length) + 1, L'\0');
    ++length;
    if (MsiGetPropertyW(session, name, value.data(), &length) != ERROR_SUCCESS) return {};
    value.resize(length);
    return value;
}
}

extern "C" __declspec(dllexport) UINT __stdcall DvmResolveDownloads(MSIHANDLE session) {
    for (const auto* name : {L"DVMFOLLOWDOWNLOADS", L"DVMSTARTATLOGIN"}) {
        const std::wstring value = property(session, name);
        const bool checked = value == L"1" || value == L"#1";
        if (MsiSetPropertyW(session, name, checked ? L"1" : L"") != ERROR_SUCCESS) return ERROR_INSTALL_FAILURE;
        const std::wstring number = std::wstring(name) + L"INT";
        if (MsiSetPropertyW(session, number.c_str(), checked ? L"1" : L"0") != ERROR_SUCCESS) return ERROR_INSTALL_FAILURE;
    }
    PWSTR path = nullptr;
    const HRESULT result = SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr, &path);
    if (FAILED(result) || !path) return ERROR_INSTALL_FAILURE;
    const UINT set = MsiSetPropertyW(session, L"DVMDOWNLOADSFOLDER", path);
    UINT selected = ERROR_SUCCESS;
    if (property(session, L"DVMFOLLOWDOWNLOADS") == L"1" || property(session, L"DVMWATCHFOLDER").empty()) selected = MsiSetPropertyW(session, L"DVMWATCHFOLDER", path);
    CoTaskMemFree(path);
    return set == ERROR_SUCCESS && selected == ERROR_SUCCESS ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE;
}

extern "C" __declspec(dllexport) UINT __stdcall DvmBrowseFolder(MSIHANDLE session) {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) return ERROR_INSTALL_FAILURE;
    IFileDialog* dialog = nullptr;
    HRESULT result = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    if (SUCCEEDED(result)) {
        DWORD options = 0;
        result = dialog->GetOptions(&options);
        if (SUCCEEDED(result)) result = dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
        if (SUCCEEDED(result)) result = dialog->SetTitle(L"감시할 폴더 선택");
        IShellItem* current = nullptr;
        const std::wstring selected = property(session, L"DVMWATCHFOLDER");
        if (SUCCEEDED(SHCreateItemFromParsingName(selected.c_str(), nullptr, IID_PPV_ARGS(&current)))) {
            dialog->SetFolder(current);
            current->Release();
        }
        if (SUCCEEDED(result)) result = dialog->Show(GetActiveWindow());
        if (SUCCEEDED(result)) {
            IShellItem* item = nullptr;
            result = dialog->GetResult(&item);
            if (SUCCEEDED(result)) {
                PWSTR path = nullptr;
                result = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
                if (SUCCEEDED(result)) {
                    if (MsiSetPropertyW(session, L"DVMWATCHFOLDER", path) != ERROR_SUCCESS || MsiSetPropertyW(session, L"DVMFOLLOWDOWNLOADS", L"") != ERROR_SUCCESS) result = E_FAIL;
                    CoTaskMemFree(path);
                }
                item->Release();
            }
        }
        dialog->Release();
    }
    if (SUCCEEDED(initialized)) CoUninitialize();
    if (result == HRESULT_FROM_WIN32(ERROR_CANCELLED)) return ERROR_SUCCESS;
    return SUCCEEDED(result) ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE;
}
