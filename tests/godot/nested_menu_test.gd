extends Node2D

func motion(point: Vector2, window: Window = null) -> void:
	if window==null: window=get_window()
	var event:=InputEventMouseMotion.new(); event.window_id=window.get_window_id(); event.position=point*DisplayServer.screen_get_scale(window.current_screen)
	Input.parse_input_event(event)

func click(point: Vector2, button: int=MOUSE_BUTTON_LEFT, window: Window = null) -> void:
	if window==null: window=get_window()
	motion(point,window)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.window_id=window.get_window_id(); event.position=point*DisplayServer.screen_get_scale(window.current_screen); event.button_index=button; event.pressed=pressed
		Input.parse_input_event(event)

func key(code: int) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new(); event.keycode=code; event.pressed=pressed
		Input.parse_input_event(event)

func point(title: String) -> Vector2:
	return Vector2(title.get_slice(" ",3).to_float(),title.get_slice(" ",4).to_float())

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("NestedMenuProbe"):
		push_error("Nested menu Java probe start failed"); get_tree().quit(1); return
	var phase:=0
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Nested menu failed phase=%d title=%s: %s"%[phase,get_window().title,host.get_runtime_error()]); get_tree().quit(1); return
		# After outside dismissal Java may unmap every surface before its thread exits.
		if phase == 14:
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		var title:=get_window().title
		var native_count:int=host.get_native_window_count()
		if native_count>0 and title.get_slice_count(" ")==6:
			var target=host.get_native_window(title.get_slice(" ",5).to_int())
			if target==null or not target.visible or target.is_present_pending(): continue
			if host.get_window_count()!=1 or target.get_window_id()==get_window().get_window_id() or not DisplayServer.get_window_list().has(target.get_window_id()) or not host.is_window_visible(title.get_slice(" ",5).to_int()):
				push_error("Submenus must have independent native windows and no embedded layers"); get_tree().quit(1); return
		if phase==0 and title=="Nested ready" and host.get_completed_presentations()>0:
			click(Vector2(80,35),MOUSE_BUTTON_RIGHT); phase=1
		elif phase==1 and title.begins_with("Nested 1 Branch ") and native_count==1:
			key(KEY_DOWN); key(KEY_RIGHT); phase=2
		elif phase==2 and title.begins_with("Nested 1 Deeper ") and native_count==2:
			key(KEY_RIGHT); phase=3
		elif phase==3 and title.begins_with("Nested 1 Leaf ") and native_count==3:
			key(KEY_LEFT); phase=4
		elif phase==4 and title.begins_with("Nested 1 Deeper ") and native_count==2:
			key(KEY_RIGHT); phase=5
		elif phase==5 and title.begins_with("Nested 1 Leaf ") and native_count==3:
			key(KEY_ENTER); phase=6
		elif phase==6 and title=="Nested hidden 1 1" and native_count==0:
			click(Vector2(80,35),MOUSE_BUTTON_RIGHT); phase=7
		elif phase==7 and title.begins_with("Nested 2 Branch ") and native_count==1:
			motion(point(title),host.get_native_window(title.get_slice(" ",5).to_int())); phase=8
		elif phase==8 and title.begins_with("Nested 2 Deeper ") and native_count==2:
			motion(point(title),host.get_native_window(title.get_slice(" ",5).to_int())); phase=9
		elif phase==9 and title.begins_with("Nested 2 Leaf ") and native_count==3:
			for frame in range(3): await RenderingServer.frame_post_draw
			if not await preload("res://native_popup_capture.gd").capture(host.get_native_window(title.get_slice(" ",5).to_int()),"res://../../artifacts/reference/nested-menu.png"):
				push_error("Nested popup did not render visible content"); get_tree().quit(1); return
			click(point(title),MOUSE_BUTTON_LEFT,host.get_native_window(title.get_slice(" ",5).to_int())); phase=10
		elif phase==10 and title=="Nested hidden 2 2" and native_count==0:
			click(Vector2(80,35),MOUSE_BUTTON_RIGHT); phase=11
		elif phase==11 and title.begins_with("Nested 3 Branch ") and native_count==1:
			key(KEY_DOWN); key(KEY_RIGHT); phase=12
		elif phase==12 and title.begins_with("Nested 3 Deeper ") and native_count==2:
			key(KEY_RIGHT); phase=13
		elif phase==13 and title.begins_with("Nested 3 Leaf ") and native_count==3:
			click(Vector2(600,320)); phase=14
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await get_tree().process_frame
	if phase!=14 or DisplayServer.get_window_list().size()!=1 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Nested menu coverage/window count differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Nested menu resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_NESTED_MENU_PASS"); get_tree().quit(0)
