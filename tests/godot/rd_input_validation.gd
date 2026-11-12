extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func solid(image: Image, expected: Color) -> bool:
	if image==null or image.get_size()!=Vector2i(16,16): return false
	for y in range(16):
		for x in range(16):
			var actual:=image.get_pixel(x,y)
			for channel in range(4):
				if absf(actual[channel]-expected[channel])>2.0/255.0: return false
	return true

func _run() -> void:
	var valid:=PackedFloat32Array([0,0,0,0,0,0,0, 0,16,0,0,1,0,1, 16,0,0,1,0,1,0, 16,16,0,1,1,1,1])
	var rgba:=PackedByteArray(); rgba.resize(16); rgba.fill(255)
	var shader:="shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nvoid fragment() { COLOR = vec4(1.0,0.0,0.0,1.0); }"
	for kind in ["z","tail","nan","too_many","colors"]:
		var target=ClassDB.instantiate("JavaFXRenderTarget")
		if not target.initialize(Vector2i(16,16)) or not target.is_rd_direct():
			push_error("RD input validation requires RD target"); quit(1); return
		var vertices:=valid.duplicate()
		var colors:=rgba.duplicate()
		match kind:
			"z": vertices[2]=1.0
			"tail": vertices.append(0)
			"nan": vertices[3]=NAN
			"too_many":
				vertices.resize(65540*7); vertices.fill(0)
				colors.resize(65540*4); colors.fill(255)
			"colors": colors.resize(15)
		print("RD_INVALID_CASE ",kind)
		target.begin_pass(true)
		target.draw_prism_quads(vertices,colors,shader,{},false,Rect2i())
		target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
		if not solid(target.rd_readback(),Color(0,0,0,0)):
			push_error("Invalid RD geometry was rendered: "+kind); quit(1); return
		# Rejection must not poison the next valid pass.
		target.begin_pass(true)
		target.draw_prism_quads(valid,rgba,shader,{},false,Rect2i())
		target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
		if not solid(target.rd_readback(),Color.RED):
			push_error("Valid RD draw failed after rejection: "+kind); quit(1); return
		target=null
	print("RD_INPUT_VALIDATION_PASS cases=5")
	quit(0)
