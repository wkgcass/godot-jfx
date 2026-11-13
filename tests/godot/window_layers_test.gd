extends Node2D

func fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false

func compose(surface) -> bool:
	if not surface.compose_windows(): return fail("Window composition rejected")
	var limit := Time.get_ticks_msec()+5000
	while surface.is_composition_pending():
		if Time.get_ticks_msec() > limit: return fail("Window composition timed out")
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return true

func pixel(image: Image, point: Vector2i, expected: Color) -> bool:
	var actual := image.get_pixelv(point)
	if maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b))) > .04:
		return fail("Window layer pixel mismatch at "+str(point)+": "+str(actual)+" expected "+str(expected))
	return true

func _ready() -> void:
	var surface = ClassDB.instantiate("JavaFXWindowSurface")
	surface.set_surface_size(Vector2i(160,120))
	surface.position = Vector2(10,10)
	add_child(surface)
	RenderingServer.set_default_clear_color(Color.WHITE)
	for cycle in range(100):
		var red = ClassDB.instantiate("JavaFXRenderTarget")
		var blue = ClassDB.instantiate("JavaFXRenderTarget")
		for entry in [[red,Color.RED],[blue,Color.BLUE]]:
			if not entry[0].initialize(Vector2i(32,32)): fail("Target allocation failed"); return
			entry[0].begin_pass(true)
			var color: Color=entry[1]
			var colors:=PackedByteArray([int(color.r*255),int(color.g*255),int(color.b*255),255])
			var vertices:=PackedFloat32Array([0,0,0,0,0,0,0, 0,32,0,0,1,0,0, 32,0,0,1,0,0,0, 32,32,0,1,1,0,0])
			entry[0].draw_prism_quads(vertices,PackedByteArray(colors+colors+colors+colors),"shader_type canvas_item; render_mode unshaded, blend_premul_alpha;",{},false,Rect2i())
			entry[0].end_pass()
		for frame in range(3): await RenderingServer.frame_post_draw
		red.finish_pass(); blue.finish_pass()
		var red_id: int = red.get_instance_id()
		var blue_id: int = blue.get_instance_id()
		if not surface.configure_window(1,Rect2(0,0,100,80),0,true,1) or not surface.configure_window(2,Rect2(40,30,90,60),1,true,.5):
			fail("Window configuration failed"); return
		if not surface.set_window_content(1,red) or not surface.set_window_content(2,blue):
			fail("Window publication failed"); return
		red=null; blue=null
		if not await compose(surface): return
		if cycle in [0,99]:
			var image := get_viewport().get_texture().get_image()
			if not pixel(image,Vector2i(30,30),Color.RED) or not pixel(image,Vector2i(70,60),Color(.5,0,.5)) or not pixel(image,Vector2i(125,65),Color(.5,.5,1)): return
			if cycle == 99: image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/window-layers.png"))
		# Hide and reorder without publishing a new texture.
		surface.configure_window(2,Rect2(40,30,90,60),1,false,1)
		if not await compose(surface): return
		if cycle in [0,99]:
			var image := get_viewport().get_texture().get_image()
			if not pixel(image,Vector2i(70,60),Color.RED) or not pixel(image,Vector2i(125,65),Color.WHITE): return
		surface.configure_window(1,Rect2(0,0,100,80),2,true,1)
		surface.configure_window(2,Rect2(40,30,90,60),1,true,1)
		if not await compose(surface): return
		if cycle in [0,99]:
			if not pixel(get_viewport().get_texture().get_image(),Vector2i(70,60),Color.RED): return
		# Move/resize beyond the native host viewport; its boundary clips layers.
		surface.configure_window(2,Rect2(-20,20,50,50),3,true,1)
		if not await compose(surface): return
		if cycle in [0,99]:
			var image := get_viewport().get_texture().get_image()
			if not pixel(image,Vector2i(15,45),Color.BLUE) or not pixel(image,Vector2i(125,65),Color.WHITE): return
		# Removal during an in-flight composition must retain sampled content.
		if not surface.compose_windows(): fail("Final composition rejected"); return
		surface.remove_window(1); surface.remove_window(2)
		if not is_instance_id_valid(red_id) or not is_instance_id_valid(blue_id): fail("In-flight layer was freed"); return
		while surface.is_composition_pending(): await get_tree().process_frame
		if is_instance_id_valid(red_id) or is_instance_id_valid(blue_id): fail("Removed window content leaked"); return
		if surface.get_window_count() != 0: fail("Logical window metadata leaked"); return
		if not await compose(surface): return
	if DisplayServer.get_window_list().size() != 1: fail("Extra native window created"); return
	remove_child(surface)
	if surface.get_owned_resource_count() != 0: fail("Window surface resources leaked"); return
	surface.free()
	print("WINDOW_LAYERS_PASS: 100 cycles, alpha/z/hide/move/clip, retained lifetimes, one native window")
	get_tree().quit()
