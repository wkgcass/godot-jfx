extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),(";" if OS.has_feature("windows") else ":").join(entries),"VfxWindowControlsProbe"):
		push_error("VFX controls JVM start failed"); get_tree().quit(1); return
	var step:=0
	var diagnostic:=Time.get_ticks_msec()+3000
	var deadline:=Time.get_ticks_msec()+60000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("VFX controls failed step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		await get_tree().process_frame
		var title:=get_window().title
		if Time.get_ticks_msec()>diagnostic:
			print("VFX_CONTROLS_STATE step=",step," title=",title," child=",host.get_native_window_info(2))
			diagnostic=Time.get_ticks_msec()+5000
		if not title.begins_with("VfxControls %d "%step): continue
		var window=host.get_native_window(title.get_slice(" ",4).to_int())
		if window==null: continue
		# VFX emulates maximize with manual bounds on macOS: the native window
		# stays windowed and is resized to the screen minus the menu bar (24pt).
		var macos:=OS.has_feature("macos")
		var expected_mode:=Window.MODE_MAXIMIZED if step==1 else Window.MODE_MINIMIZED if step==3 else Window.MODE_WINDOWED
		if macos and step==1: expected_mode=Window.MODE_WINDOWED
		if window.mode!=expected_mode: continue
		if step==1:
			if macos:
				var screen_position:=DisplayServer.screen_get_position(window.current_screen)
				var screen_size:=DisplayServer.screen_get_size(window.current_screen)
				if window.position!=screen_position+Vector2i(0,24) or window.size!=screen_size-Vector2i(0,24):
					push_error("Maximized VFX Stage does not match screen bounds minus menu bar"); get_tree().quit(1); return
			else:
				var work:=DisplayServer.screen_get_usable_rect(window.current_screen)
				if window.position!=work.position or window.size!=work.size:
					push_error("Maximized VFX Stage does not match monitor work area"); get_tree().quit(1); return
		if step!=3 and (window.is_present_pending() or window.get_content_size()!=window.size): continue
		if window.is_embedded() or DisplayServer.get_window_list().size()!=2 or get_window().mode!=Window.MODE_WINDOWED:
			push_error("VFX controls changed wrong native window"); get_tree().quit(1); return
		print("VFX_WINDOW_MODE step=",step," mode=",window.mode," size=",window.size," position=",window.position)
		if step==3:
			# Restore through the host, as the OS taskbar would; no Java setter.
			window.mode=Window.MODE_WINDOWED
		else:
			window.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-window-controls-%d.png"%step))
			var point:=Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())*DisplayServer.screen_get_scale(window.current_screen)
			var motion:=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=point; Input.parse_input_event(motion)
			for pressed in [true,false]:
				var event:=InputEventMouseButton.new(); event.window_id=window.get_window_id(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if step!=5 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("VFX controls coverage or cleanup incomplete"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("VFX controls resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_VFX_WINDOW_CONTROLS_PASS"); get_tree().quit()
