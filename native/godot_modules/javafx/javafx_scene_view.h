#pragma once

#include "core/object/ref_counted.h"
#include "scene/main/viewport.h"
#include <unordered_map>

// Main-thread owner of a real scene-tree SubViewport. Its texture RID is borrowed.
class JavaFXSceneView : public RefCounted {
	GDCLASS(JavaFXSceneView, RefCounted);
	ObjectID viewport_id;
	ObjectID scene_id;
	std::unordered_map<uint64_t, Ref<InputEvent>> pressed_inputs;
	uint32_t mouse_buttons = 0;
	SubViewport *viewport() const;
protected:
	static void _bind_methods();
public:
	bool initialize(Node *p_parent, const String &p_scene, const Size2i &p_size);
	void resize(const Size2i &p_size);
	void push_input(const Ref<InputEvent> &p_event);
	void dispatch_input(uint32_t p_kind, uint32_t p_flags, uint32_t p_code, uint32_t p_unicode, Vector2 p_position, Vector2 p_relative);
	RID get_texture() const;
	Node *get_scene_root() const;
	Size2i get_size() const;
	~JavaFXSceneView();
};
