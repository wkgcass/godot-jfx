extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),";".join(entries),"VfxLoadingProbe"):
		push_error("Loading JVM start failed");get_tree().quit(1);return
	var step:=0
	var loading_id:=-1
	var deadline:=Time.get_ticks_msec()+150000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Loading failed step=%d: %s"%[step,host.get_runtime_error()]);get_tree().quit(1);return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("VfxLoading %d "%step): continue
		var id:=title.get_slice(" ",4).to_int()
		var window=get_window() if id==0 else host.get_native_window(id)
		if window==null or (id!=0 and window.is_present_pending()) or host.is_composition_pending(): continue
		if not host.is_window_visible(id): continue
		if window.is_embedded() or DisplayServer.get_window_list().size()!=(1 if step==0 else 2):
			push_error("Loading target is not an independent native window");get_tree().quit(1);return
		if step==1: loading_id=id
		if step==2 and (id==loading_id or host.get_native_window(loading_id)!=null):
			push_error("Completion did not replace loading window");get_tree().quit(1);return
		window.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-loading-%d.png"%step))
		print("VFX_LOADING_NATIVE step=",step," id=",id," native_id=",window.get_window_id())
		if step!=1 or OS.get_environment("GODOT_JFX_LOADING_CANCEL")=="1":
			var point:=Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())*DisplayServer.screen_get_scale(window.current_screen)
			var motion:=InputEventMouseMotion.new();motion.window_id=window.get_window_id();motion.position=point;Input.parse_input_event(motion)
			for pressed in [true,false]:
				var event:=InputEventMouseButton.new();event.window_id=window.get_window_id();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if step!=3 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("Loading coverage/drain incomplete");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Loading resources retained");get_tree().quit(1);return
	host.free();print("GODOT_VFX_LOADING_PASS");get_tree().quit()
