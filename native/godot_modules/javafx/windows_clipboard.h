#pragma once

#include <windows.h>
#include <shlobj.h>
#include <jni.h>
#include <cstring>
#include <array>
#include <string>
#include <utility>
#include <vector>
#include "windows_custom_format.h"
#include "windows_dropfiles.h"

// These Win32 calls run on the calling Java thread. They do not touch Godot
// Nodes or RenderingServer and never create a second native window.
namespace godot_javafx::windows_clipboard {
constexpr size_t MAX_TEXT_BYTES = 16 * 1024 * 1024;

inline void fail(JNIEnv *env, const char *type, const char *message) {
    jclass cls = env->FindClass(type);
    if (cls) { env->ThrowNew(cls, message); env->DeleteLocalRef(cls); }
}

class Opened {
    bool opened = false;
public:
    Opened(JNIEnv *env, HWND owner) {
        // Another application can briefly hold the global clipboard lock.
        for (int i = 0; i < 25 && !opened; ++i) {
            opened = OpenClipboard(owner) != FALSE;
            if (!opened) Sleep(10);
        }
        if (!opened) fail(env, "java/lang/IllegalStateException", "Windows clipboard is busy");
    }
    ~Opened() { if (opened) CloseClipboard(); }
    explicit operator bool() const { return opened; }
};

inline UINT rich_format(int kind) {
    return RegisterClipboardFormatW(kind == 0 ? L"HTML Format" : L"Rich Text Format");
}

struct Prepared {
    std::array<HGLOBAL, 4> blocks{};
    ~Prepared() { for (HGLOBAL block : blocks) if (block) GlobalFree(block); }
};

// Own unpublished formats across allocation failures; successful publication
// nulls each transferred handle. Reserve before acquiring any HGLOBAL.
struct PreparedExtras {
    std::vector<std::pair<UINT, HGLOBAL>> blocks;
    PreparedExtras() { blocks.reserve(custom_format::MAX_FORMATS + 2); }
    PreparedExtras(const PreparedExtras &) = delete;
    PreparedExtras &operator=(const PreparedExtras &) = delete;
    ~PreparedExtras() { for (auto &entry : blocks) if (entry.second) GlobalFree(entry.second); }
};

class LockedGlobal {
    HGLOBAL memory;
    void *data;
public:
    explicit LockedGlobal(HGLOBAL value) : memory(value), data(GlobalLock(value)) {}
    LockedGlobal(const LockedGlobal &) = delete;
    LockedGlobal &operator=(const LockedGlobal &) = delete;
    ~LockedGlobal() { if (data) GlobalUnlock(memory); }
    void *get() const { return data; }
};

// Extra HGLOBAL payloads (CF_HDROP/CF_DIB/custom) publish inside the same
// clipboard-open interval; each successful SetClipboardData nulls its entry,
// so the caller only frees what was not transferred.
inline void write(JNIEnv *env, HWND owner, jstring text, jbyteArray html = nullptr, jbyteArray rtf = nullptr, jstring url = nullptr,
        std::vector<std::pair<UINT, HGLOBAL>> *extras = nullptr) {
    Prepared prepared;
    const std::array<jstring,2> strings = {text,url};
    for (size_t index=0; index<strings.size(); ++index) {
        jstring value = strings[index];
        if (!value) continue;
        HGLOBAL memory = nullptr;
        const jsize length = env->GetStringLength(value);
        if (size_t(length) >= MAX_TEXT_BYTES / sizeof(jchar)) {
            fail(env, "java/lang/IllegalArgumentException", "Clipboard text exceeds 16 MiB");
            return;
        }
        memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, (size_t(length) + 1) * sizeof(jchar));
        if (!memory) { fail(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return; }
        auto *bytes = static_cast<jchar *>(GlobalLock(memory));
        if (!bytes) { GlobalFree(memory); fail(env, "java/lang/IllegalStateException", "Clipboard memory lock failed"); return; }
        env->GetStringRegion(value, 0, length, bytes);
        bool embedded_nul = false;
        for (jsize i = 0; i < length; ++i) embedded_nul |= bytes[i] == 0;
        GlobalUnlock(memory);
        if (env->ExceptionCheck() || embedded_nul) {
            GlobalFree(memory);
            if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalArgumentException", "Clipboard text contains NUL");
            return;
        }
        prepared.blocks[index == 0 ? 0 : 3] = memory;
    }
    const std::array<jbyteArray,2> rich = {html,rtf};
    std::array<UINT,4> formats = {CF_UNICODETEXT,0,0,0};
    if (url) {
        formats[3] = RegisterClipboardFormatW(L"UniformResourceLocatorW");
        if (!formats[3]) { fail(env,"java/lang/IllegalStateException","Cannot register URL clipboard format"); return; }
    }
    for (size_t i=0;i<rich.size();++i) {
        if (!rich[i]) continue;
        const jsize length = env->GetArrayLength(rich[i]);
        if (length < 1 || size_t(length) > MAX_TEXT_BYTES) {
            fail(env,"java/lang/IllegalArgumentException","Rich clipboard data must be NUL-terminated and at most 16 MiB"); return;
        }
        formats[i+1] = rich_format(int(i));
        if (!formats[i+1]) { fail(env,"java/lang/IllegalStateException","Cannot register Windows clipboard format"); return; }
        HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, length);
        if (!block) { fail(env,"java/lang/OutOfMemoryError","Clipboard allocation failed"); return; }
        prepared.blocks[i+1] = block;
        auto *bytes = static_cast<jbyte *>(GlobalLock(block));
        if (!bytes) { fail(env,"java/lang/IllegalStateException","Clipboard memory lock failed"); return; }
        env->GetByteArrayRegion(rich[i],0,length,bytes);
        bool valid = bytes[length-1] == 0;
        for (jsize p=0;p<length-1;++p) valid &= bytes[p] != 0;
        GlobalUnlock(block);
        if (env->ExceptionCheck()) return;
        if (!valid) { fail(env,"java/lang/IllegalArgumentException","Invalid NUL in rich clipboard data"); return; }
    }
    Opened clipboard(env, owner);
    if (!clipboard) return;
    if (!EmptyClipboard()) {
        fail(env, "java/lang/IllegalStateException", "Cannot clear Windows clipboard");
        return;
    }
    for (size_t i=0;i<prepared.blocks.size();++i) {
        if (!prepared.blocks[i]) continue;
        if (!SetClipboardData(formats[i],prepared.blocks[i])) {
            fail(env,"java/lang/IllegalStateException","Cannot publish Windows clipboard format"); return;
        }
        prepared.blocks[i] = nullptr; // Ownership transferred to Windows.
    }
    if (extras) {
        for (auto &extra : *extras) {
            if (!extra.second) continue;
            if (!SetClipboardData(extra.first, extra.second)) {
                fail(env,"java/lang/IllegalStateException","Cannot publish Windows clipboard format"); return;
            }
            extra.second = nullptr; // Ownership transferred to Windows.
        }
    }
}

