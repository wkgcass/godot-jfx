extends Node2D

func fail(message:String) -> void:
	push_error(message); get_tree().quit(1)

func matches(info:Dictionary, color:int) -> bool:
	if OS.get_name()=="macOS": return info.get("installed", true)==false
	if color<0: return info.get("installed",true)==false
	# Quantum sends a 128px image on Linux. Windows requests LR_DEFAULTSIZE at system DPI.
	var native_size := 128 if OS.get_name() == "Linux" else roundi(32 * DisplayServer.screen_get_scale())
	if not info.get("installed",false) or info.get("width",0)!=native_size or info.get("height",0)!=native_size:return false
	var actual:int=info.get("center_argb",-1)
	if actual<0 or (int(info.get("corner_argb",-1))>>24)!=0:return false
	for shift in [0,8,16,24]:
		if absi(((actual>>shift)&255)-((color>>shift)&255))>2:return false
	return true

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not host.run_fixture_probe("WindowIconProbe"):
		fail("Icon probe failed");return
	var root_colors:=[0xffff0000,0xff00ff00,0xff00ff00,0xff00ff00,-1,-1,0x80000080]
	var child_colors:=[0xff0000ff,0xff0000ff,-1,0xffffff00,0xffffff00,0xffff00ff,0xffff00ff]
	var step:=0;var deadline:=Time.get_ticks_msec()+45000
	var diagnostic:=Time.get_ticks_msec()+3000
	while host.get_runtime_status()!="finished":
		await get_tree().process_frame
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			fail("Icon failed step=%d: %s"%[step,host.get_runtime_error()]);return
		if step>=7 or not get_window().title.begins_with("WindowIcon %d "%step):continue
		var child_id:=get_window().title.get_slice(" ",2).to_int()
		var root_info:Dictionary=host.get_window_icon_info(0)
		var child_info:Dictionary=host.get_window_icon_info(child_id)
		if root_info.has("supported") and not root_info["supported"]:
			fail("Wayland compositor does not advertise xdg_toplevel_icon_manager_v1")
			return
		if Time.get_ticks_msec()>diagnostic:
			print("WINDOW_ICON_WAIT ",step," ",JSON.stringify(root_info)," ",JSON.stringify(child_info))
			diagnostic=Time.get_ticks_msec()+3000
		if not matches(root_info,root_colors[step]) or not matches(child_info,child_colors[step]):continue
		print("WINDOW_ICON_NATIVE ",step," ",JSON.stringify(root_info)," ",JSON.stringify(child_info))
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.window_id=get_window().get_window_id();event.position=Vector2(120,60)*DisplayServer.screen_get_scale();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
			Input.parse_input_event(event)
		step+=1
	if step!=7:fail("Icon steps incomplete");return
	if host.get_native_window_count()!=0 or DisplayServer.get_window_list().size()!=1:
		fail("Icon probe native windows did not close");return
	remove_child(host)
	if host.get_owned_resource_count()!=0:fail("Icon probe GPU resources leaked");return
	host.free();print("GODOT_WINDOW_ICON_PASS");get_tree().quit()
