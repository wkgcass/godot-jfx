extends Node

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("ClipboardProbe"):
		push_error("Clipboard Java probe startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec()+30000
	var checked := false
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Clipboard test failed: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		if not checked and get_window().title == "Clipboard written":
			# Allow a bounded retry for transient OpenClipboard contention. A
			# mismatch can also be an external write; never assume its cause or
			# replace the expected text merely to make this check pass.
			var read_deadline := Time.get_ticks_msec()+2000
			while DisplayServer.clipboard_get() != "Godot JavaFX 中文 🙂\nsecond line":
				if Time.get_ticks_msec() > read_deadline:
					push_error("JavaFX text did not reach Windows clipboard")
					get_tree().quit(1)
					return
				await get_tree().process_frame
			var sync_path:=OS.get_environment("GODOT_JFX_CLIPBOARD_SYNC")
			var ready:=FileAccess.open(sync_path,FileAccess.WRITE)
			if ready==null:
				push_error("Clipboard external peer synchronization failed");get_tree().quit(1);return
			ready.store_string("ready");ready.close()
			checked = true
		await get_tree().process_frame
	if not checked:
		push_error("Clipboard cross-API check did not execute")
		get_tree().quit(1)
		return
	print("GODOT_CLIPBOARD_PASS")
	get_tree().quit()
