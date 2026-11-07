shader_type spatial;
// 卡通著色（Cel / Toon）：亮、暗兩階再加一條柔和過渡，邊緣一點暖色輪廓光。
// fur > 0：毛茸茸——細細的毛流深淺＋邊緣一圈柔亮的絨毛光（像絨布娃娃）。
render_mode cull_back, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, hint_default_white;
uniform float shade_softness : hint_range(0.0, 0.3) = 0.08;
uniform float shade_offset : hint_range(-1.0, 1.0) = 0.05;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.18;
uniform float light_strength = 0.78;
uniform vec3 shade_tint : source_color = vec3(0.86, 0.8, 0.92);
uniform float fur : hint_range(0.0, 1.0) = 0.0;
uniform float fur_scale = 90.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec4 c = albedo * texture(tex, UV);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = c.rgb;
	if (fur > 0.0) {
		// 毛流：沿著往下的方向拉長的細雜訊
		vec3 p = obj_pos * fur_scale;
		float strands = noise3(vec3(p.x, p.y * 0.25, p.z)) * 0.7 + noise3(p * 2.3) * 0.3;
		col *= 1.0 - fur * 0.16 * (strands - 0.35);
		// 絨毛光：邊緣寬寬的一圈，帶一點毛流的不規則
		float fuzz = smoothstep(0.08, 0.9, pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6));
		EMISSION = col * fuzz * fur * (0.22 + 0.18 * strands);
	} else {
		EMISSION = col * smoothstep(0.55, 0.75, rim) * rim_amount;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// 毛茸茸的東西明暗交界更柔和
	float soft = shade_softness + fur * 0.12;
	float lit = smoothstep(shade_offset - soft, shade_offset + soft, ndl);
	float shadow = smoothstep(0.3, 0.6, ATTENUATION);
	float k = lit * shadow;
	// 暗面帶一點冷紫，像水彩陰影
	DIFFUSE_LIGHT += light_strength * LIGHT_COLOR * mix(shade_tint * 0.25, vec3(1.0), k) / PI;
}
