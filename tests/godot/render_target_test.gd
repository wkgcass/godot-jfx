extends Node2D

func _ready() -> void:
	# A queued draw must not depend on a target object that the caller may
	# immediately release. Native RID destruction stays ordered after draws.
	for cycle in range(128):
		var transient = ClassDB.instantiate("JavaFXRenderTarget")
		if not transient.initialize(Vector2i(8,8), true):
			fail("Cannot allocate transient Viewport target"); return
		transient.begin_pass(true)
		transient.add_rectangle(Rect2(0,0,8,8), Color.RED)
		transient.end_pass()
		transient.draw_offscreen_pass()
		var transient_id: int = transient.get_instance_id()
		transient = null
		if is_instance_id_valid(transient_id):
			fail("Dispatched target object retained after release"); return
	var surface = ClassDB.instantiate("JavaFXRenderSurface")
	add_child(surface)
	var proxy_count:=int(OS.get_environment("GODOT_JFX_ASYNC_TARGET_TEXTURE")=="1")
	for cycle in range(100):
		var source = ClassDB.instantiate("JavaFXRenderTarget")
		var target = ClassDB.instantiate("JavaFXRenderTarget")
		if not source.initialize(Vector2i(32,32)) or not target.initialize(Vector2i(128,64)):
			fail("Cannot allocate GPU render targets")
			return
		# Fresh targets must initialize transparent even for a preserving pass.
		source.begin_pass(false)
		var vertices := PackedFloat32Array([0,0,0,0,0,0,0, 0,32,0,0,1,0,0, 32,0,0,1,0,0,0, 32,32,0,1,1,0,0])
		var colors := PackedByteArray([255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255])
		source.draw_prism_quads(vertices, colors,
			"shader_type canvas_item; render_mode unshaded, blend_premul_alpha; uniform vec4 tint; void fragment() { COLOR = tint; }",
			{"tint":Vector4(0.5,0,0,0.5)}, true, Rect2i(0,0,16,32))
		source.end_pass()
		target.begin_pass(true)
		target.copy_target(source, Rect2(0,0,64,64))
		target.add_rectangle(Rect2(64,0,64,64), Color.BLUE)
		target.end_pass()
		# Pass geometry lives in the bounded content cache now: one entry for
		# the quad batch, kept out of the per-pass hygiene count.
		if source.get_owned_resource_count() != 8+proxy_count or target.get_owned_resource_count() != 7+proxy_count or source.get_cached_mesh_count() != 1:
			fail("Unexpected render target allocation count")
			return
		var source_id: int = source.get_instance_id()
		var target_id: int = target.get_instance_id()
		surface.add_render_target(target, Rect2(16,16,128,64))
		source = null
		target = null
		if not is_instance_id_valid(source_id) or not is_instance_id_valid(target_id):
			fail("Sampled target was released before draw completion")
			return
		for frame in range(3):
			await RenderingServer.frame_pre_draw
			await RenderingServer.frame_post_draw
		if cycle == 99:
			var image := get_viewport().get_texture().get_image()
			var translucent := image.get_pixel(32,32)
			var blue := image.get_pixel(112,32)
			var clipped := image.get_pixel(64,32)
			if abs(clipped.r - 0.92) > 0.03 or abs(clipped.g - 0.95) > 0.03 or abs(clipped.b - 0.98) > 0.03:
				fail("Offscreen Prism clip/initialization differs: " + str(clipped))
				return
			if abs(translucent.r - 0.96) > 0.04 or abs(translucent.g - 0.475) > 0.04 or abs(translucent.b - 0.49) > 0.04 or blue.b < 0.95 or blue.r > 0.05:
				fail("GPU render-target copy/alpha differs: " + str([translucent,blue]))
				return
			if image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-render-targets.png")) != OK:
				fail("Cannot save render-target capture")
				return
		surface.clear_commands()
		if is_instance_id_valid(source_id) or is_instance_id_valid(target_id):
			fail("Render-target reference chain leaked after clear")
			return
	remove_child(surface)
	if surface.get_owned_resource_count() != 0:
		fail("Render target presentation resources leaked")
		return
	surface.free()
	print("RENDER_TARGET_PASS: 128 submit/release targets, 100 GPU copies, premultiplied alpha, retained source lifetime")
	get_tree().quit(0)

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
