extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("MediaPlanesProbe"):
		fail("Video planes probe rejected"); return
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("Video planes failed: " + host.get_runtime_error()); return
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	host.clear_commands()
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Video planes resources leaked"); return
	host.free()
	print("GODOT_MEDIA_PLANES_PASS")
	get_tree().quit()

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
