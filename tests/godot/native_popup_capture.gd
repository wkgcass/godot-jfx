extends RefCounted

# A newly shown native window can precede its first Prism publication. Pending
# being false alone does not establish that any content has reached the viewport.
static func capture(window: Window, path: String) -> bool:
	for frame in range(240):
		await RenderingServer.frame_post_draw
		if window.is_present_pending(): continue
		var pixels:=window.get_texture().get_image()
		if pixels.is_empty() or not pixels.get_used_rect().has_area(): continue
		var low:=1.0
		var high:=0.0
		for y in range(0,pixels.get_height(),2):
			for x in range(0,pixels.get_width(),2):
				var color:=pixels.get_pixel(x,y)
				if color.a<0.9: continue
				var luminance:=(color.r+color.g+color.b)/3.0
				low=minf(low,luminance); high=maxf(high,luminance)
		if high-low<0.25: continue
		return pixels.save_png(ProjectSettings.globalize_path(path))==OK
	return false
