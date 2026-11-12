extends Node

func _ready() -> void:
	var old_cap := Engine.max_fps
	var old_vsync := DisplayServer.window_get_vsync_mode()
	var mode := OS.get_environment("GODOT_JFX_TEST_PACING_MODE")
	var fallback_seen := false
	Engine.max_fps = 30 if mode == "cap" else 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	var started: bool = host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "PacingCapProbe")
	var deadline := Time.get_ticks_msec() + 20000
	while started and host.get_runtime_status() not in ["finished", "failed"] and Time.get_ticks_msec() < deadline:
		if mode != "cap" and not fallback_seen:
			if Engine.max_fps > 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED:
				fallback_seen = true
				if mode == "override": Engine.max_fps = 47
			else:
				OS.delay_msec(40) # Controlled slowdown, without setting an FPS cap.
		await get_tree().process_frame
	for frame in range(2): await get_tree().process_frame
	var expected := 30 if mode == "cap" else (47 if mode == "override" else 0)
	var passed: bool = started and host.get_runtime_status() == "finished" and Engine.max_fps == expected and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED and (mode == "cap" or fallback_seen)
	print("PACING_CAP_RESULT cap=", Engine.max_fps, " vsync=", DisplayServer.window_get_vsync_mode())
	remove_child(host)
	host.free()
	passed = passed and Engine.max_fps == expected and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED
	Engine.max_fps = old_cap
	DisplayServer.window_set_vsync_mode(old_vsync)
	if not passed:
		push_error("Pacing ownership/restoration check failed or fixture did not finish")
		get_tree().quit(1)
		return
	print("PACING_CAP_PASS")
	get_tree().quit(0)
