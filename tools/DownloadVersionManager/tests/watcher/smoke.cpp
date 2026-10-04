#include "watcher.h"
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <vector>
#include <stdexcept>

namespace fs = std::filesystem;
void write(const fs::path& path, const std::string& text) { std::ofstream out(path, std::ios::binary); out << text; if (!out) throw std::runtime_error("fixture write"); }
std::string read(const fs::path& path) { std::ifstream input(path, std::ios::binary); return std::string(std::istreambuf_iterator<char>(input), {}); }
BY_HANDLE_FILE_INFORMATION identity(const fs::path& path) {
    HANDLE file = CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, 0, nullptr);
    BY_HANDLE_FILE_INFORMATION information{}; if (file == INVALID_HANDLE_VALUE || !GetFileInformationByHandle(file, &information)) throw std::runtime_error("fixture metadata");
    CloseHandle(file); return information;
}
bool sameObject(const BY_HANDLE_FILE_INFORMATION& a, const BY_HANDLE_FILE_INFORMATION& b) { return a.dwVolumeSerialNumber == b.dwVolumeSerialNumber && a.nFileIndexHigh == b.nFileIndexHigh && a.nFileIndexLow == b.nFileIndexLow; }

int wmain(int count, wchar_t** arguments) {
    if (count != 2) { std::cerr << "Usage: watcher-smoke.exe <new-fixture-directory>\n"; return 2; }
    const auto root = fs::absolute(arguments[1]);
    if (fs::exists(root)) { std::cerr << "Use a fresh fixture directory.\n"; return 2; }
    fs::create_directories(root / L"watched" / L"nested");
    const auto folder = root / L"watched";
    unsigned failures = 0, passed = 0;
    std::vector<std::string> results;
    auto check = [&](const char* name, bool okay) { std::cout << (okay ? "PASS " : "FAIL ") << name << '\n'; okay ? ++passed : ++failures; results.push_back(std::string("{\"name\":\"")+name+"\",\"passed\":"+(okay?"true":"false")+"}"); };
    try {
        std::wstring logical;
        check("suffix-contract", dvm::duplicateName(L"한글 명단 (12).xlsx", logical) && logical == L"한글 명단.xlsx" &&
            !dvm::duplicateName(L"문서 (0).xlsx", logical) && !dvm::duplicateName(L"문서 (1).crdownload", logical) && !dvm::duplicateName(L"문서.xlsx", logical));
        for (const auto name : {L"same.bin", L"changed.bin", L"locked.bin", L"Ä.bin", L"growing.bin", L"temp.bin", L"writer.bin", L"existing.bin"}) write(folder/name, "old");
        write(folder/L"same.bin", "equal"); write(folder/L"existing (1).bin", "existing-before-start");
        write(folder/L"nested"/L"ignored.bin", "outside-descendants");
        HANDLE targetLock = CreateFileW((folder/L"locked.bin").c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
        std::mutex reportMutex; std::vector<std::wstring> reports;
        dvm::Watcher watcher; std::wstring error;
        const bool started = watcher.start(folder.wstring(), [&](const std::wstring& text) { std::lock_guard<std::mutex> lock(reportMutex); reports.push_back(text); }, error);
        check("notification-start", started); if (!started) throw std::runtime_error("watcher start");
        write(folder/L"same (1).bin", "equal"); const auto incoming = identity(folder/L"same (1).bin");
        write(folder/L"changed (1).bin", "new-content");
        write(folder/L"locked (1).bin", "new-locked");
        write(folder/L"ä (1).bin", "first"); write(folder/L"Ä (2).bin", "second");
        write(folder/L"growing (1).bin", "phase-one");
        write(folder/L"no-original (1).bin", "no-root");
        write(folder/L"temp (1).bin.crdownload", "new-temp");
        write(folder/L"nested"/L"ignored (1).bin", "nested-new");
        write(root/L"outside (1).bin", "outside-new");
        HANDLE writer = CreateFileW((folder/L"writer (1).bin").c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_NEW, 0, nullptr);
        DWORD wrote = 0; WriteFile(writer, "active-writer", 13, &wrote, nullptr);
        Sleep(1000);
        write(folder/L"growing (1).bin", "phase-two");
        MoveFileW((folder/L"temp (1).bin.crdownload").c_str(), (folder/L"temp (1).bin").c_str());
        Sleep(1500);
        check("changed-candidate-stability-window", read(folder/L"growing.bin") == "old" && fs::exists(folder/L"growing (1).bin"));
        Sleep(2200);
        check("same-keeps-incoming-object", read(folder/L"same.bin") == "equal" && !fs::exists(folder/L"same (1).bin") && sameObject(identity(folder/L"same.bin"), incoming));
        bool oldArchived = false, sameArchived = false;
        if (fs::exists(folder/L"_history")) for (const auto& item : fs::directory_iterator(folder/L"_history")) {
            if (item.path().filename().wstring().rfind(L"changed_", 0) == 0 && read(item.path()) == "old") oldArchived = true;
            if (item.path().filename().wstring().rfind(L"same_", 0) == 0) sameArchived = true;
        }
        check("changed-content-history-only", read(folder/L"changed.bin") == "new-content" && oldArchived && !sameArchived);
        check("locked-target-preserved", read(folder/L"locked.bin") == "old" && fs::exists(folder/L"locked (1).bin"));
        check("concurrent-candidates-preserved", read(folder/L"Ä.bin") == "old" && fs::exists(folder/L"ä (1).bin") && fs::exists(folder/L"Ä (2).bin"));
        check("modified-candidate-eventually-eligible", read(folder/L"growing.bin") == "phase-two" && !fs::exists(folder/L"growing (1).bin"));
        check("no-original-preserved", fs::exists(folder/L"no-original (1).bin") && !fs::exists(folder/L"no-original.bin"));
        check("temporary-final-rename", read(folder/L"temp.bin") == "new-temp" && !fs::exists(folder/L"temp (1).bin"));
        check("writer-preserved", read(folder/L"writer.bin") == "old" && fs::exists(folder/L"writer (1).bin"));
        check("scope-and-existing-preserved", read(folder/L"existing.bin") == "old" && fs::exists(folder/L"existing (1).bin") && read(folder/L"nested"/L"ignored.bin") == "outside-descendants" && fs::exists(root/L"outside (1).bin"));
        if (writer != INVALID_HANDLE_VALUE) CloseHandle(writer);
        if (targetLock != INVALID_HANDLE_VALUE) CloseHandle(targetLock);
        watcher.stop(); check("notification-stop", !watcher.running());
        write(folder/L"stopped.bin", "old"); write(folder/L"stopped (1).bin", "new");
        check("notification-restart", watcher.start(folder.wstring(), [](const std::wstring&) {}, error));
        Sleep(3400); watcher.stop();
        check("restart-does-not-clean-existing", read(folder/L"stopped.bin") == "old" && fs::exists(folder/L"stopped (1).bin") && fs::exists(folder/L"ä (1).bin") && fs::exists(folder/L"Ä (2).bin"));
    } catch (const std::exception& exception) { std::cerr << exception.what() << '\n'; ++failures; }
    std::ofstream report(root/L"watcher-results.json"); report << "{\"passed\":" << passed << ",\"failed\":" << failures << ",\"cases\":[";
    for (size_t at = 0; at < results.size(); ++at) report << (at ? "," : "") << results[at];
    report << "]}\n";
    return failures ? 1 : 0;
}
