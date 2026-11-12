extends Node2D
func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	var probe:=OS.get_environment("GODOT_JFX_FAILURE_PROBE")
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),probe):
		push_error("Failure JVM start failed"); get_tree().quit(1); return
	var deadline:=Time.get_ticks_msec()+20000
	var saw_native:=false
	while host.get_runtime_status()!="failed":
		saw_native=saw_native or host.get_native_window_count()==2
		if Time.get_ticks_msec()>deadline or host.get_runtime_status()=="finished":
			push_error("Injected failure missing"); get_tree().quit(1); return
		await get_tree().process_frame
	for frame in range(120):
		if host.get_native_window_count()==0 and host.get_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if not saw_native or host.get_native_window_count()!=0 or host.get_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("Failed application did not drain windows"); get_tree().quit(1); return
	if host.get_runtime_error()!="Java application failed; see JVM exception in the host log":
		push_error("Original application failure was replaced"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Failed application leaked GPU resources"); get_tree().quit(1); return
	host.free(); print("GODOT_FAILURE_SHUTDOWN_PASS"); get_tree().quit(0)
