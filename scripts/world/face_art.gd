class_name FaceArt
extends RefCounted
## 派派鼠的 2D 臉（SVG 畫的，執行時點陣化成貼圖）。
## 座標對應 tools/blender/build_gopher.py 的臉貼圖範圍：400x400，1px = 0.001 模型單位，
## x=200 是臉中線，y = (0.72 - z) * 1000。3D 鼻子在 (200, 238) 附近，嘴巴畫在它下方。

const LINE := "#3b2414"
const EXPRESSIONS := ["normal", "blink", "happy", "confused", "talk"]
const EYE_L := Vector2(122, 186)
const EYE_R := Vector2(278, 186)

static var _cache: Dictionary = {}


static func texture(expr: String) -> Texture2D:
	if _cache.has(expr):
		return _cache[expr]
	var img := Image.new()
	img.load_svg_from_string(svg(expr), 2.56)  # 1024x1024
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[expr] = tex
	return tex


static func svg(expr: String) -> String:
	var s := "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400' viewBox='0 0 400 400'>"
	s += "<defs>"
	s += "<radialGradient id='iris' cx='0.5' cy='0.62' r='0.62'><stop offset='0' stop-color='#a0703f'/><stop offset='0.45' stop-color='#5e3619'/><stop offset='1' stop-color='#2a150a'/></radialGradient>"
	s += "<radialGradient id='blush' cx='0.5' cy='0.5' r='0.5'><stop offset='0' stop-color='#f08f7c' stop-opacity='0.85'/><stop offset='0.6' stop-color='#f3a08d' stop-opacity='0.5'/><stop offset='1' stop-color='#f3a08d' stop-opacity='0'/></radialGradient>"
	s += "</defs>"
	# 腮紅
	for x in [72, 328]:
		s += "<ellipse cx='%d' cy='252' rx='30' ry='17' fill='url(#blush)'/>" % x
	# 眉毛
	for c: Vector2 in [EYE_L, EYE_R]:
		var side := -1.0 if c.x < 200 else 1.0
		if expr == "confused":
			# 擔心：內側上揚
			s += _path("M %f %f Q %f %f %f %f" % [c.x - side * 4, c.y - 50, c.x + side * 8, c.y - 52, c.x + side * 20, c.y - 44], 6.5, "#5a3a20")
		else:
			var lift := 6.0 if expr == "happy" else 0.0
			s += _path("M %f %f Q %f %f %f %f" % [c.x - 17, c.y - 50 - lift, c.x, c.y - 57 - lift, c.x + 17, c.y - 50 - lift], 6.5, "#5a3a20")
	# 眼睛
	for c: Vector2 in [EYE_L, EYE_R]:
		match expr:
			"blink":
				s += _path("M %f %f Q %f %f %f %f" % [c.x - 28, c.y + 2, c.x, c.y + 14, c.x + 28, c.y + 2], 6.0, LINE)
			"happy":
				s += _path("M %f %f Q %f %f %f %f" % [c.x - 26, c.y + 8, c.x, c.y - 22, c.x + 26, c.y + 8], 6.5, LINE)
			_:
				s += _eye(c, expr == "confused")
	# 嘴巴
	s += _mouth(expr)
	if expr == "confused":  # 汗滴
		s += "<path d='M 345 120 Q 335 140 340 150 Q 350 160 358 148 Q 360 138 345 120 Z' fill='#bfe3f5' stroke='%s' stroke-width='2.5'/>" % LINE
	s += "</svg>"
	return s


static func _eye(c: Vector2, small_pupil: bool) -> String:
	var s := ""
	# 奶油白外圈＋深色描邊
	s += "<ellipse cx='%f' cy='%f' rx='39' ry='41' fill='#fff8ea' stroke='%s' stroke-width='3.5'/>" % [c.x, c.y, LINE]
	# 漸層虹膜
	s += "<ellipse cx='%f' cy='%f' rx='32' ry='34' fill='url(#iris)'/>" % [c.x, c.y + 2]
	# 瞳孔
	var pr := 12.0 if small_pupil else 18.0
	s += "<ellipse cx='%f' cy='%f' rx='%f' ry='%f' fill='#170b04'/>" % [c.x, c.y + 3, pr, pr + 1]
	# 兩顆亮點（右上大、左下小）＋一顆小星光
	s += "<circle cx='%f' cy='%f' r='11' fill='#ffffff'/>" % [c.x + 10, c.y - 12]
	s += "<circle cx='%f' cy='%f' r='5' fill='#ffffff'/>" % [c.x - 12, c.y + 14]
	s += "<circle cx='%f' cy='%f' r='2.6' fill='#ffffff' fill-opacity='0.9'/>" % [c.x + 17, c.y + 8]
	return s


static func _mouth(expr: String) -> String:
	var s := ""
	# 人中
	s += _path("M 200 258 L 200 270", 3.5, LINE)
	match expr:
		"confused":
			# 小小的波浪嘴，只露一點牙
			s += "<rect x='191' y='270' width='18' height='10' rx='2' fill='#fffaf0' stroke='%s' stroke-width='2.2'/>" % LINE
			s += _path("M 176 274 Q 184 268 191 272 M 209 272 Q 216 268 224 274", 3.5, LINE)
		"talk", "happy":
			var h := 38.0 if expr == "talk" else 32.0
			s += "<path d='M 178 268 Q 200 264 222 268 Q 222 %f 200 %f Q 178 %f 178 268 Z' fill='#8c3a2e' stroke='%s' stroke-width='3.2'/>" % [268 + h * 0.8, 268 + h, 268 + h * 0.8, LINE]
			s += "<ellipse cx='200' cy='%f' rx='13' ry='8' fill='#ec8f7e'/>" % (268 + h - 9)
			s += _teeth(268)
		_:
			# w 形微笑＋張開的小嘴
			s += "<path d='M 187 272 Q 200 266 213 272 Q 214 296 200 298 Q 186 296 187 272 Z' fill='#8c3a2e' stroke='%s' stroke-width='3'/>" % LINE
			s += "<ellipse cx='200' cy='290' rx='9' ry='6' fill='#ec8f7e'/>"
			s += _teeth(270)
			s += _path("M 170 266 Q 184 282 200 270 Q 216 282 230 266", 3.6, LINE)
	return s


static func _teeth(y: float) -> String:
	var s := ""
	for x in [190.5, 200.5]:
		s += "<rect x='%f' y='%f' width='9.5' height='14' rx='2.2' fill='#fffaf0' stroke='%s' stroke-width='2'/>" % [x, y, LINE]
	return s


static func _path(d: String, w: float, color: String) -> String:
	return "<path d='%s' fill='none' stroke='%s' stroke-width='%f' stroke-linecap='round' stroke-linejoin='round'/>" % [d, color, w]
