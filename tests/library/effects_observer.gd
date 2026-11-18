extends "res://effects_test.gd"

func _ready() -> void:
	await get_tree().process_frame
	var host := get_tree().root.get_node("JavaFXHost")
	if await compare_pixels(host):
		print("LIBRARY_EFFECT_PIXELS_PASS")
