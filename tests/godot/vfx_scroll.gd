extends Node2D

func drag(point:Vector2, delta:Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.window_id=get_window().get_window_id();motion.position=point;Input.parse_input_event(motion);Input.flush_buffered_events()
	var press:=InputEventMouseButton.new();press.window_id=get_window().get_window_id();press.position=point;press.button_index=MOUSE_BUTTON_LEFT;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.pressed=true;Input.parse_input_event(press)
	motion=InputEventMouseMotion.new();motion.window_id=get_window().get_window_id();motion.position=point+delta;motion.relative=delta;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion);Input.flush_buffered_events()
	var release:=InputEventMouseButton.new();release.window_id=get_window().get_window_id();release.position=point+delta;release.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(release)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.run_fixture_probe("VfxScrollProbe"):
		push_error("VFX scroll probe failed");get_tree().quit(1);return
	var step:=0
	var baseline:Image
	var previous:Image
	var deadline:=Time.get_ticks_msec()+240000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("VFX scroll failed step=%d: %s"%[step,host.get_runtime_error()]);get_tree().quit(1);return
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("VfxScroll %d "%step) or host.is_composition_pending(): continue
		if host.get_render_stats()["completed_render_sequence"]<title.get_slice(" ",6).to_int(): continue
		var scale:=DisplayServer.screen_get_scale(get_window().current_screen)
		var rect:=Rect2i(Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())*scale,Vector2(title.get_slice(" ",4).to_float(),title.get_slice(" ",5).to_float())*scale)
		var image:=get_window().get_texture().get_image()
		if step==0: baseline=image
		else:
			for x in [rect.position.x-8,rect.end.x+8]:
				for y in range(rect.position.y+120,rect.end.y-16,16):
					if image.get_pixel(x,y)!=baseline.get_pixel(x,y):
						push_error("Long table content escaped horizontal clip");get_tree().quit(1);return
			if step in [1,2]:
				var changed:=0
				for x in range(rect.position.x+40,rect.end.x-40,8):
					for y in range(rect.position.y+120,rect.end.y-16,8):
						if image.get_pixel(x,y)!=previous.get_pixel(x,y): changed+=1
				if changed<100:
					image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-scroll-failed-%d.png"%step))
					print("VFX_SCROLL_STALE title=",title," stats=",host.get_render_stats())
					push_error("Scroll state changed without visible table movement");get_tree().quit(1);return
				print("VFX_SCROLL_PIXEL_CHANGE step=",step," samples=",changed)
		image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-scroll-%d.png"%step))
		previous=image
		if step in [0,3]: drag(Vector2(rect.position)+Vector2(rect.size.x/2.0,50*scale),Vector2((-250 if step==0 else 250)*scale,0))
		else:
			var event:=InputEventMouseButton.new();event.window_id=get_window().get_window_id();event.position=Vector2(rect.position)+Vector2(rect.size.x/2.0,200*scale);event.button_index=MOUSE_BUTTON_WHEEL_DOWN if step==1 else MOUSE_BUTTON_WHEEL_UP;event.factor=1000;event.pressed=true;Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and not host.is_composition_pending(): break
		await get_tree().process_frame
	if step!=4 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("VFX scroll coverage/drain incomplete");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("VFX scroll leaked resources");get_tree().quit(1);return
	host.free();print("GODOT_VFX_SCROLL_PASS");get_tree().quit()
