extends Node

# Isolate window lifecycle from JVM, Prism and host command queues.
func _ready() -> void:
	var kind:=OS.get_environment("GODOT_JFX_NATIVE_CHURN_KIND")
	if kind.is_empty(): kind="Window"
	if kind not in ["Idle","SubViewport","Window","JavaFXNativeWindow"]:
		push_error("Unknown churn class");get_tree().quit(1);return
	for cycle in range(181):
		if cycle>0 and kind=="SubViewport":
			var viewport:=SubViewport.new()
			viewport.size=Vector2i(400+(cycle%3)*80,240+(cycle%3)*40)
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			for frame in range(3): await RenderingServer.frame_post_draw
			viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
			RenderingServer.force_sync()
			remove_child(viewport);viewport.free()
		elif cycle>0 and kind!="Idle":
			var window:Window=ClassDB.instantiate(kind)
			window.visible=false;window.force_native=true
			window.size=Vector2i(400+(cycle%3)*80,240+(cycle%3)*40)
			add_child(window);window.show()
			for frame in range(3): await RenderingServer.frame_post_draw
			if window.is_embedded() or DisplayServer.get_window_list().size()!=2:
				push_error("Expected independent native window");get_tree().quit(1);return
			# Match the integration's explicit teardown fence before destroying
			# a window whose swapchain may still have queued rendering work.
			RenderingServer.viewport_set_update_mode(window.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_DISABLED)
			RenderingServer.force_sync()
			remove_child(window);window.free()
		for frame in range(12): await RenderingServer.frame_post_draw
		if DisplayServer.get_window_list().size()!=1:
			push_error("Native window retained");get_tree().quit(1);return
		print("NATIVE_CHURN_SAMPLE ",JSON.stringify({"cycle":cycle,"static_bytes":OS.get_static_memory_usage(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}))
	print("NATIVE_CHURN_PASS class=",kind);get_tree().quit()
