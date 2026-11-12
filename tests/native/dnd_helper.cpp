// External OLE drag/drop endpoint for Glass-Godot cross-application tests.
// Modes:
//   dnd_helper target <x> <y> <w> <h> <logfile>
//       Registers an IDropTarget on a chromeless window and logs every drop.
//   dnd_helper source <x> <y> <w> <h> <logfile> <text> <url> <file>
//       Starts DoDragDrop (text + URL + file list) when the left button is
//       pressed inside its window, then logs the performed effect.
// Logs are flushed per line; the harness kills the process when done.
#include <windows.h>
#include <ole2.h>
#include <shlobj.h>
#include <shellapi.h>
#include <cstdio>
#include <algorithm>
#include <share.h>
#include <cstring>
#include <string>
#include <vector>
#include <new>
#include <stdexcept>
#include <wrl/client.h>
#include "../../native/godot_modules/javafx/windows_dropfiles.h"

static FILE *log_file = nullptr;
static const wchar_t *CUSTOM_FORMAT_NAME = L"application/x-godot-custom-token";

static void log_line(const char *text) {
    if (!log_file) return;
    fputs(text, log_file);
    fputc('\n', log_file);
    fflush(log_file);
}

static std::string narrow(const std::wstring &wide) {
    if (wide.empty()) return {};
    int length = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), int(wide.size()), nullptr, 0, nullptr, nullptr);
    std::string result(length, 0);
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), int(wide.size()), result.data(), length, nullptr, nullptr);
    return result;
}

class HelperFormatEnumerator : public IEnumFORMATETC {
	std::vector<FORMATETC> formats;
	size_t cursor = 0;
	ULONG refs = 1;
public:
	explicit HelperFormatEnumerator(std::vector<FORMATETC> p_formats) : formats(std::move(p_formats)) {}
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override {
		if (!object) return E_POINTER;
		if (iid == IID_IUnknown || iid == IID_IEnumFORMATETC) { *object = static_cast<IEnumFORMATETC *>(this); AddRef(); return S_OK; }
		*object = nullptr;
		return E_NOINTERFACE;
	}
	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
	ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = --refs;
        if (!remaining) delete this;
        return remaining;
    }
	HRESULT STDMETHODCALLTYPE Next(ULONG count, FORMATETC *out, ULONG *fetched) override {
		if (fetched) *fetched = 0;
		if (!out || (!fetched && count != 1)) return E_POINTER;
		ULONG done = 0;
		while (done < count && cursor < formats.size()) out[done++] = formats[cursor++];
		if (fetched) *fetched = done;
		return done == count ? S_OK : S_FALSE;
	}
	HRESULT STDMETHODCALLTYPE Skip(ULONG count) override {
		const size_t skipped = (std::min)(size_t(count), formats.size() - cursor);
		cursor += skipped;
		return skipped == count ? S_OK : S_FALSE;
	}
	HRESULT STDMETHODCALLTYPE Reset() override { cursor = 0; return S_OK; }
	HRESULT STDMETHODCALLTYPE Clone(IEnumFORMATETC **copy) override {
		if (!copy) return E_POINTER;
		*copy = nullptr;
		try {
			auto *clone = new HelperFormatEnumerator(formats);
			clone->cursor = cursor;
			*copy = clone;
			return S_OK;
		} catch (const std::bad_alloc &) { return E_OUTOFMEMORY; }
	}
};

class HelperDataObject : public IDataObject {
    std::wstring text, url;
    std::vector<std::wstring> files;
    std::string custom; // NUL-terminated UTF-8 payload for CUSTOM_FORMAT_NAME.
    ULONG refs = 1;
    static HRESULT store(const void *bytes, size_t size, STGMEDIUM *medium) {
        HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE, size);
        if (!block) return E_OUTOFMEMORY;
        void *locked = GlobalLock(block);
        if (!locked) { GlobalFree(block); return E_UNEXPECTED; }
        memcpy(locked, bytes, size);
        GlobalUnlock(block);
        medium->tymed = TYMED_HGLOBAL;
        medium->hGlobal = block;
        medium->pUnkForRelease = nullptr;
        return S_OK;
    }
