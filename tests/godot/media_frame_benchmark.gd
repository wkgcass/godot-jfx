extends Node

var pre_draw_us := 0
var post_draw_us := 0
var render_us := 0
var idle_us := 0

func _process(_delta: float) -> void:
	if post_draw_us > 0:
		idle_us += Time.get_ticks_usec() - post_draw_us
		post_draw_us = 0

func before_draw() -> void:
	pre_draw_us = Time.get_ticks_usec()

func after_draw() -> void:
	post_draw_us = Time.get_ticks_usec()
	if pre_draw_us > 0: render_us += post_draw_us - pre_draw_us

func _ready() -> void:
	var phases := OS.get_environment("GODOT_JFX_MEDIA_FRAME_PHASES") == "1"
	if phases:
		RenderingServer.frame_pre_draw.connect(before_draw)
		RenderingServer.frame_post_draw.connect(after_draw)
	else:
		set_process(false)
	print("MEDIA_FRAME_DISPLAY ",JSON.stringify({"max_fps":Engine.max_fps,"low_processor":OS.low_processor_usage_mode,"vsync":DisplayServer.window_get_vsync_mode()}))
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"MediaFrameBenchmark"):
		push_error("Media benchmark startup failed");get_tree().quit(1);return
	var baseline:Dictionary={}
	var started:=0
	var unfocused:=0
	var reported:=false
	var deadline:=Time.get_ticks_msec()+40000
	var render_baseline:=0
	var idle_baseline:=0
	while host.get_runtime_status()!="finished":
		await get_tree().process_frame
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Media benchmark failed: "+host.get_runtime_error());get_tree().quit(1);return
		if get_window().title=="MediaBenchmark START" and baseline.is_empty():
			baseline=host.get_render_stats();started=Time.get_ticks_usec()
			render_baseline=render_us;idle_baseline=idle_us
		if not baseline.is_empty() and not reported and not get_window().has_focus(): unfocused+=1
		if get_window().title=="MediaBenchmark END" and not reported:
			var current:Dictionary=host.get_render_stats()
			var delta:Dictionary={}
			for key in current: delta[key]=current[key]-baseline.get(key,0)
			delta["elapsed_ms"]=(Time.get_ticks_usec()-started)/1000.0
			delta["unfocused_ticks"]=unfocused
			delta["engine_render_wall_us"]=render_us-render_baseline
			delta["engine_idle_wall_us"]=idle_us-idle_baseline
			print("MEDIA_FRAME_HOST ",JSON.stringify(delta));reported=true
	remove_child(host);host.free()
	if not reported: push_error("Missing media frame sample");get_tree().quit(1);return
	print("GODOT_MEDIA_FRAME_PASS");get_tree().quit()
