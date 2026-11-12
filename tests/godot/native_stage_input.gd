extends Node2D
func click(window, point:Vector2) -> void:
	point*=DisplayServer.screen_get_scale(window.current_screen)
	var motion:=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.window_id=window.get_window_id(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
		Input.parse_input_event(event)
func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"NativeStageInputProbe"):
		push_error("Native input JVM failed"); get_tree().quit(1); return
	var step:=0
	var deadline:=Time.get_ticks_msec()+35000
	var diagnostic:=Time.get_ticks_msec()+5000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Native input failed step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		if Time.get_ticks_msec()>diagnostic:
			print("NATIVE_INPUT_STATE step=",step," title=",get_window().title," root_focus=",get_window().has_focus()," child=",host.get_native_window_info(2))
			diagnostic=Time.get_ticks_msec()+5000
		if get_window().title!="Native input %d"%step or host.is_composition_pending(): continue
		var child=host.get_native_window(2)
		if step!=7 and (child==null or child.is_present_pending()): continue
		match step:
			0:
				if not child.has_focus(): continue
				click(child,Vector2(40,30))
			1:
				if not get_window().has_focus(): continue
				click(get_window(),Vector2(40,30))
			2:
				if not child.has_focus(): continue
				click(child,Vector2(40,85))
				for pressed in [true,false]:
					var event:=InputEventKey.new(); event.window_id=child.get_window_id(); event.keycode=KEY_A; event.unicode=97; event.pressed=pressed
					Input.parse_input_event(event)
			3:
				var event:=InputEventMouseButton.new(); event.window_id=child.get_window_id(); event.position=Vector2(150,120)*DisplayServer.screen_get_scale(child.current_screen); event.button_index=MOUSE_BUTTON_WHEEL_UP; event.pressed=true
				Input.parse_input_event(event)
			4:
				var event:=InputEventMouseButton.new(); event.window_id=child.get_window_id(); event.position=Vector2(40,30)*DisplayServer.screen_get_scale(child.current_screen); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
				Input.parse_input_event(event)
				step=40
				continue
			40:
				if not get_window().has_focus(): continue
				var release:=InputEventMouseButton.new(); release.window_id=child.get_window_id(); release.position=Vector2(40,30)*DisplayServer.screen_get_scale(child.current_screen); release.button_index=MOUSE_BUTTON_LEFT; release.pressed=false
				Input.parse_input_event(release)
				child.grab_focus()
				for pressed in [true,false]:
					var event:=InputEventScreenTouch.new(); event.window_id=child.get_window_id(); event.index=0; event.position=Vector2(40,30)*DisplayServer.screen_get_scale(child.current_screen); event.pressed=pressed
					Input.parse_input_event(event)
				step=5
				continue
			5: child.emit_signal("close_requested")
			6:
				if not child.visible: push_error("Vetoed native close hid window"); get_tree().quit(1); return
				child.emit_signal("close_requested")
			7:
				if child!=null or DisplayServer.get_window_list().size()!=1: continue
				click(get_window(),Vector2(40,30))
		step+=1
	if step!=8: push_error("Native input coverage incomplete"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Native input resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_NATIVE_STAGE_INPUT_PASS"); get_tree().quit(0)

