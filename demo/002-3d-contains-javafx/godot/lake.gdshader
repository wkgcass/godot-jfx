shader_type spatial;
render_mode unshaded;

uniform vec4 near_water : source_color = vec4(0.49, 0.64, 0.62, 1.0);
uniform vec4 far_water : source_color = vec4(0.68, 0.76, 0.71, 1.0);
varying vec2 lake_position;

void vertex() {
	lake_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float distance_mix = smoothstep(4.0, 36.0, -lake_position.x);
	float wave = sin(12.0 * lake_position.x + 1.4 * sin(lake_position.y * 1.7)) * cos(lake_position.y * 0.9 + lake_position.x);
	float glint = smoothstep(0.70, 1.0, wave) * (1.0 - distance_mix);
	ALBEDO = mix(near_water.rgb, far_water.rgb, distance_mix) + vec3(0.055 * glint);
}
