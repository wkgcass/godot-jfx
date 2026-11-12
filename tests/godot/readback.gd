extends Node2D

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost")
	add_child(host)
	var stop_read := OS.get_environment("GODOT_JFX_READBACK_STOP") == "1"
	if stop_read: host.set_process(false)
	var probe := "SnapshotProbe" if OS.get_environment("GODOT_JFX_SNAPSHOT") == "1" else "ReadbackProbe"
	var stress := OS.get_environment("GODOT_JFX_SNAPSHOT_STRESS") == "1"
	var checkpoint := 20
	var baseline_resources := -1
	var baseline_texture_bytes := 0.0
	var baseline_static_bytes := 0
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"), ProjectSettings.globalize_path("res://../../jfx/build/sdk"), ProjectSettings.globalize_path("res://../../artifacts/reference"), probe):
		fail("Readback JVM rejected")
		return
	var deadline := Time.get_ticks_msec() + (180000 if stress else 30000)
	if stop_read:
		while not host.has_pending_readback():
			if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
				fail("Readback request did not become pending")
				return
			await get_tree().process_frame
		host.stop_jvm()
		print("READBACK_STOP_OBSERVED_PENDING_REQUEST")
	while host.get_runtime_status() != "finished":
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			fail("Readback JVM failed: " + host.get_runtime_error())
			return
		await get_tree().process_frame
		if stress and get_window().title == "SnapshotStress "+str(checkpoint):
			# Pause application work at each checkpoint, then sample after the
			# submitted snapshot/presentation disposals have had time to drain.
			for i in range(12): await RenderingServer.frame_post_draw
			if host.has_pending_readback(): fail("Readback still pending at checkpoint"); return
			var resources:int=host.get_owned_resource_count()
			var texture_bytes:float=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
			var static_bytes:int=OS.get_static_memory_usage()
			print("SNAPSHOT_STRESS_RESOURCES count=",checkpoint," owned=",resources," texture_bytes=",texture_bytes," godot_static_bytes=",static_bytes)
			if checkpoint==60:
				baseline_resources=resources; baseline_texture_bytes=texture_bytes; baseline_static_bytes=static_bytes
			elif checkpoint>60:
				# Allow one small target/material set and allocator/cache slack,
				# not linear per-snapshot growth after all size variants are warm.
				if resources>baseline_resources+16 or texture_bytes>baseline_texture_bytes+2097152 or static_bytes>baseline_static_bytes+8388608:
					fail("Snapshot retained resources grew beyond warm-cache allowance"); return
			var motion:=InputEventMouseMotion.new(); motion.window_id=get_window().get_window_id(); motion.position=Vector2(10,10); Input.parse_input_event(motion)
			for pressed in [true,false]:
				var event:=InputEventMouseButton.new(); event.window_id=get_window().get_window_id(); event.position=Vector2(10,10); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; Input.parse_input_event(event)
			checkpoint+=20
	await RenderingServer.frame_post_draw
	if stress and checkpoint!=220: fail("Snapshot stress did not finish 200 reads"); return
	if probe == "SnapshotProbe":
		for i in range(120):
			if host.get_window_count() == 0 and host.get_native_window_count() == 0 and not host.is_composition_pending(): break
			await RenderingServer.frame_post_draw
		if host.get_window_count() != 0 or host.get_native_window_count() != 0 or host.is_composition_pending():
			fail("Snapshot windows did not drain")
			return
	host.clear_commands()
	# The direct fixture disposes every allocated texture. Quantum additionally
	# retains its resource-pool caches until host teardown, checked below.
	if probe == "ReadbackProbe" and host.get_owned_resource_count() != 8:
		fail("Readback resources retained: " + str(host.get_owned_resource_count()))
		return
	remove_child(host)
	if host.get_owned_resource_count() != 0:
		fail("Readback host resources leaked")
		return
	host.free()
	print("GODOT_READBACK_PASS")
	get_tree().quit()

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
