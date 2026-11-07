shader_type spatial;
// 2D 臉貼圖：跟身體同樣的卡通光影，但只畫有顏色的部分（眼睛、眉毛、嘴巴、腮紅）。
render_mode cull_back, specular_disabled, depth_draw_opaque;

uniform sampler2D face : source_color, filter_linear_mipmap, hint_default_transparent;
uniform float shade_softness = 0.06;
uniform float shade_offset = 0.05;
uniform float light_strength = 0.78;
uniform vec3 shade_tint : source_color = vec3(0.86, 0.8, 0.92);

void fragment() {
	vec4 c = texture(face, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 1.0;
	// 臉在暗面也保持清楚：加一點自發光
	EMISSION = c.rgb * 0.18;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shade_offset - shade_softness, shade_offset + shade_softness, ndl);
	float k = lit * smoothstep(0.3, 0.6, ATTENUATION);
	DIFFUSE_LIGHT += light_strength * LIGHT_COLOR * mix(shade_tint * 0.25, vec3(1.0), k) / PI;
}
