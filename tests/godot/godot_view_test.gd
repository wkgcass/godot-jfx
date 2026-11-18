extends Node2D

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func pixel(image:Image, x:int, y:int) -> Color:
	return image.get_pixelv(Vector2i(pointer(Vector2(x,y))))

func pointer(point:Vector2) -> Vector2:
	if OS.get_environment("GODOT_JFX_TEST_VIEW_TRANSFORM") == "1":
		point = Vector2(.8*point.x-.15*point.y+50,.2*point.x+.9*point.y+10)
	return point*DisplayServer.screen_get_scale()

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("GodotViewProbe"):
		fail("GodotView Java probe startup failed")
		return
	var deadline := Time.get_ticks_msec()+40000
	var initial := false
	var animated := false
	var resized := false
	var inputs_checked := false
	var scene_id := 0
	var peak := 0
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("GodotView failed/timed out: "+host.get_runtime_error())
			return
		peak = maxi(peak,host.get_owned_resource_count())
		if not initial and host.get_completed_presentations() > 0 and host.get_child_count() == 2 and get_window().title == "GodotView ready":
			for frame in range(15):
				await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-view-initial.png"))
			var red := pixel(image,40,40)
			var alpha := pixel(image,68,40)
			var clipped := pixel(image,256,40)
			var translucent := pixel(image,220,40)
			print("GODOT_VIEW_INITIAL ",[red,alpha,clipped,translucent])
			# Non-axis-aligned NGNode clipping applies alpha in both the content
			# pass and final blend, matching stock D3D TransformClipReference.
			var expected_green := .75 if OS.get_environment("GODOT_JFX_TEST_VIEW_TRANSFORM") == "1" else .5
			if red.r < .95 or red.b > .05 or absf(alpha.r-.5) > .03 or alpha.g < .95 or clipped.r < .95 or clipped.g < .95 or absf(translucent.g-expected_green) > .03 or translucent.r < .95:
				fail("GodotView composition/clip/opacity mismatch")
				return
			var root = host.get_child(0).get_child(0)
			scene_id = root.get_instance_id()
			root.color = Color.BLUE
			root.queue_redraw()
			initial = true
		if initial and not animated:
			var c := pixel(get_viewport().get_texture().get_image(),40,40)
			if c.b > .95 and c.r < .05:
				animated = true
				var motion := InputEventMouseMotion.new(); motion.position = pointer(Vector2(40,40))
				Input.parse_input_event(motion)
				for pressed in [true,false]:
					var click := InputEventMouseButton.new(); click.position = pointer(Vector2(40,40))
					click.button_index = MOUSE_BUTTON_LEFT; click.pressed = pressed
					Input.parse_input_event(click)
				var key := InputEventKey.new(); key.keycode = KEY_SPACE; key.unicode = 32; key.pressed = true
				Input.parse_input_event(key)
				var wheel := InputEventMouseButton.new(); wheel.position = pointer(Vector2(40,40))
				wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.factor = 2; wheel.pressed = true
				Input.parse_input_event(wheel)
				var touch := InputEventScreenTouch.new(); touch.index = 7; touch.position = pointer(Vector2(30,40)); touch.pressed = true
				Input.parse_input_event(touch)
				var drag := InputEventScreenDrag.new(); drag.index = 7; drag.position = pointer(Vector2(40,40)); drag.relative = pointer(Vector2(10,0))-pointer(Vector2.ZERO)
				Input.parse_input_event(drag)
				touch = InputEventScreenTouch.new(); touch.index = 7; touch.position = pointer(Vector2(40,40)); touch.pressed = false
				Input.parse_input_event(touch)
				touch = InputEventScreenTouch.new(); touch.index = 8; touch.position = pointer(Vector2(40,40)); touch.pressed = true
				Input.parse_input_event(touch)
		if animated and not inputs_checked and host.get_child_count() == 2:
			var root = host.get_child(0).get_child(0)
			if root.mouse_events == 2 and root.mouse_releases == 2 and root.wheel_events == 1 and root.key_events == 1 and root.touch_events == 2 and root.touch_releases == 1 and root.drag_events == 1:
				if root.last_mouse_position.distance_to(Vector2(20,20)) > .01 or root.last_touch_position.distance_to(Vector2(20,20)) > .01 or root.last_key != KEY_SPACE or root.last_unicode != 32:
					fail("GodotView input coordinates/key translation differ: "+str([root.last_mouse_position,root.last_touch_position,root.last_key,root.last_unicode]))
					return
				inputs_checked = true
				if absf(root.wheel_factor-2) > .001:
					fail("GodotView wheel factor changed: "+str(root.wheel_factor))
					return
				var other = host.get_child(1).get_child(0)
				if other.mouse_events != 0 or other.key_events != 0 or other.touch_events != 0:
					fail("GodotView input leaked into its sibling scene")
					return
				var motion := InputEventMouseMotion.new(); motion.position = pointer(Vector2(240,150))
				Input.parse_input_event(motion)
				for pressed in [true,false]:
					var click := InputEventMouseButton.new(); click.position = pointer(Vector2(240,150))
					click.button_index = MOUSE_BUTTON_LEFT; click.pressed = pressed
					Input.parse_input_event(click)
		if inputs_checked and not resized and get_window().title == "GodotView resized" and host.get_child_count() == 2:
			var view = host.get_child(0)
			var image := get_viewport().get_texture().get_image()
			var marker := pixel(image,156,68)
			var old := pixel(image,108,68)
			if view.size == Vector2i(144,96) and marker.g > .95 and marker.r < .05 and old.r > .95 and old.b > .95:
				if view.get_child(0).key_releases != 1 or view.get_child(0).touch_releases != 2 or view.get_child(0).canceled_touches != 1:
					await get_tree().process_frame
					continue
				if view.get_child(0).get_instance_id() != scene_id or view.get_child(0).color != Color.BLUE:
					fail("GodotView layout resize reloaded its scene")
					return
				resized = true
				var touch := InputEventScreenTouch.new(); touch.index = 8; touch.position = pointer(Vector2(40,40)); touch.pressed = false
				Input.parse_input_event(touch)
				for pressed in [true,false]:
					touch = InputEventScreenTouch.new(); touch.index = 9; touch.position = pointer(Vector2(240,150)); touch.pressed = pressed
					Input.parse_input_event(touch)
				image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-view.png"))
		await get_tree().process_frame
	if not initial or not animated or not inputs_checked or not resized or get_window().title != "GodotView touched" or host.get_child_count() != 0 or peak > 180 or DisplayServer.get_window_list().size() != 1:
		fail("GodotView redraw/resize/cleanup/window check incomplete; peak="+str(peak))
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("GodotView host resources leaked")
		return
	host.free()
	print("GODOT_VIEW_PASS peak=",peak)
	get_tree().quit(0)

