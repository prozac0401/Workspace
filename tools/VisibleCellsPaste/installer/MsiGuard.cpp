#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <tlhelp32.h>
#include <msi.h>
#include <msiquery.h>
#include <bcrypt.h>
#include <algorithm>
#include <string>
#include <vector>
#include <stdexcept>
#include "MsiIdentity.h"

// Read-only guard. File/registry installation, removal and rollback belong to
// standard Windows Installer actions, not to this custom action.
namespace vcp {
struct Failure { std::wstring message; };
[[noreturn]] void Fail(const std::wstring& text) { throw Failure{text}; }
bool Missing(DWORD error) { return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND; }
bool Equal(const std::wstring& a, const std::wstring& b) { return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL; }
struct Handle {
    HANDLE value;
    explicit Handle(HANDLE h) : value(h) {}
    ~Handle() { if (value != INVALID_HANDLE_VALUE && value != nullptr) CloseHandle(value); }
    Handle(const Handle&) = delete;
};
struct Reg { HKEY value = nullptr; ~Reg() { if (value) RegCloseKey(value); } };
struct Value { bool exists = false; DWORD type = 0; std::wstring text; };
Value ReadValue(HKEY hive, REGSAM view, const std::wstring& key, const std::wstring& name) {
    // MSI hosts custom actions in a service process while impersonating the
    // installing user. The predefined HKCU handle may have been cached for the
    // process account; resolve the thread's current user explicitly every time.
    Reg currentUser;
    if (hive == HKEY_CURRENT_USER) {
        if (RegOpenCurrentUser(KEY_READ, &currentUser.value) != ERROR_SUCCESS) Fail(L"현재 설치 사용자의 등록을 확인할 수 없습니다.");
        hive = currentUser.value;
    }
    Reg opened; LONG status = RegOpenKeyExW(hive, key.c_str(), 0, KEY_QUERY_VALUE | view, &opened.value);
    if (Missing(status)) return {};
    if (status != ERROR_SUCCESS) Fail(L"설치 등록을 읽을 수 없습니다. 변경하지 않았습니다.");
    DWORD type = 0, size = 0;
    status = RegQueryValueExW(opened.value, name.c_str(), nullptr, &type, nullptr, &size);
    if (Missing(status)) return {};
    if (status != ERROR_SUCCESS || size > 65536) Fail(L"설치 등록 값의 범위를 확인할 수 없습니다.");
    std::vector<BYTE> bytes(size + sizeof(wchar_t), 0);
    status = RegQueryValueExW(opened.value, name.c_str(), nullptr, &type, bytes.data(), &size);
    if (status != ERROR_SUCCESS) Fail(L"설치 등록을 읽는 동안 변경되었습니다.");
    Value result; result.exists = true; result.type = type;
    if (type == REG_DWORD && size == sizeof(DWORD)) result.text = std::to_wstring(*reinterpret_cast<DWORD*>(bytes.data()));
    else if ((type == REG_SZ || type == REG_EXPAND_SZ) && size % 2 == 0) result.text = reinterpret_cast<wchar_t*>(bytes.data());
    else result.text = L"<unsupported registry type>";
    return result;
}
bool KeyExists(HKEY hive, REGSAM view, const std::wstring& key) {
    Reg currentUser;
    if (hive == HKEY_CURRENT_USER) {
        if (RegOpenCurrentUser(KEY_READ, &currentUser.value) != ERROR_SUCCESS) Fail(L"현재 설치 사용자의 등록을 확인할 수 없습니다.");
        hive = currentUser.value;
    }
    Reg opened; LONG status = RegOpenKeyExW(hive, key.c_str(), 0, KEY_QUERY_VALUE | view, &opened.value);
    if (Missing(status)) return false;
    if (status != ERROR_SUCCESS) Fail(L"기존 제품 등록을 확인할 수 없습니다.");
    return true;
}
std::wstring Property(MSIHANDLE session, const wchar_t* name) {
    DWORD size = 0; wchar_t empty = 0;
    UINT status = MsiGetPropertyW(session, name, &empty, &size);
    if (status != ERROR_SUCCESS && status != ERROR_MORE_DATA) Fail(L"설치 속성을 읽을 수 없습니다.");
    if (size > 32768) Fail(L"설치 속성이 너무 깁니다.");
    std::vector<wchar_t> buffer(size + 1); ++size;
    if (MsiGetPropertyW(session, name, buffer.data(), &size) != ERROR_SUCCESS) Fail(L"설치 속성을 읽을 수 없습니다.");
    return buffer.data();
}
std::wstring FullPath(const std::wstring& path) {
    if (path.size() < 4 || path.size() > 240 || path[1] != L':' || path[2] != L'\\') Fail(L"설치 위치는 로컬 드라이브의 하위 폴더여야 합니다.");
    for (size_t i = 0; i < path.size(); ++i) {
        if (path[i] < L' ' || path[i] == L'|' || path[i] == L'/' || (i != 1 && path[i] == L':')) Fail(L"설치 경로에 허용되지 않는 문자가 있습니다.");
        if (i > 3 && path[i] == L'\\' && (path[i-1] == L'.' || path[i-1] == L' ')) Fail(L"모호한 설치 경로를 사용할 수 없습니다.");
    }
    if (path.back() == L'.' || path.back() == L' ') Fail(L"모호한 설치 경로를 사용할 수 없습니다.");
    wchar_t buffer[32768]; DWORD size = GetFullPathNameW(path.c_str(), 32768, buffer, nullptr);
    if (!size || size >= 32768) Fail(L"설치 위치를 확인할 수 없습니다.");
    std::wstring result(buffer); while (result.size() > 3 && result.back() == L'\\') result.pop_back();
    if (result.size() < 4) Fail(L"드라이브 루트에는 설치할 수 없습니다.");
    // Reject ambiguous Win32 trailing dots/spaces and explicit traversal.
    size_t at = 3;
    while (at <= result.size()) {
        size_t end = result.find(L'\\', at); if (end == std::wstring::npos) end = result.size();
        std::wstring part = result.substr(at, end - at);
        if (part.empty() || part.back() == L'.' || part.back() == L' ') Fail(L"모호한 설치 경로를 사용할 수 없습니다.");
        at = end + 1;
    }
    for (std::wstring current = result; current.size() > 3;) {
        DWORD attributes = GetFileAttributesW(current.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES) { if (!Missing(GetLastError())) Fail(L"설치 폴더를 검사할 수 없습니다."); }
        else if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) || !(attributes & FILE_ATTRIBUTE_DIRECTORY)) Fail(L"연결된 폴더 또는 파일 경로에는 설치할 수 없습니다.");
        size_t end = current.find_last_of(L'\\'); if (end < 3) break; current.resize(end);
    }
    return result;
}
std::wstring CodeBase(const std::wstring& root) {
    std::wstring result = L"file:///" + root + L"\\VisibleCellsPaste.AddIn.dll";
    std::replace(result.begin(), result.end(), L'\\', L'/'); return result;
}
void CheckMaintenanceLocation(const std::wstring& root) {
    if (MsiQueryProductStateW(VcpProductCode) != INSTALLSTATE_DEFAULT) Fail(L"Windows Installer에서 현재 사용자 설치 상태를 확인할 수 없습니다.");
    DWORD size = 0; wchar_t empty = 0;
    UINT status = MsiGetProductInfoW(VcpProductCode, INSTALLPROPERTY_INSTALLLOCATION, &empty, &size);
    if ((status != ERROR_MORE_DATA && status != ERROR_SUCCESS) || !size || size > 32768) Fail(L"Windows Installer의 기존 설치 위치를 확인할 수 없습니다.");
    std::vector<wchar_t> value(size+1); ++size;
    if (MsiGetProductInfoW(VcpProductCode, INSTALLPROPERTY_INSTALLLOCATION, value.data(), &size) != ERROR_SUCCESS || !Equal(FullPath(value.data()),root))
        Fail(L"기존 설치 위치 등록이 변경되었습니다. 파일과 등록을 보존하기 위해 중단했습니다.");
}
void ExcelClosed() {
    Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
    if (snapshot.value == INVALID_HANDLE_VALUE) Fail(L"실행 중인 Excel을 확인할 수 없습니다.");
    PROCESSENTRY32W item{}; item.dwSize = sizeof(item);
    if (!Process32FirstW(snapshot.value, &item)) Fail(L"실행 중인 프로세스를 확인할 수 없습니다.");
    do { if (Equal(item.szExeFile, L"EXCEL.EXE")) Fail(L"Excel이 실행 중입니다. 작업을 저장하고 모든 Excel 창을 닫은 뒤 다시 실행해 주세요. Excel을 강제 종료하지 않았습니다."); }
    while (Process32NextW(snapshot.value, &item));
    if (GetLastError() != ERROR_NO_MORE_FILES) Fail(L"실행 중인 Excel 검사를 마치지 못했습니다.");
}
USHORT PeMachine(const std::wstring& path) {
    Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (file.value == INVALID_HANDLE_VALUE) return 0;
    IMAGE_DOS_HEADER dos{}; DWORD read = 0;
    if (!ReadFile(file.value, &dos, sizeof(dos), &read, nullptr) || read != sizeof(dos) || dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < 0) return 0;
    LARGE_INTEGER size{}; if (!GetFileSizeEx(file.value, &size) || dos.e_lfanew > size.QuadPart - 6) return 0;
    LARGE_INTEGER offset{}; offset.QuadPart = dos.e_lfanew;
    if (!SetFilePointerEx(file.value, offset, nullptr, FILE_BEGIN)) return 0;
    DWORD signature = 0; WORD machine = 0;
    if (!ReadFile(file.value, &signature, 4, &read, nullptr) || read != 4 || signature != IMAGE_NT_SIGNATURE) return 0;
    if (!ReadFile(file.value, &machine, 2, &read, nullptr) || read != 2) return 0;
    return machine;
}
void RuntimeAndExcel() {
    Value runtime = ReadValue(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY, L"SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full", L"Release");
    if (!runtime.exists || runtime.type != REG_DWORD || wcstoul(runtime.text.c_str(), nullptr, 10) < 528040) Fail(L".NET Framework 4.8 이상이 필요합니다. Windows/조직의 승인된 설치 절차로 준비해 주세요.");
    bool found = false;
    for (REGSAM view : { KEY_WOW64_64KEY, KEY_WOW64_32KEY }) {
        for (HKEY hive : { HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE }) {
            Value excel = ReadValue(hive, view, L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\excel.exe", L"");
            if (!excel.exists || (excel.type != REG_SZ && excel.type != REG_EXPAND_SZ)) continue;
            std::wstring path = excel.text;
            if (path.size() >= 2 && path.front() == L'"' && path.back() == L'"') path = path.substr(1, path.size() - 2);
            wchar_t expanded[32768]; DWORD length = ExpandEnvironmentStringsW(path.c_str(), expanded, 32768);
            if (!length || length > 32768) continue;
            USHORT machine = PeMachine(expanded); if (!machine) continue;
            if (machine != VcpMachine) Fail(L"Excel 비트 수와 설치 파일이 다릅니다. Excel 32비트는 x86 MSI, Excel 64비트는 x64 MSI를 사용해 주세요.");
            found = true;
        }
    }
    if (!found) Fail(L"지원하는 Windows 데스크톱 Excel 설치와 비트 수를 확인할 수 없습니다.");
}
std::wstring Sha256(HANDLE file) {
    BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_HASH_HANDLE hash = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) Fail(L"설치 파일 해시 검사를 시작할 수 없습니다.");
    DWORD objectLength = 0, count = 0; std::vector<BYTE> object; std::wstring result;
    try {
        if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<BYTE*>(&objectLength), sizeof(objectLength), &count, 0) < 0) Fail(L"해시 메모리 크기 확인 실패");
        object.resize(objectLength);
        if (BCryptCreateHash(algorithm, &hash, object.data(), objectLength, nullptr, 0, 0) < 0) Fail(L"해시 생성 실패");
        BYTE buffer[65536]; DWORD read = 0;
        do { if (!ReadFile(file, buffer, sizeof(buffer), &read, nullptr)) Fail(L"설치 파일을 읽을 수 없습니다."); if (read && BCryptHashData(hash, buffer, read, 0) < 0) Fail(L"해시 계산 실패"); } while (read);
        BYTE digest[32]; if (BCryptFinishHash(hash, digest, sizeof(digest), 0) < 0) Fail(L"해시 완료 실패");
        constexpr wchar_t hex[] = L"0123456789abcdef";
        for (BYTE b : digest) { result += hex[b >> 4]; result += hex[b & 15]; }
    } catch (...) { if (hash) BCryptDestroyHash(hash); BCryptCloseAlgorithmProvider(algorithm, 0); throw; }
    BCryptDestroyHash(hash); BCryptCloseAlgorithmProvider(algorithm, 0); return result;
}
void CheckFile(const std::wstring& path, const std::wstring& expected, bool installed) {
    FullPath(path.substr(0,path.find_last_of(L'\\')));
    DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) { if (Missing(GetLastError())) return; Fail(L"설치 파일을 검사할 수 없습니다."); }
    if (!installed) Fail(L"기존 파일을 덮어쓰지 않도록 설치를 중단했습니다. 설치 위치의 기존 제품 파일을 확인해 주세요.");
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) || (attributes & FILE_ATTRIBUTE_DIRECTORY)) Fail(L"외부에서 변경한 설치 파일 경로를 보존하기 위해 중단했습니다.");
    Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    if (file.value == INVALID_HANDLE_VALUE) Fail(L"잠기거나 접근할 수 없는 설치 파일을 보존하기 위해 중단했습니다.");
    BY_HANDLE_FILE_INFORMATION info{};
    if (!GetFileInformationByHandle(file.value, &info) || info.nNumberOfLinks != 1 || (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) Fail(L"연결되거나 변경된 설치 파일을 보존하기 위해 중단했습니다.");
    // MSI deletes alternate streams with their file; do not discard external streams.
    WIN32_FIND_STREAM_DATA stream{}; HANDLE streams = FindFirstStreamW(path.c_str(), FindStreamInfoStandard, &stream, 0);
    if (streams == INVALID_HANDLE_VALUE) { if (GetLastError() != ERROR_HANDLE_EOF) Fail(L"설치 파일 스트림을 확인할 수 없습니다."); }
    else {
        bool external = false;
        do { if (wcscmp(stream.cStreamName, L"::$DATA") != 0) external = true; } while (FindNextStreamW(streams, &stream));
        DWORD last = GetLastError(); FindClose(streams);
        if (last != ERROR_HANDLE_EOF || external) Fail(L"추가 스트림이 있는 설치 파일을 보존하기 위해 중단했습니다.");
    }
    if (!Equal(Sha256(file.value), expected)) Fail(L"외부에서 변경한 프로그램 파일을 보존하기 위해 중단했습니다. 파일을 별도 보관하고 원래 파일로 복원한 뒤 다시 실행해 주세요.");
}
struct Registration { std::wstring key, name, value; DWORD type = REG_SZ; };
std::vector<Registration> Registrations(const std::wstring& root) {
    std::wstring cls = L"Software\\Classes\\CLSID\\{856B2219-6225-42ED-8FF1-2D06E5913AC8}";
    std::wstring prog = L"Software\\Classes\\Workspace.VisibleCellsPaste";
    std::wstring addin = L"Software\\Microsoft\\Office\\Excel\\Addins\\Workspace.VisibleCellsPaste";
    std::vector<Registration> result = {{cls,L"",L"VisibleCellsPaste.AddIn"},{cls+L"\\ProgId",L"",L"Workspace.VisibleCellsPaste"},{prog,L"",L"VisibleCellsPaste.AddIn"},{prog+L"\\CLSID",L"",L"{856B2219-6225-42ED-8FF1-2D06E5913AC8}"}};
    for (std::wstring sub : { cls+L"\\InprocServer32", cls+L"\\InprocServer32\\"+VcpAssemblyVersion }) {
        result.push_back({sub,L"Class",L"VisibleCellsPaste.AddIn"});
        result.push_back({sub,L"Assembly",VcpAssemblyIdentity});
        result.push_back({sub,L"RuntimeVersion",L"v4.0.30319"}); result.push_back({sub,L"CodeBase",CodeBase(root)});
    }
    result.push_back({cls+L"\\InprocServer32",L"",L"mscoree.dll"}); result.push_back({cls+L"\\InprocServer32",L"ThreadingModel",L"Both"});
    result.push_back({addin,L"FriendlyName",L"보이는 칸 붙여넣기"}); result.push_back({addin,L"Description",L"선택 범위 안의 보이는 칸에 복사한 값만 순서대로 입력합니다."}); result.push_back({addin,L"LoadBehavior",L"3",REG_DWORD});
    result.push_back({L"Software\\Workspace\\VisibleCellsPasteMsi",L"ProductCode",VcpProductCode});
    result.push_back({L"Software\\Workspace\\VisibleCellsPasteMsi",L"InstallFolder",root+L"\\"});
    result.push_back({L"Software\\Workspace\\VisibleCellsPasteMsi",L"Architecture",VcpArchitecture});
    for (const auto& file : VcpFiles) result.push_back({L"Software\\Workspace\\VisibleCellsPasteMsi\\Files",file.name,file.sha256});
    return result;
}
void Guard(const std::wstring& input, bool installed, bool remove) {
    ExcelClosed(); const std::wstring root = FullPath(input);
    if (!remove) RuntimeAndExcel();
    if (KeyExists(HKEY_CURRENT_USER, KEY_WOW64_32KEY, L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Workspace.VisibleCellsPaste") ||
        ReadValue(HKEY_CURRENT_USER, KEY_WOW64_32KEY, L"Software\\VisibleCellsPaste", L"Owner").exists)
        Fail(L"기존 ZIP/Setup 설치가 있습니다. Excel을 닫고 Windows 설정의 설치된 앱에서 기존 보이는 칸 붙여넣기를 먼저 제거한 뒤 MSI를 설치해 주세요. 기존 설치를 변경하지 않았습니다.");
    REGSAM view = VcpMachine == IMAGE_FILE_MACHINE_AMD64 ? KEY_WOW64_64KEY : KEY_WOW64_32KEY;
    REGSAM other = VcpMachine == IMAGE_FILE_MACHINE_AMD64 ? KEY_WOW64_32KEY : KEY_WOW64_64KEY;
    SYSTEM_INFO system{}; GetNativeSystemInfo(&system);
    if (system.wProcessorArchitecture != PROCESSOR_ARCHITECTURE_INTEL && KeyExists(HKEY_CURRENT_USER, other, L"Software\\Classes\\CLSID\\{856B2219-6225-42ED-8FF1-2D06E5913AC8}"))
        Fail(L"다른 비트 수의 기존 제품 등록이 있습니다. 기존 제품을 먼저 제거해 주세요.");
    if (installed) {
        // Immediate preflight independently verifies MSI identity/location and
        // attests these parameters through private CustomActionData. Deferred
        // execution cannot query product state while MSI is unpublishing it.
        // A missing marker after an interrupted install is allowed; a present
        // conflict and any changed remaining file/value are always rejected.
        Value owner = ReadValue(HKEY_CURRENT_USER, view, L"Software\\Workspace\\VisibleCellsPasteMsi", L"ProductCode");
        if (owner.exists && (owner.type != REG_SZ || !Equal(owner.text, VcpProductCode))) Fail(L"현재 MSI 설치 소유권을 확인할 수 없습니다. 기존 파일과 등록을 보존했습니다.");
    }
    for (const auto& item : Registrations(root)) {
        Value current = ReadValue(HKEY_CURRENT_USER, view, item.key, item.name);
        if (!current.exists) continue;
        if (!installed) Fail(L"기존 제품 등록이 있습니다. Windows 설정에서 기존 보이는 칸 붙여넣기를 먼저 제거해 주세요. 기존 등록은 변경하지 않았습니다.");
        if (current.type != item.type || current.text != item.value) Fail(L"외부에서 변경한 등록 또는 추가 기능 로드 설정을 보존하기 위해 중단했습니다. 변경한 값을 확인한 뒤 다시 실행해 주세요.");
    }
    for (const auto& item : VcpFiles) CheckFile(root+L"\\"+item.name, item.sha256, installed);
    ExcelClosed();
}
UINT Report(MSIHANDLE session, const std::wstring& message) {
    MSIHANDLE record = MsiCreateRecord(1);
    if (record) { MsiRecordSetStringW(record, 0, L"[1]"); MsiRecordSetStringW(record, 1, message.c_str()); MsiProcessMessage(session, INSTALLMESSAGE_ERROR, record); MsiCloseHandle(record); }
    return ERROR_INSTALL_FAILURE;
}
}

