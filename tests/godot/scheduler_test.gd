extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("GlassSchedulerProbe"):
		push_error("Scheduler probe startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Scheduler probe failed: " + host.get_runtime_error())
			host.stop_host()
			get_tree().quit(1)
			return
		await get_tree().process_frame
	remove_child(host)
	host.free()
	print("M2_GLASS_SCHEDULER_PASS")
	get_tree().quit(0)
