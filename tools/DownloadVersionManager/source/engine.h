#pragma once
#include <windows.h>
#include <string>
#include <cstdint>
namespace dvm {
struct Request {
    std::wstring newPath, logicalName; uint64_t downloadId = 0, completedAt = 0;
    std::wstring requestToken; // Per-download random token; browser IDs are not global.
    // Folder input has its own approved arrival policy, not browser endTime.
    bool folderPair = false;
    bool requireSnapshot = false;
    BY_HANDLE_FILE_INFORMATION expectedSource{};
    bool requireTargetSnapshot = false;
    BY_HANDLE_FILE_INFORMATION expectedTarget{};
};
struct Result {
    bool ok = false, changed = false; std::wstring status = L"internal_error", targetPath, newPath, oldPath;
    DWORD error = 0, rollbackError = 0; uint64_t hashBytes = 0, compareMicroseconds = 0;
    bool readOnlyProtected = false; // Confirmed under the processing handle; not a protocol field.
};
#ifdef DVM_TESTING
struct TestHooks { std::wstring fault, timestamp; const DYNAMIC_TIME_ZONE_INFORMATION* timeZone = nullptr; };
Result process(const Request&, const TestHooks& = {});
#else
Result process(const Request&);
#endif
}
