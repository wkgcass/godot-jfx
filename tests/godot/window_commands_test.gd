extends Node2D

func differs(a: Color, b: Color) -> bool:
	return absf(a.r-b.r) > .03 or absf(a.g-b.g) > .03 or absf(a.b-b.b) > .03 or absf(a.a-b.a) > .03

func acknowledge() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = Vector2(10, 10)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.WHITE)
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("WindowCommandsProbe"):
		push_error("Window command Java probe start failed")
		get_tree().quit(1)
		return
	var checked := [false, false, false, false, false, false, false, false]
	var cleanup_checked := false
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Window commands failed/timed out: " + host.get_runtime_error())
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		var count: int = host.get_completed_presentations()
		var windows: int = host.get_window_count()
		var sequence: int = host.get_applied_sequence()
		if sequence >= 10 and windows == 0 and not host.is_composition_pending() and not cleanup_checked:
			cleanup_checked = true
			acknowledge()
		var stage := sequence - 2 if sequence >= 2 and sequence <= 8 and windows == 2 and count >= 2 else (7 if sequence >= 9 and count == 3 and windows == 1 else -1)
		if stage < 0 or checked[stage] or host.is_composition_pending():
			continue
		# Completion retires GPU commands; the parent viewport may sample the
		# updated surface on the following draw due to viewport dependency order.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var left := image.get_pixel(30, 30)
		var overlap := image.get_pixel(80, 30)
		var right := image.get_pixel(130, 30)
		var expected_left := Color.RED if stage == 0 else Color.GREEN
		var expected_overlap := Color(.5, 0, .5) if stage == 0 else (Color(0, .5, .5) if stage in [1,3] else (Color.BLUE if stage == 6 else Color.GREEN))
		var expected_right := Color.WHITE if stage in [2,7] else (Color.BLUE if stage == 6 else Color(.5,.5,1))
		if differs(left, expected_left) or differs(overlap, expected_overlap) or differs(right, expected_right) or (stage > 1 and host.get_completed_presentations() != 3):
			push_error("Window pixels/presentation count differ at stage %d: %s %s %s" % [stage, left, overlap, right])
			get_tree().quit(1)
			return
		checked[stage] = true
		image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/window-commands-%d.png" % stage))
		acknowledge()
	if not checked.all(func(value): return value) or host.get_window_count() != 0 or DisplayServer.get_window_list().size() != 1:
		push_error("Missing window validation or retained layers/native windows")
		get_tree().quit(1)
		return
	host.stop_host()
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Window host leaked GPU resources")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_WINDOW_COMMANDS_PASS")
	get_tree().quit(0)
