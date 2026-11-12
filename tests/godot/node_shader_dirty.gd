extends Node2D

func pixel(image: Image, x: int, y: int) -> Color:
	return image.get_pixelv(Vector2i(Vector2(x, y) * DisplayServer.screen_get_scale()))

func white(color: Color) -> bool:
	return color.r > .95 and color.g > .95 and color.b > .95

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "NodeShaderDirtyProbe"):
		push_error("Dirty shader JVM startup failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 20000
	var phase := -1
	var warmup := 0
	var samples := [0, 0]
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Dirty shader timed out/failed: " + host.get_runtime_error())
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		# Window teardown can finish while waiting for the GPU frame.
		if host.get_runtime_status() == "finished" or host.get_window_count() == 0: continue
		var title := get_window().title
		var current := 0 if title == "Shader dirty 0" else (1 if title == "Shader dirty 1" else -1)
		if current < 0: continue
		if phase != current:
			phase = current
			warmup = 0
		warmup += 1
		if warmup < 30: continue
		var image := get_viewport().get_texture().get_image()
		var expected := pixel(image, 225 if phase == 0 else 165, 80)
		var source := pixel(image, 55 if phase == 0 else 115, 80)
		var old := pixel(image, 165 if phase == 0 else 225, 80)
		if not white(source) or not white(old) or expected.r < .95 or expected.g < .35 or expected.g > .75 or absf(expected.g - expected.b) > .03:
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/node-shader-dirty-failure.png"))
			push_error("Dirty shader stale/unwarped output phase=%s colors=%s" % [phase, [expected, source, old]])
			get_tree().quit(1)
			return
		samples[phase] += 1
		if samples[phase] == 1:
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/node-shader-dirty-%s.png" % phase))
	remove_child(host)
	if samples[0] < 10 or samples[1] < 10 or host.get_owned_resource_count() != 0:
		push_error("Dirty shader insufficient samples or retained resources: %s" % [samples])
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_NODE_SHADER_DIRTY_PASS samples=", samples)
	get_tree().quit()
