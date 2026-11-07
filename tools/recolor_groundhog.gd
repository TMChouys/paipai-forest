extends SceneTree
## 一次性工具：把水獺（Cozy Animals, Otter.glb）的深咖啡毛色調成土撥鼠的焦糖色，
## 輸出 res://models/cozy/groundhog_albedo.png。
## 用法：godot --headless --path . --script res://tools/recolor_groundhog.gd

const SRC := "res://models/cozy/Otter.glb"
const OUT := "res://models/cozy/groundhog_albedo.png"


func _init() -> void:
	var n: Node = load(SRC).instantiate()
	var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
	var mat: BaseMaterial3D = mi.get_active_material(0)
	var img: Image = mat.albedo_texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var v := c.v
			var s := c.s
			if v < 0.1:
				continue  # 眼睛、鼻子的黑色保留
			if s > 0.18 and v < 0.62:
				# 深咖啡毛 → 焦糖色（保留明暗層次，提亮、暖化）
				var nv: float = clamp(0.06 + v * 1.0, 0.0, 0.9)
				var ns: float = clamp(s * 0.72, 0.0, 0.7)
				c = Color.from_hsv(0.083, ns, nv)
			elif s <= 0.45 and v >= 0.62:
				# 奶油色口鼻與肚子：稍微更暖更亮
				c = Color.from_hsv(0.09, clamp(s * 0.8, 0.0, 0.35), clamp(v * 1.04, 0.0, 1.0))
			img.set_pixel(x, y, c)
	_paint_socks(mi, img)
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", OUT, " ", w, "x", h)
	quit()


## 借小熊貓／浣熊的特徵：腳掌塗成深咖啡色「襪子」。
## 找出模型最低處（腳）的三角形，把它們在貼圖上的 UV 範圍塗深。
func _paint_socks(mi: MeshInstance3D, img: Image) -> void:
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var w := img.get_width()
	var h := img.get_height()
	var painted := 0
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		var ymax: float = max(verts[a].y, max(verts[b].y, verts[c].y))
		if ymax > 0.17 or verts[a].z < -0.6:
			continue  # 只要腳（不含尾巴）
		var pa := uvs[a] * Vector2(w, h)
		var pb := uvs[b] * Vector2(w, h)
		var pc := uvs[c] * Vector2(w, h)
		var minx := int(floor(min(pa.x, min(pb.x, pc.x)))) - 1
		var maxx := int(ceil(max(pa.x, max(pb.x, pc.x)))) + 1
		var miny := int(floor(min(pa.y, min(pb.y, pc.y)))) - 1
		var maxy := int(ceil(max(pa.y, max(pb.y, pc.y)))) + 1
		var area := (pb - pa).cross(pc - pa)
		if abs(area) < 0.0001:
			continue
		for py in range(max(miny, 0), min(maxy, h - 1) + 1):
			for px in range(max(minx, 0), min(maxx, w - 1) + 1):
				var p := Vector2(px + 0.5, py + 0.5)
				var w0 := (pb - p).cross(pc - p) / area
				var w1 := (pc - p).cross(pa - p) / area
				var w2 := 1.0 - w0 - w1
				if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
					continue
				var col := img.get_pixel(px, py)
				# 漸層：越低越深
				var y: float = verts[a].y * w0 + verts[b].y * w1 + verts[c].y * w2
				var k: float = clamp(1.0 - y / 0.17, 0.0, 1.0)
				var dark := Color.from_hsv(0.06, 0.45, 0.26 + col.v * 0.15)
				img.set_pixel(px, py, col.lerp(dark, 0.55 + 0.45 * k))
				painted += 1
	print("socks painted px: ", painted)
