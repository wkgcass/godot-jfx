#pragma once
#include "windows_dropfiles.h"

#include <windows.h>
#include <ole2.h>
#include <shlobj.h>
#include <jni.h>
#include <atomic>
#include <mutex>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>
#include "windows_custom_format.h"

// OLE drag/drop between the hosted JavaFX application and other Windows
// processes. These calls run on the Godot main thread (window owner) and never
// touch Godot Nodes; completion reaches Java as a synthetic input record.
namespace godot_javafx::windows_dnd {

constexpr size_t MAX_TEXT_BYTES = 16 * 1024 * 1024;
constexpr size_t MAX_URL_CHARS = 4096;
constexpr size_t MAX_PATHS = 4096;
constexpr size_t MAX_PATH_CHARS = 32768;

// Fixed-order '\n' separated lists keep JNI argument encoding trivial. MIME
// names and Windows paths never contain a newline.
inline UINT html_format() { return RegisterClipboardFormatW(L"HTML Format"); }
inline UINT rtf_format() { return RegisterClipboardFormatW(L"Rich Text Format"); }
inline UINT url_format() { return RegisterClipboardFormatW(L"UniformResourceLocatorW"); }
inline UINT url_format_a() { return RegisterClipboardFormatW(L"UniformResourceLocator"); }

struct SourceData {
	std::u16string text, url;
	std::string html, rtf; // HTML carries its Windows clipboard header; both are NUL-terminated.
	std::vector<std::u16string> files;
	std::vector<std::pair<std::wstring, std::string>> custom; // Registered name, NUL-terminated bytes.
	// Dragboard.setDragView payload, as published by the Quantum layer: BGRA
	// bytes in a big-endian w/h envelope. Offsets use INT32_MIN when absent,
	// matching the Win Glass default of the image center.
	struct DragImage {
		uint32_t width = 0, height = 0;
		int32_t offset_x = INT32_MIN, offset_y = INT32_MIN;
		std::vector<uint8_t> bgra;
		bool present() const { return width != 0 && height != 0; }
	};
	DragImage image;
	DWORD effects = 0;
	int buttons = 0;      // Java bit mask 1 << buttonIndex (1 left, 2 right, 3 middle).
	int64_t source_id = 0; // Glass window id; 0 is the root host window.
};

// Published together after JNI registration. The worker closes this gate before
// DestroyJavaVM; the mutex covers the whole upcall, including GetEnv/attachment
// and detachment. Clearing an atomic class pointer alone leaves an entry race.
struct UpcallState {
	std::mutex mutex;
	JavaVM *jvm = nullptr;
	jclass bridge = nullptr;
	jmethodID callback = nullptr;
	void publish(JavaVM *vm, jclass type, jmethodID method) {
		std::lock_guard<std::mutex> lock(mutex);
		jvm = vm;
		bridge = type;
		callback = method;
	}
	void close() {
		std::lock_guard<std::mutex> lock(mutex);
		jvm = nullptr;
		bridge = nullptr;
		callback = nullptr;
	}
};

struct Upcall {
	UpcallState *state = nullptr;
	explicit operator bool() const {
		if (!state) return false;
		std::lock_guard<std::mutex> lock(state->mutex);
		return state->jvm && state->bridge && state->callback;
	}
};

inline jstring to_jstring(JNIEnv *env, const std::u16string *value) {
	if (!value) return nullptr;
	return env->NewString(reinterpret_cast<const jchar *>(value->data()), jsize(value->size()));
}
inline jstring call_string(JNIEnv *env, const std::string &value) {
	return env->NewStringUTF(value.c_str());
}
inline jbyteArray call_bytes(JNIEnv *env, const std::string *value) {
	if (!value) return nullptr;
	jbyteArray result = env->NewByteArray(jsize(value->size()));
	if (result && !value->empty()) env->SetByteArrayRegion(result, 0, jsize(value->size()), reinterpret_cast<const jbyte *>(value->data()));
	return result;
}

// Synchronous Godot-main-thread upcall. The Java handler re-dispatches to the
// JavaFX event thread with a bounded wait, so a stalled FX loop degrades to
// DROPEFFECT_NONE instead of deadlocking the host.
inline jint call_target(const Upcall &upcall, jint kind, int64_t id, jint sx, jint sy, jint effects, jint key_state,
		const std::string &mimes, const std::u16string *text, const std::string *html, const std::string *rtf,
		const std::u16string *url, const std::u16string *files,
		const std::vector<std::pair<std::wstring, std::string>> *custom) {
	if (!upcall.state) return 0;
	// No host/queue lock is held here. The Java dispatch has a bounded wait.
	std::lock_guard<std::mutex> lifetime(upcall.state->mutex);
	JavaVM *jvm = upcall.state->jvm;
	jclass bridge = upcall.state->bridge;
	jmethodID callback = upcall.state->callback;
	if (!jvm || !bridge || !callback) return 0;
	JNIEnv *env = nullptr;
	jint env_result = jvm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_8);
	bool attached = false;
	if (env_result == JNI_EDETACHED) {
		if (jvm->AttachCurrentThread(reinterpret_cast<void **>(&env), nullptr) != JNI_OK) return 0;
		attached = true; // Balance the attach: DestroyJavaVM waits for attached threads.
	} else if (env_result != JNI_OK) return 0;
	jstring mime_arg = nullptr, text_arg = nullptr, url_arg = nullptr, files_arg = nullptr;
	jbyteArray html_arg = nullptr, rtf_arg = nullptr;
	jobjectArray names_arg = nullptr, data_arg = nullptr;
	// Once JNI raises an exception, only exception handling and local-reference
	// cleanup are permitted here. Stop marshalling at the first failed operation.
	auto marshal = [&]() {
		if (env->ExceptionCheck()) return;
		mime_arg = call_string(env, mimes);
		if (env->ExceptionCheck()) return;
		text_arg = to_jstring(env, text);
		if (env->ExceptionCheck()) return;
		html_arg = call_bytes(env, html);
		if (env->ExceptionCheck()) return;
		rtf_arg = call_bytes(env, rtf);
		if (env->ExceptionCheck()) return;
		url_arg = to_jstring(env, url);
		if (env->ExceptionCheck()) return;
		files_arg = to_jstring(env, files);
		if (env->ExceptionCheck() || !custom) return;
		jclass string_class = env->FindClass("java/lang/String");
		if (!string_class) return;
		names_arg = env->NewObjectArray(jsize(custom->size()), string_class, nullptr);
		env->DeleteLocalRef(string_class);
		if (env->ExceptionCheck()) return;
		jclass bytes_class = env->FindClass("[B");
		if (!bytes_class) return;
		data_arg = env->NewObjectArray(jsize(custom->size()), bytes_class, nullptr);
		env->DeleteLocalRef(bytes_class);
		if (env->ExceptionCheck()) return;
		for (jsize i = 0; i < jsize(custom->size()); ++i) {
			jstring name = env->NewString(reinterpret_cast<const jchar *>((*custom)[i].first.data()), jsize((*custom)[i].first.size()));
			if (!name) return;
			env->SetObjectArrayElement(names_arg, i, name);
			env->DeleteLocalRef(name);
			if (env->ExceptionCheck()) return;
			jbyteArray payload = call_bytes(env, &(*custom)[i].second);
			if (payload) {
				if (!env->ExceptionCheck()) env->SetObjectArrayElement(data_arg, i, payload);
				env->DeleteLocalRef(payload);
			}
			if (env->ExceptionCheck()) return;
		}
	};
	marshal();
	jint action = 0;
	if (!env->ExceptionCheck()) {
		action = env->CallStaticIntMethod(bridge, callback, kind, jlong(id), sx, sy, effects, key_state,
				mime_arg, text_arg, html_arg, rtf_arg, url_arg, files_arg, names_arg, data_arg);
	}
	if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); action = 0; }
	if (mime_arg) env->DeleteLocalRef(mime_arg);
	if (text_arg) env->DeleteLocalRef(text_arg);
	if (html_arg) env->DeleteLocalRef(html_arg);
	if (rtf_arg) env->DeleteLocalRef(rtf_arg);
	if (url_arg) env->DeleteLocalRef(url_arg);
	if (files_arg) env->DeleteLocalRef(files_arg);
	if (names_arg) env->DeleteLocalRef(names_arg);
	if (data_arg) env->DeleteLocalRef(data_arg);
	if (attached) jvm->DetachCurrentThread();
	return action;
}

