#pragma once
#include <windows.h>
#include <string>
#include <cstdint>
namespace dvm {
struct Request {
    std::wstring newPath, logicalName; uint64_t downloadId = 0, completedAt = 0;
    std::wstring requestToken; // Per-download random token; browser IDs are not global.
};
struct Result {
    bool ok = false, changed = false; std::wstring status = L"internal_error", targetPath, newPath, oldPath;
    DWORD error = 0, rollbackError = 0; uint64_t hashBytes = 0, compareMicroseconds = 0;
};
#ifdef DVM_TESTING
struct TestHooks { std::wstring fault, timestamp; };
Result process(const Request&, const TestHooks& = {});
#else
Result process(const Request&);
#endif
}
