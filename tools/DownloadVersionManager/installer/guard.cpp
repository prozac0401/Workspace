// Read-only MSI preflight. Standard Windows Installer actions own all writes,
// servicing and rollback; this DLL neither edits registry nor deletes files.
#include <windows.h>
#include <msiquery.h>
#include <bcrypt.h>
#include <string>
#include <vector>
#include <array>
#include <sstream>
#include "payload.h"

namespace {
const wchar_t* productKey=L"Software\\Workspace\\DownloadVersionManager";
std::wstring prop(MSIHANDLE m,const wchar_t* key) {
    DWORD n=0; MsiGetPropertyW(m,key,L"",&n); std::vector<wchar_t> b(static_cast<size_t>(n)+1); ++n;
    if (MsiGetPropertyW(m,key,b.data(),&n)!=ERROR_SUCCESS) throw 1;
    return b.data();
}
std::wstring reg(const std::wstring& key,const wchar_t* name,HKEY root=HKEY_CURRENT_USER,REGSAM view=KEY_WOW64_64KEY) {
    HKEY h=nullptr; const auto e=RegOpenKeyExW(root,key.c_str(),0,KEY_QUERY_VALUE|view,&h);
    if (e==ERROR_FILE_NOT_FOUND) return L""; if (e!=ERROR_SUCCESS) throw 1;
    DWORD type=0,n=0; auto err=RegQueryValueExW(h,name,nullptr,&type,nullptr,&n);
    if (err==ERROR_FILE_NOT_FOUND) { RegCloseKey(h); return L""; }
    if (err!=ERROR_SUCCESS || type!=REG_SZ || n>65536 || n%2) { RegCloseKey(h); throw 1; }
    std::vector<wchar_t> b(n/2+1);
    err=RegQueryValueExW(h,name,nullptr,&type,reinterpret_cast<BYTE*>(b.data()),&n); RegCloseKey(h);
    if (err!=ERROR_SUCCESS) throw 1; return b.data();
}
bool equal(const std::wstring& a,const std::wstring& b) { return CompareStringOrdinal(a.c_str(),-1,b.c_str(),-1,TRUE)==CSTR_EQUAL; }
bool exists(const std::wstring& p) { return GetFileAttributesW(p.c_str())!=INVALID_FILE_ATTRIBUTES; }
std::string hash(const std::wstring& p) {
    HANDLE f=CreateFileW(p.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    if (f==INVALID_HANDLE_VALUE) throw 1;
    BY_HANDLE_FILE_INFORMATION i{};
    if (!GetFileInformationByHandle(f,&i) || (i.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))) { CloseHandle(f); throw 1; }
    BCRYPT_ALG_HANDLE alg=nullptr; BCRYPT_HASH_HANDLE h=nullptr; DWORD n=0,got=0;
    if (BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0) { CloseHandle(f); throw 1; }
    bool ok=BCryptGetProperty(alg,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&n),sizeof(n),&got,0)>=0;
    std::vector<unsigned char> object(n); std::array<unsigned char,65536> buffer{}; std::array<unsigned char,32> digest{};
    ok=ok && BCryptCreateHash(alg,&h,object.data(),n,nullptr,0,0)>=0;
    while (ok) { ok=!!ReadFile(f,buffer.data(),static_cast<DWORD>(buffer.size()),&got,nullptr); if (!ok || !got) break; ok=BCryptHashData(h,buffer.data(),got,0)>=0; }
    ok=ok && BCryptFinishHash(h,digest.data(),static_cast<ULONG>(digest.size()),0)>=0;
    if (h) BCryptDestroyHash(h); BCryptCloseAlgorithmProvider(alg,0); CloseHandle(f);
    if (!ok) throw 1;
    std::string out; for (auto b:digest) { out+="0123456789abcdef"[b>>4]; out+="0123456789abcdef"[b&15]; } return out;
}
std::string text(const std::wstring& p) {
    HANDLE f=CreateFileW(p.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    if (f==INVALID_HANDLE_VALUE) throw 1; LARGE_INTEGER n{};
    if (!GetFileSizeEx(f,&n) || n.QuadPart<1 || n.QuadPart>131072) { CloseHandle(f); throw 1; }
    std::string r(static_cast<size_t>(n.QuadPart),'\0'); DWORD got=0;
    const bool ok=!!ReadFile(f,r.data(),static_cast<DWORD>(r.size()),&got,nullptr); CloseHandle(f);
    if (!ok || got!=r.size()) throw 1; return r;
}
void plainParents(const std::wstring& input) {
    if (input.size()<4 || input[1]!=L':' || input[2]!=L'\\' || input.find(L"..")!=std::wstring::npos) throw 1;
    size_t at=3;
    for (;;) {
        at=input.find(L'\\',at); const auto prefix=input.substr(0,at);
        const auto attr=GetFileAttributesW(prefix.c_str());
        if (attr!=INVALID_FILE_ATTRIBUTES && (!(attr&FILE_ATTRIBUTE_DIRECTORY) || (attr&FILE_ATTRIBUTE_REPARSE_POINT))) throw 1;
        if (at==std::wstring::npos) break; ++at;
    }
}
}
extern "C" __declspec(dllexport) UINT __stdcall DvmPreflight(MSIHANDLE m) noexcept {
    try {
        auto folder=prop(m,L"INSTALLFOLDER"); if (folder.empty()) throw 1;
        if (folder.back()!=L'\\') folder+=L'\\'; plainParents(folder.substr(0,folder.size()-1));
        const auto owned=reg(productKey,L"InstallFolder");
        const bool servicing=!owned.empty();
        if (servicing && !equal(owned,folder)) throw 1;
        const std::wstring nativeKey=L"\\NativeMessagingHosts\\com.workspace.download_version_manager";
        for (const auto vendor:{L"Software\\Google\\Chrome",L"Software\\Microsoft\\Edge"}) {
            for (const auto view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}) {
                if (!reg(std::wstring(vendor)+nativeKey,nullptr,HKEY_LOCAL_MACHINE,view).empty()) throw 1;
                const auto actual=reg(std::wstring(vendor)+nativeKey,nullptr,HKEY_CURRENT_USER,view);
                if (!actual.empty() && (!servicing || !equal(actual,folder+L"native-host.json"))) throw 1;
            }
        }
        if (!servicing) {
            for (const auto f:DVM_FILES) if (exists(folder+f)) throw 1;
            if (exists(folder+L"ownership.tsv")) throw 1;
        } else {
            const auto inventory=folder+L"ownership.tsv";
            const auto expected=reg(productKey,L"InventorySha256");
            const auto actual=hash(inventory);
            if (expected!=std::wstring(actual.begin(),actual.end())) throw 1;
            std::istringstream in(text(inventory)); std::string line;
            if (!std::getline(in,line) || line!="DVM-OWNERSHIP-1") throw 1;
            while (std::getline(in,line)) {
                if (line.size()<66 || line[64]!='\t') throw 1;
                const auto relative=line.substr(65);
                if (relative.empty() || relative.find("..")!=std::string::npos || relative.find(':')!=std::string::npos || relative[0]=='\\' || relative[0]=='/') throw 1;
                const std::wstring fileName(relative.begin(),relative.end()); // Package paths are ASCII, not user data.
                const auto filePath=folder+fileName; const auto attrs=GetFileAttributesW(filePath.c_str());
                if (attrs==INVALID_FILE_ATTRIBUTES) { if (GetLastError()!=ERROR_FILE_NOT_FOUND && GetLastError()!=ERROR_PATH_NOT_FOUND) throw 1; }
                else if (hash(filePath)!=line.substr(0,64)) throw 1;
            }
        }
        return ERROR_SUCCESS;
    } catch (...) {
        PMSIHANDLE record=MsiCreateRecord(0);
        MsiRecordSetStringW(record,0,L"DownloadVersionManager: 기존 설치 파일 또는 브라우저 등록이 다른 상태여서 보존을 위해 중단했습니다. 설치 위치와 등록을 확인하세요.");
        MsiProcessMessage(m,INSTALLMESSAGE_ERROR,record);
        return ERROR_INSTALL_FAILURE;
    }
}
#ifdef DVM_INSTALLER_TESTING
// Isolated lifecycle fixture only. Fail inside the transaction after payload and
// native registration writes, before Windows Installer publishes the product.
extern "C" __declspec(dllexport) UINT __stdcall DvmFailRollbackTest(MSIHANDLE) noexcept {
    return ERROR_INSTALL_FAILURE;
}
#endif
