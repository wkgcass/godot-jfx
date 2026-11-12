extends Node2D

# Every generated Prism/Decora shader must compile and match the Canvas
# reference within 2/255 per channel. The former perspective exception hid
# a Y-coordinate inversion; no edge/deferred exemption remains.
func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	await get_tree().process_frame
	if RenderingServer.get_rendering_device() == null:
		push_error("RD corpus requires a RenderingDevice")
		get_tree().quit(1); return
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			image.set_pixel(x, y, Color(float(x) / 15.0 * 0.8, float(y) / 15.0 * 0.6 + 0.2, 0.4, 0.5 + float(x + y) / 30.0 * 0.5))
	var texture := ImageTexture.create_from_image(image)
	var base := ProjectSettings.globalize_path("res://../../jfx/modules/javafx.graphics/build/gensrc")
	var dirs := ["jsl-prism/com/sun/prism/godot/shaders", "jsl-decora/com/sun/scenario/effect/impl/godot/shaders"]
	var compared := 0
	var failed := 0
	var index := 0
	for dir in dirs:
		var path: String = base + "/" + dir
		var shader_count := 0
		for file in DirAccess.get_files_at(path):
			if file.ends_with(".gdshader"): shader_count += 1
		var expected_count := 212 if dir.begins_with("jsl-prism/") else 50
		if shader_count != expected_count:
			push_error("RD corpus missing or incomplete: " + path + " expected " + str(expected_count) + " got " + str(shader_count))
			get_tree().quit(1); return
		for file in DirAccess.get_files_at(path):
			if not file.ends_with(".gdshader"): continue
			if index % 20 == 0: print("RD_CORPUS_PROGRESS ", index, " ", file)
			index += 1
			var source := FileAccess.get_file_as_string(path + "/" + file)
			var result: Dictionary = host.rd_translate_probe(source, texture.get_rid(), RID())
			if result.get("translate_ok", false):
				# The first frame after phase A misses per-item state; UPDATE_ONCE
				# survives to the second frame, which renders the reference.
				await RenderingServer.frame_pre_draw
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_pre_draw
				await RenderingServer.frame_post_draw
				result = host.rd_translate_probe_finish()
			if result.get("translate_ok", false):
				if int(result.get("max_diff", 99)) <= 2:
					compared += 1
				else:
					failed += 1
					print("RD_CORPUS_DIFF ", file, " ", JSON.stringify(result))
			else:
				failed += 1
				print("RD_CORPUS_FAIL ", file, " ", result.get("error", ""))
			host.release_rd_cycle()
	# Keep legacy summary fields for log readers, always zero now.
	print("RD_CORPUS_SUMMARY exact=", compared, " edge=0 deferred=0 failed=", failed)
	if failed > 0 or compared != 262:
		push_error("RD corpus spike failed"); get_tree().quit(1); return
	print("RD_CORPUS_SPIKE_PASS")
	get_tree().quit()
