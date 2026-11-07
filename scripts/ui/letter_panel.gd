class_name LetterPanel
extends Control
## 森林信箱：左邊是收到的信，右邊是信紙。點信箱打開。

signal read_letter(id: String)
signal move_pressed

const PATH := "res://data/letters.json"

var data: Dictionary = {}
var shown: Array = []  # 目前收到的信
var read_ids: Array = []
var current := ""

var list_box: VBoxContainer
var title_lbl: Label
var from_lbl: Label
var body: RichTextLabel
var empty_lbl: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	visible = false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			data = d
	_build()


## 依照完成的任務，回傳已經收到的信（新的在前面）
static func received(d: Dictionary, stars: Dictionary) -> Array:
	# 後來收到的信放最上面（越晚的越前面），一開始就有的信照檔案順序排在後面
	var first: Array = []
	var later: Array = []
	for l in d.get("letters", []):
		var after: String = l.get("after", "")
		if after == "":
			first.append(l)
		elif stars.has(after):
			later.append(l)
	later.reverse()
	return later + first


static func unread_count(d: Dictionary, stars: Dictionary, read: Array) -> int:
	var n := 0
	for l in received(d, stars):
		if not read.has(l.id):
			n += 1
	return n


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.2, 0.12, 0.05, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)
	var box := PanelContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -440
	box.offset_right = 440
	box.offset_top = -290
	box.offset_bottom = 290
	var st := UIKit.panel_style(Color("5aa8d9"), 22, UIKit.INK, 3)  # 信箱的藍色
	st.set_content_margin_all(12)
	box.add_theme_stylebox_override("panel", st)
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label("森林信箱", 22, Color("fff8ec"))
	t.add_theme_font_override("font", UIKit.font_bold())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var mv := UIKit.focusable(UIKit.tertiary(UIKit.button("搬動信箱", func():
		close()
		move_pressed.emit(), "把信箱拿起來，換個位置擺")))
	head.add_child(mv)
	var x := UIKit.focusable(UIKit.button("×", close, "關閉（Esc）"))
	x.custom_minimum_size = Vector2(36, 36)
	x.add_theme_font_size_override("font_size", 20)
	head.add_child(x)

	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)

	var left := PanelContainer.new()
	left.custom_minimum_size.x = 260
	var lst := UIKit.panel_style(Color("fff8ec"), 14, UIKit.INK, 2)
	lst.shadow_size = 0
	left.add_theme_stylebox_override("panel", lst)
	h.add_child(left)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	sc.add_child(list_box)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pst := UIKit.panel_style(Color("fffdf6"), 6, Color("c9b08a"), 1)  # 信紙
	pst.shadow_size = 0
	pst.content_margin_left = 26
	pst.content_margin_right = 22
	pst.content_margin_top = 18
	pst.content_margin_bottom = 14
	right.add_theme_stylebox_override("panel", pst)
	h.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 4)
	right.add_child(rv)
	title_lbl = UIKit.label("", 20)
	title_lbl.add_theme_font_override("font", UIKit.font_bold())
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(title_lbl)
	from_lbl = UIKit.label("", 14, UIKit.TEXT_MUTED)
	rv.add_child(from_lbl)
	var line := ColorRect.new()
	line.color = Color("e8d6b8")
	line.custom_minimum_size.y = 2
	rv.add_child(line)
	body = RichTextLabel.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.bbcode_enabled = true
	body.scroll_active = true
	body.selection_enabled = false
	body.add_theme_color_override("default_color", UIKit.INK)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_constant_override("line_separation", 6)
	body.add_theme_font_override("mono_font", UIKit.mono())
	rv.add_child(body)
	empty_lbl = UIKit.label("信箱裡還沒有信。", 16, UIKit.TEXT_MUTED)
	rv.add_child(empty_lbl)


func open(stars: Dictionary, read: Array) -> void:
	read_ids = read
	shown = received(data, stars)
	current = ""
	# 先打開最新的一封未讀信，沒有就打開最新的一封
	for l in shown:
		if not read_ids.has(l.id):
			current = l.id
			break
	if current == "" and not shown.is_empty():
		current = shown[0].id
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _sender(l: Dictionary) -> String:
	return data.get("senders", {}).get(l.get("from", ""), l.get("from", ""))


func _refresh() -> void:
	for c in list_box.get_children():
		c.queue_free()
	for l in shown:
		var unread: bool = not read_ids.has(l.id) and l.id != current
		var b := UIKit.focusable(UIKit.button("", _select.bind(l.id)))
		b.text = ("● " if unread else "") + _sender(l) + "\n" + l.title
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if l.id == current:
			UIKit.primary(b)
		elif unread:
			b.add_theme_color_override("font_color", UIKit.TEXT_RED)
		list_box.add_child(b)
	var l: Dictionary = _letter(current)
	empty_lbl.visible = l.is_empty()
	title_lbl.visible = not l.is_empty()
	from_lbl.visible = not l.is_empty()
	body.visible = not l.is_empty()
	if l.is_empty():
		return
	title_lbl.text = l.title
	from_lbl.text = "寄信人：" + _sender(l)
	body.text = _format(l.body)
	body.scroll_to_line(0)
	if not read_ids.has(l.id):
		read_ids.append(l.id)
		read_letter.emit(l.id)


## 信裡的 print(...) 這種 Python 句子用等寬字
func _format(s: String) -> String:
	var out: Array = []
	for line in UIKit.esc(s).split("\n"):
		if line.begins_with("print("):
			out.append("[code][color=#3a75b0]" + line + "[/color][/code]")
		else:
			out.append(line)
	return "\n".join(out)


func _letter(id: String) -> Dictionary:
	for l in shown:
		if l.id == id:
			return l
	return {}


func _select(id: String) -> void:
	current = id
	_refresh()
