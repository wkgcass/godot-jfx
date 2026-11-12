extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	var sdk := ProjectSettings.globalize_path("res://../../jfx/build/sdk")
	var classes := ProjectSettings.globalize_path("res://../../artifacts/reference")
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), sdk, classes, "VirtualKeyboardProbe"):
		push_error("Virtual keyboard probe JVM startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Virtual keyboard probe failed: " + host.get_runtime_error())
			host.stop_jvm()
			get_tree().quit(1)
			return
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Virtual keyboard host retained resources"); get_tree().quit(1); return
	host.free()
	print("GODOT_VIRTUAL_KEYBOARD_PASS")
	get_tree().quit(0)
