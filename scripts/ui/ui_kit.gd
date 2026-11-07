class_name UIKit
extends RefCounted
## 繪本風 UI 的共用樣式與小工具。

const PAPER := Color("fff8ec")
const PAPER_DARK := Color("f3e3c8")
const INK := Color("5a3d2b")
const ACCENT := Color("e98a5a")
const GREEN := Color("6fb36f")
const RED := Color("d9605a")
const BLUE := Color("5a9bd9")
const MONO_FONTS := ["Cascadia Mono", "Consolas", "Noto Sans Mono CJK TC", "MS Gothic"]
const CJK_FONTS := ["Microsoft JhengHei UI", "Microsoft JhengHei", "Noto Sans TC", "Noto Sans CJK TC", "PingFang TC", "sans-serif"]

static var _theme: Theme
static var _mono: Font


static func font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(CJK_FONTS)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	# 網頁版沒有系統字型：放一個 res://fonts/NotoSansTC.ttf 就會優先使用
	if ResourceLoader.exists("res://fonts/NotoSansTC.ttf"):
		var ff: FontFile = load("res://fonts/NotoSansTC.ttf")
		return ff
	return f


static func mono() -> Font:
	if _mono == null:
		if ResourceLoader.exists("res://fonts/NotoSansMonoTC.ttf"):
			_mono = load("res://fonts/NotoSansMonoTC.ttf")
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(MONO_FONTS)
			f.fallbacks = [font()]
			_mono = f
	return _mono


static func panel_style(bg: Color = PAPER, radius: int = 14, border: Color = INK, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0.35, 0.22, 0.12, 0.18)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := panel_style(Color("ffe2b8"), 12, INK, 2)
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		s.shadow_size = 2
		match state:
			"hover": s.bg_color = Color("ffd59a")
			"pressed": s.bg_color = Color("f6b26b")
			"disabled": s.bg_color = Color("eadfce")
			"focus":
				s.draw_center = false
				s.border_color = ACCENT
		t.set_stylebox(state, "Button", s)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.4))
	var tt := panel_style(Color("fffdf6"), 8, INK, 1)
	t.set_stylebox("panel", "TooltipPanel", tt)
	t.set_color("font_color", "TooltipLabel", INK)
	_theme = t
	return t


static func button(text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


static func label(text: String, size: int = 17, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func esc(s: String) -> String:
	return s.replace("[", "[lb]")
