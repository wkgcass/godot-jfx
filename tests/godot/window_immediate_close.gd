extends Node

func _ready() -> void:
	for cycle in range(32):
		var window := Window.new()
		window.visible = false
		window.force_native = true
		window.size = Vector2i(64, 64)
		window.unfocusable = true
		add_child(window)
		window.show()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, window.get_window_id())
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED, window.get_window_id())
		# No frame or RenderingServer sync between queueing GL work and close.
		window.free()
		if DisplayServer.get_window_list().size() != 1:
			push_error("Immediate close left an OS window"); get_tree().quit(1); return
		print("WINDOW_IMMEDIATE_CLOSE_CYCLE ", cycle)
	await RenderingServer.frame_post_draw
	print("WINDOW_IMMEDIATE_CLOSE_PASS")
	get_tree().quit()
