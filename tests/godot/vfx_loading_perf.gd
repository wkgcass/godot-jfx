extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	var base := ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries := PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ";".join(entries), "io.vproxy.vfx.intro.VfxLoadingPerfProbe"):
		push_error("Loading performance probe JVM startup failed"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+120000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Loading performance probe failed: "+host.get_runtime_error()); get_tree().quit(1); return
		if Engine.get_process_frames() % 120 == 0: print("LOADING_STATS ",host.get_render_stats())
		await get_tree().process_frame
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await get_tree().process_frame
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Loading performance windows did not drain"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Loading performance resources retained"); get_tree().quit(1); return
	host.free()
	print("GODOT_VFX_LOADING_PERF_PASS")
	get_tree().quit()
