// Standalone check for the OLE drag-view registration path: the shell
// drag-image helper must accept the DataObject (SetData support) and store
// DragImageBits mirroring the published dimensions. This covers the native
// mechanism without the cross-process Robot fixture; the OS-rendered preview
// itself stays with the external drag/drop fixture.
#include "windows_dnd.h"
#include <iostream>
#include <stdexcept>

#include <cstdlib>
#include <new>

// Deterministic allocation failure inside STL-backed COM operations only.
static int allocations_before_failure = -1;
void *operator new(size_t size) {
	if (allocations_before_failure == 0) { allocations_before_failure = -1; throw std::bad_alloc(); }
	if (allocations_before_failure > 0) --allocations_before_failure;
	if (void *memory = std::malloc(size ? size : 1)) return memory;
	throw std::bad_alloc();
}
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, size_t) noexcept { std::free(memory); }

using namespace godot_javafx;

static void require(bool condition, const char *message) {
	if (!condition) { std::cerr << message << std::endl; throw std::runtime_error(message); }
}

#include "dnd_jni_failure_test.h"

static STGMEDIUM global_medium(const void *bytes, size_t size) {
	HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE, size);
	if (!block) throw std::runtime_error("GlobalAlloc failed");
	void *locked = GlobalLock(block);
	if (!locked) { GlobalFree(block); throw std::runtime_error("GlobalLock failed"); }
	memcpy(locked, bytes, size);
	GlobalUnlock(block);
	STGMEDIUM medium{};
	medium.tymed = TYMED_HGLOBAL;
	medium.hGlobal = block;
	return medium;
}

class ReleaseObserver : public IUnknown {
public:
	unsigned releases = 0;
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, void **out) override {
		if (!out) return E_POINTER;
		*out = nullptr; return E_NOINTERFACE;
	}
	ULONG STDMETHODCALLTYPE AddRef() override { return 1; }
	ULONG STDMETHODCALLTYPE Release() override { ++releases; return 1; }
};

