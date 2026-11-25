#include "robot.h"
#include "session.h"

namespace godot_javafx::wayland_robot {
namespace {
// One virtual seat per Glass event thread. The application closes it at
// toolkit termination, including held buttons and modifiers on disconnect.
thread_local std::unique_ptr<Session> session;
void fail(JNIEnv *env, const char *type, const char *message) {
	jclass exception = env->FindClass(type);
	if (exception) env->ThrowNew(exception, message);
}
template <typename F> void guard(JNIEnv *env, F f) {
	try { f(); }
	catch (const Unsupported &e) { fail(env, "java/lang/UnsupportedOperationException", e.what()); }
	catch (const std::invalid_argument &e) { fail(env, "java/lang/IllegalArgumentException", e.what()); }
	catch (const std::bad_alloc &) { fail(env, "java/lang/OutOfMemoryError", "Wayland Robot allocation failed"); }
	catch (const std::exception &e) { session.reset(); fail(env, "java/lang/IllegalStateException", e.what()); }
}
Session &get() {
	if (!session) session = std::make_unique<Session>();
	return *session;
}
jintArray array(JNIEnv *env, const int32_t *data, size_t size) {
	jintArray result = env->NewIntArray(jsize(size));
	if (result) env->SetIntArrayRegion(result, 0, jsize(size), data);
	return result;
}
}
void JNICALL open(JNIEnv *env, jclass) { guard(env, [] { get(); }); }
void JNICALL close(JNIEnv *, jclass) { session.reset(); }
void JNICALL move(JNIEnv *env, jclass, jint x, jint y) { guard(env, [&] { get().move(x,y); }); }
void JNICALL button(JNIEnv *env, jclass, jint b, jboolean pressed) { guard(env, [&] { get().button(b, pressed); }); }
void JNICALL wheel(JNIEnv *env, jclass, jint amount) { guard(env, [&] { get().wheel(amount); }); }
void JNICALL key(JNIEnv *env, jclass, jint code, jboolean pressed) { guard(env, [&] { get().key(code,pressed); }); }
jintArray JNICALL position(JNIEnv *env, jclass) {
	jintArray result = nullptr;
	guard(env, [&] { auto p = get().position(); result = array(env,p.data(),p.size()); });
	return result;
}
jintArray JNICALL capture(JNIEnv *env, jclass, jint x, jint y, jint w, jint h) {
	jintArray result = nullptr;
	guard(env, [&] { auto pixels = get().capture(x,y,w,h); result = array(env,pixels.data(),pixels.size()); });
	return result;
}
}
