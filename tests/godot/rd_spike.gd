extends Node2D

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	await get_tree().process_frame
	for items in [0,1,4,16,64]:
		var result:Dictionary=host.benchmark_offscreen_cycle(items,400)
		print("RD_SPIKE ",JSON.stringify(result))
	get_tree().quit()
