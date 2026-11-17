extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),(";" if OS.has_feature("windows") else ":").join(entries),"VfxDialogProbe"):
		push_error("VFX dialog JVM start failed"); get_tree().quit(1); return
	var step:=0
	var deadline:=Time.get_ticks_msec()+180000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" and OS.get_environment("GODOT_JFX_VFX_FAILURE")=="1" and step==4:
			for frame in range(120):
				if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
				await RenderingServer.frame_post_draw
			if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
				push_error("VFX failure did not drain windows"); get_tree().quit(1); return
			remove_child(host)
			if host.get_owned_resource_count()!=0: push_error("VFX failure leaked GPU resources"); get_tree().quit(1); return
			host.free(); print("GODOT_VFX_FAILURE_SHUTDOWN_PASS"); get_tree().quit(0); return
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("VFX dialog failed step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("VfxDialog %d "%step): continue
		if host.get_window_count()!=1 or host.get_native_window_count()!=(0 if step==0 or step==3 else 1): continue
		var id:=title.get_slice(" ",4).to_int()
		var window=get_window() if id==0 else host.get_native_window(id)
		if window==null or (id!=0 and window.is_present_pending()): continue
		for frame in range(10): await RenderingServer.frame_post_draw
		if not host.is_window_visible(id) or not DisplayServer.get_window_list().has(window.get_window_id()):
			push_error("VFX target is not a visible native window at step %d"%step); get_tree().quit(1); return
		if id!=0 and window.get_window_id()==get_window().get_window_id():
			push_error("VFX dialog reused the primary native window"); get_tree().quit(1); return
		print("VFX_NATIVE_VISIBLE step=",step," glass_id=",id," native_id=",window.get_window_id()," elapsed_ms=",Time.get_ticks_msec()," stats=",host.get_render_stats())
		window.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-dialog-%d.png"%step))
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
	if step!=5 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("VFX dialog coverage/cleanup differs"); get_tree().quit(1); return
	remove_child(host)
	print("VFX_RENDER_PROFILE elapsed_ms=",Time.get_ticks_msec()," stats=",host.get_render_stats())
	if host.get_owned_resource_count()!=0:
		push_error("VFX dialog resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_VFX_DIALOG_PASS"); get_tree().quit(0)
