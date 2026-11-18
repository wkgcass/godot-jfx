extends Node2D

var host: Node

func _ready() -> void:
	host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("ResizeCursorProbe"):
		fail("Resize cursor probe rejected")
		return
	var deadline := Time.get_ticks_msec() + 40000
	while get_window().title != "ResizeCursor ready" or host.get_completed_presentations() == 0:
		if aborted(deadline): return
		await get_tree().process_frame
	var size := get_window().size
	# JavaFX scene coordinates are logical; Godot input uses window pixels.
	var scale := Vector2(float(size.x) / 400.0, float(size.y) / 300.0)
	var corner := Vector2(392, 292) * scale
	# Hover the transparent resize circle; the scene cursor must reach the native resize shape.
	if not await hover_until(corner, DisplayServer.CURSOR_FDIAGSIZE, deadline): return
	# Follow-up motion inside the circle must not revert the cursor to the arrow:
	# the Viewport re-asserts the Input default cursor on every motion event.
	for offset in [Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(0, 0), Vector2(2, 1)]:
		send_motion(corner + offset * scale)
		await get_tree().process_frame
		await get_tree().process_frame
		if aborted(deadline): return
		if DisplayServer.cursor_get_shape() != DisplayServer.CURSOR_FDIAGSIZE:
			fail("Resize cursor reverted by follow-up motion to " + str(DisplayServer.cursor_get_shape()))
			return
	if not await hover_until(Vector2(size) * 0.5, DisplayServer.CURSOR_ARROW, deadline): return
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.window_id = get_window().get_window_id()
		click.position = Vector2(size) * 0.5
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
	while host.get_runtime_status() != "finished":
		if aborted(deadline): return
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Resize cursor host retained resources")
		return
	host.free()
	print("GODOT_RESIZE_CURSOR_PASS")
	get_tree().quit()

func send_motion(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.window_id = get_window().get_window_id()
	motion.position = point
	Input.parse_input_event(motion)

func hover_until(point: Vector2, shape: int, deadline: int) -> bool:
	var frames := 0
	while DisplayServer.cursor_get_shape() != shape:
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("Resize cursor never reached shape " + str(shape) + " (stuck at " + str(DisplayServer.cursor_get_shape()) + ")")
			return false
		if frames % 15 == 0:
			send_motion(point)
		frames += 1
		await get_tree().process_frame
	return true

func aborted(deadline: int) -> bool:
	if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
		fail("Resize cursor run aborted: " + host.get_runtime_error())
		return true
	return false

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
