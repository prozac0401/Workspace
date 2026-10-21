#include "MsiGuard.cpp"
#include <iostream>
#include <fstream>

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) return 2;
    int passed = 0, failed = 0;
    auto check = [&](const char* name, bool expectedFailure, auto action) {
        bool refused = false;
        try { action(); } catch (const vcp::Failure&) { refused = true; }
        if (refused == expectedFailure) { ++passed; std::cout << "PASS " << name << "\n"; }
        else { ++failed; std::cout << "FAIL " << name << "\n"; }
    };
    std::wstring root = vcp::FullPath(argv[1]);
    if (!CreateDirectoryW(root.c_str(), nullptr)) return 3; // Only a fresh explicit test directory.
    std::wstring file = root+L"\\sample.txt";
    { std::ofstream stream(file, std::ios::binary); stream << "abc"; }
    const std::wstring abc = L"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    check("owned file passes exact hash",false,[&]{vcp::CheckFile(file,abc,true);});
    check("first install refuses existing filename",true,[&]{vcp::CheckFile(file,abc,false);});
    check("tampered owned file refused",true,[&]{vcp::CheckFile(file,L"bad",true);});
    check("missing owned file repair allowed",false,[&]{vcp::CheckFile(root+L"\\missing",abc,true);});
    check("unknown file outside inventory untouched",false,[&]{vcp::CheckFile(root+L"\\different",abc,true);});
    check("drive root refused",true,[&]{vcp::FullPath(L"C:\\");});
    check("relative path refused",true,[&]{vcp::FullPath(L"..\\unsafe");});
    check("alternate stream path refused",true,[&]{vcp::FullPath(root+L":stream");});
    check("delimiter path refused",true,[&]{vcp::FullPath(root+L"|bad");});
    check("trailing dot path refused",true,[&]{vcp::FullPath(root+L"\\bad.");});
    check("trailing space path refused",true,[&]{vcp::FullPath(root+L"\\bad ");});
    std::wstring link = root+L"\\link.txt";
    if (!CreateHardLinkW(link.c_str(),file.c_str(),nullptr)) return 4;
    check("hardlink owned file refused",true,[&]{vcp::CheckFile(file,abc,true);});
    if (!DeleteFileW(link.c_str())) return 5;
    { std::ofstream stream(file+L":external", std::ios::binary); stream << "keep"; }
    check("external alternate stream refused",true,[&]{vcp::CheckFile(file,abc,true);});
    check("codebase retains Korean spaces and apostrophe",false,[&]{ if (vcp::CodeBase(L"C:\\한글 space's") != L"file:///C:/한글 space's/VisibleCellsPaste.AddIn.dll") vcp::Fail(L"wrong codebase"); });
    // Synthetic fixtures are retained as verification evidence; no recursive cleanup.
    std::cout << "{\"passed\":" << passed << ",\"failed\":" << failed << "}\n";
    return failed ? 1 : 0;
}
