extends Node2D
func _ready() -> void:
	get_window().size=Vector2i(260,180); get_window().position=Vector2i(30,60)
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("NativeWindowBridgeProbe"):
		push_error("Native bridge start failed"); get_tree().quit(1); return
	var seen:={}
	var default_maximum:=Vector2i.ZERO
	var deadline:=Time.get_ticks_msec()+30000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Native bridge failed: "+host.get_runtime_error()); get_tree().quit(1); return
		await get_tree().process_frame
		var title:=get_window().title
		if seen.has(title): continue
		if title=="Native bridge shown":
			if DisplayServer.get_window_list().size()!=3 or host.get_native_window(100).title!="独立窗口 A" or host.get_native_window(101).title!="独立窗口 B":
				push_error("Native window/title count differs"); get_tree().quit(1); return
			seen[title]=true
			default_maximum=host.get_native_window(101).max_size
		elif title in ["Native bridge properties", "Native bridge reset"]:
			var first=host.get_native_window(100)
			var second=host.get_native_window(101)
			var changed:=title=="Native bridge properties"
			if first.title!="更新标题 A" or second.title!="独立窗口 B" or first.unresizable!=changed or first.always_on_top!=changed or first.borderless!=changed:
				push_error("Native property isolation differs"); get_tree().quit(1); return
			if first.min_size!=(Vector2i(200,100) if changed else Vector2i.ZERO) or first.max_size!=(Vector2i(600,400) if changed else Vector2i.ZERO):
				push_error("Native size limits differ at %s: min=%s max=%s default=%s"%[title,first.min_size,first.max_size,default_maximum]); get_tree().quit(1); return
			if second.unresizable or second.always_on_top or not second.borderless or second.min_size!=Vector2i.ZERO or second.max_size!=default_maximum or get_window().size!=Vector2i(260,180):
				push_error("Properties changed another window: %s %s %s %s %s root=%s"%[second.unresizable,second.always_on_top,second.borderless,second.min_size,second.max_size,get_window().size]); get_tree().quit(1); return
			seen[title]=true
		elif title in ["Native bridge resized","Native bridge hidden","Native bridge destroyed"]: seen[title]=true
	if seen.size()!=6 or host.get_native_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		push_error("Native bridge coverage/cleanup differs"); get_tree().quit(1); return
	remove_child(host); host.free()
	print("GODOT_NATIVE_WINDOW_BRIDGE_PASS"); get_tree().quit(0)
