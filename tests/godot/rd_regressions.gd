extends Node

func check_pixels(image: Image, label: String) -> bool:
	if image == null or image.get_size() != Vector2i(192, 16):
		push_error(label + ": missing image"); return false
	for tile in range(48):
		var expected := Color(0.4, 0.2, 0.1, 0.5) if tile % 2 == 0 else Color(0.1, 0.6, 0.9, 1.0)
		for y in range(16):
			for x in range(tile * 4, tile * 4 + 4):
				var actual := image.get_pixel(x, y)
				for channel in range(4):
					if abs(actual[channel] - expected[channel]) > 2.0 / 255.0:
						push_error(label + ": tile " + str(tile) + " pixel differs: " + str(actual))
						return false
	return true

func _ready() -> void:
	if not check_readback_ownership() or not check_vertex_input_ownership():
		get_tree().quit(1); return
	var source = ClassDB.instantiate("JavaFXRenderTarget")
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	# Exercise both the restored one-argument binding and explicit backend choice.
	if not source.initialize(Vector2i(192, 16)) or not target.initialize(Vector2i(192, 16), false):
		push_error("Cannot initialize targets"); get_tree().quit(1); return
	if not source.is_rd_direct() or not target.is_rd_direct():
		push_error("RD regression requires RD-direct; viewport fallback is not acceptance")
		get_tree().quit(1); return
	# 48 distinct batches in one open pass exhaust the 16 mutable slots twice.
	# Repeating also covers slot reuse and preservation across completed passes.
	for cycle in range(4):
		source.begin_pass(cycle == 0)
		if cycle > 0:
			# Keep the clear path explicit: alpha must not accumulate between cycles.
			source.end_pass()
			source.draw_offscreen_pass()
			source.finish_pass()
			if not check_pixels(source.rd_readback(), "preserve"):
				get_tree().quit(1); return
			source.begin_pass(true)
		for tile in range(48):
			var color := Color(0.8, 0.4, 0.2, 0.5) if tile % 2 == 0 else Color(0.1, 0.6, 0.9, 1.0)
			source.add_rectangle(Rect2(tile * 4, 0, 4, 16), color)
		source.end_pass()
		source.draw_offscreen_pass()
		source.finish_pass()
		# Copy while the source pass is still pending in the batched RD queue.
		target.begin_pass(true)
		target.copy_target(source, Rect2(0, 0, 192, 16))
		target.end_pass()
		target.draw_offscreen_pass()
		target.finish_pass()
		if not check_pixels(target.rd_readback(), "copy cycle " + str(cycle)):
			get_tree().quit(1); return
		if not check_pixels(source.rd_readback(), "source cycle " + str(cycle)):
			get_tree().quit(1); return
	if target.get_rd_uniform_set_creation_count() != 1:
		push_error("Live source texture unnecessarily rebuilt its sampler binding"); get_tree().quit(1); return
	var ephemeral = ClassDB.instantiate("JavaFXRenderTarget")
	ephemeral.initialize(Vector2i(192, 16))
	ephemeral.begin_pass(true)
	ephemeral.add_rectangle(Rect2(0, 0, 192, 16), Color.BLUE)
	ephemeral.end_pass(); ephemeral.draw_offscreen_pass(); ephemeral.finish_pass()
	var source_id: int = ephemeral.get_instance_id()
	target.begin_pass(true)
	target.copy_target(ephemeral, Rect2(0, 0, 192, 16))
	target.end_pass(); target.draw_offscreen_pass()
	ephemeral = null
	if not is_instance_id_valid(source_id):
		push_error("Copy source retired before pass completion"); get_tree().quit(1); return
	target.finish_pass()
	if is_instance_id_valid(source_id):
		push_error("Copy source retained after pass completion"); get_tree().quit(1); return
	# Equal-length, equal-hash sources must still compile distinct pipelines.
	var collision_a := "void fragment() { COLOR = vec4(1.0, 0.0, 0.0, 1.0); } //TUzFHFEWriax"
	var collision_b := "void fragment() { COLOR = vec4(0.0, 1.0, 0.0, 1.0); } //GNnTqMfOaJzX"
	if collision_a.length() != collision_b.length() or collision_a.hash() != collision_b.hash():
		push_error("Invalid shader collision fixture"); get_tree().quit(1); return
	for repeat in range(3):
		if not check_uniforms(source, collision_a, {}, Color.RED) or not check_uniforms(source, collision_b, {}, Color.GREEN):
			get_tree().quit(1); return
	# Helper names and comments cannot override the explicit render_mode.
	for helper in ["blend_add", "blend_mul", "blend_disabled"]:
		var body: String = "vec4 " + helper + "() { return vec4(0.4,0.2,0.1,0.5); }\nvoid fragment() { COLOR = " + helper + "(); }"
		if not check_uniforms(source, body, {}, Color(0.4,0.2,0.1,0.5)):
			get_tree().quit(1); return
	if not check_parameter_collisions(source):
		get_tree().quit(1); return
	var defaults := "uniform vec3 tint = vec3(0.8, 0.4, 0.2);\nuniform float amount = 0.25;\nvoid fragment() { COLOR = vec4(tint * amount, 1.0); }"
	if not check_uniforms(source, defaults, {}, Color(0.2, 0.1, 0.05, 1)) \
			or not check_uniforms(source, defaults, {"amount": 0.5}, Color(0.4, 0.2, 0.1, 1)) \
			or not check_uniforms(source, "uniform float weights[1];\nvoid fragment() { COLOR = vec4(weights[0], 0.0, 0.0, 1.0); }", {"weights": PackedFloat32Array([0.75])}, Color(0.75, 0, 0, 1)) \
			or not check_uniforms(source, "uniform ivec3 tint;\nvoid fragment() { COLOR = vec4(vec3(tint) / 4.0, 1.0); }", {"tint": Vector3i(1, 2, 3)}, Color(0.25, 0.5, 0.75, 1)):
		get_tree().quit(1); return
	if not check_mesh_lifetimes(source):
		get_tree().quit(1); return
	target = null
	source = null
	if not check_uniform_retirement():
		get_tree().quit(1); return
	if not check_pixel_coordinates():
		get_tree().quit(1); return
	if not check_screen_snapshot():
		get_tree().quit(1); return
	if not check_pipeline_eviction():
		get_tree().quit(1); return
	print("RD_REGRESSIONS_PASS: 48 draws/pass, preserve, clear, premultiplied rectangles, pending-source copy, uniform defaults/overrides/array[1]/ivec3, colliding shader hashes")
	get_tree().quit(0)

