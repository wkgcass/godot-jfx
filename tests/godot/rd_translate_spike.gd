extends Node2D

# Canvas shaders copied verbatim from the generated stock corpus (jsl-prism):
# Solid_Color, Solid_TextureRGB, AlphaTexture_Color. The probe renders the
# same batch through the viewport path and the translated RD pipeline and
# compares both readbacks pixel by pixel.
const SOLID_COLOR := "shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
varying vec4 godot_vertex_color;
void vertex() {
godot_vertex_color = COLOR;
}
void fragment() {
COLOR = godot_vertex_color;
}"

const TEXTURE_RGB := "shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
varying vec2 godot_uv0;
varying vec4 godot_vertex_color;
void vertex() {
godot_uv0 = UV;
godot_vertex_color = COLOR;
}
uniform sampler2D inputTex;
vec4 paint(vec2 texCoord) {
return texture(inputTex, texCoord);
}
void fragment() {
COLOR = paint(godot_uv0) * godot_vertex_color;
}"

const MASK_COLOR := "shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
varying vec2 godot_uv0;
varying vec4 godot_vertex_color;
void vertex() {
godot_uv0 = UV;
godot_vertex_color = COLOR;
}
uniform sampler2D maskInput;
float mask(vec2 texCoord) {
return texture(maskInput, texCoord).a;
}
void fragment() {
COLOR = mask(godot_uv0) * godot_vertex_color;
}"

func _ready() -> void:
	var host = ClassDB.instantiate("JavaFXHost"); add_child(host)
	await get_tree().process_frame
	if RenderingServer.get_rendering_device() == null:
		push_error("RD translate spike requires a RenderingDevice; no RD test was executed")
		get_tree().quit(1); return
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			image.set_pixel(x, y, Color(float(x) / 15.0 * 0.8, float(y) / 15.0 * 0.6 + 0.2, 0.4, 0.5 + float(x + y) / 30.0 * 0.5))
	var texture := ImageTexture.create_from_image(image)
	var failed := false
	var cases := [["solid_color", SOLID_COLOR, RID()], ["texture_rgb", TEXTURE_RGB, texture.get_rid()], ["mask_color", MASK_COLOR, texture.get_rid()]]
	for entry in cases:
		var result: Dictionary = host.rd_translate_probe(entry[1], entry[2], get_canvas_item())
		if result.get("translate_ok", false):
			# Both diagnostics share one resource state. A pending phase A must
			# survive a rejected attempt to start the cycle benchmark.
			var overlap: Dictionary = host.benchmark_rd_cycle(1, 1, get_canvas_item())
			if overlap.get("error", "") != "cycle_already_active":
				host.release_rd_cycle()
				push_error("RD pending translate was overwritten by cycle benchmark")
				get_tree().quit(1); return
			# The first frame after phase A misses per-item state; UPDATE_ONCE
			# survives to the second frame, which renders the reference.
			await RenderingServer.frame_pre_draw
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_pre_draw
			await RenderingServer.frame_post_draw
			result = host.rd_translate_probe_finish()
		print("RD_TRANSLATE ", entry[0], " ", JSON.stringify(result))
		if not result.get("translate_ok", false) or result.get("error", "") != "" \
				or int(result.get("max_diff", 99)) > 2 or int(result.get("diffs_gt4", 99)) > 0:
			failed = true
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_pre_draw
		await RenderingServer.frame_post_draw
		# The two previews (8,8,240,120) and (256,8,240,120) are drawn the same
		# way, so they must match each other; both must differ from the window
		# background. Blend conventions of the preview composite are not under
		# test here — the readback comparison above is the pixel gate. The
		# extra settle frame mirrors the phase-A reference: the first frame
		# after new canvas commands can still miss them.
		var shot := get_viewport().get_texture().get_image()
		var left := shot.get_pixel(128, 68)
		var right := shot.get_pixel(376, 68)
		var background := shot.get_pixel(600, 68)
		if abs(left.r8 - right.r8) > 4 or abs(left.g8 - right.g8) > 4 or abs(left.b8 - right.b8) > 4 \
				or left.r8 == background.r8 and left.g8 == background.g8 and left.b8 == background.b8:
			print("RD_TRANSLATE_PREVIEW_MISMATCH ", entry[0], " left=", left.to_html(false), " right=", right.to_html(false))
			failed = true
		host.release_rd_cycle()
	if failed:
		push_error("RD translate spike failed"); get_tree().quit(1); return
	print("RD_TRANSLATE_OVERLAP_REJECT_PASS cases=3")
	print("RD_TRANSLATE_SPIKE_PASS")
	get_tree().quit()
