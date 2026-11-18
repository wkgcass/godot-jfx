extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	await get_tree().process_frame
	if not host.run_fixture_probe("MenuClickProbe"):
		push_error("Menu click probe failed"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 60000
	var clicked := false
	var before: Dictionary = {}
	while host.get_runtime_status() != "finished":
		await get_tree().process_frame
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Menu click probe failed: " + host.get_runtime_error()); get_tree().quit(1); return
		if not clicked and get_window().title == "MenuClick CLICK":
			before = host.get_render_stats()
			var point := Vector2(25, 20) * DisplayServer.screen_get_scale(get_window().current_screen)
			var motion := InputEventMouseMotion.new()
			motion.window_id = get_window().get_window_id()
			motion.position = point
			Input.parse_input_event(motion)
			for pressed in [true, false]:
				var click := InputEventMouseButton.new()
				click.window_id = get_window().get_window_id()
				click.position = point
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				Input.parse_input_event(click)
			clicked = true
	var after: Dictionary = host.get_render_stats()
	if not clicked or after.get("completed_render_sequence",0) <= before.get("completed_render_sequence",0) or after.get("presentations",0) <= before.get("presentations",0):
		push_error("Menu click did not produce render progress"); get_tree().quit(1); return
	remove_child(host); host.free()
	print("GODOT_MENU_CLICK_PASS")
	get_tree().quit(0)
