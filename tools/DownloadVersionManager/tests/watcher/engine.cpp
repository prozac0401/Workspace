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

FILETIME utc(WORD year,WORD month,WORD day,WORD hour,WORD minute,WORD second,WORD milliseconds=0) {
    SYSTEMTIME value{}; value.wYear=year; value.wMonth=month; value.wDay=day;
    value.wHour=hour; value.wMinute=minute; value.wSecond=second; value.wMilliseconds=milliseconds;
    FILETIME result{}; require(!!SystemTimeToFileTime(&value,&result),"fixture UTC conversion failed"); return result;
}
void times(const fs::path& path,const FILETIME& creation,const FILETIME& modified) {
    Handle h(CreateFileW(native(path).c_str(),FILE_WRITE_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
    require(h.value!=INVALID_HANDLE_VALUE,"fixture time open failed");
    require(!!SetFileTime(h.value,&creation,nullptr,&modified),"fixture time write failed");
}
void preserved(const BY_HANDLE_FILE_INFORMATION& before,const fs::path& path,const std::string& bytes) {
    const auto after=snapshot(path);
    require(sameObject(before,after),"preserved file object changed");
    require(CompareFileTime(&before.ftCreationTime,&after.ftCreationTime)==0,"preserved creation time changed");
    require(CompareFileTime(&before.ftLastWriteTime,&after.ftLastWriteTime)==0,"preserved last-write time changed");
    require(before.dwFileAttributes==after.dwFileAttributes,"preserved attributes changed");
    require(read(path)==bytes,"preserved content changed");
}
std::wstring localStamp(const FILETIME& modified,const DYNAMIC_TIME_ZONE_INFORMATION* overrideZone=nullptr) {
    DYNAMIC_TIME_ZONE_INFORMATION zone{};
    if (overrideZone) zone=*overrideZone;
    else require(GetDynamicTimeZoneInformation(&zone)!=TIME_ZONE_ID_INVALID,"fixture timezone unavailable");
    SYSTEMTIME universal{},local{};
    require(!!FileTimeToSystemTime(&modified,&universal),"fixture FILETIME conversion failed");
    require(!!SystemTimeToTzSpecificLocalTimeEx(&zone,&universal,&local),"fixture local conversion failed");
    wchar_t text[32]{};
    swprintf_s(text,L"%04u%02u%02u_%02u%02u%02u",local.wYear,local.wMonth,local.wDay,local.wHour,local.wMinute,local.wSecond);
    return text;
}
std::wstring archiveName(const FILETIME& modified,unsigned collision=0) {
    wchar_t suffix[16]{}; if (collision) swprintf_s(suffix,L"_%03u",collision);
    return L"report_"+localStamp(modified)+suffix+L".bin";
}
DYNAMIC_TIME_ZONE_INFORMATION pacificZone() {
    DYNAMIC_TIME_ZONE_INFORMATION result{};
    for (DWORD index=0;index<4096;++index) {
        const auto error=EnumDynamicTimeZoneInformation(index,&result);
        if (error==ERROR_NO_MORE_ITEMS) break;
        require(error==ERROR_SUCCESS,"fixture timezone enumeration failed");
        if (std::wstring(result.TimeZoneKeyName)==L"Pacific Standard Time") return result;
    }
    throw std::runtime_error("Pacific historical timezone unavailable");
}
dvm::Request legacyRequest(const fs::path& source,uint64_t at,const wchar_t* token) {
    auto result=request(source); result.folderPair=false; result.completedAt=at; result.requestToken=token; return result;
}
std::wstring orderName(const fs::path& target) {
    const auto path=target.wstring(); std::wstring folded(path.size(),L'\0');
    require(!!LCMapStringEx(LOCALE_NAME_INVARIANT,LCMAP_LOWERCASE,path.data(),static_cast<int>(path.size()),folded.data(),static_cast<int>(folded.size()),nullptr,nullptr,0),"fixture order path case failed");
    const auto count=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,folded.data(),static_cast<int>(folded.size()),nullptr,0,nullptr,nullptr);
    require(count>0,"fixture order UTF-8 size failed");
    std::string bytes(static_cast<size_t>(count),'\0');
    require(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,folded.data(),static_cast<int>(folded.size()),bytes.data(),count,nullptr,nullptr)==count,"fixture order UTF-8 failed");
    BCRYPT_ALG_HANDLE algorithm=nullptr;
    require(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0,"fixture order hash open failed");
    std::vector<unsigned char> digest(32);
    const auto error=BCryptHash(algorithm,nullptr,0,reinterpret_cast<PUCHAR>(bytes.data()),static_cast<ULONG>(bytes.size()),digest.data(),static_cast<ULONG>(digest.size()));
    BCryptCloseAlgorithmProvider(algorithm,0);
    require(error>=0,"fixture order hash failed");
    std::wstring name; for (const auto b:digest) { name+=L"0123456789abcdef"[b>>4]; name+=L"0123456789abcdef"[b&15]; } return name;
}
struct OwnedOrderValue {
    std::wstring name; bool cleaned=false;
    static constexpr const wchar_t* keyName=L"Software\\Workspace\\DownloadVersionManager\\CompletionOrder";
    explicit OwnedOrderValue(const fs::path& target):name(orderName(target)) {
        HKEY key=nullptr; const auto opened=RegOpenKeyExW(HKEY_CURRENT_USER,keyName,0,KEY_QUERY_VALUE|KEY_WOW64_64KEY,&key);
        if (opened==ERROR_FILE_NOT_FOUND) return;
        require(opened==ERROR_SUCCESS,"fixture order key check failed");
        DWORD bytes=0; const auto found=RegQueryValueExW(key,name.c_str(),nullptr,nullptr,nullptr,&bytes); RegCloseKey(key);
        require(found==ERROR_FILE_NOT_FOUND,"unexpected existing completion value must be preserved");
    }
    DWORD remove() {
        HKEY key=nullptr; const auto opened=RegOpenKeyExW(HKEY_CURRENT_USER,keyName,0,KEY_SET_VALUE|KEY_WOW64_64KEY,&key);
        if (opened==ERROR_FILE_NOT_FOUND) return ERROR_SUCCESS;
        if (opened!=ERROR_SUCCESS) return opened;
        const auto error=RegDeleteValueW(key,name.c_str()); RegCloseKey(key);
        return error==ERROR_FILE_NOT_FOUND ? ERROR_SUCCESS : error;
    }
    void clear() { require(remove()==ERROR_SUCCESS,"fixture completion value cleanup failed"); cleaned=true; }
    ~OwnedOrderValue() { if (!cleaned) remove(); } // Never removes the shared key or any other value.
};

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

        run("history name uses old last-write time and preserves both objects",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            const auto oldTime=utc(2024,9,27,0,42,37,321),newTime=utc(2025,11,6,4,3,19,654);
            times(target,utc(2001,1,2,3,4,5),oldTime); times(source,utc(2002,2,3,4,5,6),newTime);
            FILETIME now{}; GetSystemTimeAsFileTime(&now);
            require(localStamp(oldTime)!=localStamp(newTime) && localStamp(oldTime)!=localStamp(now),"fixture clocks are not distinct");
            const auto oldBefore=snapshot(target),newBefore=snapshot(source);
            const auto result=dvm::process(request(source));
            require(result.ok && result.status==L"changed_content_replaced","real-mtime folder pair failed");
            const auto versions=history(directory);
            require(versions.size()==1 && versions[0].filename()==archiveName(oldTime),"history used incoming/current/creation time");
            preserved(oldBefore,versions[0],"OLD!"); preserved(newBefore,target,"NEW!");
            require(!fs::exists(source) && result.oldPath==versions[0].wstring(),"archive result path incorrect");
        });
        run("legacy later completion archives old object's last-write time",[](const fs::path& directory) {
            const auto target=directory/L"report.bin",source=directory/L"incoming.bin";
            write(target,"LEGACY-OLD"); write(source,"LEGACY-NEW");
            const auto oldTime=utc(2019,7,8,9,10,11,123),newTime=utc(2023,4,5,6,7,8,456);
            times(target,utc(2001,1,1,0,0,1),oldTime); times(source,utc(2002,1,1,0,0,2),newTime);
            const auto oldBefore=snapshot(target),newBefore=snapshot(source); OwnedOrderValue order(target);
            const auto first=dvm::process(legacyRequest(target,1000,L"00000000000000000000000000000001"));
            require(first.ok && first.status==L"already_current","legacy completion seed failed");
            const auto result=dvm::process(legacyRequest(source,2000,L"00000000000000000000000000000002"));
            require(result.ok && result.status==L"changed_content_replaced","legacy normal archive failed");
            const auto versions=history(directory);
            require(versions.size()==1 && versions[0].filename()==archiveName(oldTime),"legacy normal archive used wrong object time");
            preserved(oldBefore,versions[0],"LEGACY-OLD"); preserved(newBefore,target,"LEGACY-NEW");
            require(!fs::exists(source),"legacy source remained after rename"); order.clear();
        });
        run("legacy stale completion archives incoming object's last-write time",[](const fs::path& directory) {
            const auto target=directory/L"report.bin",source=directory/L"incoming.bin";
            write(target,"CURRENT-CONTENT"); write(source,"DELAYED-CONTENT");
            const auto currentTime=utc(2025,2,3,4,5,6,321),incomingTime=utc(2018,6,7,8,9,10,654);
            times(target,utc(2001,2,1,0,0,1),currentTime); times(source,utc(2002,2,1,0,0,2),incomingTime);
            const auto currentBefore=snapshot(target),incomingBefore=snapshot(source); OwnedOrderValue order(target);
            const auto first=dvm::process(legacyRequest(target,2000,L"00000000000000000000000000000003"));
            require(first.ok && first.status==L"already_current","legacy stale completion seed failed");
            const auto result=dvm::process(legacyRequest(source,1000,L"00000000000000000000000000000004"));
            require(result.ok && result.status==L"superseded_archived","legacy stale archive failed");
            const auto versions=history(directory);
            require(versions.size()==1 && versions[0].filename()==archiveName(incomingTime),"stale archive used canonical old time");
            preserved(incomingBefore,versions[0],"DELAYED-CONTENT"); preserved(currentBefore,target,"CURRENT-CONTENT");
            require(!fs::exists(source) && result.newPath==versions[0].wstring(),"stale result path incorrect"); order.clear();
        });
        run("existing historical names and colliding archives are preserved",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            const auto modified=utc(2020,8,9,10,11,12,789); times(target,utc(2001,1,1,0,0,1),modified);
            const auto hp=directory/L"_history"; fs::create_directory(hp);
            const auto legacy=hp/L"report_20261005_121912.bin",collision=hp/archiveName(modified),collisionOne=hp/archiveName(modified,1);
            write(legacy,"PREVIOUS-NAMING-RULE"); write(collision,"EXISTING-BASE"); write(collisionOne,"EXISTING-001");
            const auto legacyBefore=snapshot(legacy),baseBefore=snapshot(collision),oneBefore=snapshot(collisionOne),oldBefore=snapshot(target);
            const auto result=dvm::process(request(source));
            require(result.ok && fs::exists(hp/archiveName(modified,2)) && history(directory).size()==4,"existing collision suffix incorrect");
            preserved(legacyBefore,legacy,"PREVIOUS-NAMING-RULE"); preserved(baseBefore,collision,"EXISTING-BASE"); preserved(oneBefore,collisionOne,"EXISTING-001");
            preserved(oldBefore,hp/archiveName(modified,2),"OLD!");
        });
        run("equal last-write times receive suffix without overwriting",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            const auto modified=utc(2021,3,4,5,6,7,123); times(target,utc(2001,1,1,0,0,1),modified); times(source,utc(2002,1,1,0,0,2),modified);
            const auto firstBefore=snapshot(target),secondBefore=snapshot(source);
            require(dvm::process(request(source)).ok,"first equal-time archive failed");
            const auto hp=directory/L"_history"; preserved(firstBefore,hp/archiveName(modified),"OLD!");
            write(source,"THIRD"); times(source,utc(2003,1,1,0,0,3),utc(2022,4,5,6,7,8));
            const auto result=dvm::process(request(source));
            require(result.ok && history(directory).size()==2,"second equal-time archive failed");
            preserved(firstBefore,hp/archiveName(modified),"OLD!"); preserved(secondBefore,hp/archiveName(modified,1),"NEW!");
            require(read(target)=="THIRD","equal-time current content incorrect");
        });
        run("different fractions of the same second collide without rounding",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            const auto firstTime=utc(2021,8,9,10,11,12,100),secondTime=utc(2021,8,9,10,11,12,900);
            require(CompareFileTime(&firstTime,&secondTime)!=0 && localStamp(firstTime)==localStamp(secondTime),"same-second fixture invalid");
            times(target,utc(2001,1,1,0,0,1),firstTime); times(source,utc(2002,1,1,0,0,2),secondTime);
            const auto firstBefore=snapshot(target),secondBefore=snapshot(source);
            require(dvm::process(request(source)).ok,"first fractional-second archive failed");
            write(source,"THIRD"); const auto result=dvm::process(request(source)); const auto hp=directory/L"_history";
            require(result.ok && history(directory).size()==2,"fractional-second archive collision failed");
            preserved(firstBefore,hp/archiveName(firstTime),"OLD!"); preserved(secondBefore,hp/archiveName(firstTime,1),"NEW!");
        });
        run("history collision limit preserves all 10000 names and both originals",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            const auto modified=utc(2020,1,2,3,4,5,678); times(target,utc(2001,1,1,0,0,1),modified);
            const auto oldBefore=snapshot(target),newBefore=snapshot(source); const auto hp=directory/L"_history"; fs::create_directory(hp);
            const auto stem=L"report_"+localStamp(modified);
            auto collisionName=[&](unsigned i) { wchar_t suffix[16]{}; if (i) swprintf_s(suffix,L"_%03u",i); return stem+suffix+L".bin"; };
            for (unsigned i=0;i<10000;++i) write(hp/collisionName(i),"existing-"+std::to_string(i));
            const auto result=dvm::process(request(source));
            require(!result.ok && !result.changed && result.status==L"history_collision_limit" && result.error==ERROR_ALREADY_EXISTS && result.oldPath.empty(),"collision bound changed");
            preserved(oldBefore,target,"OLD!"); preserved(newBefore,source,"NEW!"); require(history(directory).size()==10000,"collision bound added/removed an archive");
            for (unsigned i=0;i<10000;++i) require(read(hp/collisionName(i))=="existing-"+std::to_string(i),"collision bound overwrote an existing archive");
        });
        run("historical Pacific timezone rules use date-specific DST",[](const fs::path& directory) {
            const auto zone=pacificZone(); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            struct Example { FILETIME modified; const wchar_t* expected; };
            const Example examples[]={
                {utc(2006,3,15,12,34,56),L"report_20060315_043456.bin"},
                {utc(2024,3,15,12,34,56),L"report_20240315_053456.bin"},
                {utc(2024,1,15,12,34,56),L"report_20240115_043456.bin"},
                {utc(2024,7,15,12,34,56),L"report_20240715_053456.bin"}
            };
            for (const auto& example:examples) {
                pair(directory); times(target,utc(2001,1,1,0,0,1),example.modified); const auto before=snapshot(target);
                const auto result=dvm::process(request(source),{{},{},&zone});
                require(result.ok && result.status==L"changed_content_replaced","historical timezone archive failed");
                const auto expected=directory/L"_history"/example.expected;
                require(fs::exists(expected),"historical DST filename incorrect"); preserved(before,expected,"OLD!");
            }
            require(history(directory).size()==4,"historical timezone archive count incorrect");
        });
        struct TimeFault { const wchar_t* fault; DWORD error; const char* name; };
        const TimeFault faults[]={
            {L"history_time_read",ERROR_READ_FAULT,"history time read failure preserves both originals before history creation"},
            {L"history_timezone",ERROR_INVALID_DATA,"history timezone lookup failure preserves both originals before history creation"},
            {L"history_time_convert",ERROR_INVALID_PARAMETER,"history local conversion failure preserves both originals before history creation"},
            {L"history_time_invalid",ERROR_INVALID_PARAMETER,"invalid FILETIME cannot bypass validation through test timestamp"}
        };
        for (const auto& fault:faults) run(fault.name,[&](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            times(target,utc(2001,1,1,0,0,1),utc(2024,9,27,0,42,37,321));
            const auto oldBefore=snapshot(target),newBefore=snapshot(source);
            const auto result=dvm::process(request(source),{fault.fault,L"20990101_000000"});
            require(!result.ok && !result.changed && result.status==L"file_info_failed" && result.error==fault.error && result.oldPath.empty(),"history timestamp failure status incorrect");
            require(!fs::exists(directory/L"_history"),"timestamp failure created history directory");
            preserved(oldBefore,target,"OLD!"); preserved(newBefore,source,"NEW!");
        });

        const wchar_t* accessFaults[]={L"parent_open",L"file_open",L"history_create"};
        const char* accessNames[]={
            "parent folder open access failure preserves files without readonly claim",
            "file open access failure preserves files without readonly claim",
            "history creation access failure preserves files without readonly claim"
        };
        for (size_t i=0;i<3;++i) run(accessNames[i],[&](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            const auto oldBefore=snapshot(target),newBefore=snapshot(source);
            const auto result=dvm::process(request(source),{accessFaults[i],{}});
            require(!result.ok && !result.changed && result.status==L"permission_denied" && result.error==ERROR_ACCESS_DENIED && !result.readOnlyProtected,"unconfirmed access failure was mislabeled readonly");
            require(result.oldPath.empty() && !fs::exists(directory/L"_history"),"access failure changed history path");
            preserved(oldBefore,target,"OLD!"); preserved(newBefore,source,"NEW!");
        });
        run("confirmed read-only canonical file supplies protection reason",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            require(!!SetFileAttributesW(native(target).c_str(),FILE_ATTRIBUTE_READONLY),"fixture readonly target failed");
            const auto oldBefore=snapshot(target),newBefore=snapshot(source); const auto result=dvm::process(request(source));
            require(!result.ok && !result.changed && result.status==L"permission_denied" && result.error==ERROR_ACCESS_DENIED && result.readOnlyProtected,"canonical readonly reason missing");
            require(!fs::exists(directory/L"_history"),"readonly target created history"); preserved(oldBefore,target,"OLD!"); preserved(newBefore,source,"NEW!");
        });
        run("confirmed read-only incoming file supplies protection reason",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            require(!!SetFileAttributesW(native(source).c_str(),FILE_ATTRIBUTE_READONLY),"fixture readonly source failed");
            const auto oldBefore=snapshot(target),newBefore=snapshot(source); const auto result=dvm::process(request(source));
            require(!result.ok && !result.changed && result.status==L"permission_denied" && result.error==ERROR_ACCESS_DENIED && result.readOnlyProtected,"incoming readonly reason missing");
            require(!fs::exists(directory/L"_history"),"readonly source created history"); preserved(oldBefore,target,"OLD!"); preserved(newBefore,source,"NEW!");
        });
        run("other history move access failure does not claim read-only protection",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin";
            const auto oldBefore=snapshot(target),newBefore=snapshot(source); const auto result=dvm::process(request(source),{L"old_move",{}});
            require(!result.ok && !result.changed && result.status==L"permission_denied" && result.error==ERROR_ACCESS_DENIED && !result.readOnlyProtected,"access error was mislabeled readonly");
            require(history(directory).empty(),"failed history move created archive"); preserved(oldBefore,target,"OLD!"); preserved(newBefore,source,"NEW!");
        });
        run("history occupied by ordinary file preserves files without readonly claim",[](const fs::path& directory) {
            pair(directory); const auto target=directory/L"report.bin",source=directory/L"report (1).bin",occupied=directory/L"_history";
            write(occupied,"USER-OWNED-FILE"); const auto oldBefore=snapshot(target),newBefore=snapshot(source),occupiedBefore=snapshot(occupied);
            const auto result=dvm::process(request(source));
            require(!result.ok && !result.changed && !result.readOnlyProtected,"occupied history path was changed or mislabeled");
            preserved(oldBefore,target,"OLD!"); preserved(newBefore,source,"NEW!"); preserved(occupiedBefore,occupied,"USER-OWNED-FILE");
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
