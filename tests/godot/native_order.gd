extends Node

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.run_fixture_probe("NativeOrderProbe"):
		push_error("Native order probe failed");get_tree().quit(1);return
	var seen:={}
	var deadline:=Time.get_ticks_msec()+90000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Native order failed: "+host.get_runtime_error());get_tree().quit(1);return
		# frame_post_draw stops when no host window can draw: on macOS closing or
		# hiding the last visible FX Stage orders out the root NSWindow, and Godot
		# then skips RenderingServer.draw entirely (Windows keeps drawing hidden
		# windows). Race the draw signal against a timer so status/deadline
		# polling never deadlocks; ordering assertions below are unchanged.
		var drawn:=[false]
		RenderingServer.frame_post_draw.connect(func() -> void: drawn[0]=true,CONNECT_ONE_SHOT)
		get_tree().create_timer(0.02).timeout.connect(func() -> void: drawn[0]=true,CONNECT_ONE_SHOT)
		while not drawn[0]:
			await get_tree().process_frame
		var title:=get_window().title
		if not title.begins_with("NativeOrder "):continue
		var phase:=title.get_slice(" ",1).to_int()
		var a:=title.get_slice(" ",2).to_int();var b:=title.get_slice(" ",3).to_int()
		if phase>=7:
			var c:=title.get_slice(" ",4).to_int();var d:=title.get_slice(" ",5).to_int()
			if DisplayServer.get_window_list().size()!=5 or not host.is_window_above(d,c) or not host.is_window_above(c,a):
				push_error("Owned HWND order differs at phase "+str(phase));get_tree().quit(1);return
			if not seen.has(phase):print("NATIVE_ORDER_PHASE ",phase)
			seen[phase]=true
			continue
		var above:int=b if phase in [0,2,4] else a
		var below:int=a if phase in [0,2,4] else b
		if phase==1: above=b;below=0
		if phase==6: above=0;below=a
		if DisplayServer.get_window_list().size()!=3 or not host.is_window_above(above,below):
			push_error("Native HWND order differs at phase "+str(phase));get_tree().quit(1);return
		if phase==1 and not host.is_window_above(a,0):
			push_error("Primary was not lowered below both peers");get_tree().quit(1);return
		if not seen.has(phase):print("NATIVE_ORDER_PHASE ",phase)
		seen[phase]=true
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending():break
		var drained:=[false]
		RenderingServer.frame_post_draw.connect(func() -> void: drained[0]=true,CONNECT_ONE_SHOT)
		get_tree().create_timer(0.02).timeout.connect(func() -> void: drained[0]=true,CONNECT_ONE_SHOT)
		while not drained[0]:
			await get_tree().process_frame
	if seen.size()!=17 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending() or DisplayServer.get_window_list().size()!=1:
		push_error("Native order coverage/drain differs");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:push_error("Native order resources retained");get_tree().quit(1);return
	host.free();print("GODOT_NATIVE_ORDER_PASS");get_tree().quit()
