#include "engine.h"
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>

namespace fs=std::filesystem;
namespace {
void require(bool condition,const char* message) { if (!condition) throw std::runtime_error(message); }
std::wstring native(const fs::path& path) { return L"\\\\?\\"+path.wstring(); }
struct Handle {
    HANDLE value=INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE h):value(h) {}
    ~Handle() { if (value!=INVALID_HANDLE_VALUE && value) CloseHandle(value); }
};
BY_HANDLE_FILE_INFORMATION snapshot(const fs::path& path) {
    Handle h(CreateFileW(native(path).c_str(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
    require(h.value!=INVALID_HANDLE_VALUE,"snapshot open failed");
    BY_HANDLE_FILE_INFORMATION result{};
    require(!!GetFileInformationByHandle(h.value,&result),"snapshot read failed");
    return result;
}
bool sameObject(const BY_HANDLE_FILE_INFORMATION& a,const BY_HANDLE_FILE_INFORMATION& b) {
    return a.dwVolumeSerialNumber==b.dwVolumeSerialNumber && a.nFileIndexHigh==b.nFileIndexHigh && a.nFileIndexLow==b.nFileIndexLow;
}
void write(const fs::path& path,const std::string& bytes) {
    std::ofstream stream(path,std::ios::binary|std::ios::trunc);
    stream.write(bytes.data(),static_cast<std::streamsize>(bytes.size()));
    require(!!stream,"fixture write failed");
}
std::string read(const fs::path& path) {
    std::ifstream stream(path,std::ios::binary);
    require(!!stream,"fixture read failed");
    return {std::istreambuf_iterator<char>(stream),std::istreambuf_iterator<char>()};
}
dvm::Request request(const fs::path& source) {
    dvm::Request result;
    result.newPath=source.wstring(); result.logicalName=L"report.bin";
    result.folderPair=true; result.requireSnapshot=true; result.expectedSource=snapshot(source);
    return result;
}
void pair(const fs::path& directory,const std::string& oldBytes="OLD!",const std::string& newBytes="NEW!") {
    write(directory/L"report.bin",oldBytes); write(directory/L"report (1).bin",newBytes);
}
std::vector<fs::path> history(const fs::path& directory) {
    std::vector<fs::path> result;
    if (fs::exists(directory/L"_history")) for (const auto& item:fs::directory_iterator(directory/L"_history")) result.push_back(item.path());
    return result;
}
std::wstring uniqueName() {
    unsigned char bytes[16]{};
    require(BCryptGenRandom(nullptr,bytes,sizeof(bytes),BCRYPT_USE_SYSTEM_PREFERRED_RNG)>=0,"fixture random name failed");
    std::wstring result=L"engine-fixtures-";
    for (const auto b:bytes) { result+=L"0123456789abcdef"[b>>4]; result+=L"0123456789abcdef"[b&15]; }
    return result;
}
DWORD crashChild(const fs::path& directory) {
    wchar_t executable[32768]{};
    require(GetModuleFileNameW(nullptr,executable,32768)!=0,"test executable path unavailable");
    std::wstring command=L"\""+std::wstring(executable)+L"\" --crash \""+directory.wstring()+L"\"";
    STARTUPINFOW startup{}; startup.cb=sizeof(startup); PROCESS_INFORMATION process{};
    require(!!CreateProcessW(executable,command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process),"crash child launch failed");
    Handle child(process.hProcess),thread(process.hThread);
    const DWORD wait=WaitForSingleObject(child.value,15000);
    if (wait==WAIT_TIMEOUT) { TerminateProcess(child.value,88); WaitForSingleObject(child.value,5000); }
    require(wait==WAIT_OBJECT_0,"crash child did not complete");
    DWORD exitCode=0; require(!!GetExitCodeProcess(child.value,&exitCode),"crash child exit unavailable"); return exitCode;
}
}

int wmain(int argc,wchar_t** argv) {
    try {
        if (argc==3 && std::wstring(argv[1])==L"--crash") {
            const auto result=dvm::process(request(fs::path(argv[2])/L"report (1).bin"),{L"crash_after_old_move",L"20261004_120000"});
            std::cerr<<"Expected interruption was not reached: "<<result.error<<'\n'; return 2;
        }
        require(argc==3 && std::wstring(argv[1])==L"--root","usage: engine-tests --root absolute-artifact-directory");
        const fs::path output(argv[2]); require(output.is_absolute(),"fixture output must be absolute");
        const auto root=output/uniqueName(); fs::create_directories(root);
        struct Test { std::string name; bool passed; std::string reason; };
        std::vector<Test> tests;
        auto run=[&](const char* name,const std::function<void(const fs::path&)>& action) {
            const auto directory=root/std::to_wstring(tests.size()); fs::create_directory(directory);
            try { action(directory); tests.push_back({name,true,{}}); }
            catch (const std::exception& error) { tests.push_back({name,false,error.what()}); }
            std::cout<<name<<": "<<(tests.back().passed ? "PASS" : "FAIL")<<'\n';
            if (!tests.back().passed) std::cout<<tests.back().reason<<'\n';
        };
        run("folder pair identical content retains new object and times",[](const fs::path& directory) {
            pair(directory,"same","same"); const auto source=directory/L"report (1).bin";
            const auto before=snapshot(source); const auto result=dvm::process(request(source));
            require(result.ok && result.status==L"same_content_replaced","same-content pair failed");
            const auto after=snapshot(directory/L"report.bin");
            require(sameObject(before,after),"incoming object was not retained");
            require(CompareFileTime(&before.ftCreationTime,&after.ftCreationTime)==0 && CompareFileTime(&before.ftLastWriteTime,&after.ftLastWriteTime)==0,"incoming times were not retained");
            require(!fs::exists(source) && !fs::exists(directory/L"_history") && read(directory/L"report.bin")=="same","same-content final files incorrect");
        });
        run("folder pair changed content preserves old history",[](const fs::path& directory) {
            pair(directory); const auto source=directory/L"report (1).bin"; const auto before=snapshot(source);
            const auto result=dvm::process(request(source),{{},L"20261004_120000"});
            require(result.ok && result.status==L"changed_content_replaced","changed-content pair failed");
            const auto versions=history(directory);
            require(versions.size()==1 && versions[0].filename()==L"report_20261004_120000.bin" && read(versions[0])=="OLD!","old history incorrect");
            require(read(directory/L"report.bin")=="NEW!" && sameObject(before,snapshot(directory/L"report.bin")) && !fs::exists(source),"new canonical object incorrect");
        });
        run("folder pair missing target preserves source",[](const fs::path& directory) {
            const auto source=directory/L"report (1).bin"; write(source,"NEW!"); const auto result=dvm::process(request(source));
            require(!result.ok && !result.changed && result.status==L"target_missing","missing target was not rejected");
            require(read(source)=="NEW!" && !fs::exists(directory/L"report.bin") && !fs::exists(directory/L"_history"),"missing target changed files");
        });
        run("folder pair locked target preserves both",[](const fs::path& directory) {
            pair(directory); const auto source=directory/L"report (1).bin";
            Handle lock(CreateFileW(native(directory/L"report.bin").c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,0,nullptr));
            require(lock.value!=INVALID_HANDLE_VALUE,"fixture target lock failed");
            const auto result=dvm::process(request(source));
            require(!result.ok && !result.changed && result.status==L"target_locked","locked target was not preserved");
            require(read(directory/L"report.bin")=="OLD!" && read(source)=="NEW!" && !fs::exists(directory/L"_history"),"locked target changed files");
        });
        run("folder pair changed source snapshot preserves both",[](const fs::path& directory) {
            pair(directory); const auto source=directory/L"report (1).bin"; const auto expected=request(source);
            write(source,"new data after observation"); const auto result=dvm::process(expected);
            require(!result.ok && !result.changed && result.status==L"source_changed","changed source was not rejected");
            require(read(directory/L"report.bin")=="OLD!" && read(source)=="new data after observation" && !fs::exists(directory/L"_history"),"snapshot rejection changed files");
        });
        run("folder pair changed target after preview preserves both",[](const fs::path& directory) {
            pair(directory); const auto source=directory/L"report (1).bin"; auto expected=request(source);
            expected.requireTargetSnapshot=true; expected.expectedTarget=snapshot(directory/L"report.bin");
            write(directory/L"report.bin","target changed after preview"); const auto result=dvm::process(expected);
            require(!result.ok && !result.changed && result.status==L"target_changed","changed target was not rejected");
            require(read(directory/L"report.bin")=="target changed after preview" && read(source)=="NEW!" && !fs::exists(directory/L"_history"),"preview rejection changed files");
        });
        run("folder pair incoming move failure rolls back old object",[](const fs::path& directory) {
            pair(directory); const auto source=directory/L"report (1).bin"; const auto old=snapshot(directory/L"report.bin");
            const auto result=dvm::process(request(source),{L"new_move",L"20261004_120000"});
            require(!result.ok && !result.changed && result.status==L"rename_failed_rolled_back" && result.rollbackError==0,"pair rollback failed");
            require(read(directory/L"report.bin")=="OLD!" && sameObject(old,snapshot(directory/L"report.bin")) && read(source)=="NEW!" && history(directory).empty(),"rollback did not preserve both objects");
        });
        run("folder pair interrupted after old move retains both contents",[](const fs::path& directory) {
            pair(directory); require(crashChild(directory)==77,"wrong interruption exit code");
            const auto versions=history(directory);
            require(!fs::exists(directory/L"report.bin") && read(directory/L"report (1).bin")=="NEW!" && versions.size()==1 && read(versions[0])=="OLD!","interruption lost a file");
        });
        size_t failed=0; for (const auto& test:tests) if (!test.passed) ++failed;
        std::ofstream report(output/L"engine-results.json",std::ios::binary);
        report<<"{\"passed\":"<<(tests.size()-failed)<<",\"failed\":"<<failed<<",\"tests\":[";
        for (size_t i=0;i<tests.size();++i) { if (i) report<<','; report<<"{\"name\":\""<<tests[i].name<<"\",\"status\":\""<<(tests[i].passed ? "PASS" : "FAIL")<<"\"}"; }
        report<<"]}\n"; require(!!report,"test report write failed");
        std::cout<<(tests.size()-failed)<<" PASS / "<<failed<<" FAIL\n";
        return failed ? 1 : 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 2; }
}
