extends Node2D

# P2b-3: the runtime LCD variant (GODOT_JFX_LCD_SCREEN default) rewrites the
# corpus shader the same way GodotShader.loadPrism does — dstColor becomes a
# hint_screen_texture sampler, texCoord2 becomes SCREEN_UV. The translator
# turns those into a snapshot sampler at the normalized fragment position;
# the probe compares against the canvas path, whose hint sampler reads the
# just-cleared target (transparent) — matched by an equally transparent
# stand-in on the RD side.
func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	if RenderingServer.get_rendering_device() == null:
		push_error("RD LCD probe requires RenderingDevice"); get_tree().quit(1); return
	var path := ProjectSettings.globalize_path("res://../../jfx/modules/javafx.graphics/build/gensrc/jsl-prism/com/sun/prism/godot/shaders/Solid_TextureSecondPassLCD.gdshader")
	var source := FileAccess.get_file_as_string(path)
	var replaced: String = source
	for rule in [
		["uniform sampler2D dstColor;", "uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;"],
		["texture(dstColor, texCoord2)", "texture(SCREEN_TEXTURE, texCoord2)"],
		["COLOR = paint(godot_uv0, godot_uv1, godot_vertex_color);", "COLOR = paint(godot_uv0, SCREEN_UV, godot_vertex_color);"],
	]:
		if not replaced.contains(rule[0]):
			print("RD_LCD_SPIKE anchor missing: ", rule[0]); get_tree().quit(1); return
		replaced = replaced.replace(rule[0], rule[1])
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			image.set_pixel(x, y, Color(float(x) / 15.0 * 0.7, 0.3, float(y) / 15.0 * 0.5, 0.4 + float(x) / 15.0 * 0.4))
	var texture := ImageTexture.create_from_image(image)
	var result: Dictionary = host.rd_translate_probe(replaced, texture.get_rid(), RID())
	if result.get("translate_ok", false):
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
		result = host.rd_translate_probe_finish()
	print("RD_LCD ", JSON.stringify(result))
	host.release_rd_cycle()
	if not result.get("translate_ok", false) or int(result.get("max_diff", 99)) > 2 or int(result.get("diffs_gt4", 99)) > 0:
		push_error("RD LCD spike failed"); get_tree().quit(1); return
	print("RD_LCD_SPIKE_PASS")
	get_tree().quit()
