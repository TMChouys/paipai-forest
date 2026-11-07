class_name QuestBook
extends Control
## 派派兔的任務書：用知識地圖列出所有任務（點派派兔、或上方的「任務書」打開）。
## 左頁：知識範圍（章節）目錄與進度；右頁上：這一章的概念地圖（先備關係連線）；右頁下：選到的概念有哪些任務。

signal task_chosen(task_id: String)
signal closed

const MAP_PATH := "res://data/curriculum/knowledge_map.json"
const CARD := Vector2(168, 34)
const COL_GAP := 46
const ROW_GAP := 10

var data: Dictionary = {}
var concepts: Dictionary = {}  # id -> concept
var learned: Dictionary = {}  # concept id -> true
var done_tasks: Dictionary = {}  # 知識地圖任務 id -> stars
var playable_unlocked: Callable  # game_task id -> bool（沿用派派狼任務板的解鎖規則）
var area_id := "A"
var concept_id := ""

var index_box: VBoxContainer
var area_title: Label
var area_sub: Label
var map_canvas: Control
var map_scroll: ScrollContainer
var detail: VBoxContainer
var cards: Dictionary = {}  # concept id -> Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	visible = false
	data = load_map()
	for c in data.get("concepts", []):
		concepts[c.id] = c
	_build()


