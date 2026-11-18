extends Node2D

# Boots the HoverFlickerProbe. Plain styled buttons are sampled for the hover
# color per frame; the probe then cycles the demo's FusionButton (AnimationGraph
# hover + clip layers) while this side samples its luma per frame:
# HOLD frames should be bright after the 300ms ramp, GAP frames dark again
# after the ramp back. Reverts during holds and stuck-bright during gaps are
# the two user-visible present-side defects.
#
# Pointer movement is synthetic by default: when the probe publishes a HOLD/GAP
# title this side injects the matching motion event (HOLD → button center,
# FUSION GAP → outside the window) so the test never touches the real cursor.
# GODOT_JFX_HOVER_ROBOT=1 restores the physical Glass-Robot mode.

func inject_motion(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.window_id = get_window().get_window_id()
	motion.position = pos
	Input.parse_input_event(motion)

func sample_luma(image: Image, bx: int, by: int, bw: int, bh: int) -> float:
	var total := 0.0
	var count := 0
	for yy in range(max(0, by + 20), min(image.get_height(), by + bh - 20), 6):
		for xx in range(max(0, bx + 30), min(image.get_width(), bx + bw - 30), 8):
			var c := image.get_pixel(xx, yy)
			total += (c.r + c.g + c.b) / 3.0
			count += 1
	return total / max(1, count)

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	await get_tree().process_frame
	if not host.run_fixture_probe("HoverFlickerProbe"):
		push_error("Hover flicker probe failed"); get_tree().quit(1); return
	var hold_frames := 0
	var flicker_frames := 0
	var settle := 8 # hover repaint landing at a hold boundary is legal
	var fusion_hold := 0
	var fusion_hold_bright := 0
	var fusion_gap := 0
	var fusion_gap_dark := 0
	var fusion_hold_frames_per_cycle := {}
	var bright_threshold := 0.30 # Fixed theme threshold; calibration below is diagnostic.
	var last_bx := 0
	var last_by := 0
	var last_bw := 0
	var last_bh := 0
	var gap_frames_per_cycle := {}
	var saved_violations := 0
	var robot_mode := OS.get_environment("GODOT_JFX_HOVER_ROBOT") == "1"
	var injected_title := ""
	var deadline := Time.get_ticks_msec() + 120000
	while host.get_runtime_status() != "finished":
		await get_tree().process_frame
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Hover probe failed or timed out: " + host.get_runtime_error())
			get_tree().quit(1); return
		var scale := DisplayServer.screen_get_scale(get_window().current_screen)
		var title := get_window().title
		if not robot_mode and title != injected_title:
			# Synthetic pointer: HOLD titles carry the button rect in stage-local
			# logical coordinates; input events use physical window pixels at the
			# current monitor scale, as does the sampler below. GAP parks the pointer
			# outside the window so hover exits, like the robot's (-60,-60).
			var parts := title.split(" ")
			if title.begins_with("HoverFlicker FUSION GAP"):
				inject_motion(Vector2(-120, -120))
				injected_title = title
			elif (title.begins_with("HoverFlicker HOLD") or title.begins_with("HoverFlicker FUSION HOLD")) and parts.size() >= 8:
				inject_motion(Vector2((float(parts[4]) + float(parts[6]) / 2.0) * scale, (float(parts[5]) + 6) * scale))
				injected_title = title
		var image := get_viewport().get_texture().get_image()
		if title.begins_with("HoverFlicker FUSION HOLD"):
			var parts := title.split(" ")
			if parts.size() < 8: continue
			var bx := int(round(float(parts[4]) * scale))
			var by := int(round(float(parts[5]) * scale))
			var bw := int(round(float(parts[6]) * scale))
			var bh := int(round(float(parts[7]) * scale))
			var luma := sample_luma(image, bx, by, bw, bh)
			var cycle := int(parts[3])
			last_bx = bx; last_by = by; last_bw = bw; last_bh = bh
			fusion_hold += 1
			# Skip the 300ms enter ramp (~20 frames) before judging.
			if fusion_hold_frames_per_cycle.get(cycle, 0) > 22 and luma >= bright_threshold:
				fusion_hold_bright += 1
			var hold_index: int = fusion_hold_frames_per_cycle.get(cycle, 0)
			if hold_index > 22 and luma < bright_threshold and saved_violations < 12:
				saved_violations += 1
				image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/fusion-revert-") + str(cycle) + "-" + str(hold_index) + ".png")
			fusion_hold_frames_per_cycle[cycle] = fusion_hold_frames_per_cycle.get(cycle, 0) + 1
			if cycle == 0 and fusion_hold == 30:
				print("HOVER_FUSION_CALIBRATION hold_luma=", luma)
		elif title.begins_with("HoverFlicker FUSION GAP") and last_bw > 0:
			var parts := title.split(" ")
			var cycle := int(parts[3])
			# After the cursor leaves, the exit ramp (~20 frames) should end
			# dark; frames still bright long after the ramp are stuck-hover.
			var luma := sample_luma(image, last_bx, last_by, last_bw, last_bh)
			fusion_gap += 1
			if gap_frames_per_cycle.get(cycle, 0) > 22 and luma < bright_threshold:
				fusion_gap_dark += 1
			var gap_index: int = gap_frames_per_cycle.get(cycle, 0)
			var gap_stuck: bool = gap_index > 22 and luma >= bright_threshold
			if gap_stuck and saved_violations < 24:
				saved_violations += 1
				image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/fusion-stuck-") + str(cycle) + "-" + str(gap_index) + ".png")
			gap_frames_per_cycle[cycle] = gap_frames_per_cycle.get(cycle, 0) + 1
			if cycle == 0 and fusion_gap == 30:
				print("HOVER_FUSION_CALIBRATION gap_luma=", luma)
		elif title.begins_with("HoverFlicker HOLD"):
			var parts := title.split(" ")
			if parts.size() < 8: continue
			var bx := int(round(float(parts[4]) * scale))
			var by := int(round(float(parts[5]) * scale))
			var bw := int(round(float(parts[6]) * scale))
			var bh := int(round(float(parts[7]) * scale))
			var found := false
			for yy in range(max(0, by + 4), min(image.get_height(), by + bh - 4), 4):
				for xx in range(max(0, bx + 8), min(image.get_width(), bx + bw - 8), 6):
					var c := image.get_pixel(xx, yy)
					if c.g > 0.5 and c.r < 0.45 and c.b < 0.45:
						found = true
						break
				if found: break
			hold_frames += 1
			if not found:
				if settle > 0: settle -= 1
				else: flicker_frames += 1
	print("HOVER_PIXEL_STATS hold_frames=", hold_frames, " flicker_frames=", flicker_frames,
			" fusion_hold=", fusion_hold, " fusion_hold_bright=", fusion_hold_bright,
			" fusion_gap=", fusion_gap, " fusion_gap_dark=", fusion_gap_dark)
	if hold_frames < 600 or flicker_frames * 20 > hold_frames:
		push_error("Hover flicker check failed: ", flicker_frames, "/", hold_frames)
		get_tree().quit(1); return
	# Judge FusionButton after each enter/exit ramp, not only plain buttons.
	if fusion_hold_frames_per_cycle.size() != 6 or gap_frames_per_cycle.size() != 6:
		push_error("Fusion hover phases incomplete"); get_tree().quit(1); return
	var eligible_hold := 0
	var eligible_gap := 0
	for cycle in range(6):
		var hold_count: int = fusion_hold_frames_per_cycle.get(cycle,0) - 23
		var gap_count: int = gap_frames_per_cycle.get(cycle,0) - 23
		if hold_count <= 0 or gap_count <= 0:
			push_error("Fusion phase has no settled samples: " + str(cycle)); get_tree().quit(1); return
		eligible_hold += hold_count
		eligible_gap += gap_count
	if (eligible_hold-fusion_hold_bright)*20 > eligible_hold or (eligible_gap-fusion_gap_dark)*20 > eligible_gap:
		push_error("Fusion settled hover reverted or stayed bright"); get_tree().quit(1); return
	remove_child(host)
	if host.get_owned_resource_count()!=0:
		push_error("Hover flicker host retained resources after stop"); get_tree().quit(1); return
	host.free()
	print("HOVER_RESOURCE_CLEANUP_PASS")
	print("HOVER_FUSION_PIXEL_PASS eligible_hold=",eligible_hold," eligible_gap=",eligible_gap)
	get_tree().quit(0)
