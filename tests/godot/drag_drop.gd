extends Node2D
func mouse(window, point:Vector2, kind:int) -> void:
	point*=DisplayServer.screen_get_scale(window.current_screen)
	var event
	if kind==0:
		event=InputEventMouseMotion.new(); event.button_mask=MOUSE_BUTTON_MASK_LEFT
	else:
		event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=kind==1
	event.window_id=window.get_window_id(); event.position=point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("DragDropProbe"):
		push_error("Drag probe failed"); get_tree().quit(1); return
	var robot_mode:=OS.get_environment("GODOT_JFX_ROBOT_DRAG")=="1"
	var test:=0
	var phase:=0
	var deadline:=Time.get_ticks_msec()+40000
	while host.get_runtime_status()!="finished":
		await RenderingServer.frame_post_draw
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Drag failed test=%d phase=%d: %s"%[test,phase,host.get_runtime_error()]); get_tree().quit(1); return
		if robot_mode: continue
		var child=host.get_native_window(2)
		# Synthesized input delivers by window id, not OS focus, so the fixture
		# runs while another application holds the foreground (no topmost or
		# focus dependence for background-friendly runs).
		if phase==0 and get_window().title=="Drag ready %d"%test and not host.is_composition_pending():
			# The ready title can arrive before the secondary Wayland surface's
			# initial configure and focus transfer. Wait for its actual blue
			# target to be presented before batching the first mouse gesture.
			if test == 0 and DisplayServer.get_name() == "Wayland":
				if child == null or child.get_window_id() == DisplayServer.INVALID_WINDOW_ID or child.is_present_pending():
					continue
				var image: Image = child.get_texture().get_image()
				var sample := Vector2i(Vector2(40, 40) * DisplayServer.screen_get_scale(child.current_screen))
				if image == null or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(sample):
					continue
				var color := image.get_pixelv(sample)
				if color.b < 0.95 or color.r > 0.05 or color.g > 0.05:
					continue
			mouse(get_window(),Vector2(40,40),1)
			mouse(get_window(),Vector2(80,40),0)
			# Case zero deliberately queues drop in the same host batch.
			if test==0:
				mouse(get_window(),Vector2(240,40),0); mouse(get_window(),Vector2(240,40),2)
				test+=1
			else: phase=1
		elif phase==1 and get_window().title=="Drag active %d"%test:
			if test==4:
				for pressed in [true,false]:
					var key:=InputEventKey.new(); key.keycode=KEY_ESCAPE; key.pressed=pressed; Input.parse_input_event(key)
				mouse(get_window(),Vector2(80,40),2)
			elif test==5:
				mouse(child,Vector2(40,40),0)
			elif test==6:
				mouse(get_window(),Vector2(240,40),0)
			elif test==1:
				mouse(child,Vector2(40,40),0); mouse(child,Vector2(40,40),2)
			else:
				mouse(get_window(),Vector2(240,40),0); mouse(get_window(),Vector2(240,40),2)
			test+=1; phase=0
	if not robot_mode and test!=7: push_error("Drag coverage incomplete"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: push_error("Drag resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_DRAG_DROP_PASS"); get_tree().quit(0)
