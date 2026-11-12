extends Node2D

var host: Node
var handled_title := ""
var input_scale := Vector2.ONE

# Synthetic gesture driver (default; the probe publishes commands as window
# titles). Positions are physical window-local pixels, scaled from the initial
# 420×320 logical scene using its actual window size. Each step
# targets an absolute screen point and converts to window-local using the
# current window position, so the pointer races ahead of the trailing window
# exactly like a fast physical drag. GODOT_JFX_PHYSICAL_DRAG_ROBOT=1 keeps the
# probe on the real OS cursor instead and this driver stays idle.

func press_left(window_id: int, pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.window_id = window_id
	press.position = pos
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)

func release_left(window_id: int, pos: Vector2) -> void:
	var release := InputEventMouseButton.new()
	release.window_id = window_id
	release.position = pos
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)

func drag_steps(window_id: int, screen0: Vector2, step: Vector2, count: int) -> Vector2:
	var local := screen0
	for k in range(1, count + 1):
		var target := screen0 + step * k
		var motion := InputEventMouseMotion.new()
		motion.window_id = window_id
		motion.position = target - Vector2(get_window().position)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		local = motion.position
		await get_tree().process_frame
		await get_tree().process_frame
	return local

func run_drag() -> void:
	var window_id := get_window().get_window_id()
	var local := Vector2(210, 14) * input_scale
	var screen0 := Vector2(get_window().position) + local
	press_left(window_id, local)
	for i in range(18):
		await get_tree().process_frame
	local = await drag_steps(window_id, screen0, Vector2(0, -48) * input_scale, 10)
	for i in range(36):
		await get_tree().process_frame
	release_left(window_id, local)

func run_resize() -> void:
	var window_id := get_window().get_window_id()
	var local := Vector2(412, 312) * input_scale
	var screen0 := Vector2(get_window().position) + local
	press_left(window_id, local)
	for i in range(18):
		await get_tree().process_frame
	local = await drag_steps(window_id, screen0, Vector2(40, 32) * input_scale, 8)
	for i in range(36):
		await get_tree().process_frame
	release_left(window_id, local)

func _ready() -> void:
	host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "PhysicalDragProbe"):
		fail("Physical drag JVM rejected")
		return
	var deadline := Time.get_ticks_msec() + 120000
	while get_window().title != "PhysicalDrag ready":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("Physical drag stage never appeared: " + host.get_runtime_error())
			return
		await get_tree().process_frame
	print("GD_WINDOW_RECT pos=" + str(get_window().position) + " size=" + str(get_window().size))
	input_scale = Vector2(get_window().size) / Vector2(420, 320)
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("Physical drag run aborted: " + host.get_runtime_error())
			return
		var title := get_window().title
		if title != handled_title:
			if title == "PhysicalDrag SYNTH DRAG":
				handled_title = title
				await run_drag()
			elif title == "PhysicalDrag SYNTH RESIZE":
				handled_title = title
				await run_resize()
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Physical drag host retained resources")
		return
	host.free()
	print("GODOT_PHYSICAL_DRAG_PASS")
	get_tree().quit()

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
