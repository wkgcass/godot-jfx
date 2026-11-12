extends Node2D

func fail(message:String) -> void:
	push_error(message); get_tree().quit(1)

func _ready() -> void:
	if not check_sampler_collision(): fail("Sampler material hash collision regression"); return
	var surface=ClassDB.instantiate("JavaFXRenderSurface"); add_child(surface)
	var target=ClassDB.instantiate("JavaFXRenderTarget")
	var proxy_count:=int(OS.get_environment("GODOT_JFX_ASYNC_TARGET_TEXTURE")=="1")
	if not target.initialize(Vector2i(32,32), true): fail("Cache target allocation failed"); return
	var vertices:=PackedFloat32Array([0,0,0,0,0,0,0, 0,32,0,0,1,0,0, 32,0,0,1,0,0,0, 32,32,0,1,1,0,0])
	var colors:=PackedByteArray([255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255])
	for cycle in range(305):
		var variant:=maxi(0,cycle-4)
		var code:="shader_type canvas_item; render_mode unshaded, blend_premul_alpha; uniform vec4 tint; void fragment(){ COLOR=tint; } // variant %d"%variant
		if cycle >= 270: code += " " + "x".repeat(32768)
		var tint:=Vector4(1,0,0,1) if cycle%2==0 else Vector4(0,0,1,1)
		target.begin_pass(true)
		target.draw_prism_quads(vertices,colors,code,{"tint":tint},true,Rect2i(0,0,16,32))
		target.draw_prism_quads(vertices,colors,code,{"tint":Vector4(0,1,0,1)},true,Rect2i(16,0,16,32))
		target.end_pass()
		surface.add_render_target(target,Rect2(0,0,32,32))
		# Separate rendering defers post-draw notifications to the main thread.
		# Drain notifications only after a fresh draw starts, so three queued
		# notifications from old frames cannot satisfy this entire wait.
		for frame in range(3):
			await RenderingServer.frame_pre_draw
			await RenderingServer.frame_post_draw
		var pixels:=get_viewport().get_texture().get_image()
		var left:=pixels.get_pixel(8,16)
		var right:=pixels.get_pixel(24,16)
		if absf(left.r-tint.x)>.02 or absf(left.b-tint.z)>.02 or right.g<.98 or right.r>.02 or right.b>.02:
			# Preserve the image that actually failed, without another render or
			# readback that could conceal a transient mismatch.
			var directory := ProjectSettings.globalize_path("res://../../artifacts/reference")
			var capture := directory.path_join("shader-cache-failure-%d-cycle-%d.png"%[OS.get_process_id(),cycle])
			var capture_error := DirAccess.make_dir_recursive_absolute(directory)
			if capture_error == OK: capture_error = pixels.save_png(capture)
			print("SHADER_CACHE_FAILURE_CAPTURE path=%s error=%s"%[capture,error_string(capture_error)])
			fail("Shared shader pixel mismatch at cycle %d: left=%s right=%s expected_left=%s"%[cycle,left,right,tint]); return
		target.finish_pass()
		# Both quad draws share one content key, so the mesh cache holds one
		# entry across passes instead of freeing meshes at each pass end.
		if target.get_cached_shader_count()!=mini(variant+1,64) or target.get_owned_resource_count()!=5+proxy_count+target.get_cached_shader_count()+target.get_draw_slot_count()+target.get_cached_material_count() or target.get_cached_mesh_count()!=1:
			fail("Shader cache/pass resource bound differs at cycle %d"%cycle); return
		if cycle<5 and target.get_shader_creation_count()!=1:
			fail("Repeated shader was re-created across draws/passes"); return
		var memo: Dictionary = target.get_instance_uniform_cache_stats()
		if memo.entries < 1 or memo.entries > 256 or memo.bytes > 4 * 1024 * 1024:
			fail("Instance uniform name memo exceeded its budget: " + str(memo)); return
		if cycle == 269 and memo.entries != 256:
			fail("Name memo entry-pressure fixture did not fill the cache"); return
		if cycle == 304:
			if memo.bytes < 3 * 1024 * 1024 or memo.entries >= 256:
				fail("Name memo byte-pressure fixture did not evict smaller entries"); return
			print("INSTANCE_UNIFORM_MEMO_BOUND " + str(memo))
		if cycle == 274 and OS.get_environment("GODOT_JFX_TEST_QUEUED_NOTICES") == "1":
			# Queue completed old frames while main-thread notification delivery
			# is blocked here. Readback drains their render work, not callbacks.
			for pending in range(8):
				RenderingServer.force_draw(false)
			var drained := get_viewport().get_texture().get_image()
			print("QUEUED_NOTICE_INJECTION cycle=274 previous_pixel=", drained.get_pixel(8,16))
		surface.clear_commands()
	if target.get_shader_creation_count()!=538: fail("Overflow shaders were not pass-owned"); return
	var target_id:int=target.get_instance_id()
	target=null
	if is_instance_id_valid(target_id): fail("Cached target leaked"); return
	remove_child(surface)
	if surface.get_owned_resource_count()!=0: fail("Cache test surface leaked"); return
	surface.free(); print("SHADER_CACHE_PASS: reuse, distinct uniforms, 64-code bound, overflow cleanup, 256-entry/4MiB name memo"); get_tree().quit(0)

