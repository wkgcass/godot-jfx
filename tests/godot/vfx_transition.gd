extends Node2D

func _ready() -> void:
	print("VFX_TRANSITION_DISPLAY ",JSON.stringify({"refresh_hz":DisplayServer.screen_get_refresh_rate(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"low_processor_mode":OS.low_processor_usage_mode}))
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),";".join(entries),"VfxTransitionProbe"):
		push_error("Transition benchmark JVM start failed");get_tree().quit(1);return
	var baseline:Dictionary={}
	var start_us:int
	var reported:=false
	var deadline:=Time.get_ticks_msec()+300000
	# GPU timing (GODOT_JFX_GPU_TIMING=1): window viewport measurement is
	# enabled here; offscreen targets opt in host-side at creation.
	var gpu_timing:=OS.get_environment("GODOT_JFX_GPU_TIMING")=="1"
	if gpu_timing:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var gpu_window_samples:PackedFloat32Array=[]
	var gpu_offscreen_samples:PackedFloat32Array=[]
	while host.get_runtime_status()!="finished":
		await get_tree().process_frame
		if gpu_timing and not baseline.is_empty() and !reported:
			gpu_window_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())*1000.0)
			gpu_offscreen_samples.append(host.get_render_stats().get("offscreen_gpu_us",0.0))
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Transition benchmark failed: "+host.get_runtime_error());get_tree().quit(1);return
		if get_window().title=="VfxTransition START" and baseline.is_empty():
			print("VFX_TRANSITION_WINDOW ",JSON.stringify({"focused":get_window().has_focus(),"mode":get_window().mode,"visible":get_window().visible,"size":str(get_window().size)}))
			baseline=host.get_render_stats();start_us=Time.get_ticks_usec()
		if get_window().title=="VfxTransition END" and not reported:
			var stats:Dictionary=host.get_render_stats()
			var delta:Dictionary={}
			for key in stats:
				# A lifetime high-water mark is not an additive counter. Its
				# difference cannot describe the maximum within this interval.
				if key.begins_with("max_"): delta["lifetime_"+key]=stats[key]
				elif key in ["offscreen_gpu_us", "window_gpu_us"]: delta["last_"+key]=stats[key]
				else: delta[key]=stats[key]-baseline.get(key,0)
			delta["elapsed_ms"]=(Time.get_ticks_usec()-start_us)/1000.0
			delta["presentation_fps"]=1000.0*delta["presentations"]/delta["elapsed_ms"]
			print("VFX_TRANSITION_HOST ",JSON.stringify(delta));reported=true
			if gpu_timing and !gpu_window_samples.is_empty():
				gpu_window_samples.sort();gpu_offscreen_samples.sort()
				var wsum:=0.0;for v in gpu_window_samples:wsum+=v
				var osum:=0.0;for v in gpu_offscreen_samples:osum+=v
				var n:=gpu_window_samples.size()
				print("VFX_TRANSITION_GPU ",JSON.stringify({"samples":n,
					"window_us_avg":wsum/n,"window_us_p50":gpu_window_samples[n/2],"window_us_max":gpu_window_samples[n-1],
					"offscreen_us_avg":osum/n,"offscreen_us_p50":gpu_offscreen_samples[n/2],"offscreen_us_max":gpu_offscreen_samples[n-1]}))
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Transition benchmark host retained resources");host.free();get_tree().quit(1);return
	host.free()
	if not reported:push_error("Missing measurement");get_tree().quit(1);return
	print("VFX_TRANSITION_RESOURCE_CLEANUP_PASS")
	print("GODOT_VFX_TRANSITION_PASS");get_tree().quit()
