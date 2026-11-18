#if defined(LIBGODOT_ENABLED)
#include "javafx_host.h"
#include "core/config/project_settings.h"
#include "core/extension/godot_instance.h"
#include "core/extension/libgodot.h"
#include "core/io/file_access_memory.h"
#include "core/os/os.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

#include <atomic>
#include <cwchar>
#include <string>
#include <vector>

#ifdef MACOS_ENABLED
bool javafx_macos_iteration(GodotInstance *instance);
#endif

namespace {
std::atomic<bool> stopping{ false };
#ifdef WINDOWS_ENABLED
HANDLE process_claim = nullptr;

bool claim_engine() {
	if (!JavaFXHost::claim_library()) return false;
	// Separate class loaders can load different physical copies of the DLL.
	// Keep the kernel object until process exit, including after a failed start.
	wchar_t name[64];
	std::swprintf(name, 64, L"Local\\GodotJavaFXEngine-%lu", GetCurrentProcessId());
	process_claim = CreateMutexW(nullptr, FALSE, name);
	if (!process_claim) return false;
	if (GetLastError() == ERROR_ALREADY_EXISTS) {
		CloseHandle(process_claim);
		process_claim = nullptr;
		return false;
	}
	return true;
}

#else
bool claim_engine() { return JavaFXHost::claim_library(); }
#endif

void fail(JNIEnv *env, const char *message) {
	if (!env->ExceptionCheck()) {
		jclass exception = env->FindClass("java/lang/IllegalStateException");
		if (exception) env->ThrowNew(exception, message);
	}
}

String java_string(JNIEnv *env, jstring value) {
	const jchar *chars = env->GetStringChars(value, nullptr);
	if (!chars) return {};
	String result = String::utf16(reinterpret_cast<const char16_t *>(chars), env->GetStringLength(value));
	env->ReleaseStringChars(value, chars);
	return result;
}

GDExtensionBool extension_init(GDExtensionInterfaceGetProcAddress, GDExtensionClassLibraryPtr,
		GDExtensionInitialization *init) {
	init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_CORE;
	init->initialize = [](void *, GDExtensionInitializationLevel) {};
	init->deinitialize = [](void *, GDExtensionInitializationLevel) {};
	return true;
}
}

namespace godot_javafx { extern thread_local JNIEnv *scene_env; }

// Scene-driven integration fixtures use the packaged engine and existing JVM.
// GDScript owns the host node, the application entry and the final exit code.
extern "C" JNIEXPORT jint JNICALL Java_com_sun_javafx_tk_godot_GodotSceneFixture_run(JNIEnv *env, jclass, jstring library, jobjectArray arguments) {
	if (!claim_engine()) {
		fail(env, "The process already claimed a Godot instance");
		return 1;
	}
	std::vector<std::string> args{ java_string(env, library).utf8().get_data() };
	for (jsize i = 0; i < env->GetArrayLength(arguments); ++i) {
		jstring arg = static_cast<jstring>(env->GetObjectArrayElement(arguments, i));
		args.emplace_back(java_string(env, arg).utf8().get_data());
		env->DeleteLocalRef(arg);
	}
	if (env->ExceptionCheck()) return 1;
	std::vector<char *> argv;
	for (auto &arg : args) argv.push_back(arg.data());
	argv.push_back(nullptr);
	auto *instance = static_cast<GodotInstance *>(libgodot_create_godot_instance(int(args.size()), argv.data(), extension_init));
	if (!instance) return 1;
	godot_javafx::scene_env = env;
	int code = 1;
	if (instance->start()) {
#ifdef MACOS_ENABLED
		while (!javafx_macos_iteration(instance)) {}
#else
		while (!instance->iteration()) {}
#endif
		code = OS::get_singleton()->get_exit_code();
	}
	libgodot_destroy_godot_instance(instance);
	godot_javafx::scene_env = nullptr;
	return code;
}

extern "C" JNIEXPORT void JNICALL Java_com_sun_javafx_tk_godot_LibraryGodotEngine_requestStop(JNIEnv *, jclass) {
	stopping.store(true);
}

