extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("HostStopProbe"):
		push_error("Host stop Java probe start failed"); get_tree().quit(1); return
	var deadline:=Time.get_ticks_msec()+30000
	while get_window().title!="Host stop ready" or host.get_native_window_count()!=2 or DisplayServer.get_window_list().size()!=3 or host.is_composition_pending():
		if Time.get_ticks_msec()>deadline:
			push_error("Host stop setup timed out"); get_tree().quit(1); return
		await get_tree().process_frame
	host.stop_host()
	# The host deliberately stays in the tree: stopping must not depend on free().
	if host.get_native_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Explicit stop retained native windows: %d"%host.get_native_window_count())
		get_tree().quit(1); return
	host.stop_host() # Idempotent, including already removed owner/child windows.
	print("HOST_STOP_NATIVE_WINDOWS_REMOVED")
	deadline=Time.get_ticks_msec()+15000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Host stop probe did not finish: "+host.get_runtime_error()); get_tree().quit(1); return
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Host removal retained resources"); get_tree().quit(1); return
	host.free()
	print("HOST_STOP_NATIVE_WINDOWS_PASS")
	get_tree().quit()
