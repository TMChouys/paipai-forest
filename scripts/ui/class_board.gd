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
var tabs: HBoxContainer
var scroll: ScrollContainer
## 篩選：all 全部、open 能上的課、locked 還不能上的課、done 已通過的課
var filter := "open"
const FILTERS := [["all", "全部"], ["open", "能上的課"], ["locked", "還不能上的課"], ["done", "已通過的課"]]
var _book: LessonBook
var _done := {}


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
	tabs = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	scroll = sc
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


## 還沒上完的先修課（課名）
func missing_prereqs(book: LessonBook, cid: String, done: Dictionary) -> Array:
	var out: Array = []
	for p in book.concepts[cid].get("prereqs", []) + cfg.get("extra_prereqs", {}).get(cid, []):
		if book.lessons.has(p) and not done.has(p):
			out.append(book.concepts[p].name)
	return out


func open(book: LessonBook, done_list: Array) -> void:
	_book = book
	_done = {}
	for c in done_list:
		_done[c] = true
	# 有能上的課就先看能上的課；全部上完就看已通過的課
	filter = "open" if not _ids("open").is_empty() else ("done" if _ids("locked").is_empty() else "all")
	_render()
	visible = true


func _status(cid: String) -> String:
	if _done.has(cid):
		return "done"
	return "open" if is_open(_book, cid, _done) else "locked"


func _ids(f: String) -> Array:
	var out: Array = []
	for cid in _book.order:
		if _book.lessons.has(cid) and (f == "all" or _status(cid) == f):
			out.append(cid)
	return out


func set_filter(f: String) -> void:
	filter = f
	_render()


func _render() -> void:
	for n in tabs.get_children():
		n.queue_free()
	for fl in FILTERS:
		var id: String = fl[0]
		var b := UIKit.button("%s（%d）" % [fl[1], _ids(id).size()], set_filter.bind(id))
		if id == filter:
			UIKit.primary(b)
		tabs.add_child(b)
	for n in list.get_children():
		n.queue_free()
	var first: Button = null
	var ids := _ids(filter)
	if ids.is_empty():
		var e := UIKit.label({"open": "現在沒有能上的課了：全部都上完囉！", "locked": "沒有還不能上的課了，每一課都開了！",
			"done": "還沒有通過的課：先去上第一堂課吧！"}.get(filter, ""), 15, UIKit.TEXT_MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(e)
	for cid in ids:
		var b := _row(cid)
		if first == null and b != null and _status(cid) == "open":
			first = b
	scroll.scroll_vertical = 0
	if first:
		first.grab_focus.call_deferred()


## 一堂課的一列；回傳「去上課」按鈕（還不能上的課回傳 null）
func _row(cid: String) -> Button:
	var st := _status(cid)
	var c: Dictionary = _book.concepts[cid]
	var les: Dictionary = _book.lessons[cid]
	var a: Dictionary = _book._area(c.area)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.panel_style(Color("f1ece2") if st == "locked" else Color("fffdf6"), 12,
		Color("b8a99a") if st == "locked" else UIKit.INK, 2))
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
	var tl := UIKit.label(("🔒 " if st == "locked" else "") + c.name, 18, UIKit.TEXT_MUTED if st == "locked" else UIKit.INK)
	tl.add_theme_font_override("font", UIKit.font_bold())
	th.add_child(tl)
	var nq: int = 1 + (les.get("quiz_more", []) as Array).size()
	var tasks := 0
	for kt in _book.kmap.get("tasks", []):
		if cid in kt.get("concepts", []) and kt.get("game_task", "") != "":
			tasks += 1
	info.add_child(UIKit.label("老師：%s　地點：%s　小測驗 %d 題" % [teacher_name(cfg, teacher_of(cfg, cid)), cfg.get("place", "圖書館・教室"), nq], 14, Color("8a6a50")))
	var stl := UIKit.label("故事：" + story_of(cfg, cid), 14, Color("6b5a48"))
	stl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(stl)
	if st == "locked":
		var why := UIKit.label("先上完：" + "、".join(missing_prereqs(_book, cid, _done).map(func(n): return "「%s」" % n)), 14, Color("b0603a"))
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(why)
	var prac := ("實作：派派狼的冒險有 %d 個任務會用到" % tasks) if tasks > 0 else "實作：冒險任務準備中"
	info.add_child(UIKit.label("%s　｜　%s" % [les.chapter, prac], 13, UIKit.TEXT_MUTED))
	list.add_child(row)
	if st == "locked":
		var lk := UIKit.label("還不能上", 14, UIKit.TEXT_MUTED)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hh.add_child(lk)
		return null
	var id: String = cid
	var b := UIKit.focusable(UIKit.button("去上課" if st == "open" else "再上一次", func():
		visible = false
		chosen.emit(id)))
	if st == "open":
		UIKit.primary(b)
	else:
		hh.add_child(HomeHUD._done_stamp())
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(b)
	return b


func close() -> void:
	visible = false
	closed.emit()
