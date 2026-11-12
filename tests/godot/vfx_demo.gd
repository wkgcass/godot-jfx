extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test"])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"):entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),";".join(entries),"io.vproxy.vfx.intro.IntroMain"):
		push_error("VFX JVM startup failed");get_tree().quit(1);return
	var smoke:=OS.get_environment("GODOT_JFX_DEMO_SMOKE")=="1"
	# Per-frame luma sampling under the OS cursor (HOVER_SAMPLE=1): correlated
	# with the Java-side HOVER_TAP event stream in this log, it shows whether
	# a user-visible hover flicker is a state drop or a present-side revert.
	var hover_sample:=OS.get_environment("GODOT_JFX_HOVER_SAMPLE")=="1"
	var sample_frame:=0
	var started:=Time.get_ticks_msec()
	var close_sent:=false
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or (smoke and Time.get_ticks_msec()-started>60000):
			push_error("VFX Demo failed: "+host.get_runtime_error());get_tree().quit(1);return
		if smoke and not close_sent and Time.get_ticks_msec()-started>10000 and get_window().title.begins_with("VFX Intro"):
			get_window().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST);close_sent=true
		await get_tree().process_frame
		if hover_sample:
			sample_frame+=1
			if sample_frame%2==0:
				var m:=get_window().get_mouse_position()
				var img:=get_viewport().get_texture().get_image()
				var sx:int=int(m.x*img.get_width()/max(1,get_viewport().size.x))
				var sy:int=int(m.y*img.get_height()/max(1,get_viewport().size.y))
				var luma:=0.0
				var n:=0
				for dy in range(-24,25,8):
					for dx in range(-24,25,8):
						var x:=sx+dx
						var y:=sy+dy
						if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():
							var c:=img.get_pixel(x,y)
							luma+=(c.r+c.g+c.b)/3.0
							n+=1
				print("HOVER_SAMPLE f=",sample_frame," luma=",snappedf(luma/max(1,n),0.001))
	if smoke and not close_sent:
		push_error("VFX smoke did not reach the visible Demo and close action");get_tree().quit(1);return
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending():break
		await get_tree().process_frame
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("VFX windows did not drain");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("VFX resources retained");get_tree().quit(1);return
	host.free();print("VFX_DEMO_CLOSED");get_tree().quit()
