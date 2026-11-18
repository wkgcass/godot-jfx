extends Node2D

func differs(a: Color, b: Color) -> bool:
	return absf(a.r-b.r) > .03 or absf(a.g-b.g) > .03 or absf(a.b-b.b) > .03

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("WindowCompositionProbe"):
		push_error("Composition Java probe start failed")
		get_tree().quit(1)
		return
	var seen := {}
	var last_phase := -1
	var deadline := Time.get_ticks_msec()+30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Composition failed/timed out: phases=%s error=%s" % [seen.keys(),host.get_runtime_error()])
			get_tree().quit(1)
			return
		await get_tree().process_frame
		if not get_window().title.begins_with("Composition "): continue
		var index := get_window().title.get_slice(" ",1).to_int()
		if seen.has(index): continue
		var peer=host.get_native_window(90001)
		if last_phase != index:
			print("COMPOSITION_PHASE ",index," windows=",DisplayServer.get_window_list()," surface=",host.get_surface_size()," peers=",host.get_window_count()," visible=",peer!=null and peer.visible)
			last_phase=index
		var image := get_viewport().get_texture().get_image()
		if differs(image.get_pixel(80,30),Color.RED) or differs(image.get_pixel(140,30),Color.RED):
			push_error("Secondary publication overwrote primary");get_tree().quit(1);return
		var scale:=DisplayServer.screen_get_scale(get_window().current_screen)
		if host.get_surface_size()!=Vector2i(Vector2(240,160)*scale) or host.get_window_count()!=1: continue
		if index==5:
			if peer!=null or DisplayServer.get_window_list().size()!=1: continue
		elif index==3:
			if peer==null or peer.visible or DisplayServer.get_window_list().size()!=1: continue
		else:
			if peer==null or not peer.visible or peer.is_embedded() or peer.is_present_pending(): continue
			if peer.position-get_window().position!=Vector2i(120 if index==1 else 60,10): continue
			var above:bool=host.is_window_above(0,90001) if index==2 else host.is_window_above(90001,0)
			if not above: continue
			image=peer.get_texture().get_image()
			if image.get_size()!=Vector2i(80,60): continue
			var pixel:=image.get_pixel(20,20)
			var opacity:=0.5 if index in [0,4] else 1.0
			if differs(pixel,Color(0,0,opacity)) or absf(pixel.a-opacity)>.03:
				push_error("Native composition pixel differs at %d: %s" % [index,pixel]);get_tree().quit(1);return
		image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/window-composition-%d.png" % index))
		seen[index] = true
	if seen.size() != 6 or host.get_window_count() != 0 or DisplayServer.get_window_list().size() != 1:
		push_error("Composition coverage/cleanup differs: phases="+str(seen.keys()))
		get_tree().quit(1)
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		push_error("Composition GPU resources leaked")
		get_tree().quit(1)
		return
	host.free()
	print("GODOT_WINDOW_COMPOSITION_PASS")
	get_tree().quit(0)