class ReentrantReleaseObserver : public ReleaseObserver {
public:
	IDataObject *object = nullptr;
	bool saw_replacement = false, grew = false;
	ULONG STDMETHODCALLTYPE Release() override {
		++releases;
		try {
			FORMATETC format{ CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
			STGMEDIUM read{};
			if (object->GetData(&format, &read) == S_OK) {
				const char16_t expected[] = u"new";
				void *bytes = GlobalLock(read.hGlobal);
				saw_replacement = bytes && GlobalSize(read.hGlobal) >= sizeof(expected)
						&& memcmp(bytes, expected, sizeof(expected)) == 0;
				if (bytes) GlobalUnlock(read.hGlobal);
				ReleaseStgMedium(&read);
			}
			for (unsigned i = 0; i < 64; ++i) {
				format.cfFormat = CLIPFORMAT(CF_PRIVATEFIRST + i);
				STGMEDIUM added = global_medium(&i, sizeof(i));
				if (object->SetData(&format, &added, TRUE) != S_OK) { ReleaseStgMedium(&added); return 1; }
			}
			grew = true;
		} catch (...) { grew = false; }
		return 1;
	}
};

static void check_data_object_contracts() {
	{
		auto *reentrant = new windows_dnd::DataObject(windows_dnd::SourceData{});
		ReentrantReleaseObserver owner; owner.object = reentrant;
		FORMATETC format{ CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
		const char16_t old_value[] = u"old", new_value[] = u"new";
		STGMEDIUM old = global_medium(old_value, sizeof(old_value)); old.pUnkForRelease = &owner;
		require(reentrant->SetData(&format, &old, TRUE) == S_OK, "Reentrant setup failed");
		STGMEDIUM replacement = global_medium(new_value, sizeof(new_value));
		require(reentrant->SetData(&format, &replacement, FALSE) == S_OK, "Reentrant replacement failed");
		ReleaseStgMedium(&replacement);
		reentrant->Release();
		GlobalFree(old.hGlobal); // The observer, not ReleaseStgMedium, owns this block.
		require(owner.releases == 1 && owner.saw_replacement && owner.grew,
				"Release callback saw stale data or replacement failed after vector growth");
	}
	{
		windows_dnd::SourceData source;
		source.text = u"old";
		auto *replaced = new windows_dnd::DataObject(std::move(source));
		FORMATETC format{ CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
		const char16_t value[] = u"new";
		STGMEDIUM written = global_medium(value, sizeof(value));
		require(replaced->SetData(&format, &written, TRUE) == S_OK, "Built-in replacement rejected");
		STGMEDIUM read{};
		require(replaced->GetData(&format, &read) == S_OK, "Replacement read failed");
		void *bytes = GlobalLock(read.hGlobal);
		bool correct = bytes && GlobalSize(read.hGlobal) >= sizeof(value) && memcmp(bytes, value, sizeof(value)) == 0;
		if (bytes) GlobalUnlock(read.hGlobal);
		ReleaseStgMedium(&read);
		IEnumFORMATETC *enumerator = nullptr;
		require(replaced->EnumFormatEtc(DATADIR_GET, &enumerator) == S_OK, "Replacement enumeration failed");
		FORMATETC each{}; ULONG fetched = 0; unsigned occurrences = 0;
		while (enumerator->Next(1, &each, &fetched) == S_OK) if (each.cfFormat == CF_UNICODETEXT) ++occurrences;
		enumerator->Release(); replaced->Release();
		require(correct, "GetData returned original data after successful SetData");
		require(occurrences == 1, "Replacement format enumerated more than once");
	}
	windows_dnd::SourceData data;
	data.files.push_back(u"C:\\probe.txt");
	data.custom.emplace_back(L"application/x-godot-custom-probe", std::string("value\0", 6));
	auto *object = new windows_dnd::DataObject(std::move(data));
	FORMATETC files{ CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
	allocations_before_failure = 0;
	HRESULT queried = object->QueryGetData(&files);
	bool untouched = allocations_before_failure == 0;
	allocations_before_failure = -1;
	require(queried == S_OK && untouched, "QueryGetData allocated payload storage");
	FORMATETC custom{ CLIPFORMAT(custom_format::format_for(L"application/x-godot-custom-probe")), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
	allocations_before_failure = 0;
	queried = object->QueryGetData(&custom);
	untouched = allocations_before_failure == 0;
	allocations_before_failure = -1;
	require(queried == S_OK && untouched, "Custom format query allocated temporary strings");
	STGMEDIUM read{};
	allocations_before_failure = 0;
	HRESULT got = object->GetData(&files, &read);
	allocations_before_failure = -1;
	require(got == E_OUTOFMEMORY && read.tymed == TYMED_NULL, "GetData did not contain allocation failure");

	ReleaseObserver owner;
	const char payload[] = "owned by caller until success";
	STGMEDIUM medium = global_medium(payload, sizeof(payload));
	medium.pUnkForRelease = &owner;
	FORMATETC extra{ CLIPFORMAT(RegisterClipboardFormatW(L"GodotJfxOwnershipProbe")), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
	allocations_before_failure = 0;
	HRESULT stored = object->SetData(&extra, &medium, TRUE);
	allocations_before_failure = -1;
	require(stored == E_OUTOFMEMORY && owner.releases == 0, "Failed SetData consumed caller ownership");
	require(object->QueryGetData(&extra) == DV_E_FORMATETC, "Failed SetData retained the payload");
	require(object->SetData(&extra, &medium, TRUE) == S_OK, "SetData retry failed");
	STGMEDIUM replacement = global_medium(payload, sizeof(payload));
	require(object->SetData(&extra, &replacement, FALSE) == S_OK, "SetData copy failed");
	require(owner.releases == 1, "Replacing a transferred medium did not release it once");
	GlobalFree(medium.hGlobal); // observer deliberately does not free the storage
	ReleaseStgMedium(&replacement); // FALSE left caller ownership intact
	require(object->GetData(&extra, &read) == S_OK, "Copied medium died with caller storage");
	ReleaseStgMedium(&read);

	IEnumFORMATETC *enumerator = reinterpret_cast<IEnumFORMATETC *>(object); // deliberately non-null sentinel, overwritten below
	allocations_before_failure = 0;
	HRESULT listed = object->EnumFormatEtc(DATADIR_GET, &enumerator);
	allocations_before_failure = -1;
	require(listed == E_OUTOFMEMORY && !enumerator, "EnumFormatEtc allocation failure escaped or left output");
	require(object->EnumFormatEtc(DATADIR_GET, &enumerator) == S_OK, "EnumFormatEtc retry failed");
	IEnumFORMATETC *clone = enumerator;
	allocations_before_failure = 1; // object allocation succeeds; vector copy throws
	HRESULT cloned = enumerator->Clone(&clone);
	allocations_before_failure = -1;
	require(cloned == E_OUTOFMEMORY && !clone, "Clone allocation failure escaped or left output");
	FORMATETC items[2]{};
	require(enumerator->Next(2, items, nullptr) == E_POINTER, "Next accepted missing fetched count");
	ULONG fetched = 0;
	require(enumerator->Next(1, items, &fetched) == S_OK && fetched == 1 && items[0].cfFormat == CF_HDROP,
			"Rejected Next advanced the enumerator");
	enumerator->Release();
	object->Release();
	require(owner.releases == 1, "Transferred medium was released twice");
}

#include "dnd_output_contracts.h"

static void check_extraction_failure_cleanup() {
	class ReadObject : public windows_dnd::DataObject {
	public:
		STGMEDIUM medium{};
		IEnumFORMATETC *enumerator = nullptr;
		bool fail_enumeration = false;
		ReadObject() : DataObject(windows_dnd::SourceData{}) {}
		HRESULT STDMETHODCALLTYPE GetData(FORMATETC *, STGMEDIUM *out) override { *out = medium; return S_OK; }
		HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD, IEnumFORMATETC **out) override {
			if (fail_enumeration) throw std::bad_alloc();
			*out = enumerator; return S_OK;
		}
	} object;
	ReleaseObserver owner;
	const unsigned payload = 42;
	object.medium = global_medium(&payload, sizeof(payload));
	object.medium.pUnkForRelease = &owner;
	std::vector<uint8_t> bytes;
	bool failed = false;
	allocations_before_failure = 0;
	try { windows_dnd::read_hglobal(&object, CF_UNICODETEXT, bytes); }
	catch (const std::bad_alloc &) { failed = true; }
	allocations_before_failure = -1;
	bool unlocked = (GlobalFlags(object.medium.hGlobal) & GMEM_LOCKCOUNT) == 0;
	// The observer deliberately retains ownership so failure remains inspectable.
	if (!unlocked) GlobalUnlock(object.medium.hGlobal);
	GlobalFree(object.medium.hGlobal);
	require(failed && unlocked && owner.releases == 1, "Extraction allocation failure leaked lock or medium");

	class EnumObserver : public windows_dnd::FormatEnumerator {
	public:
		unsigned releases = 0;
		explicit EnumObserver(UINT format) : FormatEnumerator({FORMATETC{CLIPFORMAT(format), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL}}) {}
		ULONG STDMETHODCALLTYPE Release() override { ++releases; return 1; }
	} enumerator(RegisterClipboardFormatW(L"application/x-godot-custom-extraction-failure"));
	object.enumerator = &enumerator;
	windows_dnd::Payload extracted;
	failed = false;
	allocations_before_failure = 0; // First std::wstring name allocation after Next.
	try { windows_dnd::extract_custom(&object, extracted, false); }
	catch (const std::bad_alloc &) { failed = true; }
	allocations_before_failure = -1;
	require(failed && enumerator.releases == 1, "Extraction allocation failure leaked enumerator");
	// Opaque sentinels only satisfy the enabled-upcall gate. Extraction always
	// throws before dispatch; no JVM or JNI function is called in this test.
	windows_dnd::TargetHandler handler;
	JavaVM vm{};
	windows_dnd::UpcallState upcall_state;
	upcall_state.publish(&vm, reinterpret_cast<jclass>(&object), reinterpret_cast<jmethodID>(&object));
	handler.upcall = {&upcall_state};
	object.fail_enumeration = true;
	for (int kind : {1, 4}) {
		handler.enter_payload.mimes = "stale";
		DWORD effect = DROPEFFECT_COPY;
		require(handler.handle(kind, &object, 0, POINTL{}, &effect), "Failed drag fell through to fallback");
		require(effect == DROPEFFECT_NONE && handler.enter_payload.mimes.empty(), "Failed drag retained effect or payload");
	}
	std::cout << "DND_EXTRACTION_FAILURE_CLEANUP_PASS" << std::endl;
}

int main() {
	HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	require(SUCCEEDED(initialized), "CoInitializeEx failed");
	dnd_jni_test::check();
	check_data_object_contracts();
	check_extraction_failure_cleanup();

	// Same payload shape the FX bridge produces: 8x6 BGRA with offset (5,3).
	windows_dnd::SourceData data;
	data.text = u"drag image probe";
	data.image.width = 8;
	data.image.height = 6;
	data.image.offset_x = 5;
	data.image.offset_y = 3;
	data.image.bgra.assign(8u * 6u * 4u, 0x80);
	windows_dnd::SourceData::DragImage image = data.image;

	auto *object = new windows_dnd::DataObject(std::move(data));
	try {
		check_dnd_output_contracts(object);
		std::puts("DND_OUTPUT_CONTRACTS_PASS");
		windows_dnd::apply_drag_image(object, image);

		UINT bits = RegisterClipboardFormatW(L"DragImageBits");
		require(bits != 0, "DragImageBits format unavailable");
		FORMATETC etc{ CLIPFORMAT(bits), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
		require(object->QueryGetData(&etc) == S_OK, "DragImageBits not offered after helper registration");

		// Stored header: SIZE sizeDragImage; POINT ptOffset; COLORREF key.
		STGMEDIUM medium{};
		require(object->GetData(&etc, &medium) == S_OK, "DragImageBits GetData failed");
		require(medium.tymed == TYMED_HGLOBAL && medium.hGlobal, "DragImageBits medium is not HGLOBAL");
		SIZE_T size = GlobalSize(medium.hGlobal);
		require(size >= 20, "DragImageBits smaller than its header");
		const uint8_t *bytes = static_cast<const uint8_t *>(GlobalLock(medium.hGlobal));
		require(bytes != nullptr, "DragImageBits lock failed");
		auto read32 = [bytes](size_t offset) {
			return uint32_t(bytes[offset]) | uint32_t(bytes[offset + 1]) << 8
					| uint32_t(bytes[offset + 2]) << 16 | uint32_t(bytes[offset + 3]) << 24;
		};
		LONG stored_w = LONG(read32(0)), stored_h = LONG(read32(4));
		LONG stored_ox = LONG(read32(8)), stored_oy = LONG(read32(12));
		GlobalUnlock(medium.hGlobal);
		ReleaseStgMedium(&medium);
		require(stored_w > 0 && stored_h > 0, "stored drag image has no extent");
		std::cout << "DND_DRAG_IMAGE_STORED size=" << stored_w << "x" << stored_h
				<< " offset=" << stored_ox << "," << stored_oy << " bytes=" << size << std::endl;
		require(stored_w == 8 && stored_h == 6, "stored drag image size differs from the source");
		require(stored_ox == 5 && stored_oy == 3, "stored drag image offset differs from the source");

		// The shell also writes context formats through SetData; verify a
		// generic extra format round-trips with ownership transfer.
		UINT context = RegisterClipboardFormatW(L"DragContext");
		require(context != 0, "DragContext format unavailable");
		const char payload[] = "godot-jfx drag context";
		STGMEDIUM written = global_medium(payload, sizeof(payload));
		FORMATETC context_etc{ CLIPFORMAT(context), nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
		require(object->SetData(&context_etc, &written, TRUE) == S_OK, "SetData rejected the shell context write");
		STGMEDIUM read{};
		require(object->GetData(&context_etc, &read) == S_OK, "context GetData failed after SetData");
		bool same = false;
		if (read.tymed == TYMED_HGLOBAL && read.hGlobal && GlobalSize(read.hGlobal) >= sizeof(payload)) {
			const char *round = static_cast<const char *>(GlobalLock(read.hGlobal));
			if (round) {
				same = memcmp(round, payload, sizeof(payload)) == 0;
				GlobalUnlock(read.hGlobal);
			}
		}
		ReleaseStgMedium(&read);
		require(same, "context payload did not round-trip through SetData");

		// The enumerator must advertise the helper-stored formats too.
		IEnumFORMATETC *enumerator = nullptr;
		require(object->EnumFormatEtc(DATADIR_GET, &enumerator) == S_OK && enumerator, "EnumFormatEtc failed");
		bool listed = false;
		FORMATETC each{};
		ULONG fetched = 0;
		while (enumerator->Next(1, &each, &fetched) == S_OK && fetched == 1)
			if (each.cfFormat == bits) listed = true;
		enumerator->Release();
		require(listed, "DragImageBits missing from EnumFormatEtc");

		object->Release();
		object = nullptr;
	} catch (...) {
		if (object) object->Release();
		CoUninitialize();
		throw;
	}
	CoUninitialize();
	std::cout << "DND_DRAG_IMAGE_TEST_PASS" << std::endl;
	return 0;
}
