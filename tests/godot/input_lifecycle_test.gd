extends Node2D

func child_window(host):
	for node in host.get_children():
		if node is Window and node.visible: return node
	return null

func mouse(pressed: bool, point: Vector2, window = null) -> void:
	if window == null: window = get_window()
	point *= DisplayServer.screen_get_scale(window.current_screen)
	if pressed:
		var motion:=InputEventMouseMotion.new(); motion.position=point; motion.window_id=window.get_window_id()
		Input.parse_input_event(motion)
	var event:=InputEventMouseButton.new(); event.position=point; event.window_id=window.get_window_id(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	Input.parse_input_event(event)

func gesture(cycle: int, pressed: bool, window) -> void:
	# A late release after peer destruction is deliberately addressed to the
	# root, as happens when the original HWND can no longer receive input.
	if window == null: window = get_window()
	if cycle%3==0:
		mouse(pressed,Vector2(30,25),window)
	elif cycle%3==1:
		var event:=InputEventScreenTouch.new(); event.index=0; event.window_id=window.get_window_id(); event.position=Vector2(30,25)*DisplayServer.screen_get_scale(window.current_screen); event.pressed=pressed
		Input.parse_input_event(event)
	else:
		var event:=InputEventKey.new(); event.window_id=window.get_window_id(); event.keycode=KEY_SPACE; event.unicode=32; event.pressed=pressed
		Input.parse_input_event(event)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("InputLifecycleProbe"):
		push_error("Lifecycle Java probe start failed"); get_tree().quit(1); return
	var cycle:=0
	var phase:=0
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Input lifecycle failed cycle=%d phase=%d: %s" % [cycle,phase,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if phase==0 and title=="Lifecycle ready %d"%cycle and host.get_native_window_count()==1 and child_window(host)!=null and child_window(host).has_focus():
			gesture(cycle,true,child_window(host)); phase=1
		elif phase==1 and title=="Lifecycle hidden %d"%cycle and host.get_native_window_count()==0 and get_window().has_focus():
			gesture(cycle,false,child_window(host))
			mouse(true,Vector2(50,35)); mouse(false,Vector2(50,35)); phase=2
		elif phase==2 and title=="Lifecycle restored %d"%cycle and host.get_native_window_count()==1 and child_window(host)!=null and child_window(host).has_focus():
			gesture(cycle,true,child_window(host)); gesture(cycle,false,child_window(host)); cycle+=1; phase=0
	if cycle!=6 or DisplayServer.get_window_list().size()!=1:
		push_error("Input lifecycle coverage/native window count differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Input lifecycle resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_INPUT_LIFECYCLE_PASS"); get_tree().quit(0)
