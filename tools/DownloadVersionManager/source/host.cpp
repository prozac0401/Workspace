#include "engine.h"
#include "json.h"
#include "identity.h" // Generated from version.json and the pinned public manifest key.
#include <shellapi.h>
#include <vector>
#include <set>

namespace {
bool read(void* bytes,DWORD n) {
    auto p=static_cast<unsigned char*>(bytes);
    while (n) { DWORD got=0; if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE),p,n,&got,nullptr) || !got) return false; p+=got; n-=got; } return true;
}
bool write(const std::string& s) {
    const DWORD n=static_cast<DWORD>(s.size()); DWORD got=0;
    if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),&n,sizeof(n),&got,nullptr) || got!=sizeof(n)) return false;
    size_t at=0;
    while (at<s.size()) { if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),s.data()+at,static_cast<DWORD>(s.size()-at),&got,nullptr) || !got) return false; at+=got; } return true;
}
std::string response(const dvm::Result& r) {
    return "{\"protocolVersion\":1,\"version\":" + dvm::quote(DVM_VERSION) + ",\"ok\":" + (r.ok ? "true" : "false") +
        ",\"status\":"+dvm::quote(r.status)+",\"changed\":"+(r.changed ? "true" : "false")+
        ",\"win32Error\":"+std::to_string(r.error)+",\"rollbackError\":"+std::to_string(r.rollbackError)+
        ",\"hashBytes\":"+std::to_string(r.hashBytes)+",\"compareMicroseconds\":"+std::to_string(r.compareMicroseconds)+
        ",\"targetPath\":"+dvm::quote(r.targetPath)+",\"newPath\":"+dvm::quote(r.newPath)+",\"oldPath\":"+dvm::quote(r.oldPath)+"}";
}
}
int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int) {
    dvm::Result result;
    try {
        int count=0; LPWSTR* args=CommandLineToArgvW(GetCommandLineW(),&count);
        const bool allowed=args && count>=2 && std::wstring(args[1])==DVM_ORIGIN;
        if (args) LocalFree(args);
        if (!allowed) { result.status=L"origin_denied"; write(response(result)); return 1; }
        DWORD n=0;
        if (!read(&n,sizeof(n)) || !n || n>65536) { result.status=L"invalid_frame"; write(response(result)); return 1; }
        std::string input(n,'\0');
        if (!read(input.data(),n)) { result.status=L"truncated_frame"; write(response(result)); return 1; }
        const auto fields=dvm::Json(input).parse();
        auto number=[&](const wchar_t* key) { const auto it=fields.find(key); if (it==fields.end() || !it->second.number) throw std::runtime_error("invalid_request"); return it->second.integer; };
        auto text=[&](const wchar_t* key) { const auto it=fields.find(key); if (it==fields.end() || it->second.number) throw std::runtime_error("invalid_request"); return it->second.text; };
        if (number(L"protocolVersion")!=1) { result.status=L"protocol_mismatch"; write(response(result)); return 1; }
        const auto op=text(L"operation");
        if (op==L"ping" && fields.size()==2) { result.ok=true; result.status=L"ready"; }
        else if (op==L"process") {
            std::set<std::wstring> allowedFields{L"protocolVersion",L"operation",L"newPath",L"logicalName",L"downloadId"};
#ifdef DVM_TESTING
            allowedFields.insert(L"_fault"); allowedFields.insert(L"_timestamp");
#endif
            for (const auto& f:fields) if (!allowedFields.count(f.first)) throw std::runtime_error("invalid_request");
            const dvm::Request request{text(L"newPath"),text(L"logicalName"),number(L"downloadId")};
#ifdef DVM_TESTING
            dvm::TestHooks hooks;
            if (fields.count(L"_fault")) hooks.fault=text(L"_fault");
            if (fields.count(L"_timestamp")) hooks.timestamp=text(L"_timestamp");
            result=dvm::process(request,hooks);
#else
            result=dvm::process(request);
#endif
        } else throw std::runtime_error("invalid_request");
    } catch (const std::exception&) { result.status=L"invalid_request"; }
      catch (...) { result.status=L"internal_error"; }
    return write(response(result)) ? result.ok ? 0 : 1 : 2;
}
