#include "Guard.cpp"
#include <cstdio>
#include <functional>
#include <objbase.h>
#pragma comment(lib, "ole32.lib")

using namespace image_guard;
static unsigned int passed = 0;
void Test(const wchar_t* name, const std::function<void()>& operation) {
    operation(); ++passed; wprintf(L"PASS %s\n", name);
}
void Rejected(const std::function<void()>& operation) {
    try { operation(); } catch (const Failure&) { return; }
    Fail(L"Expected the guard to reject this fixture");
}
void WriteFixture(const std::wstring& path, const char* text, bool replace = false) {
    FileHandle file(CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, replace ? TRUNCATE_EXISTING : CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
    WinCheck(file.value != INVALID_HANDLE_VALUE, L"Cannot create synthetic fixture");
    DWORD written = 0; const DWORD size = static_cast<DWORD>(strlen(text));
    WinCheck(WriteFile(file.value, text, size, &written, nullptr) != FALSE && written == size, L"Cannot write synthetic fixture");
}
int wmain(int argc, wchar_t** argv) {
    try {
        if (argc == 3 && std::wstring(argv[1]) == L"--inspect-recovery") {
            if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) Fail(L"Cannot initialize read-only MSI probe COM");
            struct ComClose { ~ComClose() { CoUninitialize(); } } comClose;
            MsiSetInternalUI(INSTALLUILEVEL_NONE, nullptr);
            MsiHandle session;
            // This documented restricted handle is incapable of changing
            // machine state. No MSI action or embedded custom action is run.
            const UINT opened = MsiOpenPackageExW(argv[2], MSIOPENPACKAGEFLAGS_IGNOREMACHINESTATE, &session.value);
            if (opened != ERROR_SUCCESS) Fail(L"Cannot open restricted recovery probe package (Windows error " + std::to_wstring(opened) + L")");
            MsiHandle database(MsiGetActiveDatabase(session.value));
            const auto product = DatabaseProperty(database.value, L"ProductCode");
            std::wstring package, location;
            if (!ProductInfo(product, INSTALLPROPERTY_PACKAGECODE, package) || !Guid(package) ||
                !ProductInfo(product, INSTALLPROPERTY_INSTALLLOCATION, location) || location.empty()) Fail(L"Read-only recovery product identity/location is unavailable");
            const auto sid = UserSid();
            for (const auto& property : std::vector<std::pair<std::wstring, std::wstring>>{{L"INSTALLFOLDER", FullPath(location)}, {L"REINSTALL", L"ALL"}, {L"REINSTALLMODE", L"vomus"}, {L"UserSID", sid}})
                if (MsiSetPropertyW(session.value, property.first.c_str(), property.second.c_str()) != ERROR_SUCCESS) Fail(L"Cannot set restricted probe property");
            const auto plan = Prepare(session.value);
            InspectCurrentUser(plan); Inspect(plan);
            const auto deferred = Deserialize(Serialize(plan)); Inspect(deferred);
            wprintf(L"PASS complete restricted recovery preflight: PackageCode=%s files=%zu registry=%zu\n", package.c_str(), plan.manifest.files.size(), plan.manifest.registry.size());
            wprintf(L"{\"status\":\"PASS\",\"files\":%zu,\"registry\":%zu,\"readOnly\":true,\"restrictedHandle\":true,\"installerActionsRun\":false,\"productRegistrationModified\":false}\n", plan.manifest.files.size(), plan.manifest.registry.size());
            return 0;
        }
        if (argc == 3 && std::wstring(argv[1]) == L"--inspect-installed") {
            // This standalone test process may open a database read-only. The
            // production custom action only uses its active database handle.
            MsiHandle database;
            if (MsiOpenDatabaseW(argv[2], MSIDBOPEN_READONLY, &database.value) != ERROR_SUCCESS) Fail(L"Cannot open read-only probe MSI");
            const auto product = DatabaseProperty(database.value, L"ProductCode");
            std::wstring registeredPackage;
            if (!ProductInfo(product, INSTALLPROPERTY_PACKAGECODE, registeredPackage) || !Equal(registeredPackage, PackageCode(database.value))) Fail(L"Installed PackageCode lookup differs from the exact probe MSI");
            wprintf(L"PASS actual ProductInfo PackageCode: %s\n", registeredPackage.c_str());
            const auto files = PackageFiles(database.value);
            const auto folder = InstalledFolder(files, product);
            Plan installed; installed.folder = folder; installed.sid = UserSid(); installed.checkUser = false;
            installed.manifest = ReadManifest(database.value, folder, ReadFiles(database.value));
            Inspect(installed);
            wprintf(L"PASS actual installed machine resolver and ownership: %s (%zu files)\n", folder.c_str(), files.size());
            wprintf(L"{\"status\":\"PASS\",\"files\":%zu,\"readOnly\":true,\"productRegistrationModified\":false}\n", files.size());
            return 0;
        }
        if (argc != 3 || std::wstring(argv[1]) != L"--fixtures") Fail(L"Usage: ImageCopySave.Guard.Tests.exe --fixtures <new-directory>");
        const auto root = FullPath(argv[2]); PlainAncestors(root, true);
        WinCheck(CreateDirectoryW(root.c_str(), nullptr) != FALSE, L"Fixture directory must be new");
        const auto path = root + L"\\owned.bin";
        WriteFixture(path, "original owned bytes");
        const auto original = FileHash(path);
        Plan plan; plan.folder = root; plan.sid = UserSid(); plan.checkUser = false; plan.manifest.files.push_back({L"owned.bin", original});
        Test(L"unchanged owned file", [&] { Inspect(plan); });
        Test(L"missing owned file", [&] { auto p = plan; p.manifest.files[0].path = L"missing.bin"; Inspect(p); });
        Test(L"existing new file slot", [&] { auto p = plan; p.manifest.files[0].sha256.clear(); Rejected([&] { Inspect(p); }); });
        std::wstring changedHash;
        Test(L"changed owned file", [&] { WriteFixture(path, "changed external bytes", true); changedHash = FileHash(path); Rejected([&] { Inspect(plan); }); });
        Test(L"changed bytes remain", [&] { if (FileHash(path) != changedHash || changedHash == original) Fail(L"Guard changed fixture bytes"); });
        Test(L"unknown sibling preserved", [&] {
            const auto extra = root + L"\\unknown-user-file.txt"; WriteFixture(extra, "not installer owned");
            const auto before = FileHash(extra); auto p = plan; p.manifest.files[0].sha256 = FileHash(path); Inspect(p);
            if (FileHash(extra) != before) Fail(L"Guard changed unknown file");
        });
        Test(L"named data stream rejected and preserved", [&] {
            const auto stream = path + L":external-note"; WriteFixture(stream, "external stream bytes");
            Rejected([&] { FileHash(path); });
            { FileHandle streamFile(CreateFileW(stream.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr));
              WinCheck(streamFile.value != INVALID_HANDLE_VALUE, L"External stream was lost");
              char bytes[64]{}; DWORD read = 0; WinCheck(ReadFile(streamFile.value, bytes, sizeof(bytes), &read, nullptr) != FALSE, L"Cannot read synthetic stream");
              if (std::string(bytes, read) != "external stream bytes") Fail(L"External stream bytes changed"); }
            WinCheck(DeleteFileW(stream.c_str()) != FALSE, L"Cannot remove own synthetic stream");
        });
        Test(L"existing directory rejected for fresh install", [&] { auto p = plan; p.fresh = true; Rejected([&] { Inspect(p); }); });
        Test(L"relative traversal rejected", [&] { Rejected([&] { Relative(L"sub\\..\\outside.bin"); }); });
        Test(L"alternate stream rejected", [&] { Rejected([&] { Relative(L"owned.bin:other"); }); });
        Test(L"ambiguous trailing dot rejected", [&] { Rejected([&] { Relative(L"owned.bin."); }); });
        Test(L"drive root rejected", [&] { Rejected([&] { FullPath(root.substr(0, 3)); }); });
        Test(L"directory in file slot rejected", [&] {
            const auto subdir = root + L"\\directory.bin"; WinCheck(CreateDirectoryW(subdir.c_str(), nullptr) != FALSE, L"Cannot create synthetic directory");
            Rejected([&] { FileHash(subdir); });
        });
        Test(L"hard link rejected", [&] {
            const auto alias = root + L"\\hardlink.bin"; WinCheck(CreateHardLinkW(alias.c_str(), path.c_str(), nullptr) != FALSE, L"Cannot create synthetic hardlink");
            Rejected([&] { FileHash(alias); });
            WinCheck(DeleteFileW(alias.c_str()) != FALSE, L"Cannot remove own synthetic hardlink");
        });
        Test(L"product PackageCode retries packed32 to expanded38 size", [&] {
            unsigned int calls = 0; std::wstring value;
            const std::wstring guid = L"{E02D0EEC-5EF4-4BF1-85EF-20074416A568}";
            const bool found = ProductInfoWithQuery<std::function<UINT(wchar_t*, DWORD&)>>(L"PackageCode", value, [&](wchar_t* buffer, DWORD& length) -> UINT {
                ++calls;
                if (calls == 1) { if (buffer != nullptr) Fail(L"Expected a supported null size query"); length = 32; return ERROR_SUCCESS; }
                if (calls == 2) { if (length != 33) Fail(L"Expected packed GUID buffer size"); wcscpy_s(buffer, length, L"CEE0D20E4FE51FB458FE027044615A86"); length = 38; return ERROR_MORE_DATA; }
                if (length <= guid.size()) Fail(L"Expanded GUID buffer was not resized");
                wcscpy_s(buffer, length, guid.c_str()); length = static_cast<DWORD>(guid.size()); return ERROR_SUCCESS;
            });
            if (!found || value != guid || calls != 3) Fail(L"Expanded canonical PackageCode was not obtained");
        });
        Test(L"initial unknown product remains absent", [&] {
            std::wstring value = L"stale";
            if (ProductInfoWithQuery<std::function<UINT(wchar_t*, DWORD&)>>(L"PackageCode", value, [](wchar_t*, DWORD&) -> UINT { return ERROR_UNKNOWN_PRODUCT; }) || !value.empty()) Fail(L"Unknown product was adopted");
        });
        Test(L"product disappearing between reads fails closed", [&] {
            unsigned int calls = 0; std::wstring value;
            Rejected([&] { ProductInfoWithQuery<std::function<UINT(wchar_t*, DWORD&)>>(L"PackageCode", value, [&](wchar_t*, DWORD& length) -> UINT { length = 32; return ++calls == 1 ? ERROR_SUCCESS : ERROR_UNKNOWN_PRODUCT; }); });
        });
        Test(L"product property access error is not retried", [&] {
            unsigned int calls = 0; std::wstring value;
            Rejected([&] { ProductInfoWithQuery<std::function<UINT(wchar_t*, DWORD&)>>(L"PackageCode", value, [&](wchar_t*, DWORD& length) -> UINT { length = 32; return ++calls == 1 ? ERROR_SUCCESS : ERROR_ACCESS_DENIED; }); });
            if (calls != 2) Fail(L"Non-size error was retried");
        });
        Test(L"product property repeated growth is bounded", [&] {
            unsigned int calls = 0; std::wstring value;
            Rejected([&] { ProductInfoWithQuery<std::function<UINT(wchar_t*, DWORD&)>>(L"PackageCode", value, [&](wchar_t*, DWORD& length) -> UINT { ++calls; length = 32; return ERROR_MORE_DATA; }); });
            if (calls != 7) Fail(L"Property retry limit was not enforced");
        });
        Test(L"registered missing component path remains repairable", [&] {
            const std::wstring text = root + L"\\missing.dll"; std::vector<wchar_t> buffer(text.begin(), text.end()); buffer.push_back(L'\0');
            if (CheckedComponentPath(INSTALLSTATE_ABSENT, buffer, static_cast<DWORD>(text.size())) != text) Fail(L"Missing component path changed");
        });
        Test(L"unknown component state fails closed", [&] { std::vector<wchar_t> buffer(32); Rejected([&] { CheckedComponentPath(INSTALLSTATE_UNKNOWN, buffer, 0); }); });
        Test(L"invalid component returned length fails closed", [&] { std::vector<wchar_t> buffer(32); Rejected([&] { CheckedComponentPath(INSTALLSTATE_LOCAL, buffer, 32); }); });
        Test(L"truncated component path fails closed", [&] { std::vector<wchar_t> buffer(32); buffer[0] = L'x'; Rejected([&] { CheckedComponentPath(INSTALLSTATE_LOCAL, buffer, 2); }); });
        Test(L"audited default registry value expands install folder", [&] {
            Manifest m; std::set<std::wstring> roots, slots;
            AddRegistryValue(m, roots, slots, {L"Software\\Classes\\Fixture", L"", L"[INSTALLFOLDER]server.dll", true}, root);
            if (m.registry.size() != 1 || !m.registry[0].name.empty() || m.registry[0].data != root + L"\\server.dll") Fail(L"Audited default value was not expanded exactly");
        });
        Test(L"audited registry duplicate fails closed", [&] {
            Manifest m; std::set<std::wstring> roots, slots; RegistryValue v{L"Software\\Classes\\Fixture", L"", L"value", true};
            AddRegistryValue(m, roots, slots, v, root); Rejected([&] { AddRegistryValue(m, roots, slots, v, root); });
        });
        Test(L"audited recursive key deletion authoring rejected", [&] {
            Manifest m; std::set<std::wstring> roots, slots;
            Rejected([&] { AddRegistryValue(m, roots, slots, {L"Software\\Classes\\Fixture", L"*", L"value", true}, root); });
        });
        Test(L"audited unsupported registry formatting rejected", [&] {
            Manifest m; std::set<std::wstring> roots, slots;
            Rejected([&] { AddRegistryValue(m, roots, slots, {L"Software\\Classes\\Fixture", L"", L"[OTHER]file.dll", true}, root); });
        });
        Plan serial = plan;
        for (unsigned int i = 0; i < 7; ++i) serial.manifest.roots.push_back(L"Software\\Classes\\Fixture" + std::to_wstring(i));
        for (unsigned int i = 0; i < 23; ++i) serial.manifest.registry.push_back({serial.manifest.roots[i % 7], L"Value" + std::to_wstring(i), L"한글: value", true});
        Test(L"initiating user Classes hive is readable", [&] { KeyHandle user; if (!OpenPlainKey(HKEY_USERS, serial.sid + L"_Classes", user)) Fail(L"Expected the current user Classes hive to be loaded"); });
        Test(L"fresh deferred check reads user Classes without following its alias", [&] { auto p = serial; p.folder += L"\\fresh-missing"; p.fresh = true; p.checkUser = true; Inspect(p); });
        Test(L"real GUID HKCU collision is rejected by both independent user views", [&] {
            std::array<unsigned char, 16> random{};
            if (BCryptGenRandom(nullptr, random.data(), static_cast<ULONG>(random.size()), BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0) Fail(L"Cannot generate unique synthetic CLSID");
            const auto hex = Hex(random.data(), random.size());
            const auto probeName = L"{" + hex.substr(0, 8) + L"-" + hex.substr(8, 4) + L"-" + hex.substr(12, 4) + L"-" + hex.substr(16, 4) + L"-" + hex.substr(20, 12) + L"}";
            const auto probePath = L"Software\\Classes\\CLSID\\" + probeName;
            KeyHandle created; DWORD disposition = 0;
            const auto opened = RegCreateKeyExW(HKEY_CURRENT_USER, probePath.c_str(), 0, nullptr, 0, KEY_READ | KEY_WRITE | KEY_WOW64_64KEY, nullptr, &created.value, &disposition);
            if (opened != ERROR_SUCCESS || disposition != REG_CREATED_NEW_KEY) Fail(L"Cannot create unique synthetic HKCU collision");
            const std::wstring marker = L"native-guard-fixture";
            auto cleanup = [&] {
                DWORD subkeys = 0, values = 0;
                if (RegQueryInfoKeyW(created.value, nullptr, nullptr, nullptr, &subkeys, nullptr, nullptr, &values, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS || subkeys != 0 || values > 1) Fail(L"Synthetic key changed; preserved for review");
                if (values == 1) {
                    wchar_t data[64]{}; DWORD type = 0, bytes = sizeof(data);
                    if (RegQueryValueExW(created.value, L"Fixture", nullptr, &type, reinterpret_cast<BYTE*>(data), &bytes) != ERROR_SUCCESS || type != REG_SZ || std::wstring(data) != marker) Fail(L"Synthetic value changed; preserved for review");
                    if (RegDeleteValueW(created.value, L"Fixture") != ERROR_SUCCESS) Fail(L"Cannot remove own synthetic value");
                }
                RegCloseKey(created.value); created.value = nullptr;
                if (RegDeleteKeyExW(HKEY_CURRENT_USER, probePath.c_str(), KEY_WOW64_64KEY, 0) != ERROR_SUCCESS) Fail(L"Cannot remove own empty synthetic key");
                KeyHandle remains;
                const auto removed = RegOpenKeyExW(HKEY_CURRENT_USER, probePath.c_str(), 0, KEY_READ | KEY_WOW64_64KEY, &remains.value);
                if (removed != ERROR_FILE_NOT_FOUND) Fail(L"Synthetic registry cleanup was not confirmed");
            };
            try {
                if (RegSetValueExW(created.value, L"Fixture", 0, REG_SZ, reinterpret_cast<const BYTE*>(marker.c_str()), static_cast<DWORD>((marker.size() + 1) * sizeof(wchar_t))) != ERROR_SUCCESS) Fail(L"Cannot create synthetic registry value");
                auto p = serial; p.folder += L"\\fresh-user-collision"; p.fresh = true; p.checkUser = true; p.manifest.roots[0] = probePath;
                // Exercise the guard before any ordinary open can initialize an
                // alias cache, then require its exact conflict error.
                bool capturedUserRejected = false, currentUserRejected = false;
                try { Inspect(p); } catch (const Failure& error) {
                    if (error.text.rfind(L"Existing user registration was preserved:", 0) != 0) throw;
                    capturedUserRejected = true;
                }
                try { InspectCurrentUser(p); } catch (const Failure& error) {
                    if (error.text.rfind(L"Existing current-user registration was preserved:", 0) != 0) throw;
                    currentUserRejected = true;
                }
                if (!capturedUserRejected || !currentUserRejected) Fail(L"Real GUID-shaped HKCU conflict was not rejected by both checks");
                KeyHandle direct;
                const auto directPath = serial.sid + L"_Classes\\CLSID\\" + probeName;
                if (RegOpenKeyExW(HKEY_USERS, directPath.c_str(), 0, KEY_READ | KEY_WOW64_64KEY, &direct.value) != ERROR_SUCCESS) Fail(L"Independent current-user collision evidence is missing");
            } catch (...) { cleanup(); throw; }
            cleanup();
        });
        Test(L"mismatched current user SID fails closed", [&] { auto p = serial; p.checkUser = true; p.sid = L"S-1-5-18"; Rejected([&] { InspectCurrentUser(p); }); });
        Test(L"complete deferred plan round trip", [&] { const auto text = Serialize(serial); if (Serialize(Deserialize(text)) != text) Fail(L"Serialization changed the plan"); });
        Test(L"large deferred plan round trip", [&] {
            auto p = serial;
            for (unsigned int i = 0; i < 700; ++i) p.manifest.files.push_back({L"folder\\file-" + std::to_wstring(i) + L".dll", original});
            const auto text = Serialize(p);
            if (text.size() < 60000 || Serialize(Deserialize(text)) != text) Fail(L"Large plan was truncated");
        });
        Test(L"truncated deferred plan rejected", [&] { auto text = Serialize(serial); text.pop_back(); Rejected([&] { Deserialize(text); }); });
        Test(L"trailing deferred data rejected", [&] { Rejected([&] { Deserialize(Serialize(serial) + L"extra"); }); });
        Test(L"unknown deferred schema rejected", [&] { auto text = Serialize(serial); text[2] = L'2'; Rejected([&] { Deserialize(text); }); });
        Test(L"duplicate owned path rejected", [&] { auto p = serial; p.manifest.files.push_back(p.manifest.files.front()); Rejected([&] { Deserialize(Serialize(p)); }); });
        Test(L"incomplete roots rejected", [&] { auto p = serial; p.manifest.roots.pop_back(); Rejected([&] { Deserialize(Serialize(p)); }); });
        Test(L"empty deferred plan rejected", [&] { Rejected([&] { Deserialize(L""); }); });
        wprintf(L"{\"status\":\"PASS\",\"passed\":%u,\"failed\":0,\"registryFixtureCreated\":true,\"registryFixtureCleaned\":true,\"productRegistrationModified\":false,\"installed\":false}\n", passed);
        return 0;
    } catch (const Failure& error) {
        fwprintf(stderr, L"FAIL after %u checks: %s\n", passed, error.text.c_str()); return 1;
    } catch (...) { fwprintf(stderr, L"FAIL unexpected exception\n"); return 2; }
}