func check_readback_ownership() -> bool:
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(17,9)) or not target.is_rd_direct(): return false
	target.begin_pass(true)
	target.add_rectangle(Rect2(0,0,17,9), Color.RED)
	target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
	var first: Image = target.rd_readback()
	if first == null: return false
	first.set_pixel(0,0,Color.BLUE)
	var second: Image = target.rd_readback()
	target.begin_pass(true)
	target.add_rectangle(Rect2(0,0,17,9), Color.GREEN)
	target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
	var third: Image = target.rd_readback()
	target = null
	if second == null or third == null: return false
	for y in range(9):
		for x in range(17):
			if first.get_pixel(x,y) != (Color.BLUE if x == 0 and y == 0 else Color.RED) or second.get_pixel(x,y) != Color.RED or third.get_pixel(x,y) != Color.GREEN:
				push_error("Readback image ownership changed across mutation/readback/target destruction"); return false
	print("RD_READBACK_OWNERSHIP_PASS")
	return true

func check_uniforms(target, body: String, parameters: Dictionary, expected: Color) -> bool:
	var vertices := PackedFloat32Array([0,0,0,0,0,0,0, 0,16,0,0,1,0,1, 192,0,0,1,0,1,0, 192,16,0,1,1,1,1])
	var colors := PackedByteArray()
	colors.resize(16); colors.fill(255)
	target.begin_pass(true)
	target.draw_prism_quads(vertices, colors, "shader_type canvas_item;\nrender_mode unshaded, blend_premul_alpha;\n" + body, parameters, false, Rect2i())
	target.end_pass()
	target.draw_offscreen_pass()
	target.finish_pass()
	var image: Image = target.rd_readback()
	for y in range(16):
		for x in range(192):
			var actual := image.get_pixel(x, y)
			for channel in range(4):
				if abs(actual[channel] - expected[channel]) > 2.0 / 255.0:
					push_error("Uniform pixels differ: " + str(actual) + " expected " + str(expected))
					return false
	return true

