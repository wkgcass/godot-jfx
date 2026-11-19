extends Node

func verify(window,opaque:bool,tag:String) -> bool:
	if window.is_embedded() or not window.get_flag(Window.FLAG_TRANSPARENT) or not window.transparent_bg:return false
	var image:Image=window.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/transparent-"+tag+".png"))
	var scale:=DisplayServer.screen_get_scale(window.current_screen)
	var empty:=image.get_pixel(roundi(10*scale),roundi(10*scale))
	var solid:=image.get_pixel(roundi(50*scale),roundi(50*scale))
	var half:=image.get_pixel(roundi(150*scale),roundi(50*scale))
	if not opaque:
		for x in range(image.get_width()):
			if image.get_pixel(x,0).a>0.02 or image.get_pixel(x,image.get_height()-1).a>0.02:return false
		for y in range(image.get_height()):
			if image.get_pixel(0,y).a>0.02 or image.get_pixel(image.get_width()-1,y).a>0.02:return false
	print("TRANSPARENT_PIXELS empty=",empty," solid=",solid," half=",half)
	return absf(empty.a-(1.0 if opaque else 0.0))<0.02 and solid.r>0.95 and solid.g<0.05 and solid.a>0.98 and absf(half.a-(1.0 if opaque else 0.5))<0.02

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost");add_child(host)
	if not ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed",false):
		push_error("Host per-pixel transparency disabled");get_tree().quit(1);return
	if not host.run_fixture_probe("TransparentStageProbe"):
		push_error("Transparent probe failed");get_tree().quit(1);return
	var seen:={};var deadline:=Time.get_ticks_msec()+60000
	# Hidden windows stop drawing on macOS. Observe startup/close on scene
	# frames and reserve draw fences for the visible pixel checks below.
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Transparent runtime failed: "+host.get_runtime_error());get_tree().quit(1);return
		await get_tree().process_frame
		var title:=get_window().title
		if not title.begins_with("Transparent ") or host.is_composition_pending():continue
		var phase:=title.get_slice(" ",1).to_int()
		if seen.has(phase):continue
		var child=host.get_native_window(title.get_slice(" ",2).to_int())
		if child==null or child.is_present_pending():continue
		for frame in range(3):await RenderingServer.frame_post_draw
		if DisplayServer.get_window_list().size()!=2 or not verify(get_window(),phase==2,"root-"+str(phase)) or not verify(child,false,"child-"+str(phase)):
			push_error("Transparent pixels/native flags differ at phase "+str(phase));get_tree().quit(1);return
		seen[phase]=true
	for frame in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending():break
		await get_tree().process_frame
	if seen.size()!=4 or host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending():
		push_error("Transparent coverage/drain incomplete");get_tree().quit(1);return
	remove_child(host)
	if host.get_owned_resource_count()!=0:push_error("Transparent resources retained");get_tree().quit(1);return
	host.free();print("GODOT_TRANSPARENT_STAGE_PASS");get_tree().quit()
