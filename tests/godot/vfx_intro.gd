extends Node2D

func wait_page(host, page: int) -> bool:
	if OS.get_environment("GODOT_JFX_VFX_PAGES").to_int() <= 2: return true
	var limit := Time.get_ticks_msec()+60000
	while get_window().title != "VFX Intro [page=%d]"%page:
		if host.get_runtime_status() != "running" or Time.get_ticks_msec() > limit:
			push_error("VFX page acknowledgement timeout: "+str(page))
			get_tree().quit(1)
			return false
		await get_tree().process_frame
	return true

func _ready() -> void:
	var pages := maxi(2,OS.get_environment("GODOT_JFX_VFX_PAGES").to_int())
	var prefix := "vfx-pages-" if pages > 2 else "vfx-smoke-"
	if OS.get_environment("GODOT_JFX_VFX_FREEZE")=="1": prefix+="frozen-"
	var folder := ProjectSettings.globalize_path("res://../../artifacts/reference/"+prefix+RenderingServer.get_current_rendering_method())
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/run.json",FileAccess.WRITE).store_string(JSON.stringify({"status":"running","pages":pages}))
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	var base := ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries := PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test"])
	entries.append(ProjectSettings.globalize_path("res://../../artifacts/reference"))
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"):
			entries.append(base+"/dependencies/"+file)
	var entry := "VfxNavigationProbe" if OS.get_environment("GODOT_JFX_VFX_PAGES").to_int() > 2 else "io.vproxy.vfx.intro.IntroMain"
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),";".join(entries),entry):
		push_error("VFX JVM startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec()+30000
	while not get_window().title.begins_with("VFX Intro"):
		if host.get_runtime_status() in ["failed","finished"] or Time.get_ticks_msec() > deadline:
			push_error("VFX startup failed: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		await get_tree().process_frame
	await get_tree().create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	var initial := get_viewport().get_texture().get_image()
	initial.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-intro.png"))
	print("VFX_INTRO_CAPTURE resources=",host.get_owned_resource_count())
	# Exercise the Demo's own navigation through the host input queue.
	var scale:=DisplayServer.screen_get_scale(get_window().current_screen)
	var position := Vector2(get_window().size)-Vector2(95,42)*scale
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
	if not await wait_page(host,1): return
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var next := get_viewport().get_texture().get_image()
	next.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-intro-next.png"))
	# Ignore button hover pixels: the central content must change substantially.
	var changed := 0
	for y in range(roundi(100*scale),mini(roundi(650*scale),initial.get_height()),roundi(4*scale)):
		for x in range(roundi(100*scale),mini(roundi(1100*scale),initial.get_width()),roundi(4*scale)):
			if initial.get_pixel(x,y) != next.get_pixel(x,y): changed += 1
	if changed < 100:
		push_error("VFX Next action did not change content")
		get_tree().quit(1)
		return
	if DisplayServer.get_window_list().size() != 1:
		push_error("VFX created an extra native window")
		get_tree().quit(1)
		return
	print("VFX_INTRO_NAVIGATION changed_samples=",changed)
	initial.save_png(folder+"/00.png")
	next.save_png(folder+"/01.png")
	for page in range(2,pages):
		for pressed in [true,false]:
			var click := InputEventMouseButton.new()
			click.position = position
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			Input.parse_input_event(click)
		if not await wait_page(host,page): return
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		if host.get_runtime_status() != "running":
			push_error("VFX page failed: "+str(page)+" "+host.get_runtime_error())
			get_tree().quit(1)
			return
		get_viewport().get_texture().get_image().save_png(folder+"/%02d.png"%page)
		print("VFX_PAGE ",page," resources=",host.get_owned_resource_count())
	get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	deadline = Time.get_ticks_msec()+15000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("VFX shutdown failed: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		await get_tree().process_frame
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("VFX windows did not drain"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("VFX host resources leaked"); get_tree().quit(1); return
	host.free()
	FileAccess.open(folder+"/run.json",FileAccess.WRITE).store_string(JSON.stringify({"status":"passed","pages":pages,"system_scale":scale,"image_size":str(initial.get_size()),"final_owned_resources":0}))
	print("VFX_INTRO_SMOKE_PASS")
	get_tree().quit()
