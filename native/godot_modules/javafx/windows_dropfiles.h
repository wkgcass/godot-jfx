#pragma once
#include <windows.h>
#include <shlobj.h>
#include <cstdint>
#include <cstring>
#include <climits>

namespace godot_javafx::windows_dropfiles {
// Parse bytes, not wchar_t pointers: pFiles and the source buffer may be
// unaligned. Each callback receives one bounded path without its terminator.
// Callers keep results local until the entire double-NUL list is accepted.
template <class Visitor>
bool visit(const uint8_t *bytes, size_t size, size_t max_paths, size_t max_chars, Visitor &&visitor) {
    if (!bytes || size < sizeof(DROPFILES)) return false;
    DROPFILES header{};
    memcpy(&header, bytes, sizeof(header));
    if (header.pFiles < sizeof(header) || header.pFiles > size) return false;
    const size_t unit = header.fWide ? 2 : 1;
    size_t offset = header.pFiles, count = 0;
    auto nonzero = [&](size_t at) {
        // The caller checks a complete code unit is present before every read.
        uint16_t value = 0;
        memcpy(&value, bytes + at, unit);
        return value != 0;
    };
    while (size - offset >= unit) {
        if (!nonzero(offset)) return count != 0;
        const size_t start = offset;
        while (size - offset >= unit && nonzero(offset)) offset += unit;
        if (size - offset < unit || count >= max_paths) return false;
        const size_t length = (offset - start) / unit;
        if (length > INT_MAX) return false;
        if (header.fWide && length > max_chars) return false;
        if (!visitor(bytes + start, length, header.fWide != FALSE)) return false;
        ++count;
        offset += unit;
    }
    return false; // A path terminator alone is not the list terminator.
}
}
