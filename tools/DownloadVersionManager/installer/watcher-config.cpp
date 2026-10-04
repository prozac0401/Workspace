#include <windows.h>
#include <msiquery.h>
#include <shlobj.h>
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
