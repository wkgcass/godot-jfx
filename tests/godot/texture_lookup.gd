extends Node2D

func _ready() -> void:
	var target=ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(32,32)):
		push_error("Texture lookup allocation failed");get_tree().quit(1);return
	var texture:RID=target.get_texture()
	if not texture.is_valid():
		push_error("Texture lookup returned invalid RID");get_tree().quit(1);return
	var times:=PackedInt64Array()
	var vertices:=PackedFloat32Array([0,0,0,0,0,0,0, 0,32,0,0,1,0,0, 32,0,0,1,0,0,0, 32,32,0,1,1,0,0])
	var colors:=PackedByteArray([255,0,0,255,255,0,0,255,255,0,0,255,255,0,0,255])
	for cycle in range(6):
		target.begin_pass(true)
		target.draw_prism_quads(vertices,colors,"shader_type canvas_item; render_mode unshaded, blend_premul_alpha;",{},false,Rect2i())
		target.end_pass()
		await RenderingServer.frame_post_draw
		target.finish_pass()
		var start:=Time.get_ticks_usec()
		for lookup in range(1000):
			if target.get_texture()!=texture:
				push_error("Render target texture identity changed");get_tree().quit(1);return
		times.append(Time.get_ticks_usec()-start)
		var image:=RenderingServer.texture_2d_get(texture)
		if image.is_empty() or image.get_pixel(16,16).r<0.99:
			push_error("Borrowed texture is not the rendered content");get_tree().quit(1);return
	var id:int=target.get_instance_id();target=null
	if is_instance_id_valid(id):
		push_error("Target survived release");get_tree().quit(1);return
	print("TEXTURE_LOOKUP_PASS batches_us=",times)
	get_tree().quit()