static func load_map() -> Dictionary:
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.2, 0.12, 0.05, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var book := PanelContainer.new()
	book.anchor_left = 0.5
	book.anchor_right = 0.5
	book.anchor_top = 0.5
	book.anchor_bottom = 0.5
	book.offset_left = -600
	book.offset_right = 600
	book.offset_top = -335
	book.offset_bottom = 335
	var bst := UIKit.panel_style(Color("8a5a3b"), 22, UIKit.INK, 3)  # 書皮
	bst.set_content_margin_all(12)
	book.add_theme_stylebox_override("panel", bst)
	add_child(book)
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 4)
	book.add_child(pages)

	# ---- 左頁：目錄 ----
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 300
	var lst := UIKit.panel_style(Color("fff8ec"), 14, UIKit.INK, 2)
	lst.shadow_size = 0
	left.add_theme_stylebox_override("panel", lst)
	pages.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	var t := UIKit.label("派派兔的任務書", 24)
	t.add_theme_font_override("font", UIKit.font_bold())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(t)
	var sub := UIKit.label("先學會前面的知識，才能挑戰後面的任務", 13, Color("8a6a50"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	index_box = VBoxContainer.new()
	index_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index_box.add_theme_constant_override("separation", 6)
	sc.add_child(index_box)
	lv.add_child(_legend())

	# ---- 右頁：知識地圖＋任務 ----
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", lst)
	pages.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	var rh := HBoxContainer.new()
	rv.add_child(rh)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	rh.add_child(tv)
	area_title = UIKit.label("", 20)
	area_title.add_theme_font_override("font", UIKit.font_bold())
	tv.add_child(area_title)
	area_sub = UIKit.label("", 13, Color("8a6a50"))
	tv.add_child(area_sub)
	var x := UIKit.focusable(UIKit.button("×", close, "關閉（Esc）"))
	x.custom_minimum_size = Vector2(36, 36)
	x.add_theme_font_size_override("font_size", 20)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rh.add_child(x)

	map_scroll = ScrollContainer.new()
	map_scroll.custom_minimum_size.y = 250
	var mst := UIKit.panel_style(Color("fffdf6"), 10, Color("d8c3a5"), 1)
	mst.shadow_size = 0
	map_scroll.add_theme_stylebox_override("panel", mst)
	rv.add_child(map_scroll)
	map_canvas = Control.new()
	map_canvas.draw.connect(_draw_links)
	map_scroll.add_child(map_canvas)

	var ds := ScrollContainer.new()
	ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(ds)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	ds.add_child(detail)


func _legend() -> Control:
	var l := UIKit.label("✓ 學會了　● 可以學　○ 要先學前面的", 13, Color("6b5242"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## stars：遊戲任務 id -> 星數；unlocked：遊戲任務能不能開始（沿用任務板規則）
func open(stars: Dictionary, unlocked: Callable) -> void:
	playable_unlocked = unlocked
	learned.clear()
	done_tasks.clear()
	for t in data.get("tasks", []):
		var g = t.get("game_task")
		if g and int(stars.get(g, 0)) > 0:
			done_tasks[t.id] = int(stars[g])
			for c in t.concepts:
				learned[c] = true
	_fill_index()
	_show_area(area_id)
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func is_available(cid: String) -> bool:
	for p in concepts[cid].prereqs:
		if not learned.has(p):
			return false
	return true


func _area_concepts(aid: String) -> Array:
	return data.get("concepts", []).filter(func(c): return c.area == aid)


func _fill_index() -> void:
	for c in index_box.get_children():
		c.queue_free()
	for a in data.get("areas", []):
		var cs := _area_concepts(a.id)
		var n_learned := cs.filter(func(c): return learned.has(c.id)).size()
		var b := UIKit.focusable(UIKit.button("%s　%s" % [a.id, a.name], _show_area.bind(a.id), a.summary))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var st := UIKit.panel_style(Color(a.color).lightened(0.55), 10, UIKit.INK, 3 if a.id == area_id else 1)
		st.shadow_size = 0
		b.add_theme_stylebox_override("normal", st)
		var row := HBoxContainer.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		var p := UIKit.label("%d/%d" % [n_learned, cs.size()], 14, Color("6b5242"))
		p.custom_minimum_size.x = 44
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(p)
		index_box.add_child(row)


func _show_area(aid: String) -> void:
	area_id = aid
	var area: Dictionary = {}
	for a in data.get("areas", []):
		if a.id == aid:
			area = a
	area_title.text = "%s　%s" % [aid, area.get("name", "")]
	area_sub.text = "%s　教材：%s" % [area.get("summary", ""), area.get("textbook", "")]
	_fill_index()
	_layout_map(aid, Color(area.get("color", "#ffcf6b")))
	var cs := _area_concepts(aid)
	map_scroll.visible = not cs.is_empty()
	var first := ""
	for c in cs:
		if first == "" and not learned.has(c.id):
			first = c.id
	if cs.is_empty():
		# 沒有新概念的章節（演算法應用）：直接列出這一章的複合任務
		concept_id = ""
		for n in detail.get_children():
			n.queue_free()
		var hl := UIKit.label("這一章不教新概念，而是把學過的組合起來解決問題。", 15)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(hl)
		var ts: Array = data.get("tasks", []).filter(func(t): return t.area == aid)
		ts.sort_custom(func(a, b): return int(a.difficulty) < int(b.difficulty))
		for t in ts:
			detail.add_child(_task_row(t))
		return
	_show_concept(first if first != "" else cs[0].id)


## 同一章的概念依「在這一章裡的先備深度」排成一欄一欄
func _layout_map(aid: String, color: Color) -> void:
	for c in map_canvas.get_children():
		c.queue_free()
	cards.clear()
	var cs := _area_concepts(aid)
	var ids := cs.map(func(c): return c.id)
	var depth := {}
	for _i in range(cs.size()):
		for c in cs:
			var d := 0
			for p in c.prereqs:
				if p in ids:
					d = maxi(d, int(depth.get(p, 0)) + 1)
			depth[c.id] = d
	var cols := {}
	for c in cs:
		var d: int = depth[c.id]
		if not cols.has(d):
			cols[d] = []
		cols[d].append(c)
	var max_rows := 0
	for d in cols:
		max_rows = maxi(max_rows, cols[d].size())
		for i in range(cols[d].size()):
			var c: Dictionary = cols[d][i]
			var b := _card(c, color)
			b.position = Vector2(12 + d * (CARD.x + COL_GAP), 12 + i * (CARD.y + ROW_GAP))
			map_canvas.add_child(b)
			cards[c.id] = b
	map_canvas.custom_minimum_size = Vector2(24 + cols.size() * (CARD.x + COL_GAP) - COL_GAP, 24 + max_rows * (CARD.y + ROW_GAP))
	map_canvas.queue_redraw()


func _card(c: Dictionary, color: Color) -> Button:
	var mark := "✓ " if learned.has(c.id) else ("● " if is_available(c.id) else "○ ")
	var b := UIKit.focusable(UIKit.button(mark + c.name, _show_concept.bind(c.id), c.summary))
	b.size = CARD
	b.custom_minimum_size = CARD
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 14)
	var bg := Color("e6f2dc") if learned.has(c.id) else (color.lightened(0.6) if is_available(c.id) else Color("f1ebe2"))
	var st := UIKit.panel_style(bg, 10, UIKit.INK if is_available(c.id) or learned.has(c.id) else Color("b8a58f"), 3 if c.id == concept_id else 1)
	st.shadow_size = 0
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	st.content_margin_left = 8
	st.content_margin_right = 8
	b.add_theme_stylebox_override("normal", st)
	if not (is_available(c.id) or learned.has(c.id)):
		b.add_theme_color_override("font_color", Color("8a7a6a"))
	return b


func _draw_links() -> void:
	for cid in cards:
		var to: Button = cards[cid]
		for p in concepts[cid].prereqs:
			if not cards.has(p):
				continue
			var from: Button = cards[p]
			var a := from.position + Vector2(CARD.x, CARD.y / 2)
			var b := to.position + Vector2(0, CARD.y / 2)
			var col := Color("6fb36f") if learned.has(p) else Color("c9b8a0")
			var mid := (a.x + b.x) / 2
			map_canvas.draw_polyline(PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b]), col, 2.0, true)
			map_canvas.draw_colored_polygon(PackedVector2Array([b, b + Vector2(-7, -4), b + Vector2(-7, 4)]), col)


func _show_concept(cid: String) -> void:
	concept_id = cid
	for k in cards:
		var c: Dictionary = concepts[k]
		var st: StyleBoxFlat = cards[k].get_theme_stylebox("normal").duplicate()
		st.set_border_width_all(3 if k == cid else 1)
		cards[k].add_theme_stylebox_override("normal", st)
	for n in detail.get_children():
		n.queue_free()
	if cid == "":
		return
	var c: Dictionary = concepts[cid]
	var h := UIKit.label(c.name, 18)
	h.add_theme_font_override("font", UIKit.font_bold())
	detail.add_child(h)
	var s := UIKit.label(c.summary, 15)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(s)
	if not c.prereqs.is_empty():
		var names := []
		for p in c.prereqs:
			names.append(("✓" if learned.has(p) else "○") + concepts[p].name)
		var pl := UIKit.label("要先學會：" + "、".join(names), 14, UIKit.TEXT_MUTED if is_available(cid) else UIKit.TEXT_RED)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(pl)
	# 這個概念的任務：單一概念在前，複合在後；同類依難度
	var ts: Array = data.get("tasks", []).filter(func(t): return cid in t.concepts)
	ts.sort_custom(func(a, b):
		if a.compound != b.compound:
			return not a.compound
		return int(a.difficulty) < int(b.difficulty))
	for t in ts:
		detail.add_child(_task_row(t))


func _task_row(t: Dictionary) -> Control:
	var row := PanelContainer.new()
	var st := UIKit.panel_style(Color("fffdf6"), 10, UIKit.INK, 1)
	st.shadow_size = 0
	row.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	info.add_child(top)
	top.add_child(_tag("複合知識" if t.compound else "單一概念", Color("f4a8a0") if t.compound else Color("cfe3f5")))
	var title := UIKit.label("%s　%s" % [t.title, "★".repeat(int(t.difficulty)) + "☆".repeat(5 - int(t.difficulty))], 16)
	top.add_child(title)
	var place: String = data.get("places", {}).get(t.place, t.place)
	var npc: String = data.get("npcs", {}).get(t.npc, t.npc)
	var line2 := "%s・%s委託" % [place, npc]
	if t.compound:
		var names := []
		for c in t.concepts:
			names.append(concepts[c].name if concepts.has(c) else c)
		line2 += "　｜　組合：" + " ＋ ".join(names)
	info.add_child(UIKit.label(line2, 13, Color("8a6a50")))
	var story := UIKit.label(t.story, 14)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(story)
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right)
	if done_tasks.has(t.id):
		right.add_child(UIKit.label("★".repeat(done_tasks[t.id]), 16, UIKit.TEXT_WARN))
	var g = t.get("game_task")
	if g:
		var ok: bool = playable_unlocked.call(g) if playable_unlocked.is_valid() else true
		var b := UIKit.focusable(UIKit.button("開始" if not done_tasks.has(t.id) else "再挑戰", func(): task_chosen.emit(g)))
		if ok and not done_tasks.has(t.id):
			UIKit.primary(b)
		b.disabled = not ok
		if not ok:
			b.text = "未解鎖"
			b.tooltip_text = "先完成派派狼任務板上前面的任務"
		right.add_child(b)
	else:
		var l := UIKit.label("準備中", 14, UIKit.TEXT_MUTED)
		l.tooltip_text = data.get("status_names", {}).get(t.status, t.status)
		right.add_child(l)
	return row


static func _tag(text: String, bg: Color) -> Label:
	var l := UIKit.label(text, 13, UIKit.INK)
	l.add_theme_font_override("font", UIKit.font_bold())
	var st := UIKit.panel_style(bg, 8, UIKit.INK, 1)
	st.shadow_size = 0
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	l.add_theme_stylebox_override("normal", st)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l
