extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("io.vproxy.vfx.intro.VfxRippleProbe"):
		push_error("Ripple probe startup failed"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Ripple probe failed: "+host.get_runtime_error()); get_tree().quit(1); return
		await get_tree().process_frame
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await get_tree().process_frame
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Ripple windows did not drain"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Ripple resources retained"); get_tree().quit(1); return
	host.free()
	print("GODOT_VFX_RIPPLE_PASS")
	get_tree().quit()
