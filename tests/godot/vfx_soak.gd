extends "res://vfx_intro.gd"

var sample_target_details := OS.get_environment("GODOT_JFX_SOAK_TARGETS") == "1"

func sample(host, round_index:int, page:int, direction:int) -> void:
	var resources: Dictionary = host.get_texture_resource_stats()
	var breakdown := {"shared_target_shaders":resources["shared_target_shaders"], "shared_target_meshes":resources.get("shared_target_meshes", -1), "textures":resources["live"].size(), "targets":0, "target_owned":0, "target_meshes":0, "target_shaders":0, "target_materials":0, "target_slots":0, "surface_meshes":resources["surface_meshes"], "retired_targets":resources["retired_targets"].size(), "retired_textures":resources["retired_textures"]}
	var record_targets := sample_target_details and page == 0
	var targets: Array[Dictionary] = []
	for entry in resources["live"]:
		if entry.has("owned"):
			breakdown["targets"] += 1
			if record_targets:
				var size: Vector2i = entry["size"]
				targets.append({"handle": entry["handle"], "width": size.x, "height": size.y,
						"slots": entry["slots"], "shaders": entry["shaders"], "materials": entry["materials"]})
			for key in ["owned", "meshes", "shaders", "materials", "slots"]:
				breakdown["target_"+key] += entry[key]
	if record_targets:
		print("VFX_SOAK_TARGETS ", JSON.stringify({"round": round_index, "targets": targets}))
	print("VFX_SOAK_SAMPLE ",JSON.stringify({"round":round_index,"page":page,"direction":direction,"elapsed_ms":Time.get_ticks_msec(),"unix_ms":roundi(Time.get_unix_time_from_system()*1000),"owned":host.get_owned_resource_count(),"resources":breakdown,"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"static_bytes":OS.get_static_memory_usage()}))

func navigate(host, page:int, forward:bool) -> bool:
	var scale:=DisplayServer.screen_get_scale(get_window().current_screen)
	var point:=Vector2(get_window().size)-Vector2(95,42)*scale
	if not forward: point.x=95*scale
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new();click.position=point;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;Input.parse_input_event(click)
	if not await wait_page(host,page): return false
	# Allow the original Demo's animated transition to finish, without readback.
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	if host.get_runtime_status()!="running":
		push_error("VFX soak runtime failed: "+host.get_runtime_error());get_tree().quit(1);return false
	return true

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.run_fixture_probe("VfxNavigationProbe"):
		push_error("VFX soak startup failed");get_tree().quit(1);return
	var startup_deadline:=Time.get_ticks_msec()+30000
	while host.get_runtime_status()!="running":
		if host.get_runtime_status() in ["failed","finished"] or Time.get_ticks_msec()>startup_deadline:
			push_error("VFX soak startup timed out: "+host.get_runtime_error());get_tree().quit(1);return
		await get_tree().process_frame
	if not await wait_page(host,0): return
	await get_tree().create_timer(5.0).timeout
	var pages:=OS.get_environment("GODOT_JFX_VFX_PAGES").to_int()
	var rounds:=OS.get_environment("GODOT_JFX_VFX_ROUNDS").to_int()
	sample(host,0,0,0)
	for round_index in range(1,rounds+1):
		for page in range(1,pages):
			if not await navigate(host,page,true): return
			sample(host,round_index,page,1)
		for page in range(pages-2,-1,-1):
			if not await navigate(host,page,false): return
			sample(host,round_index,page,-1)
	get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	var deadline:=Time.get_ticks_msec()+15000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("VFX soak shutdown failed");get_tree().quit(1);return
		await get_tree().process_frame
	for frame in range(120):
		if host.get_window_count()==0 and not host.is_composition_pending(): break
		await get_tree().process_frame
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("VFX soak windows retained");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("VFX soak resources retained");get_tree().quit(1);return
	var shared_programs: int = host.get_texture_resource_stats().shared_target_shaders
	if shared_programs != 0:
		push_error("VFX soak retained %d shared target shaders" % shared_programs)
		get_tree().quit(1)
		return
	host.free()
	print("VFX_SOAK_PASS rounds=", rounds, " pages=", pages, " final_owned=0 final_shared_target_shaders=0")
	get_tree().quit()
