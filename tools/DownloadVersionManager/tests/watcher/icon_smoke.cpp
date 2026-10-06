// Resource and native presentation checks. The synthetic app window never starts
// a watcher or loads/saves DVM settings; Shell registration is intercepted.
#define wWinMain DvmUnusedWinMain
#include "../../source/app.cpp"
#undef wWinMain
#include <array>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>

namespace {
namespace fs = std::filesystem;
constexpr std::array<int, 7> IconSizes{16, 24, 32, 48, 64, 128, 256};
NOTIFYICONDATAW registeredIcon{};
BOOL WINAPI mockNotify(DWORD action, PNOTIFYICONDATAW icon) {
    if (action == NIM_ADD || action == NIM_MODIFY) registeredIcon = *icon;
    return TRUE;
}
#pragma pack(push, 2)
struct IconGroupHeader { WORD reserved, type, count; };
struct IconGroupEntry {
    BYTE width, height, colors, reserved;
    WORD planes, bits;
    DWORD bytes;
    WORD id;
};
#pragma pack(pop)
static_assert(sizeof(IconGroupHeader) == 6 && sizeof(IconGroupEntry) == 14);

bool resourceCoverage() {
    const HMODULE module = GetModuleHandleW(nullptr);
    HRSRC resource = FindResourceW(module, MAKEINTRESOURCEW(ApplicationIconId), RT_GROUP_ICON);
    if (!resource) return false;
    const DWORD length = SizeofResource(module, resource);
    const auto bytes = static_cast<const BYTE*>(LockResource(LoadResource(module, resource)));
    if (!bytes || length < sizeof(IconGroupHeader)) return false;
    IconGroupHeader header{}; std::memcpy(&header, bytes, sizeof(header));
    if (header.reserved || header.type != 1 || header.count != IconSizes.size() ||
        length < sizeof(header) + header.count * sizeof(IconGroupEntry)) return false;
    std::array<unsigned, IconSizes.size()> found{};
    for (unsigned index = 0; index < header.count; ++index) {
        IconGroupEntry entry{};
        std::memcpy(&entry, bytes + sizeof(header) + index * sizeof(entry), sizeof(entry));
        const int width = entry.width ? entry.width : 256;
        const int height = entry.height ? entry.height : 256;
        bool expected = false;
        for (size_t candidate = 0; candidate < IconSizes.size(); ++candidate) {
            if (width == IconSizes[candidate] && height == width) { ++found[candidate]; expected = true; }
        }
        HRSRC image = FindResourceW(module, MAKEINTRESOURCEW(entry.id), RT_ICON);
        if (!expected || entry.bits != 32 || !image || !entry.bytes ||
            SizeofResource(module, image) != entry.bytes) return false;
    }
    for (unsigned count : found) if (count != 1) return false;
    return true;
}
bool dimensions(HICON icon, int size) {
    ICONINFO info{}; if (!icon || !GetIconInfo(icon, &info)) return false;
    BITMAP bitmap{};
    const bool okay = info.hbmColor && GetObjectW(info.hbmColor, sizeof(bitmap), &bitmap) &&
        bitmap.bmWidth == size && bitmap.bmHeight == size;
    if (info.hbmColor) DeleteObject(info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
    return okay;
}
struct Canvas {
    HDC dc = nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ previous = nullptr;
    BYTE* pixels = nullptr;
    BITMAPINFO info{};
    Canvas(int width, int height) {
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
        info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = BI_RGB;
        dc = CreateCompatibleDC(nullptr);
        if (dc) bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, reinterpret_cast<void**>(&pixels), nullptr, 0);
        if (bitmap) previous = SelectObject(dc, bitmap);
    }
    ~Canvas() {
        if (previous) SelectObject(dc, previous);
        if (bitmap) DeleteObject(bitmap);
        if (dc) DeleteDC(dc);
    }
    bool ready() const { return dc && bitmap && pixels; }
    void fill(RECT area, COLORREF color) {
        HBRUSH brush = CreateSolidBrush(color); FillRect(dc, &area, brush); DeleteObject(brush);
    }
};
std::vector<BYTE> rendered(HICON icon, int size) {
    Canvas canvas(size, size); if (!canvas.ready()) return {};
    canvas.fill({0, 0, size, size}, RGB(255, 255, 255));
    if (!DrawIconEx(canvas.dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL)) return {};
    GdiFlush();
    return std::vector<BYTE>(canvas.pixels, canvas.pixels + static_cast<size_t>(size) * size * 4);
}
bool customImages() {
    for (int size : IconSizes) {
        HICON icon = applicationIcon(size);
        HICON stock = static_cast<HICON>(LoadImageW(nullptr, IDI_APPLICATION, IMAGE_ICON, size, size, LR_SHARED));
        const auto actual = rendered(icon, size), fallback = rendered(stock, size);
        if (!dimensions(icon, size) || icon == stock || actual.empty() || fallback.empty() || actual == fallback) return false;
        for (unsigned repeat = 0; repeat < 100; ++repeat) if (applicationIcon(size) != icon) return false;
    }
    return true;
}
bool windowAndTrayIcons(HWND window, UINT dpi, bool registration) {
    const int trayIconPixels = GetSystemMetricsForDpi(SM_CXSMICON, dpi), mainIconPixels = GetSystemMetricsForDpi(SM_CXICON, dpi);
    const auto smallIcon = reinterpret_cast<HICON>(SendMessageW(window, WM_GETICON, ICON_SMALL, 0));
    const auto bigIcon = reinterpret_cast<HICON>(SendMessageW(window, WM_GETICON, ICON_BIG, 0));
    const auto tray = trayIcon(window);
    return smallIcon && bigIcon && smallIcon == applicationIcon(trayIconPixels) && bigIcon == applicationIcon(mainIconPixels) &&
        dimensions(smallIcon, trayIconPixels) && dimensions(bigIcon, mainIconPixels) && tray.hIcon == smallIcon &&
        (!registration || (trayAvailable && registeredIcon.hWnd == window && registeredIcon.hIcon == smallIcon));
}
bool renderSheet(const fs::path& path) {
    constexpr int gap = 16, rowHeight = 296, width = 696, height = rowHeight * 2;
    Canvas canvas(width, height); if (!canvas.ready()) return false;
    SetBkMode(canvas.dc, TRANSPARENT);
    bool okay = true;
    for (int row = 0; row < 2; ++row) {
        canvas.fill({0, row * rowHeight, width, (row + 1) * rowHeight}, row ? RGB(20, 31, 51) : RGB(248, 250, 253));
        SetTextColor(canvas.dc, row ? RGB(245, 248, 255) : RGB(32, 44, 64));
        int x = gap;
        for (int size : IconSizes) {
            okay = DrawIconEx(canvas.dc, x, row * rowHeight + gap, applicationIcon(size), size, size, 0, nullptr, DI_NORMAL) && okay;
            const auto label = std::to_wstring(size);
            TextOutW(canvas.dc, x, row * rowHeight + gap + 260, label.c_str(), static_cast<int>(label.size()));
            x += size + gap;
        }
    }
    GdiFlush();
    BITMAPFILEHEADER header{}; header.bfType = 0x4D42;
    header.bfOffBits = sizeof(header) + sizeof(BITMAPINFOHEADER);
    const DWORD pixelBytes = static_cast<DWORD>(width * height * 4);
    header.bfSize = header.bfOffBits + pixelBytes;
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(&header), sizeof(header));
    output.write(reinterpret_cast<const char*>(&canvas.info.bmiHeader), sizeof(BITMAPINFOHEADER));
    output.write(reinterpret_cast<const char*>(canvas.pixels), pixelBytes);
    return okay && output.good();
}
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) { std::cerr << "Usage: icon-smoke.exe <fresh-fixture-directory>\n"; return 2; }
    const auto fixture = fs::absolute(argv[1]);
    if (fs::exists(fixture)) { std::cerr << "Use a fresh fixture directory.\n"; return 2; }
    fs::create_directories(fixture);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    INITCOMMONCONTROLSEX common{sizeof(common), ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES}; InitCommonControlsEx(&common);
    trayNotify = mockNotify; followDownloads = false; selectedFolder = L"Synthetic icon presentation";
    WNDCLASSW kind{}; kind.lpfnWndProc = windowProc; kind.hInstance = GetModuleHandleW(nullptr); kind.lpszClassName = L"DvmIconSmoke";
    if (!RegisterClassW(&kind)) return 2;
    HWND window = CreateWindowExW(0, kind.lpszClassName, L"DVM isolated icon presentation", WS_OVERLAPPEDWINDOW,
        0, 0, 940, 840, nullptr, nullptr, kind.hInstance, nullptr);
    if (!window) return 2;
    unsigned passed = 0, failed = 0;
    const auto check = [&](const char* name, bool okay) {
        std::cout << (okay ? "PASS " : "FAIL ") << name << '\n'; okay ? ++passed : ++failed;
    };
    check("embedded 32-bit icon resource includes all seven native sizes", resourceCoverage());
    check("all native icon sizes retain cached handles and custom pixels distinct from stock", customImages());
    check("real window big-small icons and initial Shell descriptor use embedded custom resource", windowAndTrayIcons(window, windowDpi, true));
    RECT scaled{0, 0, 1400, 1260};
    SendMessageW(window, WM_DPICHANGED, MAKEWPARAM(144, 144), reinterpret_cast<LPARAM>(&scaled));
    check("DPI change updates native window and registered tray icon sizes", windowDpi == 144 && windowAndTrayIcons(window, 144, true));
    check("native DrawIconEx light-dark preview written without starting watcher", !watcher.running() && renderSheet(fixture / L"icons-native-light-dark.bmp"));
    DestroyWindow(window); UnregisterClassW(kind.lpszClassName, kind.hInstance);
    std::ofstream summary(fixture / L"results.json");
    summary << "{\"passed\":" << passed << ",\"failed\":" << failed << ",\"scope\":\"embedded test resource and synthetic native window; no installed app or real tray interaction\"}\n";
    return failed ? 1 : 0;
}
