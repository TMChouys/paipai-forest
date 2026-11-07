shader_type spatial;
// 卡通著色（Cel / Toon）：亮、暗兩階再加一條柔和過渡，邊緣一點暖色輪廓光。
render_mode cull_back, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, hint_default_white;
uniform float shade_softness : hint_range(0.0, 0.3) = 0.06;
uniform float shade_offset : hint_range(-1.0, 1.0) = 0.05;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.18;
uniform float light_strength = 0.78;
uniform vec3 shade_tint : source_color = vec3(0.86, 0.8, 0.92);

void fragment() {
	vec4 c = albedo * texture(tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c.rgb * smoothstep(0.55, 0.75, rim) * rim_amount;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shade_offset - shade_softness, shade_offset + shade_softness, ndl);
	float shadow = smoothstep(0.3, 0.6, ATTENUATION);
	float k = lit * shadow;
	// 暗面帶一點冷紫，像水彩陰影
	DIFFUSE_LIGHT += light_strength * LIGHT_COLOR * mix(shade_tint * 0.25, vec3(1.0), k) / PI;
}
