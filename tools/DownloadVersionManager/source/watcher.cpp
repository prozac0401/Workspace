#include "watcher.h"
#include "engine.h"
#include <array>
#include <map>
#include <set>
#include <vector>
#include <algorithm>
#include <cwctype>
#include <cstddef>
#include <stdexcept>

namespace dvm {
namespace {
std::wstring lower(std::wstring text) {
    if (text.empty()) return text;
    std::wstring folded(text.size(), L'\0');
    if (!LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE, text.data(), static_cast<int>(text.size()), folded.data(), static_cast<int>(folded.size()), nullptr, nullptr, 0)) throw std::runtime_error("filename case");
    return folded;
}
std::wstring joined(const std::wstring& folder, const std::wstring& name) { return folder + (folder.back() == L'\\' ? L"" : L"\\") + name; }
bool parseDuplicateName(const std::wstring& name, std::wstring& logical) {
    const auto folded = lower(name);
    const auto dot = name.rfind(L'.');
    const auto extension = dot == std::wstring::npos ? L"" : folded.substr(dot);
    if (folded.rfind(L".dvm-", 0) == 0 || folded.rfind(L"~$", 0) == 0 ||
        extension == L".crdownload" || extension == L".part" || extension == L".partial" || extension == L".tmp" || extension == L".download") return false;
    const auto end = dot == std::wstring::npos || dot == 0 ? name.size() : dot;
    if (end < 5 || name[end-1] != L')') return false;
    const auto opening = name.rfind(L" (", end-1);
    if (opening == std::wstring::npos || opening == 0 || opening+3 >= end || name[opening+2] < L'1' || name[opening+2] > L'9') return false;
    for (size_t at = opening+2; at < end-1; ++at) if (name[at] < L'0' || name[at] > L'9') return false;
    logical = name.substr(0, opening) + name.substr(end);
    return !logical.empty();
}
bool snapshot(const std::wstring& path, BY_HANDLE_FILE_INFORMATION& information) {
    HANDLE file = CreateFileW((L"\\\\?\\" + path).c_str(), FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    const bool okay = GetFileInformationByHandle(file, &information) != FALSE &&
        (information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_OFFLINE)) == 0;
    CloseHandle(file); return okay;
}
bool same(const BY_HANDLE_FILE_INFORMATION& a, const BY_HANDLE_FILE_INFORMATION& b) {
    return a.dwVolumeSerialNumber == b.dwVolumeSerialNumber && a.nFileIndexHigh == b.nFileIndexHigh && a.nFileIndexLow == b.nFileIndexLow &&
        a.nFileSizeHigh == b.nFileSizeHigh && a.nFileSizeLow == b.nFileSizeLow &&
        CompareFileTime(&a.ftLastWriteTime, &b.ftLastWriteTime) == 0 && CompareFileTime(&a.ftCreationTime, &b.ftCreationTime) == 0;
}
struct Candidate { std::wstring name, logical; BY_HANDLE_FILE_INFORMATION information{}; ULONGLONG since = 0; bool observed = false; };
}
std::wstring resultMessage(const std::wstring& name, const Result& result) {
    if (result.status == L"cleanup_required") return name + L" → 최신 파일로 변경했습니다. 이전 파일은 지우지 못해 보존했습니다. 위치: " + result.oldPath;
    if (result.status == L"metadata_warning") return name + L" → 최신 파일로 변경했습니다. 파일 시간을 설정하지 못했습니다. 탐색기에서 시간을 확인해 주세요.";
    if (result.ok) return name + (result.status == L"same_content_replaced" ? L" → 최신 파일로 변경했습니다. 내용은 같습니다." : L" → 최신 파일로 변경하고 이전 내용을 _history에 보관했습니다.");
    if (result.status == L"target_locked" || result.status == L"new_file_locked") return name + L" → 파일이 사용 중이라 두 파일을 보존했습니다. 파일을 닫은 뒤 최신본을 직접 확인해 주세요.";
    std::wstring text;
    if (result.status == L"permission_denied") {
        const std::wstring reason = result.readOnlyProtected ? L"읽기 전용 보호: 파일 보존" : L"접근 실패: 파일 보존";
        text = reason + L" (permission_denied, 오류 " + std::to_wstring(result.error) + L") · " + name;
    } else if (result.status == L"file_info_failed") {
        text = L"파일 정보 확인 실패: 파일 보존 (file_info_failed, 오류 " + std::to_wstring(result.error) + L") · " + name;
    } else text = name + L" → 파일을 보존했습니다. (" + result.status + L")";
    if (!result.oldPath.empty() && result.rollbackError) text += L" 이전 파일 위치: " + result.oldPath;
    return text;
}