func check_parameter_collisions(target) -> bool:
	# Both names are legal uniforms and have the same djb2 hash. Dictionaries
	# with the same value therefore select the same old cache slot.
	var red := {"Ab": 0.5}
	var green := {"BA": 0.5}
	if red.hash() != green.hash() or red == green:
		push_error("Invalid parameter collision fixture"); return false
	var shader := "shader_type canvas_item;\nrender_mode unshaded, blend_premul_alpha;\nuniform float Ab = 0.0;\nuniform float BA = 0.0;\nvoid fragment() { COLOR = vec4(Ab, BA, 0.0, 1.0); }"
	var colors := PackedByteArray()
	colors.resize(16); colors.fill(255)
	for cycle in range(8):
		target.begin_pass(true)
		for tile in range(48):
			var x := tile * 4.0
			var vertices := PackedFloat32Array([x,0,0,0,0,0,0, x,16,0,0,1,0,1, x+4,0,0,1,0,1,0, x+4,16,0,1,1,1,1])
			var amount := float(cycle * 24 + tile / 2 + 1) / 256.0
			var parameters := {"Ab": amount} if tile % 2 == 0 else {"BA": amount}
			target.draw_prism_quads(vertices, colors, shader, parameters, false, Rect2i())
		target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
		var image: Image = target.rd_readback()
		if image == null:
			push_error("Parameter collision readback missing"); return false
		for y in range(16):
			for x in range(192):
				var amount := float(cycle * 24 + x / 8 + 1) / 256.0
				var expected := Color(amount, 0, 0, 1) if (x / 4) % 2 == 0 else Color(0, amount, 0, 1)
				var actual := image.get_pixel(x, y)
				for channel in range(4):
					if abs(actual[channel] - expected[channel]) > 2.0 / 255.0:
						push_error("Parameter collision draw changed before completion"); return false
	return true

func check_mesh_lifetimes(target) -> bool:
	var shader := "shader_type canvas_item;\nrender_mode unshaded, blend_premul_alpha;\nvarying vec4 godot_vertex_color;\nvoid vertex() {\ngodot_vertex_color = COLOR;\n}\nvoid fragment() {\nCOLOR = godot_vertex_color;\n}"
	# More instances than the 64-entry decode memo. The allocator may recycle
	# addresses; correctness and source destruction must not depend on that.
	for generation in range(96):
		var expected := Color.RED if generation % 2 == 0 else Color.GREEN
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0,0), Vector2(0,16), Vector2(192,0), Vector2(192,16)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0), Vector2(0,1), Vector2(1,0), Vector2(1,1)])
		var custom := PackedFloat32Array()
		custom.resize(16)
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([expected, expected, expected, expected])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,2,1,3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM_BASE)
		var instance := mesh.get_instance_id()
		# Both initial decode and repeat-hit paths must remain correct.
		for repeat in range(2):
			target.begin_pass(true)
			target.draw_prism_mesh(mesh, shader, {}, false, Rect2i())
			target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
		mesh = null
		if is_instance_id_valid(instance):
			push_error("Mesh decode memo retained a source GPU mesh"); return false
		var image: Image = target.rd_readback()
		if image == null:
			push_error("Mesh lifecycle readback missing"); return false
		for y in range(16):
			for x in range(192):
				if image.get_pixel(x,y) != expected:
					push_error("Mesh instance reused stale decoded geometry"); return false
	return true

