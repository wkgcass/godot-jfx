extends Node2D

# Cross-application OLE drag/drop fixture: all gestures are driven by the Java
# probe through the JavaFX Robot (real Windows input); this scene only owns
# the host lifecycle and the final resource assertion.
func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "ExternalDragProbe"):
		push_error("External drag JVM failed"); get_tree().quit(1); return
	var deadline = Time.get_ticks_msec() + 60000
	while host.get_runtime_status() != "finished":
		await RenderingServer.frame_post_draw
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("External drag failed: %s" % host.get_runtime_error()); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("External drag resources leaked"); get_tree().quit(1); return
	host.free()
	print("GODOT_EXTERNAL_DRAG_PASS")
	get_tree().quit(0)
