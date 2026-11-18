extends Node2D

# Boots HoverDemoProbe (the real demo + OS-cursor hover over its ImageButtons);
# the probe prints HOVER_DEMO_STATS / HOVER_DEMO_PASS to the host log.

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	await get_tree().process_frame
	if not host.run_fixture_probe("HoverDemoProbe"):
		push_error("Hover demo probe failed"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 200000
	var hold := 0
	var hold_bright := 0
	var gap := 0
	var gap_dark := 0
	var bright_threshold := 0.30
	var saved := 0
	var last_bounds := [0, 0, 0, 0]
	var frames_per_cycle := {}
	var gap_frames_per_cycle := {}
	# The VFX hover-exit animation is wall-clock driven, so the GAP settle
	# window must be wall-clock too: a frame-count skip misjudges whenever the
	# host frame rate dips (the animation then spans more frames).
	var gap_first_msec := {}
	var gap_settled_per_cycle := {}
	while host.get_runtime_status() != "finished":
		await get_tree().process_frame
		if host.get_runtime_status() == "failed" or Time.get_ticks_msec() > deadline:
			push_error("Hover demo probe failed: " + host.get_runtime_error()); get_tree().quit(1); return
		var title := get_window().title
		if not (title.begins_with("HoverDemo HOLD") or title.begins_with("HoverDemo GAP")):
			continue
		var image := get_viewport().get_texture().get_image()
		if title.begins_with("HoverDemo HOLD"):
			var parts := title.split(" ")
			if parts.size() < 7: continue
			var scale := DisplayServer.screen_get_scale(get_window().current_screen)
			var bx := int(round(float(parts[3]) * scale))
			var by := int(round(float(parts[4]) * scale))
			var bw := int(round(float(parts[5]) * scale))
			var bh := int(round(float(parts[6]) * scale))
			last_bounds = [bx, by, bw, bh]
			var luma := 0.0
			var count := 0
			for yy in range(max(0, by + 20), min(image.get_height(), by + bh - 20), 8):
				for xx in range(max(0, bx + 30), min(image.get_width(), bx + bw - 30), 10):
					var c := image.get_pixel(xx, yy)
					luma += (c.r + c.g + c.b) / 3.0
					count += 1
			luma /= max(1, count)
			var cycle := int(parts[2])
			var index: int = frames_per_cycle.get(cycle, 0)
			frames_per_cycle[cycle] = index + 1
			hold += 1
			if index == 30: print("HOVER_DEMO_CALIBRATION hold_luma=", luma)
			if index > 30 and luma >= bright_threshold: hold_bright += 1
			if index > 30 and luma < bright_threshold and saved < 6:
				saved += 1
				if saved <= 2:
					var row_text := ""
					for xx in range(max(0, bx + 40), min(image.get_width(), bx + bw - 40), max(20, (bw - 80) / 8)):
						var pc := image.get_pixel(xx, by + bh / 2)
						row_text += str(snappedi(pc.r8, 1)) + "," + str(snappedi(pc.g8, 1)) + "," + str(snappedi(pc.b8, 1)) + " "
					print("HOVER_DEMO_REVERT_FRAME cycle=", cycle, " index=", index, " midrow=", row_text)
		elif last_bounds[2] > 0:
			var parts := title.split(" ")
			var cycle := int(parts[2])
			var bx: int = last_bounds[0]
			var by: int = last_bounds[1]
			var bw: int = last_bounds[2]
			var bh: int = last_bounds[3]
			var luma := 0.0
			var count := 0
			for yy in range(max(0, by + 20), min(image.get_height(), by + bh - 20), 8):
				for xx in range(max(0, bx + 30), min(image.get_width(), bx + bw - 30), 10):
					var c := image.get_pixel(xx, yy)
					luma += (c.r + c.g + c.b) / 3.0
					count += 1
			luma /= max(1, count)
			var index: int = gap_frames_per_cycle.get(cycle, 0)
			gap_frames_per_cycle[cycle] = index + 1
			gap += 1
			var now := Time.get_ticks_msec()
			if not gap_first_msec.has(cycle): gap_first_msec[cycle] = now
			var settled: bool = now - int(gap_first_msec[cycle]) >= 500
			if settled: gap_settled_per_cycle[cycle] = gap_settled_per_cycle.get(cycle, 0) + 1
			if index == 30: print("HOVER_DEMO_CALIBRATION gap_luma=", luma)
			if settled and luma < bright_threshold: gap_dark += 1
			if settled and luma >= bright_threshold and saved < 24:
				saved += 1
				image.save_png(ProjectSettings.globalize_path("res://../../artifacts/reference/demo-stuck-") + str(cycle) + "-" + str(index) + ".png")
	print("HOVER_DEMO_PIXEL hold=", hold, " bright=", hold_bright, " gap=", gap, " dark=", gap_dark)
	if frames_per_cycle.size() != 8 or gap_frames_per_cycle.size() != 8:
		push_error("Hover demo cycles incomplete"); get_tree().quit(1); return
	var eligible_hold := 0
	var eligible_gap := 0
	for cycle in range(8):
		var h: int = frames_per_cycle.get(cycle,0)-31
		var g: int = gap_settled_per_cycle.get(cycle,0)
		if h <= 0 or g <= 0:
			push_error("Hover demo lacks settled samples in cycle " + str(cycle)); get_tree().quit(1); return
		eligible_hold += h
		eligible_gap += g
	if (eligible_hold-hold_bright)*20 > eligible_hold or (eligible_gap-gap_dark)*20 > eligible_gap:
		push_error("Hover demo settled brightness differs"); get_tree().quit(1); return
	print("HOVER_DEMO_PIXEL_PASS hold=",eligible_hold," gap=",eligible_gap)
	get_tree().quit(0)
