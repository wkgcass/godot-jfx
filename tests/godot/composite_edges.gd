extends Node2D
func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("CompositeEdgeProbe"):
		push_error("Edge probe rejected"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+40000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec()>deadline:
			push_error("Edge probe failed: "+host.get_runtime_error()); get_tree().quit(1); return
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Edge probe host resources leaked"); get_tree().quit(1); return
	host.free()
	print("GODOT_COMPOSITE_EDGES_PASS")
	get_tree().quit()
