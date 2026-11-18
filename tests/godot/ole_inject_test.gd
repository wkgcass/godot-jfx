extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("OleInjectProbe"):
		push_error("OLE inject Java probe startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec()+30000
	var timeout_sent := false
	while get_window().title != "OLE_INJECT_READY":
		if host.get_runtime_status() in ["failed","finished"] or Time.get_ticks_msec() > deadline:
			push_error("OLE inject probe startup failed: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		if OS.get_environment("GODOT_JFX_OLE_TIMEOUT") == "1" and not timeout_sent and get_window().title == "OLE_INJECT_BLOCKED":
			timeout_sent = true
			var point := get_window().position + get_window().size / 2
			if host.simulate_external_drop(point, "expired", "", PackedStringArray(), "", PackedByteArray()):
				push_error("Timed-out OLE drop accepted"); get_tree().quit(1); return
		await get_tree().process_frame
	if OS.get_environment("GODOT_JFX_OLE_TIMEOUT") == "1" and not timeout_sent:
		push_error("Timeout case did not execute"); get_tree().quit(1); return
	var window := get_window()
	var center := window.position + window.size/2
	var accepted = host.simulate_external_drop(center,"注入 OLE text 🙂","https://inject.example/路径 🙂",
			PackedStringArray(["C:/注入-a.txt","D:/inject 乙🙂.txt"]),
			"application/x-godot-custom-token","注入自定义负载 🙂".to_utf8_buffer())
	# Let the Java probe close its stage and publish its failure before ending
	# the host; an immediate quit would interrupt failure cleanup.
	deadline = Time.get_ticks_msec()+30000
	while host.get_runtime_status() == "running":
		if Time.get_ticks_msec() > deadline:
			push_error("OLE inject probe failed: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		await get_tree().process_frame
	if host.get_runtime_status() != "finished":
		push_error("OLE inject runtime failed: "+host.get_runtime_error())
		get_tree().quit(1)
		return
	if not accepted or get_window().title != "OLE_INJECT_PASS":
		push_error("OLE inject drop did not reach the probe")
		get_tree().quit(1)
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("OLE inject host retained resources")
		host.free()
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_OLE_INJECT_PASS")
	get_tree().quit()
