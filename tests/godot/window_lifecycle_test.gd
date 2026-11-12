extends Node2D

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.WHITE)
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"WindowLifecycleProbe"):
		push_error("Lifecycle JVM start failed")
		get_tree().quit(1)
		return
	var seen := {}
	var samples := 0
	var peak := 0
	var deadline := Time.get_ticks_msec()+45000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Lifecycle failed/timed out: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		peak = maxi(peak,host.get_owned_resource_count())
		var title := get_window().title
		if not title.begins_with("Hidden ") and not title.begins_with("Visible "): continue
		var hidden := title.begins_with("Hidden ")
		var index := title.get_slice(" ",1).to_int()
		var expected := Color.WHITE if hidden else (Color.GREEN if index % 2 == 0 else Color.RED)
		var actual := get_viewport().get_texture().get_image().get_pixel(20,20)
		if absf(actual.r-expected.r) > .03 or absf(actual.g-expected.g) > .03 or absf(actual.b-expected.b) > .03:
			push_error("Lifecycle pixel mismatch %s: %s" % [title,actual])
			get_tree().quit(1)
			return
		seen[title] = true
		samples += 1
	if seen.size() != 16 or samples < 16 or peak > 80 or host.get_window_count() != 0 or DisplayServer.get_window_list().size() != 1:
		push_error("Lifecycle coverage/cleanup mismatch: states=%d samples=%d peak=%d layers=%d" % [seen.size(),samples,peak,host.get_window_count()])
		get_tree().quit(1)
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Lifecycle GPU resources leaked")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_WINDOW_LIFECYCLE_PASS states=%d samples=%d peak=%d" % [seen.size(),samples,peak])
	get_tree().quit(0)
