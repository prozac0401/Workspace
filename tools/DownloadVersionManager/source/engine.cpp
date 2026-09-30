#include "engine.h"
#include "json.h"
#include <bcrypt.h>
#include <array>
#include <vector>
#include <utility>
#include <memory>
#include <cstddef>
#include <cwchar>
#include <algorithm>

namespace dvm {
namespace {
struct Error { std::wstring status; DWORD code; };
[[noreturn]] void fail(const wchar_t* status, DWORD code = GetLastError()) { throw Error{status,code}; }
struct Handle {
    HANDLE v = INVALID_HANDLE_VALUE;
    Handle() = default; explicit Handle(HANDLE h) : v(h) {}
    Handle(const Handle&) = delete; Handle& operator=(const Handle&) = delete;
    Handle(Handle&& other) noexcept : v(std::exchange(other.v,INVALID_HANDLE_VALUE)) {}
    ~Handle() { if (v != INVALID_HANDLE_VALUE && v) CloseHandle(v); }
    bool valid() const { return v != INVALID_HANDLE_VALUE && v; }
};
struct Mutex {
    Handle h; bool owned = false;
    explicit Mutex(const std::wstring& name) : h(CreateMutexW(nullptr,FALSE,name.c_str())) {
        if (!h.valid()) fail(L"lock_failed");
        const auto w = WaitForSingleObject(h.v,30000);
        owned = w == WAIT_OBJECT_0 || w == WAIT_ABANDONED;
        if (!owned) fail(w==WAIT_TIMEOUT ? L"target_busy" : L"lock_failed", w==WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError());
    }
    ~Mutex() { if (owned) ReleaseMutex(h.v); }
};
bool equal(const std::wstring& a, const std::wstring& b) {
    return CompareStringOrdinal(a.c_str(),static_cast<int>(a.size()),b.c_str(),static_cast<int>(b.size()),TRUE)==CSTR_EQUAL;
}
std::wstring lower(const std::wstring& s) {
    if (s.empty()) return {};
    std::wstring r(s.size(),L'\0');
    if (!LCMapStringEx(LOCALE_NAME_INVARIANT,LCMAP_LOWERCASE,s.data(),static_cast<int>(s.size()),r.data(),static_cast<int>(r.size()),nullptr,nullptr,0)) fail(L"invalid_path");
    return r;
}
void component(const std::wstring& s) {
    if (s.empty() || s.size()>255 || s==L"." || s==L".." || s.back()==L'.' || s.back()==L' ') fail(L"invalid_path",ERROR_INVALID_NAME);
    for (const auto c : s) if (c<32 || wcschr(L"<>:\"/\\|?*",c)) fail(L"invalid_path",ERROR_INVALID_NAME);
    const auto base = lower(s.substr(0,s.find(L'.')));
    if (base==L"con" || base==L"prn" || base==L"aux" || base==L"nul" || base==L"conin$" || base==L"conout$" ||
        (base.size()==4 && (base.substr(0,3)==L"com" || base.substr(0,3)==L"lpt") &&
         ((base[3]>=L'1' && base[3]<=L'9') || base[3]==L'\u00b9' || base[3]==L'\u00b2' || base[3]==L'\u00b3'))) fail(L"invalid_path",ERROR_INVALID_NAME);
}
std::wstring native(const std::wstring& p) { return L"\\\\?\\" + p; }
std::wstring join(const std::wstring& p,const std::wstring& name) { return p+(p.back()==L'\\' ? L"" : L"\\")+name; }
std::wstring canonical(const std::wstring& input) {
    // Do not accept UNC, device/extended input paths, drive-relative paths, ADS,
    // traversal or paths which Win32 would silently sanitize.
    if (input.size()<4 || input.size()>16000 || !((input[0]>=L'A' && input[0]<=L'Z') || (input[0]>=L'a' && input[0]<=L'z')) || input[1]!=L':' || input[2]!=L'\\') fail(L"invalid_path",ERROR_INVALID_NAME);
    size_t at=3;
    while (at<input.size()) { const auto end=input.find(L'\\',at); component(input.substr(at,end==std::wstring::npos ? end : end-at)); if (end==std::wstring::npos) break; at=end+1; }
    if (input.back()==L'\\') fail(L"invalid_path",ERROR_INVALID_NAME);
    return input;
}
std::wstring finalPath(HANDLE h) {
    std::vector<wchar_t> buf(32768);
    const auto n=GetFinalPathNameByHandleW(h,buf.data(),static_cast<DWORD>(buf.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    if (!n || n>=buf.size()) fail(L"invalid_path");
    std::wstring r(buf.data(),n);
    if (r.rfind(L"\\\\?\\",0)!=0 || r.rfind(L"\\\\?\\UNC\\",0)==0) fail(L"unsupported_path",ERROR_NOT_SUPPORTED);
    return r.substr(4);
}
BY_HANDLE_FILE_INFORMATION info(HANDLE h) {
    BY_HANDLE_FILE_INFORMATION i{};
    if (!GetFileInformationByHandle(h,&i)) fail(L"file_info_failed");
    return i;
}
uint64_t size(const BY_HANDLE_FILE_INFORMATION& i) { return (static_cast<uint64_t>(i.nFileSizeHigh)<<32)|i.nFileSizeLow; }
void ordinary(const BY_HANDLE_FILE_INFORMATION& i, bool dir) {
    if (!!(i.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)!=dir || (i.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_OFFLINE|FILE_ATTRIBUTE_ENCRYPTED)) || (!dir && i.nNumberOfLinks!=1)) fail(L"unsupported_file",ERROR_NOT_SUPPORTED);
    if (!dir && (i.dwFileAttributes&FILE_ATTRIBUTE_READONLY)) fail(L"permission_denied",ERROR_ACCESS_DENIED);
}
struct Parents {
    std::vector<Handle> leases; std::wstring path;
    explicit Parents(const std::wstring& p) {
        const std::wstring root=p.substr(0,3);
        if (GetDriveTypeW(root.c_str())!=DRIVE_FIXED) fail(L"unsupported_path",ERROR_NOT_SUPPORTED);
        wchar_t fsName[32]{};
        if (!GetVolumeInformationW(root.c_str(),nullptr,0,nullptr,nullptr,nullptr,fsName,32) || !equal(fsName,L"NTFS")) fail(L"unsupported_path",ERROR_NOT_SUPPORTED);
        size_t end=2;
        for (;;) {
            const auto part=p.substr(0,end==2 ? 3 : end);
            Handle h(CreateFileW(native(part).c_str(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
            if (!h.valid()) fail(L"permission_denied");
            ordinary(info(h.v),true);
            FILE_CASE_SENSITIVE_INFO caseInfo{};
            if (GetFileInformationByHandleEx(h.v,FileCaseSensitiveInfo,&caseInfo,sizeof(caseInfo)) && caseInfo.Flags!=0) fail(L"unsupported_path",ERROR_NOT_SUPPORTED);
            path=finalPath(h.v); leases.emplace_back(std::move(h));
            if (end==p.size()) break;
            end=p.find(L'\\',end==2 ? 3 : end+1); if (end==std::wstring::npos) end=p.size();
        }
    }
};
Handle file(const std::wstring& p, bool newer) {
    Handle h(CreateFileW(native(p).c_str(),GENERIC_READ|DELETE|(newer ? FILE_WRITE_ATTRIBUTES : 0),FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_SEQUENTIAL_SCAN,nullptr));
    if (!h.valid()) {
        const DWORD e=GetLastError();
        if (e==ERROR_SHARING_VIOLATION || e==ERROR_LOCK_VIOLATION) fail(newer ? L"new_file_locked" : L"target_locked",e);
        if (e==ERROR_FILE_NOT_FOUND || e==ERROR_PATH_NOT_FOUND) fail(newer ? L"source_missing" : L"target_missing",e);
        fail(L"permission_denied",e);
    }
    ordinary(info(h.v),false); return h;
}
class Hasher {
    BCRYPT_ALG_HANDLE alg=nullptr; BCRYPT_HASH_HANDLE hash=nullptr; std::vector<unsigned char> object;
public:
    Hasher() {
        if (BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0) fail(L"hash_failed",ERROR_GEN_FAILURE);
        DWORD n=0,got=0;
        if (BCryptGetProperty(alg,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&n),sizeof(n),&got,0)<0) { BCryptCloseAlgorithmProvider(alg,0); alg=nullptr; fail(L"hash_failed",ERROR_GEN_FAILURE); }
        object.resize(n);
        if (BCryptCreateHash(alg,&hash,object.data(),n,nullptr,0,0)<0) { BCryptCloseAlgorithmProvider(alg,0); alg=nullptr; fail(L"hash_failed",ERROR_GEN_FAILURE); }
    }
    ~Hasher() { if (hash) BCryptDestroyHash(hash); if (alg) BCryptCloseAlgorithmProvider(alg,0); }
    void add(const unsigned char* data,DWORD n) { if (BCryptHashData(hash,const_cast<PUCHAR>(data),n,0)<0) fail(L"hash_failed",ERROR_GEN_FAILURE); }
    std::array<unsigned char,32> finish() { std::array<unsigned char,32> r{}; if (BCryptFinishHash(hash,r.data(),static_cast<ULONG>(r.size()),0)<0) fail(L"hash_failed",ERROR_GEN_FAILURE); return r; }
};
std::array<unsigned char,32> digest(HANDLE h,uint64_t& count) {
    Hasher hash; std::array<unsigned char,65536> buf{}; DWORD n=0;
    for (;;) { if (!ReadFile(h,buf.data(),static_cast<DWORD>(buf.size()),&n,nullptr)) fail(L"hash_failed"); if (!n) break; hash.add(buf.data(),n); count+=n; }
    return hash.finish();
}
std::wstring mutexName(const std::wstring& p) {
    Hasher hash; const auto bytes=utf8(lower(p)); hash.add(reinterpret_cast<const unsigned char*>(bytes.data()),static_cast<DWORD>(bytes.size()));
    const auto d=hash.finish(); std::wstring r=L"Global\\Workspace.DownloadVersionManager.v1.";
    for (const auto b:d) { r+=L"0123456789abcdef"[b>>4]; r+=L"0123456789abcdef"[b&15]; }
    return r;
}
DWORD rename(HANDLE h,const std::wstring& destination) {
    const auto p=native(destination); const auto bytes=p.size()*sizeof(wchar_t);
    // Avoid allocation failures between the two moves. All accepted native paths
    // fit this fixed, bounded buffer; no business file is loaded into it.
    std::array<unsigned char,65536> data{};
    const auto length=offsetof(FILE_RENAME_INFO,FileName)+bytes+sizeof(wchar_t);
    if (length>data.size()) return ERROR_FILENAME_EXCED_RANGE;
    auto r=reinterpret_cast<FILE_RENAME_INFO*>(data.data()); r->ReplaceIfExists=FALSE; r->RootDirectory=nullptr; r->FileNameLength=static_cast<DWORD>(bytes);
    memcpy(r->FileName,p.data(),bytes);
    return SetFileInformationByHandle(h,FileRenameInfo,r,static_cast<DWORD>(length)) ? ERROR_SUCCESS : GetLastError();
}
std::wstring timestamp() {
    SYSTEMTIME t{}; GetLocalTime(&t); wchar_t s[32]{};
    swprintf_s(s,L"%04u%02u%02u_%02u%02u%02u",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond); return s;
}
std::wstring randomName() {
    std::array<unsigned char,16> b{};
    if (BCryptGenRandom(nullptr,b.data(),static_cast<ULONG>(b.size()),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0) fail(L"rename_failed",ERROR_GEN_FAILURE);
    std::wstring r=L".dvm-"; for (const auto c:b) { r+=L"0123456789abcdef"[c>>4]; r+=L"0123456789abcdef"[c&15]; } return r+L".pending";
}
}

Result process(const Request& request
#ifdef DVM_TESTING
    , const TestHooks& hooks
#endif
) {
    Result r; r.newPath=request.newPath;
    try {
        component(request.logicalName); const auto input=canonical(request.newPath);
        r.oldPath.reserve(32768);
        const auto parent=input.substr(0,(std::max)(size_t(3),input.rfind(L'\\'))); Parents parents(parent);
        const auto newer=join(parents.path,input.substr(input.rfind(L'\\')+1));
        const auto target=join(parents.path,request.logicalName); r.newPath=newer; r.targetPath=target;
        Mutex lock(mutexName(target));
        auto n=file(newer,true);
        if (!equal(finalPath(n.v),newer)) fail(L"path_changed",ERROR_INVALID_NAME);
        const auto ni=info(n.v);
        if (equal(newer,target)) { r.ok=true; r.status=L"already_current"; return r; }
        std::unique_ptr<Handle> old;
        try { old=std::make_unique<Handle>(file(target,false)); }
        catch (const Error& e) { if (e.status!=L"target_missing") throw; }
        bool same=false;
        if (old) {
            if (!equal(finalPath(old->v),target)) fail(L"path_changed",ERROR_INVALID_NAME);
            const auto oi=info(old->v);
            LARGE_INTEGER freq{},start{},end{}; QueryPerformanceFrequency(&freq); QueryPerformanceCounter(&start);
            if (size(oi)==size(ni)) { const auto a=digest(old->v,r.hashBytes); const auto b=digest(n.v,r.hashBytes); same=a==b; }
            QueryPerformanceCounter(&end); r.compareMicroseconds=static_cast<uint64_t>((end.QuadPart-start.QuadPart)*1000000/freq.QuadPart);
        }
        std::unique_ptr<Parents> historyLease;
        if (old) {
            std::wstring dest;
            if (same) dest=join(parents.path,randomName());
            else {
                const auto hp=join(parents.path,L"_history");
                if (!CreateDirectoryW(native(hp).c_str(),nullptr) && GetLastError()!=ERROR_ALREADY_EXISTS) fail(L"permission_denied");
                historyLease=std::make_unique<Parents>(hp);
                const auto dot=request.logicalName.rfind(L'.');
                const auto split=dot==std::wstring::npos || dot==0 ? request.logicalName.size() : dot;
                auto ts=timestamp();
#ifdef DVM_TESTING
                if (!hooks.timestamp.empty()) ts=hooks.timestamp;
#endif
                const auto stem=request.logicalName.substr(0,split)+L"_"+ts;
                const auto ext=request.logicalName.substr(split);
                for (unsigned i=0;i<10000;++i) {
                    wchar_t suffix[16]{}; if (i) swprintf_s(suffix,L"_%03u",i);
                    const auto name=stem+suffix+ext;
                    if (name.size()>255) fail(L"history_name_too_long",ERROR_FILENAME_EXCED_RANGE);
                    dest=join(historyLease->path,name);
                    DWORD e=0;
#ifdef DVM_TESTING
                    if (hooks.fault==L"old_move") e=ERROR_ACCESS_DENIED; else
#endif
                    e=rename(old->v,dest);
                    if (!e) { r.oldPath=dest; r.changed=true; break; }
                    if (e!=ERROR_FILE_EXISTS && e!=ERROR_ALREADY_EXISTS) fail(e==ERROR_ACCESS_DENIED ? L"permission_denied" : L"history_move_failed",e);
                }
                if (r.oldPath.empty()) fail(L"history_collision_limit",ERROR_ALREADY_EXISTS);
            }
            if (same) {
                const auto e=rename(old->v,dest); if (e) fail(L"rename_failed",e); r.oldPath=dest; r.changed=true;
            }
        }
#ifdef DVM_TESTING
        if (hooks.fault==L"crash_after_old_move") TerminateProcess(GetCurrentProcess(),77);
        if (hooks.fault==L"pause_after_old_move") Sleep(1500); // Test binary only; never in the distributed host.
#endif
        DWORD moveError=0;
#ifdef DVM_TESTING
        if (hooks.fault==L"new_move" || hooks.fault==L"rollback") moveError=ERROR_ACCESS_DENIED; else
#endif
        moveError=rename(n.v,target);
        if (moveError) {
            r.error=moveError; r.status=L"rename_failed";
            if (old) {
#ifdef DVM_TESTING
                if (hooks.fault==L"rollback") r.rollbackError=ERROR_ACCESS_DENIED; else
#endif
                r.rollbackError=rename(old->v,target);
                if (r.rollbackError) { r.status=L"rollback_failed"; r.changed=true; }
                else { r.oldPath=target; r.status=L"rename_failed_rolled_back"; r.changed=false; }
            }
            return r;
        }
        r.changed=true; r.ok=true; r.newPath=target;
        r.status=old ? same ? L"same_content_replaced" : L"changed_content_replaced" : L"renamed";
        // Restore the incoming object's times after rename (including NTFS name
        // tunneling), and never substitute the old object for an equal download.
        if (!SetFileTime(n.v,&ni.ftCreationTime,&ni.ftLastAccessTime,&ni.ftLastWriteTime)) { r.status=L"metadata_warning"; r.error=GetLastError(); }
        if (old && same) {
            FILE_DISPOSITION_INFO disp{}; disp.DeleteFile=TRUE; bool cleaned=false;
#ifdef DVM_TESTING
            if (hooks.fault==L"cleanup") SetLastError(ERROR_ACCESS_DENIED); else
#endif
            cleaned=!!SetFileInformationByHandle(old->v,FileDispositionInfo,&disp,sizeof(disp));
            if (!cleaned) { r.status=L"cleanup_required"; r.error=GetLastError(); }
            else r.oldPath.clear();
        }
        return r;
    } catch (const Error& e) { r.status=e.status; r.error=e.code; }
      catch (...) { r.status=L"internal_error"; r.error=ERROR_GEN_FAILURE; }
    return r;
}
}