func check_uniform_retirement() -> bool:
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(16,16)) or not target.is_rd_direct(): return false
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0,0),Vector2(0,16),Vector2(16,0),Vector2(16,16)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1)])
	var custom := PackedFloat32Array(); custom.resize(16)
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,2,1,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM_BASE)
	var shader := "shader_type canvas_item;\nrender_mode unshaded, blend_premul_alpha;\nuniform float amount;\nvoid fragment() { COLOR = vec4(amount,0.0,0.0,1.0); }"
	target.begin_pass(true)
	# Immutable mesh bypasses the mutable vertex ring. 129 distinct value
	# buffers evict the first 128 without forcing their pending batch to commit.
	for i in range(129):
		target.draw_prism_mesh(mesh, shader, {"amount": float(i + 1) / 256.0}, false, Rect2i())
	var colors := PackedByteArray(); colors.resize(16); colors.fill(255)
	# Reacquire the first value, then exhaust all 16 mutable slots. The 17th
	# draw obtains its binding before vertex allocation forces a batch commit.
	for i in range(17):
		var uv := float(i) / 32.0
		var x := -100.0 if i < 16 else 0.0
		var vertices := PackedFloat32Array([x,0,0,uv,0,0,0, x,16,0,uv,1,0,1, x+16,0,0,1,0,1,0, x+16,16,0,1,1,1,1])
		target.draw_prism_quads(vertices, colors, shader, {"amount": 1.0 / 256.0}, false, Rect2i())
	target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
	var image: Image = target.rd_readback()
	if image == null: return false
	for y in range(16):
		for x in range(16):
			var pixel := image.get_pixel(x,y)
			if abs(pixel.r - 1.0 / 256.0) > 2.0 / 255.0 or pixel.g != 0 or pixel.b != 0 or pixel.a != 1:
				push_error("Retired uniform buffer corrupted queued draw"); return false
	print("RD_UNIFORM_RETIREMENT_PASS")
	return true

func check_pipeline_eviction() -> bool:
	var held = ClassDB.instantiate("JavaFXRenderTarget")
	var churn = ClassDB.instantiate("JavaFXRenderTarget")
	if not held.initialize(Vector2i(192,16)) or not churn.initialize(Vector2i(192,16)): return false
	var vertices := PackedFloat32Array([0,0,0,0,0,0,0, 0,16,0,0,1,0,1, 192,0,0,1,0,1,0, 192,16,0,1,1,1,1])
	var colors := PackedByteArray(); colors.resize(16); colors.fill(255)
	var body := "uniform vec4 tint;\nvoid fragment() { COLOR = tint; }"
	var shader := "shader_type canvas_item;\nrender_mode unshaded, blend_premul_alpha;\n" + body
	# Keep an open pass referencing the oldest pipeline and its uniform set.
	# Other targets can evict its cache entry, but cannot destroy this draw.
	held.begin_pass(true)
	held.draw_prism_quads(vertices, colors, shader, {"tint": Vector4(1,0,0,1)}, false, Rect2i())
	for i in range(260):
		if not check_uniforms(churn, body + " // unique source " + str(i), {"tint": Vector4(0,0,1,1)}, Color.BLUE): return false
		if churn.get_rd_pipeline_cache_size() > 256:
			push_error("Shared pipeline cache exceeded entry budget"); return false
	if churn.get_rd_pipeline_cache_size() != 256:
		push_error("Pipeline churn did not fill cache"); return false
	held.end_pass(); held.draw_offscreen_pass(); held.finish_pass()
	var image: Image = held.rd_readback()
	if image == null: return false
	for y in range(16):
		for x in range(192):
			if image.get_pixel(x,y) != Color.RED:
				push_error("Pipeline eviction corrupted an open pass"); return false
	# Recompile the evicted source; its old uniform-cache entry must not bind.
	if not check_uniforms(held, body, {"tint": Vector4(0,1,0,1)}, Color.GREEN): return false
	print("RD_PIPELINE_EVICTION_PASS")
	return true