public:
    HelperDataObject(std::wstring p_text, std::wstring p_url, std::vector<std::wstring> p_files, std::string p_custom)
        : text(std::move(p_text)), url(std::move(p_url)), files(std::move(p_files)), custom(std::move(p_custom)) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override {
        if (!object) return E_POINTER;
        if (iid == IID_IUnknown || iid == IID_IDataObject) { *object = static_cast<IDataObject *>(this); AddRef(); return S_OK; }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = --refs;
        if (!remaining) delete this;
        return remaining;
    }
    HRESULT STDMETHODCALLTYPE GetData(FORMATETC *etc, STGMEDIUM *medium) override {
        if (!medium) return E_POINTER;
        *medium = {};
        HRESULT accepted = QueryGetData(etc);
        if (accepted != S_OK) return accepted;
        try {
            UINT url_format = RegisterClipboardFormatW(L"UniformResourceLocatorW");
            if (etc->cfFormat == CF_UNICODETEXT) return store(text.c_str(), (text.size() + 1) * sizeof(wchar_t), medium);
            if (etc->cfFormat == url_format) return store(url.c_str(), (url.size() + 1) * sizeof(wchar_t), medium);
            if (etc->cfFormat == CF_HDROP) {
                size_t chars = files.empty() ? 2 : 1;
                for (const auto &file : files) chars += file.size() + 1;
                std::vector<uint8_t> bytes(sizeof(DROPFILES) + chars * sizeof(wchar_t), 0);
                DROPFILES header{};
                header.pFiles = sizeof(DROPFILES);
                header.fWide = TRUE;
                memcpy(bytes.data(), &header, sizeof(header));
                wchar_t *cursor = reinterpret_cast<wchar_t *>(bytes.data() + sizeof(DROPFILES));
                for (const auto &file : files) { memcpy(cursor, file.c_str(), file.size() * sizeof(wchar_t)); cursor += file.size() + 1; }
                return store(bytes.data(), bytes.size(), medium);
            }
            if (!custom.empty() && etc->cfFormat == RegisterClipboardFormatW(CUSTOM_FORMAT_NAME))
                return store(custom.data(), custom.size(), medium);
            return DV_E_FORMATETC;
        } catch (const std::bad_alloc &) { return E_OUTOFMEMORY; }
        catch (const std::length_error &) { return E_OUTOFMEMORY; }
    }
    HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC *, STGMEDIUM *) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC *etc) override {
        if (!etc) return E_POINTER;
        if (etc->dwAspect != DVASPECT_CONTENT) return DV_E_DVASPECT;
        if (!(etc->tymed & TYMED_HGLOBAL)) return DV_E_TYMED;
        if (etc->lindex != -1) return DV_E_LINDEX;
        if (etc->ptd) return DV_E_DVTARGETDEVICE;
        UINT url_format = RegisterClipboardFormatW(L"UniformResourceLocatorW");
        if (etc->cfFormat == CF_UNICODETEXT || etc->cfFormat == url_format || etc->cfFormat == CF_HDROP) return S_OK;
        if (!custom.empty() && etc->cfFormat == RegisterClipboardFormatW(CUSTOM_FORMAT_NAME)) return S_OK;
        return DV_E_FORMATETC;
    }
    HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC *input, FORMATETC *out) override {
        if (!out) return E_POINTER;
        if (!input) { *out = {}; return E_POINTER; }
        *out = *input;
        out->ptd = nullptr; // No device-specific rendering; no borrowed pointer escapes.
        return DATA_S_SAMEFORMATETC;
    }
    HRESULT STDMETHODCALLTYPE SetData(FORMATETC *, STGMEDIUM *, BOOL) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction, IEnumFORMATETC **enumerator) override {
        if (!enumerator) return E_POINTER;
        *enumerator = nullptr;
        if (direction != DATADIR_GET) return E_NOTIMPL;
        try {
            std::vector<FORMATETC> formats;
            auto add = [&formats](UINT format) {
                FORMATETC etc{};
                etc.cfFormat = CLIPFORMAT(format);
                etc.dwAspect = DVASPECT_CONTENT;
                etc.lindex = -1;
                etc.tymed = TYMED_HGLOBAL;
                formats.push_back(etc);
            };
            add(CF_UNICODETEXT);
            add(RegisterClipboardFormatW(L"UniformResourceLocatorW"));
            add(CF_HDROP);
            if (!custom.empty()) add(RegisterClipboardFormatW(CUSTOM_FORMAT_NAME));
            *enumerator = new HelperFormatEnumerator(std::move(formats));
            return S_OK;
        } catch (const std::bad_alloc &) { return E_OUTOFMEMORY; }
    }

    HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC *, DWORD, IAdviseSink *, DWORD *connection) override {
        if (connection) *connection = 0;
        return OLE_E_ADVISENOTSUPPORTED;
    }
    HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
    HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA **enumerator) override {
        if (!enumerator) return E_POINTER;
        *enumerator = nullptr;
        return OLE_E_ADVISENOTSUPPORTED;
    }
};

