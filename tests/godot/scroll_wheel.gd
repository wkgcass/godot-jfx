extends Node2D

var host: Node

func _ready() -> void:
	host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "ScrollWheelProbe"):
		fail("Scroll wheel JVM rejected")
		return
	var deadline := Time.get_ticks_msec() + 60000
	while get_window().title != "ScrollWheel ready" or host.get_completed_presentations() == 0:
		if aborted(deadline): return
		await get_tree().process_frame
	var window_id := get_window().get_window_id()
	for k in range(3):
		var wheel := InputEventMouseButton.new()
		wheel.window_id = window_id
		wheel.position = Vector2(150, 150)
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.factor = 1.0
		Input.parse_input_event(wheel)
		for i in range(15):
			if aborted(deadline): return
			await get_tree().process_frame
	while host.get_runtime_status() != "finished":
		if aborted(deadline): return
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Scroll wheel host retained resources")
		return
	host.free()
	print("GODOT_SCROLL_WHEEL_PASS")
	get_tree().quit()

func aborted(deadline: int) -> bool:
	if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
		fail("Scroll wheel run aborted: " + host.get_runtime_error())
		return true
	return false

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
