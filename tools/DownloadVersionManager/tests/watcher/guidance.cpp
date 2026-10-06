#include "watcher.h"
#include "engine.h"
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace fs=std::filesystem;
namespace {
void require(bool condition,const char* message) { if (!condition) throw std::runtime_error(message); }
void includes(const std::wstring& text,const std::wstring& expected,const char* message) {
    require(text.find(expected)!=std::wstring::npos,message);
}
void reasonFirst(const std::wstring& text,const std::wstring& reason,const std::wstring& name,DWORD error) {
    require(text.rfind(reason,0)==0,"confirmed/generic reason is not first");
    includes(text,L"permission_denied","existing permission status missing");
    includes(text,L"오류 "+std::to_wstring(error),"Windows error missing");
    includes(text,name,"complete filename missing");
    require(text.find(L"permission_denied")<text.find(name),"status is hidden behind filename");
    require(text.find(L"감시를 중지")==std::wstring::npos && text.find(L"속성을 해제")==std::wstring::npos && text.find(L"권한을 변경")==std::wstring::npos,"message changed policy or claimed watcher stopped");
}
}

int wmain(int argc,wchar_t** argv) {
    try {
        require(argc==3 && std::wstring(argv[1])==L"--root","usage: guidance-tests --root absolute-artifact-directory");
        const fs::path output(argv[2]); require(output.is_absolute() && fs::is_directory(output),"report output must be an existing absolute directory");
        struct Test { std::string name; bool passed; std::string reason; };
        std::vector<Test> tests;
        auto run=[&](const char* name,const std::function<void()>& action) {
            try { action(); tests.push_back({name,true,{}}); }
            catch (const std::exception& error) { tests.push_back({name,false,error.what()}); }
            std::cout<<name<<": "<<(tests.back().passed ? "PASS" : "FAIL")<<'\n';
            if (!tests.back().passed) std::cout<<tests.back().reason<<'\n';
        };
        run("confirmed readonly reason precedes short filename and preserves status/error",[] {
            dvm::Result result; result.status=L"permission_denied"; result.error=ERROR_ACCESS_DENIED; result.readOnlyProtected=true;
            reasonFirst(dvm::resultMessage(L"report (1).bin",result),L"읽기 전용 보호: 파일 보존",L"report (1).bin",ERROR_ACCESS_DENIED);
        });
        run("confirmed readonly reason precedes complete long filename",[] {
            const auto name=std::wstring(220,L'a')+L" (1).bin";
            dvm::Result result; result.status=L"permission_denied"; result.error=ERROR_ACCESS_DENIED; result.readOnlyProtected=true;
            reasonFirst(dvm::resultMessage(name,result),L"읽기 전용 보호: 파일 보존",name,ERROR_ACCESS_DENIED);
        });
        run("access denied code five without confirmed reason stays generic",[] {
            dvm::Result result; result.status=L"permission_denied"; result.error=ERROR_ACCESS_DENIED;
            const auto text=dvm::resultMessage(L"report (1).bin",result);
            reasonFirst(text,L"접근 실패: 파일 보존",L"report (1).bin",ERROR_ACCESS_DENIED);
            require(text.find(L"읽기 전용")==std::wstring::npos,"unconfirmed access error claimed readonly");
        });
        run("other file/folder/history access error preserves actual Windows code",[] {
            dvm::Result result; result.status=L"permission_denied"; result.error=ERROR_PATH_NOT_FOUND;
            const auto text=dvm::resultMessage(L"report (1).bin",result);
            reasonFirst(text,L"접근 실패: 파일 보존",L"report (1).bin",ERROR_PATH_NOT_FOUND);
            require(text.find(L"읽기 전용")==std::wstring::npos,"other access error claimed readonly");
        });
        run("timestamp file-information failure preserves state/error/name",[] {
            dvm::Result result; result.status=L"file_info_failed"; result.error=ERROR_READ_FAULT;
            const auto text=dvm::resultMessage(L"report (1).bin",result);
            require(text.rfind(L"파일 정보 확인 실패: 파일 보존",0)==0,"timestamp failure reason missing");
            includes(text,L"file_info_failed","timestamp failure status missing"); includes(text,L"오류 30","timestamp Windows code missing");
            includes(text,L"report (1).bin","timestamp filename missing");
            require(text.find(L"읽기 전용")==std::wstring::npos,"file information error claimed readonly");
        });
        run("same-content success message stays unchanged",[] {
            dvm::Result result; result.ok=true; result.changed=true; result.status=L"same_content_replaced";
            require(dvm::resultMessage(L"report (1).bin",result)==L"report (1).bin → 최신 파일로 변경했습니다. 내용은 같습니다.","same-content success text changed");
        });
        run("changed-content success message stays unchanged",[] {
            dvm::Result result; result.ok=true; result.changed=true; result.status=L"changed_content_replaced";
            require(dvm::resultMessage(L"report (1).bin",result)==L"report (1).bin → 최신 파일로 변경하고 이전 내용을 _history에 보관했습니다.","changed-content success text changed");
        });
        run("target and incoming lock warnings stay unchanged",[] {
            for (const auto* status:{L"target_locked",L"new_file_locked"}) {
                dvm::Result result; result.status=status; result.error=ERROR_SHARING_VIOLATION;
                require(dvm::resultMessage(L"report (1).bin",result)==L"report (1).bin → 파일이 사용 중이라 두 파일을 보존했습니다. 파일을 닫은 뒤 최신본을 직접 확인해 주세요.","locked warning changed");
            }
        });
        run("unknown failure preserves original status without protection claim",[] {
            dvm::Result result; result.status=L"unexpected_fixture_error"; result.error=ERROR_GEN_FAILURE;
            require(dvm::resultMessage(L"report (1).bin",result)==L"report (1).bin → 파일을 보존했습니다. (unexpected_fixture_error)","unknown failure text changed");
        });
        run("cleanup warning retains preserved previous-file location",[] {
            dvm::Result result; result.ok=true; result.changed=true; result.status=L"cleanup_required"; result.error=ERROR_ACCESS_DENIED; result.oldPath=L"C:\\owned-fixture\\.dvm-previous.pending";
            require(dvm::resultMessage(L"report (1).bin",result)==L"report (1).bin → 최신 파일로 변경했습니다. 이전 파일은 지우지 못해 보존했습니다. 위치: "+result.oldPath,"cleanup warning/location changed");
        });
        run("metadata warning stays unchanged",[] {
            dvm::Result result; result.ok=true; result.changed=true; result.status=L"metadata_warning"; result.error=ERROR_ACCESS_DENIED;
            require(dvm::resultMessage(L"report (1).bin",result)==L"report (1).bin → 최신 파일로 변경했습니다. 파일 시간을 설정하지 못했습니다. 탐색기에서 시간을 확인해 주세요.","metadata warning changed");
        });
        run("rollback failure retains status and full recovery location",[] {
            dvm::Result result; result.changed=true; result.status=L"rollback_failed"; result.error=ERROR_ACCESS_DENIED; result.rollbackError=ERROR_ACCESS_DENIED;
            result.oldPath=L"C:\\owned-fixture\\_history\\"+std::wstring(220,L'b')+L"_20240927_004237.bin";
            const auto text=dvm::resultMessage(L"report (1).bin",result);
            includes(text,L"rollback_failed","rollback status missing"); includes(text,result.oldPath,"full recovery location missing");
            require(text.find(L"읽기 전용")==std::wstring::npos,"rollback error claimed readonly");
        });
        run("successful rollback retains status without misplaced recovery warning",[] {
            dvm::Result result; result.status=L"rename_failed_rolled_back"; result.error=ERROR_ACCESS_DENIED; result.oldPath=L"C:\\owned-fixture\\report.bin";
            require(dvm::resultMessage(L"report (1).bin",result)==L"report (1).bin → 파일을 보존했습니다. (rename_failed_rolled_back)","successful rollback warning changed");
        });
        size_t failed=0; for (const auto& test:tests) if (!test.passed) ++failed;
        std::ofstream report(output/L"guidance-results.json",std::ios::binary);
        report<<"{\"passed\":"<<(tests.size()-failed)<<",\"failed\":"<<failed<<",\"tests\":[";
        for (size_t i=0;i<tests.size();++i) {
            if (i) report<<',';
            report<<"{\"name\":\""<<tests[i].name<<"\",\"status\":\""<<(tests[i].passed ? "PASS" : "FAIL")<<"\"}";
        }
        report<<"]}\n"; require(!!report,"test report write failed");
        std::cout<<(tests.size()-failed)<<" PASS / "<<failed<<" FAIL\n";
        return failed ? 1 : 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 2; }
}
