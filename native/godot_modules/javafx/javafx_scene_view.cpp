#include "javafx_scene_view.h"
#include "javafx_render_target.h"

#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "core/os/thread.h"
#include "scene/resources/packed_scene.h"
#include "scene/resources/world_2d.h"
#if defined(WINDOWS_ENABLED)
#include "platform/windows/key_mapping_windows.h"
#elif defined(MACOS_ENABLED) || defined(LINUXBSD_ENABLED)
#include "vk_key_map.h"
#endif

void JavaFXSceneView::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "parent", "scene", "size"), &JavaFXSceneView::initialize);
	ClassDB::bind_method(D_METHOD("resize", "size"), &JavaFXSceneView::resize);
	ClassDB::bind_method(D_METHOD("push_input", "event"), &JavaFXSceneView::push_input);
	ClassDB::bind_method(D_METHOD("get_texture"), &JavaFXSceneView::get_texture);
	ClassDB::bind_method(D_METHOD("get_scene_root"), &JavaFXSceneView::get_scene_root);
	ClassDB::bind_method(D_METHOD("get_size"), &JavaFXSceneView::get_size);
}

SubViewport *JavaFXSceneView::viewport() const {
	return Object::cast_to<SubViewport>(ObjectDB::get_instance(viewport_id));
}

bool JavaFXSceneView::initialize(Node *p_parent, const String &p_scene, const Size2i &p_size) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || viewport() || !p_parent || !p_parent->is_inside_tree(), false);
	ERR_FAIL_COND_V(p_size.x < 1 || p_size.y < 1 || p_size.x > 8192 || p_size.y > 8192, false);
	ERR_FAIL_COND_V(!p_scene.begins_with("res://"), false);
	Ref<PackedScene> packed = ResourceLoader::load(p_scene, "PackedScene");
	ERR_FAIL_COND_V(packed.is_null() || !packed->can_instantiate(), false);
	Node *scene = packed->instantiate();
	ERR_FAIL_NULL_V(scene, false);
	auto *view = memnew(SubViewport);
	viewport_id = view->get_instance_id();
	scene_id = scene->get_instance_id();
	view->set_disable_3d(true);
	view->set_transparent_background(true);
	Ref<World2D> world; world.instantiate();
	view->set_world_2d(world);
	view->set_size(p_size);
	view->set_update_mode(SubViewport::UPDATE_ALWAYS);
	view->set_handle_input_locally(true);
	// Popups created by this embedded Godot scene stay inside its viewport.
	// JavaFX secondary Stages separately use independent native host windows.
	view->set_embedding_subwindows(true);
	view->add_child(scene);
	p_parent->add_child(view);
	return true;
}

void JavaFXSceneView::resize(const Size2i &p_size) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !viewport());
	ERR_FAIL_COND(p_size.x < 1 || p_size.y < 1 || p_size.x > 8192 || p_size.y > 8192);
	viewport()->set_size(p_size);
}

void JavaFXSceneView::push_input(const Ref<InputEvent> &p_event) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !viewport() || p_event.is_null());
	// Coordinates have already been converted from the JavaFX node to viewport pixels.
	viewport()->push_input(p_event, true);
}

RID JavaFXSceneView::get_texture() const {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || !viewport(), RID());
	return viewport()->get_texture()->get_rid();
}

