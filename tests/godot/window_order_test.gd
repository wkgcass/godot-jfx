extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("WindowOrderProbe"):
		push_error("Order Java probe start failed"); get_tree().quit(1); return
	var seen:={}
	var deadline:=Time.get_ticks_msec()+30000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Order failed/timed out: "+host.get_runtime_error()); get_tree().quit(1); return
		await get_tree().process_frame
		var title:=get_window().title
		if not title.begins_with("Order "): continue
		var index:=title.get_slice(" ",1).to_int()
		if seen.has(index): continue
		var top_id:int=3 if index in [0,4,9] else (4 if index in [6,7] else 2)
		var top=host.get_native_window(top_id)
		var count:=3 if index in [6,7] else (1 if index==9 else 2)
		if top==null or top.is_embedded() or top.get_content_size()==Vector2i.ZERO or top.is_present_pending(): continue
		if host.get_native_window_count()!=count or DisplayServer.get_window_list().size()!=count+1: continue
		var scale:=DisplayServer.screen_get_scale(get_window().current_screen)
		if host.get_surface_size()!=Vector2i(Vector2(320,220)*scale): continue
		var visible_on_top:bool=host.is_window_above(top_id,0)
		for id in [2,3,4]:
			if id!=top_id and host.get_native_window(id)!=null:
				visible_on_top=visible_on_top and host.is_window_above(top_id,id)
		if not visible_on_top: continue
		# All windows in this phase are visible. Read the presented viewport
		# after drawing; the final hidden window need not produce another frame.
		await RenderingServer.frame_post_draw
		var screen_point:=get_window().position+Vector2i(Vector2(120,100)*scale)
		var sample:Vector2i=screen_point-top.position
		var image:Image=top.get_texture().get_image()
		if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(sample): continue
		var expected:=Color.GREEN if top_id==3 else (Color(0.5,0,0.5) if top_id==4 else Color.BLUE)
		var actual:=image.get_pixelv(sample)
		if absf(actual.r-expected.r)>.04 or absf(actual.g-expected.g)>.04 or absf(actual.b-expected.b)>.04:
			push_error("Window order pixel differs at %d: %s" % [index,actual]);get_tree().quit(1);return
		if image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/window-order-%d.png" % index)) != OK:
			push_error("Cannot save window order capture %d" % index); get_tree().quit(1); return
		seen[index]=true
	while (host.get_window_count()!=0 or DisplayServer.get_window_list().size()!=1) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if seen.size()!=10 or host.get_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Window order coverage/cleanup differs: phases="+str(seen.keys())); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Order GPU resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_WINDOW_ORDER_PASS"); get_tree().quit(0)
