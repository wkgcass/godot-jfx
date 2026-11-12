extends Node2D

var host: Node

func _ready() -> void:
	host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "WindowDragProbe"):
		fail("Window drag JVM rejected")
		return
	var deadline := Time.get_ticks_msec() + 90000
	while get_window().title != "WindowDrag ready" or host.get_completed_presentations() == 0:
		if aborted(deadline): return
		await get_tree().process_frame
	var w0: Vector2i = get_window().position
	var window_id := get_window().get_window_id()
	# Press on the moving pane (the top 28 px title bar) and let the press reach
	# JavaFX so its drag handler records the stage/screen baseline.
	var press := InputEventMouseButton.new()
	press.window_id = window_id
	press.position = Vector2(200, 14)
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	for i in range(25):
		if aborted(deadline): return
		await get_tree().process_frame
	# Fast upward drag: 15 steps of 16 px per step. Each motion targets an
	# absolute screen position; the local coordinate goes negative once the
	# native window trails the cursor, replicating a fast physical drag.
	var lags: Array[int] = []
	for k in range(1, 16):
		var target_y := w0.y - 16 * k
		var screen := Vector2(w0.x + 200, w0.y + 14 - 16 * k)
		var motion := InputEventMouseMotion.new()
		motion.window_id = window_id
		motion.position = screen - Vector2(get_window().position)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		var waited := 0
		while get_window().position.y > target_y + 2:
			await get_tree().process_frame
			waited += 1
			if aborted(deadline): return
			if waited > 40:
				fail("Window never reached drag target y=" + str(target_y) + " (stuck at " + str(get_window().position.y) + ")")
				return
		lags.append(waited)
		print("DRAG_LAG k=" + str(k) + " frames=" + str(waited))
	# Release where the cursor ended up (above the window, like a fast drag).
	var release := InputEventMouseButton.new()
	release.window_id = window_id
	release.position = Vector2(w0.x + 200, w0.y + 14 - 240) - Vector2(get_window().position)
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	for i in range(15):
		if aborted(deadline): return
		await get_tree().process_frame
	var settled: Vector2i = get_window().position
	if abs(settled.x - w0.x) > 3 or abs(settled.y - (w0.y - 240)) > 3:
		fail("Window settled at " + str(settled) + " instead of " + str(Vector2i(w0.x, w0.y - 240)))
		return
	var total := 0
	var worst := 0
	for lag in lags:
		total += lag
		worst = maxi(worst, lag)
	print("DRAG_LAG_AVG " + str(total / float(lags.size())))
	print("DRAG_LAG_MAX " + str(worst))
	# Click the content area so the probe completes and the JVM shuts down.
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.window_id = window_id
		click.position = Vector2(200, 150)
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
	while host.get_runtime_status() != "finished":
		if aborted(deadline): return
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Window drag host retained resources")
		return
	host.free()
	print("GODOT_WINDOW_DRAG_PASS")
	get_tree().quit()

func aborted(deadline: int) -> bool:
	if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
		fail("Window drag run aborted: " + host.get_runtime_error())
		return true
	return false

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
