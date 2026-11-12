extends Node2D

func child_window(host):
	for node in host.get_children():
		if node is Window and node.visible: return node
	return null

func mouse(pressed: bool, point: Vector2, window = null) -> void:
	if window == null: window = get_window()
	point *= DisplayServer.screen_get_scale(window.current_screen)
	# Position before pressing. Injecting motion before release while the
	# button is still held is a real drag, even at unchanged coordinates.
	# This fixture tests cancellation and clicks, not dragging.
	if pressed:
		var motion:=InputEventMouseMotion.new(); motion.position=point; motion.window_id=window.get_window_id()
		Input.parse_input_event(motion)
	var event:=InputEventMouseButton.new(); event.position=point; event.window_id=window.get_window_id(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	Input.parse_input_event(event)
func touch(pressed: bool) -> void:
	var event:=InputEventScreenTouch.new(); event.index=0; event.position=Vector2(50,40)*DisplayServer.screen_get_scale(get_window().current_screen); event.pressed=pressed
	Input.parse_input_event(event)
func key(pressed: bool) -> void:
	var event:=InputEventKey.new(); event.keycode=KEY_SPACE; event.unicode=32; event.pressed=pressed
	Input.parse_input_event(event)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"InputCancelProbe"):
		push_error("Cancel JVM start failed"); get_tree().quit(1); return
	var phase:=0
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Cancellation failed/timed out phase=%d: %s" % [phase,host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		if phase==0 and title=="Cancel ready" and host.get_completed_presentations()>0 and get_window().has_focus():
			mouse(true,Vector2(50,40)); phase=1
		elif phase==1 and title=="Cancel modal 1" and host.get_native_window_count()==1 and child_window(host)!=null and child_window(host).has_focus():
			# Focus loss may swallow the original button-up. Do not repair it
			# here: the next unpressed motion must not inherit the old hold.
			mouse(true,Vector2(25,25),child_window(host)); mouse(false,Vector2(25,25),child_window(host)); phase=2
		elif phase==2 and title=="Cancel returned 1" and host.get_native_window_count()==0 and get_window().has_focus():
			mouse(true,Vector2(50,40)); mouse(false,Vector2(50,40)); phase=3
		elif phase==3 and title=="Cancel action 1":
			touch(true); phase=4
		elif phase==4 and title=="Cancel modal 2" and host.get_native_window_count()==1 and child_window(host)!=null and child_window(host).has_focus():
			touch(false); mouse(true,Vector2(25,25),child_window(host)); mouse(false,Vector2(25,25),child_window(host)); phase=5
		elif phase==5 and title=="Cancel returned 2" and host.get_native_window_count()==0 and get_window().has_focus():
			touch(true); touch(false); phase=6
		elif phase==6 and title=="Cancel action 2":
			key(true); phase=7
		elif phase==7 and title=="Cancel modal 3" and host.get_native_window_count()==1 and child_window(host)!=null and child_window(host).has_focus():
			# OS focus changes can swallow key-up. Repeats must stay canceled,
			# while the next fresh press after focus restoration must work.
			var repeat:=InputEventKey.new(); repeat.keycode=KEY_SPACE; repeat.unicode=32; repeat.pressed=true; repeat.echo=true
			Input.parse_input_event(repeat)
			mouse(true,Vector2(25,25),child_window(host)); mouse(false,Vector2(25,25),child_window(host)); phase=8
		elif phase==8 and title=="Cancel returned 3" and host.get_native_window_count()==0 and get_window().has_focus():
			key(true); key(false); phase=9
	if phase!=9 or DisplayServer.get_window_list().size()!=1:
		push_error("Cancellation coverage/native window count differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Cancellation GPU resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_INPUT_CANCEL_PASS"); get_tree().quit(0)
