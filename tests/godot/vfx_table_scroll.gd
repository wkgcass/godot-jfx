extends Node2D

# Perf harness for the large-table drag. The Java probe fires the viewport's
# own drag handler, so no synthesized OS input and no window focus is needed;
# this side only snapshots host render counters between the title markers.

func inject(point:Vector2, kind:int) -> void:
	# Full input pipeline: Godot synthesized input delivered by window id,
	# forwarded through the host to Glass exactly like OS input.
	var event
	if kind==0:
		event=InputEventMouseMotion.new(); event.button_mask=MOUSE_BUTTON_MASK_LEFT
	elif kind==1:
		event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
	else:
		event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=false
	event.window_id=get_window().get_window_id(); event.position=point
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _ready() -> void:
	var host=ClassDB.instantiate("JavaFXHost"); add_child(host)
	var base:=ProjectSettings.globalize_path("res://../../artifacts/vfx")
	var entries:=PackedStringArray([base+"/classes/java/main",base+"/classes/java/test",base+"/resources/main",base+"/resources/test",ProjectSettings.globalize_path("res://../../artifacts/reference")])
	for file in DirAccess.get_files_at(base+"/dependencies"):
		if file.ends_with(".jar"): entries.append(base+"/dependencies/"+file)
	if not host.start_jvm(OS.get_environment("GODOT_JFX_JDK"),ProjectSettings.globalize_path("res://../../jfx/build/sdk"),(";" if OS.has_feature("windows") else ":").join(entries),"VfxTableScrollProbe"):
		push_error("Table scroll JVM failed"); get_tree().quit(1); return
	var baseline:Dictionary={}
	var idleBaseline:Dictionary={}
	var idleStartUs:=0
	var start_us:int
	var reported:=false
	var idleReported:=false
	var measured_ticks:=0
	var unfocused_ticks:=0
	var deadline:=Time.get_ticks_msec()+150000
	var idle_ticks:=0
	var idle_unfocused_ticks:=0
	var growth_sample:Array=[]
	# Real-drag mode: high-rate motion events through the real input pipeline.
	var real_mode:=OS.get_environment("GODOT_JFX_DRAG_MODE")=="real"
	var drag_axis:=Vector2.RIGHT if OS.get_environment("GODOT_JFX_DRAG_AXIS")=="h" else Vector2.DOWN
	var events_per_frame:=int(OS.get_environment("GODOT_JFX_REAL_EVENTS"))
	if events_per_frame<1: events_per_frame=8
	var configured_sweeps:=OS.get_environment("GODOT_JFX_TABLE_SWEEPS")
	var sweeps:=3 if configured_sweeps.is_empty() else configured_sweeps.to_int()
	if sweeps<3 or sweeps>30:
		push_error("Table sweeps must be in [3,30]"); get_tree().quit(1); return
	var drag_frames:=sweeps*32
	var real_pressed:=false
	var real_frame:=0
	var real_base:=Vector2.ZERO
	var real_prev_offset:=0.0
	var real_scale:=1.0
	while host.get_runtime_status()!="finished":
		await get_tree().process_frame
		if host.get_runtime_status()=="failed" or Time.get_ticks_msec()>deadline:
			push_error("Table scroll failed: %s"%host.get_runtime_error()); get_tree().quit(1); return
		if not idleBaseline.is_empty() and not idleReported:
			idle_ticks+=1
			if not get_window().has_focus(): idle_unfocused_ticks+=1
		if not baseline.is_empty() and not reported:
			measured_ticks+=1
			if not get_window().has_focus(): unfocused_ticks+=1
		if real_mode and not real_pressed and get_window().title.begins_with("VfxTableScroll REAL "):
			var parts:=get_window().title.split(" ")
			real_base=Vector2(parts[2].to_float(),parts[3].to_float())
			real_scale=DisplayServer.screen_get_scale(get_window().current_screen)
			inject(real_base*real_scale,1)
			real_pressed=true
		if get_window().title=="VfxTableScroll IDLE" and idleBaseline.is_empty():
			idleBaseline=host.get_render_stats(); idleStartUs=Time.get_ticks_usec()
		# The drag marker supersedes the one-pulse idle-end marker: snapshot the
		# idle delta and arm the drag baseline from the same long-lived title.
		# Real-drag mode announces "REAL" instead of "START".
		var start_title:="VfxTableScroll START"
		if real_mode: start_title="VfxTableScroll REAL"
		if get_window().title.begins_with(start_title) and not idleReported and not idleBaseline.is_empty():
			var idle:Dictionary=host.get_render_stats()
			var idleDelta:Dictionary={}
			for key in idle:
				if key.begins_with("max_"): idleDelta["lifetime_"+key]=idle[key]
				elif key == "offscreen_gpu_us": idleDelta["last_"+key]=idle[key]
				else: idleDelta[key]=idle[key]-idleBaseline.get(key,0)
			idleDelta["measured_ticks"]=idle_ticks
			idleDelta["unfocused_ticks"]=idle_unfocused_ticks
			idleDelta["elapsed_ms"]=(Time.get_ticks_usec()-idleStartUs)/1000.0
			print("VFX_TABLE_SCROLL_IDLE_STATS ",JSON.stringify(idleDelta))
			idleReported=true
			baseline=host.get_render_stats(); start_us=Time.get_ticks_usec()
			growth_sample.append([0,baseline.get("offscreen_passes",0),baseline.get("presentations",0),baseline.get("host_ticks",0)])
		if get_window().title=="VfxTableScroll END" and not reported and not baseline.is_empty():
			var stats:Dictionary=host.get_render_stats()
			var delta:Dictionary={}
			for key in stats:
				if key.begins_with("max_"): delta["lifetime_"+key]=stats[key]
				elif key == "offscreen_gpu_us": delta["last_"+key]=stats[key]
				else: delta[key]=stats[key]-baseline.get(key,0)
			delta["elapsed_ms"]=(Time.get_ticks_usec()-start_us)/1000.0
			delta["measured_ticks"]=measured_ticks
			delta["unfocused_ticks"]=unfocused_ticks
			print("VFX_TABLE_SCROLL_STATS ",JSON.stringify(delta))
			growth_sample.append([measured_ticks,stats.get("offscreen_passes",0),stats.get("presentations",0),stats.get("host_ticks",0)])
			if measured_ticks < 1 or unfocused_ticks > measured_ticks:
				push_error("Invalid drag observation interval"); get_tree().quit(1); return
			for index in range(1,growth_sample.size()):
				if growth_sample[index][0] <= growth_sample[index-1][0]:
					push_error("Resource growth ticks are not strictly increasing"); get_tree().quit(1); return
			print("VFX_TABLE_SCROLL_GROWTH ",JSON.stringify(growth_sample))
			reported=true
		elif not baseline.is_empty() and not reported and measured_ticks > 0 and measured_ticks%8==0:
			var probe_stats:Dictionary=host.get_render_stats()
			growth_sample.append([measured_ticks,probe_stats.get("offscreen_passes",0),probe_stats.get("presentations",0),probe_stats.get("host_ticks",0)])
		if real_mode and real_pressed and real_frame<drag_frames:
			# Same sawtooth the probe's direct mode uses; interpolate sub-positions
			# so events_per_frame motions per Godot frame emulate a fast device.
			var phase:=real_frame%32
			var sweep:=real_frame/32
			var offset:=(25.0*phase)*(1.0 if sweep%2==1 else -1.0)
			for i in range(events_per_frame):
				var t:=float(i+1)/float(events_per_frame)
				var sub:=real_prev_offset+(offset-real_prev_offset)*t
				inject((real_base+drag_axis*sub)*real_scale,0)
			real_prev_offset=offset
			real_frame+=1
			if real_frame==drag_frames:
				inject((real_base+drag_axis*real_prev_offset)*real_scale,2)
	if not reported:
		push_error("Table scroll markers not observed"); get_tree().quit(1); return
	for frame in range(120):
		if host.get_window_count()==0 and not host.is_composition_pending(): break
		await get_tree().process_frame
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Table scroll resources leaked"); get_tree().quit(1); return
	host.free(); print("GODOT_VFX_TABLE_SCROLL_PASS"); get_tree().quit()
