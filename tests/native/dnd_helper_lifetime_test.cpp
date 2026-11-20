// Exercise actual helper COM classes and pre-window startup failures without physical input.
#define wmain dnd_helper_window_main
#include "dnd_helper.cpp"
#undef wmain
#include "dnd_output_contracts.h"
#include <cassert>
#include <cstdlib>
#include <new>
static int allocations_before_failure = -1;
void *operator new(size_t size) {
    if (allocations_before_failure == 0) { allocations_before_failure = -1; throw std::bad_alloc(); }
    if (allocations_before_failure > 0) --allocations_before_failure;
    if (void *memory = std::malloc(size ? size : 1)) return memory;
    throw std::bad_alloc();
}
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, size_t) noexcept { std::free(memory); }

static void enumeration_contracts() {
    FORMATETC first{CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    FORMATETC second{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    auto *enumerator = new HelperFormatEnumerator({first, second});
    FORMATETC out[2]{};
    ULONG fetched = 99;
    assert(enumerator->Next(2, out, nullptr) == E_POINTER);
    assert(enumerator->Next(1, nullptr, &fetched) == E_POINTER && fetched == 0);
    assert(enumerator->Next(1, out, nullptr) == S_OK && out[0].cfFormat == first.cfFormat);
    for (int point = 0; point < 2; ++point) {
        IEnumFORMATETC *copy = reinterpret_cast<IEnumFORMATETC *>(1);
        allocations_before_failure = point;
        HRESULT result = enumerator->Clone(&copy);
        allocations_before_failure = -1;
        assert(result == E_OUTOFMEMORY && copy == nullptr);
    }
    IEnumFORMATETC *copy = nullptr;
    assert(enumerator->Clone(&copy) == S_OK);
    assert(copy->Next(1, out, &fetched) == S_OK && fetched == 1 && out[0].cfFormat == second.cfFormat);
    assert(copy->Release() == 0);
    assert(enumerator->Skip(1) == S_OK); // Exact end is a successful skip.
    assert(enumerator->Skip(0) == S_OK);
    assert(enumerator->Skip(0xffffffffUL) == S_FALSE);
    assert(enumerator->Next(1, out, &fetched) == S_FALSE && fetched == 0);
    assert(enumerator->Reset() == S_OK);
    assert(enumerator->Next(2, out, &fetched) == S_OK && fetched == 2);
    assert(enumerator->Release() == 0);
    auto *data = new HelperDataObject(L"text", L"url", {}, "custom");
    bool reached_success = false;
    for (int point = 0; point < 10; ++point) {
        IEnumFORMATETC *formats = reinterpret_cast<IEnumFORMATETC *>(1);
        allocations_before_failure = point;
        HRESULT result = data->EnumFormatEtc(DATADIR_GET, &formats);
        allocations_before_failure = -1;
        if (result == S_OK) {
            assert(formats != nullptr && formats->Release() == 0);
            reached_success = true; break;
        }
        assert(result == E_OUTOFMEMORY && formats == nullptr);
    }
    assert(reached_success && data->Release() == 0);
    std::puts("DND_HELPER_ENUMERATION_PASS");
}


template<class T> static void release_all(T *object) {
    assert(object->AddRef() == 2);
    IUnknown *alias = nullptr;
    assert(object->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&alias)) == S_OK);
    assert(alias != nullptr);
    assert(alias->Release() == 2);
    assert(object->Release() == 1);
    assert(object->Release() == 0);
}
class MediumTracker final : public IUnknown {
public:
    HGLOBAL block = nullptr;
    unsigned releases = 0;
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, void **out) override { if (out) *out=nullptr; return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override { return 2; }
    ULONG STDMETHODCALLTYPE Release() override {
        assert(block != nullptr && (GlobalFlags(block) & GMEM_LOCKCOUNT) == 0);
        assert(GlobalFree(block) == nullptr);
        block = nullptr; ++releases; return 1;
    }
};
class ReadFixture final : public HelperDataObject {
public:
    MediumTracker owner;
    bool terminated = true;
    bool custom = false;
    UINT custom_format = RegisterClipboardFormatW(CUSTOM_FORMAT_NAME);
    ReadFixture() : HelperDataObject(L"",L"",{},"") {}
    HRESULT STDMETHODCALLTYPE GetData(FORMATETC *format, STGMEDIUM *medium) override {
        *medium = {};
        if (format->cfFormat != (custom ? custom_format : CF_UNICODETEXT)) return DV_E_FORMATETC;
        assert(owner.block == nullptr);
        owner.block = GlobalAlloc(GMEM_MOVEABLE,512);
        assert(owner.block);
        size_t size = GlobalSize(owner.block);
        auto *data = static_cast<unsigned char *>(GlobalLock(owner.block));
        assert(data);
        memset(data,0x41,size); // Fill the full allocated extent: no accidental terminator.
        if (terminated) memset(data+size-(custom?1:2),0,custom?1:2);
        GlobalUnlock(owner.block);
        medium->tymed=TYMED_HGLOBAL; medium->hGlobal=owner.block; medium->pUnkForRelease=&owner;
        return S_OK;
    }
};
static void read_contracts() {
    HelperDropTarget target(nullptr);
    ReadFixture data;
    DWORD effect = DROPEFFECT_COPY;
    data.terminated = false;
    assert(target.Drop(&data,0,{},&effect) == DV_E_FORMATETC && effect == DROPEFFECT_NONE);
    assert(data.owner.releases == 1 && data.owner.block == nullptr);
    data.terminated = true;
    allocations_before_failure = 0;
    HRESULT result = target.Drop(&data,0,{},&effect);
    allocations_before_failure = -1;
    assert(result == E_OUTOFMEMORY && effect == DROPEFFECT_NONE && data.owner.releases == 2);
    effect = DROPEFFECT_COPY;
    assert(target.Drop(&data,0,{},&effect) == S_OK && effect == DROPEFFECT_COPY && data.owner.releases == 3);
    data.custom = true; data.terminated = false;
    assert(target.Drop(&data,0,{},&effect) == DV_E_FORMATETC && effect == DROPEFFECT_NONE && data.owner.releases == 4);
    data.terminated = true;
    allocations_before_failure = 0;
    result = target.Drop(&data,0,{},&effect);
    allocations_before_failure = -1;
    assert(result == E_OUTOFMEMORY && effect == DROPEFFECT_NONE && data.owner.releases == 5);
    auto custom = HelperDropTarget::read_bytes(&data,data.custom_format);
    assert(!custom.empty() && custom.front() == 'A' && data.owner.releases == 6);
    assert(target.Drop(nullptr,0,{},&effect) == E_POINTER && effect == DROPEFFECT_NONE);
    assert(target.Drop(&data,0,{},nullptr) == E_POINTER);
    std::puts("DND_HELPER_READ_PASS");
}
static void data_contracts() {
    HelperDataObject data(L"text",L"url",{L"file"},"");
    FORMATETC format{CF_HDROP,nullptr,DVASPECT_CONTENT,-1,TYMED_HGLOBAL};
    STGMEDIUM medium{};
    auto rejected = [&](HRESULT expected) {
        medium.tymed=TYMED_HGLOBAL; medium.hGlobal=reinterpret_cast<HGLOBAL>(1);
        assert(data.QueryGetData(&format) == expected);
        assert(data.GetData(&format,&medium) == expected);
        assert(medium.tymed == TYMED_NULL && medium.hGlobal == nullptr && medium.pUnkForRelease == nullptr);
    };
    format.dwAspect=DVASPECT_ICON; rejected(DV_E_DVASPECT); format.dwAspect=DVASPECT_CONTENT;
    format.tymed=TYMED_ISTREAM; rejected(DV_E_TYMED); format.tymed=TYMED_HGLOBAL;
    format.lindex=0; rejected(DV_E_LINDEX); format.lindex=-1;
    DVTARGETDEVICE device{}; format.ptd=&device; rejected(DV_E_DVTARGETDEVICE); format.ptd=nullptr;
    allocations_before_failure=0;
    assert(data.QueryGetData(&format) == S_OK && allocations_before_failure == 0);
    HRESULT result=data.GetData(&format,&medium);
    allocations_before_failure=-1;
    assert(result == E_OUTOFMEMORY && medium.tymed == TYMED_NULL && !medium.hGlobal);
    assert(data.GetData(&format,&medium) == S_OK);
    assert(DragQueryFileW(static_cast<HDROP>(medium.hGlobal),0xffffffff,nullptr,0) == 1);
    ReleaseStgMedium(&medium);
    HelperDataObject empty(L"",L"",{},"");
    assert(empty.GetData(&format,&medium) == S_OK);
    auto *bytes=static_cast<unsigned char *>(GlobalLock(medium.hGlobal));
    assert(bytes && GlobalSize(medium.hGlobal) >= sizeof(DROPFILES)+2*sizeof(wchar_t));
    const auto *names=reinterpret_cast<const wchar_t *>(bytes+sizeof(DROPFILES));
    assert(names[0] == 0 && names[1] == 0);
    GlobalUnlock(medium.hGlobal); ReleaseStgMedium(&medium);
    medium.tymed=TYMED_HGLOBAL; medium.hGlobal=reinterpret_cast<HGLOBAL>(1);
    assert(data.GetData(nullptr,&medium) == E_POINTER && medium.tymed == TYMED_NULL && !medium.hGlobal);
    assert(data.GetData(&format,nullptr) == E_POINTER);
    std::puts("DND_HELPER_DATA_PASS");
}
class NoTextFixture final : public HelperDataObject {
public:
    NoTextFixture() : HelperDataObject(L"",L"",{},"") {}
    HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC *) override { return DV_E_FORMATETC; }
};
static void effect_contracts() {
    HelperDropTarget target(nullptr);
    HelperDataObject text(L"payload",L"url",{},"");
    for (DWORD allowed : {DWORD(DROPEFFECT_NONE), DWORD(DROPEFFECT_MOVE), DWORD(DROPEFFECT_LINK), DWORD(DROPEFFECT_COPY | DROPEFFECT_MOVE)}) {
        DWORD effect = allowed;
        assert(target.DragEnter(&text,0,{},&effect) == S_OK && effect == (allowed & DROPEFFECT_COPY));
        effect = allowed;
        assert(target.DragOver(0,{},&effect) == S_OK && effect == (allowed & DROPEFFECT_COPY));
        effect = allowed;
        assert(target.Drop(&text,0,{},&effect) == S_OK && effect == (allowed & DROPEFFECT_COPY));
        effect = DROPEFFECT_COPY;
        assert(target.DragOver(0,{},&effect) == S_OK && effect == DROPEFFECT_NONE);
    }
    NoTextFixture missing;
    DWORD effect = DROPEFFECT_COPY;
    assert(target.DragEnter(&missing,0,{},&effect) == S_OK && effect == DROPEFFECT_NONE);
    effect = DROPEFFECT_COPY;
    assert(target.DragOver(0,{},&effect) == S_OK && effect == DROPEFFECT_NONE);
    effect = DROPEFFECT_COPY;
    assert(target.DragEnter(&text,0,{},&effect) == S_OK && effect == DROPEFFECT_COPY);
    assert(target.DragLeave() == S_OK);
    effect = DROPEFFECT_COPY;
    assert(target.DragOver(0,{},&effect) == S_OK && effect == DROPEFFECT_NONE);
    assert(target.DragEnter(nullptr,0,{},&effect) == E_POINTER && effect == DROPEFFECT_NONE);
    assert(target.DragEnter(&text,0,{},nullptr) == E_POINTER);
    assert(target.DragOver(0,{},nullptr) == E_POINTER);
    std::puts("DND_HELPER_EFFECT_PASS");
}
class FileFixture final : public HelperDataObject {
public:
    MediumTracker owner;
    std::vector<unsigned char> bytes;
    HRESULT status = S_OK;
    FileFixture() : HelperDataObject(L"",L"",{},"") {}
    HRESULT STDMETHODCALLTYPE GetData(FORMATETC *format, STGMEDIUM *medium) override {
        *medium = {};
        if (format->cfFormat != CF_HDROP) return DV_E_FORMATETC;
        if (status != S_OK) return status;
        assert(!owner.block);
        owner.block=GlobalAlloc(GMEM_MOVEABLE,bytes.size());
        assert(owner.block);
        void *data=GlobalLock(owner.block); assert(data);
        // Fill allocator padding too, so missing termination cannot pass by luck.
        memset(data,0x41,GlobalSize(owner.block));
        memcpy(data,bytes.data(),bytes.size()); GlobalUnlock(owner.block);
        medium->tymed=TYMED_HGLOBAL; medium->hGlobal=owner.block; medium->pUnkForRelease=&owner;
        return S_OK;
    }
    void wide(const std::wstring &path) {
        DROPFILES header{}; header.pFiles=sizeof(header)+1; header.fWide=TRUE;
        bytes.assign(header.pFiles+(path.size()+2)*sizeof(wchar_t),0);
        memcpy(bytes.data(),&header,sizeof(header));
        memcpy(bytes.data()+header.pFiles,path.data(),path.size()*sizeof(wchar_t));
    }
};
static void file_contracts() {
    FileFixture data;
    std::wstring path=L"C:\\"+std::wstring(600,L'x');
    data.wide(path);
    auto files=HelperDropTarget::read_files(&data);
    assert(files.count == 1 && files.first == path && data.owner.releases == 1);
    allocations_before_failure=0;
    bool failed=false;
    try { HelperDropTarget::read_files(&data); } catch (const std::bad_alloc &) { failed=true; }
    allocations_before_failure=-1;
    assert(failed && data.owner.releases == 2 && !data.owner.block);
    HelperDropTarget target(nullptr);
    auto reject=[&](HRESULT expected) {
        auto releases=data.owner.releases;
        DWORD effect=DROPEFFECT_COPY;
        assert(target.Drop(&data,0,{},&effect) == expected && effect == DROPEFFECT_NONE);
        assert(data.owner.releases == releases+(data.status == S_OK ? 1 : 0));
        assert(!data.owner.block);
    };
    // No list terminator; malformed offsets; oversized single path.
    data.bytes.resize(data.bytes.size()-2); reject(DV_E_FORMATETC);
    data.wide(path);
    DROPFILES header{}; memcpy(&header,data.bytes.data(),sizeof(header));
    header.pFiles=DWORD(data.bytes.size()+1); memcpy(data.bytes.data(),&header,sizeof(header));
    reject(DV_E_FORMATETC);
    data.wide(std::wstring(32768,L'x')); reject(DV_E_FORMATETC);
    data.wide(L""); files=HelperDropTarget::read_files(&data);
    assert(files.count == 0 && files.first.empty());
    header={}; header.pFiles=sizeof(header); header.fWide=FALSE;
    const char ansi[]="C:\\first.txt\0C:\\second.txt\0";
    data.bytes.resize(sizeof(header)+sizeof(ansi));
    memcpy(data.bytes.data(),&header,sizeof(header));
    memcpy(data.bytes.data()+sizeof(header),ansi,sizeof(ansi));
    files=HelperDropTarget::read_files(&data);
    assert(files.count == 2 && files.first == L"C:\\first.txt");
    data.status=E_OUTOFMEMORY; reject(E_OUTOFMEMORY);
    data.status=E_FAIL; reject(DV_E_FORMATETC);
    data.status=DV_E_FORMATETC; files=HelperDropTarget::read_files(&data);
    assert(files.count == -1 && files.first.empty());
    std::puts("DND_HELPER_FILES_PASS");
}
static void startup_contracts() {
    WNDCLASSW wc{};
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = HELPER_CLASS;
    assert(RegisterClassW(&wc));
    wchar_t mode[]=L"target", zero[]=L"0", size[]=L"100";
    wchar_t log[]=L"agentdir/logs/dnd-helper-startup.log";
    wchar_t name[]=L"helper";
    wchar_t *args[]={name,mode,zero,zero,size,size,log};
    // Registration fails before any window is created. Warm up OLE before
    // measuring GDI resources, then require repeated failures to stay bounded.
    assert(dnd_helper_window_main(7,args) == 1 && !log_file);
    DWORD before=GetGuiResources(GetCurrentProcess(),GR_GDIOBJECTS);
    for (int i=0;i<100;++i) {
        assert(dnd_helper_window_main(7,args) == 1 && !log_file);
        WNDCLASSW existing{};
        assert(GetClassInfoW(wc.hInstance,HELPER_CLASS,&existing));
        HANDLE file=CreateFileW(log,GENERIC_READ,0,nullptr,OPEN_EXISTING,0,nullptr);
        assert(file != INVALID_HANDLE_VALUE); CloseHandle(file);
        // An unbalanced OleInitialize would leave this thread in STA mode.
        HRESULT initialized=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
        assert(initialized == S_OK); CoUninitialize();
    }
    assert(GetGuiResources(GetCurrentProcess(),GR_GDIOBJECTS) == before);
    assert(UnregisterClassW(HELPER_CLASS,wc.hInstance));
    source_mode=true; drag_started=false;
    allocations_before_failure=0;
    assert(helper_wndproc(nullptr,WM_LBUTTONDOWN,0,0) == 0);
    assert(allocations_before_failure == -1);
    MSG message{};
    assert(PeekMessageW(&message,nullptr,WM_QUIT,WM_QUIT,PM_REMOVE));
    assert(message.wParam == 1);
    source_mode=false; drag_started=false;
    std::puts("DND_HELPER_STARTUP_PASS failures=101");
}
int main() {
    startup_contracts();
    file_contracts();
    enumeration_contracts();
    read_contracts();
    data_contracts();
    HelperDataObject output_data(L"",L"",{},"");
    check_dnd_output_contracts(&output_data);
    std::puts("DND_HELPER_OUTPUT_PASS");
    effect_contracts();
    for (int i = 0; i < 1000; ++i) {
        release_all(new HelperFormatEnumerator({}));
        release_all(new HelperDataObject(L"text", L"url", {L"file"}, "custom"));
        release_all(new HelperDropSource());
        release_all(new HelperDropTarget(nullptr));
    }
    std::puts("DND_HELPER_LIFETIME_PASS objects=4000");
}