extern "C" UINT __stdcall VcpPreflight(MSIHANDLE session) {
    try {
        if (!vcp::Property(session,L"VCPRELATED").empty()) vcp::Fail(L"다른 버전의 MSI가 설치되어 있습니다. Windows 설정에서 기존 버전을 먼저 제거해 주세요. 자동 업그레이드는 이번 버전에서 지원하지 않습니다.");
        std::wstring root = vcp::FullPath(vcp::Property(session,L"INSTALLFOLDER"));
        bool installed = !vcp::Property(session,L"Installed").empty();
        bool remove = vcp::Equal(vcp::Property(session,L"REMOVE"),L"ALL");
        if (installed) vcp::CheckMaintenanceLocation(root);
        vcp::Guard(root, installed, remove);
        std::wstring codebase = vcp::CodeBase(root);
        std::wstring data = root + L"|" + (installed ? L"1" : L"0") + L"|" + (remove ? L"1" : L"0");
        if (MsiSetPropertyW(session,L"VCPCODEBASE",codebase.c_str()) != ERROR_SUCCESS || MsiSetPropertyW(session,L"VcpDeferred",data.c_str()) != ERROR_SUCCESS) vcp::Fail(L"설치 검증 정보를 전달할 수 없습니다.");
        return ERROR_SUCCESS;
    } catch (const vcp::Failure& e) { return vcp::Report(session,e.message); }
    catch (...) { return vcp::Report(session,L"설치 안전 검사를 완료하지 못했습니다. 변경하지 않았습니다."); }
}
extern "C" UINT __stdcall VcpDeferred(MSIHANDLE session) {
    try {
        std::wstring data = vcp::Property(session,L"CustomActionData");
        size_t first = data.find(L'|'), last = data.find_last_of(L'|');
        if (first == std::wstring::npos || first == last || data.size() != last+2 || last != first+2 || (data[first+1] != L'0' && data[first+1] != L'1') || (data[last+1] != L'0' && data[last+1] != L'1')) vcp::Fail(L"잘못된 설치 검증 정보입니다.");
        vcp::Guard(data.substr(0,first),data[first+1] == L'1',data[last+1] == L'1');
        return ERROR_SUCCESS;
    } catch (const vcp::Failure& e) { return vcp::Report(session,e.message); }
    catch (...) { return vcp::Report(session,L"설치 직전 안전 검사를 완료하지 못했습니다."); }
}
