#include "javafx_native_window.h"
#include "core/object/class_db.h"
#include "core/object/callable_mp.h"
#include "core/os/thread.h"
#include "servers/rendering/rendering_server.h"

JavaFXNativeWindow::JavaFXNativeWindow() {
	set_visible(false);
	set_force_native(true);
	set_transparent_background(true);
	surface = memnew(JavaFXWindowSurface);
	add_child(surface);
	connect("size_changed", callable_mp(this, &JavaFXNativeWindow::resized));
	set_process(true);
}

void JavaFXNativeWindow::_bind_methods() {
	ClassDB::bind_method(D_METHOD("present_content", "content", "output_size"), &JavaFXNativeWindow::present_content, DEFVAL(Size2i()));
	ClassDB::bind_method(D_METHOD("is_present_pending"), &JavaFXNativeWindow::is_present_pending);
	ClassDB::bind_method(D_METHOD("get_content_size"), &JavaFXNativeWindow::get_content_size);
	ClassDB::bind_method(D_METHOD("get_owned_resource_count"), &JavaFXNativeWindow::get_owned_resource_count);
}

void JavaFXNativeWindow::resized() {
	if (get_size().x <= 0 || get_size().y <= 0) return;
	surface->set_surface_size(get_size());
	dirty = content.is_valid();
}

void JavaFXNativeWindow::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		resized();
	} else if (p_what == NOTIFICATION_PROCESS && dirty && !surface->is_composition_pending()) {
		// Render resolution may differ from output resolution. Retain the
		// published output size while Prism prepares a resized frame.
		if (content.is_null()) {
			surface->remove_window(1);
			if (surface->compose_windows()) dirty = false;
		} else if (surface->configure_window(1, Rect2(Vector2(), content_output_size), 0, true, content_opacity) &&
				surface->set_window_content(1, content) && surface->compose_windows()) dirty = false;
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		// Parent/tree teardown visits children before JavaFXHost can run its
		// explicit destroy-window fence. EXIT_TREE is reverse notification order,
		// so quiesce this viewport before Window deletes its native swap chain.
		auto *rs = RenderingServer::get_singleton();
		rs->viewport_set_update_mode(get_viewport_rid(), RSE::VIEWPORT_UPDATE_DISABLED);
		rs->sync();
		content.unref(); dirty = false;
	}
}

bool JavaFXNativeWindow::present_content(const Ref<JavaFXRenderTarget> &p_content, Size2i p_output_size) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || !is_inside_tree() || p_content.is_null(), false);
	if (p_output_size == Size2i()) p_output_size = p_content->get_size();
	ERR_FAIL_COND_V(p_output_size.x <= 0 || p_output_size.y <= 0 || p_output_size.x > 8192 || p_output_size.y > 8192, false);
	content = p_content;
	content_output_size = p_output_size;
	dirty = true;
	return true;
}

bool JavaFXNativeWindow::is_present_pending() const {
	return dirty || surface->is_composition_pending();
}

void JavaFXNativeWindow::clear_content() {
	ERR_FAIL_COND(!Thread::is_main_thread());
	content.unref(); dirty = true;
}

void JavaFXNativeWindow::set_content_opacity(float p_opacity) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !Math::is_finite(p_opacity) || p_opacity < 0 || p_opacity > 1);
	content_opacity = p_opacity;
	if (content.is_valid()) dirty = true;
}

int JavaFXNativeWindow::get_owned_resource_count() const {
	return surface->get_owned_resource_count();
}
