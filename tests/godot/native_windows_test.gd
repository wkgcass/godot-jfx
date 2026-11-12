extends Node2D

func fail(message: String) -> bool:
	push_error(message); get_tree().quit(1); return false

func paint(color: Color, size: Vector2i):
	var target=ClassDB.instantiate("JavaFXRenderTarget")
	if not target.initialize(size): fail("Native target allocation failed"); return null
	target.begin_pass(true); target.add_rectangle(Rect2(Vector2.ZERO,size),color); target.end_pass()
	for frame in range(3): await RenderingServer.frame_post_draw
	target.finish_pass()
	return target

func settled(window) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while window.is_present_pending():
		if Time.get_ticks_msec()>deadline: return fail("Native presentation timed out")
		await get_tree().process_frame
	for frame in range(3): await RenderingServer.frame_post_draw
	return true

func pixel(window, expected: Color) -> bool:
	var image:Image=window.get_texture().get_image()
	var actual:=image.get_pixel(30,30)
	if maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b)))>.04:
		return fail("Native window pixel differs: "+str(actual))
	return true

func _ready() -> void:
	get_window().size=Vector2i(260,180); get_window().position=Vector2i(30,60)
	var baseline:=DisplayServer.get_window_list().size()
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.create_native_window(100,0,Rect2i(330,60,320,180),"JavaFX native presentation A",0): fail("Host window creation failed"); return
	if host.create_native_window(100,0,Rect2i(330,60,320,180),"Duplicate",0) or host.create_native_window(101,999,Rect2i(330,60,320,180),"Unknown owner",0):
		fail("Host accepted duplicate identity/unknown owner"); return
	if not host.create_native_window(101,100,Rect2i(330,300,320,180),"JavaFX native presentation B",1): fail("Owned native creation failed"); return
	var first=host.get_native_window(100)
	var second=host.get_native_window(101)
	host.configure_native_window(100,Rect2i(330,60,320,180),true)
	host.configure_native_window(101,Rect2i(330,300,320,180),true)
	for frame in range(5): await RenderingServer.frame_post_draw
	if first.is_embedded() or second.is_embedded() or first.get_window_id()==second.get_window_id() or DisplayServer.get_window_list().size()!=baseline+2:
		fail("Secondary windows are not distinct native windows"); return
	if first.position.x<=get_window().position.x+get_window().size.x:
		fail("Native Stage fixture does not extend beyond original host"); return
	var first_info:Dictionary=host.get_native_window_info(100)
	var second_info:Dictionary=host.get_native_window_info(101)
	if first_info.id!=100 or second_info.owner!=100 or first_info.native_id==second_info.native_id or host.get_native_window_count()!=2:
		fail("Window identity snapshot differs"); return
	var red=await paint(Color.RED,Vector2i(320,180))
	var blue=await paint(Color.BLUE,Vector2i(320,180))
	var old_id:int=red.get_instance_id()
	var blue_id:int=blue.get_instance_id()
	if not first.present_content(red) or not second.present_content(blue): fail("Native publication rejected"); return
	red=null; blue=null
	if not await settled(first) or not await settled(second): return
	if not pixel(first,Color.RED) or not pixel(second,Color.BLUE): return
	first.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/native-window-a.png"))
	second.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/native-window-b.png"))
	host.configure_native_window(100,Rect2i(350,70,400,240),true)
	var green=await paint(Color.GREEN,Vector2i(400,240))
	var green_id:int=green.get_instance_id()
	if not first.present_content(green): fail("Native replacement rejected"); return
	green=null
	if not await settled(first): return
	if not pixel(first,Color.GREEN) or not pixel(second,Color.BLUE): return
	if is_instance_id_valid(old_id) or second.size!=Vector2i(320,180) or get_window().size!=Vector2i(260,180):
		fail("Native replacement retained old target or resized another window"); return
	second.hide()
	for frame in range(3): await RenderingServer.frame_post_draw
	if not first.visible or second.visible: fail("Native hide changed sibling visibility"); return
	second.show()
	for frame in range(5): await RenderingServer.frame_post_draw
	if not pixel(second,Color.BLUE): return
	if DisplayServer.get_window_list().size()!=baseline+2: fail("Native show did not restore window count"); return
	var first_id:int=first.get_instance_id()
	var second_id:int=second.get_instance_id()
	host.destroy_native_window(100)
	if is_instance_id_valid(blue_id) or is_instance_id_valid(green_id): fail("Native owner teardown retained GPU targets"); return
	if is_instance_id_valid(first_id) or is_instance_id_valid(second_id) or host.get_native_window_count()!=0 or not host.get_native_window_info(101).is_empty():
		fail("Owner destruction retained native children or identities"); return
	# Tree exit must also destroy windows whose caller did not explicitly close.
	if not host.create_native_window(102,0,Rect2i(330,60,320,180),"Teardown",0): fail("Teardown creation failed"); return
	host.configure_native_window(102,Rect2i(330,60,320,180),true)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	remove_child(host)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(10,10)
	get_viewport().push_input(motion, true)
	if Input.get_current_cursor_shape() != Input.CURSOR_CROSS:
		host.free()
		fail("Host without JVM changed application default cursor"); return
	if host.get_native_window_count()!=0: fail("Host exit retained window registry"); return
	Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
	host.free()
	get_viewport().push_input(motion, true)
	if Input.get_current_cursor_shape() != Input.CURSOR_IBEAM:
		fail("Host destruction changed application default cursor"); return
	print("NATIVE_NO_JVM_CURSOR_PASS")
	for frame in range(3): await RenderingServer.frame_post_draw
	if DisplayServer.get_window_list().size()!=baseline: fail("Native windows leaked on deletion"); return
	print("NATIVE_WINDOWS_PASS: independent OS windows/viewports, outside-host placement, GPU replacement, resize/hide/show, cleanup")
	get_tree().quit(0)
