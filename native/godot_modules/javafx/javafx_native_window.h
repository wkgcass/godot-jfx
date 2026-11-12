#pragma once

#include "scene/main/window.h"
#include "javafx_window_surface.h"

// A real Godot-owned OS window with its own JavaFX GPU presentation surface.
// Glass identity/commands are connected by JavaFXHost, not by Java threads.
class JavaFXNativeWindow : public Window {
	GDCLASS(JavaFXNativeWindow, Window);
	JavaFXWindowSurface *surface = nullptr;
	Ref<JavaFXRenderTarget> content;
	Size2i content_output_size;
	bool dirty = false;
	float content_opacity = 1;
	void resized();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	JavaFXNativeWindow();
	bool present_content(const Ref<JavaFXRenderTarget> &p_content, Size2i p_output_size = Size2i());
	void clear_content();
	void set_content_opacity(float p_opacity);
	bool is_present_pending() const;
	Size2i get_content_size() const { return content.is_valid() ? content->get_size() : Size2i(); }
	int get_owned_resource_count() const;
};
