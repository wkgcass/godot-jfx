#include "register_types.h"

#include "javafx_render_surface.h"

#include "javafx_shader_rewrite.h"
#include "javafx_host.h"
#include "javafx_render_target.h"
#include "javafx_scene_view.h"
#include "javafx_window_surface.h"
#include "javafx_native_window.h"
#include "core/config/project_settings.h"
#include "core/object/class_db.h"

void initialize_javafx_module(ModuleInitializationLevel p_level) {
#if defined(WINDOWS_ENABLED) && defined(LIBGODOT_ENABLED)
	// The project is loaded before CORE modules, and Godot selects its driver afterward.
	if (p_level == MODULE_INITIALIZATION_LEVEL_CORE) {
		auto *settings = ProjectSettings::get_singleton();
		const String driver_setting = "rendering/rendering_device/driver.windows";
		if (!settings->has_setting(driver_setting)) {
			settings->set_setting(driver_setting, "d3d12");
		}
	}
#endif
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(JavaFXRenderSurface);
		GDREGISTER_CLASS(JavaFXWindowSurface);
		GDREGISTER_CLASS(JavaFXNativeWindow);
		GDREGISTER_CLASS(JavaFXHost);
		GDREGISTER_CLASS(JavaFXRenderTarget);
		GDREGISTER_CLASS(JavaFXSceneView);
	}
}

void uninitialize_javafx_module(ModuleInitializationLevel p_level) {
	// Godot calls this for every level, including CORE after renderer teardown.
	// Match our registration level: scene objects and rendering services are
	// still available here, and each shared resource must be retired once.
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
	godot_javafx::clear_instance_uniform_cache();
}
