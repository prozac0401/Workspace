#include "Guard.cpp"
#include <cstdio>
#include <functional>

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