inline jbyteArray read_rich(JNIEnv *env, HWND owner, int kind) {
    if (kind < 0 || kind > 1) { fail(env,"java/lang/IllegalArgumentException","Unknown rich clipboard format"); return nullptr; }
    const UINT format = rich_format(kind);
    if (!format) { fail(env,"java/lang/IllegalStateException","Cannot register Windows clipboard format"); return nullptr; }
    Opened clipboard(env,owner);
    if (!clipboard || !IsClipboardFormatAvailable(format)) return nullptr;
    HANDLE memory = GetClipboardData(format);
    SIZE_T size = memory ? GlobalSize(memory) : 0;
    if (!memory || size < 1 || size > MAX_TEXT_BYTES) { fail(env,"java/lang/IllegalStateException","Invalid rich clipboard size"); return nullptr; }
    const auto *bytes = static_cast<const jbyte *>(GlobalLock(memory));
    if (!bytes) { fail(env,"java/lang/IllegalStateException","Cannot lock rich clipboard data"); return nullptr; }
    size_t length=0; while (length<size && bytes[length]) ++length;
    jbyteArray result=nullptr;
    if (length==size) fail(env,"java/lang/IllegalStateException","Unterminated rich clipboard data");
    else {
        result=env->NewByteArray(jsize(length+1));
        if (result) env->SetByteArrayRegion(result,0,jsize(length+1),bytes);
    }
    GlobalUnlock(memory);
    return result;
}

