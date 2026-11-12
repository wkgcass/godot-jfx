extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"WindowOrderProbe"):
		push_error("Order JVM start failed"); get_tree().quit(1); return
	var seen:={}
	var deadline:=Time.get_ticks_msec()+30000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Order failed/timed out: "+host.get_runtime_error()); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if not title.begins_with("Order "): continue
		var index:=title.get_slice(" ",1).to_int()
		var expected:=Color.GREEN if index in [0,4,9] else (Color(.5,0,.5) if index in [6,7] else Color.BLUE)
		var image:=get_viewport().get_texture().get_image()
		var actual:=image.get_pixel(120,100)
		if absf(actual.r-expected.r)>.04 or absf(actual.g-expected.g)>.04 or absf(actual.b-expected.b)>.04:
			push_error("Window order pixel differs at %d: %s" % [index,actual]); get_tree().quit(1); return
		var layers:=4 if index in [6,7] else (2 if index==9 else 3)
		if host.get_window_count()!=layers or host.get_surface_size()!=Vector2i(320,220):
			push_error("Order changed ownership/surface size"); get_tree().quit(1); return
		if not seen.has(index): image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/window-order-%d.png" % index))
		seen[index]=true
	if seen.size()!=10 or host.get_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Window order coverage/cleanup differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Order GPU resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_WINDOW_ORDER_PASS"); get_tree().quit(0)
