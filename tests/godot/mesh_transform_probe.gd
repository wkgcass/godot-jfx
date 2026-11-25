extends Node2D

# Diagnostic: verifies that a QUADS record whose vertices are in local space
# is mapped by its draw transform, the same way effect passes map content
# into RT pixels. Covers both draw paths: the offscreen target pass and the
# surface's shared command item, where the transform must also reset so
# following identity batches are not displaced.

func _ready() -> void:
	var surface = ClassDB.instantiate("JavaFXRenderSurface")
	add_child(surface)
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(64, 64)):
		push_error("target allocation failed")
		get_tree().quit(1)
		return
	var code := "shader_type canvas_item; render_mode unshaded, blend_premul_alpha; void fragment() { COLOR = vec4(1.0,0.0,0.0,1.0); }"
	var code_blue := "shader_type canvas_item; render_mode unshaded, blend_premul_alpha; void fragment() { COLOR = vec4(0.0,0.0,1.0,1.0); }"
	var white := PackedByteArray([255,255,255,255, 255,255,255,255, 255,255,255,255, 255,255,255,255])
	var control := PackedFloat32Array([0,0,0,0,0,0,0, 0,64,0,0,1,0,0, 20,0,0,1,0,0,0, 20,64,0,1,1,0,0])
	var local := PackedFloat32Array([20,190,0,0,0,0,0, 20,210,0,0,1,0,0, 40,190,0,1,0,0,0, 40,210,0,1,1,0,0])
	target.begin_pass(true)
	# Control: identity transform, vertices already in target space.
	target.draw_prism_quads(control, white, code_blue, {}, false, Rect2i(), RID(), Transform2D())
	# Probe: x' = x, y' = y-150 maps local (20,190)-(40,210) to (20,40)-(40,60).
	target.draw_prism_quads(local, white, code, {}, false, Rect2i(), RID(), Transform2D(Vector2(1,0), Vector2(0,1), Vector2(0,-150)))
	if OS.get_environment("GODOT_JFX_MESH_CACHE_PRESSURE") == "1":
		for entry in range(4097):
			var displaced := control.duplicate()
			for vertex in range(4):
				displaced[vertex * 7] += 1000.0 + entry * 50.0
			target.draw_prism_quads(displaced, white, code_blue, {}, false, Rect2i(), RID(), Transform2D())
		if target.get_cached_mesh_count() != 4096:
			push_error("Target mesh cache entry budget not enforced"); get_tree().quit(1); return
	if OS.get_environment("GODOT_JFX_MESH_CACHE_PRESSURE") == "1":
		# A second target shares the global budget; destroying it must not clear
		# geometry still cached/queued by the first target.
		var peer = ClassDB.instantiate("JavaFXRenderTarget")
		if not peer.initialize(Vector2i(64,64)):
			push_error("Peer target allocation failed"); get_tree().quit(1); return
		peer.begin_pass(true)
		peer.draw_prism_quads(control, white, code_blue, {}, false, Rect2i(), RID(), Transform2D())
		peer.end_pass()
		if peer.get_cached_mesh_count() != 4096 or target.get_cached_mesh_count() != 4096:
			push_error("Targets do not share the bounded mesh budget"); get_tree().quit(1); return
		peer = null
		if target.get_cached_mesh_count() != 4096:
			push_error("Peer destruction cleared another target's cache"); get_tree().quit(1); return
		print("SHARED_TARGET_MESH_CACHE_PASS")
	target.end_pass()
	surface.add_render_target(target, Rect2(0,0,64,64))
	# Surface path on a second, non-overlapping surface. The translated batch's
	# untransformed rect lies outside the viewport: with a mesh-command transform
	# the cull rect ignores the transform and the batch never reaches the screen.
	var green_surface = ClassDB.instantiate("JavaFXRenderSurface")
	green_surface.position = Vector2(100, 0)
	add_child(green_surface)
	green_surface.set_draw_shader_code("shader_type canvas_item; render_mode unshaded; void fragment() { COLOR = vec4(0.0,1.0,0.0,1.0); }")
	var deep := PackedFloat32Array([20,540,0,0,0,0,0, 20,560,0,0,1,0,0, 40,540,0,1,0,0,0, 40,560,0,1,1,0,0])
	green_surface.add_prism_quads(deep, white, Transform2D(Vector2(1,0), Vector2(0,1), Vector2(0,-500)))
	# Identity batch after a translated one: without a transform reset it would
	# inherit the -500 shift and vanish instead of filling (0,0)-(20,64).
	green_surface.add_prism_quads(control, white, Transform2D())
	if OS.get_environment("GODOT_JFX_MESH_CACHE_PRESSURE") == "1":
		# Evict the first visible meshes before the command list is rendered.
		# New geometry is off-screen; original green pixels must survive.
		for entry in range(4097):
			var displaced := control.duplicate()
			for vertex in range(4):
				displaced[vertex * 7] += 1000.0 + entry * 50.0
			green_surface.add_prism_quads(displaced, white, Transform2D())
		if green_surface.get_cached_mesh_count() != 4096:
			push_error("Mesh cache entry budget not enforced"); get_tree().quit(1); return
	for frame in range(6):
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var red_min := Vector2i(9999, 9999)
	var red_max := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y)
			if c.r > 0.9 and c.g < 0.1 and c.b < 0.1:
				red_min.x = mini(red_min.x, x); red_min.y = mini(red_min.y, y)
				red_max.x = maxi(red_max.x, x); red_max.y = maxi(red_max.y, y)
	print("MESH_TRANSFORM_PROBE red_bounds=", red_min, "..", red_max, " (want 20,40..40,60)")
	var translated := image.get_pixel(130, 50)
	var identity := image.get_pixel(110, 32)
	# A second pass keeps the first draw and drops the translated red draw.
	# An empty clearing pass must then retire the remaining blue draw.
	for keep_blue in [true, false]:
		target.finish_pass()
		target.begin_pass(true)
		if keep_blue:
			target.draw_prism_quads(control, white, code_blue, {}, false, Rect2i())
		target.end_pass()
		for frame in range(3):
			await RenderingServer.frame_pre_draw
			await RenderingServer.frame_post_draw
		var updated := get_viewport().get_texture().get_image()
		var background := updated.get_pixel(55, 50)
		if not updated.get_pixel(30, 50).is_equal_approx(background):
			push_error("A removed translated draw reappeared"); get_tree().quit(1); return
		var blue := updated.get_pixel(8, 32)
		if (keep_blue and (blue.b < 0.98 or blue.r > 0.02)) or (not keep_blue and not blue.is_equal_approx(background)):
			push_error("Retained or retired blue draw differs: " + str(blue)); get_tree().quit(1); return
	remove_child(surface)
	surface.free()
	remove_child(green_surface)
	green_surface.free()
	if OS.get_environment("GODOT_JFX_MESH_CACHE_PRESSURE") == "1":
		target = null
		var fresh = ClassDB.instantiate("JavaFXRenderTarget")
		if not fresh.initialize(Vector2i(64,64)):
			push_error("Fresh target allocation failed"); get_tree().quit(1); return
		fresh.begin_pass(true)
		fresh.draw_prism_quads(control, white, code_blue, {}, false, Rect2i(), RID(), Transform2D())
		fresh.end_pass()
		if fresh.get_cached_mesh_count() != 1:
			push_error("Final target release retained shared cache"); get_tree().quit(1); return
		fresh = null
		print("SHARED_TARGET_MESH_RELEASE_PASS")
	if red_min != Vector2i(20, 40) or red_max != Vector2i(39, 59):
		push_error("Target-pass draw transform misplaced: %s..%s" % [red_min, red_max])
		get_tree().quit(1)
		return
	if translated.g < 0.9 or translated.r > 0.1:
		push_error("Surface-pass draw transform culled/misplaced: " + str(translated))
		get_tree().quit(1)
		return
	if identity.g < 0.9 or identity.r > 0.1:
		push_error("Surface-pass transform reset missing: " + str(identity))
		get_tree().quit(1)
		return
	print("MESH_TRANSFORM_PROBE_PASS")
	get_tree().quit(0)
