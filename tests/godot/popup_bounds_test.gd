extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("PopupBoundsProbe"):
		push_error("Popup bounds Java probe start failed"); get_tree().quit(1); return
	var step:=0
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Popup bounds failed step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("Bounds ready %d "%step): continue
		var scale:=DisplayServer.screen_get_scale()
		var size:=Vector2i(Vector2(title.get_slice(" ",5).to_float(),title.get_slice(" ",6).to_float())*scale)
		if host.get_surface_size()!=size: continue
		if host.get_window_count()!=1 or host.get_native_window_count()!=(0 if step==6 else 1): continue
		if step!=6:
			var id:=title.get_slice(" ",7).to_int()
			var popup=host.get_native_window(id)
			if popup==null or popup.is_present_pending(): continue
			if popup.get_window_id()==get_window().get_window_id() or not host.is_window_visible(id):
				push_error("Bounds popup must be an independently visible native window"); get_tree().quit(1); return
			var origin:=Vector2(DisplayServer.screen_get_position(DisplayServer.get_primary_screen()))
			var expected:=(origin+(Vector2(title.get_slice(" ",3).to_float(),title.get_slice(" ",4).to_float())-origin)*scale).round()
			if Vector2(popup.position).distance_to(expected)>1: continue
			var pos:=Vector2i(Vector2(30,20)*scale)
			var image:Image=popup.get_texture().get_image()
			if pos.x<0 or pos.y<0 or pos.x>=image.get_width() or pos.y>=image.get_height(): continue
			var color:=image.get_pixelv(pos)
			if color.r<.95 or absf(color.g-.647)>.04 or color.b>.04: continue
			if step==7: image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/popup-bounds.png"))
		for pressed in [true,false]:
			var event:=InputEventKey.new(); event.keycode=KEY_F6; event.pressed=pressed
			Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if step!=8 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("Popup bounds coverage/window cleanup differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Popup bounds resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_POPUP_BOUNDS_PASS"); get_tree().quit(0)
