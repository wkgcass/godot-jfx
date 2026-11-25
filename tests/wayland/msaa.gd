extends SceneTree

func _initialize() -> void:
	verify.call_deferred()

func capture(scene_3d: bool, mode: Viewport.MSAA) -> Image:
	if scene_3d:
		root.msaa_3d = mode
	else:
		root.msaa_2d = mode
	for frame in range(5):
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func check_edges(scene_3d: bool) -> bool:
	var single := await capture(scene_3d, Viewport.MSAA_DISABLED)
	var multi := await capture(scene_3d, Viewport.MSAA_2X)
	var restored := await capture(scene_3d, Viewport.MSAA_DISABLED)
	if single == null or multi == null or restored == null or single.is_empty() or single.get_size() != multi.get_size() or single.get_size() != restored.get_size():
		push_error("Missing Wayland viewport readback")
		return false
	var size := single.get_size()
	var center := multi.get_pixelv(size / 2)
	var edge_pixels := 0
	for y in range(size.y):
		for x in range(size.x):
			if absf(single.get_pixel(x, y).r - multi.get_pixel(x, y).r) > 0.04:
				edge_pixels += 1
	var same := single.get_data() == restored.get_data()
	print("MSAA_READBACK dimensions=", 3 if scene_3d else 2, " center=", center, " changed=", edge_pixels, " restored=", same)
	if center.r < 0.9 or center.g > 0.1 or center.b > 0.1 or not same:
		return false
	if not scene_3d and RenderingServer.get_current_rendering_method() == "gl_compatibility":
		if multi.get_data() != single.get_data():
			push_error("Compatibility 2D MSAA behavior changed. Check the renderer capability and warning.")
			return false
		print("MSAA_2D_UNSUPPORTED renderer=gl_compatibility pixels_unchanged=true")
		return true
	return edge_pixels >= 16

func verify() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position.z = 3
	camera.current = true
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.rotation.z = 0.37
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.RED
	box.material_override = material
	root.add_child(box)
	if not await check_edges(true):
		quit(1)
		return
	box.free()
	camera.free()

	var size := root.get_visible_rect().size
	var triangle := Polygon2D.new()
	triangle.color = Color.RED
	triangle.polygon = PackedVector2Array([size * Vector2(0.18, 0.23), size * Vector2(0.85, 0.33), size * Vector2(0.46, 0.88)])
	root.add_child(triangle)
	if not await check_edges(false):
		quit(1)
		return
	print("WAYLAND_MSAA_PASS display=", DisplayServer.get_name(), " driver=", RenderingServer.get_current_rendering_driver_name(), " method=", RenderingServer.get_current_rendering_method(), " gpu=", RenderingServer.get_video_adapter_name())
	quit()
