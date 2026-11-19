extends Node2D

func _ready() -> void:
	if not ClassDB.class_exists("JavaFXHost"):
		push_error("JavaFXHost is missing")
		get_tree().quit(1)
		return
	if ClassDB.class_has_method("JavaFXHost", "start_jvm"):
		push_error("The packaged host still exposes the legacy JVM launcher")
		get_tree().quit(1)
		return
	var host = ClassDB.instantiate("JavaFXHost")
	host.position = Vector2(32, 32)
	add_child(host)
	var stop_from_host := OS.get_environment("GODOT_JFX_TEST_STOP") == "1"
	var main_class := "BridgeStopProbe" if stop_from_host else "BridgeProbe"
	var encoded := OS.get_environment("GODOT_JFX_TEST_ENCODED") == "1"
	var expected_sequence := 32 if encoded else 1
	if encoded:
		main_class = "RenderCommandsProbe"
	var textures := OS.get_environment("GODOT_JFX_TEST_TEXTURES") == "1"
	if textures:
		main_class = "TextureCommandsProbe"
	var prism_textures := OS.get_environment("GODOT_JFX_TEST_PRISM_TEXTURES") == "1"
	var shader_states := OS.get_environment("GODOT_JFX_TEST_SHADER_STATES") == "1"
	var prism_context := OS.get_environment("GODOT_JFX_TEST_CONTEXT") == "1"
	if prism_context:
		main_class = "PrismContextProbe"
	if shader_states:
		main_class = "ShaderCommandsProbe"
	if prism_textures:
		main_class = "PrismTextureProbe"
		expected_sequence = 2
	if not host.run_fixture_probe(main_class):
		push_error("Java probe startup was rejected")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 30000
	if encoded:
		# Prove FULL/retry against the real bounded native queue. Keep the
		# scene alive while deliberately withholding host command consumption.
		host.set_process(false)
		while host.get_backpressure_count() == 0:
			if Time.get_ticks_msec() > deadline or host.get_runtime_status() == "failed":
				push_error("Encoder did not reach the native backpressure path")
				host.stop_host()
				get_tree().quit(1)
				return
			await get_tree().process_frame
		host.set_process(true)
		print("ENCODER_BACKPRESSURE_OBSERVED")
	var frames_after_submit := 0
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("probe failed or timed out: " + host.get_runtime_error())
			host.stop_host()
			get_tree().quit(1)
			return
		if stop_from_host and host.get_applied_sequence() == expected_sequence:
			frames_after_submit += 1
			if frames_after_submit == 20:
				host.stop_host()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if OS.get_environment("GODOT_JFX_PROFILE_COMMANDS")=="1":print("BRIDGE_PATCH_PROFILE ",JSON.stringify(host.get_render_stats()))
	var pixel := image.get_pixel(64, 64)
	var mesh_pixel := image.get_pixel(248 if textures else 272, 64)
	if mesh_pixel.g < 0.95 or mesh_pixel.r > 0.05 or mesh_pixel.b > 0.05:
		push_error("Prism quad batch did not render: " + str(mesh_pixel))
		get_tree().quit(1)
		return
	if host.get_applied_sequence() != expected_sequence or abs(pixel.r - 0.8) > 0.06 or abs(pixel.g - 0.2) > 0.06 or abs(pixel.b - 0.6) > 0.06:
		push_error("JNI frame was not rendered: " + str(pixel))
		get_tree().quit(1)
		return
	var output := ProjectSettings.globalize_path("res://../../artifacts/reference/godot-bridge.png")
	if prism_context:
		output = ProjectSettings.globalize_path("res://../../artifacts/reference/godot-prism-context.png")
		var clipped := image.get_pixel(62,182)
		var initialized_target := image.get_pixel(372,252)
		if abs(initialized_target.r - 0.92) > 0.03 or abs(initialized_target.g - 0.95) > 0.03 or abs(initialized_target.b - 0.98) > 0.03:
			push_error("Java RTTexture was not initialized transparent: " + str(initialized_target))
			get_tree().quit(1)
			return
		var excluded := image.get_pixel(42,162)
		var restored := image.get_pixel(172,192)
		var partial_clear := image.get_pixel(167,187)
		var clear_quad := image.get_pixel(157,177)
		var source_replace := image.get_pixel(262,192)
		if abs(partial_clear.r - 0.46) > 0.04 or abs(partial_clear.g - 0.475) > 0.04 or abs(partial_clear.b - 0.99) > 0.04 or abs(clear_quad.r - 0.92) > 0.03 or abs(source_replace.r - 0.96) > 0.04 or abs(source_replace.g - 0.475) > 0.04 or abs(source_replace.b - 0.49) > 0.04:
			push_error("Prism clear/SRC premultiplied pixels differ: " + str([partial_clear, clear_quad, source_replace]))
			get_tree().quit(1)
			return
		if clipped.b < 0.95 or clipped.r > 0.05 or abs(excluded.r - 0.92) > 0.03 or restored.r < 0.95 or restored.g > 0.05:
			push_error("Prism scissor switch/empty/reset differs: " + str([clipped, excluded, restored]))
			get_tree().quit(1)
			return
	if prism_context:
		host.clear_commands()
		if host.get_owned_resource_count() != 8:
			push_error("Prism RT allocation/retired resources leaked after clear")
			get_tree().quit(1)
			return
	if shader_states:
		output = ProjectSettings.globalize_path("res://../../artifacts/reference/godot-shader-bridge.png")
		if host.get_owned_resource_count() != 13:
			push_error("Shader snapshot resource count differs: " + str(host.get_owned_resource_count()))
			get_tree().quit(1)
			return
		host.clear_commands()
		if host.get_owned_resource_count() != 8:
			push_error("Shader snapshot resources leaked after clear")
			get_tree().quit(1)
			return
	if prism_textures:
		output = ProjectSettings.globalize_path("res://../../artifacts/reference/godot-prism-textures.png")
		var blue := image.get_pixel(372, 64)
		var gray := image.get_pixel(64, 192)
		var alpha := image.get_pixel(272, 192)
		var large := image.get_pixel(372, 192)
		var float_corner:=image.get_pixel(154,178)
		var float_patch:=image.get_pixel(200,224)
		if float_corner.b<0.95 or float_corner.r>0.05 or abs(float_patch.r-.2)>0.03 or abs(float_patch.g-.7)>0.03 or abs(float_patch.b-.1)>0.03:
			push_error("Float texture partial upload changed the patch or untouched corner");get_tree().quit(1);return
		if blue.b < 0.95 or blue.r > 0.05 or blue.g > 0.05 or abs(gray.r - 0.502) > 0.03 or abs(gray.g - 0.502) > 0.03 or abs(gray.b - 0.502) > 0.03 or abs(alpha.r - 0.96) > 0.03 or abs(alpha.g - 0.975) > 0.03 or abs(alpha.b - 0.99) > 0.03 or large.r < 0.95 or abs(large.g - 0.502) > 0.03 or large.b > 0.05 or host.get_owned_resource_count() != 15:
			push_error("Prism texture format conversion or retained resource count differs: owned=%d blue=%s gray=%s alpha=%s large=%s"%[host.get_owned_resource_count(),blue,gray,alpha,large])
			get_tree().quit(1)
			return
		host.clear_commands()
		if host.get_owned_resource_count() != 8:
			push_error("Prism textures leaked after command clear")
			get_tree().quit(1)
			return
	if textures:
		output = ProjectSettings.globalize_path("res://../../artifacts/reference/godot-texture-versions.png")
		var blue := image.get_pixel(372, 64)
		var untouched := image.get_pixel(296, 112)
		var initialized := image.get_pixel(64, 192)
		var atlas := image.get_pixel(372, 192)
		if abs(untouched.r - 0.8) > 0.06 or abs(untouched.g - 0.2) > 0.06 or abs(untouched.b - 0.6) > 0.06 or abs(initialized.r - 0.92) > 0.03 or abs(initialized.g - 0.95) > 0.03 or atlas.b < 0.95 or atlas.r > 0.05:
			push_error("Texture patch changed untouched pixels, zero initialization or large atlas differs")
			get_tree().quit(1)
			return
		if blue.b < 0.95 or blue.r > 0.05 or blue.g > 0.05 or host.get_owned_resource_count() != 13:
			push_error("Texture versioning, slot reuse or retained resources differ: owned=%d blue=%s"%[host.get_owned_resource_count(),blue])
			get_tree().quit(1)
			return
		host.clear_commands()
		if host.get_owned_resource_count() != 8:
			push_error("Clear failed to release retired texture revisions")
			get_tree().quit(1)
			return
	if image.save_png(output) != OK:
		push_error("Cannot write bridge rendering capture")
		get_tree().quit(1)
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Host did not release rendering resources")
		get_tree().quit(1)
		return
	host.free()
	print("M2_BRIDGE_PASS: probe finished, Java buffer copied, commands applied on Godot main thread")
	get_tree().quit(0)
