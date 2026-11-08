extends SceneTree
## 派派兔重新上色：膚色／橘桃色的毛改成粉紅色（遊戲裡是暖色光，桃色看起來會變奶油黃）。
## 只動「橘紅色調、有一點彩度、夠亮」的地方；奶油色肚子、綠衣服、棕色尾巴、眼睛不動，保留原本明暗。
## 用法：godot --headless --path . --script res://tools/recolor_rabbit.gd
## 原始貼圖備份在 tools/orig/，每次都從原始貼圖重畫。

const TEX := "res://models/rabbit/rabbit_rigged_Image_0.jpg"
const ORIG := "res://tools/orig/rabbit_rigged_Image_0.orig.jpg"  # tools/orig 有 .gdignore，不會打包進遊戲
const PINK_H := 0.955  # 粉紅（約 344°）


func _init() -> void:
	var src := ProjectSettings.globalize_path(ORIG)
	if not FileAccess.file_exists(ORIG):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(TEX), src)
	var img := Image.load_from_file(src)
	img.convert(Image.FORMAT_RGB8)
	var out := img.duplicate() as Image
	var sz := img.get_size()
	var n := 0
	for y in sz.y:
		for x in sz.x:
			var c := img.get_pixel(x, y)
			var h := c.h
			if h > 0.5:
				h -= 1.0  # 紅色那一端接起來：-0.05..0
			# 橘桃色：色相 -10°..30°、彩度 0.18 以上、亮度 0.45 以上
			var w := smoothstep(-0.05, -0.02, h) * (1.0 - smoothstep(0.075, 0.095, h))
			w *= smoothstep(0.16, 0.26, c.s) * smoothstep(0.42, 0.52, c.v)
			if w <= 0.0:
				continue
			var s := clampf(0.08 + 0.62 * c.s, 0.18, 0.42)  # 柔和的粉紅，不要太螢光
			var col := Color.from_hsv(PINK_H, s, minf(c.v * 1.02, 1.0))
			out.set_pixel(x, y, c.lerp(col, w))
			n += 1
	print("pink px ", n)
	out.save_jpg(ProjectSettings.globalize_path(TEX), 0.95)
	quit()
