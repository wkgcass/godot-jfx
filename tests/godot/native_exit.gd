extends Node

func _ready() -> void:
	for cycle in range(12):
		var group:=Node.new(); add_child(group)
		var windows:=[]
		for index in range(3):
			var window=ClassDB.instantiate("JavaFXNativeWindow")
			window.size=Vector2i(480,320); group.add_child(window); window.show()
			windows.append(window)
			var target=ClassDB.instantiate("JavaFXRenderTarget")
			if not target.initialize(Vector2i(480,320)): get_tree().quit(1); return
			target.begin_pass(true)
			for n in range(300): target.add_rectangle(Rect2(n%30*16,n/30*32,16,32),Color(.2,.4,.8))
			target.end_pass()
			window.present_content(target)
		await RenderingServer.frame_post_draw
		# Queue rendering, then remove the parent rather than invoking the host's
		# explicit destroy_native_window path. Child EXIT_TREE runs first.
		RenderingServer.force_draw(false)
		remove_child(group)
		for window in windows:
			if window.get_owned_resource_count()!=0:
				push_error("Native exit retained surface resources"); get_tree().quit(1); return
		group.free()
		if DisplayServer.get_window_list().size()!=1:
			push_error("Native exit retained OS windows"); get_tree().quit(1); return
		print("NATIVE_EXIT_CYCLE ",cycle)
	print("NATIVE_EXIT_PASS")
	get_tree().quit()
