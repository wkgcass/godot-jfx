extends Node

func _ready() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var host = get_tree().root.get_node_or_null("JavaFXHost")
		if not host or DisplayServer.get_window_list().size() < 2 or host.get_completed_presentations() < 2:
			continue
		var scale := DisplayServer.screen_get_scale()
		var image := get_tree().root.get_texture().get_image()
		var position := Vector2i(Vector2(170, 50) * scale)
		if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(position):
			continue
		var color := image.get_pixelv(position)
		if color.g < 0.96 or color.r > 0.04 or color.b > 0.04:
			continue
		if image.save_png(OS.get_environment("GODOT_LIBRARY_CAPTURE")) != OK:
			push_error("Could not save GodotView capture")
			return
		print("LIBRARY_VIEW_STAGE_PASS renderer=", RenderingServer.get_current_rendering_method(),
				" windows=", DisplayServer.get_window_list().size(), " pixel=", color)
		var point := Vector2(32, 22) * scale
		var motion := InputEventMouseMotion.new()
		motion.position = point
		Input.parse_input_event(motion)
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = point
			click.pressed = pressed
			Input.parse_input_event(click)
		return
	push_error("Timed out waiting for independent window and embedded scene pixels")
