#include <windows.h>
#include <stdexcept>
#include <iostream>
#include <new>
#include <limits>

static unsigned frees;
static HGLOBAL tracked_free(HGLOBAL block) { ++frees; return GlobalFree(block); }
static UINT enumeration_next;
static UINT enumeration_previous;
static DWORD enumeration_error;
static UINT fake_enumeration(UINT previous) { enumeration_previous = previous; return enumeration_next; }
static DWORD fake_last_error() { return enumeration_error; }
#define GlobalFree tracked_free
#define EnumClipboardFormats fake_enumeration
#define GetLastError fake_last_error
#include "windows_clipboard.h"
#undef GlobalFree
#undef EnumClipboardFormats
#undef GetLastError

using namespace godot_javafx::windows_clipboard;
static void require(bool value, const char *message) {
    if (!value) throw std::runtime_error(message);
}
static HGLOBAL block() {
    HGLOBAL value = GlobalAlloc(GMEM_MOVEABLE, 64);
    if (!value) throw std::bad_alloc();
    return value;
}
// A mutable Java array returns a different immutable String on a second read.
// Encoding must retain the first observation, without reopening the clipboard.
static unsigned path_reads;
static jsize JNICALL fake_array_length(JNIEnv *, jarray) { return 1; }
static jobject JNICALL fake_path(JNIEnv *, jobjectArray, jsize) {
    static const char16_t first[] = u"A", replacement[] = u"B";
    return reinterpret_cast<jobject>(const_cast<char16_t *>(++path_reads == 1 ? first : replacement));
}
static jsize JNICALL fake_string_length(JNIEnv *, jstring) { return 1; }
static void JNICALL fake_string_region(JNIEnv *, jstring value, jsize, jsize length, jchar *out) {
    memcpy(out, value, size_t(length) * sizeof(jchar));
}
static void JNICALL fake_delete_local(JNIEnv *, jobject) {}
static jboolean JNICALL fake_exception(JNIEnv *) { return JNI_FALSE; }
static void check_path_snapshot() {
    JNINativeInterface_ functions{};
    functions.GetArrayLength = fake_array_length;
    functions.GetObjectArrayElement = fake_path;
    functions.GetStringLength = fake_string_length;
    functions.GetStringRegion = fake_string_region;
    functions.DeleteLocalRef = fake_delete_local;
    functions.ExceptionCheck = fake_exception;
    JNIEnv env{&functions};
    HGLOBAL encoded = encode_hdrop(&env, reinterpret_cast<jobjectArray>(&functions));
    require(encoded != nullptr, "Path snapshot encoding failed");
    const auto *bytes = static_cast<const uint8_t *>(GlobalLock(encoded));
    bool correct = bytes && GlobalSize(encoded) >= sizeof(DROPFILES) + 6
            && reinterpret_cast<const char16_t *>(bytes + sizeof(DROPFILES))[0] == u'A'
            && reinterpret_cast<const char16_t *>(bytes + sizeof(DROPFILES))[1] == 0
            && reinterpret_cast<const char16_t *>(bytes + sizeof(DROPFILES))[2] == 0;
    if (bytes) GlobalUnlock(encoded);
    GlobalFree(encoded);
    require(correct && path_reads == 1, "File list was fetched again after sizing");
    std::cout << "CLIPBOARD_PATH_SNAPSHOT_PASS (mock JNI, no clipboard access)\n";
}
int main() {
    try {
        check_path_snapshot();
        UINT format = 99;
        enumeration_next = 0; enumeration_error = ERROR_SUCCESS;
        require(next_format(0, format) && format == 0, "Empty enumeration rejected");
        enumeration_next = CF_UNICODETEXT; enumeration_error = ERROR_ACCESS_DENIED;
        require(next_format(0, format) && format == CF_UNICODETEXT && enumeration_previous == 0,
                "Successful enumeration used an irrelevant last error");
        enumeration_next = 0;
        require(!next_format(CF_UNICODETEXT, format) && format == 0 && enumeration_previous == CF_UNICODETEXT,
                "Partial enumeration error accepted as completion");
        require(!next_format(0, format), "Initial enumeration error accepted as empty clipboard");
        enumeration_error = ERROR_SUCCESS;
        require(next_format(CF_UNICODETEXT, format) && format == 0, "Normal enumeration end rejected");
        std::cout << "CLIPBOARD_ENUMERATION_FAILURE_PASS (mock API, no clipboard access)\n";
        // Exercise the scanner used by both clipboard and OLE readers, with
        // exact byte lengths (GlobalAlloc may round allocations upward).
        for (bool wide : {false, true}) {
            DROPFILES files{}; files.pFiles = sizeof(files) + 1; files.fWide = wide;
            const size_t unit = wide ? 2 : 1;
            std::vector<uint8_t> bytes(files.pFiles + 4 * unit, 0);
            memcpy(bytes.data(), &files, sizeof(files));
            bytes[files.pFiles] = 'A'; bytes[files.pFiles + unit] = 'B';
            size_t visits = 0;
            auto visitor = [&](const uint8_t *path, size_t length, bool is_wide) {
                ++visits;
                require(is_wide == wide && length == 2 && path[0] == 'A' && path[unit] == 'B',
                        "Unaligned path decoded incorrectly");
                return true;
            };
            require(godot_javafx::windows_dropfiles::visit(bytes.data(), bytes.size(), 1, 2, visitor)
                    && visits == 1, "Valid unaligned double-NUL list rejected");
            require(!godot_javafx::windows_dropfiles::visit(bytes.data(), bytes.size() - unit, 1, 2, visitor),
                    "Single-NUL list accepted");
            require(!godot_javafx::windows_dropfiles::visit(bytes.data(), files.pFiles + 2 * unit, 1, 2, visitor),
                    "Unterminated path accepted");
            require(!godot_javafx::windows_dropfiles::visit(bytes.data(), bytes.size() - 1, 1, 2, visitor),
                    "Partial list terminator accepted");
            require(!godot_javafx::windows_dropfiles::visit(bytes.data(), bytes.size(), 0, 2, visitor),
                    "Path-count bound ignored");
            if (wide) require(!godot_javafx::windows_dropfiles::visit(bytes.data(), bytes.size(), 1, 1, visitor),
                    "UTF-16 path-length bound ignored");
            bytes[files.pFiles] = 0;
            require(!godot_javafx::windows_dropfiles::visit(bytes.data(), bytes.size(), 1, 2, visitor),
                    "Empty file list accepted");
            bytes[files.pFiles] = 'A';
            files.pFiles = DWORD(bytes.size() + 1); memcpy(bytes.data(), &files, sizeof(files));
            require(!godot_javafx::windows_dropfiles::visit(bytes.data(), bytes.size(), 1, 2, visitor),
                    "Out-of-bounds path offset accepted");
        }
        BITMAPINFOHEADER header{};
        header.biSize = sizeof(header); header.biWidth = 3; header.biHeight = 2;
        header.biPlanes = 1; header.biBitCount = 24; header.biCompression = BI_RGB;
        LONG height = 0; SIZE_T stride = 0, pixel_offset = 0;
        require(image_layout(header, sizeof(header) + 24, height, stride, pixel_offset) && height == 2 && stride == 12,
                "Padded 24-bit image rejected");
        require(!image_layout(header, sizeof(header) + 23, height, stride, pixel_offset), "Truncated final row accepted");
        header.biHeight = -2; header.biBitCount = 32;
        require(image_layout(header, sizeof(header) + 24, height, stride, pixel_offset) && height == 2 && stride == 12,
                "Top-down 32-bit image rejected");
        for (LONG invalid : {(std::numeric_limits<LONG>::min)(), LONG(-MAX_IMAGE_DIM - 1), LONG(0), LONG(MAX_IMAGE_DIM + 1)}) {
            header.biHeight = invalid;
            require(!image_layout(header, MAX_DIB_BYTES, height, stride, pixel_offset), "Invalid signed height accepted");
        }
        header.biHeight = 2; header.biWidth = (std::numeric_limits<LONG>::max)();
        require(!image_layout(header, MAX_DIB_BYTES, height, stride, pixel_offset), "Oversized width accepted");
        header.biWidth = 3; header.biSize = (std::numeric_limits<DWORD>::max)();
        require(!image_layout(header, 64, height, stride, pixel_offset), "Out-of-bounds header accepted");
        header.biClrUsed = 2;
        for (DWORD header_size : {DWORD(sizeof(header)), DWORD(sizeof(BITMAPV4HEADER)), DWORD(sizeof(BITMAPV5HEADER))}) {
            header.biSize = header_size;
            for (WORD bits : {WORD(24), WORD(32)}) {
                header.biBitCount = bits;
                require(image_layout(header, header_size + 8 + 24, height, stride, pixel_offset)
                        && pixel_offset == header_size + 8, "Color table treated as pixels");
                require(!image_layout(header, header_size + 24, height, stride, pixel_offset),
                        "Missing pixel bytes after color table accepted");
            }
        }
        header.biSize = sizeof(header);
        header.biClrUsed = (std::numeric_limits<DWORD>::max)();
        require(!image_layout(header, 128, height, stride, pixel_offset), "Oversized color table accepted");
        HGLOBAL transferred = block();
        try {
            PreparedExtras prepared;
            require(prepared.blocks.capacity() >= 34, "Insufficient preallocated format capacity");
            prepared.blocks.emplace_back(CF_DIB, block());
            prepared.blocks.emplace_back(CF_HDROP, block());
            prepared.blocks.emplace_back(CF_TEXT, transferred);
            prepared.blocks.back().second = nullptr; // Successful publication transfers ownership.
            throw std::bad_alloc(); // Later format-name allocation fails.
        } catch (const std::bad_alloc &) {}
        require(frees == 2, "Unpublished blocks leaked or transferred block freed");
        require(GlobalSize(transferred) >= 64, "Transferred block lost ownership");
        GlobalFree(transferred);
        HGLOBAL borrowed = block();
        try {
            LockedGlobal locked(borrowed);
            require(locked.get() != nullptr, "Lock failed");
            require((GlobalFlags(borrowed) & GMEM_LOCKCOUNT) == 1, "Missing lock");
            throw std::bad_alloc(); // Parsing a string/vector fails while locked.
        } catch (const std::bad_alloc &) {}
        require((GlobalFlags(borrowed) & GMEM_LOCKCOUNT) == 0, "Borrowed block left locked");
        require(frees == 2, "Borrowed block was freed");
        GlobalFree(borrowed);
        std::cout << "CLIPBOARD_OWNERSHIP_PASS (no system clipboard access)\n";
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
