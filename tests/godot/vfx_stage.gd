extends Node2D

func drag_corner(window:Window, delta:Vector2) -> void:
	var scale:=DisplayServer.screen_get_scale(window.current_screen)
	var start:=Vector2(window.size)-Vector2(4,4)*scale
	var motion:=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=start; Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var press:=InputEventMouseButton.new(); press.window_id=window.get_window_id(); press.position=start; press.button_index=MOUSE_BUTTON_LEFT; press.button_mask=MOUSE_BUTTON_MASK_LEFT; press.pressed=true; Input.parse_input_event(press)
	motion=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=start+delta*scale; motion.relative=delta*scale; motion.button_mask=MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var release:=InputEventMouseButton.new(); release.window_id=window.get_window_id(); release.position=start+delta*scale; release.button_index=MOUSE_BUTTON_LEFT; release.pressed=false; Input.parse_input_event(release)

func wait_size(window:Window, logical:Vector2) -> bool:
	var target:=Vector2i(logical*DisplayServer.screen_get_scale(window.current_screen))
	var deadline:=Time.get_ticks_msec()+10000
	while window.size!=target or window.is_present_pending() or window.get_content_size()!=target:
		if Time.get_ticks_msec()>deadline:
			print("VFX_RESIZE_TIMEOUT actual=",window.size," content=",window.get_content_size()," expected=",target)
			return false
		await RenderingServer.frame_post_draw
	return true

func abort_fixture(host, window:Window, message:String) -> void:
	var key:=InputEventKey.new(); key.window_id=window.get_window_id(); key.keycode=KEY_F12; key.pressed=true; Input.parse_input_event(key)
	var deadline:=Time.get_ticks_msec()+15000
	while host.get_runtime_status()=="running" and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	push_error(message)
	get_tree().quit(1)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("VfxStageProbe"):
		push_error("VFX Stage Java probe start failed"); get_tree().quit(1); return
	var step:=0
	var drag_checked:={}
	var native_state := ""
	var deadline:=Time.get_ticks_msec()+180000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("VFX Stage failed step=%d: %s %s"%[step,host.get_runtime_error(),native_state]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("VfxStage %d "%step): continue
		if host.get_window_count()!=1 or host.get_native_window_count()!=(step%2): continue
		var id:=title.get_slice(" ",4).to_int()
		var window=get_window() if id==0 else host.get_native_window(id)
		if window==null or (id!=0 and window.is_present_pending()): continue
		if id!=0:
			if window.size!=Vector2i(Vector2(400,400)*DisplayServer.screen_get_scale(window.current_screen)): continue
			var ids := DisplayServer.get_window_list()
			var child_id: int = window.get_window_id()
			native_state = "glass=%d native=%d registered=%s embedded=%s" % [id, child_id, ids, window.is_embedded()]
			if window.is_embedded() or child_id == get_window().get_window_id() or ids.size() != 2 or not ids.has(child_id) or not ids.has(get_window().get_window_id()):
				continue
		for frame in range(10): await RenderingServer.frame_post_draw
		if not is_instance_valid(window) or not window.visible or (id != 0 and not DisplayServer.get_window_list().has(window.get_window_id())):
			continue
		if step==1 and OS.get_environment("GODOT_JFX_VFX_ABRUPT")=="1":
			print("VFX_ABRUPT_EXIT_REQUESTED")
			get_tree().quit(); return
		if step in [1,9] and not drag_checked.has(step):
			drag_corner(window,Vector2(60,40))
			if step==1:
				if not await wait_size(window,Vector2(460,440)):
					await abort_fixture(host,window,"VFX resize drag did not reach expected size"); return
				window.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-stage-resized.png"))
				drag_corner(window,Vector2(-60,-40))
				if not await wait_size(window,Vector2(400,400)):
					await abort_fixture(host,window,"VFX reverse resize drag did not restore size"); return
			else:
				await get_tree().create_timer(0.5).timeout
				if window.size!=Vector2i(Vector2(400,400)*DisplayServer.screen_get_scale(window.current_screen)):
					push_error("Non-resizable VFX Stage resized by corner drag"); get_tree().quit(1); return
			drag_checked[step]=true
			print("VFX_RESIZE_DRAG_PASS step=",step," size=",window.size)
			continue
		if not host.is_window_visible(id) or not DisplayServer.get_window_list().has(window.get_window_id()):
			push_error("VFX target is not a visible native window at step %d"%step); get_tree().quit(1); return
		if id!=0 and window.get_window_id()==get_window().get_window_id():
			push_error("VFX Stage reused the primary native window"); get_tree().quit(1); return
		print("VFX_NATIVE_VISIBLE step=",step," glass_id=",id," native_id=",window.get_window_id()," elapsed_ms=",Time.get_ticks_msec()," stats=",host.get_render_stats())
		window.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-stage-%d.png"%step))
		var point:=Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())
		point*=DisplayServer.screen_get_scale(window.current_screen)
		var motion:=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=point; Input.parse_input_event(motion)
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new(); event.window_id=window.get_window_id(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
			Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if step!=12 or drag_checked.size()!=2 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("VFX Stage coverage/cleanup differs"); get_tree().quit(1); return
	remove_child(host)
	print("VFX_RENDER_PROFILE elapsed_ms=",Time.get_ticks_msec()," stats=",host.get_render_stats())
	if host.get_owned_resource_count()!=0:
		push_error("VFX Stage resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_VFX_STAGE_PASS"); get_tree().quit(0)


