extends "res://node_shader_test.gd"

func _ready() -> void:
	await get_tree().process_frame
	var host := get_tree().root.get_node("JavaFXHost")
	if await observe(host, true):
		print("LIBRARY_SHADER_PIXELS_PASS")
