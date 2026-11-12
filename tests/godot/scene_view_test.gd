extends Node2D

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func _ready() -> void:
	var surface = ClassDB.instantiate("JavaFXRenderSurface")
	add_child(surface)
	for cycle in range(100):
		var view = ClassDB.instantiate("JavaFXSceneView")
		if not view.initialize(surface,"res://embedded_scene.tscn",Vector2i(64,64)):
			fail("Embedded scene allocation failed")
			return
		var root = view.get_scene_root()
		var root_id: int = root.get_instance_id()
		var viewport_id: int = root.get_viewport().get_instance_id()
		var owner_id: int = view.get_instance_id()
		if cycle == 0:
			var popup := Window.new()
			popup.size = Vector2i(20,20)
			root.add_child(popup)
			popup.show()
			await RenderingServer.frame_post_draw
			if not popup.is_embedded() or DisplayServer.get_window_list().size() != 1:
				fail("Embedded scene opened an extra native window")
				return
			popup.free()
		view.resize(Vector2i(96,64))
		if view.get_size() != Vector2i(96,64):
			fail("Embedded viewport resize failed")
			return
		surface.add_scene_view(view,Rect2(16,16,192,128))
		for frame in range(4):
			await RenderingServer.frame_post_draw
		if root.ticks < 1:
			fail("Embedded scene did not process")
			return
		var mouse := InputEventMouseButton.new()
		mouse.position = Vector2(12,14)
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = true
		view.push_input(mouse)
		var touch := InputEventScreenTouch.new()
		touch.index = 1
		touch.position = Vector2(22,24)
		touch.pressed = true
		view.push_input(touch)
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = true
		view.push_input(key)
		if root.mouse_events != 1 or root.touch_events != 1 or root.key_events != 1 or root.last_position != Vector2(22,24):
			fail("Embedded viewport input routing failed")
			return
		view = null
		if not is_instance_id_valid(owner_id) or not is_instance_id_valid(viewport_id):
			fail("Sampled scene released before rendering")
			return
		for frame in range(3):
			await RenderingServer.frame_post_draw
		if cycle == 99:
			var image := get_viewport().get_texture().get_image()
			var blue := image.get_pixel(48,48)
			var alpha := image.get_pixel(108,48)
			var transparent := image.get_pixel(160,40)
			var resized := image.get_pixel(190,112)
			print("SCENE_VIEW_PIXELS ",[blue,alpha,transparent,resized])
			if blue.b < .95 or blue.r > .05 or absf(alpha.r-.46) > .04 or absf(alpha.g-.975) > .04 or absf(transparent.r-.92) > .04 or resized.g < .95 or resized.r > .05:
				fail("Embedded scene texture/alpha/resize mismatch")
				return
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-scene-view.png"))
		surface.clear_commands()
		if is_instance_id_valid(owner_id) or is_instance_id_valid(root_id) or is_instance_id_valid(viewport_id) or surface.get_child_count() != 0:
			fail("Embedded scene owner or nodes leaked")
			return
	# A parent can destroy its tree while a Java/native resource wrapper survives.
	var surviving_owner = ClassDB.instantiate("JavaFXSceneView")
	if not surviving_owner.initialize(surface,"res://embedded_scene.tscn",Vector2i(32,32)):
		fail("Parent teardown fixture failed")
		return
	var surviving_root_id: int = surviving_owner.get_scene_root().get_instance_id()
	remove_child(surface)
	if surface.get_owned_resource_count() != 0:
		fail("Embedded scene surface resources leaked")
		return
	surface.free()
	if is_instance_id_valid(surviving_root_id) or surviving_owner.get_scene_root() != null or surviving_owner.get_size() != Vector2i.ZERO:
		fail("Scene wrapper retained a destroyed parent tree")
		return
	surviving_owner = null
	print("SCENE_VIEW_PASS: 100 scene load/resize/input/retain/release cycles")
	get_tree().quit(0)