class HelperDropSource : public IDropSource {
    ULONG refs = 1;
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override {
        if (!object) return E_POINTER;
        if (iid == IID_IUnknown || iid == IID_IDropSource) { *object = static_cast<IDropSource *>(this); AddRef(); return S_OK; }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = --refs;
        if (!remaining) delete this;
        return remaining;
    }
    HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape, DWORD keys) override {
        if (escape) return DRAGDROP_S_CANCEL;
        if (!(keys & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON))) return DRAGDROP_S_DROP;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }
};

struct HelperMedium {
    STGMEDIUM value{};
    HelperMedium() = default;
    HelperMedium(const HelperMedium &) = delete;
    HelperMedium &operator=(const HelperMedium &) = delete;
    ~HelperMedium() { if (value.tymed != TYMED_NULL) ReleaseStgMedium(&value); }
};
struct HelperGlobalLock {
    HGLOBAL block;
    const void *data;
    explicit HelperGlobalLock(HGLOBAL value) : block(value), data(GlobalLock(value)) {}
    HelperGlobalLock(const HelperGlobalLock &) = delete;
    HelperGlobalLock &operator=(const HelperGlobalLock &) = delete;
    ~HelperGlobalLock() { if (data) GlobalUnlock(block); }
};
static constexpr SIZE_T HELPER_MAX_TEXT_BYTES = 16 * 1024 * 1024;

