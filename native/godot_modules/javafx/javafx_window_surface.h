#pragma once

#include "javafx_render_surface.h"
#include <map>

// Legacy logical-window compositor, retained for protocol diagnostics.
// Current Glass Stages use independent native windows via NATIVE_WINDOW_PRESENT;
// this layer does not define their window ownership or input routing.
class JavaFXWindowSurface : public JavaFXRenderSurface {
	GDCLASS(JavaFXWindowSurface, JavaFXRenderSurface);
	struct Layer {
		Rect2 rect;
		int z = 0;
		bool visible = true;
		float opacity = 1;
		Ref<JavaFXRenderTarget> content;
	};
	std::map<int64_t, Layer> layers;
	bool pending = false;

protected:
	void composition_finished();
	static void _bind_methods();
	void _notification(int p_what);

public:
	bool configure_window(int64_t p_id, const Rect2 &p_rect, int p_z, bool p_visible, float p_opacity);
	bool set_window_content(int64_t p_id, const Ref<JavaFXRenderTarget> &p_content);
	void remove_window(int64_t p_id);
	bool compose_windows();
	int get_window_count() const { return layers.size(); }
	Size2i get_window_content_size(int64_t p_id) const;
	bool is_composition_pending() const { return pending; }
};
