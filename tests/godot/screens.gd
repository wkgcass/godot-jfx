extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("ScreensProbe"):
		push_error("Screen Java probe start failed"); get_tree().quit(1); return
	var step:=0
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Screen test failed step=%d: %s"%[step,host.get_runtime_error()]); get_tree().quit(1); return
		# frame_post_draw stops when no host window can draw: on macOS closing or
		# hiding the last visible FX Stage orders out the root NSWindow, and Godot
		# then skips RenderingServer.draw entirely (Windows keeps drawing hidden
		# windows). Race the draw signal against a timer so status/deadline
		# polling never deadlocks; screen assertions below are unchanged.
		var drawn:=[false]
		RenderingServer.frame_post_draw.connect(func() -> void: drawn[0]=true,CONNECT_ONE_SHOT)
		get_tree().create_timer(0.02).timeout.connect(func() -> void: drawn[0]=true,CONNECT_ONE_SHOT)
		while not drawn[0]:
			await get_tree().process_frame
		var title:=get_window().title
		if not title.begins_with("Screens %d "%step): continue
		var child=host.get_native_window(title.get_slice(" ",2).to_int())
		if child==null or not child.visible or child.is_present_pending(): continue
		var screen_index:=title.get_slice(" ",3).to_int()-1
		var bounds:=Rect2i(DisplayServer.screen_get_position(screen_index),DisplayServer.screen_get_size(screen_index))
		var work:=DisplayServer.screen_get_usable_rect(screen_index)
		var dpi:=DisplayServer.screen_get_dpi(screen_index)
		if OS.get_name() in ["macOS", "Linux"]:
			dpi=roundi(DisplayServer.screen_get_scale(screen_index)*96.0)
		var expected:=[screen_index+1,bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y,work.position.x,work.position.y,work.size.x,work.size.y,dpi]
		for i in range(10):
			if title.get_slice(" ",i+3).to_int()!=expected[i]:
				push_error("Screen metadata differs from DisplayServer"); get_tree().quit(1); return
		if (step==0 and screen_index!=DisplayServer.get_primary_screen()) or child.current_screen!=screen_index:
			push_error("Primary order or child screen association differs"); get_tree().quit(1); return
		print(title)
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new(); event.window_id=get_window().get_window_id(); event.position=Vector2(120,60)*DisplayServer.screen_get_scale(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
			Input.parse_input_event(event)
		step+=1
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		var drained:=[false]
		RenderingServer.frame_post_draw.connect(func() -> void: drained[0]=true,CONNECT_ONE_SHOT)
		get_tree().create_timer(0.02).timeout.connect(func() -> void: drained[0]=true,CONNECT_ONE_SHOT)
		while not drained[0]:
			await get_tree().process_frame
	if step!=DisplayServer.get_screen_count() or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("Screen coverage/cleanup differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Screen GPU resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_SCREENS_PASS"); get_tree().quit(0)
