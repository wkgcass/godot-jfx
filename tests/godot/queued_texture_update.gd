extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	var sdk := ProjectSettings.globalize_path("res://../../jfx/build/sdk")
	var classes := ProjectSettings.globalize_path("res://../../artifacts/reference")
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), sdk, classes, "QueuedTextureUpdateProbe"):
		push_error("Queued texture probe JVM startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Queued texture probe failed: " + host.get_runtime_error())
			host.stop_jvm()
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var viewport_state := OS.get_environment("GODOT_JFX_TEST_VIEWPORT_STATE") == "1"
	var commits := int(host.get_render_stats().get("rd_batch_commits",0))
	if viewport_state and commits != 0:
		push_error("Viewport state fixture unexpectedly used RD batching"); get_tree().quit(1); return
	if not viewport_state and commits < 1:
		push_error("Queued texture fixture did not exercise RD batching"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Queued texture fixture retained resources"); host.free(); get_tree().quit(1); return
	host.free()
	print("GODOT_QUEUED_TEXTURE_UPDATE_PASS")
	get_tree().quit(0)
