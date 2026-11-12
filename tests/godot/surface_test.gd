extends Node2D

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _ready() -> void:
	# ClassDB construction reports missing native module as a test failure.
	if not ClassDB.class_exists("JavaFXRenderSurface"):
		push_error("JavaFX custom module is missing")
		get_tree().quit(1)
		return
	var surface = ClassDB.instantiate("JavaFXRenderSurface")
	surface.position = Vector2(32, 32)
	add_child(surface)
	check(surface.get_owned_resource_count() == 8, "Initial RID ownership mismatch")
	surface.set_surface_size(Vector2i(400, 240))
	surface.add_rectangle(Rect2(16, 16, 96, 64), Color(0.25, 0.5, 1.0, 1.0))
	var pixels := PackedByteArray([0, 255, 0, 255, 0, 255, 0, 255,
		0, 255, 0, 255, 0, 255, 0, 255])
	surface.upload_rgba(Vector2i(2, 2), pixels)
	surface.add_texture(Rect2(160, 16, 96, 64), Color.WHITE)
	surface.set_shader_code("shader_type canvas_item; render_mode unshaded; void fragment() { vec4 c = texture(TEXTURE, UV); COLOR = vec4(c.rgb * 0.8, c.a); }")
	check(surface.get_owned_resource_count() == 9, "Texture/shader RID ownership mismatch")
	# Real GPU draws complete before readback, which is used only for testing.
	for frame in range(8):
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(not image.is_empty(), "Viewport capture is empty")
	if not image.is_empty():
		var blue := image.get_pixel(64, 64)
		var green := image.get_pixel(224, 64)
		check(abs(blue.b - 0.8) < 0.06 and blue.r < 0.3, "Rectangle or shader output differs: " + str(blue))
		check(abs(green.g - 0.8) < 0.06 and green.r < 0.05, "Uploaded texture or shader output differs: " + str(green))
		var output := ProjectSettings.globalize_path("res://../../artifacts/reference/godot-m1.png")
		check(image.save_png(output) == OK, "Could not write M1 capture")
		print("M1_CAPTURE ", output)
	remove_child(surface)
	check(surface.get_owned_resource_count() == 0, "Exit-tree failed to release RIDs")
	surface.free()
	var vertices := PackedFloat32Array([
		16, 16, 0, 0.25, 0.5, 0.75, 0.125,
		16, 112, 0, 0.25, 0.5, 0.75, 0.125,
		176, 16, 0, 0.25, 0.5, 0.75, 0.125,
		176, 112, 0, 0.25, 0.5, 0.75, 0.125])
	var colors := PackedByteArray([51, 102, 153, 255, 51, 102, 153, 255,
		51, 102, 153, 255, 51, 102, 153, 255])
	var mesh_surface = ClassDB.instantiate("JavaFXRenderSurface")
	mesh_surface.position = Vector2(32, 32)
	add_child(mesh_surface)
	mesh_surface.set_draw_shader_code("shader_type canvas_item; render_mode unshaded; varying vec2 prism_uv1; void vertex() { prism_uv1 = CUSTOM0.xy; } void fragment() { COLOR = vec4(UV.x, prism_uv1.x, COLOR.b, 1.0); }")
	mesh_surface.add_prism_quads(vertices, colors)
	# Geometry now lives in the bounded content cache (see get_cached_mesh_count),
	# outside the per-draw ownership count.
	check(mesh_surface.get_owned_resource_count() == 8 and mesh_surface.get_cached_mesh_count() == 1, "Prism mesh RID count differs")
	for frame in range(8):
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
	var mesh_image := get_viewport().get_texture().get_image()
	var attributes := mesh_image.get_pixel(64, 64)
	check(abs(attributes.r - 0.25) < 0.03 and abs(attributes.g - 0.75) < 0.03 and abs(attributes.b - 0.6) < 0.03,
		"Prism UV0/UV1/color channels differ: " + str(attributes))
	check(mesh_image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-prism-vertices.png")) == OK, "Cannot save Prism vertex capture")
	mesh_surface.clear_commands()
	check(mesh_surface.get_owned_resource_count() == 8 and mesh_surface.get_cached_mesh_count() == 1,
		"Clear did not release draw state or preserve reusable geometry")
	mesh_surface.set_draw_shader_code("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;")
	var translucent := PackedByteArray([128, 0, 0, 128, 128, 0, 0, 128, 128, 0, 0, 128, 128, 0, 0, 128])
	mesh_surface.add_prism_quads(vertices, translucent)
	for frame in range(8):
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
	var alpha_pixel := get_viewport().get_texture().get_image().get_pixel(64, 64)
	check(abs(alpha_pixel.r - 0.96) < 0.03 and abs(alpha_pixel.g - 0.475) < 0.03 and abs(alpha_pixel.b - 0.49) < 0.03,
		"Premultiplied alpha was multiplied twice or lost: " + str(alpha_pixel))
	remove_child(mesh_surface)
	check(mesh_surface.get_owned_resource_count() == 0 and mesh_surface.get_cached_mesh_count() == 0, "Mesh surface leaked resources or cached geometry")
	mesh_surface.free()
	for iteration in range(100):
		var temporary = ClassDB.instantiate("JavaFXRenderSurface")
		add_child(temporary)
		temporary.set_surface_size(Vector2i(64 + iteration, 64))
		temporary.add_rectangle(Rect2(0, 0, 32, 32), Color.RED)
		temporary.add_prism_quads(vertices, colors)
		remove_child(temporary)
		check(temporary.get_owned_resource_count() == 0 and temporary.get_cached_mesh_count() == 0, "Resource or geometry-cache leak at iteration " + str(iteration))
		temporary.free()
	# Allow deferred rendering-server frees to drain before exiting.
	await RenderingServer.frame_pre_draw
	await RenderingServer.frame_post_draw
	print("M1_RESULT ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