inline jstring read(JNIEnv *env, HWND owner, UINT format = CF_UNICODETEXT) {
    if (!format) { fail(env,"java/lang/IllegalStateException","Invalid clipboard format"); return nullptr; }
    Opened clipboard(env, owner);
    if (!clipboard || !IsClipboardFormatAvailable(format)) return nullptr;
    HANDLE memory = GetClipboardData(format);
    SIZE_T bytes = memory ? GlobalSize(memory) : 0;
    if (!memory || bytes < sizeof(jchar) || bytes > MAX_TEXT_BYTES || bytes % sizeof(jchar)) {
        fail(env, "java/lang/IllegalStateException", "Invalid or oversized Windows clipboard text");
        return nullptr;
    }
    auto *data = static_cast<const jchar *>(GlobalLock(memory));
    if (!data) { fail(env, "java/lang/IllegalStateException", "Cannot lock Windows clipboard text"); return nullptr; }
    size_t length = 0;
    while (length < bytes / sizeof(jchar) && data[length]) ++length;
    jstring result = nullptr;
    if (length == bytes / sizeof(jchar)) fail(env, "java/lang/IllegalStateException", "Unterminated Windows clipboard text");
    else result = env->NewString(data, jsize(length));
    GlobalUnlock(memory);
    return result;
}

constexpr size_t MAX_PATHS = 4096;
constexpr size_t MAX_PATH_CHARS = 32768;
constexpr size_t MAX_DIB_BYTES = 64 * 1024 * 1024;
constexpr int MAX_IMAGE_DIM = 16384;

// UTF-16 DROPFILES without a document header; fWide set, double NUL terminated.
inline HGLOBAL encode_hdrop(JNIEnv *env, jobjectArray paths) {
    const jsize count = env->GetArrayLength(paths);
    if (count < 1 || size_t(count) > MAX_PATHS) {
        fail(env, "java/lang/IllegalArgumentException", "Clipboard file list must hold 1..4096 paths");
        return nullptr;
    }
    // Java array elements can be replaced by another thread. Size and encode
    // the same owned strings instead of fetching each element a second time.
    std::vector<std::u16string> snapshot;
    snapshot.reserve(size_t(count));
    size_t chars = 1; // Final list terminator, in addition to each path's NUL.
    for (jsize i = 0; i < count; ++i) {
        auto path = reinterpret_cast<jstring>(env->GetObjectArrayElement(paths, i));
        if (!path) {
            if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalArgumentException", "Clipboard file list contains null");
            return nullptr;
        }
        const jsize length = env->GetStringLength(path);
        if (length < 1 || size_t(length) > MAX_PATH_CHARS || size_t(length) + 1 > MAX_TEXT_BYTES / sizeof(jchar) - chars) {
            env->DeleteLocalRef(path);
            fail(env, "java/lang/IllegalArgumentException", "Clipboard file path exceeds its limit");
            return nullptr;
        }
        try { snapshot.emplace_back(size_t(length), char16_t(0)); }
        catch (...) { env->DeleteLocalRef(path); throw; }
        auto &copy = snapshot.back();
        env->GetStringRegion(path, 0, length, reinterpret_cast<jchar *>(copy.data()));
        env->DeleteLocalRef(path);
        if (env->ExceptionCheck()) return nullptr;
        if (copy.find(u'\0') != std::u16string::npos || copy.find(u'\n') != std::u16string::npos) {
            fail(env, "java/lang/IllegalArgumentException", "Invalid character in clipboard file path");
            return nullptr;
        }
        chars += size_t(length) + 1;
    }
    HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(DROPFILES) + chars * sizeof(wchar_t));
    if (!block) { fail(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return nullptr; }
    auto *bytes = static_cast<uint8_t *>(GlobalLock(block));
    if (!bytes) { GlobalFree(block); fail(env, "java/lang/IllegalStateException", "Clipboard memory lock failed"); return nullptr; }
    DROPFILES header{};
    header.pFiles = sizeof(DROPFILES);
    header.fWide = TRUE;
    memcpy(bytes, &header, sizeof(header));
    auto *cursor = reinterpret_cast<jchar *>(bytes + sizeof(DROPFILES));
    for (const auto &path : snapshot) {
        memcpy(cursor, path.data(), path.size() * sizeof(jchar));
        cursor += path.size() + 1;
    }
    GlobalUnlock(block);
    return block;
}

