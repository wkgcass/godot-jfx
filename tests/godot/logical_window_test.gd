extends Node2D

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var button := InputEventMouseButton.new()
		button.position = point
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		Input.parse_input_event(button)

func matches(a: Color, b: Color) -> bool:
	return absf(a.r-b.r)<.04 and absf(a.g-b.g)<.04 and absf(a.b-b.b)<.04

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"LogicalWindowProbe"):
		push_error("Logical JVM failed to start")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec()+40000
	var state := 0
	var seen := {}
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec()>deadline:
			push_error("Logical windows failed/timed out: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		var title := get_window().title
		if state == 0 and title == "Logical ready" and host.get_window_count() == 2:
			var image := get_viewport().get_texture().get_image()
			if not matches(image.get_pixel(120,115),Color.BLUE): continue
			if host.get_surface_size() != Vector2i(240,160) or not matches(image.get_pixel(230,140),Color.RED):
				push_error("Logical Stage changed primary surface")
				get_tree().quit(1)
				return
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/logical-windows-initial.png"))
			click(Vector2(120,70)); state=1
		elif state == 1 and title == "Child action 1":
			for pressed in [true,false]:
				var key := InputEventKey.new()
				key.keycode=KEY_SPACE; key.unicode=32; key.pressed=pressed
				Input.parse_input_event(key)
			state=2
		elif state == 2 and title == "Child action 2":
			click(Vector2(20,25)); state=3
		if title in ["Logical moved","Logical hidden","Logical restored"]:
			var image := get_viewport().get_texture().get_image()
			var expected := Color.RED if title == "Logical hidden" else Color(.5,0,.5)
			if not matches(image.get_pixel(40,125),expected) or not matches(image.get_pixel(180,115),Color.RED):
				image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/logical-diagnostic.png"))
				push_error("Logical geometry/visibility pixel mismatch: %s new=%s old=%s layers=%d" % [title,image.get_pixel(40,125),image.get_pixel(180,115),host.get_window_count()])
				get_tree().quit(1)
				return
			seen[title]=true
	if state != 3 or seen.size()!=3 or host.get_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Logical lifecycle/interaction coverage differs")
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
