extends Node2D

func click(point: Vector2, button_index: int = MOUSE_BUTTON_LEFT, window: Window = null) -> void:
	if window==null: window=get_window()
	point*=DisplayServer.screen_get_scale(window.current_screen)
	var motion := InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var button := InputEventMouseButton.new(); button.window_id=window.get_window_id(); button.position=point; button.button_index=button_index; button.pressed=pressed
		Input.parse_input_event(button)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"PopupProbe"):
		push_error("Popup JVM start failed"); get_tree().quit(1); return
	var phase:=0
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Popup test failed/timed out phase=%d: %s" % [phase,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if title.contains(" target ") and host.get_native_window_count()>0:
			var target=host.get_native_window(title.get_slice(" ",5 if title.begins_with("Combo") else 4).to_int())
			if target==null or not target.visible or target.is_present_pending(): continue
			if host.get_window_count()!=1 or target.get_window_id()==get_window().get_window_id() or not DisplayServer.get_window_list().has(target.get_window_id()) or not host.is_window_visible(title.get_slice(" ",5 if title.begins_with("Combo") else 4).to_int()):
				push_error("Popup must have its own native window and no embedded layer"); get_tree().quit(1); return
		if phase==0 and title=="Popup ready" and host.get_completed_presentations()>0:
			click(Vector2(165,35)); phase=1
		elif phase==1 and title.begins_with("Combo target 1 ") and host.get_window_count()==1 and host.get_native_window_count()==1:
			for frame in range(3): await RenderingServer.frame_post_draw
			if not await preload("res://native_popup_capture.gd").capture(host.get_native_window(title.get_slice(" ",5).to_int()),"res://../../artifacts/reference/combo-popup.png"):
				push_error("Combo popup did not render visible content"); get_tree().quit(1); return
			click(Vector2(title.get_slice(" ",3).to_float(),title.get_slice(" ",4).to_float()),MOUSE_BUTTON_LEFT,host.get_native_window(title.get_slice(" ",5).to_int())); phase=2
		elif phase==2 and title=="Combo closed 1 Two" and host.get_window_count()==1 and host.get_native_window_count()==0:
			click(Vector2(165,35)); phase=3
		elif phase==3 and title.begins_with("Combo target 2 ") and host.get_window_count()==1 and host.get_native_window_count()==1:
			click(Vector2(300,220)); phase=4
		elif phase==4 and title=="Combo closed 2 Two" and host.get_window_count()==1 and host.get_native_window_count()==0:
			click(Vector2(165,35)); phase=5
		elif phase==5 and title.begins_with("Combo target 3 ") and host.get_window_count()==1 and host.get_native_window_count()==1:
			for pressed in [true,false]:
				var key:=InputEventKey.new(); key.keycode=KEY_ESCAPE; key.pressed=pressed
				Input.parse_input_event(key)
			phase=6
		elif phase==6 and title=="Combo closed 3 Two" and host.get_window_count()==1 and host.get_native_window_count()==0:
			click(Vector2(85,155),MOUSE_BUTTON_RIGHT); phase=7
		elif phase==7 and title.begins_with("Menu target ") and host.get_window_count()==1 and host.get_native_window_count()==1:
			for frame in range(3): await RenderingServer.frame_post_draw
			if not await preload("res://native_popup_capture.gd").capture(host.get_native_window(title.get_slice(" ",4).to_int()),"res://../../artifacts/reference/context-popup.png"):
				push_error("Context popup did not render visible content"); get_tree().quit(1); return
			click(Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float()),MOUSE_BUTTON_LEFT,host.get_native_window(title.get_slice(" ",4).to_int())); phase=8
		elif phase==8 and title=="Menu action 1" and host.get_window_count()==1 and host.get_native_window_count()==0:
			for pressed in [true,false]:
				var key:=InputEventKey.new(); key.keycode=KEY_MENU; key.pressed=pressed
				Input.parse_input_event(key)
			phase=9
		elif phase==9 and title.begins_with("Menu target ") and host.get_window_count()==1 and host.get_native_window_count()==1:
			click(Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float()),MOUSE_BUTTON_LEFT,host.get_native_window(title.get_slice(" ",4).to_int())); phase=10
		elif phase==10 and title=="Menu action 2" and host.get_window_count()==1 and host.get_native_window_count()==0:
			for pressed in [true,false]:
				var key:=InputEventKey.new(); key.keycode=KEY_F10; key.shift_pressed=true; key.pressed=pressed
				Input.parse_input_event(key)
			phase=11
		elif phase==11 and title.begins_with("Menu target ") and host.get_window_count()==1 and host.get_native_window_count()==1:
			click(Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float()),MOUSE_BUTTON_LEFT,host.get_native_window(title.get_slice(" ",4).to_int())); phase=12
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if phase!=12 or DisplayServer.get_window_list().size()!=1 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Popup coverage/native window count differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Popup GPU resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_POPUPS_PASS"); get_tree().quit(0)
