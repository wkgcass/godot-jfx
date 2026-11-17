#include "javafx_window_surface.h"
#include "core/os/os.h"
#include "core/object/class_db.h"
#include "core/object/callable_mp.h"
#include "core/os/thread.h"
#include "servers/display/display_server.h"
#include "servers/rendering/rendering_server.h"
#include <algorithm>
#include <vector>

void JavaFXWindowSurface::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure_window", "id", "rect", "z", "visible", "opacity"), &JavaFXWindowSurface::configure_window);
	ClassDB::bind_method(D_METHOD("set_window_content", "id", "content"), &JavaFXWindowSurface::set_window_content);
	ClassDB::bind_method(D_METHOD("remove_window", "id"), &JavaFXWindowSurface::remove_window);
	ClassDB::bind_method(D_METHOD("compose_windows"), &JavaFXWindowSurface::compose_windows);
	ClassDB::bind_method(D_METHOD("get_window_count"), &JavaFXWindowSurface::get_window_count);
	ClassDB::bind_method(D_METHOD("get_window_content_size", "id"), &JavaFXWindowSurface::get_window_content_size);
	ClassDB::bind_method(D_METHOD("is_composition_pending"), &JavaFXWindowSurface::is_composition_pending);
}

Size2i JavaFXWindowSurface::get_window_content_size(int64_t p_id) const {
	auto found = layers.find(p_id);
	return found == layers.end() || found->second.content.is_null() ? Size2i() : found->second.content->get_size();
}

void JavaFXWindowSurface::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		RenderingServer::get_singleton()->connect("frame_post_draw", callable_mp(this, &JavaFXWindowSurface::composition_finished));
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		RenderingServer::get_singleton()->disconnect("frame_post_draw", callable_mp(this, &JavaFXWindowSurface::composition_finished));
		layers.clear(); pending = false;
	}
}

bool JavaFXWindowSurface::configure_window(int64_t p_id, const Rect2 &p_rect, int p_z, bool p_visible, float p_opacity) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || p_id <= 0, false);
	ERR_FAIL_COND_V(!p_rect.position.is_finite() || !p_rect.size.is_finite() || p_rect.size.x <= 0 || p_rect.size.y <= 0 || p_rect.size.x > 8192 || p_rect.size.y > 8192, false);
	ERR_FAIL_COND_V(!Math::is_finite(p_opacity) || p_opacity < 0 || p_opacity > 1, false);
	ERR_FAIL_COND_V(!layers.count(p_id) && layers.size() >= 64, false);
	Layer &layer = layers[p_id];
	layer.rect = p_rect; layer.z = p_z; layer.visible = p_visible; layer.opacity = p_opacity;
	return true;
}

bool JavaFXWindowSurface::set_window_content(int64_t p_id, const Ref<JavaFXRenderTarget> &p_content) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || p_content.is_null(), false);
	auto found = layers.find(p_id);
	ERR_FAIL_COND_V(found == layers.end(), false);
	// Submitted draws retain their own source reference, so replacing a layer
	// cannot release the previous content while its composition is in flight.
	found->second.content = p_content;
	return true;
}

void JavaFXWindowSurface::remove_window(int64_t p_id) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	layers.erase(p_id);
}

bool JavaFXWindowSurface::compose_windows() {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || !is_inside_tree(), false);
	// frame_post_draw never fires while no window can draw (e.g. macOS orders
	// out the root window when the last visible FX Stage hides or closes), so
	// a fence outliving the last drawable frame would deadlock every later
	// composition. Retire the stale fence and compose without re-arming it;
	// the recorded content still renders should a drawable frame return.
	const bool drawable = DisplayServer::get_singleton()->can_any_window_draw();
	if (pending && !drawable) { finish_present(); pending = false; }
	ERR_FAIL_COND_V(pending, false);
	std::vector<std::pair<int64_t, const Layer *>> order;
	for (const auto &entry : layers) {
		const Layer &layer = entry.second;
		if (layer.visible && layer.content.is_valid()) order.push_back({entry.first, &layer});
	}
	std::sort(order.begin(), order.end(), [](const auto &a, const auto &b) {
		return a.second->z == b.second->z ? a.first < b.first : a.second->z < b.second->z;
	});
	begin_present(); clear_commands();
	set_draw_shader_code("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;");
	set_draw_shader_parameters(Dictionary());
	set_draw_clip(false, Rect2i());
	for (const auto &entry : order) {
		const Layer &layer = *entry.second;
		add_render_target(layer.content, layer.rect, layer.opacity);
	}
	commit_present(); pending = drawable;
	return true;
}

void JavaFXWindowSurface::composition_finished() {
	if (!pending) return;
	finish_present(); pending = false;
}
