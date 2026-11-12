extends Node

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"MediaChurnProbe"):
		fail("Media churn JVM startup failed");return
	var cycles:=OS.get_environment("GODOT_JFX_MEDIA_CYCLES").to_int()
	if cycles<24 or cycles>240: fail("Invalid media cycle count");return
	var deadline:=Time.get_ticks_msec()+30000+cycles*6000
	var checkpoint:=1
	var baseline_owned:=-1
	var baseline_texture:=0.0
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			fail("Media churn failed: "+host.get_runtime_error());return
		await get_tree().process_frame
		if get_window().title=="MediaChurn drained "+str(checkpoint):
			for i in range(12): await RenderingServer.frame_post_draw
			var owned:int=host.get_owned_resource_count()
			var texture:float=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
			print("MEDIA_CHURN_SAMPLE ",JSON.stringify({"cycle":checkpoint,"owned":owned,"texture_bytes":texture,"static_bytes":OS.get_static_memory_usage(),"elapsed_ms":Time.get_ticks_msec()}))
			if checkpoint==6: baseline_owned=owned;baseline_texture=texture
			if checkpoint>6 and (owned>baseline_owned+8 or texture>baseline_texture+2097152):
				fail("Media churn retained GPU resources grow after warmup");return
			checkpoint+=1
	if checkpoint!=cycles+1: fail("Missing media churn checkpoint");return
	remove_child(host)
	if host.get_owned_resource_count()!=0: fail("Media churn host resources retained");return
	host.free();print("GODOT_MEDIA_CHURN_PASS final_owned=0");get_tree().quit()

func fail(message:String) -> void:
	push_error(message);get_tree().quit(1)