class HelperDropTarget : public IDropTarget {
    ULONG refs = 1;
    HWND owner;
    bool accepts_text = false;
    static bool has(IDataObject *object, UINT format) {
        FORMATETC etc{ CLIPFORMAT(format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        return object->QueryGetData(&etc) == S_OK;
    }
    static std::wstring read_text(IDataObject *object, UINT format) {
        FORMATETC etc{ CLIPFORMAT(format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        HelperMedium medium;
        HRESULT result = object->GetData(&etc, &medium.value);
        if (result == DV_E_FORMATETC) return {};
        if (result == E_OUTOFMEMORY) throw std::bad_alloc();
        if (result != S_OK || medium.value.tymed != TYMED_HGLOBAL || !medium.value.hGlobal)
            throw std::invalid_argument("Invalid helper text medium");
        SIZE_T bytes = GlobalSize(medium.value.hGlobal);
        if (bytes == 0 || bytes > HELPER_MAX_TEXT_BYTES || bytes % sizeof(wchar_t))
            throw std::invalid_argument("Invalid helper text size");
        HelperGlobalLock locked(medium.value.hGlobal);
        if (!locked.data) throw std::invalid_argument("Cannot lock helper text");
        const auto *wide = static_cast<const wchar_t *>(locked.data);
        size_t length = 0, limit = bytes / sizeof(wchar_t);
        while (length < limit && wide[length]) ++length;
        if (length == limit) throw std::invalid_argument("Unterminated helper text");
        return std::wstring(wide, length);
    }
public:
    explicit HelperDropTarget(HWND window) : owner(window) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override {
        if (!object) return E_POINTER;
        if (iid == IID_IUnknown || iid == IID_IDropTarget) { *object = static_cast<IDropTarget *>(this); AddRef(); return S_OK; }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = --refs;
        if (!remaining) delete this;
        return remaining;
    }
    HRESULT STDMETHODCALLTYPE DragEnter(IDataObject *object, DWORD, POINTL point, DWORD *effect) override {
        accepts_text = false;
        if (!effect) return E_POINTER;
        const DWORD allowed = *effect;
        *effect = DROPEFFECT_NONE;
        if (!object) return E_POINTER;
        accepts_text = has(object, CF_UNICODETEXT);
        *effect = accepts_text ? allowed & DROPEFFECT_COPY : DROPEFFECT_NONE;
        // The shell drag-image helper attaches DragImageBits when the source
        // registered a drag view. Header: SIZE size, POINT offset, COLORREF.
        char image[96] = "image=none";
        UINT image_format = RegisterClipboardFormatW(L"DragImageBits");
        FORMATETC image_etc{ CLIPFORMAT(image_format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        STGMEDIUM image_medium{};
        if (image_format && object->QueryGetData(&image_etc) == S_OK
                && object->GetData(&image_etc, &image_medium) == S_OK
                && image_medium.tymed == TYMED_HGLOBAL && image_medium.hGlobal) {
            const uint8_t *bytes = static_cast<const uint8_t *>(GlobalLock(image_medium.hGlobal));
            SIZE_T size = bytes ? GlobalSize(image_medium.hGlobal) : 0;
            if (bytes && size >= 20) {
                int w = int(uint32_t(bytes[0]) | uint32_t(bytes[1]) << 8 | uint32_t(bytes[2]) << 16 | uint32_t(bytes[3]) << 24);
                int h = int(uint32_t(bytes[4]) | uint32_t(bytes[5]) << 8 | uint32_t(bytes[6]) << 16 | uint32_t(bytes[7]) << 24);
                int ox = int(uint32_t(bytes[8]) | uint32_t(bytes[9]) << 8 | uint32_t(bytes[10]) << 16 | uint32_t(bytes[11]) << 24);
                int oy = int(uint32_t(bytes[12]) | uint32_t(bytes[13]) << 8 | uint32_t(bytes[14]) << 16 | uint32_t(bytes[15]) << 24);
                snprintf(image, sizeof(image), "image=%dx%d@%d,%d bytes=%lu", w, h, ox, oy, (unsigned long)size);
            } else if (bytes) {
                snprintf(image, sizeof(image), "image=short");
            }
            if (bytes) GlobalUnlock(image_medium.hGlobal);
        }
        ReleaseStgMedium(&image_medium);
        {   char buf[192];
            snprintf(buf, sizeof(buf), "DND_HELPER_ENTER x=%ld y=%ld effect=%ld %s", point.x, point.y, (long)*effect, image);
            log_line(buf);
        }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD *effect) override {
        if (!effect) return E_POINTER;
        *effect = accepts_text ? *effect & DROPEFFECT_COPY : DROPEFFECT_NONE;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DragLeave() override { accepts_text = false; log_line("DND_HELPER_LEAVE"); return S_OK; }
    static std::string read_bytes(IDataObject *object, UINT format) {
        FORMATETC etc{ CLIPFORMAT(format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        HelperMedium medium;
        HRESULT result = object->GetData(&etc, &medium.value);
        if (result == DV_E_FORMATETC) return {};
        if (result == E_OUTOFMEMORY) throw std::bad_alloc();
        if (result != S_OK || medium.value.tymed != TYMED_HGLOBAL || !medium.value.hGlobal)
            throw std::invalid_argument("Invalid helper custom medium");
        SIZE_T size = GlobalSize(medium.value.hGlobal);
        if (size == 0 || size > HELPER_MAX_TEXT_BYTES) throw std::invalid_argument("Invalid helper custom size");
        HelperGlobalLock locked(medium.value.hGlobal);
        if (!locked.data) throw std::invalid_argument("Cannot lock helper custom data");
        const char *bytes = static_cast<const char *>(locked.data);
        size_t length = strnlen(bytes, size);
        if (length == size) throw std::invalid_argument("Unterminated helper custom text");
        return std::string(bytes, length);
    }
    struct FileSummary { int count = -1; std::wstring first; };
    static FileSummary read_files(IDataObject *object) {
        FORMATETC etc{ CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        HelperMedium owned;
        HRESULT result = object->GetData(&etc, &owned.value);
        if (result == DV_E_FORMATETC) return {};
        if (result == E_OUTOFMEMORY) throw std::bad_alloc();
        if (result != S_OK || owned.value.tymed != TYMED_HGLOBAL || !owned.value.hGlobal)
            throw std::invalid_argument("Invalid helper files medium");
        SIZE_T size = GlobalSize(owned.value.hGlobal);
        if (size < sizeof(DROPFILES) || size > HELPER_MAX_TEXT_BYTES)
            throw std::invalid_argument("Invalid helper files size");
        HelperGlobalLock locked(owned.value.hGlobal);
        if (!locked.data) throw std::invalid_argument("Cannot lock helper files");
        const auto *bytes = static_cast<const uint8_t *>(locked.data);
        DROPFILES header{};
        memcpy(&header, bytes, sizeof(header));
        FileSummary summary{0, {}};
        // The shared parser requires a nonempty list. Accept a correctly
        // terminated empty list too, as emitted by HelperDataObject.
        const size_t unit = header.fWide ? 2 : 1;
        if (header.pFiles >= sizeof(header) && header.pFiles <= size && size-header.pFiles >= 2*unit) {
            uint32_t terminators = 0;
            memcpy(&terminators, bytes+header.pFiles, 2*unit);
            if (!terminators) return summary;
        }
        bool valid = godot_javafx::windows_dropfiles::visit(bytes, size, 4096, 32767,
                [&](const uint8_t *path, size_t length, bool wide) {
            if (length > 32767) return false;
            if (summary.count == 0) {
                if (wide) {
                    summary.first.resize(length);
                    memcpy(summary.first.data(), path, length*sizeof(wchar_t));
                } else {
                    int chars = MultiByteToWideChar(CP_ACP, 0, reinterpret_cast<const char *>(path), int(length), nullptr, 0);
                    if (chars <= 0 || chars > 32767) return false;
                    summary.first.resize(chars);
                    if (MultiByteToWideChar(CP_ACP, 0, reinterpret_cast<const char *>(path), int(length), summary.first.data(), chars) != chars)
                        return false;
                }
            }
            ++summary.count;
            return true;
        });
        if (!valid) throw std::invalid_argument("Malformed helper file list");
        return summary;
    }
    HRESULT STDMETHODCALLTYPE Drop(IDataObject *object, DWORD, POINTL, DWORD *effect) override {
        accepts_text = false;
        if (!effect) return E_POINTER;
        const DWORD allowed = *effect;
        *effect = DROPEFFECT_NONE;
        if (!object) return E_POINTER;
        try {
            std::wstring text = read_text(object, CF_UNICODETEXT);
            std::wstring url = read_text(object, RegisterClipboardFormatW(L"UniformResourceLocatorW"));
            std::string custom = read_bytes(object, RegisterClipboardFormatW(CUSTOM_FORMAT_NAME));
            FileSummary files = read_files(object);
            std::string line = "DND_HELPER_DROP text=[" + narrow(text) + "] url=[" + narrow(url) + "] files=" + std::to_string(files.count) + " first=[" + narrow(files.first) + "] custom=[" + custom + "]";
            log_line(line.c_str());
            *effect = text.empty() ? DROPEFFECT_NONE : allowed & DROPEFFECT_COPY;
            return S_OK;
        } catch (const std::bad_alloc &) { return E_OUTOFMEMORY; }
        catch (const std::length_error &) { return E_OUTOFMEMORY; }
        catch (const std::invalid_argument &) { return DV_E_FORMATETC; }
    }

};

static const wchar_t *HELPER_CLASS = L"GodotJfxDndHelper";
static bool source_mode = false;
static std::wstring source_text, source_url, source_file;
static std::string source_custom;
static bool drag_started = false;

static LRESULT CALLBACK helper_wndproc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_LBUTTONDOWN && source_mode && !drag_started) {
        drag_started = true;
        try {
            Microsoft::WRL::ComPtr<IDataObject> object;
            object.Attach(new HelperDataObject(source_text, source_url, { source_file }, source_custom));
            Microsoft::WRL::ComPtr<IDropSource> source;
            source.Attach(new HelperDropSource);
            DWORD effect = 0;
            HRESULT result = DoDragDrop(object.Get(), source.Get(), DROPEFFECT_COPY, &effect);
            if (FAILED(result)) {
                log_line("DND_HELPER_ERROR drag");
                PostQuitMessage(1);
            } else {
                std::string line = "DND_HELPER_SOURCE_DONE effect=" + std::to_string(result == DRAGDROP_S_DROP ? int(effect) : 0);
                log_line(line.c_str());
            }
        } catch (const std::exception &) {
            // No C++ exception may cross the Windows callback boundary.
            log_line("DND_HELPER_ERROR source-allocation");
            PostQuitMessage(1);
        }
        return 0;
    }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

// Construct before initialization so every early return uses the same cleanup.
struct HelperSession {
    HINSTANCE instance = GetModuleHandleW(nullptr);
    HBRUSH unregistered_brush = nullptr;
    HWND window = nullptr;
    HelperDropTarget *target = nullptr;
    bool ole = false, registered_class = false, registered_drop = false;
    ~HelperSession() {
        if (registered_drop && IsWindow(window)) RevokeDragDrop(window);
        if (target) target->Release();
        if (IsWindow(window)) DestroyWindow(window);
        // Windows owns the background brush after successful registration.
        if (registered_class) UnregisterClassW(HELPER_CLASS, instance);
        if (unregistered_brush) DeleteObject(unregistered_brush);
        if (ole) OleUninitialize();
        if (log_file) { fclose(log_file); log_file = nullptr; }
    }
};

int wmain(int argc, wchar_t **argv) {
    if (argc < 7) { fprintf(stderr, "usage: dnd_helper <target|source> x y w h logfile [text url file]\n"); return 2; }
    source_mode = wcscmp(argv[1], L"source") == 0;
    if (!source_mode && wcscmp(argv[1], L"target") != 0) return 2;
    if (source_mode && argc < 10) return 2;
    int x = _wtoi(argv[2]), y = _wtoi(argv[3]), w = _wtoi(argv[4]), h = _wtoi(argv[5]);
    if (w <= 0 || h <= 0) return 2;
    HelperSession session;
    // The launcher reads readiness and payload records while this process runs.
    log_file = _wfsopen(argv[6], L"wb", _SH_DENYWR);
    if (!log_file) return 2;
    try {
        drag_started = false;
        source_custom.clear();
        if (source_mode) {
            source_text = argv[7];
            source_url = argv[8];
            source_file = argv[9];
            if (argc >= 11) { source_custom = narrow(argv[10]); source_custom += '\0'; }
        }
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        if (FAILED(OleInitialize(nullptr))) { log_line("DND_HELPER_ERROR ole"); return 1; }
        session.ole = true;
        WNDCLASSW wc{};
        wc.lpfnWndProc = helper_wndproc;
        wc.hInstance = session.instance;
        wc.lpszClassName = HELPER_CLASS;
        session.unregistered_brush = CreateSolidBrush(RGB(0, 90, 160));
        if (!session.unregistered_brush) { log_line("DND_HELPER_ERROR brush"); return 1; }
        wc.hbrBackground = session.unregistered_brush;
        if (!RegisterClassW(&wc)) { log_line("DND_HELPER_ERROR register"); return 1; }
        session.registered_class = true;
        session.unregistered_brush = nullptr;
        HWND window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, HELPER_CLASS, L"DnD helper", WS_POPUP,
                x, y, w, h, nullptr, nullptr, wc.hInstance, nullptr);
        session.window = window;
        if (!window) { log_line("DND_HELPER_ERROR window"); return 1; }
        if (!source_mode) {
            session.target = new HelperDropTarget(window);
            if (FAILED(RegisterDragDrop(window, session.target))) { log_line("DND_HELPER_ERROR drop-target"); return 1; }
            session.registered_drop = true;
        }
        ShowWindow(window, SW_SHOW);
        UpdateWindow(window);
        RECT rect{};
        GetWindowRect(window, &rect);
        char buf[192];
        snprintf(buf, sizeof(buf), "DND_HELPER_RECT %ld,%ld-%ld,%ld visible=%d topmost=%d",
                rect.left, rect.top, rect.right, rect.bottom,
                (int)IsWindowVisible(window),
                (int)((GetWindowLongW(window, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0));
        log_line(buf);
        log_line(source_mode ? "DND_HELPER_READY source" : "DND_HELPER_READY target");
        MSG message{};
        BOOL status;
        while ((status = GetMessageW(&message, nullptr, 0, 0)) > 0) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if (status == -1) { log_line("DND_HELPER_ERROR message-loop"); return 1; }
        return static_cast<int>(message.wParam);
    } catch (const std::exception &) {
        log_line("DND_HELPER_ERROR startup-allocation");
        return 1;
    }
}
