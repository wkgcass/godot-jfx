extends Node2D
func _ready() -> void:
	var original_mouse_mode:=DisplayServer.mouse_get_mode()
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("ImageCursorProbe"):
		fail("Cursor probe rejected"); return
	var step:=0
	var moved:=-1
	var deadline:=Time.get_ticks_msec()+40000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			fail("Cursor test failed step="+str(step)+" info="+str(host.get_custom_cursor_info())+" "+host.get_runtime_error()); return
		await RenderingServer.frame_post_draw
		if step>=13 or get_window().title!="ImageCursor "+str(step) or host.get_completed_presentations()==0: continue
		var window=get_window() if step==0 else host.get_native_window(2)
		if window==null or (step!=0 and window.is_present_pending()): continue
		if step!=0 and window.get_window_id()==get_window().get_window_id(): fail("Cursor child is embedded"); return
		if moved!=step:
			var motion:=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=Vector2(40,40)
			Input.parse_input_event(motion); moved=step
		var info:Dictionary=host.get_custom_cursor_info()
		var hidden:bool=step in [4,5,7,9,12]
		if DisplayServer.mouse_get_mode()!=(DisplayServer.MOUSE_MODE_HIDDEN if hidden else DisplayServer.MOUSE_MODE_VISIBLE): continue
		if step==4 and DisplayServer.cursor_get_shape()!=DisplayServer.CURSOR_CROSS: continue
		if step==5 and DisplayServer.cursor_get_shape()!=DisplayServer.CURSOR_ARROW: continue
		if step==10:
			if not info.get("native_null",false): continue
		elif step in [2,11] or hidden:
			if not info.is_empty(): continue
		else:
			var values:=[48,40,11,13] if step in [1,6] else [32,24,5,7]
			if info.get("width",0)!=values[0] or info.get("height",0)!=values[1] or info.get("hotspot_x",-1)!=values[2] or info.get("hotspot_y",-1)!=values[3]: continue
			var pixel:int=info.get("center_argb",-1)
			var expected:int=0xff00ff00 if step in [1,6] else 0x80800000
			for shift in [0,8,16,24]:
				if absi(((pixel>>shift)&255)-((expected>>shift)&255))>2:
					fail("Native cursor premultiplied pixel differs: "+str(info)); return
		print("NATIVE_CURSOR step=",step," window=",window.get_window_id()," hidden=",hidden," info=",info)
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new(); event.window_id=window.get_window_id(); event.position=Vector2(40,40); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
			Input.parse_input_event(event)
		step+=1
	if step!=13: fail("Cursor sequence incomplete"); return
	remove_child(host)
	if host.get_owned_resource_count()!=0 or not host.get_custom_cursor_info().is_empty(): fail("Cursor host teardown retained resources"); return
	if DisplayServer.mouse_get_mode()!=original_mouse_mode: fail("Cursor teardown did not restore original mouse mode"); return
	# EXIT_TREE has already restored the JavaFX-owned cursor state. A later
	# destructor must not overwrite a new cursor chosen by the Godot application.
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	host.free()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(10,10)
	get_viewport().push_input(motion, true)
	if Input.get_current_cursor_shape() != Input.CURSOR_CROSS:
		fail("Repeated host cleanup overwrote application cursor"); return
	print("CURSOR_RESTORE_ONCE_PASS")
	print("GODOT_IMAGE_CURSOR_PASS"); get_tree().quit()

func fail(message:String) -> void:
	push_error(message); get_tree().quit(1)