func check_screen_snapshot() -> bool:
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(192,16)): return false
	var vertices := PackedFloat32Array([0,0,0,0,0,0,0, 0,16,0,0,1,0,1, 192,0,0,1,0,1,0, 192,16,0,1,1,1,1])
	var colors := PackedByteArray(); colors.resize(16); colors.fill(255)
	var shader := "shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nuniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;\nvec4 paint(vec2 uv) { return texture(SCREEN_TEXTURE, uv).bgra; }\nvoid fragment() { COLOR = paint(SCREEN_UV); }"
	var direct := shader.replace("COLOR = paint(SCREEN_UV)", "COLOR = texture(SCREEN_TEXTURE, SCREEN_UV).bgra")
	# Swap blue/red so a dropped sampling draw cannot pass by leaving the
	# original background untouched. Exercise helper and direct references.
	for variant in [shader, direct, direct.replace("SCREEN_TEXTURE", "scene_snapshot")]:
		for background in [true, false]:
			# Magenta belongs to an earlier pass and must not enter this snapshot.
			target.begin_pass(true)
			target.add_rectangle(Rect2(0,0,192,16), Color.MAGENTA)
			target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
			target.begin_pass(true)
			if background:
				target.add_rectangle(Rect2(0,0,192,8), Color.BLUE)
				target.add_rectangle(Rect2(0,8,192,8), Color.GREEN)
			target.draw_prism_quads(vertices, colors, variant, {}, false, Rect2i())
			target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
			var image: Image = target.rd_readback()
			if image == null: return false
			for y in range(16):
				var expected := (Color.RED if y < 8 else Color.GREEN) if background else Color(0,0,0,0)
				for x in range(192):
					if image.get_pixel(x,y) != expected:
						push_error("Screen snapshot missed current clear/background: " + str(image.get_pixel(x,y))); return false
	print("RD_SCREEN_SNAPSHOT_PASS")
	return true

func check_pixel_coordinates() -> bool:
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(192,16)): return false
	var vertices := PackedFloat32Array([0,0,0,0,0,0,0, 0,16,0,0,1,0,1, 192,0,0,1,0,1,0, 192,16,0,1,1,1,1])
	var colors := PackedByteArray(); colors.resize(16); colors.fill(255)
	var shader := "shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nvoid fragment() { vec2 pixcoord = SCREEN_UV / SCREEN_PIXEL_SIZE; COLOR = vec4(pixcoord.x / 192.0, pixcoord.y / 16.0, 0.0, 1.0); }"
	target.begin_pass(true); target.draw_prism_quads(vertices,colors,shader,{},false,Rect2i())
	target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
	var image: Image = target.rd_readback()
	if image == null: return false
	for y in range(16):
		for x in range(192):
			var pixel := image.get_pixel(x,y)
			if abs(pixel.r-(x+0.5)/192.0)>2.0/255.0 or abs(pixel.g-(y+0.5)/16.0)>2.0/255.0 or pixel.b != 0 or pixel.a != 1:
				push_error("RD pixel coordinate differs at " + str(Vector2i(x,y)) + ": " + str(pixel)); return false
	print("RD_PIXEL_COORDINATES_PASS")
	return true

# The public packed-array entry must consume/copy input before returning;
# later mutation must not change a recorded but not yet submitted draw.
func check_vertex_input_ownership() -> bool:
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(192,16)) or not target.is_rd_direct():
		push_error("Vertex ownership requires RD target"); return false
	var vertices:=PackedFloat32Array()
	var colors:=PackedByteArray()
	for point in [Vector2(0,0),Vector2(0,16),Vector2(192,0),Vector2(192,16)]:
		vertices.append_array(PackedFloat32Array([point.x,point.y,0,0.25,0.5,0.6,0.75]))
		colors.append_array(PackedByteArray([0,0,128,255]))
	var shader:="shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nvarying vec2 godot_uv1;\nvoid vertex() { godot_uv1 = CUSTOM0.xy; }\nvoid fragment() { COLOR = vec4(UV.x, godot_uv1.y, COLOR.b, 1.0); }"
	target.begin_pass(true)
	target.draw_prism_quads(vertices,colors,shader,{},false,Rect2i())
	vertices.fill(-1000.0)
	colors.fill(0)
	target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
	var image:Image=target.rd_readback()
	if image==null or image.get_size()!=Vector2i(192,16):
		push_error("Vertex ownership readback missing"); return false
	var expected:=Color(0.25,0.75,128.0/255.0,1)
	for y in range(16):
		for x in range(192):
			var pixel:=image.get_pixel(x,y)
			for channel in range(4):
				if absf(pixel[channel]-expected[channel])>2.0/255.0:
					push_error("Recorded vertex input changed after caller mutation: "+str(pixel)); return false
	target=null
	print("RD_VERTEX_INPUT_OWNERSHIP_PASS")
	return true
