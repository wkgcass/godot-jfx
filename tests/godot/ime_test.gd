extends Node

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("ImeProbe"):
		push_error("IME Java probe startup failed")
		get_tree().quit(1)
		return
	var phase := 0
	var disabled := false
	var deadline := Time.get_ticks_msec()+35000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("IME failed: "+host.get_runtime_error()+" phase="+str(phase))
			get_tree().quit(1)
			return
		var title := get_window().title
		if phase == 0 and host.is_ime_active() and title == "IME ready":
			host.update_ime_composition("ni🙂",3); phase=1
		elif phase == 1 and title == "IME preedit 1":
			host.update_ime_composition("你好🙂",2); phase=2
		elif phase == 2 and title == "IME preedit 2":
			for character in "你好🙂":
				for pressed in [true,false]:
					var key := InputEventKey.new(); key.pressed=pressed; key.unicode=character.unicode_at(0)
					Input.parse_input_event(key)
			phase=3
		elif phase == 3 and title == "IME committed":
			host.update_ime_composition("取消",2); phase=4
		elif phase == 4 and title == "IME cancel ready":
			# No physical IME composition is active in this injected-event test.
			# Exercise the real DisplayServer empty-preedit query/cancel route.
			host.notification(MainLoop.NOTIFICATION_OS_IME_UPDATE); phase=5
		elif phase == 5 and title == "IME canceled":
			host.update_ime_composition("焦点",2); phase=6
		elif phase == 6 and title == "IME focus ready":
			for pressed in [true,false]:
				var click := InputEventMouseButton.new(); click.position=Vector2(80,115) * Vector2(get_window().size) / Vector2(400,180); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=pressed
				Input.parse_input_event(click)
				if OS.get_environment("GODOT_JFX_IME_SPACED_CLICK") == "1":
					await get_tree().process_frame
					await get_tree().process_frame
			phase=7
		if phase == 7 and title == "IME done" and not host.is_ime_active(): disabled=true
		await get_tree().process_frame
	if phase != 7 or not disabled:
		push_error("IME focus/disable checks missing")
		get_tree().quit(1)
		return
	print("GODOT_IME_PASS")
	get_tree().quit()
