extends Node2D

var phase_origin_us:int=0
var phase_active:=false
var phase_trace:Array=[]

func record_phase(phase:String) -> void:
	if phase_active:
		phase_trace.append([Time.get_ticks_usec()-phase_origin_us,phase])

func before_draw() -> void:
	record_phase("pre_draw")

func after_draw() -> void:
	# This CPU callback is not a GPU timestamp or physical presentation time.
	record_phase("post_draw_callback")

func _ready() -> void:
	if OS.get_environment("GODOT_JFX_BENCHMARK_MAILBOX")=="1":DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
	print("VFX_FRAME_DISPLAY ",JSON.stringify({"refresh_hz":DisplayServer.screen_get_refresh_rate(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"low_processor_mode":OS.low_processor_usage_mode}))
	var options:Dictionary={}
	var enabled:Dictionary={}
	for key in ["DIRECT_OFFSCREEN","BATCH_PASSES","DIRECT_PRESENT","SHADER_SOURCE_CACHE","FRAME_PULSE"]:
		options[key]=OS.get_environment("GODOT_JFX_"+key)
		enabled[key]=options[key]!="0"
	options["REGION_UPLOAD"]=OS.get_environment("GODOT_JFX_REGION_UPLOAD")
	enabled["REGION_UPLOAD"]=options["REGION_UPLOAD"]!="0"
	options["REUSE_SHADOW"]=OS.get_environment("GODOT_JFX_REUSE_SHADOW")
	enabled["REUSE_SHADOW"]=options["REUSE_SHADOW"]!="0"
	print("VFX_FRAME_OPTIONS ",JSON.stringify(options))
	print("VFX_FRAME_ENABLED ",JSON.stringify(enabled))
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),(";" if OS.has_feature("windows") else ":").join(entries),"VfxFrameBenchmark"):
		push_error("Benchmark JVM start failed");get_tree().quit(1);return
	var baseline:Dictionary={}
	var start_us:int
	var reported:=false
	var measured_ticks:=0
	var unfocused_ticks:=0
	var trace_enabled:=OS.get_environment("GODOT_JFX_BENCHMARK_TRACE")=="1"
	if trace_enabled:
		RenderingServer.frame_pre_draw.connect(before_draw)
		RenderingServer.frame_post_draw.connect(after_draw)
	var trace:Array=[]
	var deadline:=Time.get_ticks_msec()+150000
	while host.get_runtime_status()!="finished":
		await get_tree().process_frame
		record_phase("process_frame")
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Benchmark failed: "+host.get_runtime_error());get_tree().quit(1);return
		if not baseline.is_empty() and not reported:
			measured_ticks+=1
			if not get_window().has_focus():unfocused_ticks+=1
			if trace_enabled:
				var sample:Dictionary=host.get_render_stats()
				sample["time_us"]=Time.get_ticks_usec()-start_us
				trace.append(sample)
		if get_window().title=="VfxBenchmark START" and baseline.is_empty():
			print("VFX_FRAME_MEASUREMENT_VSYNC ",DisplayServer.window_get_vsync_mode())
			print("VFX_FRAME_WINDOW ",JSON.stringify({"focused":get_window().has_focus(),"mode":get_window().mode,"visible":get_window().visible,"size":str(get_window().size)}))
			baseline=host.get_render_stats();start_us=Time.get_ticks_usec()
			if trace_enabled:
				phase_origin_us=start_us;phase_active=true;record_phase("measurement_start")
				var initial:Dictionary=baseline.duplicate();initial["time_us"]=0;trace.append(initial)
		if get_window().title=="VfxBenchmark END" and not reported:
			phase_active=false
			var stats:Dictionary=host.get_render_stats()
			var delta:Dictionary={}
			for key in stats: delta[key]=stats[key]-baseline.get(key,0)
			delta["elapsed_ms"]=(Time.get_ticks_usec()-start_us)/1000.0
			delta["unfocused_ticks"]=unfocused_ticks
			delta["measured_ticks"]=measured_ticks
			delta["presentation_fps"]=1000.0*delta["presentations"]/delta["elapsed_ms"]
			print("VFX_FRAME_HOST ",JSON.stringify(delta));reported=true
			if trace_enabled:
				print("VFX_FRAME_TRACE_HOST ",JSON.stringify(trace))
				print("VFX_FRAME_TRACE_PHASES ",JSON.stringify(phase_trace))
	if trace_enabled:
		RenderingServer.frame_pre_draw.disconnect(before_draw)
		RenderingServer.frame_post_draw.disconnect(after_draw)
	remove_child(host);host.free()
	if not reported:push_error("Missing measurement");get_tree().quit(1);return
	print("GODOT_VFX_FRAME_BENCHMARK_PASS");get_tree().quit()