// 32bpp BI_RGB bottom-up DIB from ARGB integers (Glass INT_ARGB_PRE pixels).
inline HGLOBAL encode_dib(JNIEnv *env, jintArray pixels, jint width, jint height) {
    if (width < 1 || height < 1 || width > MAX_IMAGE_DIM || height > MAX_IMAGE_DIM
            || uint64_t(width) * uint64_t(height) * 4 + sizeof(BITMAPINFOHEADER) > MAX_DIB_BYTES) {
        fail(env, "java/lang/IllegalArgumentException", "Clipboard image dimensions exceed their limit");
        return nullptr;
    }
    if (!pixels || env->GetArrayLength(pixels) != width * height) {
        fail(env, "java/lang/IllegalArgumentException", "Clipboard image pixel count differs from its dimensions");
        return nullptr;
    }
    const SIZE_T total = sizeof(BITMAPINFOHEADER) + SIZE_T(width) * SIZE_T(height) * 4;
    HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, total);
    if (!block) { fail(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return nullptr; }
    auto *bytes = static_cast<uint8_t *>(GlobalLock(block));
    if (!bytes) { GlobalFree(block); fail(env, "java/lang/IllegalStateException", "Clipboard memory lock failed"); return nullptr; }
    BITMAPINFOHEADER header{};
    header.biSize = sizeof(header);
    header.biWidth = width;
    header.biHeight = height; // Bottom-up.
    header.biPlanes = 1;
    header.biBitCount = 32;
    header.biCompression = BI_RGB;
    header.biSizeImage = DWORD(width) * DWORD(height) * 4;
    memcpy(bytes, &header, sizeof(header));
    jint *rows = env->GetIntArrayElements(pixels, nullptr);
    if (!rows) { GlobalUnlock(block); GlobalFree(block); return nullptr; }
    for (jint y = 0; y < height; ++y) {
        uint8_t *target = bytes + sizeof(BITMAPINFOHEADER) + SIZE_T(height - 1 - y) * SIZE_T(width) * 4;
        const jint *source = rows + SIZE_T(y) * SIZE_T(width);
        for (jint x = 0; x < width; ++x) {
            const uint32_t argb = uint32_t(source[x]);
            target[x * 4 + 0] = uint8_t(argb & 0xFF);
            target[x * 4 + 1] = uint8_t((argb >> 8) & 0xFF);
            target[x * 4 + 2] = uint8_t((argb >> 16) & 0xFF);
            target[x * 4 + 3] = uint8_t((argb >> 24) & 0xFF);
        }
    }
    env->ReleaseIntArrayElements(pixels, rows, JNI_ABORT);
    GlobalUnlock(block);
    return block;
}

// Converts and validates one custom format name; empty on failure (a Java
// exception is already pending then).
inline std::wstring custom_name(JNIEnv *env, jstring name) {
    const jsize length = env->GetStringLength(name);
    if (size_t(length) > custom_format::MAX_NAME_CHARS) {
        fail(env, "java/lang/IllegalArgumentException", "Custom clipboard format name exceeds its limit");
        return {};
    }
    std::wstring wide(size_t(length), 0);
    if (length) env->GetStringRegion(name, 0, length, reinterpret_cast<jchar *>(wide.data()));
    if (env->ExceptionCheck()) return {};
    if (!custom_format::valid_name(wide)) {
        fail(env, "java/lang/IllegalArgumentException", "Custom clipboard format name outside the application/x-godot-custom- convention");
        return {};
    }
    return wide;
}

