extends Node2D

func click(window, point: Vector2) -> void:
	point*=DisplayServer.screen_get_scale(window.current_screen)
	var motion:=InputEventMouseMotion.new(); motion.window_id=window.get_window_id(); motion.position=point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var button:=InputEventMouseButton.new(); button.window_id=window.get_window_id(); button.position=point; button.button_index=MOUSE_BUTTON_LEFT; button.pressed=pressed
		Input.parse_input_event(button)

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),ProjectSettings.globalize_path("res://../../artifacts/reference"),"ModalProbe"):
		push_error("Modal JVM failed to start"); get_tree().quit(1); return
	var phase:=0
	var deadline:=Time.get_ticks_msec()+35000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Modal failed/timed out phase=%d title=%s native=%d root_enabled=%s: %s" % [phase,get_window().title,host.get_native_window_count(),host.is_window_input_enabled(0),host.get_runtime_error()]); get_tree().quit(1); return
		await RenderingServer.frame_post_draw
		var title:=get_window().title
		var count:int=host.get_native_window_count()
		if phase==0 and title=="Modal ready" and count==1:
			click(get_window(),Vector2(30,25)); phase=1
		elif phase==1 and title=="Outer window active" and count==2:
			if host.is_window_input_enabled(0) or not host.is_window_input_enabled(2) or not host.is_window_input_enabled(3): continue
			click(get_window(),Vector2(30,75)); click(host.get_native_window(2),Vector2(25,25)); phase=2
		elif phase==2 and title=="Independent action 1":
			click(host.get_native_window(3),Vector2(25,25)); phase=3
		elif phase==3 and title=="Inner active" and count==3:
			if host.is_window_input_enabled(0) or host.is_window_input_enabled(3) or not host.is_window_input_enabled(4): continue
			var captured:=false
			for frame in range(120):
				await RenderingServer.frame_post_draw
				var image:Image=host.get_native_window(4).get_texture().get_image()
				var dark:=0
				for y in range(0,image.get_height(),2):
					for x in range(0,image.get_width(),2):
						if image.get_pixel(x,y).get_luminance()<0.5:dark+=1
				if dark>20:
					image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/modal-nested.png"));captured=true;break
			if not captured:
				push_error("Nested modal content never reached GPU output");get_tree().quit(1);return
			click(host.get_native_window(3),Vector2(25,75)); click(get_window(),Vector2(30,75)); click(host.get_native_window(4),Vector2(25,25)); phase=4
		elif phase==4 and title=="Inner returned" and count==2:
			if host.is_window_input_enabled(0) or not host.is_window_input_enabled(3): continue
			click(get_window(),Vector2(30,75)); click(host.get_native_window(3),Vector2(25,75)); phase=5
		elif phase==5 and title=="Outer window returned" and count==1:
			if not host.is_window_input_enabled(0) or not host.is_window_input_enabled(2): continue
			click(get_window(),Vector2(30,75)); phase=6
		elif phase==6 and title=="Parent action 1":
			click(get_window(),Vector2(30,25)); phase=7
		elif phase==7 and title=="Outer app active" and count==2:
			if host.is_window_input_enabled(0) or host.is_window_input_enabled(2) or not host.is_window_input_enabled(5): continue
			click(get_window(),Vector2(30,75)); click(host.get_native_window(2),Vector2(25,25)); click(host.get_native_window(5),Vector2(25,75)); phase=8
		elif phase==8 and title=="Outer app returned" and count==1:
			if not host.is_window_input_enabled(0) or not host.is_window_input_enabled(2): continue
			click(get_window(),Vector2(30,75)); phase=9
	if phase!=9 or DisplayServer.get_window_list().size()!=1:
		push_error("Modal interaction/native window coverage differs"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Modal resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_MODALS_PASS"); get_tree().quit(0)
