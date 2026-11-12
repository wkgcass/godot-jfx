extends Node2D

func matches(window, expected: Color) -> bool:
	var actual:Color=window.get_texture().get_image().get_pixel(30,30)
	return maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b)))<.04

func _ready() -> void:
	get_window().size=Vector2i(260,180); get_window().position=Vector2i(30,60)
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"NativeWindowPixelsProbe"):
		push_error("Native pixels JVM start failed"); get_tree().quit(1); return
	var step:=0
	var deadline:=Time.get_ticks_msec()+30000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Native pixels failed step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		if get_window().title!="Native pixels %d"%step: continue
		var first=host.get_native_window(100)
		var second=host.get_native_window(101)
		if first==null or first.is_present_pending(): continue
		if step<4 and (second==null or second.is_present_pending()): continue
		if host.get_window_count()!=0: push_error("Native publication created embedded layer"); get_tree().quit(1); return
		if step<5 and not matches(first,Color.RED if step==0 else Color.GREEN): continue
		if step<2 and not matches(second,Color.BLUE): continue
		if step==2 and second.visible: push_error("Publication restored hidden native window"); get_tree().quit(1); return
		if step==3 and not matches(second,Color.YELLOW): continue
		if step==4 and (second!=null or DisplayServer.get_window_list().size()!=2): push_error("Queued frame resurrected native window"); get_tree().quit(1); return
		if step==5 and matches(first,Color.GREEN): continue
		if step==0:
			first.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/native-pixels-a.png"))
			second.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/native-pixels-b.png"))
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new(); event.position=Vector2(10,10); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
			Input.parse_input_event(event)
		step+=1
	if step!=6 or host.get_native_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Native pixels coverage/cleanup differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Native pixels GPU resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_NATIVE_WINDOW_PIXELS_PASS"); get_tree().quit(0)