// NUL-terminated byte block for one custom format payload.
inline HGLOBAL encode_custom(JNIEnv *env, jbyteArray data) {
    const jsize length = env->GetArrayLength(data);
    if (length < 1 || size_t(length) > custom_format::MAX_DATA_BYTES) {
        fail(env, "java/lang/IllegalArgumentException", "Custom clipboard data must be NUL-terminated and at most 16 MiB");
        return nullptr;
    }
    HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, length);
    if (!block) { fail(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return nullptr; }
    auto *bytes = static_cast<jbyte *>(GlobalLock(block));
    if (!bytes) { GlobalFree(block); fail(env, "java/lang/IllegalStateException", "Clipboard memory lock failed"); return nullptr; }
    env->GetByteArrayRegion(data, 0, length, bytes);
    bool valid = bytes[length - 1] == 0;
    for (jsize p = 0; p < length - 1; ++p) valid &= bytes[p] != 0;
    GlobalUnlock(block);
    if (env->ExceptionCheck()) { GlobalFree(block); return nullptr; }
    if (!valid) { GlobalFree(block); fail(env, "java/lang/IllegalArgumentException", "Invalid NUL in custom clipboard data"); return nullptr; }
    return block;
}

// Full-system publication: every advertised format is prepared before the
// clipboard is emptied, so a validation failure keeps the previous content.
inline void write_full(JNIEnv *env, HWND owner, jstring text, jbyteArray html, jbyteArray rtf, jstring url,
        jobjectArray files, jintArray image, jint image_w, jint image_h, jobjectArray custom_names, jobjectArray custom_data) {
    PreparedExtras prepared;
    auto &extras = prepared.blocks;
    if (files) {
        HGLOBAL block = encode_hdrop(env, files);
        if (!block) return;
        extras.emplace_back(CF_HDROP, block);
    }
    if (image) {
        HGLOBAL block = encode_dib(env, image, image_w, image_h);
        if (!block) return;
        extras.emplace_back(CF_DIB, block);
    }
    if (custom_names || custom_data) {
        const jsize count = custom_names ? env->GetArrayLength(custom_names) : 0;
        if (!custom_names || !custom_data || count != env->GetArrayLength(custom_data)
                || size_t(count) > custom_format::MAX_FORMATS) {
            fail(env, "java/lang/IllegalArgumentException", "Custom clipboard formats require matching name/data arrays (at most 32)");
            return;
        }
        for (jsize i = 0; i < count; ++i) {
            auto name = reinterpret_cast<jstring>(env->GetObjectArrayElement(custom_names, i));
            auto payload = reinterpret_cast<jbyteArray>(env->GetObjectArrayElement(custom_data, i));
            if (!name || !payload) {
                if (name) env->DeleteLocalRef(name);
                if (payload) env->DeleteLocalRef(payload);
                if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalArgumentException", "Custom clipboard formats contain null");
                return;
            }
            std::wstring wide = custom_name(env, name);
            env->DeleteLocalRef(name);
            UINT format = wide.empty() ? 0 : custom_format::format_for(wide);
            if (!format) {
                env->DeleteLocalRef(payload);
                if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalStateException", "Cannot register custom clipboard format");
                return;
            }
            for (const auto &extra : extras) {
                if (extra.first == format) {
                    env->DeleteLocalRef(payload);
                    fail(env, "java/lang/IllegalArgumentException", "Duplicate custom clipboard format");
                    return;
                }
            }
            HGLOBAL block = encode_custom(env, payload);
            env->DeleteLocalRef(payload);
            if (!block) return;
            extras.emplace_back(format, block);
        }
    }
    write(env, owner, text, html, rtf, url, &extras);
}

