extends Node2D

var host: Node
var injected := 0

func pan(delta: Vector2) -> void:
	var event := InputEventPanGesture.new()
	event.window_id = get_window().get_window_id()
	event.position = Vector2(200, 150)
	event.delta = delta
	Input.parse_input_event(event)
	injected += 1

func _ready() -> void:
	host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("PanScrollProbe"):
		fail("Pan scroll probe rejected")
		return
	var deadline := Time.get_ticks_msec() + 120000
	while true:
		var t := get_window().title
		if (t.begins_with("PanScroll ready") or t.begins_with("PAN ")) and host.get_completed_presentations() > 0:
			break
		if aborted(deadline): return
		await get_tree().process_frame
	# The probe drives phases through the stage title; stream 5 events per frame
	# while a scrolling phase is active (8px per event, signed by direction).
	while host.get_runtime_status() != "finished":
		if aborted(deadline): return
		var title := get_window().title
		if title.begins_with("PAN "):
			var phase := title.substr(4)
			if phase == "down" or phase == "over":
				for n in range(5): pan(Vector2(0, 8))
			elif phase == "up" or phase == "overUp":
				for n in range(5): pan(Vector2(0, -8))
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Pan scroll host retained resources")
		return
	host.free()
	print("PAN_INJECTED total=", injected)
	print("GODOT_SCROLL_PAN_PASS")
	get_tree().quit()

func aborted(deadline: int) -> bool:
	if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
		fail("Pan scroll run aborted: " + host.get_runtime_error())
		return true
	return false

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
