extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var compiled: bool = ClassDB.class_call_static("JavaFXHost", "is_rd_direct_compiled")
	var expected := OS.get_environment("GODOT_JFX_EXPECT_RD_COMPILED") == "1"
	if compiled != expected:
		fail("Build capability differs from expected value"); return
	var requested := OS.get_environment("GODOT_JFX_RD_DIRECT") == "1"
	var target = ClassDB.instantiate("JavaFXRenderTarget")
	if requested and not compiled:
		if target.initialize(Vector2i(16,16)):
			fail("Viewport-only build accepted an explicit RD request"); return
		var host = ClassDB.instantiate("JavaFXHost")
		root.add_child(host)
		if host.start_jvm("missing-jdk", "missing-sdk", "", ""):
			fail("JVM startup accepted an unavailable RD request"); return
		if not host.benchmark_rd_cycle(1,1,RID()).has("error"):
			fail("RD cycle probe did not report unsupported build"); return
		if not host.rd_translate_probe("",RID(),RID()).has("error"):
			fail("RD translation probe did not report unsupported build"); return
		if not host.rd_translate_probe_finish().has("error"):
			fail("RD finish probe did not report unsupported build"); return
		host.release_rd_cycle()
		host.free()
	else:
		if not target.initialize(Vector2i(16,16)):
			fail("Cannot initialize target"); return
		var device_available := RenderingServer.get_rendering_device() != null
		if target.is_rd_direct() != (compiled and requested and device_available):
			fail("Selected backend differs from build/runtime/device combination"); return
		# Exercise real device allocation, drawing and readback for either backend.
		target.begin_pass(true)
		target.add_rectangle(Rect2(0,0,16,16), Color.RED)
		target.end_pass()
		target.draw_offscreen_pass()
		await RenderingServer.frame_post_draw
		var image: Image
		if target.is_rd_direct():
			image = target.rd_readback()
		else:
			image = RenderingServer.texture_2d_get(target.get_texture())
		if image == null or image.get_pixel(8,8).r < 0.95 or image.get_pixel(8,8).g > 0.05:
			fail("Render target red pixel differs"); return
		target.finish_pass()
	# Explicit Viewport reference targets must work in every configuration.
	var reference = ClassDB.instantiate("JavaFXRenderTarget")
	if not reference.initialize(Vector2i(8,8), true) or reference.is_rd_direct():
		fail("Forced Viewport target failed"); return
	reference = null
	target = null
	if not (requested and not compiled):
		var host = ClassDB.instantiate("JavaFXHost")
		root.add_child(host)
		if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),
			ProjectSettings.globalize_path("res://../../jfx/build/sdk"),
			ProjectSettings.globalize_path("res://../../artifacts/reference"), "RDBuildProbe"):
			fail("JVM startup rejected the build capability probe"); return
		var deadline := Time.get_ticks_msec() + 30000
		while host.get_runtime_status() != "finished":
			if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
				fail("JNI build probe failed or timed out: " + host.get_runtime_error()); return
			await process_frame
		host.free()
	print("RD_BUILD_PASS compiled=", compiled, " requested=", requested)
	quit(0)

func fail(message: String) -> void:
	push_error(message)
	quit(1)
