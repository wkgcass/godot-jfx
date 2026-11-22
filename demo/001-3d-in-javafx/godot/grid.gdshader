shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 grid_color : source_color = vec4(0.7294, 0.7098, 0.6706, 1.0);

void fragment() {
	vec2 cell = (UV - 0.5) * 12.0;
	vec2 dx = dFdx(cell);
	vec2 dy = dFdy(cell);
	vec2 footprint = max(sqrt(dx * dx + dy * dy), vec2(0.0001));
	vec2 distance_px = abs(fract(cell + 0.5) - 0.5) / footprint;
	// Smooth one-pixel lines; fade the floor before its outer edge becomes visible.
	vec2 ink = max(1.0 - distance_px, vec2(0.0))
			* (1.0 - smoothstep(vec2(0.18), vec2(0.5), footprint));
	ALBEDO = grid_color.rgb;
	ALPHA = max(ink.x, ink.y) * (1.0 - smoothstep(2.0, 5.5, length(cell)));
}