// Data extracted from a source IDataObject. Presence flags mirror the MIME list.
struct Payload {
	bool has_text = false, has_html = false, has_rtf = false, has_url = false, has_files = false;
	std::u16string text, url, files;
	std::string html, rtf;
	std::vector<std::pair<std::wstring, std::string>> custom; // NUL-terminated bytes.
	std::string mimes;
};

inline bool query_format(IDataObject *object, UINT format) {
	FORMATETC etc{ CLIPFORMAT(format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
	return object->QueryGetData(&etc) == S_OK;
}

inline bool read_hglobal(IDataObject *object, UINT format, std::vector<uint8_t> &out) {
	FORMATETC etc{ CLIPFORMAT(format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
	STGMEDIUM medium{};
	if (object->GetData(&etc, &medium) != S_OK) return false;
	struct MediumScope {
		STGMEDIUM *value;
		~MediumScope() { ReleaseStgMedium(value); }
	} medium_scope{ &medium };
	bool ok = false;
	if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal) {
		SIZE_T size = GlobalSize(medium.hGlobal);
		if (size >= 1 && size <= MAX_TEXT_BYTES * 2) {
			const auto *bytes = static_cast<const uint8_t *>(GlobalLock(medium.hGlobal));
			if (bytes) {
				struct LockScope {
					HGLOBAL value;
					~LockScope() { GlobalUnlock(value); }
				} lock_scope{ medium.hGlobal };
				out.assign(bytes, bytes + size);
				ok = true;
			}
		}
	}
	return ok;
}

// Text payloads must be NUL-terminated UTF-16, matching the clipboard adapter.
inline bool read_text(IDataObject *object, UINT format, std::u16string &out) {
	std::vector<uint8_t> bytes;
	if (!read_hglobal(object, format, bytes)) return false;
	if (bytes.size() < 2 || bytes.size() % 2) return false;
	const auto *wide = reinterpret_cast<const char16_t *>(bytes.data());
	size_t length = 0, capacity = bytes.size() / 2;
	while (length < capacity && wide[length]) ++length;
	if (length == capacity) return false;
	out.assign(wide, length);
	return true;
}

inline bool read_bytes(IDataObject *object, UINT format, std::string &out) {
	std::vector<uint8_t> bytes;
	if (!read_hglobal(object, format, bytes)) return false;
	size_t length = 0;
	while (length < bytes.size() && bytes[length]) ++length;
	out.assign(reinterpret_cast<const char *>(bytes.data()), length + (length < bytes.size() ? 1 : 0));
	return true;
}

inline bool read_files(IDataObject *object, std::u16string &out) {
	std::vector<uint8_t> bytes;
	if (!read_hglobal(object, CF_HDROP, bytes)) return false;
    std::u16string joined;
    bool valid = windows_dropfiles::visit(bytes.data(), bytes.size(), MAX_PATHS, MAX_PATH_CHARS,
        [&](const uint8_t *path, size_t length, bool wide) {
            if (!joined.empty()) joined += u'\n';
            const size_t start = joined.size();
            if (wide) {
                joined.resize(start + length);
                memcpy(joined.data() + start, path, length * sizeof(char16_t));
            } else {
                const char *ansi = reinterpret_cast<const char *>(path);
                int chars = MultiByteToWideChar(CP_ACP, 0, ansi, int(length), nullptr, 0);
                if (chars <= 0 || size_t(chars) > MAX_PATH_CHARS) return false;
                joined.resize(start + size_t(chars));
                if (MultiByteToWideChar(CP_ACP, 0, ansi, int(length),
                        reinterpret_cast<wchar_t *>(joined.data() + start), chars) != chars) return false;
            }
            return true;
        });
    if (!valid) return false;
	out = std::move(joined);
	return true;
}

// Registered formats inside the custom convention advertised by this source.
// Malformed payloads drop that one format instead of failing the drag.
inline void extract_custom(IDataObject *object, Payload &payload, bool with_data) {
	IEnumFORMATETC *enumerator = nullptr;
	if (object->EnumFormatEtc(DATADIR_GET, &enumerator) != S_OK || !enumerator) return;
	struct EnumeratorScope {
		IEnumFORMATETC *value;
		~EnumeratorScope() { value->Release(); }
	} enumerator_scope{ enumerator };
	while (payload.custom.size() < custom_format::MAX_FORMATS) {
		FORMATETC etc{};
		ULONG fetched = 0;
		if (enumerator->Next(1, &etc, &fetched) != S_OK || fetched != 1) break;
		const UINT format = etc.cfFormat;
		const bool usable = format >= 0xC000 && etc.dwAspect == DVASPECT_CONTENT && (etc.tymed & TYMED_HGLOBAL);
		if (etc.ptd) CoTaskMemFree(etc.ptd);
		if (!usable) continue;
		wchar_t buffer[custom_format::MAX_NAME_CHARS + 1]{};
		const int length = GetClipboardFormatNameW(format, buffer, int(sizeof(buffer) / sizeof(buffer[0])));
		if (length <= 0) continue;
		std::wstring name(buffer, size_t(length));
		if (!custom_format::valid_name(name)) continue;
		std::string bytes;
		if (with_data && (!read_bytes(object, format, bytes) || bytes.empty() || bytes.back() != 0)) continue;
		payload.custom.emplace_back(std::move(name), std::move(bytes));
	}
}

// Queries availability for every supported format; extracts data when requested
// (drag enter and drop). Malformed payloads drop that format instead of failing.
inline bool extract(IDataObject *object, Payload &payload, bool with_data) {
	Payload fresh{};
	fresh.has_text = query_format(object, CF_UNICODETEXT);
	UINT html = html_format(), rtf = rtf_format(), url = url_format(), url_a = url_format_a();
	fresh.has_html = html && query_format(object, html);
	fresh.has_rtf = rtf && query_format(object, rtf);
	fresh.has_url = (url && query_format(object, url)) || (url_a && query_format(object, url_a));
	fresh.has_files = query_format(object, CF_HDROP);
	extract_custom(object, fresh, with_data);
	if (with_data) {
		if (fresh.has_text && !read_text(object, CF_UNICODETEXT, fresh.text)) fresh.has_text = false;
		if (fresh.has_html && !read_bytes(object, html, fresh.html)) fresh.has_html = false;
		if (fresh.has_rtf && !read_bytes(object, rtf, fresh.rtf)) fresh.has_rtf = false;
		if (fresh.has_url) {
			if (!url || !query_format(object, url) || !read_text(object, url, fresh.url)) {
				// ANSI-only sources: convert through the ACP code page.
				std::vector<uint8_t> bytes;
				if (url_a && read_hglobal(object, url_a, bytes)) {
					size_t length = 0;
					while (length < bytes.size() && bytes[length]) ++length;
					if (length < bytes.size()) {
						int wide_length = MultiByteToWideChar(CP_ACP, 0, reinterpret_cast<const char *>(bytes.data()), int(length), nullptr, 0);
						if (wide_length > 0 && wide_length <= int(MAX_URL_CHARS)) {
							std::wstring wide(size_t(wide_length), 0);
							MultiByteToWideChar(CP_ACP, 0, reinterpret_cast<const char *>(bytes.data()), int(length), wide.data(), wide_length);
							fresh.url.assign(reinterpret_cast<const char16_t *>(wide.data()), size_t(wide_length));
						} else fresh.has_url = false;
					} else fresh.has_url = false;
				} else fresh.has_url = false;
			}
			if (fresh.has_url && fresh.url.size() > MAX_URL_CHARS) fresh.has_url = false;
		}
		if (fresh.has_files && !read_files(object, fresh.files)) fresh.has_files = false;
	}
	if (!fresh.has_text && !fresh.has_html && !fresh.has_rtf && !fresh.has_url && !fresh.has_files && fresh.custom.empty()) return false;
	if (fresh.has_text) fresh.mimes += "text/plain\n";
	if (fresh.has_html) fresh.mimes += "text/html\n";
	if (fresh.has_rtf) fresh.mimes += "text/rtf\n";
	if (fresh.has_url) fresh.mimes += "text/uri-list\n";
	if (fresh.has_files) fresh.mimes += "application/x-java-file-list\n";
	for (const auto &entry : fresh.custom) {
		// Custom names are validated ASCII, so narrowing cannot lose content.
		for (wchar_t letter : entry.first) fresh.mimes.push_back(static_cast<char>(letter));
		fresh.mimes += '\n';
	}
	if (!fresh.mimes.empty()) fresh.mimes.pop_back();
	payload = std::move(fresh);
	return true;
}

class DataObject : public IDataObject {
	std::atomic<ULONG> refs{ 1 };
	SourceData data;
	// Formats the system stores on the object during the drag. The shell drag
	// image helper writes its rendered DragImageBits/context through SetData;
	// without them InitializeFromBitmap fails and no drag preview is shown.
	std::vector<std::pair<FORMATETC, STGMEDIUM>> extras;

	static HRESULT store_bytes(const void *bytes, size_t size, STGMEDIUM *medium) {
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

	const STGMEDIUM *find_extra(UINT format) const {
		for (const auto &entry : extras)
			if (entry.first.cfFormat == format) return &entry.second;
		return nullptr;
	}

	bool offers(UINT format) const {
		if (format == CF_UNICODETEXT && !data.text.empty()) return true;
		if (format == html_format() && !data.html.empty()) return true;
		if (format == rtf_format() && !data.rtf.empty()) return true;
		if (format == url_format() && !data.url.empty()) return true;
		if (format == CF_HDROP && !data.files.empty()) return true;
		for (const auto &entry : data.custom)
			if (format == custom_format::format_for(entry.first)) return true;
		return find_extra(format) != nullptr;
	}

	HRESULT get(UINT format, STGMEDIUM *medium) const {
		const STGMEDIUM *extra = find_extra(format);
		if (extra && extra->tymed == TYMED_HGLOBAL && extra->hGlobal) {
			SIZE_T size = GlobalSize(extra->hGlobal);
			const void *bytes = size ? GlobalLock(extra->hGlobal) : nullptr;
			if (!bytes) return E_UNEXPECTED;
			HRESULT result = store_bytes(bytes, size, medium);
			GlobalUnlock(extra->hGlobal);
			return result;
		}
		if (format == CF_UNICODETEXT && !data.text.empty())
			return store_bytes(data.text.c_str(), (data.text.size() + 1) * sizeof(char16_t), medium);
		UINT html = html_format(), rtf = rtf_format(), url = url_format();
		if (format == html && !data.html.empty()) return store_bytes(data.html.data(), data.html.size(), medium);
		if (format == rtf && !data.rtf.empty()) return store_bytes(data.rtf.data(), data.rtf.size(), medium);
		if (format == url && !data.url.empty())
			return store_bytes(data.url.c_str(), (data.url.size() + 1) * sizeof(char16_t), medium);
		if (format == CF_HDROP && !data.files.empty()) {
			size_t chars = 1;
			for (const auto &file : data.files) chars += file.size() + 1;
			std::vector<uint8_t> bytes(sizeof(DROPFILES) + chars * sizeof(wchar_t), 0);
			DROPFILES header{};
			header.pFiles = sizeof(DROPFILES);
			header.fWide = TRUE;
			memcpy(bytes.data(), &header, sizeof(header));
			wchar_t *cursor = reinterpret_cast<wchar_t *>(bytes.data() + sizeof(DROPFILES));
			for (const auto &file : data.files) {
				memcpy(cursor, file.c_str(), file.size() * sizeof(wchar_t));
				cursor += file.size() + 1;
			}
			return store_bytes(bytes.data(), bytes.size(), medium);
		}
		for (const auto &entry : data.custom) {
			if (format == custom_format::format_for(entry.first))
				return store_bytes(entry.second.data(), entry.second.size(), medium);
		}
		return DV_E_FORMATETC;
	}

	void formats(std::vector<FORMATETC> &out) const {
		auto add = [&](UINT format) {
            for (const auto &entry : out) if (entry.cfFormat == format) return;
            out.push_back(FORMATETC{ CLIPFORMAT(format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL });
        };
		if (!data.text.empty()) add(CF_UNICODETEXT);
		if (!data.html.empty()) add(html_format());
		if (!data.rtf.empty()) add(rtf_format());
		if (!data.url.empty()) add(url_format());
		if (!data.files.empty()) add(CF_HDROP);
		for (const auto &entry : data.custom) {
			UINT format = custom_format::format_for(entry.first);
			if (format) add(format);
		}
		for (const auto &entry : extras) add(entry.first.cfFormat);
	}

public:
	explicit DataObject(SourceData &&source) : data(std::move(source)) {}
	~DataObject() {
		for (auto &entry : extras) ReleaseStgMedium(&entry.second);
	}

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override {
		if (!object) return E_POINTER;
		if (iid == IID_IUnknown || iid == IID_IDataObject) {
			*object = static_cast<IDataObject *>(this);
			AddRef();
			return S_OK;
		}
		*object = nullptr;
		return E_NOINTERFACE;
	}
	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
	ULONG STDMETHODCALLTYPE Release() override {
		ULONG count = --refs;
		if (!count) delete this;
		return count;
	}
	HRESULT STDMETHODCALLTYPE GetData(FORMATETC *etc, STGMEDIUM *medium) override {
		if (!etc || !medium) return E_POINTER;
		if (etc->dwAspect != DVASPECT_CONTENT || !(etc->tymed & TYMED_HGLOBAL) || etc->lindex != -1) return DV_E_FORMATETC;
		*medium = {};
		try {
			return get(etc->cfFormat, medium);
		} catch (const std::bad_alloc &) {
			return E_OUTOFMEMORY;
		}
	}
	HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC *, STGMEDIUM *) override { return E_NOTIMPL; }
	HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC *etc) override {
		if (!etc || etc->dwAspect != DVASPECT_CONTENT || !(etc->tymed & TYMED_HGLOBAL) || etc->lindex != -1) return DV_E_FORMATETC;
		// Capability checks must not serialize/copy payloads or allocate media.
		return offers(etc->cfFormat) ? S_OK : DV_E_FORMATETC;
	}
	HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC *input, FORMATETC *out) override {
        if (!out) return E_POINTER;
        if (!input) { *out = {}; return E_POINTER; }
        *out = *input;
        out->ptd = nullptr; // No device-specific rendering; no borrowed pointer escapes.
        return DATA_S_SAMEFORMATETC;
    }
    HRESULT STDMETHODCALLTYPE SetData(FORMATETC *etc, STGMEDIUM *medium, BOOL release) override {
		// The shell calls this to attach the prepared drag image (DragImageBits,
		// DragContext, DragSourceHelperFlags) during InitializeFromBitmap. Only
		// HGLOBAL storage is accepted; TYMED_FILE would make this object own a
		// deletable file, which the drag never needs.
		if (!etc || !medium) return E_POINTER;
		if (etc->lindex != -1) return DV_E_LINDEX;
		if (etc->dwAspect != DVASPECT_CONTENT || (etc->tymed & TYMED_HGLOBAL) == 0
				|| medium->tymed != TYMED_HGLOBAL || !medium->hGlobal) return E_NOTIMPL;
		STGMEDIUM owned{};
		if (release) {
			owned = *medium;
		} else {
			SIZE_T size = GlobalSize(medium->hGlobal);
			HGLOBAL copy = size ? GlobalAlloc(GMEM_MOVEABLE, size) : nullptr;
			void *destination = copy ? GlobalLock(copy) : nullptr;
			void *source = size ? GlobalLock(medium->hGlobal) : nullptr;
			if (!destination || !source) {
				if (destination) GlobalUnlock(copy);
				if (source) GlobalUnlock(medium->hGlobal);
				if (copy) GlobalFree(copy);
				return E_UNEXPECTED;
			}
			memcpy(destination, source, size);
			GlobalUnlock(copy);
			GlobalUnlock(medium->hGlobal);
			owned.tymed = TYMED_HGLOBAL;
			owned.hGlobal = copy;
			owned.pUnkForRelease = nullptr;
		}
		for (auto &entry : extras) {
			if (entry.first.cfFormat == etc->cfFormat) {
                // Release can invoke external COM code, which may reenter and
                // grow extras. Publish first and never retain an entry reference
                // across that callback.
                STGMEDIUM previous = entry.second;
                entry.second = owned;
                ReleaseStgMedium(&previous);
				return S_OK;
			}
		}
		try {
			extras.emplace_back(FORMATETC{ etc->cfFormat, nullptr, etc->dwAspect, etc->lindex, TYMED_HGLOBAL }, owned);
		} catch (const std::bad_alloc &) {
			// Ownership transfers only on success. A rejected fRelease=TRUE
			// medium still belongs to the caller; only our private copy is ours.
			if (!release) ReleaseStgMedium(&owned);
			return E_OUTOFMEMORY;
		}
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction, IEnumFORMATETC **enumerator) override;
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

class FormatEnumerator : public IEnumFORMATETC {
	std::atomic<ULONG> refs{ 1 };
	std::vector<FORMATETC> list;
	size_t index = 0;
public:
	explicit FormatEnumerator(std::vector<FORMATETC> &&formats) : list(std::move(formats)) {}
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override {
		if (!object) return E_POINTER;
		if (iid == IID_IUnknown || iid == IID_IEnumFORMATETC) {
			*object = static_cast<IEnumFORMATETC *>(this);
			AddRef();
			return S_OK;
		}
		*object = nullptr;
		return E_NOINTERFACE;
	}
	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
	ULONG STDMETHODCALLTYPE Release() override {
		ULONG count = --refs;
		if (!count) delete this;
		return count;
	}
	HRESULT STDMETHODCALLTYPE Next(ULONG count, FORMATETC *out, ULONG *fetched) override {
		if (fetched) *fetched = 0;
		if (!out || (count != 1 && !fetched)) return E_POINTER;
		ULONG produced = 0;
		while (produced < count && index < list.size()) out[produced++] = list[index++];
		if (fetched) *fetched = produced;
		return produced == count ? S_OK : S_FALSE;
	}
	HRESULT STDMETHODCALLTYPE Skip(ULONG count) override {
		if (index + count > list.size()) { index = list.size(); return S_FALSE; }
		index += count;
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE Reset() override { index = 0; return S_OK; }
	HRESULT STDMETHODCALLTYPE Clone(IEnumFORMATETC **clone) override {
		if (!clone) return E_POINTER;
		*clone = nullptr;
		try {
			auto *copy = new (std::nothrow) FormatEnumerator(std::vector<FORMATETC>(list));
			if (!copy) return E_OUTOFMEMORY;
			copy->index = index;
			*clone = copy;
			return S_OK;
		} catch (const std::bad_alloc &) {
			return E_OUTOFMEMORY;
		}
	}
};

inline HRESULT DataObject::EnumFormatEtc(DWORD direction, IEnumFORMATETC **enumerator) {
	if (!enumerator) return E_POINTER;
	*enumerator = nullptr;
	if (direction != DATADIR_GET) return E_NOTIMPL;
	try {
		std::vector<FORMATETC> list;
		formats(list);
		auto *created = new (std::nothrow) FormatEnumerator(std::move(list));
		if (!created) return E_OUTOFMEMORY;
		*enumerator = created;
		return S_OK;
	} catch (const std::bad_alloc &) {
		return E_OUTOFMEMORY;
	}
}

class DropSource : public IDropSource {
	std::atomic<ULONG> refs{ 1 };
public:
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override {
		if (!object) return E_POINTER;
		if (iid == IID_IUnknown || iid == IID_IDropSource) {
			*object = static_cast<IDropSource *>(this);
			AddRef();
			return S_OK;
		}
		*object = nullptr;
		return E_NOINTERFACE;
	}
	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
	ULONG STDMETHODCALLTYPE Release() override {
		ULONG count = --refs;
		if (!count) delete this;
		return count;
	}
	HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape, DWORD keys) override {
		if (escape) return DRAGDROP_S_CANCEL;
		if (!(keys & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON))) return DRAGDROP_S_DROP;
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }
};

// Registers the Dragboard drag view with the shell drag-image helper, mirroring
// the Win Glass setDragImage path: build a 32bpp bitmap from the BGRA payload,
// then let IDragSourceHelper store its DragImageBits on the data object so the
// system renders the preview for the whole OLE gesture. Failure is not fatal —
// pictured drag is a secondary feature, and the drag itself must proceed.
inline void apply_drag_image(IDataObject *object, const SourceData::DragImage &image) {
	if (!object || !image.present()) return;
	HBITMAP bitmap = CreateBitmap(int(image.width), int(image.height), 1, 32, image.bgra.data());
	if (!bitmap) return;
	SHDRAGIMAGE info{};
	info.sizeDragImage.cx = LONG(image.width);
	info.sizeDragImage.cy = LONG(image.height);
	info.ptOffset.x = image.offset_x == INT32_MIN ? LONG(image.width / 2) : image.offset_x;
	info.ptOffset.y = image.offset_y == INT32_MIN ? LONG(image.height / 2) : image.offset_y;
	info.crColorKey = 0xFFFFFFFF;
	info.hbmpDragImage = bitmap;
	IDragSourceHelper *helper = nullptr;
	HRESULT result = CoCreateInstance(CLSID_DragDropHelper, nullptr, CLSCTX_ALL, IID_IDragSourceHelper,
			reinterpret_cast<void **>(&helper));
	if (SUCCEEDED(result) && helper) {
		helper->InitializeFromBitmap(&info, object);
		helper->Release();
	}
	// InitializeFromBitmap copies the bits into its own DragImageBits storage.
	DeleteObject(bitmap);
}

// Handles drag-in events for one host window through the DisplayServerWindows
// drag delegate. Runs on the Godot main thread inside OLE callbacks; ownership
// and per-window lifetime are managed by the JavaFX host.
struct TargetHandler {
	int64_t id = 0;
	Upcall upcall;
	Payload enter_payload;

	jint dispatch(jint kind, POINTL point, DWORD effects, DWORD key_state, const Payload *payload) {
		return call_target(upcall, kind, id, point.x, point.y, jint(effects), jint(key_state),
				payload ? payload->mimes : std::string(),
				payload && payload->has_text ? &payload->text : nullptr,
				payload && payload->has_html ? &payload->html : nullptr,
				payload && payload->has_rtf ? &payload->rtf : nullptr,
				payload && payload->has_url ? &payload->url : nullptr,
				payload && payload->has_files ? &payload->files : nullptr,
				payload && !payload->custom.empty() ? &payload->custom : nullptr);
	}

	bool handle(int kind, IDataObject *object, DWORD key_state, POINTL point, DWORD *effect) {
		try { return handle_impl(kind, object, key_state, point, effect); }
		catch (const std::bad_alloc &) { }
		catch (const std::length_error &) { }
		// Never unwind an allocation failure through the Windows COM callback.
		// Consume the rejected drag instead of retrying through Godot's fallback.
		if (effect) *effect = DROPEFFECT_NONE;
		enter_payload = Payload{};
		std::fputs("JavaFX OLE target rejected drag: allocation failed\n", stderr);
		return true;
	}

private:
	bool handle_impl(int kind, IDataObject *object, DWORD key_state, POINTL point, DWORD *effect) {
		if (!upcall) return false;
		switch (kind) {
			case 1: { // DragEnter
				if (!effect || !object) return false;
				DWORD allowed = *effect;
				*effect = DROPEFFECT_NONE;
				// Unsupported payloads fall through to Godot's own file handling.
				if (!extract(object, enter_payload, true)) return false;
				jint action = dispatch(1, point, allowed, key_state, &enter_payload);
				*effect = DWORD(action) & allowed;
				return true;
			}
			case 2: { // DragOver
				if (!effect || enter_payload.mimes.empty()) return false;
				DWORD allowed = *effect;
				// Availability was extracted on enter; over events only carry the MIME list.
				jint action = dispatch(2, point, allowed, key_state, &enter_payload);
				*effect = DWORD(action) & allowed;
				return true;
			}
			case 3: { // DragLeave
				bool ours = !enter_payload.mimes.empty();
				enter_payload = Payload{};
				if (ours) {
					POINTL origin{};
					dispatch(3, origin, 0, 0, nullptr);
				}
				return true;
			}
			case 4: { // Drop
				if (!effect || !object) return false;
				DWORD allowed = *effect;
				*effect = DROPEFFECT_NONE;
				Payload payload;
				bool extracted = extract(object, payload, true);
				if (extracted) {
					jint action = dispatch(4, point, allowed, key_state, &payload);
					*effect = DWORD(action) & allowed;
				}
				enter_payload = Payload{};
				return extracted;
			}
		}
		return false;
	}
};

} // namespace godot_javafx::windows_dnd
