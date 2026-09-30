#pragma once
// Deliberately small, strict flat-object protocol parser. No recursive JSON,
// floating point, duplicate properties, silent coercions or non-UTF-8 input.
#include <windows.h>
#include <map>
#include <string>
#include <stdexcept>
#include <cstdint>

namespace dvm {
inline std::wstring wide(const std::string& s) {
    if (s.empty()) return {};
    const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), nullptr, 0);
    if (!n) throw std::runtime_error("invalid_utf8");
    std::wstring r(static_cast<size_t>(n), L'\0');
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), r.data(), n)) throw std::runtime_error("invalid_utf8");
    return r;
}
inline std::string utf8(const std::wstring& s) {
    if (s.empty()) return {};
    const int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
    if (!n) throw std::runtime_error("invalid_unicode");
    std::string r(static_cast<size_t>(n), '\0');
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), r.data(), n, nullptr, nullptr)) throw std::runtime_error("invalid_unicode");
    return r;
}
inline std::string quote(const std::wstring& s) {
    std::string r = "\"";
    const char* hex = "0123456789abcdef";
    for (const unsigned char c : utf8(s)) {
        if (c == '"' || c == '\\') { r += '\\'; r += static_cast<char>(c); }
        else if (c < 32) { r += "\\u00"; r += hex[c >> 4]; r += hex[c & 15]; }
        else r += static_cast<char>(c);
    }
    return r + "\"";
}
struct Value { bool number = false; uint64_t integer = 0; std::wstring text; };
class Json {
    const std::string& s; size_t p = 0;
    [[noreturn]] void fail() const { throw std::runtime_error("invalid_json"); }
    void ws() { while (p < s.size() && (s[p]==' ' || s[p]=='\r' || s[p]=='\n' || s[p]=='\t')) ++p; }
    bool take(char c) { ws(); if (p < s.size() && s[p] == c) { ++p; return true; } return false; }
    unsigned hex4() {
        unsigned v = 0;
        for (unsigned i=0;i<4;++i) {
            if (p == s.size()) fail(); const char c = s[p++];
            const int x = c >= '0' && c <= '9' ? c-'0' : c >= 'a' && c <= 'f' ? c-'a'+10 : c >= 'A' && c <= 'F' ? c-'A'+10 : -1;
            if (x < 0) fail(); v = v*16 + static_cast<unsigned>(x);
        }
        return v;
    }
    std::wstring str() {
        if (!take('"')) fail(); std::wstring out; std::string raw;
        auto flush = [&] { out += wide(raw); raw.clear(); };
        while (p < s.size()) {
            const unsigned char c = static_cast<unsigned char>(s[p++]);
            if (c == '"') { flush(); return out; }
            if (c < 32) fail();
            if (c != '\\') { raw += static_cast<char>(c); continue; }
            flush(); if (p == s.size()) fail();
            switch (s[p++]) {
                case '"': out += L'"'; break; case '\\': out += L'\\'; break; case '/': out += L'/'; break;
                case 'b': out += L'\b'; break; case 'f': out += L'\f'; break; case 'n': out += L'\n'; break;
                case 'r': out += L'\r'; break; case 't': out += L'\t'; break;
                case 'u': {
                    const unsigned u = hex4();
                    if (u >= 0xD800 && u <= 0xDBFF) {
                        if (p+2 > s.size() || s[p++]!='\\' || s[p++]!='u') fail();
                        const unsigned v=hex4(); if (v < 0xDC00 || v > 0xDFFF) fail();
                        out += static_cast<wchar_t>(u); out += static_cast<wchar_t>(v);
                    } else { if (u >= 0xDC00 && u <= 0xDFFF) fail(); out += static_cast<wchar_t>(u); }
                    break;
                }
                default: fail();
            }
        }
        fail();
    }
public:
    explicit Json(const std::string& input) : s(input) {}
    std::map<std::wstring,Value> parse() {
        std::map<std::wstring,Value> r;
        if (!take('{')) fail();
        if (!take('}')) {
            do {
                const auto key = str(); if (key.empty() || key.size()>32 || r.count(key) || !take(':')) fail();
                Value v; ws();
                if (p<s.size() && s[p]=='"') v.text = str();
                else {
                    v.number = true; const auto begin = p;
                    while (p<s.size() && s[p]>='0' && s[p]<='9') {
                        if (v.integer > (9007199254740991ULL-static_cast<unsigned>(s[p]-'0'))/10) fail();
                        v.integer = v.integer*10 + static_cast<unsigned>(s[p++]-'0');
                    }
                    if (begin==p || (p-begin>1 && s[begin]=='0')) fail();
                }
                r.emplace(key,std::move(v)); if (r.size()>10) fail();
            } while (take(','));
            if (!take('}')) fail();
        }
        ws(); if (p!=s.size()) fail(); return r;
    }
};
}
