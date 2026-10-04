#pragma once
#include <windows.h>
#include <functional>
#include <string>

namespace dvm {
// Call while the watcher is stopped, after validating the selected folder.
// true means every discovered group was processed or explicitly preserved.
// Closing the review or a scan failure returns false, without automatic retry.
bool reviewExisting(HWND parent, const std::wstring& folder,
    const std::function<void(const std::wstring&)>& report);
}
