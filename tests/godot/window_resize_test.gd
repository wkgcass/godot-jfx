extends Node2D

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.WHITE)
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "WindowResizeProbe"):
		push_error("Resize JVM start failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 40000
	var samples := 0
	var sizes := {}
	var peak := 0
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Resize failed/timed out: " + host.get_runtime_error())
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		peak = maxi(peak, host.get_owned_resource_count())
		if get_window().title == "Resize active":
			var color := get_viewport().get_texture().get_image().get_pixel(20,20)
			if color.r < .95 or color.g > .05 or color.b > .05 or host.get_window_count() != 1:
				push_error("Resize lost retained window image: %s layers=%d" % [color, host.get_window_count()])
				get_tree().quit(1)
				return
			samples += 1
			sizes[get_window().size] = true
	if samples < 40 or sizes.size() < 4 or peak > 80 or host.get_window_count() != 0 or DisplayServer.get_window_list().size() != 1:
		push_error("Resize lifecycle/resource coverage failed: samples=%d sizes=%d peak=%d layers=%d" % [samples, sizes.size(), peak, host.get_window_count()])
		get_tree().quit(1)
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Resize host leaked GPU resources")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_WINDOW_RESIZE_PASS samples=%d sizes=%d peak=%d" % [samples, sizes.size(), peak])
	get_tree().quit(0)
