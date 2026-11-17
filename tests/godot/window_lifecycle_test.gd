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
		# frame_post_draw stops when no host window can draw: on macOS hiding the
		# last visible FX Stage orders out the root NSWindow, and Godot then skips
		# RenderingServer.draw entirely (Windows keeps drawing hidden windows).
		# Race the draw signal against a timer so status/deadline polling never
		# deadlocks; assertions below are unchanged. Keep the fallback interval
		# short: the probe holds each "Hidden N" title for only 20 host ticks, so
		# a coarse timer deterministically misses every hidden state.
		var drawn := [false]
		RenderingServer.frame_post_draw.connect(func() -> void: drawn[0] = true, CONNECT_ONE_SHOT)
		get_tree().create_timer(0.02).timeout.connect(func() -> void: drawn[0] = true, CONNECT_ONE_SHOT)
		while not drawn[0]:
			await get_tree().process_frame
		peak = maxi(peak,host.get_owned_resource_count())
		var title := get_window().title
		if not title.begins_with("Hidden ") and not title.begins_with("Visible "): continue
		var hidden := title.begins_with("Hidden ")
		var index := title.get_slice(" ",1).to_int()
		# macOS does not draw hidden windows at all (window_can_draw=false), so a
		# hidden window's pixels are unobservable there; state coverage, cleanup
		# and resource assertions below still apply on every platform.
		var pixel_observable := not (hidden and OS.has_feature("macos"))
		if pixel_observable:
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
