extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("io.vproxy.vfx.intro.VfxMenuPerformanceProbe"):
		push_error("Menu performance probe startup failed"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Menu performance probe failed: "+host.get_runtime_error()); get_tree().quit(1); return
		if Engine.get_process_frames() % 120 == 0: print("MENU_STATS ",host.get_render_stats())
		await get_tree().process_frame
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await get_tree().process_frame
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Menu performance windows did not drain"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Menu performance resources retained"); get_tree().quit(1); return
	host.free()
	print("GODOT_VFX_MENU_PERFORMANCE_PASS")
	get_tree().quit()
