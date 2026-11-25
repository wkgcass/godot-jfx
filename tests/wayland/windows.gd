extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func make_window(parent: Window, title: String, color: Color, owned: bool) -> Window:
	var window := Window.new()
	window.title = title
	window.size = Vector2i(160, 100)
	window.visible = false
	window.force_native = true
	window.transient = owned
	parent.add_child(window)
	var marker := ColorRect.new()
	marker.size = Vector2(80, 80)
	marker.color = color
	window.add_child(marker)
	window.show()
	return window


func matches_pixel(window: Window, color: Color) -> bool:
	var img := window.get_texture().get_image()
	if img == null or img.is_empty():
		return false
	var actual := img.get_pixel(32, 32)
	return actual.is_equal_approx(color)


func surface(window: Window) -> int:
	return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())


func wait_frames() -> void:
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw


func run() -> void:
	var driver := RenderingServer.get_current_rendering_driver_name()
	var method := RenderingServer.get_current_rendering_method()
	var adapter := RenderingServer.get_video_adapter_name()
	print("WAYLAND_WINDOWS server=", DisplayServer.get_name(), " driver=", driver, " method=", method, " gpu=", adapter)
	if DisplayServer.get_name() != "Wayland" or driver != OS.get_environment("EXPECTED_DRIVER") or method != OS.get_environment("EXPECTED_METHOD"):
		quit(1)
		return
	var owner := make_window(root, "Wayland owner", Color.RED, false)
	var child := make_window(owner, "Wayland owned child", Color.GREEN, true)
	var peer := make_window(root, "Wayland independent peer", Color.BLUE, false)
	await wait_frames()
	var handles := [surface(root), surface(owner), surface(child), surface(peer)]
	print("WAYLAND_WINDOW_SURFACES ", handles)
	for handle in handles:
		if handle == 0 or handles.count(handle) != 1:
			quit(1)
			return
	if not matches_pixel(owner, Color.RED) or not matches_pixel(child, Color.GREEN) or not matches_pixel(peer, Color.BLUE):
		quit(1)
		return
	child.exclusive = true
	await wait_frames()
	child.hide()
	await wait_frames()
	if child.get_window_id() != DisplayServer.INVALID_WINDOW_ID or not matches_pixel(peer, Color.BLUE):
		quit(1)
		return
	child.show()
	await wait_frames()
	if not surface(child) or not matches_pixel(child, Color.GREEN):
		quit(1)
		return
	child.exclusive = false
	var floating_size := child.size
	child.mode = Window.MODE_MAXIMIZED
	await wait_frames()
	if child.mode != Window.MODE_MAXIMIZED or child.size == floating_size:
		push_error("Child did not maximize from %s; actual size %s" % [floating_size, child.size])
		quit(1)
		return
	child.mode = Window.MODE_WINDOWED
	await wait_frames()
	if child.mode != Window.MODE_WINDOWED or child.size != floating_size or not matches_pixel(child, Color.GREEN):
		push_error("Child did not restore its floating geometry: expected %s, got %s" % [floating_size, child.size])
		quit(1)
		return
	print("WAYLAND_WINDOW_RESTORED size=", child.size)
	owner.mode = Window.MODE_MINIMIZED
	await wait_frames()
	if not matches_pixel(peer, Color.BLUE):
		quit(1)
		return
	owner.queue_free()
	await wait_frames()
	if is_instance_valid(child) or not matches_pixel(peer, Color.BLUE):
		quit(1)
		return
	print("WAYLAND_NATIVE_WINDOWS_PASS")
	quit()