extern "C" JNIEXPORT void JNICALL Java_com_sun_javafx_tk_godot_LibraryGodotEngine_mountScenePack(JNIEnv *env, jclass, jbyteArray contents) {
	const String source = "res://.godot-jfx-scenes.pck";
	const jsize length = env->GetArrayLength(contents);
	{
		Vector<uint8_t> bytes;
		if (length < 4 || bytes.resize(length) != OK) {
			fail(env, "resources: empty or unreadable bundled GodotView scenes.pck");
			return;
		}
		env->GetByteArrayRegion(contents, 0, length, reinterpret_cast<jbyte *>(bytes.ptrw()));
		if (env->ExceptionCheck()) return;
		FileAccessMemory::register_file(source, bytes);
	}
	if (!bool(ProjectSettings::get_singleton()->call(SNAME("load_resource_pack"), source, false))) {
		fail(env, "resources: could not mount bundled GodotView scenes.pck");
	}
}

extern "C" JNIEXPORT void JNICALL Java_com_sun_javafx_tk_godot_LibraryGodotEngine_run(
		JNIEnv *env, jclass, jclass bridge, jobject ready, jstring library, jstring project,
		jboolean pack, jstring renderer, jstring startup, jboolean disable_vsync, jint max_fps, jboolean verbose) {
	if (!claim_engine()) {
		fail(env, "create: the process already claimed a Godot instance");
		return;
	}
	const String startup_mode = java_string(env, startup);
	std::vector<std::string> args{ java_string(env, library).utf8().get_data() };
	if (project) {
		args.push_back(pack ? "--main-pack" : "--path");
		args.emplace_back(java_string(env, project).utf8().get_data());
	} else {
		args.push_back("--javafx-no-project");
	}
	if (disable_vsync) args.emplace_back("--disable-vsync");
	if (max_fps > 0) {
		args.emplace_back("--max-fps");
		args.push_back(std::to_string(max_fps));
	}
	args.insert(args.end(), { "--rendering-method", java_string(env, renderer).utf8().get_data(),
		"--render-thread", "safe", "--", ("--javafx-startup=" + startup_mode).utf8().get_data()
	});
	if (env->ExceptionCheck()) return;
	std::vector<char *> argv;
	for (auto &arg : args) argv.push_back(arg.data());
	argv.push_back(nullptr);
	auto *instance = static_cast<GodotInstance *>(libgodot_create_godot_instance(int(args.size()), argv.data(), extension_init));
	if (!instance) {
		fail(env, "create: Godot could not load the project");
		return;
	}
	if (verbose) print_line("GODOT_LIBRARY_INSTANCE_CREATED");
	if (!instance->start()) {
		libgodot_destroy_godot_instance(instance);
		fail(env, "start: Godot could not start the SceneTree");
		return;
	}
	SceneTree *tree = SceneTree::get_singleton();
	if (!tree || !tree->get_root() || !tree->get_root()->find_children("*", "JavaFXHost", true, false).is_empty()) {
		fail(env, "attach: project must supply a SceneTree without another JavaFXHost");
	} else {
		auto *host = memnew(JavaFXHost);
		host->set_name("JavaFXHost");
		tree->get_root()->add_child(host);
		ObjectID id = host->get_instance_id();
		if (!host->connect_jvm(env, bridge, startup_mode)) {
			fail(env, "attach: could not connect JavaFXHost to GodotBridge");
		} else {
			if (verbose) print_line("GODOT_LIBRARY_LOOP renderer=" + OS::get_singleton()->get_current_rendering_method());
			jclass callback = env->GetObjectClass(ready);
			jmethodID publish = callback ? env->GetMethodID(callback, "run", "()V") : nullptr;
			if (publish) env->CallVoidMethod(ready, publish);
			while (!env->ExceptionCheck() && !stopping.load()) {
#ifdef MACOS_ENABLED
				if (javafx_macos_iteration(instance)) break;
#else
				if (instance->iteration()) break;
#endif
				auto *live = ObjectDB::get_instance<JavaFXHost>(id);
				if (!live || !live->is_jvm_connected()) {
					fail(env, "iteration: project stopped or removed JavaFXHost");
					break;
				}
			}
		}
		if (auto *live = ObjectDB::get_instance<JavaFXHost>(id)) live->stop_host();
	}
	libgodot_destroy_godot_instance(instance);
	FileAccessMemory::cleanup();
}
#endif
