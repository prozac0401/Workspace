#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <msi.h>
#include <msiquery.h>
#include <bcrypt.h>
#include <sddl.h>
#include <algorithm>
#include <array>
#include <cwctype>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

// This module never changes installed resources. Windows Installer owns all writes
// and rollback. The guard rejects a conflict before those standard actions begin.
namespace image_guard {
constexpr size_t MaxItems = 8192;
constexpr size_t MaxText = 4 * 1024 * 1024;
struct Failure { std::wstring text; };
[[noreturn]] void Fail(const std::wstring& text) { throw Failure{text}; }
void WinCheck(bool ok, const std::wstring& operation) {
    if (!ok) Fail(operation + L" (Windows error " + std::to_wstring(GetLastError()) + L")");
}
bool Missing(DWORD error) { return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND; }
std::wstring Lower(std::wstring text) {
    std::transform(text.begin(), text.end(), text.begin(), [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
    return text;
}
bool Equal(const std::wstring& a, const std::wstring& b) { return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL; }
struct MsiHandle {
    MSIHANDLE value = 0;
    MsiHandle() = default;
    explicit MsiHandle(MSIHANDLE v) : value(v) {}
    ~MsiHandle() { if (value) MsiCloseHandle(value); }
    MsiHandle(const MsiHandle&) = delete;
    MsiHandle& operator=(const MsiHandle&) = delete;
};
struct FileHandle {
    HANDLE value = INVALID_HANDLE_VALUE;
    explicit FileHandle(HANDLE v) : value(v) {}
    ~FileHandle() { if (value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    FileHandle(const FileHandle&) = delete;
};
struct KeyHandle {
    HKEY value = nullptr;
    ~KeyHandle() { if (value) RegCloseKey(value); }
    KeyHandle(const KeyHandle&) = delete;
    KeyHandle() = default;
};
std::wstring Record(MSIHANDLE record, UINT field) {
    DWORD length = 0;
    const UINT first = MsiRecordGetStringW(record, field, L"", &length);
    if (first != ERROR_MORE_DATA && first != ERROR_SUCCESS) Fail(L"Cannot read package record");
    if (length > MaxText) Fail(L"Package record is too large");
    std::vector<wchar_t> buffer(static_cast<size_t>(length) + 1);
    DWORD capacity = static_cast<DWORD>(buffer.size());
    if (MsiRecordGetStringW(record, field, buffer.data(), &capacity) != ERROR_SUCCESS) Fail(L"Cannot read package record");
    return std::wstring(buffer.data(), capacity);
}
std::wstring Property(MSIHANDLE session, const wchar_t* name) {
    DWORD length = 0;
    const UINT first = MsiGetPropertyW(session, name, L"", &length);
    if (first != ERROR_MORE_DATA && first != ERROR_SUCCESS) Fail(L"Cannot read installer property");
    if (length > MaxText) Fail(L"Installer property is too large");
    std::vector<wchar_t> buffer(static_cast<size_t>(length) + 1);
    DWORD capacity = static_cast<DWORD>(buffer.size());
    if (MsiGetPropertyW(session, name, buffer.data(), &capacity) != ERROR_SUCCESS) Fail(L"Cannot read installer property");
    return std::wstring(buffer.data(), capacity);
}
template<typename Function> void Rows(MSIHANDLE database, const wchar_t* sql, Function consume) {
    MsiHandle view;
    if (MsiDatabaseOpenViewW(database, sql, &view.value) != ERROR_SUCCESS ||
        MsiViewExecute(view.value, 0) != ERROR_SUCCESS) Fail(L"Cannot read required ownership table");
    size_t count = 0;
    for (;;) {
        MsiHandle row;
        const UINT status = MsiViewFetch(view.value, &row.value);
        if (status == ERROR_NO_MORE_ITEMS) break;
        if (status != ERROR_SUCCESS || ++count > MaxItems) Fail(L"Invalid ownership table");
        consume(row.value);
    }
}
bool Table(MSIHANDLE database, const wchar_t* name) {
    const MSICONDITION result = MsiDatabaseIsTablePersistentW(database, name);
    if (result == MSICONDITION_ERROR) Fail(L"Cannot inspect ownership table");
    return result == MSICONDITION_TRUE;
}
std::wstring DatabaseProperty(MSIHANDLE database, const wchar_t* name) {
    std::wstring result;
    Rows(database, L"SELECT `Property`, `Value` FROM `Property`", [&](MSIHANDLE row) {
        if (Record(row, 1) == name) result = Record(row, 2);
    });
    return result;
}
bool Guid(const std::wstring& text) {
    if (text.size() != 38 || text.front() != L'{' || text.back() != L'}') return false;
    for (size_t i = 1; i < 37; ++i) {
        if (i == 9 || i == 14 || i == 19 || i == 24) { if (text[i] != L'-') return false; }
        else if (!iswxdigit(text[i])) return false;
    }
    return true;
}
std::wstring PackageCode(MSIHANDLE database) {
    MsiHandle summary;
    if (MsiGetSummaryInformationW(database, nullptr, 0, &summary.value) != ERROR_SUCCESS) Fail(L"Cannot read package identity");
    UINT type = 0; INT number = 0; FILETIME time{}; DWORD size = 0;
    const UINT first = MsiSummaryInfoGetPropertyW(summary.value, 9, &type, &number, &time, L"", &size);
    if (first != ERROR_MORE_DATA && first != ERROR_SUCCESS) Fail(L"Cannot read package identity");
    std::vector<wchar_t> buffer(static_cast<size_t>(size) + 1);
    DWORD capacity = static_cast<DWORD>(buffer.size());
    if (MsiSummaryInfoGetPropertyW(summary.value, 9, &type, &number, &time, buffer.data(), &capacity) != ERROR_SUCCESS) Fail(L"Cannot read package identity");
    const std::wstring code(buffer.data(), capacity);
    if (!Guid(code)) Fail(L"Invalid package identity");
    return code;
}
void Relative(const std::wstring& path, size_t maximum = 255) {
    if (path.empty() || path.size() > maximum || path.front() == L'\\' || path.front() == L'/') Fail(L"Invalid owned relative path");
    size_t start = 0;
    for (size_t i = 0; i <= path.size(); ++i) {
        if (i < path.size() && path[i] != L'\\' && path[i] != L'/') {
            if (path[i] < 32 || wcschr(L":*?\"<>|", path[i])) Fail(L"Invalid owned relative path");
            continue;
        }
        const auto part = path.substr(start, i - start);
        if (part.empty() || part == L"." || part == L".." || part.back() == L'.' || part.back() == L' ') Fail(L"Invalid owned relative path");
        start = i + 1;
    }
}
std::wstring Slashes(std::wstring text) { std::replace(text.begin(), text.end(), L'/', L'\\'); return text; }
std::wstring FullPath(const std::wstring& input) {
    if (input.size() < 4 || !iswalpha(input[0]) || input[1] != L':' || input[2] != L'\\' ||
        input.find(L':', 2) != std::wstring::npos || input.find(L'/') != std::wstring::npos ||
        input.find(L'\0') != std::wstring::npos) Fail(L"Installation must use an absolute local path");
    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetFullPathNameW(input.c_str(), static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
    if (!length || length >= buffer.size()) Fail(L"Invalid installation path");
    std::wstring path(buffer.data(), length);
    while (path.size() > 3 && path.back() == L'\\') path.pop_back();
    if (path.size() <= 3) Fail(L"Installation cannot target a drive root");
    Relative(path.substr(3), 32760);
    const std::wstring volume = path.substr(0, 3);
    if (GetDriveTypeW(volume.c_str()) != DRIVE_FIXED) Fail(L"Installation must use a local fixed drive");
    return path;
}
std::wstring NativePath(const std::wstring& path) { return L"\\\\?\\" + path; }
void PlainAncestors(const std::wstring& path, bool lastIsDirectory) {
    const std::wstring normalized = FullPath(path);
    for (size_t i = 2; i <= normalized.size(); ++i) {
        if (i != normalized.size() && normalized[i] != L'\\') continue;
        std::wstring part = normalized.substr(0, i);
        if (i == 2) part += L"\\";
        const DWORD attrs = GetFileAttributesW(NativePath(part).c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES) {
            const DWORD error = GetLastError();
            if (Missing(error)) continue;
            Fail(L"Cannot inspect path: " + part + L" (Windows error " + std::to_wstring(error) + L")");
        }
        if ((attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0) Fail(L"Reparse point is not an owned installation path: " + part);
        if ((i != normalized.size() || lastIsDirectory) && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0) Fail(L"Expected a directory: " + part);
    }
}
std::wstring Hex(const unsigned char* data, size_t size) {
    static const wchar_t digits[] = L"0123456789abcdef";
    std::wstring value(size * 2, L'0');
    for (size_t i = 0; i < size; ++i) { value[2 * i] = digits[data[i] >> 4]; value[2 * i + 1] = digits[data[i] & 15]; }
    return value;
}
bool HashFormat(const std::wstring& hash) { return hash.size() == 64 && std::all_of(hash.begin(), hash.end(), [](wchar_t c) { return iswxdigit(c) != 0; }); }
void RejectNamedStreams(const std::wstring& path) {
    WIN32_FIND_STREAM_DATA data{};
    HANDLE search = FindFirstStreamW(NativePath(path).c_str(), FindStreamInfoStandard, &data, 0);
    if (search == INVALID_HANDLE_VALUE) {
        if (GetLastError() == ERROR_HANDLE_EOF) return;
        Fail(L"Cannot inspect owned file streams: " + path);
    }
    struct SearchCloser { HANDLE h; ~SearchCloser() { FindClose(h); } } close{search};
    for (;;) {
        if (wcscmp(data.cStreamName, L"::$DATA") != 0) Fail(L"An externally added file stream was preserved: " + path);
        if (!FindNextStreamW(search, &data)) {
            if (GetLastError() != ERROR_HANDLE_EOF) Fail(L"Cannot completely inspect owned file streams: " + path);
            break;
        }
    }
}
std::wstring FileHash(const std::wstring& path) {
    PlainAncestors(path, false);
    FileHandle file(CreateFileW(NativePath(path).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
    if (file.value == INVALID_HANDLE_VALUE) {
        const DWORD error = GetLastError();
        if (Missing(error)) return L"";
        Fail(L"Cannot safely read owned file: " + path + L" (Windows error " + std::to_wstring(error) + L")");
    }
    BY_HANDLE_FILE_INFORMATION info{};
    WinCheck(GetFileInformationByHandle(file.value, &info) != FALSE, L"Cannot inspect file handle");
    if ((info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) || info.nNumberOfLinks != 1)
        Fail(L"Owned file is a directory, reparse point, or hard link: " + path);
    RejectNamedStreams(path);
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) Fail(L"SHA-256 is unavailable");
    struct AlgorithmCloser { BCRYPT_ALG_HANDLE h; ~AlgorithmCloser() { BCryptCloseAlgorithmProvider(h, 0); } } closeAlgorithm{algorithm};
    DWORD objectSize = 0, returned = 0;
    if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&objectSize), sizeof(objectSize), &returned, 0) < 0)
        Fail(L"Cannot initialize SHA-256");
    std::vector<unsigned char> object(objectSize);
    BCRYPT_HASH_HANDLE hash = nullptr;
    if (BCryptCreateHash(algorithm, &hash, object.data(), objectSize, nullptr, 0, 0) < 0) Fail(L"Cannot initialize SHA-256");
    struct HashCloser { BCRYPT_HASH_HANDLE h; ~HashCloser() { BCryptDestroyHash(h); } } closeHash{hash};
    std::array<unsigned char, 65536> buffer{};
    for (;;) {
        DWORD read = 0;
        WinCheck(ReadFile(file.value, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) != FALSE, L"Cannot hash owned file");
        if (read == 0) break;
        if (BCryptHashData(hash, buffer.data(), read, 0) < 0) Fail(L"Cannot hash owned file");
    }
    std::array<unsigned char, 32> digest{};
    if (BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) < 0) Fail(L"Cannot complete SHA-256");
    return Hex(digest.data(), digest.size());
}
struct OwnedFile { std::wstring path; std::wstring sha256; };
struct RegistryValue { std::wstring key; std::wstring name; std::wstring data; bool mayExist = true; };
struct Manifest { std::vector<OwnedFile> files; std::vector<RegistryValue> registry; std::vector<std::wstring> roots; };
struct Plan { std::wstring folder; std::wstring sid; bool fresh = false; bool checkUser = true; Manifest manifest; };
std::wstring LongName(const std::wstring& name) {
    const auto bar = name.find(L'|');
    return bar == std::wstring::npos ? name : name.substr(bar + 1);
}
struct PackageFile { std::wstring path; std::wstring component; };
std::vector<PackageFile> PackageFiles(MSIHANDLE database) {
    std::map<std::wstring, std::pair<std::wstring, std::wstring>> dirs;
    Rows(database, L"SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`", [&](MSIHANDLE row) {
        auto name = Record(row, 3); const auto source = name.find(L':'); if (source != std::wstring::npos) name.resize(source);
        dirs.emplace(Record(row, 1), std::make_pair(Record(row, 2), LongName(name)));
    });
    std::vector<PackageFile> result;
    Rows(database, L"SELECT `File`.`FileName`, `Component`.`Directory_`, `Component`.`ComponentId` FROM `File`, `Component` WHERE `File`.`Component_` = `Component`.`Component`", [&](MSIHANDLE row) {
        std::wstring relative = LongName(Record(row, 1));
        std::wstring directory = Record(row, 2);
        std::set<std::wstring> visited;
        while (directory != L"INSTALLFOLDER") {
            if (!visited.insert(directory).second) Fail(L"Cyclic package directory");
            const auto it = dirs.find(directory);
            if (it == dirs.end() || it->second.first.empty()) Fail(L"Package file outside INSTALLFOLDER");
            if (it->second.second != L".") relative = it->second.second + L"\\" + relative;
            directory = it->second.first;
        }
        Relative(relative);
        const auto component = Record(row, 3);
        if (!Guid(component)) Fail(L"Invalid owned component identity");
        result.push_back({relative, component});
    });
    if (result.empty()) Fail(L"Package has no owned files");
    return result;
}
std::vector<OwnedFile> ReadFiles(MSIHANDLE database) {
    if (!Table(database, L"ImageGuardFile")) Fail(L"Required file ownership manifest is missing");
    std::vector<OwnedFile> result;
    std::set<std::wstring> paths;
    Rows(database, L"SELECT `Path`, `Sha256` FROM `ImageGuardFile`", [&](MSIHANDLE row) {
        OwnedFile file{Slashes(Record(row, 1)), Lower(Record(row, 2))};
        Relative(file.path);
        if (!HashFormat(file.sha256) || !paths.insert(Lower(file.path)).second) Fail(L"Invalid file ownership manifest");
        result.push_back(std::move(file));
    });
    if (result.empty()) Fail(L"Empty file ownership manifest");
    return result;
}
void ValidateInventory(MSIHANDLE database, const std::vector<OwnedFile>& files) {
    const auto authored = PackageFiles(database);
    if (authored.size() != files.size()) Fail(L"File ownership manifest does not cover the package");
    std::set<std::wstring> expected;
    for (const auto& file : files) expected.insert(Lower(file.path));
    for (const auto& file : authored) if (expected.erase(Lower(file.path)) != 1) Fail(L"File ownership manifest differs from the package");
    if (!expected.empty()) Fail(L"File ownership manifest is incomplete");
}
void AddRegistryValue(Manifest& result, std::set<std::wstring>& roots, std::set<std::wstring>& slots,
    RegistryValue value, const std::wstring& folder) {
    Relative(value.key);
    if (value.key.rfind(L"Software\\Classes\\", 0) != 0 || value.name == L"*" || value.name == L"-" || value.name == L"+" ||
        value.name.find_first_of(L"\\[]") != std::wstring::npos) Fail(L"Unsupported registry ownership authoring");
    const std::wstring token = L"[INSTALLFOLDER]";
    size_t position = 0;
    while ((position = value.data.find(token, position)) != std::wstring::npos) {
        value.data.replace(position, token.size(), folder + L"\\"); position += folder.size() + 1;
    }
    if (value.data.find_first_of(L"[]") != std::wstring::npos || (!value.data.empty() && value.data.front() == L'#'))
        Fail(L"Guard only supports literal REG_SZ ownership values");
    std::wstring root = value.key;
    const std::wstring suffix = L"\\InprocServer32";
    if (root.size() >= suffix.size() && Equal(root.substr(root.size() - suffix.size()), suffix)) root.resize(root.size() - suffix.size());
    if (!slots.insert(Lower(value.key) + L"\n" + Lower(value.name)).second) Fail(L"Duplicate owned registry slot");
    roots.insert(root); result.registry.push_back(std::move(value));
}
void CompleteRegistry(Manifest& result, const std::set<std::wstring>& roots) {
    if (roots.size() != 7 || result.registry.size() != 23) Fail(L"Unexpected COM/menu ownership inventory");
    result.roots.assign(roots.begin(), roots.end());
}
Manifest ReadManifest(MSIHANDLE database, const std::wstring& folder, std::vector<OwnedFile> files) {
    ValidateInventory(database, files);
    Manifest result; result.files = std::move(files);
    std::set<std::wstring> roots, slots;
    Rows(database, L"SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`", [&](MSIHANDLE row) {
        if (MsiRecordGetInteger(row, 1) != 2) Fail(L"Guard only supports authored HKLM registration");
        AddRegistryValue(result, roots, slots, {Record(row, 2), Record(row, 3), Record(row, 4), true}, folder);
    });
    CompleteRegistry(result, roots);
    if (Table(database, L"RemoveRegistry") || Table(database, L"RemoveFile")) Fail(L"Destructive removal tables are not supported by this guard");
    return result;
}
struct PriorBaseline {
    bool allowSameProduct = false;
    std::vector<OwnedFile> files;
    std::vector<PackageFile> components;
    std::vector<RegistryValue> registry;
};
PriorBaseline ReadPriorBaseline(MSIHANDLE database, const std::wstring& product, const std::wstring& package) {
    if (!Table(database, L"ImageGuardPrior") || !Table(database, L"ImageGuardPriorFile") || !Table(database, L"ImageGuardPriorRegistry"))
        Fail(L"Required audited prior ownership baseline is missing");
    PriorBaseline result; std::wstring id; int fileCount = 0, registryCount = 0;
    Rows(database, L"SELECT `Id`, `ProductCode`, `PackageCode`, `AllowSameProduct`, `FileCount`, `RegistryCount` FROM `ImageGuardPrior`", [&](MSIHANDLE row) {
        const auto baselineProduct = Record(row, 2), baselinePackage = Record(row, 3);
        if (!Guid(baselineProduct) || !Guid(baselinePackage)) Fail(L"Invalid prior package identity");
        if (!Equal(baselineProduct, product) || !Equal(baselinePackage, package)) return;
        if (!id.empty()) Fail(L"Duplicate prior package ownership baseline");
        id = Record(row, 1); const int allow = MsiRecordGetInteger(row, 4);
        fileCount = MsiRecordGetInteger(row, 5); registryCount = MsiRecordGetInteger(row, 6);
        if (id.empty() || (allow != 0 && allow != 1) || fileCount != 404 || registryCount != 23) Fail(L"Invalid prior ownership baseline counts or mode");
        result.allowSameProduct = allow == 1;
    });
    if (id.empty()) Fail(L"This exact earlier package has not been audited for safe migration");
    std::set<std::wstring> paths, components;
    Rows(database, L"SELECT `PriorId`, `Path`, `Sha256`, `ComponentId` FROM `ImageGuardPriorFile`", [&](MSIHANDLE row) {
        if (Record(row, 1) != id) return;
        OwnedFile file{Slashes(Record(row, 2)), Lower(Record(row, 3))}; const auto component = Record(row, 4);
        Relative(file.path);
        if (!HashFormat(file.sha256) || !Guid(component) || !paths.insert(Lower(file.path)).second || !components.insert(Lower(component)).second)
            Fail(L"Invalid prior file/component ownership inventory");
        result.components.push_back({file.path, component}); result.files.push_back(std::move(file));
    });
    Rows(database, L"SELECT `PriorId`, `Root`, `Key`, `Name`, `Value` FROM `ImageGuardPriorRegistry`", [&](MSIHANDLE row) {
        if (Record(row, 1) != id) return;
        if (MsiRecordGetInteger(row, 2) != 2) Fail(L"Prior baseline must use authored HKLM registration");
        result.registry.push_back({Record(row, 3), Record(row, 4), Record(row, 5), true});
    });
    if (result.files.size() != static_cast<size_t>(fileCount) || result.registry.size() != static_cast<size_t>(registryCount))
        Fail(L"Prior ownership baseline is incomplete");
    return result;
}
Manifest PriorManifest(const PriorBaseline& baseline, const std::wstring& folder) {
    Manifest result; result.files = baseline.files; std::set<std::wstring> roots, slots;
    for (const auto& value : baseline.registry) AddRegistryValue(result, roots, slots, value, folder);
    CompleteRegistry(result, roots); return result;
}
void ValidateSid(const std::wstring& sid) {
    PSID value = nullptr;
    if (!ConvertStringSidToSidW(sid.c_str(), &value)) Fail(L"Cannot determine initiating user");
    const bool valid = IsValidSid(value) != FALSE;
    LocalFree(value);
    if (!valid) Fail(L"Invalid initiating user");
}
std::wstring UserSid() {
    HANDLE raw = nullptr;
    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &raw)) {
        if (GetLastError() != ERROR_NO_TOKEN || !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw)) Fail(L"Cannot determine initiating user token");
    }
    FileHandle token(raw);
    DWORD size = 0; GetTokenInformation(token.value, TokenUser, nullptr, 0, &size);
    if (!size || size > 65536) Fail(L"Cannot determine initiating user token");
    std::vector<unsigned char> data(size);
    WinCheck(GetTokenInformation(token.value, TokenUser, data.data(), size, &size) != FALSE, L"Cannot inspect initiating user token");
    LPWSTR text = nullptr;
    WinCheck(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid, &text) != FALSE, L"Cannot read initiating user SID");
    const std::wstring sid(text); LocalFree(text); ValidateSid(sid); return sid;
}
// Open each ancestor without following registry symbolic links.
bool OpenPlainKey(HKEY hive, const std::wstring& path, KeyHandle& output) {
    size_t position = 0;
    for (;;) {
        position = path.find(L'\\', position);
        const auto part = position == std::wstring::npos ? path : path.substr(0, position);
        KeyHandle key;
        const LSTATUS opened = RegOpenKeyExW(hive, part.c_str(), REG_OPTION_OPEN_LINK, KEY_READ | KEY_WOW64_64KEY, &key.value);
        if (opened == ERROR_FILE_NOT_FOUND || opened == ERROR_PATH_NOT_FOUND) return false;
        if (opened != ERROR_SUCCESS) Fail(L"Cannot inspect registry key: " + part + L" (Windows error " + std::to_wstring(opened) + L")");
        DWORD type = 0, bytes = 0;
        const LSTATUS link = RegQueryValueExW(key.value, L"SymbolicLinkValue", nullptr, &type, nullptr, &bytes);
        if (link == ERROR_SUCCESS && type == REG_LINK) Fail(L"Registry symbolic link is not an owned registration: " + part);
        if (link != ERROR_SUCCESS && link != ERROR_FILE_NOT_FOUND) Fail(L"Cannot inspect registry key type: " + part);
        if (position == std::wstring::npos) { output.value = key.value; key.value = nullptr; return true; }
        ++position;
    }
}
void RegistryCheck(const RegistryValue& value) {
    KeyHandle key;
    if (!OpenPlainKey(HKEY_LOCAL_MACHINE, value.key, key)) return;
    DWORD type = 0, bytes = 0;
    const LSTATUS first = RegQueryValueExW(key.value, value.name.c_str(), nullptr, &type, nullptr, &bytes);
    if (first == ERROR_FILE_NOT_FOUND) return;
    if (first != ERROR_SUCCESS || bytes > 65536) Fail(L"Cannot inspect owned registry value: " + value.key + L" [" + value.name + L"]");
    if (!value.mayExist) Fail(L"Existing registration occupies a new owned value: " + value.key + L" [" + value.name + L"]");
    std::vector<unsigned char> data(static_cast<size_t>(bytes) + sizeof(wchar_t), 0);
    DWORD actual = bytes;
    const LSTATUS read = RegQueryValueExW(key.value, value.name.c_str(), nullptr, &type, data.data(), &actual);
    const size_t expected = (value.data.size() + 1) * sizeof(wchar_t);
    if (read != ERROR_SUCCESS || type != REG_SZ || actual != expected ||
        memcmp(data.data(), value.data.c_str(), expected) != 0) Fail(L"Externally modified registration was preserved: " + value.key + L" [" + value.name + L"]");
}
void Inspect(const Plan& plan) {
    if (FullPath(plan.folder) != plan.folder) Fail(L"Installation path is not canonical");
    PlainAncestors(plan.folder, true);
    if (plan.fresh) {
        const DWORD attrs = GetFileAttributesW(NativePath(plan.folder).c_str());
        if (attrs != INVALID_FILE_ATTRIBUTES) Fail(L"Existing installation directory was preserved: " + plan.folder);
        if (!Missing(GetLastError())) Fail(L"Cannot determine whether installation directory exists");
        for (const auto& root : plan.manifest.roots) {
            KeyHandle key;
            if (OpenPlainKey(HKEY_LOCAL_MACHINE, root, key)) Fail(L"Existing machine registration was preserved: " + root);
        }
    }
    if (plan.checkUser) {
        ValidateSid(plan.sid);
        KeyHandle user;
        const auto classesHive = plan.sid + L"_Classes";
        if (!OpenPlainKey(HKEY_USERS, classesHive, user)) Fail(L"Initiating user's Classes registry hive is unavailable");
        for (const auto& root : plan.manifest.roots) {
            KeyHandle key;
            const std::wstring prefix = L"Software\\Classes\\";
            if (root.rfind(prefix, 0) != 0) Fail(L"Invalid user registration root");
            if (OpenPlainKey(user.value, root.substr(prefix.size()), key)) Fail(L"Existing user registration was preserved: " + root);
        }
    }
    for (const auto& file : plan.manifest.files) {
        Relative(file.path);
        const auto hash = FileHash(plan.folder + L"\\" + file.path);
        if (!hash.empty() && (file.sha256.empty() || !Equal(hash, file.sha256)))
            Fail(L"Externally modified or unowned file was preserved: " + plan.folder + L"\\" + file.path);
    }
    for (const auto& value : plan.manifest.registry) RegistryCheck(value);
}
void InspectCurrentUser(const Plan& plan) {
    if (!plan.checkUser) return;
    if (!Equal(UserSid(), plan.sid)) Fail(L"The current custom-action user does not match the initiating user");
    KeyHandle user;
    const LSTATUS opened = RegOpenCurrentUser(KEY_READ | KEY_WOW64_64KEY, &user.value);
    if (opened != ERROR_SUCCESS) Fail(L"Cannot independently inspect the initiating user's registry");
    // Software\Classes is the documented HKCU alias for the loaded Classes
    // hive. Open that anchor normally, then inspect every owned descendant
    // without following further registry links and with the same 64-bit view.
    KeyHandle classes;
    if (RegOpenKeyExW(user.value, L"Software\\Classes", 0, KEY_READ | KEY_WOW64_64KEY, &classes.value) != ERROR_SUCCESS)
        Fail(L"The initiating user's Classes registry alias is unavailable");
    const std::wstring prefix = L"Software\\Classes\\";
    for (const auto& root : plan.manifest.roots) {
        if (root.rfind(prefix, 0) != 0) Fail(L"Invalid current-user registration root");
        KeyHandle key;
        if (OpenPlainKey(classes.value, root.substr(prefix.size()), key)) Fail(L"Existing current-user registration was preserved: " + root);
    }
}
void Put(std::wstring& output, const std::wstring& value) {
    if (value.find(L'\0') != std::wstring::npos) Fail(L"Embedded null in ownership plan");
    output += std::to_wstring(value.size()) + L":" + value;
    if (output.size() > MaxText) Fail(L"Ownership plan is too large");
}
std::wstring Serialize(const Plan& plan) {
    std::wstring output;
    Put(output, L"1"); Put(output, plan.folder); Put(output, plan.sid); Put(output, plan.fresh ? L"1" : L"0"); Put(output, plan.checkUser ? L"1" : L"0");
    Put(output, std::to_wstring(plan.manifest.files.size()));
    for (const auto& file : plan.manifest.files) { Put(output, file.path); Put(output, file.sha256); }
    Put(output, std::to_wstring(plan.manifest.registry.size()));
    for (const auto& value : plan.manifest.registry) { Put(output, value.key); Put(output, value.name); Put(output, value.data); Put(output, value.mayExist ? L"1" : L"0"); }
    Put(output, std::to_wstring(plan.manifest.roots.size()));
    for (const auto& root : plan.manifest.roots) Put(output, root);
    return output;
}
struct Reader {
    const std::wstring& input; size_t position = 0;
    std::wstring Get() {
        const auto colon = input.find(L':', position);
        if (colon == std::wstring::npos || colon == position || colon - position > 8) Fail(L"Malformed deferred ownership plan");
        size_t size = 0;
        for (size_t i = position; i < colon; ++i) {
            if (input[i] < L'0' || input[i] > L'9') Fail(L"Malformed deferred ownership plan");
            size = size * 10 + static_cast<size_t>(input[i] - L'0');
        }
        position = colon + 1;
        if (size > MaxText || size > input.size() - position) Fail(L"Truncated deferred ownership plan");
        const auto result = input.substr(position, size); position += size;
        if (result.find(L'\0') != std::wstring::npos) Fail(L"Malformed deferred ownership plan");
        return result;
    }
    size_t Count() {
        const auto value = Get(); size_t count = 0;
        if (value.empty() || value.size() > 5) Fail(L"Malformed ownership count");
        for (const auto ch : value) { if (ch < L'0' || ch > L'9') Fail(L"Malformed ownership count"); count = count * 10 + static_cast<size_t>(ch - L'0'); }
        if (count > MaxItems) Fail(L"Ownership count is too large");
        return count;
    }
    bool Flag() { const auto value = Get(); if (value != L"0" && value != L"1") Fail(L"Malformed ownership flag"); return value == L"1"; }
};
Plan Deserialize(const std::wstring& input) {
    if (input.empty() || input.size() > MaxText) Fail(L"Missing deferred ownership plan");
    Reader reader{input}; Plan plan;
    if (reader.Get() != L"1") Fail(L"Unsupported deferred ownership schema");
    plan.folder = reader.Get(); plan.sid = reader.Get(); plan.fresh = reader.Flag(); plan.checkUser = reader.Flag();
    const auto files = reader.Count(); std::set<std::wstring> seen;
    for (size_t i = 0; i < files; ++i) {
        OwnedFile file{reader.Get(), reader.Get()}; Relative(file.path);
        if ((!file.sha256.empty() && !HashFormat(file.sha256)) || !seen.insert(Lower(file.path)).second) Fail(L"Invalid deferred file inventory");
        plan.manifest.files.push_back(std::move(file));
    }
    const auto values = reader.Count(); seen.clear();
    for (size_t i = 0; i < values; ++i) {
        RegistryValue value{reader.Get(), reader.Get(), reader.Get(), reader.Flag()}; Relative(value.key);
        if (!seen.insert(Lower(value.key) + L"\n" + Lower(value.name)).second) Fail(L"Invalid deferred registry inventory");
        plan.manifest.registry.push_back(std::move(value));
    }
    const auto roots = reader.Count(); seen.clear();
    for (size_t i = 0; i < roots; ++i) { auto root = reader.Get(); Relative(root); if (!seen.insert(Lower(root)).second) Fail(L"Invalid deferred root inventory"); plan.manifest.roots.push_back(std::move(root)); }
    if (files == 0 || roots != 7 || values != 23 || reader.position != input.size()) Fail(L"Incomplete deferred ownership plan");
    ValidateSid(plan.sid);
    return plan;
}
template<typename Query> bool ProductInfoWithQuery(const wchar_t* property, std::wstring& output, Query query) {
    output.clear(); DWORD length = 0;
    const UINT first = query(nullptr, length);
    if (first == ERROR_UNKNOWN_PRODUCT) return false;
    if (first != ERROR_MORE_DATA && first != ERROR_SUCCESS)
        Fail(L"Cannot inspect installed product property " + std::wstring(property) + L" (Windows error " + std::to_wstring(first) + L", size query)");
    if (length > MaxText) Fail(L"Installed product property is too large: " + std::wstring(property));
    size_t capacity = static_cast<size_t>(length) + 1;
    for (unsigned int attempt = 1; attempt <= 6; ++attempt) {
        std::vector<wchar_t> buffer(capacity); DWORD actual = static_cast<DWORD>(capacity);
        const UINT status = query(buffer.data(), actual);
        if (status == ERROR_SUCCESS) {
            if (actual >= buffer.size() || buffer[actual] != L'\0' || wcslen(buffer.data()) != actual)
                Fail(L"Invalid installed product property length: " + std::wstring(property));
            output.assign(buffer.data(), actual); return true;
        }
        // PackageCode may report its packed 32-character registry form during
        // sizing, then require 38 characters for its expanded GUID. Retry only
        // the documented insufficient-buffer result; all other failures stop.
        if (status != ERROR_MORE_DATA)
            Fail(L"Cannot inspect installed product property " + std::wstring(property) + L" (Windows error " + std::to_wstring(status) + L", read attempt " + std::to_wstring(attempt) + L")");
        if (actual > MaxText) Fail(L"Installed product property is too large: " + std::wstring(property));
        capacity = std::max(capacity * 2, static_cast<size_t>(actual) + 1);
        if (capacity > MaxText + 1) Fail(L"Installed product property growth exceeded its limit: " + std::wstring(property));
    }
    Fail(L"Installed product property remained unstable: " + std::wstring(property) + L" (Windows error " + std::to_wstring(ERROR_MORE_DATA) + L")");
}
bool ProductInfo(const std::wstring& product, const wchar_t* property, std::wstring& output) {
    return ProductInfoWithQuery(property, output, [&](wchar_t* buffer, DWORD& length) {
        return MsiGetProductInfoExW(product.c_str(), nullptr, MSIINSTALLCONTEXT_MACHINE, property, buffer, &length);
    });
}
void RequireMachineProduct(const std::wstring& product) {
    size_t matches = 0;
    for (DWORD index = 0; index < 16; ++index) {
        wchar_t code[39]{}; wchar_t sid[256]{}; DWORD sidLength = 256; MSIINSTALLCONTEXT context = MSIINSTALLCONTEXT_NONE;
        const UINT status = MsiEnumProductsExW(product.c_str(), nullptr, MSIINSTALLCONTEXT_ALL, index, code, &context, sid, &sidLength);
        if (status == ERROR_NO_MORE_ITEMS) break;
        if (status != ERROR_SUCCESS || index == 15 || context != MSIINSTALLCONTEXT_MACHINE || sidLength != 0 || !Equal(code, product))
            Fail(L"Installed product context is ambiguous or cannot be established");
        ++matches;
    }
    if (matches != 1) Fail(L"Exactly one per-machine product registration is required");
}
std::wstring CheckedComponentPath(INSTALLSTATE state, const std::vector<wchar_t>& buffer, DWORD length) {
    if ((state != INSTALLSTATE_LOCAL && state != INSTALLSTATE_ABSENT) || !length || length >= buffer.size() ||
        buffer[length] != L'\0' || wcslen(buffer.data()) != length)
        Fail(L"Cannot establish installed component path (state " + std::to_wstring(state) + L", length " + std::to_wstring(length) + L")");
    return std::wstring(buffer.data(), length);
}
std::wstring InstalledFolder(const std::vector<PackageFile>& files, const std::wstring& product) {
    RequireMachineProduct(product);
    std::wstring result;
    for (const auto& file : files) {
        // Explicitly validate the machine component before using the classic
        // path API. On the tested Windows Installer 5.0 build, PathEx reports
        // UNKNOWN even for unrelated, correctly registered machine products.
        INSTALLSTATE registered = INSTALLSTATE_UNKNOWN;
        const UINT status = MsiQueryComponentStateW(product.c_str(), nullptr, MSIINSTALLCONTEXT_MACHINE, file.component.c_str(), &registered);
        if (status != ERROR_SUCCESS || registered != INSTALLSTATE_LOCAL)
            Fail(L"Cannot establish installed machine component ownership: " + file.component + L" (error " + std::to_wstring(status) + L", state " + std::to_wstring(registered) + L")");
        std::vector<wchar_t> buffer(32768); DWORD capacity = static_cast<DWORD>(buffer.size());
        const INSTALLSTATE state = MsiGetComponentPathW(product.c_str(), file.component.c_str(), buffer.data(), &capacity);
        const auto installed = CheckedComponentPath(state, buffer, capacity);
        const std::wstring suffix = L"\\" + file.path;
        if (installed.size() <= suffix.size() || !Equal(installed.substr(installed.size() - suffix.size()), suffix)) Fail(L"Installed component path differs from its ownership manifest");
        const auto folder = FullPath(installed.substr(0, installed.size() - suffix.size()));
        if (result.empty()) result = folder;
        else if (!Equal(result, folder)) Fail(L"Installed product spans inconsistent directories");
    }
    if (result.empty()) Fail(L"Installed product path is unknown");
    return result;
}
void NewSlots(const Manifest& incoming, Manifest& prior) {
    std::set<std::wstring> files, values;
    for (const auto& item : prior.files) files.insert(Lower(item.path));
    for (const auto& item : prior.registry) values.insert(Lower(item.key) + L"\n" + Lower(item.name));
    for (const auto& item : incoming.files) if (files.insert(Lower(item.path)).second) prior.files.push_back({item.path, L""});
    for (const auto& item : incoming.registry) if (values.insert(Lower(item.key) + L"\n" + Lower(item.name)).second) {
        auto value = item; value.mayExist = false; prior.registry.push_back(std::move(value));
    }
    std::set<std::wstring> roots(prior.roots.begin(), prior.roots.end());
    roots.insert(incoming.roots.begin(), incoming.roots.end());
    prior.roots.assign(roots.begin(), roots.end());
    if (prior.registry.size() != 23 || prior.roots.size() != 7) Fail(L"Changing the registry ownership schema requires a new guard schema");
}
Plan Prepare(MSIHANDLE session) {
    MsiHandle database(MsiGetActiveDatabase(session));
    if (!database.value || DatabaseProperty(database.value, L"ImageGuardSchema") != L"2") Fail(L"Unsupported package ownership schema");
    const auto product = DatabaseProperty(database.value, L"ProductCode");
    const auto upgrade = DatabaseProperty(database.value, L"UpgradeCode");
    const auto package = PackageCode(database.value);
    if (!Guid(product) || !Guid(upgrade)) Fail(L"Invalid product ownership identity");
    Plan plan; plan.folder = FullPath(Property(session, L"INSTALLFOLDER"));
    const auto tokenSid = UserSid();
    plan.sid = Property(session, L"UserSID"); ValidateSid(plan.sid);
    if (!Equal(tokenSid, plan.sid)) Fail(L"Custom-action token SID differs from Windows Installer UserSID: token=" + tokenSid + L" installer=" + plan.sid);
    // Removal never changes another user's HKCU registration.
    plan.checkUser = Property(session, L"REMOVE") != L"ALL";
    auto incoming = ReadManifest(database.value, plan.folder, ReadFiles(database.value));
    std::vector<std::wstring> related;
    for (DWORD i = 0; i < 32; ++i) {
        wchar_t code[39]{};
        const UINT status = MsiEnumRelatedProductsW(upgrade.c_str(), 0, i, code);
        if (status == ERROR_NO_MORE_ITEMS) break;
        if (status != ERROR_SUCCESS || i == 31) Fail(L"Cannot establish related product ownership");
        std::wstring registeredPackage;
        if (!ProductInfo(code, INSTALLPROPERTY_PACKAGECODE, registeredPackage) || !Guid(registeredPackage)) Fail(L"A related product uses an unsupported installation context");
        related.emplace_back(code);
    }
    if (related.size() > 1) Fail(L"Multiple related installations require individual review");
    std::wstring ownPackage;
    const bool ownInstalled = ProductInfo(product, INSTALLPROPERTY_PACKAGECODE, ownPackage);
    if (ownInstalled && (related.size() != 1 || !Equal(related.front(), product))) Fail(L"Installed product identity is inconsistent");
    if (related.empty()) {
        if (ownInstalled || !Property(session, L"WIX_UPGRADE_DETECTED").empty()) Fail(L"Unexpected upgrade identity");
        plan.fresh = true; plan.manifest = std::move(incoming); return plan;
    }
    const auto priorProduct = related.front();
    const bool maintenance = Equal(priorProduct, product);
    const auto detected = Property(session, L"WIX_UPGRADE_DETECTED");
    if ((!maintenance && !Equal(detected, priorProduct)) || (maintenance && !detected.empty())) Fail(L"Upgrade detection does not match the installed product");
    std::wstring priorPackage;
    if (!ProductInfo(priorProduct, INSTALLPROPERTY_PACKAGECODE, priorPackage) || !Guid(priorPackage)) Fail(L"Installed package identity is unavailable");
    std::wstring folder;
    if (maintenance && Equal(priorPackage, package)) {
        // The active database is the exact installed package. Opening another
        // MSI database inside a custom action is unsupported by Windows Installer.
        folder = InstalledFolder(PackageFiles(database.value), priorProduct);
        plan.manifest = std::move(incoming);
    } else {
        const auto baseline = ReadPriorBaseline(database.value, priorProduct, priorPackage);
        if (maintenance && (!baseline.allowSameProduct || Property(session, L"REINSTALL") != L"ALL" ||
            Lower(Property(session, L"REINSTALLMODE")).find(L'v') == std::wstring::npos || !Property(session, L"REMOVE").empty()))
            Fail(L"The same ProductCode has a different PackageCode; only an explicitly audited recovery update is supported");
        if (!maintenance && baseline.allowSameProduct) Fail(L"A recovery baseline cannot authorize a major upgrade");
        folder = InstalledFolder(baseline.components, priorProduct);
        plan.manifest = PriorManifest(baseline, folder);
        NewSlots(incoming, plan.manifest);
    }
    if (!Equal(folder, plan.folder)) Fail(L"Moving an existing installation is not supported; existing files were preserved");
    return plan;
}
void Log(MSIHANDLE session, const std::wstring& message, INSTALLMESSAGE type = INSTALLMESSAGE_INFO) {
    MsiHandle record(MsiCreateRecord(0));
    if (record.value) { const auto text = L"ImageCopySave ownership guard: " + message; MsiRecordSetStringW(record.value, 0, text.c_str()); MsiProcessMessage(session, type, record.value); }
}
UINT Reject(MSIHANDLE session, const std::wstring& reason) {
    Log(session, L"BLOCKED: " + reason);
    MsiHandle record(MsiCreateRecord(0));
    if (record.value) {
        const auto text = L"설치 자원의 충돌 또는 외부 변경을 발견하여 작업을 중단했습니다. 원본은 보존됩니다.\n" + reason +
            L"\n변경된 항목을 별도 보관하거나 원래 설치 상태로 되돌린 뒤 다시 실행하세요. 변경한 파일을 자동으로 덮어쓰거나 삭제하지 않습니다.";
        MsiRecordSetStringW(record.value, 0, text.c_str()); MsiProcessMessage(session, INSTALLMESSAGE_ERROR, record.value);
    }
    return ERROR_INSTALL_FAILURE;
}
} // namespace image_guard
extern "C" __declspec(dllexport) UINT __stdcall ImageGuardPreflight(MSIHANDLE session) {
    try {
        auto plan = image_guard::Prepare(session);
        image_guard::Log(session, L"context preflight: UserSID=" + plan.sid + L" checkUser=" + (plan.checkUser ? L"true" : L"false") + L" roots=" + std::to_wstring(plan.manifest.roots.size()));
        for (const auto& root : plan.manifest.roots) image_guard::Log(session, L"initiating-user registration root: " + root);
        image_guard::InspectCurrentUser(plan);
        image_guard::Inspect(plan);
        const auto data = image_guard::Serialize(plan);
        // Private mixed-case property cannot be used as a public command-line bypass.
        if (MsiSetPropertyW(session, L"ImageGuardDeferred", data.c_str()) != ERROR_SUCCESS ||
            image_guard::Property(session, L"ImageGuardDeferred") != data) image_guard::Fail(L"Cannot schedule complete deferred ownership check");
        image_guard::Log(session, L"PASS (preflight)");
        return ERROR_SUCCESS;
    } catch (const image_guard::Failure& error) { return image_guard::Reject(session, error.text); }
      catch (...) { return image_guard::Reject(session, L"Unexpected validation failure"); }
}
extern "C" __declspec(dllexport) UINT __stdcall ImageGuardDeferred(MSIHANDLE session) {
    try {
        const auto plan = image_guard::Deserialize(image_guard::Property(session, L"CustomActionData"));
        const auto installerSid = image_guard::Property(session, L"UserSID");
        image_guard::ValidateSid(installerSid);
        if (!image_guard::Equal(installerSid, plan.sid)) image_guard::Fail(L"Deferred user context differs from the validated initiating user");
        image_guard::Log(session, L"context deferred: UserSID=" + plan.sid + L" checkUser=" + (plan.checkUser ? L"true" : L"false") + L" roots=" + std::to_wstring(plan.manifest.roots.size()));
        image_guard::Inspect(plan);
        image_guard::Log(session, L"PASS (deferred recheck)");
        return ERROR_SUCCESS;
    } catch (const image_guard::Failure& error) { return image_guard::Reject(session, error.text); }
      catch (...) { return image_guard::Reject(session, L"Unexpected deferred validation failure"); }
}
