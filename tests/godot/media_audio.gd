extends Node

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.run_fixture_probe("MediaAudioProbe"):
		push_error("Media Java probe startup failed");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+40000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Media audio failed: "+host.get_runtime_error());get_tree().quit(1);return
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Media audio host resources retained");get_tree().quit(1);return
	host.free();print("GODOT_MEDIA_AUDIO_PASS");get_tree().quit()
