extends Node2D

func click(window: Window, point: Vector2) -> void:
	point *= DisplayServer.screen_get_scale(window.current_screen)
	var motion := InputEventMouseMotion.new()
	motion.window_id = window.get_window_id()
	motion.position = point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var button := InputEventMouseButton.new()
		button.window_id = window.get_window_id()
		button.position = point
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		Input.parse_input_event(button)

func matches(a: Color, b: Color) -> bool:
	return absf(a.r-b.r)<.04 and absf(a.g-b.g)<.04 and absf(a.b-b.b)<.04

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("LogicalWindowProbe"):
		push_error("Logical probe failed to start")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec()+40000
	var state := 0
	var seen := {}
	var last_observed := ""
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec()>deadline:
			push_error("Logical windows failed/timed out: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		# Closing the final Stage stops viewport drawing on macOS. Keep
		# observing the probe and its deadline while the engine is still running.
		await get_tree().process_frame
		var title := get_window().title
		var scale := DisplayServer.screen_get_scale(get_window().current_screen)
		var child: Window = null
		for node in host.get_children():
			if node is Window and node.visible:
				child = node
		if state == 0 and title == "Logical ready" and child != null:
			var root_image := get_viewport().get_texture().get_image()
			var child_image := child.get_texture().get_image()
			if not matches(child_image.get_pixelv(Vector2i(Vector2(20,65)*DisplayServer.screen_get_scale(child.current_screen))),Color.BLUE): continue
			if child.is_embedded() or host.get_surface_size() != Vector2i(Vector2(240,160)*scale) or not matches(root_image.get_pixelv(Vector2i(Vector2(230,140)*scale)),Color.RED):
				push_error("Secondary Stage changed primary surface");get_tree().quit(1);return
			child_image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/logical-windows-initial.png"))
			click(child,Vector2(20,20)); state=1
		elif state == 1 and title == "Child action 1" and child != null:
			for pressed in [true,false]:
				var key := InputEventKey.new()
				key.window_id=child.get_window_id(); key.keycode=KEY_SPACE; key.pressed=pressed
				Input.parse_input_event(key)
			state=2
		elif state == 2 and title == "Child action 2":
			click(get_window(),Vector2(20,25)); state=3
		if title in ["Logical moved","Logical hidden","Logical restored"] and not seen.has(title):
			var root_image := get_viewport().get_texture().get_image()
			if not matches(root_image.get_pixelv(Vector2i(Vector2(180,115)*scale)),Color.RED): continue
			if title == "Logical hidden":
				if child != null or DisplayServer.get_window_list().size()!=1: continue
			else:
				if child == null or child.is_embedded() or DisplayServer.get_window_list().size()!=2: continue
				if child.position-get_window().position != Vector2i(Vector2(30,60)*scale): continue
				var pixel := child.get_texture().get_image().get_pixelv(Vector2i(Vector2(10,65)*DisplayServer.screen_get_scale(child.current_screen)))
				if last_observed!=title:
					print("NATIVE_STAGE_OBSERVED ",title," ",pixel)
					last_observed=title
				if absf(pixel.b-.5)>.04 or absf(pixel.a-.5)>.04 or pixel.r>.04 or pixel.g>.04: continue
			seen[title]=true
	if state != 3 or seen.size()!=3 or host.get_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Logical lifecycle/interaction coverage differs: states="+str(seen.keys()))
		get_tree().quit(1)
		return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Logical GPU resources leaked")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_LOGICAL_WINDOWS_PASS")
	get_tree().quit(0)
