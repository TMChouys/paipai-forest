class_name PhotoCard
extends Control
## 爺爺給的舊照片：泛黃的拍立得，畫著大樹底下的地洞樹屋。開場時派派鼠拿出來對照。

const SIZE := Vector2(300, 340)
const PIC := Rect2(Vector2(18, 18), Vector2(264, 236))
## 樹屋的實景快照（開場前用小相機拍下來）；沒有的話就畫一張簡單的圖
var photo: Texture2D = null

const SEPIA := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 sep = vec3(l * 1.08 + 0.05, l * 0.93 + 0.03, l * 0.72 + 0.01);
	vec3 col = mix(c.rgb, sep, 0.72);
	vec2 d = UV - 0.5;
	col *= 1.0 - dot(d, d) * 0.85;
	col = mix(col, vec3(0.93, 0.86, 0.72), 0.14);
	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = SIZE / 2
	if photo != null:
		# 舊照片：泛黃、四周暗一點
		var tr := TextureRect.new()
		tr.texture = photo
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = PIC.position
		tr.size = PIC.size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = SEPIA
		var m := ShaderMaterial.new()
		m.shader = sh
		tr.material = m
		add_child(tr)


func _draw() -> void:
	var ink := Color("5a3d2b")
	# 影子與白邊
	draw_rect(Rect2(Vector2(6, 8), SIZE), Color(0.2, 0.12, 0.05, 0.25))
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("f6efe0"))
	draw_rect(Rect2(Vector2.ZERO, SIZE), ink, false, 2.0)
	var pic := PIC
	if photo != null:
		draw_rect(pic.grow(1), ink, false, 1.0)
		_caption(ink)
		return
	# 沒有快照：畫一張泛黃的簡圖
	draw_rect(pic, Color("e3c99a"))
	var sky := Rect2(pic.position, Vector2(pic.size.x, 150))
	draw_rect(sky, Color("ecd8ae"))
	var ground_y := pic.position.y + 170
	draw_rect(Rect2(Vector2(pic.position.x, ground_y), Vector2(pic.size.x, pic.end.y - ground_y)), Color("b9a571"))
	# 大樹：樹冠＋樹幹
	var cx := pic.get_center().x
	draw_rect(Rect2(Vector2(cx - 34, pic.position.y + 70), Vector2(68, 105)), Color("8a6440"))
	for c in [[Vector2(cx, pic.position.y + 62), 62.0], [Vector2(cx - 62, pic.position.y + 82), 44.0], [Vector2(cx + 64, pic.position.y + 80), 46.0], [Vector2(cx - 20, pic.position.y + 32), 40.0]]:
		draw_circle(c[0], c[1], Color("8f9a62"))
	# 樹根底下的小屋：牆、屋簷、圓門、小窗
	var house := Rect2(Vector2(cx - 58, ground_y - 52), Vector2(116, 56))
	draw_rect(house, Color("d9b88a"))
	draw_rect(house, ink, false, 2.0)
	draw_rect(Rect2(Vector2(house.position.x - 8, house.position.y - 10), Vector2(house.size.x + 16, 12)), Color("7a5236"))
	draw_rect(Rect2(Vector2(cx - 12, ground_y - 34), Vector2(24, 38)), Color("8f5f3c"))
	draw_circle(Vector2(cx, ground_y - 34), 12, Color("8f5f3c"))
	draw_rect(Rect2(Vector2(house.position.x + 14, house.position.y + 14), Vector2(20, 18)), Color("f1e2bf"))
	draw_rect(Rect2(Vector2(house.end.x - 34, house.position.y + 14), Vector2(20, 18)), Color("f1e2bf"))
	# 門前的石頭小路
	for i in range(4):
		draw_circle(Vector2(cx + sin(i * 1.3) * 6, ground_y + 14 + i * 16), 7 - i * 0.6, Color("a8987a"))
	# 照片泛黃的邊角
	draw_rect(pic, Color(0.55, 0.38, 0.15, 0.12))
	draw_rect(pic, ink, false, 1.0)
	_caption(ink)


func _caption(ink: Color) -> void:
	var f := UIKit.font_bold()
	draw_string(f, Vector2(18, SIZE.y - 52), "派派森林・大樹下的樹屋", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 36, 18, ink)
	draw_string(UIKit.font(), Vector2(18, SIZE.y - 24), "—— 爺爺的樹屋", HORIZONTAL_ALIGNMENT_RIGHT, SIZE.x - 36, 16, Color("8a6a50"))
