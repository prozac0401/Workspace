#pragma once
#include <windows.h>
#include <atomic>
#include <functional>
#include <string>
#include <thread>

namespace dvm {
struct Result;
std::wstring resultMessage(const std::wstring& name, const Result& result);
bool duplicateName(const std::wstring& name, std::wstring& logical);
bool validateFolder(const std::wstring& folder, std::wstring& error);
class Watcher {
public:
    using Report = std::function<void(const std::wstring&)>;
    Watcher() = default;
    ~Watcher();
    Watcher(const Watcher&) = delete;
    Watcher& operator=(const Watcher&) = delete;
    bool start(const std::wstring& folder, Report report, std::wstring& error);
    void stop();
    bool running() const { return active.load(); }
private:
    HANDLE directory = INVALID_HANDLE_VALUE, stopped = nullptr, ready = nullptr;
    std::atomic<bool> active{false};
    std::thread worker;
    void run(std::wstring folder, Report report);
};
}
