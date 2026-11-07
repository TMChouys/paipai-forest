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
## 文字用的顏色（在紙色上對比度 ≥ 4.5:1）；上面那組只用在底色、邊框。
const TEXT_RED := Color("b8473f")
const TEXT_GREEN := Color("3d7a3d")
const TEXT_WARN := Color("8f5f12")
const TEXT_INFO := Color("3a75b0")
const TEXT_MUTED := Color("7a6a5a")
const ACCENT_LINE := Color("c8693a")
const MONO_FONTS := ["Cascadia Mono", "Consolas", "Noto Sans Mono CJK TC", "MS Gothic"]
const CJK_FONTS := ["Microsoft JhengHei UI", "Microsoft JhengHei", "Noto Sans TC", "Noto Sans CJK TC", "PingFang TC", "sans-serif"]

static var _theme: Theme
static var _mono: Font
static var _bold: Font


static func font() -> Font:
	# 網頁版沒有系統字型：用內附的 Noto Sans TC（可變字型，預設是最細的 100，所以要指定 400）
	if ResourceLoader.exists("res://fonts/body.tres"):
		return load("res://fonts/body.tres")
	var f := SystemFont.new()
	f.font_names = PackedStringArray(CJK_FONTS)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


static func font_bold() -> Font:
	if _bold == null:
		if ResourceLoader.exists("res://fonts/bold.tres"):
			_bold = load("res://fonts/bold.tres")
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(CJK_FONTS)
			f.font_weight = 700
			_bold = f
	return _bold


static func mono() -> Font:
	if _mono == null:
		if ResourceLoader.exists("res://fonts/mono.tres"):
			_mono = load("res://fonts/mono.tres")
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
	t.set_font("bold_font", "RichTextLabel", font_bold())
	t.set_font("mono_font", "RichTextLabel", mono())
	# 輸入框（input() 回答、存檔名稱…）：紙色底＋墨色框，聚焦時加粗橘框
	var le := panel_style(Color("fffdf6"), 10, INK, 2)
	le.shadow_size = 0
	var le_focus := le.duplicate()
	le_focus.border_color = ACCENT_LINE
	le_focus.set_border_width_all(3)
	le_focus.draw_center = false
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	var le_ro := le.duplicate()
	le_ro.bg_color = Color("f6efe2")
	t.set_stylebox("read_only", "LineEdit", le_ro)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("font_selected_color", "LineEdit", INK)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := panel_style(Color("ffe2b8"), 12, INK, 2)
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		s.shadow_size = 2
		match state:
			"hover": s.bg_color = Color("ffd59a")
			"pressed":
				s.bg_color = Color("f6b26b")
				s.shadow_size = 0
				s.content_margin_top = 7
				s.content_margin_bottom = 3
			"disabled": s.bg_color = Color("eadfce")
			"focus":
				s.draw_center = false
				s.border_color = ACCENT
		t.set_stylebox(state, "Button", s)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.4))
	# 主要按鈕（每個畫面只有一個）：暖橘底、粗框、陰影較深；按下時往下沉
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := panel_style(Color("f4a261"), 12, INK, 3)
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 3)
		match state:
			"hover": s.bg_color = Color("f7b37a")
			"pressed":
				s.bg_color = Color("e98a5a")
				s.shadow_size = 1
				s.shadow_offset = Vector2(0, 1)
				s.content_margin_top = 8
				s.content_margin_bottom = 4
			"disabled":
				s.bg_color = Color("eadfce")
				s.border_color = Color(INK, 0.4)
				s.shadow_size = 0
			"focus":
				s.draw_center = false
				s.border_color = ACCENT_LINE
		t.set_stylebox(state, "PrimaryButton", s)
	t.set_type_variation("PrimaryButton", "Button")
	t.set_font("font", "PrimaryButton", font_bold())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "PrimaryButton", INK)
	t.set_color("font_disabled_color", "PrimaryButton", Color(INK, 0.45))
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


## 主要按鈕：接受任務、執行、交件、收下獎勵這類「現在要做的事」。
static func primary(b: Button) -> Button:
	b.theme_type_variation = "PrimaryButton"
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
