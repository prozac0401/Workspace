#pragma once
// Pure, side-effect-free decisions shared by the COM adapter and native tests.
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace ImageCopySave::ShellPolicy
{
inline constexpr std::size_t MaximumPathCharacters = 32766;
inline constexpr std::size_t MaximumPathComponents = 256;
inline constexpr std::uint32_t DirectoryAttribute = 0x00000010;
inline constexpr std::uint32_t UnsupportedAttributes =
    0x00000040 | // FILE_ATTRIBUTE_DEVICE
    0x00000400 | // FILE_ATTRIBUTE_REPARSE_POINT
    0x00001000 | // FILE_ATTRIBUTE_OFFLINE
    0x00040000 | // FILE_ATTRIBUTE_RECALL_ON_OPEN
    0x00400000;  // FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS

struct ClipboardFormats
{
    bool png = false;
    bool dibV5 = false;
    bool dib = false;
    bool bitmap = false;
};

inline constexpr bool HasSupportedImage(const ClipboardFormats formats) noexcept
{
    // CF_HDROP, text, HTML, OLE-only and vector formats cannot enter this set.
    return formats.png || formats.dibV5 || formats.dib || formats.bitmap;
}

inline constexpr wchar_t LowerAscii(const wchar_t value) noexcept
{
    return value >= L'A' && value <= L'Z' ? value + (L'a' - L'A') : value;
}

inline bool EqualAsciiInsensitive(const std::wstring_view left,
                                  const std::wstring_view right) noexcept
{
    if (left.size() != right.size()) return false;
    for (std::size_t i = 0; i < left.size(); ++i)
        if (LowerAscii(left[i]) != LowerAscii(right[i])) return false;
    return true;
}

inline bool IsSupportedImageExtension(const std::wstring_view path) noexcept
{
    const auto dot = path.find_last_of(L'.');
    const auto separator = path.find_last_of(L"\\/");
    if (dot == std::wstring_view::npos ||
        (separator != std::wstring_view::npos && dot < separator)) return false;
    const auto extension = path.substr(dot);
    return EqualAsciiInsensitive(extension, L".png") ||
           EqualAsciiInsensitive(extension, L".jpg") ||
           EqualAsciiInsensitive(extension, L".jpeg") ||
           EqualAsciiInsensitive(extension, L".bmp");
}

inline bool IsReservedDeviceComponent(const std::wstring_view component) noexcept
{
    // Win32 reserves these names even before an extension, in any directory.
    // Also reject console aliases. Trim stem spaces to avoid DOS alias parsing.
    auto stem = component.substr(0, component.find(L'.'));
    while (!stem.empty() && stem.back() == L' ') stem.remove_suffix(1);
    if (EqualAsciiInsensitive(stem, L"CON") ||
        EqualAsciiInsensitive(stem, L"PRN") ||
        EqualAsciiInsensitive(stem, L"AUX") ||
        EqualAsciiInsensitive(stem, L"NUL") ||
        EqualAsciiInsensitive(stem, L"CONIN$") ||
        EqualAsciiInsensitive(stem, L"CONOUT$")) return true;
    if (stem.size() != 4 ||
        (!EqualAsciiInsensitive(stem.substr(0, 3), L"COM") &&
         !EqualAsciiInsensitive(stem.substr(0, 3), L"LPT"))) return false;
    const wchar_t suffix = stem[3];
    return (suffix >= L'1' && suffix <= L'9') ||
           suffix == L'\u00b9' || suffix == L'\u00b2' || suffix == L'\u00b3';
}

inline bool IsOrdinaryAbsolutePath(const std::wstring_view path) noexcept
{
    // Only an unambiguous drive-letter path. No UNC, device namespace, ADS,
    // drive-relative path, slash alias, dot segments or Win32 trimming aliases.
    if (path.size() < 3 || path.size() > MaximumPathCharacters ||
        LowerAscii(path[0]) < L'a' || LowerAscii(path[0]) > L'z' ||
        path[1] != L':' || path[2] != L'\\') return false;
    if (path.size() == 3) return true;
    std::size_t components = 0;
    for (std::size_t start = 3; start < path.size();)
    {
        if (++components > MaximumPathComponents) return false;
        const auto found = path.find(L'\\', start);
        const auto end = found == std::wstring_view::npos ? path.size() : found;
        if (start == end) return false;
        const auto component = path.substr(start, end - start);
        if (IsReservedDeviceComponent(component) ||
            component == L"." || component == L".." ||
            component.back() == L'.' || component.back() == L' ') return false;
        for (const wchar_t character : component)
            if (character < L' ' || character == L'/' || character == L':' ||
                character == L'<' || character == L'>' || character == L'"' ||
                character == L'|' || character == L'?' || character == L'*')
                return false;
        if (found == std::wstring_view::npos) return true;
        start = end + 1;
        if (start == path.size()) return false;
    }
    return false;
}

inline constexpr bool AreSupportedAttributes(const std::uint32_t attributes,
                                             const bool expectDirectory) noexcept
{
    return attributes != 0xFFFFFFFF &&
           (attributes & UnsupportedAttributes) == 0 &&
           ((attributes & DirectoryAttribute) != 0) == expectDirectory;
}

inline bool IsPhysicalVolumeDevice(const std::wstring_view target) noexcept
{
    // Reject SUBST (\??\...), mapped network and virtual-device aliases even
    // where GetDriveType alone reports DRIVE_FIXED.
    constexpr std::wstring_view prefix = L"\\Device\\HarddiskVolume";
    if (target.size() <= prefix.size() ||
        target.substr(0, prefix.size()) != prefix) return false;
    for (const wchar_t character : target.substr(prefix.size()))
        if (character < L'0' || character > L'9') return false;
    return true;
}

inline std::wstring QuoteWindowsArgument(const std::wstring_view value)
{
    // CommandLineToArgvW/CRT-compatible quoting, including empty arguments and
    // trailing backslashes. CreateProcessW also receives an explicit exe path.
    std::wstring quoted(1, L'"');
    std::size_t backslashes = 0;
    for (const wchar_t character : value)
    {
        if (character == L'\\') { ++backslashes; continue; }
        if (character == L'"')
        {
            quoted.append(backslashes * 2 + 1, L'\\');
            quoted.push_back(character);
        }
        else
        {
            quoted.append(backslashes, L'\\');
            quoted.push_back(character);
        }
        backslashes = 0;
    }
    quoted.append(backslashes * 2, L'\\');
    quoted.push_back(L'"');
    return quoted;
}

inline bool IsSavedImageInFolder(const std::wstring_view folder,
                                 const std::wstring_view result) noexcept
{
    if (!IsOrdinaryAbsolutePath(folder) || !IsOrdinaryAbsolutePath(result)) return false;
    const auto separator = result.find_last_of(L'\\');
    if (separator == std::wstring_view::npos) return false;
    const auto parent = result.substr(0, separator == 2 ? 3 : separator);
    const auto name = result.substr(separator + 1);
    return EqualAsciiInsensitive(parent, folder) && name.size() > 4 &&
           EqualAsciiInsensitive(name.substr(name.size() - 4), L".png");
}
}
