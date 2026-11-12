extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), "BlitProbe"):
		fail("Blit JVM rejected")
		return
	var deadline := Time.get_ticks_msec() + 30000
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("Blit JVM failed: " + host.get_runtime_error())
			return
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var cases := [
		[Vector2i(22,22),Color(0,1,0)],
		[Vector2i(40,40),Color(.96,.475,.49)],
		[Vector2i(74,64),Color(.75,1,0)],
		[Vector2i(110,30),Color(0,0,1)],
		[Vector2i(30,90),Color(.96,.475,.49)],
		[Vector2i(70,90),Color(0,0,1)],
		[Vector2i(51,90),Color(.72,.35625,.6175)],
		[Vector2i(144,30),Color(0,0,1)],
		[Vector2i(168,30),Color(.96,.475,.49)],
		[Vector2i(10,10),Color(.92,.95,.98)]
	]
	for sample in cases:
		var actual := image.get_pixelv(sample[0])
		var expected: Color = sample[1]
		if maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b))) > .035:
			fail("Blit pixel differs at " + str(sample[0]) + ": " + str(actual) + " expected " + str(expected))
			return
	image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/godot-blit.png"))
	host.clear_commands()
	if host.get_owned_resource_count() != 8:
		fail("Blit resources retained after clear: " + str(host.get_owned_resource_count()))
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Blit host resources leaked")
		return
	host.free()
	print("GODOT_BLIT_PASS")
	get_tree().quit()

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
