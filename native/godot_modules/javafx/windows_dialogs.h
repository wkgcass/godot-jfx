#pragma once
#include <windows.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <jni.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <string>
#include <vector>
#include <stdexcept>

namespace godot_javafx::windows_dialogs {
using Microsoft::WRL::ComPtr;
struct Request {
    int64_t owner = -1;
    int mode = 0, selected = 0; // open, multi-open, save, directory
    std::wstring folder, filename, title;
    std::vector<std::wstring> names, patterns, files;
    std::string error;
    std::atomic<bool> cancel{false}, done{false};
    std::atomic<DWORD> thread_id{0};
    bool started = false;
    HWND hwnd_owner = nullptr;
};
inline void require(HRESULT hr, const char *operation) {
    if (FAILED(hr)) throw std::runtime_error(std::string(operation)+" (HRESULT "+std::to_string(static_cast<unsigned long>(hr))+")");
}
inline std::wstring path(IShellItem *item) {
    PWSTR text = nullptr;
    require(item->GetDisplayName(SIGDN_FILESYSPATH,&text),"Read selected path");
    try { std::wstring result(text); CoTaskMemFree(text); return result; }
    catch (...) { CoTaskMemFree(text); throw; }
}
struct Apartment {
    HRESULT status = CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED|COINIT_DISABLE_OLE1DDE);
    ~Apartment() { if (SUCCEEDED(status)) CoUninitialize(); }
};
inline void close_windows(Request *request) {
    DWORD thread=request->thread_id.load();
    if (!thread || request->done.load()) return;
    EnumThreadWindows(thread,[](HWND window,LPARAM) -> BOOL {
        wchar_t name[64]{};
        GetClassNameW(window,name,64);
        if (wcscmp(name,L"#32770")==0) PostMessageW(window,WM_CLOSE,0,0);
        return TRUE;
    },0);
}
struct Watch {
    Request *request;
    IFileDialog *dialog;
};
inline thread_local Watch *watch = nullptr;
inline void CALLBACK cancel_timer(HWND, UINT, UINT_PTR, DWORD) {
    if (watch && (watch->request->cancel.load() ||
            (watch->request->hwnd_owner && !IsWindow(watch->request->hwnd_owner))))
        close_windows(watch->request);
}
struct Timer {
    UINT_PTR id;
    Watch state;
    Timer(Request *request, IFileDialog *dialog) : state{request,dialog} {
        watch = &state;
        id = SetTimer(nullptr,0,50,cancel_timer);
        if (!id) { watch=nullptr; throw std::runtime_error("Cannot create file-dialog cancellation timer"); }
    }
    ~Timer() { KillTimer(nullptr,id); watch=nullptr; }
};
inline void run(const std::shared_ptr<Request> &r) {
    r->thread_id.store(GetCurrentThreadId());
    try {
        Apartment apartment;
        require(apartment.status,"Initialize file-dialog COM apartment");
        ComPtr<IFileDialog> dialog;
        require(CoCreateInstance(r->mode==2 ? CLSID_FileSaveDialog : CLSID_FileOpenDialog,
                nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&dialog)),"Create file dialog");
        DWORD flags=0;
        require(dialog->GetOptions(&flags),"Read dialog options");
        flags |= FOS_FORCEFILESYSTEM|FOS_NOCHANGEDIR;
        if (r->mode==1) flags |= FOS_ALLOWMULTISELECT;
        if (r->mode==3) flags |= FOS_PICKFOLDERS;
        if (r->mode!=2) flags |= FOS_FILEMUSTEXIST;
        else flags |= FOS_OVERWRITEPROMPT;
        require(dialog->SetOptions(flags),"Configure dialog options");
        if (!r->title.empty()) require(dialog->SetTitle(r->title.c_str()),"Set dialog title");
        if (!r->folder.empty()) {
            ComPtr<IShellItem> folder;
            require(SHCreateItemFromParsingName(r->folder.c_str(),nullptr,IID_PPV_ARGS(&folder)),"Resolve initial folder");
            require(dialog->SetFolder(folder.Get()),"Set initial folder");
        }
        if (!r->filename.empty()) require(dialog->SetFileName(r->filename.c_str()),"Set initial file name");
        std::vector<COMDLG_FILTERSPEC> filters;
        for (size_t i=0;i<r->names.size();++i) filters.push_back({r->names[i].c_str(),r->patterns[i].c_str()});
        if (!filters.empty()) {
            require(dialog->SetFileTypes(static_cast<UINT>(filters.size()),filters.data()),"Set extension filters");
            require(dialog->SetFileTypeIndex(r->selected+1),"Set selected extension filter");
        }
        Timer timer(r.get(),dialog.Get());
        if (r->cancel.load() || (r->hwnd_owner && !IsWindow(r->hwnd_owner))) {
            r->selected=-1;
        } else {
            HRESULT hr=dialog->Show(r->hwnd_owner);
            if (hr==HRESULT_FROM_WIN32(ERROR_CANCELLED)) r->selected=-1;
            else {
                require(hr,"Show file dialog");
                UINT index=0;
                if (!filters.empty()) require(dialog->GetFileTypeIndex(&index),"Read selected extension filter");
                r->selected=index ? static_cast<int>(index)-1 : -1;
                if (r->mode==1) {
                    ComPtr<IFileOpenDialog> open;
                    require(dialog.As(&open),"Read multi-file dialog");
                    ComPtr<IShellItemArray> items;
                    require(open->GetResults(&items),"Read selected files");
                    DWORD count=0;
                    require(items->GetCount(&count),"Count selected files");
                    if (count>4096) throw std::runtime_error("File selection exceeds 4096 paths");
                    for (DWORD i=0;i<count;++i) {
                        ComPtr<IShellItem> item;
                        require(items->GetItemAt(i,&item),"Read selected file");
                        r->files.push_back(path(item.Get()));
                    }
                } else {
                    ComPtr<IShellItem> item;
                    require(dialog->GetResult(&item),"Read selected item");
                    r->files.push_back(path(item.Get()));
                }
            }
        }
    } catch (const std::exception &e) { r->error=e.what(); }
    catch (...) { r->error="Unexpected native file-dialog failure"; }
    r->done.store(true,std::memory_order_release);
}
class Service {
    std::mutex mutex;
    std::shared_ptr<Request> active;
    std::thread worker;
    bool stopped=false;
public:
    ~Service() { stop(); }
    void submit(std::shared_ptr<Request> request) {
        std::lock_guard<std::mutex> lock(mutex);
        if (stopped) throw std::runtime_error("File-dialog service stopped");
        if (active) throw std::runtime_error("A file dialog is already open");
        active=std::move(request);
    }
    std::shared_ptr<Request> pending() {
        std::lock_guard<std::mutex> lock(mutex);
        return active && !active->started ? active : nullptr;
    }
    void start(const std::shared_ptr<Request> &r, HWND owner, bool valid_owner) {
        std::lock_guard<std::mutex> lock(mutex);
        if (active!=r || r->started) return;
        r->started=true; r->hwnd_owner=owner;
        if (stopped || !valid_owner || r->cancel.load()) { r->selected=-1; r->done.store(true); return; }
        try { worker=std::thread(run,r); }
        catch (const std::exception &e) { r->error=e.what(); r->done.store(true); }
    }
    void cancel() {
        std::lock_guard<std::mutex> lock(mutex);
        if (active) { active->cancel.store(true); close_windows(active.get()); }
    }
    std::shared_ptr<Request> take_result() {
        std::lock_guard<std::mutex> lock(mutex);
        if (!active || !active->done.load(std::memory_order_acquire)) return nullptr;
        if (worker.joinable()) worker.join();
        auto result=active; active.reset(); return result;
    }
    void stop() {
        std::lock_guard<std::mutex> lock(mutex);
        stopped=true;
        if (active) {
            active->cancel.store(true);
            close_windows(active.get());
            if (!active->started) { active->selected=-1; active->done.store(true); }
        }
        if (worker.joinable()) {
            // IFileDialog can synchronously re-enable its owner while leaving
            // Show(). Service sent window messages while the owner thread waits
            // for COM cleanup; otherwise host shutdown could deadlock in join.
            HANDLE handle=worker.native_handle();
            while (WaitForSingleObject(handle,0)!=WAIT_OBJECT_0) {
                MsgWaitForMultipleObjects(1,&handle,FALSE,50,QS_SENDMESSAGE);
                MSG message{};
                PeekMessageW(&message,nullptr,WM_NULL,WM_NULL,PM_NOREMOVE);
            }
            worker.join();
        }
    }
};
inline void fail(JNIEnv *env, const char *type, const char *message) {
    jclass cls=env->FindClass(type);
    if (cls) { env->ThrowNew(cls,message); env->DeleteLocalRef(cls); }
}
inline std::wstring string(JNIEnv *env,jstring value) {
    if (!value) return {};
    jsize n=env->GetStringLength(value);
    if (n>32768) throw std::invalid_argument("Dialog string exceeds 32768 characters");
    const jchar *data=env->GetStringChars(value,nullptr);
    if (!data) throw std::runtime_error("Cannot copy dialog string");
    std::wstring result;
    try { result.assign(reinterpret_cast<const wchar_t *>(data),n); }
    catch (...) { env->ReleaseStringChars(value,data); throw; }
    env->ReleaseStringChars(value,data);
    if (result.find(L'\0')!=std::wstring::npos) throw std::invalid_argument("Dialog string contains NUL");
    return result;
}
inline void submit(JNIEnv *env,Service &service,jlong owner,jint mode,jstring folder,jstring filename,jstring title,jobjectArray filters,jint selected) {
    try {
        if (owner < -1 || mode<0 || mode>3) throw std::invalid_argument("Invalid dialog mode/owner");
        auto r=std::make_shared<Request>(); r->owner=owner; r->mode=mode; r->selected=selected;
        r->folder=string(env,folder); r->filename=string(env,filename); r->title=string(env,title);
        jsize n=filters ? env->GetArrayLength(filters) : 0;
        if (n%2 || n>256 || (n && (selected<0 || selected>=n/2))) throw std::invalid_argument("Invalid dialog filters");
        for (jsize i=0;i<n;++i) {
            auto text=static_cast<jstring>(env->GetObjectArrayElement(filters,i));
            auto value=string(env,text); env->DeleteLocalRef(text);
            if (value.empty()) throw std::invalid_argument("Empty dialog filter");
            (i%2 ? r->patterns : r->names).push_back(std::move(value));
        }
        service.submit(std::move(r));
    } catch (const std::invalid_argument &e) { if (!env->ExceptionCheck()) fail(env,"java/lang/IllegalArgumentException",e.what()); }
    catch (const std::exception &e) { if (!env->ExceptionCheck()) fail(env,"java/lang/IllegalStateException",e.what()); }
}
inline jobjectArray poll(JNIEnv *env,Service &service) {
    auto r=service.take_result();
    if (!r) return nullptr;
    if (!r->error.empty()) { fail(env,"java/lang/IllegalStateException",r->error.c_str()); return nullptr; }
    jclass type=env->FindClass("java/lang/String");
    if (!type) return nullptr;
    jobjectArray result=env->NewObjectArray(static_cast<jsize>(r->files.size()+1),type,nullptr);
    env->DeleteLocalRef(type);
    if (!result) return nullptr;
    std::wstring index=std::to_wstring(r->selected);
    for (size_t i=0;i<=r->files.size();++i) {
        const auto &value=i ? r->files[i-1] : index;
        jstring text=env->NewString(reinterpret_cast<const jchar *>(value.data()),static_cast<jsize>(value.size()));
        if (!text) return nullptr;
        env->SetObjectArrayElement(result,static_cast<jsize>(i),text); env->DeleteLocalRef(text);
        if (env->ExceptionCheck()) return nullptr;
    }
    return result;
}
}
