extends Node2D
func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("RobotProbe"):
		push_error("Robot probe failed"); get_tree().quit(1); return
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		await RenderingServer.frame_post_draw
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Robot failed: "+host.get_runtime_error()); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Robot resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_ROBOT_PASS"); get_tree().quit(0)
