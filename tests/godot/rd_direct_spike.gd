extends Node2D

func close_enough(c: Color, r: int, g: int, b: int) -> bool:
	return abs(c.r8 - r) <= 6 and abs(c.g8 - g) <= 6 and abs(c.b8 - b) <= 6

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	await get_tree().process_frame
	if RenderingServer.get_rendering_device() == null:
		push_error("RD direct spike requires a RenderingDevice; no RD test was executed")
		get_tree().quit(1); return
	var failed := false
	for items in [0, 1, 4, 16, 64]:
		var result: Dictionary = host.benchmark_rd_cycle(items, 400, RID())
		print("RD_DIRECT_CYCLE ", JSON.stringify(result))
		host.release_rd_cycle()
		if result.get("error", "") != "" or not result.get("pixels_ok", false):
			failed = true
	# Canvas bridge: RD-rendered output must stay sampleable by the ordinary
	# canvas pipeline (the hand-off the real integration depends on).
	var bridge: Dictionary = host.benchmark_rd_cycle(4, 100, get_canvas_item())
	print("RD_DIRECT_BRIDGE ", JSON.stringify(bridge))
	# Separate rendering may still deliver an older deferred post-draw notice.
	# Wait for a fresh submission before sampling the newly attached preview.
	await RenderingServer.frame_pre_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var inside := image.get_pixel(128, 64)
	var outside := image.get_pixel(384, 192)
	print("RD_DIRECT_BRIDGE_PIXELS ", inside.to_html(false), " ", outside.to_html(false))
	# The 512x256 preview shows the 2016x928 target: the quad (230,128,77)
	# fills its left half, the clear color (26,51,77) the right half.
	if not bridge.get("bridge_ok", false) or not close_enough(inside, 230, 128, 77) or not close_enough(outside, 26, 51, 77):
		failed = true
	host.release_rd_cycle()
	if failed:
		push_error("RD direct spike failed"); get_tree().quit(1); return
	print("RD_DIRECT_SPIKE_PASS")
	get_tree().quit()
