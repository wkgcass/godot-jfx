extends SceneTree

var began := 0
var measured := 0
var frames := 0

func _initialize() -> void:
	root.size = Vector2i(640, 360)
	root.title = "Godot host frame diagnostic"
	began = Time.get_ticks_usec()
	print("HOST_FRAME_CONFIG ", JSON.stringify({"max_fps": Engine.max_fps, "low_processor": OS.low_processor_usage_mode, "vsync": DisplayServer.window_get_vsync_mode()}))

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if measured == 0 and now - began >= 2000000:
		measured = now
	if measured > 0:
		frames += 1
		if now - measured >= 10000000:
			print("HOST_FRAME_RESULT ", JSON.stringify({"frames": frames, "seconds": (now-measured)/1000000.0, "fps": frames*1000000.0/(now-measured), "focused": root.has_focus()}))
			quit()
	return false
