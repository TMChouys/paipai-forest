class_name ClassBoard
extends Control
## 派派兔的上課表：「準備好一起去上課了嗎？」先選要上什麼課（和派派狼的冒險任務板一樣）。
## 每一堂課寫老師是誰、用什麼故事講、地點（圖書館・教室）、小測驗幾題、對應的實作任務。
## 老師是先安排好的：講這個知識點用的是誰的故事，就由誰來上課（classes.json）。
## 每個概念都有兩種鑑定：認知＝上課的選擇題；實作＝派派狼的冒險任務。

signal chosen(concept_id: String)
signal closed

const PATH := "res://data/curriculum/classes.json"

var cfg: Dictionary = {}
var list: VBoxContainer
var panel: PanelContainer


static func load_cfg() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	visible = false
	cfg = load_cfg()
	var dim := ColorRect.new()
	dim.color = Color(0.2, 0.12, 0.05, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -300
	panel.offset_bottom = 300
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fff8ec"), 20, UIKit.INK, 3))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var pad := Control.new()
	pad.custom_minimum_size.x = 36
	h.add_child(pad)
	var t := UIKit.label("派派兔：準備好一起去上課了嗎？", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var x := UIKit.button("×", close, "關閉（Esc）")
	x.custom_minimum_size = Vector2(36, 36)
	h.add_child(x)
	var sub := UIKit.label("上課在圖書館的教室。每一課用誰的故事講，就由誰來當老師。上課考選擇題（認知），派派狼的冒險考實作。", 14, UIKit.TEXT_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)


## 這一課的老師（id）和故事
static func teacher_of(c: Dictionary, cid: String) -> String:
	return c.get("classes", {}).get(cid, {}).get("teacher", "turtle")


static func story_of(c: Dictionary, cid: String) -> String:
	return c.get("classes", {}).get(cid, {}).get("story", "")


static func teacher_name(c: Dictionary, who: String) -> String:
	return c.get("teacher_names", {}).get(who, "慢慢館長")


## 這一課能不能上：先修的課都上完（答對全部小測驗）了
func is_open(book: LessonBook, cid: String, done: Dictionary) -> bool:
	var pre: Array = book.concepts[cid].get("prereqs", []) + cfg.get("extra_prereqs", {}).get(cid, [])
	for p in pre:
		if book.lessons.has(p) and not done.has(p):
			return false
	return true


func open(book: LessonBook, done_list: Array) -> void:
	var done := {}
	for c in done_list:
		done[c] = true
	for n in list.get_children():
		n.queue_free()
	var kmap: Dictionary = book.kmap
	var first: Button = null
	var open_ids: Array = []
	var done_ids: Array = []
	var locked := 0
	for cid in book.order:
		if not book.lessons.has(cid):
			continue
		if done.has(cid):
			done_ids.append(cid)
		elif is_open(book, cid, done):
			open_ids.append(cid)
		else:
			locked += 1
	if not open_ids.is_empty():
		list.add_child(UIKit.label("現在可以上的課", 16, UIKit.TEXT_INFO))
	for cid in open_ids + done_ids:
		if cid == (done_ids[0] if not done_ids.is_empty() else ""):
			list.add_child(UIKit.label("上過的課（可以再上一次）", 16, UIKit.TEXT_GREEN))
		var c: Dictionary = book.concepts[cid]
		var les: Dictionary = book.lessons[cid]
		var a: Dictionary = book._area(c.area)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fffdf6"), 12, UIKit.INK, 2))
		var hh := HBoxContainer.new()
		hh.add_theme_constant_override("separation", 10)
		row.add_child(hh)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(info)
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 8)
		info.add_child(th)
		th.add_child(QuestBook._tag("%s %s" % [c.area, a.get("name", "")], Color(a.get("color", "#cfe3f5")).lightened(0.3)))
		var tl := UIKit.label(c.name, 18)
		tl.add_theme_font_override("font", UIKit.font_bold())
		th.add_child(tl)
		var nq: int = 1 + (les.get("quiz_more", []) as Array).size()
		var tasks := 0
		for kt in kmap.get("tasks", []):
			if cid in kt.get("concepts", []) and kt.get("game_task", "") != "":
				tasks += 1
		info.add_child(UIKit.label("老師：%s　地點：%s　小測驗 %d 題" % [teacher_name(cfg, teacher_of(cfg, cid)), cfg.get("place", "圖書館・教室"), nq], 14, Color("8a6a50")))
		var stl := UIKit.label("故事：" + story_of(cfg, cid), 14, Color("6b5a48"))
		stl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(stl)
		var prac := ("實作：派派狼的冒險有 %d 個任務會用到" % tasks) if tasks > 0 else "實作：冒險任務準備中"
		info.add_child(UIKit.label("%s　｜　%s" % [les.chapter, prac], 13, UIKit.TEXT_MUTED))
		var id: String = cid
		var b := UIKit.focusable(UIKit.button("去上課" if not done.has(cid) else "再上一次", func():
			visible = false
			chosen.emit(id)))
		if not done.has(cid):
			UIKit.primary(b)
			if first == null:
				first = b
		else:
			hh.add_child(HomeHUD._done_stamp())
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hh.add_child(b)
		list.add_child(row)
	if locked > 0:
		var l := UIKit.label("還有 %d 堂課還沒開：先上完前面的課，新的課就會開。" % locked, 14, UIKit.TEXT_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(l)
	visible = true
	if first:
		first.grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed.emit()
