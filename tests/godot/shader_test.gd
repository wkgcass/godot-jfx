extends Node2D

func _ready() -> void:
	var root := ProjectSettings.globalize_path("res://../../jfx/modules/javafx.graphics/build/gensrc/")
	var paths := [root + "jsl-prism/com/sun/prism/godot/shaders/", root + "jsl-decora/com/sun/scenario/effect/impl/godot/shaders/"]
	var count := 0
	for directory in paths:
		var files := DirAccess.get_files_at(directory)
		if files.is_empty():
			push_error("Generated Godot shaders missing: " + directory)
			get_tree().quit(1)
			return
		for name in files:
			if not name.ends_with(".gdshader"):
				continue
			print("CHECK_SHADER ", name)
			var shader := Shader.new()
			shader.code = FileAccess.get_file_as_string(directory + name)
			shader.get_shader_uniform_list()
			count += 1
		await get_tree().process_frame
	var surface = ClassDB.instantiate("JavaFXRenderSurface")
	add_child(surface)
	surface.set_draw_shader_code(FileAccess.get_file_as_string(paths[0] + "FillPgram_Color.gdshader"))
	var vertices := PackedFloat32Array([
		16.25, 16, 0, -80, -48, 40, 24,
		16.25, 112, 0, -80, 48, 40, 24,
		176.25, 16, 0, 80, -48, 40, 24,
		176.25, 112, 0, 80, 48, 40, 24])
	var colors := PackedByteArray([51, 102, 153, 255, 51, 102, 153, 255, 51, 102, 153, 255, 51, 102, 153, 255])
	surface.add_prism_quads(vertices, colors)
	for frame in range(8):
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var center := image.get_pixel(96, 64)
	var outside := image.get_pixel(24, 24)
	var edge := image.get_pixel(56, 64)
	if abs(center.r - 0.2) > 0.03 or abs(center.g - 0.4) > 0.03 or abs(center.b - 0.6) > 0.03 or abs(outside.r - 0.92) > 0.03 or abs(edge.r - 0.38) > 0.04 or abs(edge.g - 0.5375) > 0.04 or abs(edge.b - 0.695) > 0.04:
		push_error("Generated Prism mask shader pixels differ: " + str(center) + " / " + str(outside))
		get_tree().quit(1)
		return
	if image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-generated-shader.png")) != OK:
		push_error("Cannot save generated shader GPU capture")
		get_tree().quit(1)
		return
	# Three overlapping draws retain their own uniform/code revisions. Later
	# parameter replacement (including dropping a value) cannot recolor them.
	for cycle in range(100):
		surface.clear_commands()
		# Geometry reuse lives in the bounded mesh cache (get_cached_mesh_count),
		# outside this per-clear hygiene count; the single batch above must not grow.
		if surface.get_owned_resource_count() != 8 or surface.get_cached_mesh_count() != 1:
			push_error("Draw state resources grew after clear")
			get_tree().quit(1)
			return
		surface.set_draw_shader_code("shader_type canvas_item; render_mode unshaded, blend_premul_alpha; uniform vec4 tint = vec4(1.0); void fragment() { COLOR = tint; }")
		surface.set_draw_shader_parameters({"tint": Vector4(1, 0, 0, 1)})
		surface.add_rectangle(Rect2(10, 10, 100, 80), Color.WHITE)
		surface.set_draw_shader_parameters({"tint": Vector4(0, 1, 0, 1)})
		surface.add_rectangle(Rect2(60, 10, 100, 80), Color.WHITE)
		surface.set_draw_shader_code("shader_type canvas_item; render_mode unshaded, blend_premul_alpha; void fragment() { COLOR = vec4(0.0, 0.0, 1.0, 1.0); }")
		surface.add_rectangle(Rect2(110, 10, 100, 80), Color.WHITE)
		if surface.get_owned_resource_count() != 14:
			push_error("Unexpected draw state resource ownership")
			get_tree().quit(1)
			return
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
	for frame in range(4):
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	var red := image.get_pixel(35, 40)
	var green := image.get_pixel(85, 40)
	var blue := image.get_pixel(135, 40)
	if red.r < 0.95 or red.g > 0.05 or green.g < 0.95 or green.r > 0.05 or blue.b < 0.95 or blue.g > 0.05:
		push_error("Draw material revision/order mismatch: " + str([red, green, blue]))
		get_tree().quit(1)
		return
	if image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-shader-states.png")) != OK:
		push_error("Cannot save material state GPU capture")
		get_tree().quit(1)
		return
	remove_child(surface)
	if surface.get_owned_resource_count() != 0 or surface.get_cached_mesh_count() != 0:
		push_error("Generated shader fixture leaked resources")
		get_tree().quit(1)
		return
	surface.free()
	print("GODOT_SHADER_PASS count=", count)
	get_tree().quit(0)
