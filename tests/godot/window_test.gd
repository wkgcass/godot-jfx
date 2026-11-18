extends Node2D

func _ready() -> void:
	print("WINDOWS_BEFORE_PROBE ", DisplayServer.get_window_list())
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("GlassWindowProbe"):
		push_error("Window probe probe failed to start")
		get_tree().quit(1)
		return
	var checked := false
	var close_stage := 0
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Window probe failed: " + host.get_runtime_error())
			host.stop_host()
			get_tree().quit(1)
			return
		if not checked and get_window().title == "Godot Glass 主窗口 🧪" and get_window().size == Vector2i(800, 480):
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var pixel := image.get_pixel(40, 40)
			if DisplayServer.get_window_list().size() != 1 or not get_window().get_flag(Window.FLAG_RESIZE_DISABLED):
				print("WINDOWS_AFTER_PROBE ", DisplayServer.get_window_list())
				for id in DisplayServer.get_window_list():
					print("WINDOW_DETAIL ", id, " ", DisplayServer.window_get_size(id), " ", DisplayServer.window_get_position(id))
				push_error("Window state differs: count=" + str(DisplayServer.get_window_list().size()) + " resize_disabled=" + str(get_window().get_flag(Window.FLAG_RESIZE_DISABLED)))
				get_tree().quit(1)
				return
			if abs(pixel.r - 0.12) > 0.02 or abs(pixel.g - 0.24) > 0.02 or abs(pixel.b - 0.36) > 0.02:
				push_error("Window background differs: " + str(pixel))
				get_tree().quit(1)
				return
			if DisplayServer.cursor_get_shape() != DisplayServer.CURSOR_IBEAM:
				push_error("Cursor shape command was not applied")
				get_tree().quit(1)
				return
			var output := ProjectSettings.globalize_path("res://../../artifacts/reference/godot-glass-window.png")
			if image.save_png(output) != OK:
				push_error("Cannot save window rendering capture")
				get_tree().quit(1)
				return
			checked = true
			inject_pointer_events()
		if checked and close_stage == 0 and get_window().title == "Input verified":
			if get_tree().auto_accept_quit:
				push_error("Host must let Glass decide whether to accept a close request")
				get_tree().quit(1)
				return
			get_window().propagate_notification(NOTIFICATION_WM_MOUSE_EXIT)
			get_window().propagate_notification(NOTIFICATION_WM_MOUSE_ENTER)
			get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			close_stage = 1
		elif close_stage == 1 and get_window().title == "Close request vetoed":
			get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			close_stage = 2
		await get_tree().process_frame
	remove_child(host)
	host.free()
	if not get_tree().auto_accept_quit or close_stage != 2:
		push_error("Close lifecycle did not restore host state")
		get_tree().quit(1)
		return
	if not checked:
		push_error("Window state was never observed")
		get_tree().quit(1)
		return
	print("M2_GLASS_WINDOW_PASS: existing host window, Unicode title, resize, cursor and GPU background")
	get_tree().quit(0)

func inject_pointer_events() -> void:
	# Enter through Godot's normal Input path, not a test-only JNI entry point.
	for step in range(5):
		var event: InputEventMouse
		if step == 0 or step == 2:
			event = InputEventMouseMotion.new()
		else:
			event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_WHEEL_UP if step == 4 else MOUSE_BUTTON_LEFT
			event.pressed = step != 3
			if step == 4:
				event.factor = 0.5
		event.position = Vector2(73, 91)
		event.global_position = Vector2(73, 91)
		event.shift_pressed = true
		event.ctrl_pressed = true
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if step == 1 or step == 2 else 0
		Input.parse_input_event(event)
	for step in range(5):
		var key := InputEventKey.new()
		key.keycode = KEY_A if step < 3 else KEY_LEFT
		key.unicode = 0x1f9ea if step < 3 else 0
		key.pressed = step != 2 and step != 4
		key.echo = step == 1
		Input.parse_input_event(key)
