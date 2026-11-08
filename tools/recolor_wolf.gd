extends SceneTree
## 派派狼重新上色：全身灰色的毛改成藍色；尾巴藍色、尾巴尖白色（照角色設定圖）。
## 身上的毛：貼圖裡灰灰的（彩度低、不太亮也不太暗）的地方換成藍色，保留明暗；衣服、白毛、眼睛不動。
## 找身體後面、貼圖顏色深的頂點＝尾巴，在 UV 上把那些三角形重畫，保留原本的毛流明暗。
## 用法：godot --headless --path . --script res://tools/recolor_wolf.gd -- [stats]
## 原始貼圖備份在 tools/orig/，每次都從原始貼圖重畫。

const TEX := "res://models/wolf/wolf_rigged_Image_0.jpg"
const ORIG := "res://tools/orig/wolf_rigged_Image_0.orig.jpg"  # tools/orig 有 .gdignore，不會打包進遊戲
const BLUE := Color("5a6f96")   # 藍
const TIP := Color("f4f1ea")    # 尾巴尖的白


func _init() -> void:
	var stats_only := "stats" in OS.get_cmdline_user_args()
	var inst: Node3D = (load("res://models/wolf/wolf_rigged.glb") as PackedScene).instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var src_path := ProjectSettings.globalize_path(ORIG)
	if not FileAccess.file_exists(ORIG):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(TEX), src_path)
	var img := Image.load_from_file(src_path)
	img.convert(Image.FORMAT_RGB8)
	var sz := img.get_size()
	var lum := func(p: Vector2) -> float:
		var q := Vector2i(p * Vector2(sz)).clamp(Vector2i.ZERO, sz - Vector2i.ONE)
		return img.get_pixelv(q).get_luminance()
	# 尾巴頂點
	var sel := PackedByteArray()
	sel.resize(v.size())
	var ymin := 1e9
	var ymax := -1e9
	var zmin := 1e9
	var n := 0
	var lsum := 0.0
	for i in v.size():
		var p := v[i]
		var l: float = lum.call(uv[i])
		if p.z < -0.155 and p.y < 0.38 and l < 0.245:
			sel[i] = 1
			n += 1
			lsum += l
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
			zmin = minf(zmin, p.z)
	var lavg := lsum / maxf(n, 1)
	print("tail verts ", n, " y ", ymin, "..", ymax, " zmin ", zmin, " lum avg ", lavg)
	# 尾巴尖在哪：最後面那一截的平均高度
	var tip_y := 0.0
	var tip_n := 0
	for i in v.size():
		if sel[i] and v[i].z < zmin + 0.03:
			tip_y += v[i].y
			tip_n += 1
	tip_y /= maxf(tip_n, 1)
	print("tip (最後面) 平均高度 ", tip_y)
	if stats_only:
		quit()
		return
	# 沿著尾巴的位置 t：0＝連在身上，1＝尾巴尖。用離「最後面那一點」的距離
	var tip_p := Vector3(0, tip_y, zmin)
	var root_d := 0.0
	for i in v.size():
		if sel[i]:
			root_d = maxf(root_d, v[i].distance_to(tip_p))
	var out := _blue_fur(img)
	var painted := 0
	for f in range(0, idx.size(), 3):
		var a := idx[f]
		var b := idx[f + 1]
		var c := idx[f + 2]
		var k := int(sel[a]) + int(sel[b]) + int(sel[c])
		if k < 2:
			continue
		var ua := uv[a] * Vector2(sz)
		var ub := uv[b] * Vector2(sz)
		var uc := uv[c] * Vector2(sz)
		var lo := ua.min(ub).min(uc).floor() - Vector2.ONE
		var hi := ua.max(ub).max(uc).ceil() + Vector2.ONE
		var den := (ub.y - uc.y) * (ua.x - uc.x) + (uc.x - ub.x) * (ua.y - uc.y)
		if absf(den) < 1e-6:
			continue
		for py in range(int(lo.y), int(hi.y) + 1):
			for px in range(int(lo.x), int(hi.x) + 1):
				if px < 0 or py < 0 or px >= sz.x or py >= sz.y:
					continue
				var q := Vector2(px + 0.5, py + 0.5)
				var w1 := ((ub.y - uc.y) * (q.x - uc.x) + (uc.x - ub.x) * (q.y - uc.y)) / den
				var w2 := ((uc.y - ua.y) * (q.x - uc.x) + (ua.x - uc.x) * (q.y - uc.y)) / den
				var w3 := 1.0 - w1 - w2
				if w1 < -0.08 or w2 < -0.08 or w3 < -0.08:
					continue
				var p3 := v[a] * w1 + v[b] * w2 + v[c] * w3
				var s := float(sel[a]) * w1 + float(sel[b]) * w2 + float(sel[c]) * w3
				# 尾巴往後下垂：下垂的尾端（低的那一截）是白色，往上連到身體是藍色
				var t := clampf((ymax - p3.y) / (ymax - ymin), 0.0, 1.0)
				var white := smoothstep(0.66, 0.8, t)
				var base := BLUE.lerp(TIP, white)
				var orig := img.get_pixel(px, py)
				var shade := clampf(0.6 + 0.4 * orig.get_luminance() / lavg, 0.75, 1.2)  # 保留一點毛流的明暗
				var col := Color(base.r * shade, base.g * shade, base.b * shade)
				out.set_pixel(px, py, orig.lerp(col, clampf(s * 1.5, 0.0, 1.0)))
				painted += 1
	print("painted px ", painted)
	out.save_jpg(ProjectSettings.globalize_path(TEX), 0.95)
	quit()


## 灰毛的權重：彩度低、亮度在中間
static func _fur_w(c: Color) -> float:
	var l := c.get_luminance()
	return (1.0 - smoothstep(0.10, 0.19, c.s)) * smoothstep(0.16, 0.26, l) * (1.0 - smoothstep(0.66, 0.76, l))


static func _blue_fur(img: Image) -> Image:
	var out := img.duplicate() as Image
	var sz := img.get_size()
	var lsum := 0.0
	var wsum := 0.0
	for y in range(0, sz.y, 4):
		for x in range(0, sz.x, 4):
			var c := img.get_pixel(x, y)
			var w := _fur_w(c)
			lsum += c.get_luminance() * w
			wsum += w
	var lref := lsum / maxf(wsum, 1.0)
	print("fur lum avg ", lref)
	var n := 0
	for y in sz.y:
		for x in sz.x:
			var c := img.get_pixel(x, y)
			var w := _fur_w(c)
			if w <= 0.0:
				continue
			var k := clampf(0.55 + 0.45 * c.get_luminance() / lref, 0.6, 1.35)
			var col := Color(BLUE.r * k, BLUE.g * k, BLUE.b * k)
			out.set_pixel(x, y, c.lerp(col, w))
			n += 1
	print("fur px ", n)
	return out
