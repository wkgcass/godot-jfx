extends Node2D

func key(code:int, unicode:int, ctrl:bool=false) -> void:
	for pressed in [true,false]:
		# Select-all is the platform shortcut: Ctrl on Windows, Cmd(Meta) on macOS.
		var event:=InputEventKey.new(); event.window_id=get_window().get_window_id(); event.keycode=code; event.unicode=unicode; event.pressed=pressed
		if ctrl:
			if OS.has_feature("macos"): event.meta_pressed=true
			else: event.ctrl_pressed=true
		Input.parse_input_event(event)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),(";" if OS.has_feature("windows") else ":").join(entries),"VfxTableProbe"):
		push_error("VFX table JVM failed"); get_tree().quit(1); return
	var step:=0
	var deadline:=Time.get_ticks_msec()+180000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("VFX table failed step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("VfxTable %d "%step) or host.is_composition_pending(): continue
		if host.get_native_window_count()!=0:
			push_error("Unexpected table popup window"); get_tree().quit(1); return
		get_window().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-table-%d.png"%step))
		if step==3:
			key(KEY_A,0,true)
			for character in "Godot测试": key(KEY_NONE,character.unicode_at(0))
		else:
			var point:=Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())*DisplayServer.screen_get_scale(get_window().current_screen)
			var motion:=InputEventMouseMotion.new(); motion.window_id=get_window().get_window_id(); motion.position=point; Input.parse_input_event(motion)
			for pressed in [true,false]:
				var event:=InputEventMouseButton.new(); event.window_id=get_window().get_window_id(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if step!=8 or host.get_window_count()!=0 or host.is_composition_pending():
		push_error("VFX table coverage or drain incomplete"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("VFX table resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_VFX_TABLE_PASS"); get_tree().quit()
