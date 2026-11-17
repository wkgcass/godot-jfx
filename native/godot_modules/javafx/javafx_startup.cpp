#include "javafx_host.h"
#include "core/os/os.h"
#include "main/splash.gen.h"
#if defined(WINDOWS_ENABLED)
#include "platform/windows/display_server_windows.h"
#elif defined(MACOS_ENABLED)
#include "javafx_host_macos.h"
#endif
#include "scene/main/canvas_layer.h"
#include "scene/gui/color_rect.h"
#include "scene/gui/texture_rect.h"
#include "scene/resources/image_texture.h"
#include "servers/rendering/rendering_server.h"

// Un-hide a window kept hidden while the JavaFX runtime starts up (see the
// GODOT_JFX_STARTUP handling in each DisplayServer backend).
static void release_startup_window(DisplayServerEnums::WindowID p_window) {
#if defined(WINDOWS_ENABLED)
	static_cast<DisplayServerWindows *>(DisplayServer::get_singleton())->release_javafx_startup_window(p_window);
#elif defined(MACOS_ENABLED)
	godot_javafx::macos_release_startup_window(p_window);
#endif
}

Window *JavaFXHost::startup_window() const {
	return startup_window_id ? get_native_window(startup_window_id) : get_window();
}

bool JavaFXHost::startup_show(int64_t p_id, bool p_visible) {
	if (!startup_enabled) return false;
	if (!p_visible) {
		if (startup_active && startup_window_id == p_id) startup_cancel();
		return false;
	}
	if (startup_active && startup_window_id == p_id) return true;
	if (startup_consumed) {
		Window *window = p_id ? get_native_window(p_id) : get_window();
		if (window && window->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
			release_startup_window(window->get_window_id());
		return false;
	}
	Window *window = p_id ? get_native_window(p_id) : get_window();
	ERR_FAIL_NULL_V(window, false);
	startup_consumed = true;
	startup_active = true;
	startup_window_id = p_id;
	startup_frame_ready = false;
	startup_window_shown = false;
	startup_logo_drawn = false;
	startup_logo_begin_us = 0;
	startup_fade_begin_us = 0;
	if (startup_logo_enabled) {
		startup_overlay = memnew(CanvasLayer);
		startup_overlay->set_layer(1024);
		window->add_child(startup_overlay);
		startup_background = memnew(ColorRect);
		startup_background->set_color(Color(0.14, 0.14, 0.14, 1));
		startup_background->set_mouse_filter(Control::MOUSE_FILTER_IGNORE);
		startup_overlay->add_child(startup_background);
		startup_image = memnew(TextureRect);
		Ref<Image> image = memnew(Image(boot_splash_png));
		startup_image->set_texture(ImageTexture::create_from_image(image));
		startup_image->set_expand_mode(TextureRect::EXPAND_IGNORE_SIZE);
		startup_image->set_stretch_mode(TextureRect::STRETCH_KEEP_ASPECT_CENTERED);
		startup_image->set_mouse_filter(Control::MOUSE_FILTER_IGNORE);
		startup_overlay->add_child(startup_image);
		++startup_logo_count;
	}
	startup_tick();
	auto *rs = RenderingServer::get_singleton();
	startup_previous_update_mode = rs->viewport_get_update_mode(window->get_viewport_rid());
	rs->viewport_set_update_mode(window->get_viewport_rid(), RSE::VIEWPORT_UPDATE_ALWAYS);
	return true;
}

void JavaFXHost::startup_tick() {
	if (!startup_active) return;
	Window *window = startup_window();
	if (!window) { startup_cancel(); return; }
	if (startup_background) {
		const Vector2 size = window->get_size();
		startup_background->set_size(size);
		const Vector2 image_size = startup_image->get_texture()->get_size();
		startup_image->set_size(image_size);
		startup_image->set_position(((size - image_size) * 0.5f).floor());
	}
}

void JavaFXHost::startup_post_draw() {
	if (!startup_active) return;
	Window *window = startup_window();
	if (!window || window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return;
	const uint64_t now = OS::get_singleton()->get_ticks_usec();
	if (!startup_window_shown) {
		if (!startup_logo_enabled && !startup_frame_ready) return;
		release_startup_window(window->get_window_id());
		startup_window_shown = true;
		if (!startup_logo_enabled) startup_cancel();
		return;
	}
	if (!startup_logo_drawn) {
		startup_logo_drawn = true;
		startup_logo_begin_us = now;
	}
	if (startup_frame_ready && now - startup_logo_begin_us >= 1000000) {
		if (startup_fade_begin_us == 0) startup_fade_begin_us = now;
		const float progress = MIN(float(now - startup_fade_begin_us) / 500000.0f, 1.0f);
		if (progress >= 1.0f) {
			startup_cancel();
		} else {
			const Color modulation(1, 1, 1, 1.0f - progress);
			startup_background->set_modulate(modulation);
			startup_image->set_modulate(modulation);
		}
	}
}

void JavaFXHost::startup_cancel() {
	if (startup_previous_update_mode >= 0) {
		Window *window = startup_window();
		if (window) RenderingServer::get_singleton()->viewport_set_update_mode(window->get_viewport_rid(), static_cast<RSE::ViewportUpdateMode>(startup_previous_update_mode));
		startup_previous_update_mode = -1;
	}
	if (startup_overlay) {
		startup_overlay->get_parent()->remove_child(startup_overlay);
		memdelete(startup_overlay);
	}
	startup_overlay = nullptr;
	startup_background = nullptr;
	startup_image = nullptr;
	startup_active = false;
}

Dictionary JavaFXHost::get_startup_status() const {
	Dictionary status;
	status["enabled"] = startup_enabled;
	status["active"] = startup_active;
	status["window_id"] = startup_window_id;
	status["frame_ready"] = startup_frame_ready;
	status["shown"] = startup_window_shown;
	status["logo_count"] = startup_logo_count;
	status["logo_begin_us"] = startup_logo_begin_us;
	status["fade_begin_us"] = startup_fade_begin_us;
	return status;
}