func check_sampler_collision() -> bool:
	# Find a real Dictionary hash collision using live sampler RIDs. No hash
	# override is needed in production, and each tuple has a distinct RGB value.
	var sources: Array = []
	for index in range(96):
		var source = ClassDB.instantiate("JavaFXRenderTarget")
		if not source.initialize(Vector2i(1,1), true): return false
		source.begin_pass(true)
		var level := float(index + 1) / 97.0
		source.add_rectangle(Rect2(0,0,1,1), Color(level,level,level,1))
		source.end_pass(); source.draw_offscreen_pass(); source.finish_pass()
		sources.append(source)
	var seen: Dictionary = {}
	var pair: Array = []
	for a in range(96):
		for b in range(96):
			for c in range(96):
				var params := {"tex0":sources[a].get_texture(), "tex1":sources[b].get_texture(), "tex2":sources[c].get_texture()}
				var key := params.hash()
				if seen.has(key):
					var first: Vector3i = seen[key]
					if first.x not in [a,b,c] or first.y not in [a,b,c] or first.z not in [a,b,c]:
						pair = [first, Vector3i(a,b,c)]
						break
				seen[key] = Vector3i(a,b,c)
			if not pair.is_empty(): break
		if not pair.is_empty(): break
	if pair.is_empty():
		push_error("No sampler hash collision found in bounded fixture"); return false
	seen.clear()
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(Vector2i(32,32), true): return false
	var code := "shader_type canvas_item; render_mode unshaded, blend_premul_alpha; uniform sampler2D tex0; uniform sampler2D tex1; uniform sampler2D tex2; void fragment(){ COLOR=vec4(texture(tex0,UV).r,texture(tex1,UV).r,texture(tex2,UV).r,1.0); }"
	var vertices := PackedFloat32Array([0,0,0,0,0,0,0, 0,32,0,0,1,0,0, 32,0,0,1,0,0,0, 32,32,0,1,1,0,0])
	var colors := PackedByteArray([255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255])
	for cycle in range(3):
		target.begin_pass(true)
		for side in range(2):
			var ids: Vector3i = pair[side]
			target.draw_prism_quads(vertices,colors,code,{"tex0":sources[ids.x].get_texture(),"tex1":sources[ids.y].get_texture(),"tex2":sources[ids.z].get_texture()},true,Rect2i(side*16,0,16,32))
		target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
		var pixels := RenderingServer.texture_2d_get(target.get_texture())
		for side in range(2):
			var actual := pixels.get_pixel(side*16+8,16)
			var ids: Vector3i = pair[side]
			for channel in range(3):
				if absf(actual[channel]-float(ids[channel]+1)/97.0)>2.0/255.0:
					push_error("Sampler collision overwrote draw: " + str(pair) + " actual=" + str(actual)); return false
		if target.get_cached_material_count()!=2:
			push_error("Colliding sampler materials were not reused"); return false
	var first: Vector3i = pair[0]
	var remaining: Vector3i = pair[1]
	var retired := -1
	for index in [first.x,first.y,first.z]:
		if index not in [remaining.x,remaining.y,remaining.z]:
			retired = index
			break
	if retired < 0: return false
	var retired_id: int = sources[retired].get_instance_id()
	sources[retired] = null
	if is_instance_id_valid(retired_id):
		push_error("Collision fixture did not retire its sampler"); return false
	# The primary bucket is removed on the first miss. The second lookup
	# must find the surviving collision entry even with that empty bucket.
	for cycle in range(2):
		target.begin_pass(true)
		target.draw_prism_quads(vertices,colors,code,{"tex0":sources[remaining.x].get_texture(),"tex1":sources[remaining.y].get_texture(),"tex2":sources[remaining.z].get_texture()},false,Rect2i())
		target.end_pass(); target.draw_offscreen_pass(); target.finish_pass()
		var pixels := RenderingServer.texture_2d_get(target.get_texture())
		var actual := pixels.get_pixel(16,16)
		for channel in range(3):
			if absf(actual[channel]-float(remaining[channel]+1)/97.0)>2.0/255.0:
				push_error("Surviving collision sampler changed after retirement"); return false
		if target.get_cached_material_count()!=1:
			push_error("Collision deletion hole duplicated or retained a material"); return false
	print("SAMPLER_MATERIAL_COLLISION_PASS pair=" + str(pair) + " retired=" + str(retired))
	return true
