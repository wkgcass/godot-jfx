extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("EffectsProbe"):
		push_error("Effects Java probe startup failed")
		get_tree().quit(1)
		return
	var failed := not await compare_pixels(host)
	# The probe exits normally after its observation ticks. Keep render queues
	# alive until JavaFX has closed its windows and disposed their targets.
	var deadline := Time.get_ticks_msec()+30000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Effect probe did not exit normally: "+host.get_runtime_error()); get_tree().quit(1); return
		await get_tree().process_frame
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending(): failed=true
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		failed = true
	host.free()
	if failed:
		push_error("Effect comparison failed; inspect per-effect metrics and captures")
		get_tree().quit(1)
	else:
		print("GODOT_EFFECTS_PASS")
		get_tree().quit(0)

func compare_pixels(host) -> bool:
	var deadline := Time.get_ticks_msec()+30000
	while get_window().title != "Effects ready" or host.get_applied_sequence() < 1:
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Effects startup timeout/failure: " + host.get_runtime_error())
			get_tree().quit(1)
			return false
		await get_tree().process_frame
	# A larger effect graph can need more than a fixed number of host frames.
	# Wait for its completed window publication, not an intermediate clear.
	while host.get_window_content_size(1)==Vector2i() or host.is_composition_pending():
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Effect window publication did not complete"); get_tree().quit(1); return false
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var actual := get_viewport().get_texture().get_image()
	actual.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-effects.png"))
	var expected := Image.load_from_file(ProjectSettings.globalize_path("res://../../artifacts/reference/d3d-effects.png"))
	if actual.get_size() != expected.get_size():
		push_error("Effect reference dimensions differ")
		get_tree().quit(1)
		return false
	var names := ["None","GaussianBlur","BoxBlur","DropShadow","InnerShadow","Glow","Bloom","ColorAdjust","Reflection","MotionBlur","Lighting","Blend","DisplacementMap","DisplacementMapWrap","SepiaTone","Shadow","PerspectiveTransform","ImageInput","ColorInput","ChainedBlurSepiaShadow"]
	var failed := false
	for mode in ["SRC_OVER","SRC_ATOP","ADD","MULTIPLY","SCREEN","OVERLAY","DARKEN","LIGHTEN","COLOR_DODGE","COLOR_BURN","HARD_LIGHT","SOFT_LIGHT","DIFFERENCE","EXCLUSION","RED","GREEN","BLUE"]:
		names.append("Blend_"+mode)
	names.append_array(["LightingPoint","LightingSpot"])
	var scale:=DisplayServer.screen_get_scale()
	for tile in range(names.size()):
		var total := 0.0
		var bad := 0
		var area:=Rect2i(roundi((tile%4)*100*scale),roundi(int(tile/4)*80*scale),roundi(100*scale),roundi(80*scale))
		for y in range(area.position.y,area.end.y):
			for x in range(area.position.x,area.end.x):
				var a := actual.get_pixel(x,y)
				var b := expected.get_pixel(x,y)
				var error := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
				total += error
				if error > 0.08:
					bad += 1
		var count:=area.size.x*area.size.y
		var mean := total/count
		print("EFFECT_COMPARE ",names[tile]," mean=",mean," bad=",bad)
		if mean > 0.01 or float(bad)/count > 0.01:
			failed = true
	return not failed
