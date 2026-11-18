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

func point(title: String) -> Vector2:
	return Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("PopupEdgeProbe"):
		push_error("Popup edge Java probe start failed"); get_tree().quit(1); return
	var phase:=0
	var last_title:=""
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Popup edge failed phase=%d title=%s: %s"%[phase,get_window().title,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if title!=last_title:
			print("EDGE_STATE phase=%d layers=%d title=%s"%[phase,host.get_window_count(),title]); last_title=title
		var native_count:int=host.get_native_window_count()
		if phase==0 and title.begins_with("Edge ready ") and host.get_completed_presentations()>0:
			var reported:=Rect2i(title.get_slice(" ",2).to_int(),title.get_slice(" ",3).to_int(),title.get_slice(" ",4).to_int(),title.get_slice(" ",5).to_int())
			var index:=DisplayServer.get_primary_screen()
			var scale:=DisplayServer.screen_get_scale(index)
			var origin:=DisplayServer.screen_get_position(index)
			var native_work:=DisplayServer.screen_get_usable_rect(index)
			var expected:=Rect2i(origin+Vector2i((Vector2(native_work.position-origin)/scale).round()),Vector2i((Vector2(native_work.size)/scale).round()))
			if reported!=expected:
				push_error("JavaFX visual bounds differ from native usable screen area"); get_tree().quit(1); return
			click(Vector2(310,195)); phase=1
		elif phase==1 and title.begins_with("Edge Two ") and native_count==1:
			# The native configure queue is independent of the title host
			# command: the title can appear before the popup window is
			# realized. An unrealized window has no window_id, so a click
			# would fall back to the root window and auto-hide the popup.
			if host.get_native_window_info(title.get_slice(" ",4).to_int()).get("visible",false):
				click(point(title),MOUSE_BUTTON_LEFT,host.get_native_window(title.get_slice(" ",4).to_int())); phase=2
		elif phase==2 and title=="Edge selected" and native_count==0:
			click(Vector2(310,155),MOUSE_BUTTON_RIGHT); phase=3
		elif phase==3 and title.begins_with("Edge More ") and native_count==1:
			if host.get_native_window_info(title.get_slice(" ",4).to_int()).get("visible",false):
				motion(point(title),host.get_native_window(title.get_slice(" ",4).to_int())); phase=4
		elif phase==4 and title.begins_with("Edge Run ") and native_count==2:
			if not host.get_native_window_info(title.get_slice(" ",4).to_int()).get("visible",false): continue
			for frame in range(3): await RenderingServer.frame_post_draw
			if not await preload("res://native_popup_capture.gd").capture(host.get_native_window(title.get_slice(" ",4).to_int()),"res://../../artifacts/reference/popup-edge.png"):
				push_error("Edge menu has no rendered content"); get_tree().quit(1); return
			click(point(title),MOUSE_BUTTON_LEFT,host.get_native_window(title.get_slice(" ",4).to_int())); phase=5
		elif phase==5 and title=="Edge fixed" and native_count==1:
			click(Vector2(40,25)); phase=6
		elif phase==6 and title=="Edge unfixed" and native_count==1:
			click(Vector2(40,25)); phase=7
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if phase!=7 or DisplayServer.get_window_list().size()!=1 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Popup edge coverage/window count differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Popup edge resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_POPUP_EDGE_PASS"); get_tree().quit(0)
