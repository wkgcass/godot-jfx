// Mock JNI failure injection: no JVM, clipboard, or physical input required.
#include <thread>
#include <condition_variable>
#include <chrono>

namespace dnd_jni_test {
#ifdef __APPLE__
namespace dnd = godot_javafx::macos_dnd;
#elif defined(__linux__)
namespace dnd = godot_javafx::linux_dnd;
#else
namespace dnd = godot_javafx::windows_dnd;
#endif
static int fail_at, operations, live_refs, callbacks, attaches, detaches, violations;
static bool pending;
static JNIEnv *active_env;
static std::mutex pause_mutex;
static std::condition_variable pause_changed;
static bool pause_entry = false, entered = false, resume_entry = false;

static bool operation() {
    if (pending) ++violations;
    ++operations;
    if (operations == fail_at) { pending = true; return false; }
    return true;
}
template <class T> static T reference() {
    if (!operation()) return nullptr;
    ++live_refs;
    return reinterpret_cast<T>(uintptr_t(operations + 1));
}
static jstring JNICALL new_string(JNIEnv *, const jchar *, jsize) { return reference<jstring>(); }
static jstring JNICALL new_utf(JNIEnv *, const char *) { return reference<jstring>(); }
static jbyteArray JNICALL new_bytes(JNIEnv *, jsize) { return reference<jbyteArray>(); }
static jclass JNICALL find_class(JNIEnv *, const char *) { return reference<jclass>(); }
static jobjectArray JNICALL new_array(JNIEnv *, jsize, jclass, jobject) { return reference<jobjectArray>(); }
static void JNICALL set_bytes(JNIEnv *, jbyteArray, jsize, jsize, const jbyte *) { operation(); }
static void JNICALL set_element(JNIEnv *, jobjectArray, jsize, jobject) { operation(); }
static void JNICALL delete_ref(JNIEnv *, jobject) { --live_refs; }
static jboolean JNICALL exception_check(JNIEnv *) { return pending ? JNI_TRUE : JNI_FALSE; }
static void JNICALL exception_describe(JNIEnv *) { }
static void JNICALL exception_clear(JNIEnv *) { pending = false; }
static jint JNICALL invoke(JNIEnv *, jclass, jmethodID, va_list) { ++callbacks; operation(); return 7; }
static jint JNICALL get_env(JavaVM *, void **, jint) {
    if (pause_entry) {
        std::unique_lock<std::mutex> lock(pause_mutex);
        entered = true;
        pause_changed.notify_all();
        if (!pause_changed.wait_for(lock, std::chrono::seconds(5), [] { return resume_entry; })) return JNI_ERR;
    }
    return JNI_EDETACHED;
}
static jint JNICALL attach(JavaVM *, void **out, void *) { ++attaches; *out = active_env; return JNI_OK; }
static jint JNICALL detach(JavaVM *) { ++detaches; return JNI_OK; }
static void check() {
    JNINativeInterface_ functions{};
    functions.NewString = new_string;
    functions.NewStringUTF = new_utf;
    functions.NewByteArray = new_bytes;
    functions.FindClass = find_class;
    functions.NewObjectArray = new_array;
    functions.SetByteArrayRegion = set_bytes;
    functions.SetObjectArrayElement = set_element;
    functions.DeleteLocalRef = delete_ref;
    functions.ExceptionCheck = exception_check;
    functions.ExceptionDescribe = exception_describe;
    functions.ExceptionClear = exception_clear;
    functions.CallStaticIntMethodV = invoke;
    JNIEnv env{ &functions };
    active_env = &env;
    JNIInvokeInterface_ vm_functions{};
    vm_functions.GetEnv = get_env;
    vm_functions.AttachCurrentThread = attach;
    vm_functions.DetachCurrentThread = detach;
    JavaVM vm{ &vm_functions };
    dnd::UpcallState state;
    state.publish(&vm, reinterpret_cast<jclass>(uintptr_t(1)), reinterpret_cast<jmethodID>(uintptr_t(1)));
    dnd::Upcall upcall{ &state };
    const std::u16string text = u"data";
    const std::string bytes = "bytes";
    const std::vector<std::pair<dnd::wide_string, std::string>> custom{
        { dnd::wide_string(1, 'a'), bytes }, { dnd::wide_string(1, 'b'), bytes }
    };
    int total = 0;
    for (int failure = 0; failure <= total; ++failure) {
        fail_at = failure;
        operations = live_refs = callbacks = attaches = detaches = violations = 0;
        pending = false;
        jint result = dnd::call_target(upcall, 1, 0, 0, 0, 7, 0, "text/plain",
                &text, &bytes, &bytes, &text, &text, &custom);
        if (!failure) total = operations;
        require(violations == 0, "JNI operation executed with a pending exception");
        require(live_refs == 0, "DnD upcall leaked JNI local references");
        require(attaches == 1 && detaches == 1 && !pending, "DnD upcall failed to clean JNI state");
        require(result == (failure ? 0 : 7), "DnD upcall did not reject JNI failure");
        require(callbacks == ((!failure || failure == total) ? 1 : 0), "Partial payload reached Java callback");
        require(!failure || operations == failure, "JNI marshalling continued after failure");
    }
    std::cout << "DND_JNI_FAILURE_CLEANUP_PASS operations=" << total << std::endl;
    // Pause after admission but before attachment: shutdown must not pass here.
    fail_at = operations = live_refs = callbacks = attaches = detaches = violations = 0;
    pending = false;
    pause_entry = true;
    jint result = 0;
    std::thread caller([&] {
        result = dnd::call_target(upcall, 1, 0, 0, 0, 7, 0, "text/plain",
                &text, nullptr, nullptr, nullptr, nullptr, nullptr);
    });
    bool reached;
    {
        std::unique_lock<std::mutex> lock(pause_mutex);
        reached = pause_changed.wait_for(lock, std::chrono::seconds(5), [] { return entered; });
    }
    bool protected_entry = !state.mutex.try_lock();
    if (!protected_entry) state.mutex.unlock();
    std::thread closer([&] { state.close(); });
    {
        std::lock_guard<std::mutex> lock(pause_mutex);
        resume_entry = true;
        pause_changed.notify_all();
    }
    caller.join();
    closer.join();
    pause_entry = false;
    require(reached && protected_entry, "VM shutdown can overtake an admitted upcall before attachment");
    require(result == 7 && attaches == 1 && detaches == 1 && live_refs == 0,
            "Admitted upcall did not finish cleanly before shutdown");
    const int before = operations;
    result = dnd::call_target(upcall, 1, 0, 0, 0, 7, 0, "text/plain",
            &text, nullptr, nullptr, nullptr, nullptr, nullptr);
    require(!upcall && result == 0 && operations == before && attaches == 1 && detaches == 1,
            "Closed gate allowed another JNI upcall");
    std::cout << "DND_JNI_SHUTDOWN_GATE_PASS" << std::endl;

}
} // namespace dnd_jni_test