// One custom format payload, terminator included (same shape as read_rich).
inline jbyteArray read_custom(JNIEnv *env, HWND owner, jstring name) {
    std::wstring wide = custom_name(env, name);
    if (wide.empty()) return nullptr;
    UINT format = custom_format::format_for(wide);
    if (!format) { fail(env, "java/lang/IllegalStateException", "Cannot register custom clipboard format"); return nullptr; }
    Opened clipboard(env, owner);
    if (!clipboard || !IsClipboardFormatAvailable(format)) return nullptr;
    HANDLE memory = GetClipboardData(format);
    const SIZE_T size = memory ? GlobalSize(memory) : 0;
    if (!memory || size < 1 || size > custom_format::MAX_DATA_BYTES) {
        fail(env, "java/lang/IllegalStateException", "Invalid custom clipboard size");
        return nullptr;
    }
    const auto *bytes = static_cast<const jbyte *>(GlobalLock(memory));
    if (!bytes) { fail(env, "java/lang/IllegalStateException", "Cannot lock custom clipboard data"); return nullptr; }
    size_t length = 0;
    while (length < size && bytes[length]) ++length;
    jbyteArray result = nullptr;
    if (length == size || length == 0) fail(env, "java/lang/IllegalStateException", "Unterminated custom clipboard data");
    else {
        result = env->NewByteArray(jsize(length + 1));
        if (result) env->SetByteArrayRegion(result, 0, jsize(length + 1), bytes);
    }
    GlobalUnlock(memory);
    return result;
}

inline bool next_format(UINT previous, UINT &format) {
    format = EnumClipboardFormats(previous);
    return format != 0 || GetLastError() == ERROR_SUCCESS;
}

// Every present registered format inside the custom convention, as Java strings.
inline jobjectArray custom_formats(JNIEnv *env, HWND owner) {
    Opened clipboard(env, owner);
    if (!clipboard) return nullptr;
    std::vector<std::wstring> names;
    wchar_t buffer[custom_format::MAX_NAME_CHARS + 1];
    UINT previous = 0;
    while (true) {
        UINT format = 0;
        if (!next_format(previous, format)) {
            fail(env, "java/lang/IllegalStateException", "Cannot enumerate Windows clipboard formats");
            return nullptr;
        }
        if (!format) break;
        previous = format;
        if (format < 0xC000) continue;
        const int length = GetClipboardFormatNameW(format, buffer, int(sizeof(buffer) / sizeof(buffer[0])));
        if (length <= 0) continue;
        std::wstring name(buffer, size_t(length));
        if (custom_format::valid_name(name)) {
            names.push_back(std::move(name));
            if (names.size() >= custom_format::MAX_FORMATS) break;
        }
    }
    jclass string_class = env->FindClass("java/lang/String");
    if (!string_class) return nullptr;
    jobjectArray result = env->NewObjectArray(jsize(names.size()), string_class, nullptr);
    if (result) {
        for (jsize i = 0; i < jsize(names.size()); ++i) {
            jstring name = env->NewString(reinterpret_cast<const jchar *>(names[i].data()), jsize(names[i].size()));
            if (!name) { env->DeleteLocalRef(string_class); return nullptr; }
            env->SetObjectArrayElement(result, i, name);
            env->DeleteLocalRef(name);
        }
    }
    env->DeleteLocalRef(string_class);
    return result;
}

