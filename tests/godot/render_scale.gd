extends Node2D
func pixels_match(image:Image,width:int,height:int) -> bool:
	var scale:=DisplayServer.screen_get_scale()
	if image.get_width()!=roundi(width*scale) or image.get_height()!=roundi(height*scale): return false
	var points:=[Vector2i(25,35),Vector2i(90,70),Vector2i(width-8,height-8),Vector2i(5,5)]
	var colors:=[Color.RED,Color.GREEN,Color.BLUE,Color(.75,.75,.75)]
	for i in range(points.size()):
		var actual:=image.get_pixelv(Vector2i(Vector2(points[i])*scale)); var wanted:Color=colors[i]
		if maxf(absf(actual.r-wanted.r),maxf(absf(actual.g-wanted.g),absf(actual.b-wanted.b)))>.04: return false
	return true

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	if not host.run_fixture_probe("RenderScaleProbe"):
		fail("Scale probe rejected"); return
	var primary_sizes:=[Vector2i(320,240),Vector2i(640,480),Vector2i(640,480),Vector2i(240,300),Vector2i(320,240),Vector2i(320,240)]
	var child_sizes:=[Vector2i(288,192),Vector2i(288,192),Vector2i(432,384),Vector2i(432,384),Vector2i(576,144),Vector2i(288,192)]
	var step:=0; var deadline:=Time.get_ticks_msec()+90000
	var diagnostic:=Time.get_ticks_msec()+2000
	while host.get_runtime_status()!="finished":
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			fail("Scale failed step="+str(step)+" root_buffer="+str(host.get_window_content_size(1))+" "+host.get_runtime_error()); return
		await RenderingServer.frame_post_draw
		if step>=6 or get_window().title!="RenderScale "+str(step): continue
		var child=host.get_native_window(2)
		if Time.get_ticks_msec()>diagnostic:
			print("SCALE_STATE root=",get_window().size," root_buffer=",host.get_window_content_size(1)," child_buffer=",child.get_content_size() if child!=null else Vector2i())
			if child!=null:
				print("SCALE_PIXELS root=",get_window().get_texture().get_image().get_pixel(90,70)," child=",child.get_texture().get_image().get_pixel(90,70))
			diagnostic=Time.get_ticks_msec()+3000
		if child==null or child.is_present_pending() or host.is_composition_pending(): continue
		if child.get_window_id()==get_window().get_window_id(): fail("Scale child reused primary"); return
		if host.get_window_content_size(1)!=primary_sizes[step] or child.get_content_size()!=child_sizes[step]: continue
		var root_image:=get_window().get_texture().get_image()
		var child_image:Image=child.get_texture().get_image()
		if not pixels_match(root_image,320,240) or not pixels_match(child_image,288,192): continue
		print("RENDER_SCALE step=",step," root_buffer=",host.get_window_content_size(1)," child_buffer=",child.get_content_size())
		root_image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/render-scale-root-%d.png"%step))
		child_image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/render-scale-child-%d.png"%step))
		var target=get_window() if step%2==0 else child
		var point:=Vector2(30,40)*DisplayServer.screen_get_scale()
		var motion:=InputEventMouseMotion.new(); motion.window_id=target.get_window_id(); motion.position=point; Input.parse_input_event(motion)
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new(); event.window_id=target.get_window_id(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; Input.parse_input_event(event)
		step+=1
	if step!=6: fail("Scale phases incomplete"); return
	for i in range(120):
		if host.get_window_count()==0 and host.get_native_window_count()==0 and not host.is_composition_pending(): break
		await RenderingServer.frame_post_draw
	if host.get_window_count()!=0 or host.get_native_window_count()!=0 or host.is_composition_pending(): fail("Scale windows did not drain"); return
	remove_child(host)
	if host.get_owned_resource_count()!=0: fail("Scale resources leaked"); return
	host.free(); print("GODOT_RENDER_SCALE_PASS"); get_tree().quit()

func fail(message:String) -> void:
	push_error(message); get_tree().quit(1)

