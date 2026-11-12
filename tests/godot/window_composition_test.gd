extends Node2D

func differs(a: Color, b: Color) -> bool:
	return absf(a.r-b.r) > .03 or absf(a.g-b.g) > .03 or absf(a.b-b.b) > .03

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"WindowCompositionProbe"):
		push_error("Composition JVM start failed")
		get_tree().quit(1)
		return
	var seen := {}
	var deadline := Time.get_ticks_msec()+30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Composition failed/timed out: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		if not get_window().title.begins_with("Composition "): continue
		var index := get_window().title.get_slice(" ",1).to_int()
		var image := get_viewport().get_texture().get_image()
		var middle := image.get_pixel(80,30)
		var right := image.get_pixel(140,30)
		var expected := Color(.5,0,.5) if index in [0,4] else Color.RED
		var right_expected := Color.BLUE if index == 1 else Color.RED
		if differs(middle,expected) or differs(right,right_expected):
			push_error("Composition pixels differ at %d: %s %s" % [index,middle,right])
			get_tree().quit(1)
			return
		if host.get_surface_size() != Vector2i(240,160) or host.get_window_count() != (1 if index == 5 else 2):
			push_error("Secondary Presentable changed host size or layer ownership")
			get_tree().quit(1)
			return
		if not seen.has(index): image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/window-composition-%d.png" % index))
		seen[index] = true
	if seen.size() != 6 or host.get_window_count() != 0 or DisplayServer.get_window_list().size() != 1:
		push_error("Composition coverage/cleanup differs")
		get_tree().quit(1)
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Composition GPU resources leaked")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_WINDOW_COMPOSITION_PASS")
	get_tree().quit(0)
