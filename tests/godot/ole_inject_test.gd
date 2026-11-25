extends Node2D

# Only synchronization uses files. Formats, actions and completion travel over
# the Wayland data-device connection between Weston and the actual Godot JVM.
func wayland_offer(directory: String, phase: String) -> bool:
	var request := directory.path_join("request")
	var response := directory.path_join("response")
	var f := FileAccess.open(request + ".tmp", FileAccess.WRITE)
	if not f: return false
	f.store_line("%d %s" % [OS.get_process_id(), phase])
	f.close()
	if DirAccess.rename_absolute(request + ".tmp", request) != OK: return false
	var deadline := Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(response):
		if Time.get_ticks_msec() > deadline: return false
		await get_tree().process_frame
	var result := FileAccess.get_file_as_string(response).strip_edges()
	DirAccess.remove_absolute(response)
	print("WAYLAND_DND_REPLY ", phase, " ", result)
	return result == ("canceled" if phase == "timeout" else "finished")

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("OleInjectProbe"):
		push_error("OLE inject Java probe startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec()+30000
	var timeout_sent := false
	var wayland_peer := OS.get_environment("GODOT_JFX_WAYLAND_DND_DIR")
	while get_window().title != "OLE_INJECT_READY":
		if host.get_runtime_status() in ["failed","finished"] or Time.get_ticks_msec() > deadline:
			push_error("OLE inject probe startup failed: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		if OS.get_environment("GODOT_JFX_OLE_TIMEOUT") == "1" and not timeout_sent and get_window().title == "OLE_INJECT_BLOCKED":
			timeout_sent = true
			var point := get_window().position + get_window().size / 2
			if not wayland_peer.is_empty():
				if not await wayland_offer(wayland_peer, "timeout"):
					push_error("Wayland test offer did not expire"); get_tree().quit(1); return
			elif host.simulate_external_drop(point, "expired", "", PackedStringArray(), "", PackedByteArray()):
				push_error("Timed-out OLE drop accepted"); get_tree().quit(1); return
		await get_tree().process_frame
	if OS.get_environment("GODOT_JFX_OLE_TIMEOUT") == "1" and not timeout_sent:
		push_error("Timeout case did not execute"); get_tree().quit(1); return
	var window := get_window()
	var center := window.position + window.size/2
	var files := PackedStringArray(["C:/注入-a.txt","D:/inject 乙🙂.txt"])
	if OS.get_name() == "Linux":
		files = PackedStringArray(["/tmp/注入-a.txt", "/tmp/inject 乙🙂.txt"])
	var accepted: bool
	var title_observed := false
	if not wayland_peer.is_empty():
		accepted = await wayland_offer(wayland_peer, "drop")
		deadline = Time.get_ticks_msec() + 10000
		while accepted and get_window().title != "OLE_INJECT_PASS" and host.get_runtime_status() == "running" and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		title_observed = get_window().title == "OLE_INJECT_PASS"
		if title_observed:
			var ack := FileAccess.open(wayland_peer.path_join("title-observed"), FileAccess.WRITE)
			if not ack:
				push_error("Cannot acknowledge completed drop"); get_tree().quit(1); return
			ack.close()
	else:
		accepted = host.simulate_external_drop(center,"注入 OLE text 🙂","https://inject.example/路径 🙂",
				files, "application/x-godot-custom-token","注入自定义负载 🙂".to_utf8_buffer())
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
	if not accepted or not (title_observed or get_window().title == "OLE_INJECT_PASS"):
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
