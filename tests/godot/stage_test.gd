extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "StageProbe"):
		push_error("Stage JVM startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 40000
	var checked := false
	var peak_resources := 0
	var keyboard_sent := false
	var interaction_checked := false
	var initial_text_hash := 0
	# Keep fractional DPI (e.g. 1.25/1.5); round only at image pixel boundaries.
	var ps := 1.0
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Stage probe failed/timed out: " + host.get_runtime_error())
			host.stop_jvm()
			get_tree().quit(1)
			return
		peak_resources = maxi(peak_resources, host.get_owned_resource_count())
		if not checked and get_window().title == "Stage dynamic complete":
			# The Glass title update runs ahead of Prism's queued GPU passes.
			# Wait for the final rectangle position, with a bounded failure path.
			var image: Image
			for frame in range(120):
				await RenderingServer.frame_post_draw
				peak_resources = maxi(peak_resources, host.get_owned_resource_count())
				image = get_viewport().get_texture().get_image()
				ps = maxf(1.0, float(image.get_width()) / 400.0)
				var old_position := image.get_pixel(roundi(140*ps),roundi(40*ps))
				var final_position := image.get_pixel(roundi(40*ps),roundi(40*ps))
				if old_position.r > .95 and old_position.g > .95 and old_position.b > .95 and absf(final_position.g-.2) < .04:
					break
			var purple := image.get_pixel(roundi(40*ps),roundi(40*ps))
			var green := image.get_pixel(roundi(240*ps),roundi(40*ps))
			var cleared := image.get_pixel(roundi(140*ps),roundi(40*ps))
			var blur_center := image.get_pixel(roundi(30*ps),roundi(200*ps))
			var blur_edge := image.get_pixel(roundi(18*ps),roundi(200*ps))
			var shadow_body := image.get_pixel(roundi(130*ps),roundi(200*ps))
			var shadow_edge := image.get_pixel(roundi(153*ps),roundi(211*ps))
			print("STAGE_EFFECT_PIXELS ", [blur_center,blur_edge,shadow_body,shadow_edge])
			if blur_center.r < 0.9 or blur_center.g > 0.15 or blur_edge.g < 0.2 or blur_edge.g > 0.99 or shadow_body.b < 0.9 or shadow_body.r > 0.1 or shadow_edge.r > 0.97:
				push_error("GaussianBlur/DropShadow pixels differ: " + str([blur_center,blur_edge,shadow_body,shadow_edge]))
				get_tree().quit(1)
				return
			var text_pixels := 0
			for y in range(roundi(140*ps),roundi(160*ps)):
				for x in range(roundi(16*ps),roundi(125*ps)):
					var c := image.get_pixel(x,y)
					if c.r < 0.65 and c.g < 0.65 and c.b < 0.65:
						text_pixels += 1
			var button_pixel := image.get_pixel(roundi(201*ps),roundi(150*ps))
			initial_text_hash = hash(image.get_region(Rect2i(roundi(16*ps),roundi(140*ps),roundi(140*ps),roundi(24*ps))).get_data())
			if text_pixels < 80*ps*ps or button_pixel.r > 0.95:
				push_error("Control text/background missing")
				get_tree().quit(1)
				return
			print("STAGE_DYNAMIC_RESOURCES peak=", peak_resources, " final=", host.get_owned_resource_count(), " sequence=", host.get_applied_sequence())
			if host.get_applied_sequence() < 20 or peak_resources > 128 or cleared.r < 0.95 or cleared.g < 0.95 or cleared.b < 0.95:
				push_error("Dynamic redraw failed or retained resource history grew: " + str(cleared))
				get_tree().quit(1)
				return
			if abs(purple.r - 0.8) > 0.04 or abs(purple.g - 0.2) > 0.04 or abs(purple.b - 0.6) > 0.04 or green.g < 0.95 or green.r > 0.05 or DisplayServer.get_window_list().size() != 1:
				push_error("Stage pixels/window ownership differ: " + str([purple,green]))
				get_tree().quit(1)
				return
			if image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-stage.png")) != OK:
				push_error("Stage GPU capture failed")
				get_tree().quit(1)
				return
			checked = true
			# Synthetic input travels the same physical-pixel path as OS events:
			# Quantum divides forwarded coordinates by the FX platform scale, so
			# logical scene targets must be injected scaled up at HiDPI.
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(230*ps,151*ps)
			Input.parse_input_event(motion)
			for pressed in [true,false]:
				var click := InputEventMouseButton.new()
				click.position = Vector2(230*ps,151*ps)
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				Input.parse_input_event(click)
		if checked and not keyboard_sent and get_window().title == "Button action 1":
			var first_action_hash := initial_text_hash
			for frame in range(90):
				await RenderingServer.frame_post_draw
				first_action_hash = hash(get_viewport().get_texture().get_image().get_region(Rect2i(roundi(16*ps),roundi(140*ps),roundi(140*ps),roundi(24*ps))).get_data())
				if first_action_hash != initial_text_hash:
					break
			if first_action_hash == initial_text_hash:
				push_error("Mouse button action did not render updated Label")
				get_tree().quit(1)
				return
			initial_text_hash = first_action_hash
			for pressed in [true,false]:
				var key := InputEventKey.new()
				key.keycode = KEY_SPACE
				key.unicode = 32
				key.pressed = pressed
				Input.parse_input_event(key)
			keyboard_sent = true
		if keyboard_sent and not interaction_checked and get_window().title == "Button action 2":
			var updated_image: Image
			for frame in range(90):
				await RenderingServer.frame_post_draw
				updated_image = get_viewport().get_texture().get_image()
				if hash(updated_image.get_region(Rect2i(roundi(16*ps),roundi(140*ps),roundi(140*ps),roundi(24*ps))).get_data()) != initial_text_hash:
					break
			if hash(updated_image.get_region(Rect2i(roundi(16*ps),roundi(140*ps),roundi(140*ps),roundi(24*ps))).get_data()) == initial_text_hash:
				push_error("Button actions did not update rendered Label text")
				get_tree().quit(1)
				return
			if updated_image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-stage-interaction.png")) != OK:
				push_error("Cannot save interactive control capture")
				get_tree().quit(1)
				return
			interaction_checked = true
		await get_tree().process_frame
	if not checked or not keyboard_sent or not interaction_checked or get_window().title != "Button action 2":
		push_error("Stage rendering or control interaction was incomplete")
		get_tree().quit(1)
		return
	var launches: int = host.get_render_stats()["java_launch_upcalls"]
	if launches != 1:
		push_error("Expected one scene host launch, observed " + str(launches))
		get_tree().quit(1)
		return
	print("STAGE_HOST_JAVA_LAUNCHES ", launches)
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Stage host resources not released")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_STAGE_PASS")
	get_tree().quit(0)
