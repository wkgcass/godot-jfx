extends Node2D
func pixel_matches(window, color:Color) -> bool:
	var image=window.get_texture().get_image()
	var actual:Color=image.get_pixelv(Vector2i(Vector2(200,100)*DisplayServer.screen_get_scale(window.current_screen)))
	return maxf(absf(actual.r-color.r),maxf(absf(actual.g-color.g),absf(actual.b-color.b)))<.04
func _ready() -> void:
	get_window().position=Vector2i(30,60)
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"NativeStageProbe"):
		push_error("Native Stage JVM failed"); get_tree().quit(1); return
	var scale:=DisplayServer.screen_get_scale()
	var step:=0
	var deadline:=Time.get_ticks_msec()+40000
	var diagnostic:=Time.get_ticks_msec()+5000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Native Stage timeout step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		if Time.get_ticks_msec()>diagnostic:
			print("NATIVE_STAGE_STATE step=",step," count=",host.get_native_window_count()," child2=",host.get_native_window_info(2)," child3=",host.get_native_window_info(3))
			diagnostic=Time.get_ticks_msec()+5000
		if get_window().title!="Native Stage %d"%step or host.is_composition_pending(): continue
		var child=host.get_native_window(2 if step<3 else 3)
		if get_window().size!=Vector2i(Vector2(320,180)*scale) or not pixel_matches(get_window(),Color.RED): continue
		if step in [0,1,3,4,5,6,7,8,9,10,11]:
			if child==null or child.is_present_pending(): continue
			if child.title!="独立 Stage" or child.borderless or child.is_embedded():
				push_error("Standard decorated Stage is not an independent native window"); get_tree().quit(1); return
			if not child.visible or child.get_window_id()==get_window().get_window_id() or DisplayServer.get_window_list().size()!=2: continue
			if not pixel_matches(child,Color.BLUE if step==0 else Color.GREEN): continue
			if step in [4,6,9]:
				if child.mode!=Window.MODE_FULLSCREEN or child.size!=DisplayServer.screen_get_size(child.current_screen): continue
				var full_image=child.get_texture().get_image()
				var far_pixel:Color=full_image.get_pixel(child.size.x-20,child.size.y-20)
				if far_pixel.g<.96 or far_pixel.r>.04 or far_pixel.b>.04: continue
				if get_window().mode!=Window.MODE_WINDOWED: push_error("Child fullscreen changed root mode"); get_tree().quit(1); return
			elif step in [8,10]:
				if child.mode!=Window.MODE_MAXIMIZED or child.size.x<=400*scale or child.size.y<=240*scale: continue
			elif step>=1 and (child.mode!=Window.MODE_WINDOWED or child.size!=Vector2i(Vector2(400,240)*scale) or child.position!=Vector2i(Vector2(470,120)*scale)): continue
			if step==0:
				child.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/native-stage-child.png"))
		else:
			if child!=null or host.get_native_window_count()!=0 or DisplayServer.get_window_list().size()!=1: continue
		if host.get_window_count()!=1:
			push_error("Secondary Stage was embedded in root compositor"); get_tree().quit(1); return
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new(); event.position=Vector2(30,25)*scale; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
			Input.parse_input_event(event)
		if step==6:
			for pressed in [true,false]:
				var key:=InputEventKey.new(); key.window_id=child.get_window_id(); key.keycode=KEY_ESCAPE; key.pressed=pressed
				Input.parse_input_event(key)
		step+=1
	if step!=13: push_error("Native Stage phases incomplete"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Native Stage resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_NATIVE_STAGE_PASS"); get_tree().quit(0)

