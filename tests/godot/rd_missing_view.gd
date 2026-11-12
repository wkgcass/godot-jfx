extends Node

func _ready() -> void:
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(16, 16)) or not target.is_rd_direct():
		push_error("Missing-view fixture requires RD-direct"); get_tree().quit(1); return
	var vertices := PackedFloat32Array([0,0,0,0,0,0,0, 0,16,0,0,1,0,1, 16,0,0,1,0,1,0, 16,16,0,1,1,1,1])
	var colors := PackedByteArray()
	colors.resize(16); colors.fill(255)
	var shader := "shader_type canvas_item;\nrender_mode unshaded, blend_premul_alpha;\nuniform sampler2D source_tex;\nvoid fragment() { COLOR = texture(source_tex, UV); }"
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	var texture := ImageTexture.create_from_image(image)
	# An explicitly empty sampled RID has no device view. Reusing precisely
	# the same parameters must retry rather than hit the white fallback cache.
	for cycle in range(3):
		var sampled := RID() if cycle < 2 else texture.get_rid()
		target.begin_pass(true)
		target.draw_prism_quads(vertices, colors, shader, {"source_tex": sampled}, false, Rect2i())
		target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
		if target.get_rd_uniform_set_creation_count() != cycle + 1:
			push_error("Missing view incorrectly reused provisional binding"); get_tree().quit(1); return
		# Keep the first fallback draw queued while replacing its binding.
		# Readback after the second draw validates delayed retirement as well.
		if cycle == 0:
			continue
		var actual: Image = target.rd_readback()
		var expected := Color.WHITE if cycle < 2 else Color.GREEN
		for y in range(16):
			for x in range(16):
				if not actual.get_pixel(x, y).is_equal_approx(expected):
					push_error("Missing-view fallback/recovery pixel mismatch"); get_tree().quit(1); return
	target = null
	print("RD_MISSING_VIEW_PASS")
	get_tree().quit()
