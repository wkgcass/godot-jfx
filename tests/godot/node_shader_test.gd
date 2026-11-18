extends Node2D

func pixel(image:Image, x:int, y:int) -> Color:
	return image.get_pixelv(Vector2i(Vector2(x,y)*DisplayServer.screen_get_scale()))

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("NodeShaderProbe"):
		push_error("Node shader probe failed")
		get_tree().quit(1)
		return
	var observed := await observe(host)
	remove_child(host)
	if not observed or host.get_owned_resource_count() != 0:
		push_error("Node shader interaction or cleanup failed")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_NODE_SHADER_PASS")
	get_tree().quit(0)



# Library fixtures use the same GPU checks and synthetic button input.
func observe(host, library_mode := false) -> bool:
	var deadline := Time.get_ticks_msec()+40000
	var checked := false
	var updated := false
	var peak := 0
	while host.get_runtime_status() != "finished":
		peak = maxi(peak,host.get_owned_resource_count())
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Node shader failed/timed out: "+host.get_runtime_error())
			get_tree().quit(1)
			return false
		if not checked and get_window().title == "Shader ready":
			for frame in range(12):
				await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var red := pixel(image,50,50)
			# The title acknowledgement can overtake queued uniform frames.
			# Wait for the final gain=1 publication before judging the scene.
			if red.r<.95 or red.g>.05: continue
			var green := pixel(image,200,40)
			var outside := pixel(image,240,40)
			var blue := pixel(image,320,40)
			var uv := pixel(image,200,150)
			var glyph_pixels := 0
			var scale:=DisplayServer.screen_get_scale()
			for y in range(roundi(145*scale),roundi(166*scale)):
				for x in range(roundi(25*scale),roundi(108*scale)):
					var color := image.get_pixel(x,y)
					if color.r < .25 and color.g < .25 and color.b < .25:
						glyph_pixels += 1
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/node-shader-diagnostic.png"))
			print("NODE_SHADER_PIXELS ",[red,green,outside,blue,uv]," peak=",peak," glyph_pixels=",glyph_pixels)
			if red.r < .95 or red.g > .05 or green.g < .95 or absf(green.r-.5) > .03 or outside.r < .95 or outside.b < .95 or blue.b < .95 or blue.r > .05 or absf(uv.r-.25) > .03 or absf(uv.g-.25) > .03 or glyph_pixels < 15 or peak > 180:
				push_error("Node shader isolation/clip/opacity/UV/resource check failed")
				get_tree().quit(1)
				return false
			image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-node-shaders.png"))
			checked = true
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(60,155)*DisplayServer.screen_get_scale()
			Input.parse_input_event(motion)
			for pressed in [true,false]:
				var click := InputEventMouseButton.new()
				click.position = Vector2(60,155)*DisplayServer.screen_get_scale()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				Input.parse_input_event(click)
		if checked and get_window().title == "Shader action":
			var color := pixel(get_viewport().get_texture().get_image(),50,50)
			if color.b > .95 and color.r < .05:
				updated = true
				if library_mode: return true
		await get_tree().process_frame
	return checked and updated
