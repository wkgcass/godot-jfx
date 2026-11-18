#if defined(MACOS_ENABLED) && defined(LIBGODOT_ENABLED)
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <jni.h>
#include "core/extension/godot_instance.h"

bool javafx_macos_iteration(GodotInstance *instance) {
	@autoreleasepool {
		return instance->iteration();
	}
}

// The JDK launcher parks the first thread in a CFRunLoop. Execute the
// Godot pump there without holding the main dispatch queue during iteration.
static void run_on_appkit_thread(JNIEnv *env, jobject loop) {
	// A second Java class loader may have loaded a different copy of the dylib.
	NSProcessInfo *process = [NSProcessInfo processInfo];
	const void *claim = reinterpret_cast<const void *>(sel_registerName("godotJavaFXEngineClaim"));
	@synchronized(process) {
		if (objc_getAssociatedObject(process, claim)) {
			env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "The process already claimed a Godot instance");
			return;
		}
		objc_setAssociatedObject(process, claim, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	JavaVM *vm = nullptr;
	if (env->GetJavaVM(&vm) != JNI_OK) {
		env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Could not obtain the hosting JVM");
		return;
	}
	jmethodID run = env->GetMethodID(env->GetObjectClass(loop), "run", "()V");
	if (!run) return;
	if ([NSThread isMainThread]) {
		env->CallVoidMethod(loop, run);
		return;
	}
	jobject callback = env->NewGlobalRef(loop);
	if (!callback) return;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	__block jthrowable failure = nullptr;
	__block bool attached = false;
	CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
		@autoreleasepool {
			JNIEnv *main_env = nullptr;
			bool detach = vm->GetEnv(reinterpret_cast<void **>(&main_env), JNI_VERSION_1_8) == JNI_EDETACHED;
			if (detach) vm->AttachCurrentThreadAsDaemon(reinterpret_cast<void **>(&main_env), nullptr);
			if (main_env) {
				attached = true;
				main_env->CallVoidMethod(callback, run);
				if (jthrowable thrown = main_env->ExceptionOccurred()) {
					main_env->ExceptionClear();
					failure = static_cast<jthrowable>(main_env->NewGlobalRef(thrown));
					main_env->DeleteLocalRef(thrown);
				}
				if (detach) vm->DetachCurrentThread();
			}
		}
		dispatch_semaphore_signal(done);
	});
	CFRunLoopWakeUp(CFRunLoopGetMain());
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
#if !OS_OBJECT_USE_OBJC || !__has_feature(objc_arc)
	dispatch_release(done);
#endif
	env->DeleteGlobalRef(callback);
	if (!attached) {
		env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Could not attach AppKit thread to the JVM");
	} else if (failure) {
		env->Throw(failure);
		env->DeleteGlobalRef(failure);
	}
}

extern "C" JNIEXPORT void JNICALL Java_com_sun_javafx_tk_godot_LibraryGodotEngine_runOnAppKitThread(JNIEnv *env, jclass, jobject loop) {
	run_on_appkit_thread(env, loop);
}

extern "C" JNIEXPORT void JNICALL Java_com_sun_javafx_tk_godot_GodotSceneFixture_runOnAppKitThread(JNIEnv *env, jclass, jobject loop) {
	run_on_appkit_thread(env, loop);
}
#endif