Watcher::~Watcher() { stop(); }
bool duplicateName(const std::wstring& name, std::wstring& logical) { return parseDuplicateName(name, logical); }
bool validateFolder(const std::wstring& folder, std::wstring& error) {
    if (folder.size() < 3 || folder.size() > 16000 || folder[1] != L':' || folder[2] != L'\\') {
        error = L"로컬 NTFS 폴더를 선택해 주세요."; return false;
    }
    const std::wstring root = folder.substr(0, 3);
    wchar_t filesystem[32]{};
    if (GetDriveTypeW(root.c_str()) != DRIVE_FIXED || !GetVolumeInformationW(root.c_str(), nullptr, 0, nullptr, nullptr, nullptr, filesystem, 32) || lower(filesystem) != L"ntfs") {
        error = L"고정 로컬 NTFS 드라이브의 폴더를 선택해 주세요."; return false;
    }
    size_t end = 3;
    for (;;) {
        const auto part = folder.substr(0, end);
        const DWORD attributes = GetFileAttributesW((L"\\\\?\\"+part).c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
            error = L"폴더를 열 수 없습니다. 바로 가기나 연결 폴더 대신 실제 폴더를 선택해 주세요."; return false;
        }
        if (end == folder.size()) break;
        end = folder.find(L'\\', end == 3 ? 3 : end+1);
        if (end == std::wstring::npos) end = folder.size();
    }
    return true;
}
bool Watcher::start(const std::wstring& folder, Report report, std::wstring& error) {
    stop();
    if (!validateFolder(folder, error)) return false;
    directory = CreateFileW((L"\\\\?\\" + folder).c_str(), FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (directory == INVALID_HANDLE_VALUE) { error = L"폴더 감시 권한을 확인하고 다시 시작해 주세요."; return false; }
    stopped = CreateEventW(nullptr, TRUE, FALSE, nullptr); ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!stopped || !ready) { error = L"감시를 준비하지 못했습니다. 다시 시작해 주세요."; stop(); return false; }
    active = true;
    try { worker = std::thread(&Watcher::run, this, folder, std::move(report)); }
    catch (...) { active = false; error = L"감시를 시작하지 못했습니다. 다시 시작해 주세요."; stop(); return false; }
    if (WaitForSingleObject(ready, 5000) != WAIT_OBJECT_0 || !active.load()) {
        error = L"폴더 변경 알림을 시작하지 못했습니다. 다시 시작해 주세요."; stop(); return false;
    }
    return true;
}
void Watcher::stop() {
    if (stopped) SetEvent(stopped);
    if (worker.joinable()) worker.join();
    active = false;
    if (directory != INVALID_HANDLE_VALUE) { CloseHandle(directory); directory = INVALID_HANDLE_VALUE; }
    if (stopped) { CloseHandle(stopped); stopped = nullptr; }
    if (ready) { CloseHandle(ready); ready = nullptr; }
}
void Watcher::run(std::wstring folder, Report report) {
    std::array<DWORD, 16384> buffer{};
    OVERLAPPED overlapped{}; overlapped.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    bool outstanding = false;
    std::map<std::wstring, Candidate> pending;
    std::set<std::wstring> ambiguous;
    auto notify = [&](const std::wstring& text) { try { report(text); } catch (...) {} };
    auto queue = [&]() {
        ResetEvent(overlapped.hEvent);
        outstanding = ReadDirectoryChangesW(directory, buffer.data(), static_cast<DWORD>(sizeof(buffer)), FALSE,
            FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_LAST_WRITE, nullptr, &overlapped, nullptr) != FALSE;
        return outstanding;
    };
    try {
        if (!overlapped.hEvent || !queue()) { active = false; SetEvent(ready); throw std::runtime_error("notification start"); }
        SetEvent(ready);
        const HANDLE events[] = {stopped, overlapped.hEvent};
        while (WaitForSingleObject(stopped, 0) != WAIT_OBJECT_0) {
            const DWORD wait = WaitForMultipleObjects(2, events, FALSE, pending.empty() ? INFINITE : 250);
            if (wait == WAIT_OBJECT_0) break;
            if (wait == WAIT_OBJECT_0+1) {
                DWORD received = 0;
                if (!GetOverlappedResult(directory, &overlapped, &received, FALSE) || received == 0) {
                    outstanding = false; notify(L"변경 알림을 놓쳐 감시를 중지했습니다. 파일은 보존했습니다. 감시를 다시 시작해 주세요."); break;
                }
                outstanding = false;
                size_t offset = 0;
                for (;;) {
                    if (offset+offsetof(FILE_NOTIFY_INFORMATION, FileName) > received) throw std::runtime_error("notification bounds");
                    const auto record = reinterpret_cast<const FILE_NOTIFY_INFORMATION*>(reinterpret_cast<const BYTE*>(buffer.data())+offset);
                    if (offset+offsetof(FILE_NOTIFY_INFORMATION, FileName)+record->FileNameLength > received || record->FileNameLength % sizeof(wchar_t)) throw std::runtime_error("notification name");
                    const std::wstring name(record->FileName, record->FileNameLength/sizeof(wchar_t));
                    const auto key = lower(name);
                    if (record->Action == FILE_ACTION_ADDED || record->Action == FILE_ACTION_RENAMED_NEW_NAME) {
                        std::wstring logical;
                        if (duplicateName(name, logical) && !ambiguous.count(lower(logical))) {
                            BY_HANDLE_FILE_INFORMATION target{};
                            if (snapshot(joined(folder, logical), target)) {
                                Candidate candidate; candidate.name = name; candidate.logical = logical; candidate.since = GetTickCount64();
                                candidate.observed = snapshot(joined(folder, name), candidate.information); pending[key] = candidate;
                            }
                        }
                    } else if (record->Action == FILE_ACTION_MODIFIED) {
                        const auto found = pending.find(key);
                        if (found != pending.end()) { found->second.since = GetTickCount64(); found->second.observed = snapshot(joined(folder, name), found->second.information); }
                    } else if (record->Action == FILE_ACTION_REMOVED || record->Action == FILE_ACTION_RENAMED_OLD_NAME) pending.erase(key);
                    if (!record->NextEntryOffset) break;
                    if (record->NextEntryOffset < offsetof(FILE_NOTIFY_INFORMATION, FileName) || record->NextEntryOffset > received-offset) throw std::runtime_error("notification offset");
                    offset += record->NextEntryOffset;
                }
                if (!queue()) throw std::runtime_error("notification queue");
                std::map<std::wstring, unsigned> counts;
                for (const auto& item : pending) ++counts[lower(item.second.logical)];
                for (const auto& item : counts) if (item.second > 1) {
                    ambiguous.insert(item.first); notify(item.first + L" → 여러 새 파일이 함께 들어와 모두 보존했습니다. 최신본을 직접 확인해 주세요.");
                }
                for (auto at = pending.begin(); at != pending.end();) if (ambiguous.count(lower(at->second.logical))) at = pending.erase(at); else ++at;
                if (pending.size() > 512) { notify(L"처리 후보가 너무 많아 감시를 중지했습니다. 파일은 보존했습니다."); break; }
                continue;
            }
            if (wait != WAIT_TIMEOUT) throw std::runtime_error("notification wait");
            for (auto at = pending.begin(); at != pending.end();) {
                auto& candidate = at->second;
                BY_HANDLE_FILE_INFORMATION current{};
                if (!snapshot(joined(folder, candidate.name), current)) { candidate.observed = false; ++at; continue; }
                if (!candidate.observed || !same(candidate.information, current)) {
                    candidate.information = current; candidate.observed = true; candidate.since = GetTickCount64(); ++at; continue;
                }
                if (GetTickCount64()-candidate.since < 3000) { ++at; continue; }
                // Read newly queued names before committing an eligible candidate.
                if (WaitForSingleObject(overlapped.hEvent, 0) == WAIT_OBJECT_0 || WaitForSingleObject(stopped, 0) == WAIT_OBJECT_0) break;
                Request request; request.newPath = joined(folder, candidate.name); request.logicalName = candidate.logical;
                request.folderPair = true; request.requireSnapshot = true; request.expectedSource = current;
                const auto result = process(request); notify(resultMessage(candidate.name, result));
                at = pending.erase(at);
            }
        }
    } catch (...) { notify(L"폴더 감시를 중지했습니다. 파일은 보존했습니다. 감시를 다시 시작해 주세요."); }
    if (outstanding) { CancelIoEx(directory, &overlapped); DWORD bytes = 0; GetOverlappedResult(directory, &overlapped, &bytes, TRUE); }
    if (overlapped.hEvent) CloseHandle(overlapped.hEvent);
    active = false; SetEvent(ready); notify(L"감시가 꺼져 있습니다.");
}
}
