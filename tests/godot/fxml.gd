extends Node2D

func key(code:int,unicode:int,ctrl:bool=false) -> void:
	for pressed in [true,false]:
		# Select-all is the platform shortcut: Ctrl on Windows, Cmd(Meta) on macOS.
		var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=pressed
		if ctrl:
			if OS.has_feature("macos"): event.meta_pressed=true
			else: event.ctrl_pressed=true
		Input.parse_input_event(event)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.run_fixture_probe("FXMLProbe"):
		push_error("FXML Java probe start failed");get_tree().quit(1);return
	var step:=0
	var deadline:=Time.get_ticks_msec()+90000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("FXML failed step=%d: %s"%[step,host.get_runtime_error()]);get_tree().quit(1);return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("FXML %d "%step) or host.is_composition_pending(): continue
		var id:=title.get_slice(" ",4).to_int()
		var window=get_window() if id==0 else host.get_native_window(id)
		if window==null or (id!=0 and window.is_present_pending()) or not host.is_window_visible(id): continue
		if window.is_embedded() or DisplayServer.get_window_list().size()!=(2 if step==3 else 1):
			push_error("FXML Stage native identity differs");get_tree().quit(1);return
		var scale:=DisplayServer.screen_get_scale(window.current_screen)
		for frame in range(3): await RenderingServer.frame_post_draw
		var image:Image=window.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/fxml-%d.png"%step))
		if step==0:
			var pixel:=image.get_pixel(roundi(title.get_slice(" ",5).to_float()*scale),roundi(title.get_slice(" ",6).to_float()*scale))
			if absf(pixel.r-0.2)>0.01 or absf(pixel.g-0.4)>0.01 or absf(pixel.b-0.6)>0.01:
				push_error("FXML CSS GPU pixel differs: "+str(pixel));get_tree().quit(1);return
		if step==1:
			key(KEY_A,0,true)
			for character in "Godot测试": key(KEY_NONE,character.unicode_at(0))
		else:
			var point:=Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())*scale
			var motion:=InputEventMouseMotion.new();motion.window_id=window.get_window_id();motion.position=point;Input.parse_input_event(motion)
			for pressed in [true,false]:
				var event:=InputEventMouseButton.new();event.window_id=window.get_window_id();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if step!=4 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("FXML coverage/drain incomplete");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("FXML resources retained");get_tree().quit(1);return
	host.free();print("GODOT_FXML_PASS");get_tree().quit()
