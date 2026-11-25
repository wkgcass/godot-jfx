extends Node
var saved_pointer:=Vector2i.ZERO
var pointer_saved:=false
func restore_pointer() -> void:
	if not pointer_saved: return
	for window_id in DisplayServer.get_window_list():
		if DisplayServer.window_is_focused(window_id):
			DisplayServer.warp_mouse(saved_pointer-DisplayServer.window_get_position(window_id))
			pointer_saved=false
			return
func _exit_tree() -> void:
	restore_pointer()

func _ready() -> void:
	saved_pointer=DisplayServer.mouse_get_position()
	pointer_saved=true
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("NativeImeProbe"):
		push_error("IME Java probe startup failed")
		get_tree().quit(1)
		return
	var phase := 0
	var disabled := false
	var deadline := Time.get_ticks_msec()+35000
	var last_candidate := Vector2i.ZERO
	var last_title := ""
	var last_ime_enabled := false
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("IME failed: %s phase=%d title=%s enabled=%s candidate_px=%s" % [host.get_runtime_error(), phase, last_title, last_ime_enabled, last_candidate])
			get_tree().quit(1)
			return
		var window=host.get_native_window(2)
		if window==null:
			await get_tree().process_frame
			continue
		var info=host.get_native_window_info(2)
		var title:String=window.title
		last_title = title
		last_candidate = info["ime_position"]
		last_ime_enabled = info["ime_enabled"]
		if phase == 0 and info["ime_enabled"] and title == "IME ready":
			var candidate := Vector2(last_candidate) * Vector2(400, 180) / Vector2(window.size)
			if candidate.x<20 or candidate.x>300 or candidate.y<20 or candidate.y>90:
				await get_tree().process_frame
				continue
			host.update_window_ime_composition(2,"ni🙂",3); phase=1
		elif phase == 1 and title == "IME preedit 1":
			host.update_window_ime_composition(2,"你好🙂",2); phase=2
		elif phase == 2 and title == "IME preedit 2":
			for character in "你好🙂":
				for pressed in [true,false]:
					var key := InputEventKey.new(); key.window_id=window.get_window_id(); key.pressed=pressed; key.unicode=character.unicode_at(0)
					Input.parse_input_event(key)
			phase=3
		elif phase == 3 and title == "IME committed":
			host.update_window_ime_composition(2,"取消",2); phase=4
		elif phase == 4 and title == "IME cancel ready":
			# No physical IME composition is active in this injected-event test.
			# Exercise the real DisplayServer empty-preedit query/cancel route.
			host.notification(MainLoop.NOTIFICATION_OS_IME_UPDATE); phase=5
		elif phase == 5 and title == "IME canceled":
			host.update_window_ime_composition(2,"焦点",2); phase=6
		elif phase == 6 and title == "IME focus ready":
			window.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/native-ime-before-click.png"))
			# IME completion pumps real OS events. Keep the physical pointer over
			# this target so a real WM_MOUSELEAVE cannot contradict injected clicks.
			# NativeImeProbe lays out its child Scene in 400 x 180 logical units.
			# Godot's window-local events use pixels of this particular window.
			var button_point := Vector2(80, 115) * Vector2(window.size) / Vector2(400, 180)
			DisplayServer.warp_mouse(Vector2i(button_point.round()))
			for pressed in [true,false]:
				var click := InputEventMouseButton.new(); click.window_id=window.get_window_id(); click.position=button_point; click.button_index=MOUSE_BUTTON_LEFT; click.pressed=pressed
				Input.parse_input_event(click)
			phase=7
		if phase == 7 and title == "IME done" and not info["ime_enabled"]:
			disabled=true
			restore_pointer()
		await get_tree().process_frame
	if phase != 7 or not disabled:
		push_error("IME focus/disable checks missing")
		get_tree().quit(1)
		return
	for frame in range(120):
		if host.get_native_window_count()==0 and host.get_window_count()==0: break
		await RenderingServer.frame_post_draw
	if host.get_native_window_count()!=0 or host.get_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Native IME windows were not cleaned up"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Native IME GPU resources leaked"); get_tree().quit(1); return
	host.free()
	print("GODOT_NATIVE_IME_PASS")
	get_tree().quit()