void JavaFXSceneView::dispatch_input(uint32_t p_kind, uint32_t p_flags, uint32_t p_code, uint32_t p_unicode, Vector2 p_position, Vector2 p_relative) {
	ERR_FAIL_COND(!Thread::is_main_thread() || !viewport());
	bool pressed = (p_flags & 1) != 0;
	if (p_kind == 5) {
		if (!pressed) {
			viewport()->gui_release_focus();
			for (const auto &entry : pressed_inputs) {
				Ref<InputEvent> release = entry.second->duplicate();
				release->set("pressed", false);
				Ref<InputEventMouseButton> button = release;
				if (button.is_valid()) { button->set_button_mask(BitField<MouseButtonMask>()); button->set_canceled(true); }
				Ref<InputEventScreenTouch> touch = release;
				if (touch.is_valid()) touch->set_canceled(true);
				Ref<InputEventKey> key = release;
				if (key.is_valid()) key->set_echo(false);
				Ref<InputEventWithModifiers> modifiers = release;
				if (modifiers.is_valid()) {
					modifiers->set_shift_pressed(false); modifiers->set_ctrl_pressed(false);
					modifiers->set_alt_pressed(false); modifiers->set_meta_pressed(false);
				}
				push_input(release);
			}
			pressed_inputs.clear(); mouse_buttons = 0;
		}
		return;
	}
	Ref<InputEvent> event;
	uint64_t identity = (uint64_t(p_kind) << 32) | p_code;
	if (p_kind == 0) {
		Ref<InputEventMouseMotion> motion; motion.instantiate();
		motion->set_position(p_position); motion->set_global_position(p_position); motion->set_relative(p_relative);
		motion->set_button_mask(BitField<MouseButtonMask>(mouse_buttons)); event = motion;
	} else if (p_kind == 1) {
		Ref<InputEventMouseButton> button; button.instantiate();
		if (pressed) mouse_buttons |= 1u << (p_code-1); else mouse_buttons &= ~(1u << (p_code-1));
		button->set_position(p_position); button->set_global_position(p_position);
		button->set_button_index(MouseButton(p_code)); button->set_pressed(pressed); button->set_double_click((p_flags & 32) != 0);
		if (p_code >= 4 && p_code <= 7) button->set_factor(p_relative.x);
		button->set_button_mask(BitField<MouseButtonMask>(mouse_buttons)); event = button;
	} else if (p_kind == 2) {
		Ref<InputEventKey> key; key.instantiate();
		// Java sends JavaFX KeyCode values, which mirror Win32 virtual-key codes.
#if defined(WINDOWS_ENABLED)
		key->set_keycode(KeyMappingWindows::get_keysym(p_code));
#elif defined(MACOS_ENABLED) || defined(LINUXBSD_ENABLED)
		key->set_keycode(godot_javafx::vk_to_godot_key(p_code));
#endif
		key->set_unicode(p_unicode); key->set_pressed(pressed);
		key->set_echo(pressed && pressed_inputs.count(identity)); event = key;
	} else if (p_kind == 3) {
		Ref<InputEventScreenTouch> touch; touch.instantiate();
		touch->set_index(p_code); touch->set_position(p_position); touch->set_pressed(pressed); event = touch;
	} else if (p_kind == 4) {
		Ref<InputEventScreenDrag> drag; drag.instantiate();
		drag->set_index(p_code); drag->set_position(p_position); drag->set_relative(p_relative); event = drag;
	}
	ERR_FAIL_COND(event.is_null());
	Ref<InputEventWithModifiers> modifiers = event;
	if (modifiers.is_valid()) {
		modifiers->set_shift_pressed((p_flags & 2) != 0); modifiers->set_ctrl_pressed((p_flags & 4) != 0);
		modifiers->set_alt_pressed((p_flags & 8) != 0); modifiers->set_meta_pressed((p_flags & 16) != 0);
	}
	if (p_kind == 1 || p_kind == 2 || p_kind == 3) {
		if (pressed) pressed_inputs[identity] = event->duplicate(); else pressed_inputs.erase(identity);
	}
	push_input(event);
}

Node *JavaFXSceneView::get_scene_root() const {
	return Object::cast_to<Node>(ObjectDB::get_instance(scene_id));
}

Size2i JavaFXSceneView::get_size() const {
	return viewport() ? viewport()->get_size() : Size2i();
}

JavaFXSceneView::~JavaFXSceneView() {
	// The parent may have already destroyed its children during scene teardown.
	if (auto *view = viewport()) {
		ERR_FAIL_COND(!Thread::is_main_thread());
		JavaFXRenderTarget::live_sampler_rids.erase(get_texture());
		memdelete(view);
	}
}
