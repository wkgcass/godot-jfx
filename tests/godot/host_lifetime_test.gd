extends Node2D

func click(point: Vector2, window: Window) -> void:
	point*=DisplayServer.screen_get_scale(window.current_screen)
	var motion:=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.window_id=window.get_window_id(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
		Input.parse_input_event(event)

func matches(a: Color,b: Color) -> bool:
	return absf(a.r-b.r)<.04 and absf(a.g-b.g)<.04 and absf(a.b-b.b)<.04

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("HostLifetimeProbe"):
		push_error("Lifetime Java probe start failed"); get_tree().quit(1); return
	var phase:=0
	var deadline:=Time.get_ticks_msec()+35000
	var diagnostic:=Time.get_ticks_msec()+3000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Host lifetime failed phase=%d: %s"%[phase,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		if Time.get_ticks_msec()>diagnostic:
			print("LIFETIME_STATE phase=",phase," root_visible=",host.is_window_visible(0)," child_visible=",host.is_window_visible(2)," child=",host.get_native_window_info(2))
			diagnostic=Time.get_ticks_msec()+5000
		if host.get_completed_presentations()==0: continue
		var survivor=host.get_native_window(2)
		if survivor==null or survivor.is_present_pending(): continue
		var image:Image=survivor.get_texture().get_image()
		var scale:=DisplayServer.screen_get_scale(survivor.current_screen)
		var sample:=Vector2i(Vector2(130,80)*scale)
		if image.get_width()!=roundi(140*scale) or image.get_height()!=roundi(90*scale): continue
		if phase==0 and get_window().title=="Lifetime ready" and host.get_window_count()==1 and host.get_native_window_count()==1 and matches(image.get_pixelv(sample),Color.BLUE):
			if not host.is_window_visible(0) or not host.is_window_visible(2):
				continue # Native visibility acknowledgement may follow the first GPU frame.
			click(Vector2(40,30),get_window()); phase=1
		elif phase==1 and get_window().title=="Lifetime surviving" and host.get_window_count()==0 and matches(image.get_pixelv(sample),Color.BLUE):
			if host.is_window_visible(0) or not host.is_window_visible(2):
				continue # Wait for queued primary hide and independent native show.
			click(Vector2(40,30),survivor); phase=2
		elif phase==2 and matches(image.get_pixelv(sample),Color.GREEN):
			for pressed in [true,false]:
				var event:=InputEventKey.new(); event.window_id=survivor.get_window_id(); event.keycode=KEY_SPACE; event.unicode=32; event.pressed=pressed
				Input.parse_input_event(event)
			phase=3
		elif phase==3 and host.get_native_window_count()==2 and matches(image.get_pixelv(sample),Color.CYAN):
			var third=host.get_native_window(3)
			if third==null or third.is_present_pending(): continue
			var third_image:Image=third.get_texture().get_image()
			if third_image.get_width()!=roundi(140*scale) or third_image.get_height()!=roundi(70*scale) or not matches(third_image.get_pixelv(Vector2i(Vector2(130,60)*scale)),Color.YELLOW): continue
			if not host.is_window_visible(3): continue
			if host.get_surface_size()!=Vector2i(Vector2(360,230)*scale) or host.get_window_count()!=0 or host.is_window_visible(0) or not host.is_window_visible(2) or not host.is_window_visible(3) or DisplayServer.get_window_list().size()!=3:
				push_error("New Stage took over primary or lost independent native visibility"); get_tree().quit(1); return
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/host-lifetime-survivor.png"))
			third_image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/host-lifetime-third.png"))
			click(Vector2(40,30),third); phase=4
	# Probe completion precedes consumption of the final queued layer removals.
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if phase!=4 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("Lifetime coverage/cleanup differs phase=%d layers=%d"%[phase,host.get_window_count()]); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Lifetime resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_HOST_LIFETIME_PASS"); get_tree().quit(0)

