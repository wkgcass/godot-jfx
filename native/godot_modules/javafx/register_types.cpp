#include "register_types.h"

#include "javafx_render_surface.h"
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
#include "javafx_rd_pass.h"
#endif

#include "javafx_shader_rewrite.h"
#include "javafx_host.h"
#include "javafx_render_target.h"
#include "javafx_scene_view.h"
#include "javafx_window_surface.h"
#include "javafx_native_window.h"
#include "core/object/class_db.h"

void initialize_javafx_module(ModuleInitializationLevel p_level) {
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
	// Surfaces own their RIDs and release them when they leave the scene tree;
	// the RD-direct shared sampler is module-lifetime and freed here, while
	// the rendering server and its device are still alive.
#ifdef GODOT_JAVAFX_RD_DIRECT_ENABLED
	godot_javafx::rd_direct::print_rd_profile();
	godot_javafx::rd_direct::rd_profile_print_sinks();
	godot_javafx::rd_direct::release_all_passes();
	godot_javafx::rd_direct::release_shared_pipelines();
	godot_javafx::rd_direct::release_shared_sampler();
#endif
	godot_javafx::clear_instance_uniform_cache();
}
