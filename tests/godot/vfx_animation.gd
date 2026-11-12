extends Node2D

func write_motion_report(samples:Array,passed:bool) -> void:
	var report:=FileAccess.open(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-animation-motion.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":passed,"samples":samples,"minimum_displacement_pixels":20,"scope":"GPU motion evidence; synchronous readback prevents FPS claims"},"\t"))

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),";".join(entries),"VfxAnimationProbe"):
		push_error("Animation JVM start failed");get_tree().quit(1);return
	var timing_only:=OS.get_environment("GODOT_JFX_ANIMATION_TIMING_ONLY")=="1"
	var step:=0
	var motion_origin:=Vector2.INF
	var motion_start:Image
	var sampled_presentation:=-1
	var timing_start:Dictionary={}
	var timing_start_ms:int
	var motion_samples:Array=[]
	var deadline:=Time.get_ticks_msec()+150000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Animation failed step=%d: %s"%[step,host.get_runtime_error()]);get_tree().quit(1);return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if step==3 and title.begins_with("VfxAnimation 4 "):
			if timing_only:
				var stats:Dictionary=host.get_render_stats()
				print("VFX_ANIMATION_TIMING_STATS ",stats)
				var delta:Dictionary={}
				for key in stats:
					if key!="max_draw_sync_us":delta[key]=stats[key]-timing_start.get(key,0)
				delta["elapsed_ms"]=Time.get_ticks_msec()-timing_start_ms
				delta["presentation_fps"]=1000.0*delta["presentations"]/delta["elapsed_ms"]
				delta["host_tick_hz"]=1000.0*delta["host_ticks"]/delta["elapsed_ms"]
				print("VFX_ANIMATION_TIMING_DELTA ",JSON.stringify(delta));step=4;continue
			write_motion_report(motion_samples,false)
			if motion_start!=null:motion_start.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-animation-motion-start.png"))
			push_error("Animation ended before GPU motion was observed; samples="+str(motion_samples.size())+"; see vfx-animation-motion.json");get_tree().quit(1);return
		# Observe the short animation immediately after Play. Waiting for a
		# Java title/render round trip can miss its intermediate frames.
		if step!=3 and not title.begins_with("VfxAnimation %d "%step): continue
		if step!=3 and host.is_composition_pending(): continue
		if host.get_native_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
			push_error("Unexpected animation dialog/window");get_tree().quit(1);return
		if timing_only and step==3:continue
		if not timing_only:
			if step==3:
				var presentation:int=host.get_completed_presentations()
				if presentation==sampled_presentation:continue
				sampled_presentation=presentation
			var image:=get_viewport().get_texture().get_image()
			if step==3 or step==7:
				var red:=0
				var sum:=Vector2.ZERO
				for y in range(0,image.get_height(),8):
					for x in range(0,image.get_width(),8):
						var color:=image.get_pixel(x,y)
						if color.r>0.9 and color.g<0.1 and color.b<0.1:
							red+=1;sum+=Vector2(x,y)
				if red<5: continue
				if step==3:
					var center:=sum/float(red)
					if motion_samples.is_empty():print("VFX_ANIMATION_GPU_SAMPLE center=",center," presentations=",host.get_completed_presentations())
					motion_samples.append({"time_ms":Time.get_ticks_msec(),"x":center.x,"y":center.y,"red_samples":red,"presentations":host.get_completed_presentations()})
					if motion_origin==Vector2.INF:
						motion_origin=center
						motion_start=image
						continue
					if center.distance_to(motion_origin)<20:continue
					print("VFX_ANIMATION_GPU_MOTION pixels=",center.distance_to(motion_origin)," observations=",motion_samples.size())
				print("VFX_ANIMATION_RED step=",step," samples=",red)
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-animation-%d.png"%step))
		if step!=3:
			if step==2:timing_start=host.get_render_stats();timing_start_ms=Time.get_ticks_msec()
			var point:=Vector2(title.get_slice(" ",2).to_float(),title.get_slice(" ",3).to_float())*DisplayServer.screen_get_scale(get_window().current_screen)
			var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
			for pressed in [true,false]:
				var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if step!=8 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Animation coverage/drain incomplete");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Animation resources retained");get_tree().quit(1);return
	if motion_start!=null:motion_start.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/vfx-animation-motion-start.png"))
	if not timing_only:write_motion_report(motion_samples,true)
	host.free();print("GODOT_VFX_ANIMATION_PASS");get_tree().quit()
