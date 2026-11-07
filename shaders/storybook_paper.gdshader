shader_type canvas_item;
// 繪本故事書濾鏡：蓋在整個畫面上。
// 1. 調色：降一點飽和、把最亮的地方壓成紙的米白、暗部帶暖棕（像印刷油墨）
// 2. 紙張：細顆粒＋長纖維，讓畫面像印在粗紙上
// 3. 書頁邊緣：四周淡淡的暖色暗角

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float saturation = 0.9;
uniform vec3 paper = vec3(0.97, 0.945, 0.89);   // 最亮的地方 = 紙色
uniform vec3 ink = vec3(0.2, 0.14, 0.1);      // 最暗的地方 = 暖棕油墨
uniform float grain = 0.022;
uniform float fiber = 0.008;
uniform float vignette = 0.1;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 src = c;
	// 調色
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = mix(ink, paper, c);  // 黑 → 油墨、白 → 紙
	// 紙張顆粒（以像素為單位，畫面大小改變時顆粒大小不變）
	vec2 px = FRAGCOORD.xy;
	float g = vnoise(px * 1.3);  // 只留很細的紙紋，不要大片的斑點（看起來會像螢幕髒了）
	float fb = vnoise(vec2(px.x * 0.035, px.y * 0.6)) * vnoise(vec2(px.x * 0.6, px.y * 0.04));  // 橫、直的纖維
	c *= 1.0 - grain * (g - 0.5) * 2.0 - fiber * fb;
	// 暗角
	vec2 uv = SCREEN_UV - 0.5;
	float v = smoothstep(0.5, 0.95, length(uv * vec2(1.0, 0.85)));
	c *= 1.0 - vignette * v;
	c = mix(c, c * vec3(1.0, 0.96, 0.9), v * 0.4);
	COLOR = vec4(mix(src, c, strength), 1.0);
}