// Parses DROPFILES bytes shared with the OLE drag reader; returns a Java
// String[] of paths, or null when the format is absent.
inline jobjectArray read_files(JNIEnv *env, HWND owner) {
    Opened clipboard(env, owner);
    if (!clipboard || !IsClipboardFormatAvailable(CF_HDROP)) return nullptr;
    HANDLE memory = GetClipboardData(CF_HDROP);
    const SIZE_T size = memory ? GlobalSize(memory) : 0;
    if (!memory || size < sizeof(DROPFILES) + sizeof(wchar_t) || size > MAX_TEXT_BYTES * 2) {
        fail(env, "java/lang/IllegalStateException", "Invalid Windows clipboard file list");
        return nullptr;
    }
    LockedGlobal locked(memory);
    const auto *bytes = static_cast<const uint8_t *>(locked.get());
    if (!bytes) { fail(env, "java/lang/IllegalStateException", "Cannot lock Windows clipboard files"); return nullptr; }
    std::vector<std::u16string> paths;
    bool valid = windows_dropfiles::visit(bytes, size, MAX_PATHS, MAX_PATH_CHARS,
        [&](const uint8_t *path, size_t length, bool wide) {
            if (wide) {
                paths.emplace_back(length, char16_t(0));
                memcpy(paths.back().data(), path, length * sizeof(char16_t));
            } else {
                const char *ansi = reinterpret_cast<const char *>(path);
                int chars = MultiByteToWideChar(CP_ACP, 0, ansi, int(length), nullptr, 0);
                if (chars <= 0 || size_t(chars) > MAX_PATH_CHARS) return false;
                paths.emplace_back(size_t(chars), char16_t(0));
                if (MultiByteToWideChar(CP_ACP, 0, ansi, int(length),
                        reinterpret_cast<wchar_t *>(paths.back().data()), chars) != chars) return false;
            }
            return true;
        });
    if (!valid || paths.empty()) {
        fail(env, "java/lang/IllegalStateException", "Malformed Windows clipboard file list");
        return nullptr;
    }
    jclass string_class = env->FindClass("java/lang/String");
    if (!string_class) return nullptr;
    jobjectArray result = env->NewObjectArray(jsize(paths.size()), string_class, nullptr);
    if (result) {
        for (jsize i = 0; i < jsize(paths.size()); ++i) {
            jstring path = env->NewString(reinterpret_cast<const jchar *>(paths[i].data()), jsize(paths[i].size()));
            if (!path) { env->DeleteLocalRef(string_class); return nullptr; }
            env->SetObjectArrayElement(result, i, path);
            env->DeleteLocalRef(path);
        }
    }
    env->DeleteLocalRef(string_class);
    return result;
}

// CF_DIB is a BITMAPINFO (header + pixels) with no file header. Only the
// common BI_RGB 24/32bpp layouts are accepted; pixels come back top-down as
// {width, height, ARGB...}.
inline bool image_layout(const BITMAPINFOHEADER &header, SIZE_T size, LONG &height, SIZE_T &stride, SIZE_T &pixel_offset) {
    // Check the signed range before negation: -LONG_MIN is undefined in C++.
    if (size > MAX_DIB_BYTES || header.biSize < sizeof(BITMAPINFOHEADER)
            || SIZE_T(header.biSize) > size || header.biPlanes != 1
            || header.biCompression != BI_RGB || (header.biBitCount != 24 && header.biBitCount != 32)
            || header.biWidth < 1 || header.biWidth > MAX_IMAGE_DIM
            || header.biHeight == 0 || header.biHeight < -LONG(MAX_IMAGE_DIM)
            || header.biHeight > MAX_IMAGE_DIM) return false;
    height = header.biHeight < 0 ? -header.biHeight : header.biHeight;
    stride = ((SIZE_T(header.biWidth) * header.biBitCount + 31) / 32) * 4;
    const SIZE_T available = size - SIZE_T(header.biSize);
    if (SIZE_T(header.biClrUsed) > available / sizeof(RGBQUAD)) return false;
    pixel_offset = SIZE_T(header.biSize) + SIZE_T(header.biClrUsed) * sizeof(RGBQUAD);
    return stride * SIZE_T(height) <= size - pixel_offset;
}

