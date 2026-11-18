extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("LcdOverlapProbe"):
		push_error("LCD probe probe failed"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+30000
	var captured := false
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec()>deadline:
			push_error("LCD probe failed/timed out"); get_tree().quit(1); return
		await get_tree().process_frame
		if not captured and get_window().title == "LCD_OVERLAP_READY":
			await RenderingServer.frame_pre_draw
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			if image == null or image.is_empty():
				push_error("LCD capture missing image"); get_tree().quit(1); return
			var suffix := OS.get_environment("GODOT_JFX_LCD_SCREEN")
			var save_error := image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/lcd-overlap-"+suffix+".png"))
			if save_error != OK:
				push_error("LCD capture save failed: " + str(save_error)); get_tree().quit(1); return
			if suffix == "1":
				var reference := Image.load_from_file(ProjectSettings.globalize_path("res://../../artifacts/reference/lcd-overlap-0.png"))
				if reference == null or reference.get_size() != image.get_size():
					push_error("LCD reference missing or size differs"); get_tree().quit(1); return
				var differences := 0
				var ink := 0
				for y in range(image.get_height()):
					for x in range(image.get_width()):
						var a := reference.get_pixel(x,y); var b := image.get_pixel(x,y)
						if a.r < 0.9 or a.g < 0.9 or a.b < 0.9: ink += 1
						if abs(a.r-b.r)>2.0/255.0 or abs(a.g-b.g)>2.0/255.0 or abs(a.b-b.b)>2.0/255.0 or abs(a.a-b.a)>2.0/255.0: differences += 1
				print("LCD_OVERLAP_DIFF pixels=",differences," ink=",ink)
				if differences != 0 or ink < 100:
					push_error("LCD overlap differs from LCDBuffer reference"); get_tree().quit(1); return
				print("LCD_OVERLAP_DIFF_PASS")
			captured = true
			for pressed in [true,false]:
				var event := InputEventMouseButton.new(); event.position=Vector2(10,165); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
				Input.parse_input_event(event)
	remove_child(host); host.free()
	if not captured: push_error("LCD capture missing"); get_tree().quit(1); return
	print("LCD_OVERLAP_CAPTURE_PASS"); get_tree().quit(0)
