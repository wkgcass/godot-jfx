# Loaded by the --smoke launcher only. Exercise the window/Glass input path without OS input.
extends Node

var room
var errors := PackedStringArray()

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func wait_state(expected: int) -> bool:
	for i in 100:
		if room.device_state == expected:
			return true
		await get_tree().create_timer(0.05).timeout
	return false

func button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	get_window().push_input(event, true)

func click(target: Vector3) -> void:
	room.camera.look_at(target)
	button(true)
	button(false)
	await get_tree().physics_frame

func walk(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = pressed
	Input.parse_input_event(key)
	Input.flush_buffered_events()

func walk_and_click(mouse_first: bool, expected_state: int) -> void:
	var light_button := Vector3(-0.935, 1.224, -3.37)
	room.camera.look_at(light_button)
	if mouse_first:
		button(true)
	var origin: Vector3 = room.player.position
	var yaw: float = room.player.rotation.y
	walk(true)
	if not mouse_first:
		button(true)
	for i in 8:
		# Track the same button as the player walks past it.
		room.camera.look_at(light_button)
		var turn := InputEventMouseMotion.new()
		turn.button_mask = MOUSE_BUTTON_MASK_LEFT
		turn.screen_relative = Vector2(0.5, 0)
		get_window().push_input(turn, true)
		await get_tree().physics_frame
	check(room.player.position.distance_to(origin) > 0.12 and room.player.rotation.y < yaw - 0.005,
		"Held W and mouse look did not move and turn together")
	check(room.button_down, "Walking or turning cancelled the held panel button")
	if mouse_first:
		walk(false)
		await get_tree().physics_frame
		check(room.button_down, "Key release cancelled the held panel button")
	room.camera.look_at(light_button)
	button(false)
	if not mouse_first:
		origin = room.player.position
		for i in 5:
			await get_tree().physics_frame
		check(room.player.position.distance_to(origin) > 0.09, "Mouse release stopped W movement")
		walk(false)
	check(await wait_state(expected_state), "Panel click during movement did not toggle the light")

func run() -> void:
	room = get_tree().current_scene
	check(await wait_state(29), "JavaFX did not publish the initial state")
	await get_tree().create_timer(0.6).timeout
	var output := OS.get_environment("VFX_ROOM_PREVIEW")
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		check(get_window().get_texture().get_image().save_png(output) == OK, "Cannot save room preview")
	button(true)
	button(false)
	check(room.captured and DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED, "First click did not capture the mouse")
	var turn := InputEventMouseMotion.new()
	turn.screen_relative = Vector2(65, 24)
	var old_yaw: float = room.player.rotation.y
	get_window().push_input(turn, true)
	check(room.player.rotation.y < old_yaw and room.camera.rotation.x < 0, "Mouse look did not rotate the camera")
	await walk_and_click(false, 28)
	await walk_and_click(true, 29)
	var light := Vector3(-0.935,1.224,-3.37)
	var power := Vector3(0.54,1.224,-3.37)
	var plus := Vector3(1.44,1.224,-3.37)
	var minus := Vector3(1.10,1.224,-3.37)
	await click(light)
	check(await wait_state(28) and room.get_node("Interior").lamps[0].light_energy == 0, "Light switch did not turn off the lamp")
	# Let the asynchronous Glass hover cursor reach the display server.
	await get_tree().create_timer(0.35).timeout
	check(DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED, "JavaFX hover released the OS mouse grab")
	await click(power)
	check(await wait_state(30), "AC power did not turn on")
	await click(plus)
	check(await wait_state(34), "AC setpoint did not increase")
	await click(minus)
	check(await wait_state(30), "AC setpoint did not decrease")
	await click(power)
	check(await wait_state(28), "AC power did not turn off")
	await click(plus)
	await click(Vector3(0,1.54,-3.5))
	await get_tree().create_timer(0.3).timeout
	check(room.device_state == 28, "Standby or a click between panels changed a device")
	await click(light)
	check(await wait_state(29), "Light switch did not turn on the lamp")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_window().push_input(escape, true)
	check(not room.captured and not room.button_down and DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_VISIBLE, "Escape did not release input")
	button(true)
	button(false)
	await get_tree().create_timer(0.25).timeout
	check(DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED, "Second click did not recapture the mouse")
	get_window().focus_exited.emit()
	check(DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_VISIBLE, "Focus loss did not release the mouse")
	var file := FileAccess.open(String(ProjectSettings.get_setting("room/session")).path_join("result.txt"), FileAccess.WRITE)
	file.store_string("PASS" if errors.is_empty() else "\n".join(errors))
	file.close()
	get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
