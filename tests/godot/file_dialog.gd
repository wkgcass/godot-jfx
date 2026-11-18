extends Node2D
func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("FileDialogProbe"):
		push_error("Dialog probe failed"); get_tree().quit(1); return
	var stopped:=false
	var deadline:=Time.get_ticks_msec()+60000
	while host.get_runtime_status()!="finished":
		await RenderingServer.frame_post_draw
		if not stopped and OS.get_environment("GODOT_JFX_DIALOG_STOP")=="1" and FileAccess.file_exists(OS.get_environment("GODOT_JFX_DIALOG_READY")):
			stopped=true
			host.stop_host()
			print("FILE_DIALOG_HOST_STOP_RETURNED")
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Dialog failed: "+host.get_runtime_error()); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Dialog resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_FILE_DIALOG_PASS"); get_tree().quit(0)