inline jintArray read_image(JNIEnv *env, HWND owner) {
    Opened clipboard(env, owner);
    if (!clipboard || !IsClipboardFormatAvailable(CF_DIB)) return nullptr;
    HANDLE memory = GetClipboardData(CF_DIB);
    const SIZE_T size = memory ? GlobalSize(memory) : 0;
    if (!memory || size < sizeof(BITMAPINFOHEADER) + 4 || size > MAX_DIB_BYTES) {
        fail(env, "java/lang/IllegalStateException", "Invalid Windows clipboard image");
        return nullptr;
    }
    const auto *bytes = static_cast<const uint8_t *>(GlobalLock(memory));
    if (!bytes) { fail(env, "java/lang/IllegalStateException", "Cannot lock Windows clipboard image"); return nullptr; }
    BITMAPINFOHEADER header{};
    memcpy(&header, bytes, sizeof(header));
    const LONG width = header.biWidth, raw_height = header.biHeight;
    const bool top_down = raw_height < 0;
    LONG height = 0;
    const uint32_t bpp = header.biBitCount;
    SIZE_T stride = 0, pixel_offset = 0;
    bool valid = image_layout(header, size, height, stride, pixel_offset);
    jintArray result = nullptr;
    if (valid) {
        result = env->NewIntArray(2 + width * height);
        jint *out = result ? env->GetIntArrayElements(result, nullptr) : nullptr;
        if (!out) valid = false;
        else {
            out[0] = width; out[1] = height;
            const uint8_t *pixel_base = bytes + pixel_offset;
            for (LONG y = 0; y < height; ++y) {
                const LONG source_y = top_down ? y : height - 1 - y;
                const uint8_t *row = pixel_base + stride * SIZE_T(source_y);
                jint *target = out + 2 + SIZE_T(y) * SIZE_T(width);
                for (LONG x = 0; x < width; ++x) {
                    const uint8_t blue = row[x * (bpp / 8) + 0], green = row[x * (bpp / 8) + 1], red = row[x * (bpp / 8) + 2];
                    const uint8_t alpha = bpp == 32 ? row[x * 4 + 3] : 0xFF;
                    target[x] = jint((uint32_t(alpha) << 24) | (uint32_t(red) << 16) | (uint32_t(green) << 8) | blue);
                }
            }
            env->ReleaseIntArrayElements(result, out, 0);
        }
    }
    GlobalUnlock(memory);
    if (!valid) {
        if (result) env->DeleteLocalRef(result);
        if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalStateException", "Unsupported Windows clipboard image layout");
        return nullptr;
    }
    return result;
}

// Wide UniformResourceLocatorW first; ANSI-only sources convert through ACP.
inline jstring read_url(JNIEnv *env, HWND owner) {
    UINT wide = RegisterClipboardFormatW(L"UniformResourceLocatorW");
    if (wide && IsClipboardFormatAvailable(wide)) return read(env, owner, wide);
    UINT ansi = RegisterClipboardFormatW(L"UniformResourceLocator");
    if (!ansi) { fail(env, "java/lang/IllegalStateException", "Cannot register URL clipboard format"); return nullptr; }
    Opened clipboard(env, owner);
    if (!clipboard || !IsClipboardFormatAvailable(ansi)) return nullptr;
    HANDLE memory = GetClipboardData(ansi);
    const SIZE_T size = memory ? GlobalSize(memory) : 0;
    if (!memory || size < 1 || size > MAX_TEXT_BYTES) {
        fail(env, "java/lang/IllegalStateException", "Invalid Windows clipboard URL");
        return nullptr;
    }
    LockedGlobal locked(memory);
    const auto *bytes = static_cast<const char *>(locked.get());
    if (!bytes) { fail(env, "java/lang/IllegalStateException", "Cannot lock Windows clipboard URL"); return nullptr; }
    size_t length = 0;
    while (length < size && bytes[length]) ++length;
    jstring result = nullptr;
    if (length == size || length == 0) fail(env, "java/lang/IllegalStateException", "Unterminated Windows clipboard URL");
    else {
        int wide_length = MultiByteToWideChar(CP_ACP, 0, bytes, int(length), nullptr, 0);
        if (wide_length <= 0) fail(env, "java/lang/IllegalStateException", "Cannot convert ANSI clipboard URL");
        else {
            std::wstring text(size_t(wide_length), 0);
            MultiByteToWideChar(CP_ACP, 0, bytes, int(length), text.data(), wide_length);
            result = env->NewString(reinterpret_cast<const jchar *>(text.data()), jsize(text.size()));
        }
    }
    return result;
}
}
