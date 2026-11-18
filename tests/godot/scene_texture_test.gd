extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	var missing := OS.get_environment("GODOT_JFX_SCENE_MISSING") == "1"
	var resizing := OS.get_environment("GODOT_JFX_SCENE_RESIZE") == "1"
	var first_id := 0
	var resize_preserved := false
	if not host.run_fixture_probe("SceneTextureProbe"):
		push_error("Scene texture Java probe start failed")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec()+20000
	while host.get_runtime_status() != "finished" and host.get_runtime_status() != "failed":
		if resizing and host.get_child_count() == 2:
			var view = host.get_child(0)
			var root = view.get_child(0)
			if first_id == 0:
				first_id = root.get_instance_id()
				root.color = Color.BLUE
				root.queue_redraw()
			elif view.size == Vector2i(96,64):
				resize_preserved = root.get_instance_id() == first_id and root.color == Color.BLUE and root.ticks > 30
		if Time.get_ticks_msec() > deadline:
			push_error("Scene texture probe timeout")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	if missing:
		if host.get_runtime_status() != "failed" or not "Cannot load embedded Godot scene: res://missing-scene.tscn" in host.get_runtime_error() or host.get_child_count() != 0:
			push_error("Scene load failure was not propagated/cleaned")
			get_tree().quit(1)
			return
	else:
		if host.get_runtime_status() == "failed" or (not resizing and host.get_child_count() != 2) or (resizing and (not resize_preserved or host.get_child_count() != 0)):
			push_error("Scene texture owner lifetime differs: "+host.get_runtime_error())
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var first := image.get_pixel(48,48)
		var second := image.get_pixel(252 if resizing else 232,48)
		var alpha := image.get_pixel(300 if resizing else 292,48)
		var marker := image.get_pixel(366 if resizing else 374,112)
		print("SCENE_TEXTURE_PIXELS ",[first,second,alpha,marker])
		var first_valid := first.b > .95 and first.r < .05 if resizing else first.r > .95 and first.b < .05
		if not first_valid or second.r < .95 or second.b > .05 or absf(alpha.r-.46) > .04 or absf(alpha.g-.975) > .04 or marker.g < .95 or marker.r > .05:
			push_error("Prism scene texture pixels differ")
			get_tree().quit(1)
			return
		for view in host.get_children():
			if view.get_child(0).ticks < 1:
				push_error("Retired scene texture stopped processing")
				get_tree().quit(1)
				return
		image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-scene-textures.png"))
		host.clear_commands()
		if host.get_child_count() != 0:
			push_error("Retired scene nodes were not released after clear")
			get_tree().quit(1)
			return
	host.stop_host()
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Scene texture host resources leaked")
		get_tree().quit(1)
		return
	host.free()
	print("SCENE_TEXTURE_FAILURE_PASS" if missing else "GODOT_SCENE_TEXTURE_PASS")
	get_tree().quit(0)
