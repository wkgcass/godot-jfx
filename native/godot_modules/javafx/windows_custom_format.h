#pragma once

#include <windows.h>
#include <string>

// One convention shared by the system clipboard adapter and the OLE drag
// endpoints: a Java MIME "application/x-godot-custom-<suffix>" maps to the
// Windows registered clipboard format of the same name and carries a single
// NUL-terminated byte payload, so external processes can exchange it without
// any OLE-private structure. The suffix stays lowercase [a-z0-9._-] so the
// MIME<->format mapping is unambiguous (format names are case-insensitive).
namespace godot_javafx::custom_format {
constexpr char PREFIX[] = "application/x-godot-custom-";
constexpr size_t PREFIX_LENGTH = sizeof(PREFIX) - 1;
constexpr size_t MAX_NAME_CHARS = 128;
constexpr size_t MAX_FORMATS = 32;
constexpr size_t MAX_DATA_BYTES = 16 * 1024 * 1024;

inline bool valid_name(const std::wstring &name) {
    if (name.size() <= PREFIX_LENGTH || name.size() > MAX_NAME_CHARS) return false;
    for (size_t i = 0; i < PREFIX_LENGTH; ++i)
        if (name[i] != static_cast<wchar_t>(PREFIX[i])) return false;
    for (size_t i = PREFIX_LENGTH; i < name.size(); ++i) {
        const wchar_t c = name[i];
        const bool ok = (c >= L'a' && c <= L'z') || (c >= L'0' && c <= L'9') || c == L'-' || c == L'.' || c == L'_';
        if (!ok) return false;
    }
    return true;
}

// Registered id for a validated name; 0 when the name is out of convention or
// registration failed (callers report once, no silent drop).
inline UINT format_for(const std::wstring &name) {
    if (!valid_name(name)) return 0;
    return RegisterClipboardFormatW(name.c_str());
}
}
