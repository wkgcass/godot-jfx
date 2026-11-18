extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.run_fixture_probe("CompositeProbe"):
		fail("Composite probe rejected")
		return
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("Composite probe failed: " + host.get_runtime_error())
			return
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-composite-observed.png"))
	for row in range(5):
		var a: float = [0.0,0.25,1.0,0.25,0.25][row]
		# Independent premultiplied Porter-Duff equations, in CompositeMode order.
		var expected := [Color(0,0,0,0),Color(a,0,0,a),Color(a,0,.5*(1-a),a+.5*(1-a)),Color(0,0,.5*(1-a),.5*(1-a)),Color(a,0,.5,minf(1,a+.5))]
		for col in range(5):
			for clipped in [false,true]:
				var pre: Color = Color(0,0,.5,.5) if clipped else expected[col]
				var wanted := Vector3(pre.r,pre.g,pre.b) + Vector3(.92,.95,.98)*(1-pre.a)
				var point := Vector2i(10+col*60+(4 if clipped else 25),10+row*50+20)
				var actual := image.get_pixelv(point)
				var delta := (Vector3(actual.r,actual.g,actual.b)-wanted).abs()
				if maxf(delta.x,maxf(delta.y,delta.z)) > .025:
					fail("Composite pixel row="+str(row)+" mode="+str(col)+" clipped="+str(clipped)+": "+str(actual)+" expected "+str(wanted))
					return
	image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-composite.png"))
	host.clear_commands()
	if host.get_owned_resource_count() != 8:
		fail("Composite resources retained after clear: " + str(host.get_owned_resource_count()))
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Composite host resources leaked")
		return
	host.free()
	print("GODOT_COMPOSITE_PASS")
	get_tree().quit()

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
