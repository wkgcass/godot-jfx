extends Node2D

func click(window:Window) -> void:
	var point:=Vector2(45,25)*DisplayServer.screen_get_scale(window.current_screen)
	var motion:=InputEventMouseMotion.new();motion.window_id=window.get_window_id();motion.position=point;Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.window_id=window.get_window_id();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"StageChurnProbe"):
		push_error("Stage churn JVM failed");get_tree().quit(1);return
	var cycle:=0
	var cycles:=OS.get_environment("GODOT_JFX_CHURN_CYCLES").to_int()
	if cycles==0: cycles=36
	var want_open:=false
	var baseline:=-1
	var baseline_texture:=0.0
	var sample_count:=0
	var deadline:=Time.get_ticks_msec()+maxi(240000,cycles*3000)
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Stage churn failed cycle=%d open=%s: %s"%[cycle,want_open,host.get_runtime_error()]);get_tree().quit(1);return
		await RenderingServer.frame_post_draw
		var prefix:="StageChurn %s %d"%["open" if want_open else "closed",cycle]
		var title:=get_window().title
		if title!=prefix and not title.begins_with(prefix+" "): continue
		if host.is_composition_pending(): continue
		if want_open:
			var child=host.get_native_window(title.get_slice(" ",3).to_int())
			if child==null or child.is_present_pending() or not host.is_window_visible(title.get_slice(" ",3).to_int()): continue
			var scale:=DisplayServer.screen_get_scale(child.current_screen)
			var expected:=Vector2i(Vector2(200+(cycle%3)*40,120+(cycle%3)*20)*scale)
			if child.size!=expected or child.get_content_size()!=expected: continue
			if child.is_embedded() or DisplayServer.get_window_list().size()!=2:
				push_error("Churn Stage is not independent");get_tree().quit(1);return
			var image:Image=child.get_texture().get_image()
			var color:Color=image.get_pixel(expected.x-10,expected.y-10)
			if (color.r<0.99 if cycle%2==0 else color.b<0.99): continue
			click(child);cycle+=1;want_open=false
		else:
			if host.get_native_window_count()!=0 or DisplayServer.get_window_list().size()!=1: continue
			# Offscreen passes and explicit presentation fences can emit multiple
			# post-draw notifications in one host iteration. Allow twelve actual
			# host iterations for asynchronous Glass/Quantum close jobs to drain.
			for frame in range(12): await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var owned:int=host.get_owned_resource_count()
			var texture:float=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
			var sample:={"cycle":cycle,"owned":owned,"texture_bytes":texture,"godot_static_bytes":OS.get_static_memory_usage()}
			# Stream observations; retaining dictionaries here would make the
			# fixture itself grow Godot's static-memory measurement every cycle.
			sample_count+=1;print("STAGE_CHURN_RESOURCES ",JSON.stringify(sample))
			if cycle==6:
				baseline=owned;baseline_texture=texture
			elif cycle>6 and (owned!=baseline or texture!=baseline_texture):
				print("STAGE_CHURN_RETAINED ",host.get_texture_resource_stats())
				push_error("Closed Stage resources did not return to warm baseline");get_tree().quit(1);return
			click(get_window());want_open=true
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if cycle!=cycles or sample_count!=cycles+1 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Stage churn coverage/drain incomplete");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Stage churn retained resources after removal");get_tree().quit(1);return
	var report:={"status":"passed","cycles":cycle,"forced_gc":false,"sample_count":sample_count,"final_owned":0}
	var file:=FileAccess.open(ProjectSettings.globalize_path("res://../../artifacts/reference/stage-churn.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
	host.free();print("GODOT_STAGE_CHURN_PASS");get_tree().quit()
